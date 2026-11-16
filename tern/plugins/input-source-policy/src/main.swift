import Carbon
import Foundation

// Tern input-source policy: the half that touches macOS.
//
// window.luau decides which class the focused Tern pane should type in and
// calls `apply ascii|cjk` only on a focus edge. This binary selects the source,
// waits for TIS to catch up, re-reads it, retries once when the switch did not
// take, and traces every apply to a log.
//
//   ascii -> US Extended, remembering the non-ASCII source it displaced
//   cjk   -> the remembered source, else the first enabled non-ASCII keyboard
//            source, else the fallback id

// MARK: - Configuration

/// Used only when nothing is remembered and no non-ASCII source is enabled.
private let fallbackCJKSourceID = "im.rime.inputmethod.Squirrel.Hans"

/// US Extended. Any other ASCII-capable source is a fallback if it is disabled.
private let asciiSourceID = "com.apple.keylayout.USExtended"

private let home = FileManager.default.homeDirectoryForCurrentUser
private let stateDirectory = home.appendingPathComponent(".local/state/tern-input-source-policy", isDirectory: true)
private let displacedSourceFile = stateDirectory.appendingPathComponent("previous-input-source")
/// Every apply, so a surprising input source can be traced back to the focus
/// edge that produced it (or to the absence of one). Dropped once it exceeds the cap.
private let traceFile = stateDirectory.appendingPathComponent("policy.log")
private let traceMaxBytes = 256 * 1024

// MARK: - Input source primitives

private func property<T>(_ source: TISInputSource, _ key: CFString, as type: T.Type) -> T? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
}

private func sourceID(_ source: TISInputSource) -> String? {
    property(source, kTISPropertyInputSourceID, as: String.self)
}

private func isASCIICapable(_ source: TISInputSource) -> Bool {
    property(source, kTISPropertyInputSourceIsASCIICapable, as: NSNumber.self)?.boolValue == true
}

private func isSelectable(_ source: TISInputSource) -> Bool {
    property(source, kTISPropertyInputSourceIsSelectCapable, as: NSNumber.self)?.boolValue == true
}

private func isKeyboardInput(_ source: TISInputSource) -> Bool {
    property(source, kTISPropertyInputSourceCategory, as: String.self)
        == (kTISCategoryKeyboardInputSource as String)
}

private func currentSource() -> TISInputSource? {
    TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
}

/// Enabled sources only — `TISCreateInputSourceList(nil, false)` excludes installed-but-disabled ones.
private func enabledSources() -> [TISInputSource] {
    guard let unmanaged = TISCreateInputSourceList(nil, false) else { return [] }
    return unmanaged.takeRetainedValue() as NSArray as? [TISInputSource] ?? []
}

@discardableResult
private func selectSource(id: String) -> Bool {
    guard let source = enabledSources().first(where: { sourceID($0) == id }) else { return false }
    return TISSelectInputSource(source) == noErr
}

private enum InputClass: String {
    case ascii
    case cjk
}

// MARK: - Applying a class

private func readTrimmed(_ url: URL) -> String? {
    guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func rememberedDisplacedSourceID() -> String? {
    readTrimmed(displacedSourceFile)
}

private func rememberDisplacedSource(_ id: String) {
    try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    try? id.write(to: displacedSourceFile, atomically: true, encoding: .utf8)
}

private func forgetDisplacedSource() {
    try? FileManager.default.removeItem(at: displacedSourceFile)
}

/// Selects US Extended, remembering the non-ASCII source it displaced.
///
/// Always selects, even when the live source already reads ASCII: TIS reports
/// the *previous* source for a few hundred ms after a switch, so an "already
/// ASCII, skip" shortcut can no-op on a stale read and leave the pane on Rime.
private func applyASCII() {
    if let current = currentSource(), !isASCIICapable(current), let id = sourceID(current) {
        rememberDisplacedSource(id)
    }
    if selectSource(id: asciiSourceID) { return }

    // US Extended not enabled — take any ASCII-capable source rather than leaving CJK on.
    if let source = enabledSources().first(where: isASCIICapable) {
        TISSelectInputSource(source)
    }
}

/// Selects a non-ASCII (CJK) source: the remembered displaced one, else the first
/// enabled non-ASCII source, else the configured fallback id.
private func applyCJK() {
    var candidates: [String] = []
    if let remembered = rememberedDisplacedSourceID() { candidates.append(remembered) }
    candidates += enabledSources()
        .filter { !isASCIICapable($0) && isSelectable($0) && isKeyboardInput($0) }
        .compactMap(sourceID)
    candidates.append(fallbackCJKSourceID)

    for id in candidates where selectSource(id: id) {
        forgetDisplacedSource()
        return
    }
}

private func apply(_ desired: InputClass) {
    switch desired {
    case .ascii: applyASCII()
    case .cjk: applyCJK()
    }
}

// MARK: - Commands

private func describeCurrent() -> (id: String, klass: InputClass)? {
    guard let source = currentSource(), let id = sourceID(source) else { return nil }
    return (id, isASCIICapable(source) ? .ascii : .cjk)
}

/// One line per apply: which pane and reason asked for it, and whether the
/// input source actually moved. Best effort — never fails an apply.
private func trace(
    desired: InputClass,
    pane: String,
    reason: String,
    before: (id: String, klass: InputClass)?,
    after: (id: String, klass: InputClass)?,
    note: String?
) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    var line = "\(stamp) pane=\(pane) reason=\(reason) desired=\(desired.rawValue)"
    line += " before=\(before?.id ?? "-") after=\(after?.id ?? "-")"
    if let note { line += " note=\(note)" }

    // O_APPEND single write, so overlapping applies never drop each other's lines.
    try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    let path = traceFile.path
    if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
       size > traceMaxBytes {
        try? FileManager.default.removeItem(atPath: path)
    }
    let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard fd >= 0 else { return }
    defer { close(fd) }
    _ = (line + "\n").withCString { write(fd, $0, strlen($0)) }
}

/// Selects `desired`, then re-reads once the switch has had time to settle and
/// retries once if it did not take: TIS reports the previous source for a few
/// hundred ms, and a select issued from a background process does not always
/// stick. A silent failure shows up in the log (and the exit status) instead of
/// as a wrong keyboard.
private func runApply(_ desired: InputClass, options: [String]) {
    func option(_ name: String) -> String? {
        guard let index = options.firstIndex(of: name), index + 1 < options.count else { return nil }
        return options[index + 1]
    }

    let before = describeCurrent()
    apply(desired)
    usleep(300_000)
    var after = describeCurrent()
    var note: String?
    if after?.klass != desired {
        apply(desired)
        usleep(300_000)
        after = describeCurrent()
        note = after?.klass == desired ? "retried" : "retry-failed"
    }
    trace(
        desired: desired,
        pane: option("--pane") ?? "-",
        reason: option("--reason") ?? "cli",
        before: before,
        after: after,
        note: note
    )
    print("\(after?.id ?? "-")\t\(after?.klass.rawValue ?? "-")")
    if after?.klass != desired { exit(EXIT_FAILURE) }
}

private func runStatus() {
    let current = describeCurrent()
    print("current=\(current?.id ?? "-")")
    print("current_class=\(current?.klass.rawValue ?? "-")")
    print("remembered=\(rememberedDisplacedSourceID() ?? "-")")
    if current == nil { exit(EXIT_FAILURE) }
}

private let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "ascii":
    runApply(.ascii, options: Array(arguments.dropFirst()))
case "cjk":
    runApply(.cjk, options: Array(arguments.dropFirst()))
case "status":
    runStatus()
default:
    fputs("usage: input-source-policy ascii|cjk [--pane ID] [--reason REASON] | status\n", stderr)
    exit(EXIT_FAILURE)
}
