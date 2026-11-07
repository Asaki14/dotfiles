// omacosy-bar — a native bar surface, in ONE process.
//
// SLICE: workspace chips + front-app pill, on the built-in display only,
// drawn over sketchybar's own bar so the two can be watched side by side
// (sketchybar keeps the external display). This exists to answer one
// question with numbers rather than opinion: how much of the bar's
// latency is the work, and how much is the process boundaries?
//
// The shape of the answer is in the data flow. sketchybar learns that a
// workspace changed, forks a shell script, and that script spawns five
// `aerospace` CLI calls (~23 ms each) to ask what happened — 220 ms
// before a pixel moves. This daemon already holds the window model in
// memory, fed by the same SkyLight notifications the other daemons use,
// so a workspace switch touches no subprocess at all: update one field,
// draw one frame. The slow path (which windows exist, where) runs only
// on window create/destroy, off the critical path.
//
// Timings land in /tmp/omacosy-bar.log as `switch <ws> <ms>`.
//
// The right cluster is the same eight pills the bar already carries, but
// reading their sources directly instead of forking a script that forks
// `pmset`, `osascript`, `networksetup` and `ipconfig`: IOPS for power,
// CoreAudio for volume, DisplayServices for brightness, SCDynamicStore
// for the network, IOBluetooth for devices. Every one of those is a
// publisher, so nothing here polls except the clock and the weather,
// which have no publisher to listen to.
import ApplicationServices
import AppKit
import CoreAudio
import CoreBluetooth
import CoreLocation
import CoreWLAN
import IOBluetooth
import IOKit.ps
import SystemConfiguration
import UniformTypeIdentifiers

// DisplayServices (private) — the same calls Control Center makes, and
// the same ones helper/main.swift uses for `omacosy-helper brightness`.
@_silgen_name("DisplayServicesGetBrightness")
func DSGetBrightness(_ display: CGDirectDisplayID, _ value: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
func DSSetBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Int32

// Brightness has a publisher after all. The callback's later arguments
// are deliberately untyped and never dereferenced: the arity is what the
// ABI needs, the contents are not ours to trust.
typealias DSBrightnessProc = @convention(c) (UnsafeRawPointer?, CGDirectDisplayID, UnsafeRawPointer?, UnsafeRawPointer?) -> Void
@_silgen_name("DisplayServicesRegisterForBrightnessChangeNotifications")
func DSRegisterBrightnessNotifications(_ display: CGDirectDisplayID, _ context: UnsafeMutableRawPointer?, _ callback: DSBrightnessProc) -> Int32

@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func BTGetPower() -> Int32

// --- SkyLight window events (borders.swift recipe) ------------------------

typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32
@_silgen_name("SLSRequestNotificationsForWindows")
func SLSRequestNotificationsForWindows(_ cid: Int32, _ windows: UnsafePointer<UInt32>, _ count: Int32) -> CGError
@_silgen_name("SLSRegisterNotifyProc")
func SLSRegisterNotifyProc(_ proc: NotifyProc, _ event: UInt32, _ context: UnsafeMutableRawPointer?) -> CGError
@_silgen_name("SLSGetEventPort")
func SLSGetEventPort(_ cid: Int32, _ port: UnsafeMutablePointer<mach_port_t>) -> CGError
@_silgen_name("SLEventCreateNextEvent")
func SLEventCreateNextEvent(_ cid: Int32) -> Unmanaged<CGEvent>?

let EVENT_WINDOW_MOVE: UInt32 = 806
let EVENT_WINDOW_RESIZE: UInt32 = 807
// Sending a window to another workspace ORDERS IT OUT, it does not move
// it: measured with a SkyLight probe, a workspace switch fires
// 806/808/815 but a window changing workspace fires only 808 and 815.
// Watching 806 for that is why the chips sat stale until some unrelated
// app next opened a window. They arrive as a pair; both are watched
// because the pairing is observed behaviour, not a documented promise.
let EVENT_WINDOW_ORDER: UInt32 = 808
let EVENT_WINDOW_VISIBILITY: UInt32 = 815
let EVENT_WINDOW_CREATE: UInt32 = 1325
let EVENT_WINDOW_DESTROY: UInt32 = 1326

// --- plumbing -------------------------------------------------------------

let aerospaceBin = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "aerospace"

@discardableResult
func aerospace(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: aerospaceBin)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

// The OTHER window manager. omacosy-wm-switch can hand the session from
// AeroSpace to OmniWM (and back) while this daemon runs. The running-app
// check is an in-process lookup, cheap enough to be the whole detection;
// reconcile() below keeps which manager labels the bar in labelsFromOmniWM.
let omniwmBundleID = "com.barut.OmniWM"

func omniwmActive() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: omniwmBundleID).isEmpty
}

let omniwmctlBin = ["/opt/homebrew/bin/omniwmctl",
                    "/Applications/OmniWM.app/Contents/MacOS/omniwmctl"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "omniwmctl"

@discardableResult
func omniwmctl(_ args: [String]) -> String { shell(omniwmctlBin, args) }

// exec a binary at an absolute path, stdout back (the omniQuery fast path)
func shellOut(_ bin: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: bin)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

// One query, unwrapped to its payload. The CLI prints the whole
// IPCResponse envelope; everything the bar wants lives two levels down
// at result.payload (OmniWM docs/IPC-CLI.md, "Response Format").
func omniQuery(_ name: String, _ args: [String] = []) -> [String: Any]? {
    // fast path: omacosy-omni holds a persistent socket and launches in
    // ~3 ms where omniwmctl (Swift) needs ~10; it speaks `query <name>
    // [fields-csv]` and prints the same envelope. Anything fancier
    // (selector flags like --focused) stays on omniwmctl.
    let omni = "\(NSHomeDirectory())/.local/bin/omacosy-omni"
    var out = ""
    if FileManager.default.isExecutableFile(atPath: omni),
       args.isEmpty || (args.count == 2 && args[0] == "--fields") {
        out = shellOut(omni, args.isEmpty ? ["query", name] : ["query", name, args[1]])
    }
    if out.isEmpty {
        out = omniwmctl(["query", name] + args + ["--format", "json"])
    }
    guard let data = out.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (root["ok"] as? Bool) == true,
          let result = root["result"] as? [String: Any]
    else { return nil }
    return result["payload"] as? [String: Any]
}

// click-to-jump, whichever WM is listening. OmniWM's focus-name resolves
// a numeric raw workspace ID across all monitors, which is exactly what a
// chip on either display means.
func focusWorkspace(_ ws: String) {
    if omniwmActive() {
        omniwmctl(["workspace", "focus-name", ws])
    } else {
        aerospace(["workspace", ws])
    }
}

let logURL = URL(fileURLWithPath: "/tmp/omacosy-bar.log")
func tlog(_ m: String) {
    let line = "\(Date()) \(m)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.data(using: .utf8)!.write(to: logURL)
    }
}

private struct BundleIdentifier {
    let rawValue: String

    init?(_ rawValue: String) {
        let segments = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              segments.allSatisfy({ segment in
                  guard let first = segment.unicodeScalars.first,
                        BundleIdentifier.isAlphanumeric(first) else { return false }
                  return segment.unicodeScalars.allSatisfy(BundleIdentifier.isAlphanumericOrHyphen)
              })
        else { return nil }
        self.rawValue = rawValue
    }

    private static func isAlphanumeric(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value) || (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
    }

    private static func isAlphanumericOrHyphen(_ scalar: UnicodeScalar) -> Bool {
        isAlphanumeric(scalar) || scalar.value == 45
    }
}

private enum WorkspaceIcon {
    case glyph(String)
    case image(NSImage)
    case unavailable
}

private enum WorkspaceIconDeclaration {
    case glyph(String)
    case bundle(BundleIdentifier)
}

private struct WorkspaceIconConfig {
    let values: [String: WorkspaceIcon]

    func icon(for workspace: String) -> WorkspaceIcon? {
        if let icon = values[workspace] { return icon }
        guard workspace.count > 1,
              workspace.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let last = workspace.unicodeScalars.last,
              (49...57).contains(last.value)
        else { return nil }
        return values[String(Character(last))]
    }
}

private func loadWorkspaceIconConfig() -> WorkspaceIconConfig {
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omacosy/workspace-icons.conf")
    guard FileManager.default.fileExists(atPath: file.path) else {
        return WorkspaceIconConfig(values: [:])
    }
    guard let text = try? String(contentsOf: file, encoding: .utf8) else {
        tlog("workspace-icons: could not read \(file.path)")
        return WorkspaceIconConfig(values: [:])
    }

    var declarations: [String: WorkspaceIconDeclaration] = [:]
    for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let lineNumber = offset + 1
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        guard let separator = line.firstIndex(of: "=") else {
            tlog("workspace-icons: malformed line \(lineNumber)")
            continue
        }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else {
            tlog("workspace-icons: malformed line \(lineNumber)")
            continue
        }

        let declaration: WorkspaceIconDeclaration?
        if let bundle = BundleIdentifier(value) {
            declaration = .bundle(bundle)
        } else if value.unicodeScalars.count == 1 {
            declaration = .glyph(value)
        } else {
            declaration = nil
        }
        guard let declaration else {
            tlog("workspace-icons: malformed line \(lineNumber)")
            continue
        }
        if declarations[key] != nil {
            tlog("workspace-icons: duplicate \(key) on line \(lineNumber), last valid value wins")
        }
        declarations[key] = declaration
    }

    var values: [String: WorkspaceIcon] = [:]
    for (key, declaration) in declarations {
        switch declaration {
        case .glyph(let glyph):
            values[key] = .glyph(glyph)
        case .bundle(let identifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier.rawValue) else {
                tlog("workspace-icons: \(key) could not resolve \(identifier.rawValue)")
                values[key] = .unavailable
                continue
            }
            values[key] = .image(NSWorkspace.shared.icon(forFile: url.path))
        }
    }
    return WorkspaceIconConfig(values: values)
}

private let workspaceIconConfig = loadWorkspaceIconConfig()

// --- theme ----------------------------------------------------------------
// The same palette sketchybar reads. Parsed once and kept as colours, not
// re-sourced per item by sixteen shell scripts.

struct Palette {
    var itemBG = NSColor.black
    var accent = NSColor.systemBlue
    var label = NSColor.white
    var muted = NSColor.gray
    var barBG = NSColor.black
    var red = NSColor.systemRed
    var green = NSColor.systemGreen
    var yellow = NSColor.systemYellow
}

func color(fromARGB v: UInt64) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: CGFloat((v >> 24) & 0xff) / 255)
}

func loadPalette() -> Palette {
    var p = Palette()
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omarchy/current/theme/sketchybar.sh")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return p }
    for line in text.split(separator: "\n") {
        let parts = line.replacingOccurrences(of: "export ", with: "").split(separator: "=")
        guard parts.count == 2, parts[1].hasPrefix("0x"),
              let v = UInt64(parts[1].dropFirst(2), radix: 16) else { continue }
        switch parts[0] {
        case "ITEM_BG": p.itemBG = color(fromARGB: v)
        case "ACCENT": p.accent = color(fromARGB: v)
        case "LABEL_COLOR": p.label = color(fromARGB: v)
        case "MUTED": p.muted = color(fromARGB: v)
        case "BAR_BG_SOLID": p.barBG = color(fromARGB: v)
        case "RED": p.red = color(fromARGB: v)
        case "GREEN": p.green = color(fromARGB: v)
        case "YELLOW": p.yellow = color(fromARGB: v)
        default: break
        }
    }
    return p
}

// Ask for the family by name and VERIFY we got it. sketchybar's
// `--default` silently handed half the bar "Hack Nerd Font", which is not
// installed, so the text fell back to a system face and nothing said so.
// A missing family is a loud fallback here, once, at startup.
func nerdFont(_ face: String, _ size: CGFloat) -> NSFont {
    let desc = NSFontDescriptor(fontAttributes: [
        .family: "JetBrainsMono Nerd Font",
        .face: face,
    ])
    if let f = NSFont(descriptor: desc, size: size), f.familyName == "JetBrainsMono Nerd Font" {
        return f
    }
    tlog("font: JetBrainsMono Nerd Font \(face) unavailable — using system mono")
    return .monospacedSystemFont(ofSize: size, weight: face == "Bold" ? .bold : .semibold)
}

// --- model ----------------------------------------------------------------

// Shared across every display: which workspace has focus, what the front
// app is, which workspaces hold what. Anything that differs per screen —
// the workspace set, the visible one, the notch — belongs to the surface.
final class Model {
    var focused = "" // globally focused workspace
    var soleApp: [String: String] = [:] // ws -> app name, when it holds exactly one
    var occupied: Set<String> = []
    var frontApp = ""
    var media = Media()
}

struct Media: Equatable {
    var running = false
    var playing = false
    var title = ""
}

let model = Model()
var palette = loadPalette()

// SLOW path: who lives where. Three CLI calls — and it runs only when a
// window is created or destroyed, never on a workspace switch.
//
// It is computed OFF the main queue and applied on it. Measured the hard
// way: with the CLI calls inline on main, one contended rebuild blocked
// the render path for 7.6 seconds and every switch queued behind it. The
// architecture only pays off if subprocess work never sits on the path a
// frame has to travel.
struct Snapshot {
    var perMonitor: [String: (workspaces: [String], visible: String)] = [:]
    var soleApp: [String: String] = [:]
    var occupied: Set<String> = []
    var focused = "" // omniwm only — under aerospace the fast path owns it
}

let rebuildQueue = DispatchQueue(label: "com.omacosy.bar.rebuild")

func fetchSnapshot() -> Snapshot {
    omniwmActive() ? omniwmSnapshot() : aerospaceSnapshot()
}

func aerospaceSnapshot() -> Snapshot {
    var s = Snapshot()
    // ONE call for every monitor's set and which of them is visible: the
    // old loop spent two subprocesses per display, so docking doubled it
    // to four and the rebuild grew with the display count — on a path a
    // window move now waits behind
    var sets: [String: [String]] = [:]
    var visible: [String: String] = [:]
    for line in aerospace(["list-workspaces", "--all", "--format",
                           "%{workspace}|%{monitor-id}|%{workspace-is-visible}"])
        .split(separator: "\n") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 3 else { continue }
        sets[f[1], default: []].append(f[0])
        if f[2] == "true" { visible[f[1]] = f[0] }
    }
    for id in surfaces.map({ $0.monitorID }) {
        s.perMonitor[id] = (sets[id] ?? [], visible[id] ?? "")
    }

    var sole: [String: String] = [:]
    var count: [String: Int] = [:]
    for line in aerospace(["list-windows", "--all", "--format",
                           "%{workspace}|%{app-name}|%{window-layout}"]).split(separator: "\n") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 3 else { continue }
        guard f[2] != "floating" else { continue }
        s.occupied.insert(f[0])
        if let existing = sole[f[0]] {
            if existing != f[1] { count[f[0]] = 2 }
        } else {
            sole[f[0]] = f[1]
            count[f[0]] = 1
        }
    }
    s.soleApp = sole.filter { count[$0.key] == 1 }
    return s
}

// The same answers out of omniwmctl, on the same two-subprocess budget:
// workspaces arrive with their display and visibility in one query, and
// the windows query brings the app names the sole-app chips need. The
// snapshot also carries focus — OmniWM has no exec-on-workspace-change
// hook to feed /tmp/omacosy-bar-ws, so it rides the slow path here and
// the watch stream below covers the fast one.
func omniwmSnapshot() -> Snapshot {
    var s = Snapshot()
    var sets: [String: [String]] = [:]
    var visible: [String: String] = [:]
    if let list = omniQuery("workspaces",
                            ["--fields", "raw-name,display"])?["workspaces"]
        as? [[String: Any]] {
        for w in list {
            guard let name = w["rawName"] as? String,
                  let monitor = (w["display"] as? [String: Any])?["id"] as? String else { continue }
            sets[monitor, default: []].append(name)
        }
    }
    // visible/focused come from the DISPLAYS query: the workspaces
    // query's isVisible/isFocused go dark on EMPTY workspaces (the
    // same trap omacosy-ws hit), and the pill for a focused empty 8/9
    // never lit up
    if let displays = omniQuery("displays", [])?["displays"] as? [[String: Any]] {
        for d in displays {
            guard let id = d["id"] as? String,
                  let active = (d["activeWorkspace"] as? [String: Any])?["rawName"] as? String
            else { continue }
            visible[id] = active
            if (d["isCurrent"] as? Bool) == true { s.focused = active }
        }
    }
    for id in surfaces.map({ $0.monitorID }) {
        s.perMonitor[id] = (sets[id] ?? [], visible[id] ?? "")
    }

    var sole: [String: String] = [:]
    var count: [String: Int] = [:]
    if let list = omniQuery("windows", ["--fields", "workspace,app,mode"])?["windows"]
        as? [[String: Any]] {
        for w in list {
            guard let ws = (w["workspace"] as? [String: Any])?["rawName"] as? String,
                  let app = (w["app"] as? [String: Any])?["name"] as? String else { continue }
            guard (w["mode"] as? String) != "floating" else { continue }
            s.occupied.insert(ws)
            if let existing = sole[ws] {
                if existing != app { count[ws] = 2 }
            } else {
                sole[ws] = app
                count[ws] = 1
            }
        }
    }
    s.soleApp = sole.filter { count[$0.key] == 1 }
    return s
}

// Reports whether anything actually moved. A workspace switch produces
// window moves too, and those snapshots come back identical — saying so
// keeps the repaint (and the log line) for the times something changed.
@discardableResult
func apply(_ s: Snapshot) -> Bool {
    var changed = false
    for surface in surfaces {
        guard let part = s.perMonitor[surface.monitorID] else { continue }
        if !part.workspaces.isEmpty, surface.workspaces != part.workspaces {
            surface.workspaces = part.workspaces
            surface.mine = Set(part.workspaces)
            changed = true
        }
        if !part.visible.isEmpty, surface.visible != part.visible {
            surface.visible = part.visible
            changed = true
        }
    }
    if model.occupied != s.occupied { model.occupied = s.occupied; changed = true }
    if model.soleApp != s.soleApp { model.soleApp = s.soleApp; changed = true }
    if !s.focused.isEmpty, model.focused != s.focused {
        tlog("focused \(s.focused) (snapshot)")
        model.focused = s.focused
        changed = true
    }
    return changed
}


// FAST path: a workspace switch changes focus and nothing else. No CLI,
// no IPC, no shell — every surface already knows the rest, and the one
// that owns the workspace also now shows it.
func setFocused(_ ws: String) {
    model.focused = ws
    for surface in surfaces where surface.mine.contains(ws) { surface.visible = ws }
}

// --- media (Spotify announces itself; the title needs no subprocess) -------
// media.sh spawns osascript to ask what is playing. Spotify's own
// PlaybackStateChanged notification already carries Name, Artist and
// Player State, so the only subprocess left is the one a click sends —
// and that is user-initiated, where 20 ms does not show.

let spotifyBundleID = "com.spotify.client"

func spotifyRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundleID).isEmpty
}

func updateMedia(from info: [AnyHashable: Any]? = nil) {
    guard !mediaSourceMPD else { return } // `media-source mpd`: the daemon file owns Media
    var next = Media()
    next.running = spotifyRunning()
    if next.running {
        if let info {
            next.playing = (info["Player State"] as? String) == "Playing"
            let name = info["Name"] as? String ?? ""
            let artist = info["Artist"] as? String ?? ""
            next.title = artist.isEmpty ? name : "\(artist) — \(name)"
        } else {
            next.title = model.media.title
            next.playing = model.media.playing
        }
    }
    guard next != model.media else { return }
    let t0 = DispatchTime.now().uptimeNanoseconds
    model.media = next
    repaint()
    tlog(String(format: "media %@ %@ %.2f ms", next.playing ? "play" : "pause", next.title,
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

// startup only: the notification fires on change, so the current track
// has to be asked for once
func primeMedia() {
    guard !mediaSourceMPD, spotifyRunning() else { return }
    rebuildQueue.async {
        let script = """
        tell application "Spotify" to if it is running then \
        return (player state as text) & "|" & artist of current track & "|" & name of current track
        """
        let out = shell("/usr/bin/osascript", ["-e", script])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = out.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return }
        DispatchQueue.main.async {
            model.media = Media(running: true, playing: parts[0] == "playing",
                                title: parts[1].isEmpty ? parts[2] : "\(parts[1]) — \(parts[2])")
            repaint()
        }
    }
}

func spotify(_ command: String) {
    DispatchQueue.global(qos: .userInitiated).async {
        _ = shell("/usr/bin/osascript", ["-e", "tell application \"Spotify\" to \(command)"])
    }
}

// --- right cluster ---------------------------------------------------------
// An item is data. Layout, hit-testing and drawing are generic over the
// list, so adding a pill is one entry and one provider — no per-item
// geometry, no padding arithmetic, no width caches.

struct BarItem: Equatable {
    var icon = ""
    var label = ""
    // which palette colour, not a copy of it: read when drawing, so a
    // theme switch recolours every pill in the repaint it already does
    var iconColor: KeyPath<Palette, NSColor>?
    var drawing = true
}

// screen order, left to right
let rightLayout = configuredRightLayout(
    ["weather", "proxy-speed", "fission", "wifi", "bluetooth", "brightness", "volume", "battery", "airpods",
     "caffeinate", "clock", "activity"])
let rightOrder = rightLayout.order
let rightGroups = rightLayout.groups
// `media-controls off` in bar-items.conf; absent = on, i.e. upstream behaviour
let mediaControls = rightLayout.mediaControls
// `media-source mpd` in bar-items.conf: the media pill and its lyric both come
// from the lyrics daemon's JSON (which then reads mpd), Spotify is never asked.
// Absent = upstream Spotify behaviour. Declared here, before the first
// top-level primeMedia()/updateMedia(), so it is initialised when they run.
let mediaSourceMPD = configuredValue("media-source") == "mpd"
let rightGroupOf = groupIndexByItem(rightGroups)
var rightItems: [String: BarItem] = [:]

func set(_ name: String, _ mutate: (inout BarItem) -> Void) {
    var item = rightItems[name] ?? BarItem()
    mutate(&item)
    guard item != rightItems[name] else { return } // no pixels owed
    let t0 = DispatchTime.now().uptimeNanoseconds
    rightItems[name] = item
    repaint()
    // an open popup shows the same state as its pill — the brightness
    // popup kept whatever value it was built with while the pill moved
    if openPopup == name { refreshPopup() }
    tlog(String(format: "item %@ %.2f ms", name, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

func shell(_ launch: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launch)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: out, encoding: .utf8) ?? ""
}

// --- clock (no publisher: the one honest timer, aligned to the minute)
// Month before day, Chinese weekday. Built from date COMPONENTS rather than
// from a DateFormatter pattern with a zh_CN locale: a pattern still answers
// to the user's region settings (calendar, digit shaping, weekday names), and
// this label must read the same on any Mac and never fall back to English.
let cnWeekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

func updateClock() {
    let cal = Calendar(identifier: .gregorian)
    let c = cal.dateComponents([.month, .day, .hour, .minute, .weekday], from: Date())
    let label = String(format: "%d月%d日 周%@  %02d:%02d",
                       c.month ?? 0, c.day ?? 0,
                       cnWeekdayNames[((c.weekday ?? 1) - 1) % 7],
                       c.hour ?? 0, c.minute ?? 0)
    set("clock") { $0.icon = "󰃰"; $0.label = label }
}

// --- battery (IOPS publishes, capacity ticks included)
func updateBattery() {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
    else { return }
    for source in list {
        guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let cur = d[kIOPSCurrentCapacityKey] as? Int else { continue }
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
        let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        // same thresholds and glyphs the bar already uses
        var icon = "󰂃", color: KeyPath<Palette, NSColor> = \.red
        switch pct {
        case 90...: icon = "󰁹"; color = \.green
        case 60..<90: icon = "󰂀"; color = \.label
        case 30..<60: icon = "󰁾"; color = \.label
        case 10..<30: icon = "󰁻"; color = \.yellow
        default: break
        }
        if charging { icon = "󰂄"; color = \.green }
        set("battery") { $0.icon = icon; $0.iconColor = color; $0.label = "\(pct)%" }
        return
    }
}

// --- volume (CoreAudio publishes on the device itself)
func defaultOutputDevice() -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                               mScope: kAudioDevicePropertyScopeOutput, mElement: element)
}

func readVolume() -> (percent: Int, muted: Bool)? {
    let dev = defaultOutputDevice()
    guard dev != 0 else { return nil }

    var muted: UInt32 = 0
    var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
    var muteSize = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(dev, &muteAddr, 0, nil, &muteSize, &muted)

    var level: Float32 = 0
    var addr = volumeAddress(kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Float32>.size)
    if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &level) != noErr {
        // a device without a master channel: average the stereo pair
        var sum: Float32 = 0
        var found = 0
        for channel in UInt32(1)...UInt32(2) {
            var chAddr = volumeAddress(channel)
            var chSize = UInt32(MemoryLayout<Float32>.size)
            var value: Float32 = 0
            if AudioObjectGetPropertyData(dev, &chAddr, 0, nil, &chSize, &value) == noErr {
                sum += value
                found += 1
            }
        }
        guard found > 0 else { return nil }
        level = sum / Float32(found)
    }
    return (Int((level * 100).rounded()), muted != 0)
}

func writeVolume(_ percent: Int) {
    let dev = defaultOutputDevice()
    guard dev != 0 else { return }
    var value = Float32(min(100, max(0, percent))) / 100
    let size = UInt32(MemoryLayout<Float32>.size)
    var addr = volumeAddress(kAudioObjectPropertyElementMain)
    if AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &value) != noErr {
        for channel in UInt32(1)...UInt32(2) {
            var chAddr = volumeAddress(channel)
            AudioObjectSetPropertyData(dev, &chAddr, 0, nil, size, &value)
        }
    }
}

// the output devices the volume popup lists — the same enumeration
// helper/main.swift does for `omacosy-helper audio`, without the round trip
func audioOutputDevices() -> [(id: AudioDeviceID, name: String)] {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
    else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
    else { return [] }

    var result: [(AudioDeviceID, String)] = []
    for id in ids {
        // output-capable only: a device with no output streams is a mic
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0
        else { continue }

        var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var ok = false
        withUnsafeMutablePointer(to: &name) { ptr in
            ok = AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, ptr) == noErr
        }
        guard ok else { continue }
        result.append((id, name as String))
    }
    return result
}

// BLE battery telemetry alone is not an audio connection. CoreAudio exposes
// connected Bluetooth outputs even when another output is selected.
func connectedBluetoothOutputNames() -> Set<String> {
    var names = Set<String>()
    for device in audioOutputDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE else { continue }
        names.insert(device.name)
    }
    return names
}

func setDefaultOutputDevice(_ id: AudioDeviceID) {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var dev = id
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                               UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
}

func updateVolume() {
    guard let v = readVolume() else { return }
    let icon: String
    if v.muted || v.percent == 0 {
        icon = "󰝟"
    } else if v.percent >= 70 {
        icon = "󰕾"
    } else if v.percent >= 30 {
        icon = "󰖀"
    } else {
        icon = "󰕿"
    }
    set("volume") { $0.icon = icon; $0.iconColor = nil; $0.label = v.muted ? "mute" : "\(v.percent)%" }
}

// --- shade (below the hardware minimum, without an overlay window) -------
// QuickShade and friends float a translucent black window over everything.
// That works, but the window is real: it sits in the z-order, it covers
// the bar, and it turns every screenshot black — including yours. Scaling
// the display's GAMMA instead dims at scanout, so there is no window, it
// applies over fullscreen apps, and captures come out normal.
//
// It also fails safe. Gamma set by a process is reset when that process
// exits (verified), so a crash or an uninstall restores the screen by
// itself and there is no way to be left staring at a dark display.
//
// Bonus: unlike DisplayServices this reaches EXTERNAL displays, which have
// no backlight API without DDC.
let shadeFile = "\(NSHomeDirectory())/.local/state/omacosy/shade"
let shadeFloor: Double = 0.15 // never darker than this fraction of output

var shade: Double = {
    guard let t = try? String(contentsOfFile: shadeFile, encoding: .utf8),
          let v = Double(t.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
    return min(1, max(0, v))
}()

func applyShade() {
    let scale = Float(1 - shade * (1 - shadeFloor))
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(8, &ids, &count) == .success else { return }
    for i in 0..<Int(count) {
        if shade <= 0.001 {
            CGDisplayRestoreColorSyncSettings()
        } else {
            CGSetDisplayTransferByFormula(ids[i], 0, scale, 1, 0, scale, 1, 0, scale, 1)
        }
    }
}

func setShade(_ value: Double) {
    shade = min(1, max(0, value))
    applyShade()
    try? String(format: "%.3f", shade).write(toFile: shadeFile, atomically: true, encoding: .utf8)
    updateBrightness()
}

// --- brightness (DisplayServices publishes; built-in panel only)
func builtinDisplayID() -> CGDirectDisplayID {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
}

func updateBrightness() {
    var value: Float = 0
    guard DSGetBrightness(builtinDisplayID(), &value) == 0, value.isFinite else {
        set("brightness") { $0.drawing = false } // hide rather than lie
        return
    }
    let pct = Int((value * 100).rounded())
    // Shaded reads as BELOW zero, because that is what it is: past the
    // point the backlight can go. The moon says which side of zero you are on.
    if shade > 0.001 {
        set("brightness") {
            $0.drawing = true
            $0.icon = "\u{F0594}"
            $0.iconColor = \.muted
            $0.label = "−\(Int((shade * 100).rounded()))%"
        }
        return
    }
    let icon = pct >= 66 ? "󰃠" : (pct >= 33 ? "󰃟" : "󰃞")
    set("brightness") { $0.drawing = true; $0.icon = icon; $0.iconColor = nil; $0.label = "\(pct)%" }
}

// --- location (what the network name costs) -------------------------------
// macOS classes the SSID as location data. Two things are required and
// neither alone is enough: this grant, and a BUNDLED binary — measured,
// an unbundled build reads nil with authorisation held, services on and
// updates running, while a bundled one reads the name the instant the
// answer lands. Nothing here reads a coordinate; the authorisation IS
// the API, and the manager exists only to ask for it.
//
// Gated like bluetooth: TCC judges the RESPONSIBLE process, so only the
// launchd-started bar may prompt and running it by hand stays quiet.
final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var managed: Bool { ProcessInfo.processInfo.environment["OMACOSY_MANAGED"] != nil }

    func start() {
        manager.delegate = self
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            updateWifi() // the name is readable now; the pill may predate it
        case .denied, .restricted:
            tlog("location: denied — the wi-fi pill stays nameless")
        default:
            guard managed else {
                tlog("location: not launchd-managed, so not prompting")
                return
            }
            manager.requestWhenInUseAuthorization()
        }
    }

    // the name appears the moment the answer lands — no restart, and no
    // polling for a permission that publishes
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        tlog("location: authorization now \(m.authorizationStatus.rawValue)")
        updateWifi()
    }
}
let locationGate = LocationGate()

// --- night shift (CBBlueLightClient publishes) ---------------------------
// Private CoreBrightness, reached by reflection the way omacosy-helper
// reaches it. It has a publisher: setStatusNotificationBlock fires on
// every change whoever made it — the schedule, Control Center, System
// Settings, us. The popup used to cache what one subprocess printed
// the first time it opened, so anything that turned night shift off
// afterwards left the row reading yesterday's answer until the bar
// restarted.
struct BlueLightStatus {
    // `active` read true in every state measured here — toggle on and
    // off, inside and outside the schedule window — so the row reads
    // `enabled`, which is the field setEnabled: actually moves
    var active: ObjCBool = false
    var enabled: ObjCBool = false
    var sunSchedulePermitted: ObjCBool = false
    var mode: Int32 = 0
    var schedule: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
    var disableFlags: UInt64 = 0
    var available: ObjCBool = false
}

let blueLight: (cls: NSObject.Type, client: NSObject)? = {
    guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
                 RTLD_LAZY) != nil,
        let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
    else {
        tlog("CoreBrightness unavailable — no night shift row")
        return nil
    }
    return (cls, cls.init())
}()

func blueLightStatus() -> BlueLightStatus? {
    let sel = NSSelectorFromString("getBlueLightStatus:")
    guard let bl = blueLight, let m = class_getInstanceMethod(bl.cls, sel) else { return nil }
    typealias GetFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    let f = unsafeBitCast(method_getImplementation(m), to: GetFn.self)
    var st = BlueLightStatus()
    let ok = withUnsafeMutablePointer(to: &st) { f(bl.client, sel, UnsafeMutableRawPointer($0)) }
    return ok ? st : nil
}

func setNightShift(_ on: Bool) {
    let sel = NSSelectorFromString("setEnabled:")
    guard let bl = blueLight, let m = class_getInstanceMethod(bl.cls, sel) else { return }
    typealias SetFn = @convention(c) (AnyObject, Selector, Bool) -> Bool
    _ = unsafeBitCast(method_getImplementation(m), to: SetFn.self)(bl.client, sel, on)
}

// CoreBrightness keeps the block, so the block has to keep itself
var nightShiftBlock: (@convention(block) () -> Void)? = nil

func watchNightShift() {
    let sel = NSSelectorFromString("setStatusNotificationBlock:")
    guard let bl = blueLight, let m = class_getInstanceMethod(bl.cls, sel) else {
        tlog("night shift notifications unavailable — the row reads fresh on open only")
        return
    }
    let block: @convention(block) () -> Void = {
        DispatchQueue.main.async {
            guard let s = blueLightStatus() else { return }
            // which field a schedule boundary actually moves is worth
            // having in the log the morning after
            tlog("night shift changed: enabled=\(s.enabled.boolValue) "
                + "active=\(s.active.boolValue) mode=\(s.mode)")
            if openPopup == "brightness" { refreshPopup() }
        }
    }
    nightShiftBlock = block
    typealias SetFn = @convention(c) (AnyObject, Selector, Any) -> Void
    unsafeBitCast(method_getImplementation(m), to: SetFn.self)(bl.client, sel, block)
}

// --- wifi (SCDynamicStore publishes; SSID needs a subprocess, so it is
// fetched off-main and only when the network actually changed)
var wifiDevice = CWWiFiClient.shared().interface()?.interfaceName ?? "en0"

func updateWifi() {
    let powered = CWWiFiClient.shared().interface()?.powerOn() ?? false
    guard powered else {
        set("wifi") { $0.icon = "󰖪"; $0.iconColor = nil; $0.label = "off" }
        return
    }
    // The name lives in the POPUP, not the pill: a seventeen-character
    // SSID is ~150pt of bar, and the right cluster is right-aligned, so
    // on the notched display it pushed the far end under the notch. The
    // icon says connected; a click says to what.
    set("wifi") { $0.icon = "󰖩"; $0.iconColor = nil; $0.label = "" }
}

// --- bluetooth (IOBluetooth publishes connect/disconnect)
//
// IOBluetooth ABORTS the process outright — SIGABRT, no exception to
// catch — if it is touched without the Bluetooth privacy grant. Learnt
// here the same way watcher.swift learnt it: exit code 134 and an empty
// log. So the grant is gated on CBCentralManager.authorization (reading
// that never prompts), and the pill simply stays hidden when it is not
// held. The binary carries helper/bar-info.plist for the usage string,
// without which the prompt cannot even be raised.
func updateBluetooth() {
    guard CBCentralManager.authorization == .allowedAlways else { return }
    guard BTGetPower() != 0 else {
        set("bluetooth") { $0.drawing = true; $0.icon = "󰂲"; $0.iconColor = nil; $0.label = "off" }
        return
    }
    let connected = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [])
        .filter { $0.isConnected() }.count
    set("bluetooth") {
        $0.drawing = true
        $0.icon = connected > 0 ? "󰂱" : "󰂯"
        $0.iconColor = nil
        $0.label = connected > 0 ? "\(connected)" : ""
    }
}

// IOBluetooth's connect/disconnect notifications are ObjC target/action,
// so they need a real object to aim at; CoreBluetooth's delegate is what
// tells us the grant has landed.
final class BluetoothWatcher: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var classicStarted = false

    // Creating a CBCentralManager is itself an access, and TCC judges it
    // by the RESPONSIBLE process rather than this binary: started from a
    // shell the whole process is killed (SIGABRT, exit 134, no report),
    // embedded Info.plist and signature notwithstanding. Under launchd it
    // is responsible for itself and may prompt — which is the only reason
    // watcher.swift could. The plist sets OMACOSY_MANAGED so that running
    // this by hand for a test stays safe instead of dying.
    private var managed: Bool { ProcessInfo.processInfo.environment["OMACOSY_MANAGED"] != nil }

    func start() {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            startClassic()
            central = CBCentralManager(delegate: self, queue: .main)
        case .denied, .restricted:
            tlog("bluetooth: permission denied — pill hidden")
            set("bluetooth") { $0.drawing = false }
        default:
            guard managed else {
                tlog("bluetooth: not launchd-managed, so not prompting — pill hidden")
                set("bluetooth") { $0.drawing = false }
                return
            }
            set("bluetooth") { $0.drawing = false }
            central = CBCentralManager(delegate: self, queue: .main) // raises the prompt
        }
    }

    private func startClassic() {
        guard !classicStarted else { return }
        classicStarted = true
        IOBluetoothDevice.register(forConnectNotifications: self,
                                   selector: #selector(connected(_:device:)))
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        where device.isConnected() {
            device.register(forDisconnectNotification: self, selector: #selector(changed(_:device:)))
        }
        updateBluetooth()
    }

    @objc func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(changed(_:device:)))
        DispatchQueue.main.async { updateBluetooth() }
    }

    @objc func changed(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { updateBluetooth() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if CBCentralManager.authorization == .allowedAlways { startClassic() }
        DispatchQueue.main.async { updateBluetooth() }
    }
}
let bluetoothWatcher = BluetoothWatcher()

// --- weather (no publisher; wttr.in, refreshed on a long timer)
// One j1 fetch feeds both the pill and its popup — weather.sh does the
// same, via a cache file it writes atomically because a click can read it
// mid-write. In one process the struct IS the cache and that race cannot
// be expressed.

struct Weather {
    var emoji = ""
    var temp = ""
    var tempUnit = "°C"
    var desc = ""
    var feels = ""
    var low = ""
    var high = ""
    var wind = ""
    var humidity = ""
    var rain = ""
    var sunrise = ""
    var sunset = ""
    var moon = ""
    var location = ""
}

var weather: Weather?

struct WeatherPreferences {
    var fahrenheit = false
    var location = ""
}

func loadWeatherPreferences() -> WeatherPreferences {
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omacosy/weather.json")
    guard let data = try? Data(contentsOf: file),
          let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return WeatherPreferences() }

    var preferences = WeatherPreferences()
    if (config["unit"] as? String)?.lowercased() == "fahrenheit" {
        preferences.fahrenheit = true
    }
    if let location = config["location"] as? String {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.lowercased() != "auto" {
            preferences.location = trimmed
        }
    }
    return preferences
}

// WWO condition code -> glyph, night-aware for the clear/partly pair
func weatherEmoji(_ code: Int, night: Bool) -> String {
    switch code {
    case 113: return night ? "🌙" : "☀️"
    case 116: return night ? "☁️" : "⛅"
    case 119, 122: return "☁️"
    case 143, 248, 260: return "🌫️"
    case 176, 263, 266, 293, 296, 353: return "🌦️"
    case 299, 302, 305, 308, 356, 359: return "🌧️"
    case 200, 386, 389, 392, 395: return "⛈️"
    case 179, 182, 185, 227, 230, 281, 284, 311...338, 350, 362...368, 374...377: return "❄️"
    default: return "🌡️"
    }
}

func moonEmoji(_ phase: String) -> String {
    switch phase {
    case "New Moon": return "🌑"
    case "Waxing Crescent": return "🌒"
    case "First Quarter": return "🌓"
    case "Waxing Gibbous": return "🌔"
    case "Full Moon": return "🌕"
    case "Waning Gibbous": return "🌖"
    case "Last Quarter", "Third Quarter": return "🌗"
    case "Waning Crescent": return "🌘"
    default: return "🌙"
    }
}

func updateWeather() {
    let preferences = loadWeatherPreferences()
    var components = URLComponents()
    components.scheme = "https"
    components.host = "wttr.in"
    components.path = "/" + preferences.location
    components.queryItems = [URLQueryItem(name: "format", value: "j1")]
    guard let url = components.url else { return }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    URLSession.shared.dataTask(with: request) { data, _, _ in
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (root["current_condition"] as? [[String: Any]])?.first,
              let today = (root["weather"] as? [[String: Any]])?.first
        else { return }

        func text(_ d: [String: Any], _ key: String) -> String { d[key] as? String ?? "" }
        func nested(_ d: [String: Any], _ key: String) -> String {
            ((d[key] as? [[String: Any]])?.first?["value"] as? String) ?? ""
        }

        var w = Weather()
        let fahrenheit = preferences.fahrenheit
        let hour = Calendar.current.component(.hour, from: Date())
        w.emoji = weatherEmoji(Int(text(current, "weatherCode")) ?? 0, night: hour < 7 || hour >= 20)
        w.temp = text(current, fahrenheit ? "temp_F" : "temp_C")
        w.tempUnit = fahrenheit ? "°F" : "°C"
        w.desc = nested(current, "weatherDesc").lowercased()
        w.feels = text(current, fahrenheit ? "FeelsLikeF" : "FeelsLikeC")
        w.low = text(today, fahrenheit ? "mintempF" : "mintempC")
        w.high = text(today, fahrenheit ? "maxtempF" : "maxtempC")
        w.humidity = text(current, "humidity")

        let degrees = Int(text(current, "winddirDegree")) ?? 0
        let arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
        let wind = text(current, fahrenheit ? "windspeedMiles" : "windspeedKmph")
        w.wind = "\(arrows[((degrees + 180) / 45) % 8]) \(wind) \(fahrenheit ? "mph" : "km/h")"

        // rain earns a row only with real signal: falling now, or likely today
        let precipitation = text(current, fahrenheit ? "precipInches" : "precipMM")
        let precip = Double(precipitation) ?? 0
        let precipUnit = fahrenheit ? "in" : "mm"
        let chance = ((today["hourly"] as? [[String: Any]]) ?? [])
            .compactMap { Int(($0["chanceofrain"] as? String) ?? "0") }.max() ?? 0
        if precip > 0 {
            w.rain = "☔ \(precipitation)\(precipUnit) now"
            if chance >= 30 { w.rain += " · rain \(chance)% today" }
        } else if chance >= 30 {
            w.rain = "☔ rain \(chance)% today"
        }

        if let astro = (today["astronomy"] as? [[String: Any]])?.first {
            w.sunrise = text(astro, "sunrise")
            w.sunset = text(astro, "sunset")
            w.moon = "\(moonEmoji(text(astro, "moon_phase"))) \(text(astro, "moon_phase").lowercased())"
        }

        if let area = (root["nearest_area"] as? [[String: Any]])?.first {
            // wttr repeats the city as its region ("Porto, Porto"), so the
            // region is dropped whenever either name contains the other
            let city = nested(area, "areaName")
            let region = nested(area, "region")
            let country = nested(area, "country")
            var parts = [city]
            if !region.isEmpty,
               !city.lowercased().contains(region.lowercased()),
               !region.lowercased().contains(city.lowercased()) {
                parts.append(region)
            }
            if !country.isEmpty { parts.append(country) }
            w.location = parts.joined(separator: ", ")
        }

        DispatchQueue.main.async {
            weather = w
            set("weather") { $0.icon = ""; $0.label = "\(w.emoji) \(w.temp)\(w.tempUnit)" }
            if openPopup == "weather" { refreshPopup() }
        }
    }.resume()
}

// --- popups ----------------------------------------------------------------
// A popup is a list of rows in its own window. sketchybar has to model
// these as bar items with a naming convention (`clock.cal.3`) that a
// separate shell guard greps to clean up; here they are just views that
// go away when the window closes, so there is no convention to break and
// nothing to leak.

// Three type sizes, so a panel can say what matters most without a second
// font family: .large is the one headline a popup is allowed (today's
// weather), .small is the tail a reader only scans (the next days).
enum RowScale {
    case large
    case normal
    case small
}

// One day box in a calendar week strip. The week used to be a single
// pre-formatted string, which made a per-DAY highlight impossible: the cells
// are separate so today's box can be filled and the rest stay in columns.
struct CalendarCell {
    var text = ""
    var inMonth = true
    var today = false
}

// --- omacosy extras (fork): the clock panel's weather column ---------------
// The clock popup is two COLUMNS, not one list: the calendar on the left, the
// weather on the right. Today is a card with a glyph three times the body size
// because a panel this wide has room to answer "what is it doing now" before
// the eye ever reaches the forecast; the days after it are bars on one shared
// temperature window, so five days read as a slope instead of five numbers.
struct WeatherCard {
    var glyph = ""
    var temp = "" // "30°"
    var range = "" // today's own low~high, small, beside the big number
    var desc = "" // "晴  ·  市区"
    var detail = "" // "体感 33°  ·  湿度 46%"
}

struct TrendDay {
    var name = "" // 明天 / 周三
    var glyph = ""
    var low = 0
    var high = 0
    // the window every bar in the column is measured against — the whole
    // forecast's low and high, so the bars are comparable to each other
    var spanLow = 0.0
    var spanHigh = 1.0
    // further out is fainter: the drop in alpha carries the drop in
    // confidence without spending a second colour on it
    var fade: CGFloat = 1
    // 0 = this column's coolest high, 1 = its warmest. A settled week draws
    // five bars of nearly equal length; the tint is what still separates them.
    var warmth: CGFloat = 0

    var span: Double { spanHigh - spanLow }
}

// One Fishing Funds line on a fixed column grid: name, trend curve, rate, profit.
// `total` is the portfolio row — bold, no name column of its own.
struct FundLine {
    var name = ""
    var rate: Double?
    var profit = 0.0
    var spark: [Double] = []
    var total = false
}

let fundNameWidth: CGFloat = 168
let fundSparkWidth: CGFloat = 96
let fundRateWidth: CGFloat = 62
let fundProfitWidth: CGFloat = 64
let fundColumnGap: CGFloat = 12
let fundLineWidth = fundNameWidth + fundSparkWidth + fundRateWidth + fundProfitWidth + fundColumnGap * 3

struct PopupRow {
    var icon = ""
    var image: NSImage? // 16pt leading icon — Recent Items entries
    var text = ""
    var detail = "" // right-aligned, dim — menu shortcuts live here
    var hero = false // accent, bold — the title row
    var dim = false // the quiet action footer
    var muted = false // palette.muted — a secondary row, e.g. a forecast day
    var highlight = false // today's week, the active device
    var slider: Double? // 0...1 draws a track instead of text
    var onSlide: ((Double) -> Void)?
    var action: (() -> Void)?
    // a provider row carries its own colours: the source script already
    // decides them (per-window usage tone), so the row states them instead
    // of the view inferring one from hero/dim
    var tint: NSColor? // text colour, else the hero/dim/label rule
    var iconTint: NSColor? // glyph colour, else palette.accent
    // an explicit left-column width: a text icon ("5h", "Fable") measured by
    // INK would put every row's text at a different x, which is exactly what
    // a two-column panel must not do
    var iconColumn: CGFloat?
    // --- omacosy extras (fork) ---
    var scale: RowScale = .normal
    // a hairline between two sections of one popup; carries no text
    var rule = false
    // a week strip: seven day boxes on a fixed column grid
    var cells: [CalendarCell]?
    // A row with TWO hit zones, at its left and right edges, plus a centred
    // title: the calendar's month stepper. `action` stays one-per-row for
    // every other popup; only this row splits, and it splits by geometry the
    // same way `slider` does.
    var navBack: (() -> Void)?
    var navForward: (() -> Void)?
    // the two rows of the weather column, each drawn whole instead of as an
    // icon/text pair: they own their internal layout
    var card: WeatherCard?
    var trend: TrendDay?
    var fund: FundLine?
}

let rowHeight: CGFloat = 26
let popupPad: CGFloat = 8
let popupRadius: CGFloat = 8
// the click target of one month chevron, at each end of a nav row
let navZone: CGFloat = 26
// the air between the two columns of a split popup; the hairline sits in it
let popupColumnGap: CGFloat = 20
// the weather column is measured, not fitted: a bar needs a stable track, and
// a column that resized with the longest day name would move it every day
let weatherColumnWidth: CGFloat = 300
let weatherCardHeight: CGFloat = 100
let weatherTrendHeight: CGFloat = 28
let chevronLeft = "\u{F0141}" // md-chevron_left
let chevronRight = "\u{F0142}" // md-chevron_right

final class PopupView: NSView {
    var rows: [PopupRow] = []
    // an optional SECOND column, drawn to the right of `rows` — empty for
    // every popup but the clock's
    var sideRows: [PopupRow] = []
    // keyed by the row itself, not by an index: with two columns an index
    // no longer identifies which list it came from
    private var rowRects: [(PopupRow, NSRect)] = []
    // the row under the pointer, actionable rows only — menus read as menus
    // when they answer the hover. Held as its RECT for the same reason
    // rowRects is: with two columns an index names no single row.
    private var hoveredRect: NSRect?

    // NOT flipped: CTLineDraw draws in the CONTEXT's coordinates, so a
    // flipped view renders every glyph mirrored. NSString.draw hid that
    // difference, which is why this only broke when the text layer moved to
    // CoreText — the bar is unflipped and looked fine. Rows are laid out
    // downward explicitly instead of flipping the view.
    func font(_ row: PopupRow) -> NSFont {
        switch row.scale {
        case .large: return nerdFont("Bold", 17)
        case .small: return nerdFont("Regular", 11.5)
        case .normal:
            // the hero is half a point bigger than the body it titles: enough
            // to read as a heading next to accent+bold, not enough to reflow
            if row.hero { return nerdFont("Bold", 13.5) }
            if row.dim { return nerdFont("Regular", 12) }
            return nerdFont("Regular", 13)
        }
    }

    // the glyph column tracks the text size, so a headline row is big in BOTH
    // columns and a tail row is small in both
    func iconFont(_ row: PopupRow) -> NSFont {
        switch row.scale {
        case .large: return nerdFont("Bold", 20)
        case .small: return nerdFont("Regular", 12)
        case .normal: return nerdFont("Bold", 13)
        }
    }

    // the right-aligned dim column: a menu shortcut, never a heading
    func detailFont() -> NSFont { nerdFont("Regular", 11) }

    func height(_ row: PopupRow) -> CGFloat {
        // a rule is a hairline, not a row: a full 26 pt of blank per rule made
        // long menus read bulky instead of sectioned
        if row.rule { return 11 }
        if row.card != nil { return weatherCardHeight }
        if row.trend != nil { return weatherTrendHeight }
        if row.fund != nil { return 28 }
        // a week strip is taller than a text row: the calendar is the panel's
        // left half now, and a cramped grid was the main thing that made the
        // old single column look like a list rather than a month
        if row.cells != nil { return 30 }
        switch row.scale {
        case .large: return 34
        case .small: return 21
        case .normal: return rowHeight
        }
    }

    // one calendar column: the widest two-digit day plus air. Monospace, so
    // every day is the same ink and the grid never shifts month to month.
    func cellWidth(_ font: NSFont) -> CGFloat { advance("00", font) + 15 }

    // the seven columns a week row occupies — a body-sized row, which is what
    // calendarRows() builds its weeks as
    func calendarWidth() -> CGFloat { cellWidth(nerdFont("Regular", 13)) * 7 }

    // the stepper spans the GRID it steps, not the popup: the weather title
    // below can make the popup much wider, and chevrons pinned to that edge
    // would float away from the month they belong to
    func navRect(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.minX, y: rect.minY,
               width: min(rect.width, calendarWidth() + 8), height: rect.height)
    }

    // the glyph column: the accent, stepped back for a tail row so the small
    // rows recede in colour as well as in size
    func iconColor(_ row: PopupRow) -> NSColor {
        if let tint = row.iconTint { return tint }
        return row.scale == .small ? palette.accent.withAlphaComponent(0.7) : palette.accent
    }

    func color(_ row: PopupRow) -> NSColor {
        if let tint = row.tint { return tint }
        if row.hero { return palette.accent }
        // the dim footer is the label colour at 60%, the same relationship
        // the shell popups build with a 0x99 alpha prefix
        if row.dim { return palette.label.withAlphaComponent(0.6) }
        if row.muted { return palette.muted }
        return palette.label
    }

    // one column's own ink, before any popup padding is added
    func columnSize(_ rows: [PopupRow]) -> NSSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        for row in rows {
            height += self.height(row)
            if row.rule { continue }
            if row.card != nil || row.trend != nil {
                width = max(width, weatherColumnWidth)
                continue
            }
            if row.fund != nil {
                width = max(width, fundLineWidth + 8)
                continue
            }
            if let cells = row.cells {
                width = max(width, CGFloat(cells.count) * cellWidth(font(row)))
                continue
            }
            var w = advance(row.text, font(row))
            // the shortcut column never overlaps the label: it is measured in,
            // with the air a menu keeps between the two
            if !row.detail.isEmpty { w += advance(row.detail, detailFont()) + 24 }
            if !row.icon.isEmpty { w += (row.iconColumn ?? inkBox(row.icon, iconFont(row)).width) + 8 }
            // an app icon (Recent Items) rides the same leading bay a glyph would
            if row.image != nil { w += 22 }
            // a month stepper needs its two chevrons to clear the title
            if row.navBack != nil { w += navZone * 2 }
            if row.slider != nil { w = max(w, 150) }
            width = max(width, w)
        }
        return NSSize(width: width, height: height)
    }

    func measure() -> NSSize {
        let left = columnSize(rows)
        // one column keeps upstream's trailing air; two columns spend it on
        // the gap between them instead
        guard !sideRows.isEmpty else {
            return NSSize(width: left.width + popupPad * 2 + 20,
                          height: left.height + popupPad * 2)
        }
        let right = columnSize(sideRows)
        return NSSize(width: left.width + popupColumnGap + right.width + popupPad * 2 + 8,
                      height: max(left.height, right.height) + popupPad * 2)
    }

    // where the left column ends inside `bounds` — the divider and the right
    // column hang off it, and draw() and measure() must agree on it
    func leftColumnWidth() -> CGFloat {
        sideRows.isEmpty ? bounds.width - popupPad * 2 : columnSize(rows).width
    }

    override func draw(_ dirtyRect: NSRect) {
        rowRects.removeAll()
        // plain fill: the scroll CONTAINER carries the rounded clip and the
        // accent border, so the corners stay put while tall content scrolls
        palette.barBG.setFill()
        bounds.fill()

        let inner = bounds.insetBy(dx: popupPad, dy: popupPad)
        let left = NSRect(x: inner.minX, y: inner.minY,
                          width: leftColumnWidth(), height: inner.height)
        drawColumn(rows, in: left)
        guard !sideRows.isEmpty else { return }
        // the hairline states the split without boxing either half in
        palette.muted.withAlphaComponent(0.35).setFill()
        NSRect(x: left.maxX + popupColumnGap / 2 - 0.5, y: inner.minY + 3,
               width: 1, height: inner.height - 6).fill()
        drawColumn(sideRows, in: NSRect(x: left.maxX + popupColumnGap, y: inner.minY,
                                        width: inner.maxX - (left.maxX + popupColumnGap),
                                        height: inner.height))
    }

    // rows stack downward from the column's top edge; every column lays out
    // the same way, so a popup with two of them has no second code path
    func drawColumn(_ rows: [PopupRow], in area: NSRect) {
        var y = area.maxY
        for row in rows {
            let h = height(row)
            y -= h
            let rect = NSRect(x: area.minX, y: y, width: area.width, height: h)
            rowRects.append((row, rect))
            let hovered = row.action != nil && rect == hoveredRect

            if row.rule {
                palette.muted.withAlphaComponent(0.4).setFill()
                NSRect(x: rect.minX + 2, y: rect.midY, width: rect.width - 4, height: 1).fill()
                continue
            }
            if row.highlight || hovered {
                // ITEM_BG is within a hair of BAR_BG_SOLID under rose-pine, so
                // the old block was invisible there; a wash of the accent is
                // visible under every theme and cannot collide with the text
                palette.accent.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: 2), xRadius: 5, yRadius: 5).fill()
            }
            if let card = row.card {
                drawCard(card, in: rect)
                continue
            }
            if let trend = row.trend {
                drawTrend(trend, in: rect)
                continue
            }
            if let fund = row.fund {
                drawFund(fund, in: rect)
                continue
            }
            if let cells = row.cells {
                drawWeek(cells, in: rect, row: row)
                continue
            }
            if row.navBack != nil || row.navForward != nil {
                drawNav(row, in: rect)
                continue
            }
            var x = rect.minX + 4
            if let image = row.image {
                image.draw(in: NSRect(x: x, y: rect.midY - 8, width: 16, height: 16))
                x += 22
            }
            if !row.icon.isEmpty {
                // same strategy as the bar: glyphs centre on ink, text on
                // cap height — one way of placing things in this file
                let iconFont = self.iconFont(row)
                let w = row.iconColumn ?? inkBox(row.icon, iconFont).width
                // a fixed column left-aligns its text; an ink-sized one keeps
                // upstream's centred glyph
                if row.iconColumn != nil {
                    drawText(row.icon, iconFont, iconColor(row), leftAt: x, midY: rect.midY)
                } else {
                    drawIcon(row.icon, iconFont, iconColor(row),
                             centeredIn: NSRect(x: x, y: rect.minY, width: w, height: rect.height))
                }
                x += w + 8
            }
            if let value = row.slider {
                // track, then filled portion — the readout is the row's text
                let trackW = rect.width - (x - rect.minX) - 52
                let track = NSRect(x: x, y: rect.midY - 3, width: trackW, height: 6)
                palette.itemBG.setFill()
                NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
                palette.accent.setFill()
                NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY,
                                                 width: track.width * CGFloat(value), height: track.height),
                             xRadius: 3, yRadius: 3).fill()
                drawText(row.text, font(row), color(row),
                         leftAt: rect.maxX - advance(row.text, font(row)) - 4, midY: rect.midY)
            } else {
                drawText(row.text, font(row), hovered ? palette.accent : color(row),
                         leftAt: x, midY: rect.midY)
                if !row.detail.isEmpty {
                    let df = detailFont()
                    drawText(row.detail, df, palette.label.withAlphaComponent(0.5),
                             leftAt: rect.maxX - advance(row.detail, df) - 4, midY: rect.midY)
                }
            }
        }
    }

    // Today, on its own ground: the glyph gets a whole left bay and the
    // reading stacks beside it, big number first. Nothing here is a row of
    // icon + text — that shape is exactly what made the old panel read as a
    // list in which today was just the first line.
    func drawCard(_ card: WeatherCard, in rect: NSRect) {
        palette.accent.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        let bay = NSRect(x: rect.minX, y: rect.minY, width: 78, height: rect.height)
        drawIcon(card.glyph, nerdFont("Bold", 42), palette.accent, centeredIn: bay)
        let x = bay.maxX
        let tempFont = nerdFont("Bold", 30)
        drawText(card.temp, tempFont, palette.label, leftAt: x, midY: rect.maxY - 34)
        // today's range rides the big number's baseline shoulder: it is the
        // same fact at a tenth the weight
        drawText(card.range, nerdFont("Regular", 12), palette.muted,
                 leftAt: x + advance(card.temp, tempFont) + 8, midY: rect.maxY - 28)
        drawText(card.desc, nerdFont("Bold", 13), palette.accent, leftAt: x, midY: rect.maxY - 63)
        drawText(card.detail, nerdFont("Regular", 11.5), palette.muted,
                 leftAt: x, midY: rect.minY + 17)
    }

    // name | curve | rate | profit on fixed columns; numbers right-aligned so
    // every digit column lines up. Curve is min–max scaled per row and tinted
    // by whether the window ended above where it started.
    func drawFund(_ line: FundLine, in rect: NSRect) {
        let numFont = nerdFont(line.total ? "Bold" : "Regular", 12.5)
        let tone: NSColor
        switch line.rate {
        case .some(let r) where r > 0.005: tone = palette.green
        case .some(let r) where r < -0.005: tone = palette.red
        default: tone = palette.muted
        }
        var x = rect.minX + 4
        let nameFont = nerdFont(line.total ? "Bold" : "Regular", 13)
        var name = line.name
        while name.count > 1 && advance(name, nameFont) > fundNameWidth - 4 { name.removeLast() }
        if name != line.name { name += "\u{2026}" }
        drawText(name, nameFont, line.total ? palette.accent : palette.label, leftAt: x, midY: rect.midY)
        x += fundNameWidth + fundColumnGap

        if line.spark.count >= 2, let lo = line.spark.min(), let hi = line.spark.max() {
            let box = NSRect(x: x, y: rect.minY + 6, width: fundSparkWidth, height: rect.height - 12)
            let span = hi - lo
            let pts = line.spark.enumerated().map { i, v -> NSPoint in
                let t = span > 0 ? CGFloat((v - lo) / span) : 0.5
                return NSPoint(x: box.minX + box.width * CGFloat(i) / CGFloat(line.spark.count - 1),
                               y: box.minY + box.height * t)
            }
            let rising = line.spark.last! >= line.spark.first!
            let ink = rising ? palette.green : palette.red
            let area = NSBezierPath()
            area.move(to: NSPoint(x: pts[0].x, y: box.minY))
            pts.forEach { area.line(to: $0) }
            area.line(to: NSPoint(x: pts.last!.x, y: box.minY))
            area.close()
            ink.withAlphaComponent(0.14).setFill()
            area.fill()
            let path = NSBezierPath()
            path.move(to: pts[0])
            pts.dropFirst().forEach { path.line(to: $0) }
            path.lineWidth = 1.3
            path.lineJoinStyle = .round
            ink.setStroke()
            path.stroke()
            let end = pts.last!
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4)).fill()
        } else {
            drawText("\u{2014}", numFont, palette.muted, leftAt: x + fundSparkWidth / 2 - 4, midY: rect.midY)
        }
        x += fundSparkWidth + fundColumnGap

        let rateText = line.rate.map { String(format: "%+.2f%%", $0) } ?? "\u{2014}"
        drawText(rateText, numFont, tone,
                 leftAt: x + fundRateWidth - advance(rateText, numFont), midY: rect.midY)
        x += fundRateWidth + fundColumnGap
        let profitText = line.rate == nil ? "\u{2014}" : String(format: "%+.2f", line.profit)
        drawText(profitText, numFont, tone,
                 leftAt: x + fundProfitWidth - advance(profitText, numFont), midY: rect.midY)
    }

    // One forecast day: name, its glyph, then the bar that is the point of
    // the tail — a span drawn on the column's shared temperature window, so
    // a warming week slopes right and a cold snap punches left.
    func drawTrend(_ day: TrendDay, in rect: NSRect) {
        let fade = day.fade
        drawText(day.name, nerdFont("Regular", 12), palette.label.withAlphaComponent(fade),
                 leftAt: rect.minX + 2, midY: rect.midY)
        let bay = NSRect(x: rect.minX + 42, y: rect.minY, width: 20, height: rect.height)
        drawIcon(day.glyph, nerdFont("Bold", 13), palette.accent.withAlphaComponent(fade),
                 centeredIn: bay)
        let text = "\(day.low)~\(day.high)°"
        let textFont = nerdFont("Regular", 11.5)
        let textW = advance(text, textFont)
        drawText(text, textFont, palette.muted, leftAt: rect.maxX - textW, midY: rect.midY)
        let trackX = bay.maxX + 8
        let trackW = rect.maxX - textW - 10 - trackX
        guard trackW > 24, day.span > 0 else { return }
        let track = NSRect(x: trackX, y: rect.midY - 3, width: trackW, height: 6)
        palette.muted.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let lo = CGFloat((Double(day.low) - day.spanLow) / day.span)
        let hi = CGFloat((Double(day.high) - day.spanLow) / day.span)
        // a flat day would otherwise draw a zero-width sliver and vanish
        let fill = NSRect(x: track.minX + track.width * lo, y: track.minY,
                          width: max(6, track.width * (hi - lo)), height: track.height)
        // never all the way to yellow: the accent has to stay the family the
        // bar belongs to, whichever of the five themes is loaded
        let tint = palette.accent.blended(withFraction: day.warmth * 0.7, of: palette.yellow)
            ?? palette.accent
        tint.withAlphaComponent(fade).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
    }

    // seven fixed columns, so the header letters, every week and the next
    // month all line up on the same grid
    func drawWeek(_ cells: [CalendarCell], in rect: NSRect, row: PopupRow) {
        let f = font(row)
        let w = cellWidth(f)
        for (i, cell) in cells.enumerated() {
            let box = NSRect(x: rect.minX + 4 + CGFloat(i) * w, y: rect.minY, width: w, height: rect.height)
            if cell.today {
                // solid accent with the popup's own background as the ink:
                // the one place a filled block is worth it, and it reads under
                // a light accent (rose-pine) and a mid one (osaka-jade) alike
                palette.accent.setFill()
                NSBezierPath(roundedRect: box.insetBy(dx: 2, dy: 3), xRadius: 5, yRadius: 5).fill()
            }
            let tint = cell.today ? palette.barBG
                : (cell.inMonth ? color(row) : palette.muted.withAlphaComponent(0.5))
            drawText(cell.text, cell.today ? nerdFont("Bold", f.pointSize) : f, tint, centeredIn: box)
        }
    }

    // ‹ title › — the title stays centred over the grid below it and the two
    // chevrons sit in the fixed-width zones mouseUp() tests against
    func drawNav(_ row: PopupRow, in rect: NSRect) {
        let box = navRect(rect)
        let glyphFont = nerdFont("Bold", 15)
        drawText(row.text, font(row), color(row), centeredIn: box)
        if row.navBack != nil {
            drawIcon(chevronLeft, glyphFont, palette.accent,
                     centeredIn: NSRect(x: box.minX, y: box.minY, width: navZone, height: box.height))
        }
        if row.navForward != nil {
            drawIcon(chevronRight, glyphFont, palette.accent,
                     centeredIn: NSRect(x: box.maxX - navZone, y: box.minY,
                                        width: navZone, height: box.height))
        }
    }


    // Tracking areas, not a poll and not a global monitor: a global
    // monitor stops delivering once this app is itself active, which is
    // exactly what clicking the bar makes it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = rowRects.first(where: { $0.1.contains(p) && $0.0.action != nil })?.1
        if hit != hoveredRect { hoveredRect = hit; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredRect != nil { hoveredRect = nil; needsDisplay = true }
        scheduleHullCheck()
    }

    private func slide(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let (row, rect) = rowRects.first(where: { $0.1.contains(p) }),
              row.slider != nil, let onSlide = row.onSlide else { return }
        let trackX = rect.minX + 4
        let trackW = rect.width - 4 - 52
        onSlide(min(1, max(0, (p.x - trackX) / trackW)))
    }

    override func mouseDown(with event: NSEvent) { slide(event) }
    override func mouseDragged(with event: NSEvent) { slide(event) }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let (row, rect) = rowRects.first(where: { $0.1.contains(p) }),
              row.slider == nil else { return }
        // a nav row splits by geometry, like a slider does: left edge steps
        // back, right edge steps forward, the title between them does nothing
        if row.navBack != nil || row.navForward != nil {
            let box = navRect(rect)
            if p.x <= box.minX + navZone {
                row.navBack?()
            } else if p.x >= box.maxX - navZone, p.x <= box.maxX {
                row.navForward?()
            }
            return
        }
        row.action?()
    }
}

final class PopupWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

var popupWindow: PopupWindow?
var popupView: PopupView?
var openPopup: String? // which bar item owns it
// The display the open popup belongs to, as a display id and not a BarSurface:
// surfaces are rebuilt on a screen change and the reference would dangle.
var openPopupDisplay: CGDirectDisplayID?

func closePopup() {
    popupWindow?.orderOut(nil)
    popupWindow = nil
    popupView = nil
    openPopup = nil
    openPopupDisplay = nil
}

// rows are rebuilt, not patched: the content is cheap to regenerate and a
// stale row is worse than a redrawn one
// exact-fit on every refresh: grow-only left the app-menu popup huge
// after backing out of a long menu. The window is bottom-anchored, so
// the frame is recomputed to keep the TOP edge pinned under the bar.
var popupTopY: CGFloat = 0
var popupAnchorX: CGFloat = 0
var popupAlignLeft = false

func refreshPopup() {
    guard let name = openPopup, let view = popupView, let window = popupWindow else { return }
    view.rows = popupRows(for: name)
    view.sideRows = popupSideRows(for: name)
    let size = view.measure()
    let screen = window.screen ?? NSScreen.main
    var winH = size.height
    var x = popupAlignLeft ? popupAnchorX : popupAnchorX - size.width
    if let screen {
        winH = min(size.height, popupTopY - screen.frame.minY - 20)
        x = min(max(screen.frame.minX + 6, x), screen.frame.maxX - size.width - 6)
    }
    window.setFrame(NSRect(x: x, y: popupTopY - winH,
                           width: size.width, height: winH), display: false)
    (window.contentView as? NSScrollView)?.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: winH))
    view.frame = NSRect(origin: .zero, size: size)
    view.scroll(NSPoint(x: 0, y: max(0, size.height - winH))) // drilling resets to the top
    view.needsDisplay = true
    view.display()
}

func showPopup(_ name: String, under anchor: NSRect, on surface: BarSurface, alignLeft: Bool = false) {
    if openPopup == name { closePopup(); return }
    closePopup()
    calendarMonthStep = 0 // a fresh open is always this month
    let rows = popupRows(for: name)
    guard !rows.isEmpty else { return }

    let view = PopupView(frame: .zero)
    view.rows = rows
    view.sideRows = popupSideRows(for: name)
    let size = view.measure()
    view.frame = NSRect(origin: .zero, size: size)

    // right-aligned under the item, clamped to the screen it opened on;
    // taller-than-screen content (Recent Items) scrolls inside a capped
    // window instead of running off the display
    let screen = surface.screen
    let barBottom = surface.window.frame.minY
    popupTopY = barBottom - 4
    popupAnchorX = alignLeft ? anchor.minX : anchor.maxX
    popupAlignLeft = alignLeft
    let winH = min(size.height, popupTopY - screen.frame.minY - 20)
    var x = alignLeft ? anchor.minX : anchor.maxX - size.width
    x = min(max(screen.frame.minX + 6, x), screen.frame.maxX - size.width - 6)
    let window = PopupWindow(contentRect: NSRect(x: x, y: popupTopY - winH,
                                                 width: size.width, height: winH),
                             styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.acceptsMouseMovedEvents = true
    let scroll = NSScrollView(frame: NSRect(origin: .zero, size: NSSize(width: size.width, height: winH)))
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    scroll.documentView = view
    scroll.wantsLayer = true
    scroll.layer?.cornerRadius = popupRadius
    scroll.layer?.masksToBounds = true
    scroll.layer?.borderWidth = 1
    // the frame states the popup's edge without shouting it: a full-strength
    // accent hairline read as a second highlight next to the rows it contains
    scroll.layer?.borderColor = palette.accent.withAlphaComponent(0.45).cgColor
    window.contentView = scroll
    view.scroll(NSPoint(x: 0, y: max(0, size.height - winH))) // start at the top
    window.orderFrontRegardless()
    popupWindow = window
    popupView = view
    openPopup = name
    openPopupDisplay = screenID(screen)
}

// --- popup content ---------------------------------------------------------

// How many months the OPEN clock popup has been stepped away from this one.
// It belongs to the popup, not to the bar: showPopup() clears it, so the
// calendar always opens on the current month and the stepping never outlives
// the window it happened in.
var calendarMonthStep = 0

func calendarRows() -> [PopupRow] {
    var rows: [PopupRow] = []
    let now = Date()
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2 // Monday, like the shell version
    guard let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
          let monthStart = cal.date(byAdding: .month, value: calendarMonthStep, to: thisMonth),
          let range = cal.range(of: .day, in: .month, for: monthStart) else { return rows }
    let shown = cal.dateComponents([.year, .month], from: monthStart)

    // the title says which month is on screen, and it is the stepper itself
    var title = PopupRow(text: "\(shown.year ?? 0)年\(shown.month ?? 0)月", hero: true)
    title.navBack = { calendarMonthStep -= 1; refreshPopup() }
    title.navForward = { calendarMonthStep += 1; refreshPopup() }
    rows.append(title)

    var head = PopupRow(dim: true)
    head.cells = ["一", "二", "三", "四", "五", "六", "日"].map { CalendarCell(text: $0, inMonth: true) }
    rows.append(head)

    // today is only a day of THIS month; stepping away simply stops matching
    let onThisMonth = cal.isDate(monthStart, equalTo: thisMonth, toGranularity: .month)
    let today = cal.component(.day, from: now)
    // weekday index with Monday = 0
    let leading = (cal.component(.weekday, from: monthStart) + 5) % 7
    let prevDays = cal.range(of: .day, in: .month,
                             for: cal.date(byAdding: .month, value: -1, to: monthStart)!)!.count

    var cells: [CalendarCell] = []
    for i in 0..<leading {
        cells.append(CalendarCell(text: "\(prevDays - leading + 1 + i)", inMonth: false))
    }
    for d in range {
        cells.append(CalendarCell(text: "\(d)", inMonth: true, today: onThisMonth && d == today))
    }
    // always six weeks: a 5-week month next to a 6-week one would resize the
    // popup on every step, and the stepper is a thing you hold down
    var next = 1
    while cells.count < 42 { cells.append(CalendarCell(text: "\(next)", inMonth: false)); next += 1 }

    for week in stride(from: 0, to: cells.count, by: 7) {
        var row = PopupRow()
        row.cells = Array(cells[week..<week + 7])
        rows.append(row)
    }
    if onThisMonth {
        rows.append(PopupRow(text: "第 \(cal.component(.weekOfYear, from: now)) 周", dim: true))
    } else {
        rows.append(PopupRow(text: "回到本月", dim: true,
                             action: { calendarMonthStep = 0; refreshPopup() }))
    }
    return rows
}

func brightnessRows() -> [PopupRow] {
    var value: Float = 0
    guard DSGetBrightness(builtinDisplayID(), &value) == 0 else { return [] }
    var rows = [
        PopupRow(icon: "󰃟", text: "\(Int((value * 100).rounded()))%",
                 slider: Double(value),
                 onSlide: { fraction in
                     _ = DSSetBrightness(builtinDisplayID(), Float(fraction))
                     updateBrightness()
                 }),
        PopupRow(icon: "\u{F0594}", text: "\(Int((shade * 100).rounded()))%",
                 slider: shade,
                 onSlide: { setShade($0) }),
    ]
    // read in process, every time the rows are built: the row says what
    // CoreBrightness says now, and a Mac without night shift gets no row
    // rather than a lying one
    if let ns = blueLightStatus(), ns.available.boolValue {
        let on = ns.enabled.boolValue
        rows.append(PopupRow(text: "night shift \(on ? "on" : "off")", action: {
            setNightShift(!on)
            refreshPopup()
        }))
    }
    rows.append(PopupRow(text: "display settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
        closePopup()
    }))
    return rows
}

func volumeRows() -> [PopupRow] {
    guard let v = readVolume() else { return [] }
    var rows: [PopupRow] = [
        PopupRow(icon: v.muted ? "󰝟" : "󰕾", text: v.muted ? "mute" : "\(v.percent)%",
                 slider: Double(v.percent) / 100,
                 onSlide: { fraction in
                     writeVolume(Int((fraction * 100).rounded()))
                     updateVolume()
                 }),
    ]
    // output devices, current one marked — the same list `omacosy-helper
    // audio` offers, read here without the round trip
    let current = defaultOutputDevice()
    for device in audioOutputDevices() {
        rows.append(PopupRow(icon: device.id == current ? "󰄬" : " ", text: device.name,
                             highlight: device.id == current,
                             action: {
                                 setDefaultOutputDevice(device.id)
                                 updateVolume()
                                 refreshPopup()
                             }))
    }
    rows.append(PopupRow(text: "sound settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        closePopup()
    }))
    return rows
}

// SCDynamicStore answers both in process. The popup used to fork
// ipconfig on the click path just for the address — and the router,
// the one number you actually want when the network misbehaves, was
// never shown at all.
func wifiIPv4() -> (ip: String, router: String) {
    guard let store = SCDynamicStoreCreate(nil, "omacosy-bar-ipv4" as CFString, nil, nil)
    else { return ("", "") }
    let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
        as? [String: Any]
    let iface = SCDynamicStoreCopyValue(store,
        "State:/Network/Interface/\(wifiDevice)/IPv4" as CFString) as? [String: Any]
    return ((iface?["Addresses"] as? [String])?.first ?? "",
            global?["Router"] as? String ?? "")
}

// Name only what is certain — the generic personal/enterprise cases
// cover several generations and guessing one would be a lie.
func securityName(_ s: CWSecurity) -> String? {
    switch s {
    case .none: return "open"
    case .WEP, .dynamicWEP: return "WEP"
    case .wpaPersonal, .wpaPersonalMixed, .wpaEnterprise, .wpaEnterpriseMixed: return "WPA"
    case .wpa2Personal, .wpa2Enterprise: return "WPA2"
    case .wpa3Personal, .wpa3Enterprise, .wpa3Transition: return "WPA3"
    case .OWE, .oweTransition: return "OWE"
    default: return nil
    }
}

func wifiRows() -> [PopupRow] {
    let interface = CWWiFiClient.shared().interface()
    var rows: [PopupRow] = [
        // the SSID is location-sensitive data: it needs the Location
        // grant AND a bundled binary (measured on macOS 26.3 — an
        // unbundled build reads nil however it is authorised), which
        // is why the bar ships inside a .app. See install.sh.
        PopupRow(text: interface?.ssid() ?? "wi-fi", hero: true),
    ]
    let net = wifiIPv4()
    rows.append(PopupRow(text: "ip \(net.ip.ifEmpty("none"))"))
    if !net.router.isEmpty { rows.append(PopupRow(text: "router \(net.router)")) }
    if let rssi = interface?.rssiValue(), rssi != 0 {
        let verdict = rssi >= -55 ? "excellent" : (rssi >= -67 ? "good" : (rssi >= -75 ? "fair" : "weak"))
        rows.append(PopupRow(text: "signal \(rssi) dBm  \(verdict)"))
    }
    // how fast, and how safe — the two questions the old rows left open
    var link: [String] = []
    if let rate = interface?.transmitRate(), rate > 0 { link.append("\(Int(rate)) Mbps") }
    if let sec = interface?.security(), let name = securityName(sec) { link.append(name) }
    if !link.isEmpty { rows.append(PopupRow(text: "link " + link.joined(separator: "  "))) }
    if let channel = interface?.wlanChannel() {
        // a bare channel number means nothing to most people; the band
        // is what says "you are on the fast radio"
        var parts = ["channel \(channel.channelNumber)"]
        switch channel.channelBand {
        case .band2GHz: parts.append("2.4 GHz")
        case .band5GHz: parts.append("5 GHz")
        case .band6GHz: parts.append("6 GHz")
        default: break
        }
        switch channel.channelWidth {
        case .width20MHz: parts.append("20 MHz")
        case .width40MHz: parts.append("40 MHz")
        case .width80MHz: parts.append("80 MHz")
        case .width160MHz: parts.append("160 MHz")
        default: break
        }
        rows.append(PopupRow(text: parts.joined(separator: "  ")))
    }
    rows.append(PopupRow(text: "network settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
        closePopup()
    }))
    return rows
}

func bluetoothRows() -> [PopupRow] {
    var rows: [PopupRow] = [PopupRow(text: "bluetooth", hero: true)]
    guard CBCentralManager.authorization == .allowedAlways else {
        rows.append(PopupRow(text: "no permission in this launch context", dim: true))
        return rows
    }
    for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
        let name = device.name ?? device.addressString ?? "device"
        rows.append(PopupRow(icon: device.isConnected() ? "󰂱" : "󰂯", text: name,
                             highlight: device.isConnected(),
                             action: {
                                 if device.isConnected() { device.closeConnection() } else { device.openConnection() }
                                 updateBluetooth()
                                 refreshPopup()
                             }))
    }
    rows.append(PopupRow(text: "bluetooth settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        closePopup()
    }))
    return rows
}

func weatherRows() -> [PopupRow] {
    guard let w = weather else { return [] }
    var rows: [PopupRow] = [PopupRow(text: "\(w.emoji) \(w.temp)\(w.tempUnit) \(w.desc)", hero: true)]

    // feels-like earns a mention only when it differs from the real temp
    var today = "today \(w.low)° → \(w.high)\(w.tempUnit)"
    if w.feels != w.temp { today = "feels \(w.feels)\(w.tempUnit) · " + today }
    rows.append(PopupRow(text: today))
    rows.append(PopupRow(text: "wind \(w.wind) · humidity \(w.humidity)%"))
    if !w.rain.isEmpty { rows.append(PopupRow(text: w.rain)) }
    if !w.sunrise.isEmpty {
        rows.append(PopupRow(text: "sun \(w.sunrise) → \(w.sunset) · \(w.moon)"))
    }
    if !w.location.isEmpty { rows.append(PopupRow(text: w.location, dim: true)) }
    return rows
}

// The system menu the hidden native menu bar used to carry, plus the two
// omacosy actions. "Reload Bar" has no counterpart here on purpose: there
// is no config to re-read, the theme is watched, and a row that did
// nothing would be worse than a row that is absent.
func appleRows() -> [PopupRow] {
    func settings(_ pane: String) -> () -> Void {
        { NSWorkspace.shared.open(URL(string: pane)!); closePopup() }
    }
    func run(_ launch: String, _ args: [String]) -> () -> Void {
        {
            closePopup()
            DispatchQueue.global(qos: .userInitiated).async { _ = shell(launch, args) }
        }
    }
    func systemEvents(_ verb: String) -> () -> Void {
        run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to \(verb)"])
    }
    return [
        PopupRow(text: "About This Mac", hero: true,
                 action: settings("x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension")),
        PopupRow(text: "System Settings…", action: run("/usr/bin/open", ["-a", "System Settings"])),
        // same launch as the activity pill's click, so that pill can be hidden
        PopupRow(text: "Activity Monitor (btop)",
                 action: run("/usr/bin/open",
                             ["-na", terminalApp, "--args", "--title=omacosy-activity", "-e", btopBinary()])),
        // pmset displaysleepnow only darkens the panel — whether that
        // locks depends on the screenLock delay, so it usually did not
        PopupRow(text: "Lock Screen",
                 action: run("\(NSHomeDirectory())/.local/bin/omacosy-helper", ["lock"])),
        PopupRow(text: "Sleep", action: run("/usr/bin/pmset", ["sleepnow"])),
        PopupRow(text: "Restart…", action: systemEvents("restart")),
        PopupRow(text: "Shut Down…", action: systemEvents("shut down")),
        PopupRow(text: "Next Theme", dim: true,
                 action: run("\(NSHomeDirectory())/.local/bin/theme-next", [])),
    ]
}

// a hairline between two sections of one popup — cheaper to read than the
// blank row a shell popup would have used, and it carries no content
func dividerRow() -> PopupRow {
    var row = PopupRow()
    row.rule = true
    return row
}

// two sections joined into one popup keep a rule between them; a joint with
// nothing on the far side keeps no rule
func joined(_ first: [PopupRow], _ second: [PopupRow]) -> [PopupRow] {
    guard !first.isEmpty, !second.isEmpty else { return first + second }
    return first + [dividerRow()] + second
}

func popupRows(for name: String) -> [PopupRow] {
    switch name {
    case "apple": return appleMenuRows()
    // weather follows the calendar so the weather pill can be hidden without
    // losing the forecast; weatherRows() opens with its own hero title row,
    // which is the section break
    // the weather has its own COLUMN now (popupSideRows); it only stacks
    // under the calendar when there is no panel to put beside it
    case "clock":
        if !popupSideRows(for: "clock").isEmpty { return calendarRows() }
        return joined(calendarRows(), openMeteoConfigured() ? (openMeteoRows ?? []) : weatherRows())
    case "weather": return weatherRows()
    case "fission": return fissionRows()
    case "ai": return aiRows()
    case "brightness": return brightnessRows()
    // bluetooth follows the output devices so the pill can be hidden
    // without losing the paired-device menu; bluetoothRows() opens with
    // its own hero title row, which is the section break
    case "volume": return joined(volumeRows(), bluetoothRows())
    case "wifi": return wifiRows()
    case "bluetooth": return bluetoothRows()
    case "appmenu": return appMenuRows()
    default: return []
    }
}

// The right-hand column of a split popup. Only the clock has one, and only
// once the Open-Meteo panel has been parsed: an unconfigured or not-yet-
// fetched weather leaves the popup single-column, exactly as before.
func popupSideRows(for name: String) -> [PopupRow] {
    guard name == "clock" else { return [] }
    return weatherPanelRows()
}

// The focused app's menu bar, read over Accessibility and rendered
// INSIDE our popup: top level lists File/Edit/…, clicking drills into
// that menu's actual items, and clicking a leaf performs its AXPress —
// the command runs with no native menu ever appearing. A navigation
// stack lives for the popup's lifetime; "‹" walks back up.
var appMenuStack: [(title: String, element: AXUIElement)] = []

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &ref) == .success,
          let children = ref as? [AXUIElement] else { return [] }
    return children
}

private func axString(_ element: AXUIElement, _ attr: String) -> String {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return "" }
    return ref as? String ?? ""
}

// one menu's items as popup rows — shared by the app drill-down and the
// apple pill. A menu bar item wraps one AXMenu; the items live inside.
// AXEnabled is a lie for closed menus: apps validate items lazily when
// a menu OPENS, so unopened menus read mostly disabled (Arc's whole
// Tabs menu greyed out). Render all leaves live; a truly disabled
// item's AXPress just no-ops.
// Recent Items: AX exposes no menu-item images, but its entries are
// apps and documents whose icons Launch Services can resolve by name —
// the section headers ("Applications"/"Documents"/"Servers") say which
// strategy applies. Headers render dim, entries get real icons.
func recentItemIcon(_ title: String, section: String) -> NSImage? {
    if section == "Applications" {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == title }),
           let icon = app.icon { return icon }
        if let path = NSWorkspace.shared.fullPath(forApplication: title) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
    if section == "Documents" {
        let ext = (title as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
    return nil
}

func rowsForMenu(_ element: AXUIElement, context: String = "",
                 collapseAlternates: Bool = false) -> [PopupRow] {
    let container = axChildren(element).first ?? element
    var rows: [PopupRow] = []
    var section = ""
    var prevTitle = ""
    let recents = context == "Recent Items"
    for item in axChildren(container) {
        let title = axString(item, "AXTitle")
        if title.isEmpty {
            if rows.last?.rule != true { rows.append(dividerRow()) }
            prevTitle = ""
            continue
        }
        // the Apple menu carries hold-Option ALTERNATES ("Restart…" then
        // "Restart", "Force Quit…" then "Force Quit Arc") that the native
        // menu hides — AX enumerates them flat. An item whose title
        // extends its predecessor's (ellipsis stripped) is the alternate.
        if collapseAlternates, !prevTitle.isEmpty {
            let base = prevTitle.replacingOccurrences(of: "…", with: "")
            if title.hasPrefix(base) { continue }
        }
        prevTitle = title
        // Recent Items' own hold-Option alternates ("Show X in Finder")
        // carry a different title shape than the root menu's (English UI;
        // the pattern is locale-bound, worst case they reappear)
        if recents, title.hasPrefix("Show “"), title.hasSuffix("” in Finder") { continue }
        if recents, ["Applications", "Documents", "Servers"].contains(title) {
            section = title
            rows.append(PopupRow(text: title, dim: true))
            continue
        }
        if !axChildren(item).isEmpty {
            rows.append(PopupRow(icon: "›", text: title, action: {
                appMenuStack.append((title, item))
                refreshPopup()
            }))
        } else {
            let cmd = axString(item, "AXMenuItemCmdChar")
            rows.append(PopupRow(image: recents ? recentItemIcon(title, section: section) : nil,
                                 text: title, detail: cmd.isEmpty ? "" : "⌘\(cmd)", action: {
                closePopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    AXUIElementPerformAction(item, "AXPress" as CFString)
                }
            }))
        }
    }
    return rows
}

// the frontmost app's AX menu bar, resolved the popup-safe way
func frontAppAXMenuBar() -> AXUIElement? {
    guard !model.frontApp.isEmpty,
          let app = NSWorkspace.shared.runningApplications.first(where: {
              $0.localizedName == model.frontApp
                  && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
          })
    else { return nil }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(ax, "AXMenuBar" as CFString, &ref) == .success,
          let bar = ref, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    return (bar as! AXUIElement)
}

// The REAL Apple menu — child 0 of the front app's menu bar, the item
// the app drill-down skips — through the same drill machinery, with
// omacosy's own extras appended. Falls back to the hand-rolled rows
// when Accessibility is not granted or AX has nothing.
func appleMenuRows() -> [PopupRow] {
    guard AXIsProcessTrusted(),
          let menubar = frontAppAXMenuBar(),
          let apple = axChildren(menubar).first
    else { return appleRows() }
    if !appMenuStack.isEmpty {
        return appMenuRows()
    }
    var rows = rowsForMenu(apple, collapseAlternates: true)
    guard !rows.isEmpty else { return appleRows() }
    if rows.last?.rule != true { rows.append(dividerRow()) }
    // same launch as the activity pill's click, so that pill can be hidden —
    // the real Apple menu has no such item, so the fork appends its own
    rows.append(PopupRow(text: "Activity Monitor (btop)", action: {
        closePopup()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell("/usr/bin/open",
                      ["-na", terminalApp, "--args", "--title=omacosy-activity", "-e", btopBinary()])
        }
    }))
    rows.append(PopupRow(text: "Next Theme", dim: true, action: {
        closePopup()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell("\(NSHomeDirectory())/.local/bin/theme-next", [])
        }
    }))
    return rows
}

func appMenuRows() -> [PopupRow] {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(opts) else {
        return [PopupRow(text: "grant Accessibility to omacosy-bar", hero: true),
                PopupRow(text: "System Settings opened the pane — toggle the bar on,", dim: true),
                PopupRow(text: "then click the app name again", dim: true)]
    }
    // drilled into a menu: its items, behind a back row
    if let top = appMenuStack.last {
        var rows = [PopupRow(icon: "‹", text: top.title, highlight: true, action: {
            appMenuStack.removeLast()
            refreshPopup()
        })]
        rows.append(contentsOf: rowsForMenu(top.element, context: top.title))
        return rows
    }
    // NOT frontmostApplication: the click that opens this popup makes
    // the bar itself frontmost for a beat, and the popup bailed empty.
    // model.frontApp tracks the real app and ignores our own pid.
    guard let menubar = frontAppAXMenuBar() else {
        tlog("appmenu: no menu bar for '\(model.frontApp)'")
        return []
    }
    // no hero title: the app's name is literally the pill this popup
    // hangs from. Index 0 is the Apple menu — our apple pill's ground.
    var rows: [PopupRow] = []
    for item in axChildren(menubar).dropFirst() {
        let title = axString(item, "AXTitle")
        guard !title.isEmpty else { continue }
        rows.append(PopupRow(icon: "›", text: title, action: {
            appMenuStack.append((title, item))
            refreshPopup()
        }))
    }
    if !rows.isEmpty { rows[0].highlight = true }
    return rows
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// --- cheatsheet (Super+K) --------------------------------------------------
// Rendered from the LIVE config of whichever WM is running — aerospace.toml
// or OmniWM's settings.toml — never from a list kept here: a cheatsheet
// that can disagree with the keys is worse than no cheatsheet. The
// config's own section comments become the headings, so the grouping is
// the author's rather than a second opinion about it.

struct CheatEntry {
    let group: String
    let key: String
    let action: String
}

// "cmd-ctrl-alt-shift-1" -> "Super+Shift+1". Super IS cmd-ctrl-alt here
// (Caps Lock sends it), so it is collapsed back into the one key the
// user actually presses.
func prettyKey(_ raw: String) -> String {
    var rest = raw
    var parts: [String] = []
    if rest.hasPrefix("cmd-ctrl-alt-") {
        parts.append("Super")
        rest = String(rest.dropFirst("cmd-ctrl-alt-".count))
    }
    while let dash = rest.firstIndex(of: "-") {
        let mod = String(rest[rest.startIndex..<dash])
        guard ["shift", "ctrl", "alt", "cmd"].contains(mod) else { break }
        parts.append(mod == "cmd" ? "Cmd" : mod.capitalized)
        rest = String(rest[rest.index(after: dash)...])
    }
    parts.append(rest.count == 1 ? rest.uppercased() : rest.capitalized)
    return parts.joined(separator: "+")
}

// The command IS the description — printing it keeps this honest. Only
// the noise a reader cannot use is removed, by rule and not per binding.
func prettyAction(_ raw: String) -> String {
    var s = raw
    // the binary's directory AND its omacosy- prefix go together: doing
    // them separately rewrote /tmp/omacosy-bar-cheatsheet into a path
    // that does not exist, which is worse than the noise
    for noise in ["exec-and-forget ", "\(NSHomeDirectory())/.local/bin/omacosy-",
                  "$HOME/.local/bin/omacosy-", "\(NSHomeDirectory())/.local/bin/",
                  "$HOME/.local/bin/", "/usr/bin/", "/bin/"] {
        s = s.replacingOccurrences(of: noise, with: "")
    }
    return s.trimmingCharacters(in: .whitespaces)
}

func cheatEntries() -> [CheatEntry] {
    omniwmActive() ? omniwmCheatEntries() : aerospaceCheatEntries()
}

func aerospaceCheatEntries() -> [CheatEntry] {
    let path = "\(NSHomeDirectory())/.config/aerospace/aerospace.toml"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var entries: [CheatEntry] = []
    var group = ""
    var inSection = false
    var lastWasComment = false
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") {
            inSection = line == "[mode.main.binding]"
            continue
        }
        guard inSection else { continue }
        if line.hasPrefix("#") {
            // only the FIRST line of a comment block is a heading; the
            // rest is prose explaining why, which belongs in the config
            if !lastWasComment {
                var title = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                // "(omarchy: ...)" is a provenance note, not part of the
                // heading; a colon or full stop starts the explanation
                if let p = title.range(of: " (omarchy") { title = String(title[..<p.lowerBound]) }
                if let c = title.firstIndex(where: { $0 == ":" || $0 == "." }) {
                    title = String(title[..<c])
                }
                title = title.trimmingCharacters(in: .whitespaces)
                if title.count > 34 { title = String(title.prefix(33)) + "…" }
                group = title
            }
            lastWasComment = true
            continue
        }
        lastWasComment = false
        guard let eq = line.firstIndex(of: "="), line.first?.isLetter == true else { continue }
        let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        // read BETWEEN the quotes: a trailing `# comment` on the line is
        // config prose, not part of the command
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard let q = value.first, q == "'" || q == "\"",
            let close = value.dropFirst().firstIndex(of: q)
        else { continue }
        let action = String(value[value.index(after: value.startIndex)..<close])
        guard !key.isEmpty, !action.isEmpty else { continue }
        entries.append(CheatEntry(group: group, key: prettyKey(key), action: prettyAction(action)))
    }
    return entries
}

// "Control+Option+Command+Shift+1" -> "Super+Shift+1" — the same collapse
// prettyKey does for aerospace's cmd-ctrl-alt, in OmniWM's spelling. The
// key names arrive already capitalised; only " Arrow" is dropped, so the
// arrows read "Left" the way the aerospace sheet prints them.
func prettyOmniKey(_ raw: String) -> String {
    var rest = raw
    var parts: [String] = []
    if rest.hasPrefix("Control+Option+Command+") {
        parts.append("Super")
        rest = String(rest.dropFirst("Control+Option+Command+".count))
    }
    for comp in rest.split(separator: "+") {
        var key = String(comp)
        if key.hasSuffix(" Arrow") { key = String(key.dropLast(" Arrow".count)) }
        parts.append(key)
    }
    return parts.joined(separator: "+")
}

// "switchWorkspace.0" -> "switch workspace 1": the raw catalog ids were
// printed verbatim once, on the theory that the config's truth beats a
// pretty lie — and read as a mess (0-based suffixes beside 1-based
// keycaps, camelCase runs). The id's meaning survives; only the casing
// and indexing are translated to match the keycap next to it.
func humanizeOmniId(_ id: String) -> String {
    func words(_ s: String) -> String {
        var out = ""
        for ch in s { out.append(ch.isUppercase ? " " + String(ch).lowercased() : String(ch)) }
        return out.trimmingCharacters(in: .whitespaces)
    }
    let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
    // dwindle reality beats the catalog's niri-flavored names: moveColumn
    // is a tile SWAP there (the binding people reach for daily), and
    // plain move STACKS into the neighbor as a group
    let renamed = ["moveColumn": "swap window", "move": "stack into"]
    let head = renamed[parts[0]] ?? words(parts[0])
    guard parts.count > 1 else { return head }
    if let n = Int(parts[1]) { return "\(head) \(n + 1)" }
    switch parts[1] {
    case "decrease10Percent": return "\(head) −10%"
    case "increase10Percent": return "\(head) +10%"
    default: return "\(head) \(words(parts[1]))"
    }
}

// with the comment headings stripped by the strict-decoder rewrite, the
// sheet gets its sections from the id families instead
func omniGroup(_ id: String) -> String {
    let h = String(id.split(separator: ".").first ?? "")
    if h.lowercased().contains("workspace") { return "Workspaces" }
    if h.hasPrefix("focus") { return "Focus" }
    if h.hasPrefix("move") || h.hasPrefix("summon") { return "Move" }
    if h.contains("Span") || h.hasPrefix("resize") || h.hasPrefix("balance")
        || h.hasPrefix("cycleSize") || h.hasPrefix("set") { return "Size" }
    if h.hasPrefix("toggle") || h.contains("Layout") || h.contains("Column")
        || h.hasPrefix("preselect") || h.contains("olumn") { return "Layout & columns" }
    return "System"
}

// [[hotkeys]] tables out of OmniWM's settings.toml: a binding string and
// an action id per table, in either order.
func omniwmCheatEntries() -> [CheatEntry] {
    let path = "\(NSHomeDirectory())/.config/omniwm/settings.toml"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var entries: [CheatEntry] = []
    var group = ""
    var lastWasComment = false
    var inHotkey = false
    var binding = ""
    var id = ""
    func flush() {
        // the canonical settings file carries EVERY catalog id — most
        // Unassigned. A cheatsheet's job is what you CAN press, so the
        // ~90 unassigned rows stay out (they made the sheet a wall).
        if inHotkey, !binding.isEmpty, binding != "Unassigned", !id.isEmpty {
            entries.append(CheatEntry(
                group: group.isEmpty ? omniGroup(id) : group,
                key: prettyOmniKey(binding), action: humanizeOmniId(id)))
        }
        binding = ""
        id = ""
    }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            // a comment between tables starts the NEXT group: a complete
            // pending entry belongs to the heading it was written under,
            // not the one about to be read (a half-read table keeps its
            // keys — TOML allows comments between them)
            if !binding.isEmpty, !id.isEmpty { flush() }
            // first line of a comment block is a heading, same rule as the
            // aerospace parser — the "---" ruler decoration is trimmed off
            if !lastWasComment {
                var title = String(line.dropFirst())
                    .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                if let c = title.firstIndex(where: { $0 == ":" || $0 == "." }) {
                    title = String(title[..<c])
                }
                title = title.trimmingCharacters(in: .whitespaces)
                if title.count > 34 { title = String(title.prefix(33)) + "…" }
                group = title
            }
            lastWasComment = true
            continue
        }
        lastWasComment = false
        if line.hasPrefix("[") {
            flush()
            inHotkey = line == "[[hotkeys]]"
            continue
        }
        guard inHotkey, let eq = line.firstIndex(of: "=") else { continue }
        let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard let q = value.first, q == "'" || q == "\"",
            let close = value.dropFirst().firstIndex(of: q)
        else { continue }
        let v = String(value[value.index(after: value.startIndex)..<close])
        if key == "binding" { binding = v } else if key == "id" { id = v }
    }
    flush()
    // derived groups arrive interleaved (switch/move alternate per
    // workspace) — order them section by section, keeping in-group
    // order (index tiebreak kept explicit rather than leaning on
    // sort stability)
    let sectionOrder = ["Workspaces", "Focus", "Move", "Layout & columns", "Size", "System"]
    let indexed = entries.enumerated().map { ($0.offset, $0.element) }
    entries = indexed.sorted { a, b in
        let ga = sectionOrder.firstIndex(of: a.1.group) ?? 99
        let gb = sectionOrder.firstIndex(of: b.1.group) ?? 99
        return ga != gb ? ga < gb : a.0 < b.0
    }.map { $0.1 }
    // the exec chords live in Karabiner while OmniWM runs (its hotkeys
    // cannot exec) — the sheet must show them or half the muscle-memory
    // map is invisible. Read our own injected rules back by their
    // description prefix.
    entries.append(contentsOf: karabinerExecCheatEntries())
    return entries
}

// "omacosy-omniwm: terminal" rules out of karabiner.json — description
// carries the action, from.key_code + modifiers carry the chord
func karabinerExecCheatEntries() -> [CheatEntry] {
    let path = "\(NSHomeDirectory())/.config/karabiner/karabiner.json"
    guard let data = FileManager.default.contents(atPath: path),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let profiles = root["profiles"] as? [[String: Any]] else { return [] }
    var entries: [CheatEntry] = []
    for profile in profiles {
        guard (profile["selected"] as? Bool) ?? (profiles.count == 1),
            let cm = profile["complex_modifications"] as? [String: Any],
            let rules = cm["rules"] as? [[String: Any]] else { continue }
        for rule in rules {
            guard let desc = rule["description"] as? String,
                desc.hasPrefix("omacosy-omniwm: "),
                let manips = rule["manipulators"] as? [[String: Any]],
                let from = manips.first?["from"] as? [String: Any],
                let keyCode = from["key_code"] as? String else { continue }
            let mods = ((from["modifiers"] as? [String: Any])?["mandatory"] as? [String]) ?? []
            let hasShift = mods.contains("shift")
            let key = keyCode == "return_or_enter" ? "Enter"
                : keyCode == "spacebar" ? "Space" : keyCode.uppercased()
            let chord = "Super+" + (hasShift ? "Shift+" : "") + key
            entries.append(CheatEntry(group: "Apps and system (Karabiner)",
                key: chord, action: String(desc.dropFirst("omacosy-omniwm: ".count))))
        }
    }
    return entries
}

let cheatColumns = 3
let cheatRowH: CGFloat = 20
let cheatPad: CGFloat = 18

// the sheet takes key focus while open (the overview's pattern) so it
// can be typed into; hideCheatsheet hands focus back to the app that
// had it, so the search never costs the user their window
final class CheatWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
}

final class CheatsheetView: NSView {
    var entries: [CheatEntry] = []
    var filter = ""
    private var keyFont: NSFont { nerdFont("Bold", 12) }
    private var actFont: NSFont { nerdFont("Regular", 12) }
    private var headFont: NSFont { nerdFont("Bold", 13) }

    private func visibleEntries() -> [CheatEntry] {
        guard !filter.isEmpty else { return entries }
        let f = filter.lowercased()
        return entries.filter {
            $0.key.lowercased().contains(f) || $0.action.lowercased().contains(f)
                || $0.group.lowercased().contains(f)
        }
    }

    // rows are (heading?, entry?) laid into balanced columns
    private func rows() -> [(String?, CheatEntry?)] {
        var out: [(String?, CheatEntry?)] = []
        var seen = ""
        for e in visibleEntries() {
            if e.group != seen {
                if !out.isEmpty { out.append((nil, nil)) } // breathing room
                out.append((e.group, nil))
                seen = e.group
            }
            out.append((nil, e))
        }
        return out
    }

    private func columns() -> [[(String?, CheatEntry?)]] {
        let all = rows()
        guard !all.isEmpty else { return [] }
        let per = Int((Double(all.count) / Double(cheatColumns)).rounded(.up))
        return stride(from: 0, to: all.count, by: per).map {
            Array(all[$0..<min($0 + per, all.count)])
        }
    }

    private func columnWidths() -> [(key: CGFloat, total: CGFloat)] {
        columns().map { col in
            var k: CGFloat = 0, a: CGFloat = 0
            for (head, e) in col {
                if let head { k = max(k, advance(head, headFont)) }
                if let e {
                    k = max(k, advance(e.key, keyFont))
                    a = max(a, advance(e.action, actFont))
                }
            }
            return (k, k + 14 + a)
        }
    }

    func measure() -> NSSize {
        let cols = columns()
        guard !cols.isEmpty else { return NSSize(width: 320, height: 80) }
        let widths = columnWidths()
        let w = widths.reduce(0) { $0 + $1.total } + CGFloat(cols.count - 1) * 28
        let tallest = cols.map(\.count).max() ?? 0
        return NSSize(width: w + cheatPad * 2,
                      height: CGFloat(tallest) * cheatRowH + cheatPad * 2 + 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: popupRadius, yRadius: popupRadius)
        palette.barBG.setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = 1
        body.stroke()

        let title = filter.isEmpty
            ? "keybindings — Super is Caps Lock · type to search · Super+K, Esc or click to close"
            : "search: \(filter)▏ — \(visibleEntries().count) match\(visibleEntries().count == 1 ? "" : "es") · Esc clears"
        drawText(title, nerdFont("Bold", 12), palette.accent.withAlphaComponent(0.8),
                 leftAt: cheatPad, midY: bounds.maxY - cheatPad - 6)

        var x = cheatPad
        for (i, col) in columns().enumerated() {
            let width = columnWidths()[i]
            var y = bounds.maxY - cheatPad - 30
            for (head, e) in col {
                if let head {
                    drawText(head, headFont, palette.accent, leftAt: x, midY: y - cheatRowH / 2)
                } else if let e {
                    drawText(e.key, keyFont, palette.label, leftAt: x, midY: y - cheatRowH / 2)
                    drawText(e.action, actFont, palette.muted,
                             leftAt: x + width.key + 14, midY: y - cheatRowH / 2)
                }
                y -= cheatRowH
            }
            x += width.total + 28
        }
    }

    override func mouseDown(with event: NSEvent) { hideCheatsheet() }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // esc — clear an active search first, close on the second
            if filter.isEmpty { hideCheatsheet() } else { filter = ""; refit() }
        case 51: // backspace
            if !filter.isEmpty { filter.removeLast(); refit() }
        case 40 where event.modifierFlags.contains([.command, .control, .option]):
            hideCheatsheet() // Super+K toggles closed even while we hold key
        default:
            guard let chars = event.charactersIgnoringModifiers,
                !chars.isEmpty,
                !event.modifierFlags.contains(.command),
                chars.rangeOfCharacter(from: .alphanumerics.union(CharacterSet(charactersIn: "+- "))) != nil
            else { return }
            filter += chars
            refit()
        }
    }

    // the sheet shrinks to its matches — re-measure and keep the centre
    private func refit() {
        guard let window = window else { needsDisplay = true; return }
        let size = measure()
        let c = NSPoint(x: window.frame.midX, y: window.frame.midY)
        frame = NSRect(origin: .zero, size: size)
        window.setFrame(NSRect(x: c.x - size.width / 2, y: c.y - size.height / 2,
                               width: size.width, height: size.height), display: true)
        needsDisplay = true
    }
}

var cheatWindow: CheatWindow?
var cheatPrevApp: NSRunningApplication?

func hideCheatsheet() {
    cheatWindow?.orderOut(nil)
    cheatWindow = nil
    // hand focus back to whoever had it before the sheet took key
    cheatPrevApp?.activate()
    cheatPrevApp = nil
}

func toggleCheatsheet() {
    if cheatWindow != nil { hideCheatsheet(); return }
    let entries = cheatEntries()
    guard !entries.isEmpty else {
        tlog("cheatsheet: no bindings parsed from \(omniwmActive() ? "omniwm settings.toml" : "aerospace.toml")")
        return
    }
    let view = CheatsheetView(frame: .zero)
    view.entries = entries
    let size = view.measure()
    view.frame = NSRect(origin: .zero, size: size)
    // centred on the display holding the cursor, like every other
    // full-surface thing here
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
    let window = CheatWindow(
        contentRect: NSRect(x: screen.frame.midX - size.width / 2,
                            y: screen.frame.midY - size.height / 2,
                            width: size.width, height: size.height),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.contentView = view
    // take key so typing filters — remember the app that had focus, the
    // close path activates it again
    cheatPrevApp = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    cheatWindow = window
    tlog("cheatsheet: \(entries.count) bindings")
}

// --- view -----------------------------------------------------------------

// Text positioning, done properly.
//
// `NSString.size(withAttributes:)` returns the TYPOGRAPHIC box — advance
// width and line height — which is what you want to flow a paragraph and
// exactly wrong for centring one glyph in a pill. A glyph's ink does not
// fill its advance (Nerd Font icons carry lopsided side bearings), and a
// line box reserves descender room that digits never use. Measured on the
// live bar, that put the wifi glyph 4 px right of centre and every label
// about 1 px high.
//
// So: icons centre on their INK box, text centres on CAP HEIGHT. Cap
// height rather than ink for text because it does not move when the
// content changes — "28°C" and "8:05 PM" sit on the same baseline.
func inkBox(_ s: String, _ font: NSFont) -> CGRect {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font]))
    return CTLineGetImageBounds(line, nil) // baseline at y = 0
}

func advance(_ s: String, _ font: NSFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

// draws with `origin` as the BASELINE origin, which is the only anchor
// that means the same thing for every string
func drawLine(_ s: String, _ font: NSFont, _ color: NSColor, baseline origin: CGPoint) {
    guard !s.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: s, attributes: [.font: font, .foregroundColor: color]))
    ctx.textPosition = origin
    CTLineDraw(line, ctx)
}

// one glyph, centred on its ink in both axes
func drawIcon(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: CGRect) {
    let ink = inkBox(s, font)
    drawLine(s, font, color,
             baseline: CGPoint(x: box.midX - ink.midX, y: box.midY - ink.midY))
}

// a text run: advance-centred across, cap-height-centred down
func drawText(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: CGRect) {
    drawLine(s, font, color,
             baseline: CGPoint(x: box.midX - advance(s, font) / 2,
                               y: box.midY - font.capHeight / 2))
}

func drawText(_ s: String, _ font: NSFont, _ color: NSColor, leftAt x: CGFloat, midY: CGFloat) {
    drawLine(s, font, color, baseline: CGPoint(x: x, y: midY - font.capHeight / 2))
}

// Icons come from the running app and are cached by name: a redraw must
// not walk the process list.
var iconCache: [String: NSImage] = [:]
func appIcon(_ name: String) -> NSImage? {
    if let cached = iconCache[name] { return cached }
    guard let icon = NSWorkspace.shared.runningApplications
        .first(where: { $0.localizedName == name })?.icon else { return nil }
    iconCache[name] = icon
    return icon
}

// The bar owns the menu-bar strip, so it is as tall as the strip macOS
// draws rather than a number tuned to one release — Tahoe changed the
// height and it can change again. The strip is NOT one height for every
// display: NSMenu.menuBarHeight reports only the MAIN display's, so on a
// machine with a notched built-in and a flat external, both bars drew the
// notch's height while the external's dropdown menus unfold at its own
// shorter strip — the bar's lower edge stayed outside every menu.
//
// The Window Server keeps one Menubar window PER display, at that
// display's real strip height, and keeps it in the window list even while
// the native bar is auto-hidden, which is the state macos-defaults.sh
// puts it in and where visibleFrame and safeAreaInsets both read 0.
// Auto-hidden, the window sits slid just ABOVE the display's top edge;
// shown, just below it; the strip always touches that edge, which is the
// test — next to x and width — so a read during the slide still lands.
//
// The Window Server's own row is the one to ask, but MenuBarAgent's row
// for the same display carries the same height, so accepting either makes
// the read survive a release that moves the window's owner. The window
// NAME is not used at all: kCGWindowName is only delivered to processes
// holding Screen Recording, and the bar has no reason to ask for it.
// The heights are points already, and a scaled panel's strip measures
// more than the legacy 24 (a DELL on a scaled mode reports 30 here), so
// beyond a per-display read there is no constant worth falling back to
// except the main display's own value.
//
// The fallback read needs a main menu, and an .accessory app never
// displays one. Top-level code runs in order, so the menu is set here
// rather than with the app setup further down.
NSApplication.shared.mainMenu = NSMenu()
let barHeightFallback: CGFloat = NSApplication.shared.mainMenu?.menuBarHeight ?? 34

// Height of the menu-bar strip THIS display draws, in points.
func menuBarHeight(for screen: NSScreen) -> CGFloat {
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    let topY = primaryH - screen.frame.maxY // the display's top edge, CG space
    let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    guard let list = CGWindowListCopyWindowInfo([], kCGNullWindowID)
        as? [[String: Any]] else { return barHeightFallback }
    var agentHeight: CGFloat = 0 // MenuBarAgent's answer, used if the server's is absent
    for w in list {
        guard (w[kCGWindowLayer as String] as? Int) == menuLevel,
              let owner = w[kCGWindowOwnerName as String] as? String,
              owner == "Window Server" || owner == "MenuBarAgent",
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let width = b["Width"],
              let height = b["Height"], height > 0,
              height < screen.frame.height / 4 // a strip, not a stray window
        else { continue }
        // Slid out of view while auto-hidden (its bottom edge on the
        // display top), slid back in when shown (its top edge there), and
        // between the two mid-animation, so require the strip to touch
        // that edge rather than sit at either end of it.
        if abs(x - screen.frame.minX) < 2, abs(width - screen.frame.width) < 2,
           y <= topY + 2, y + height >= topY - 2 {
            if owner == "Window Server" { return height }
            if agentHeight == 0 { agentHeight = height }
        }
    }
    return agentHeight > 0 ? agentHeight : barHeightFallback
}

// Height of THIS display's bar. A notched display keeps the fork's notch
// alignment: the bar is the notch inset plus 4 pt, so a pill (barHeight - 8,
// centred) spans 4..inset from the screen top — a 4 pt gap above it and its
// bottom edge on the notch strip. Every other display follows its strip.
func surfaceBarHeight(for screen: NSScreen) -> CGFloat {
    let inset = screen.safeAreaInsets.top
    return inset > 0 ? inset + 4 : menuBarHeight(for: screen)
}

// Widths are unrelated to the strip and stay fixed; the heights inside
// the bar follow ITS display's strip instead, and live on BarView.
let padLeft: CGFloat = 10
let chipBox: CGFloat = 20
let chipPad: CGFloat = 2

let radius: CGFloat = 4
let gap: CGFloat = 14
// spacing between two members sharing one grouped background, in place of
// the 14 pt gap and the two 10 pt paddings a pill boundary would have cost
let groupInnerGap: CGFloat = 8

// The terminal the activity pill opens btop in. install.sh writes the
// RESOLVED choice (apps.local.conf overrides already applied) next to the
// other daemon configs, because a launchd agent cannot read the repo when
// the clone sits under ~/Documents — which is exactly where this one is.
let terminalApp: String = {
    let config = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/omacosy/apps.conf")
    guard let text = try? String(contentsOf: config, encoding: .utf8) else { return "Ghostty" }
    for line in text.split(separator: "\n") where line.hasPrefix("TERMINAL=") {
        return line.dropFirst("TERMINAL=".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
    return "Ghostty"
}()

final class BarView: NSView {
    weak var surface: BarSurface?
    var chipRects: [(String, NSRect)] = []
    var itemRects: [(String, NSRect)] = []
    var lastRectLog = ""
    var mediaRects: [(String, NSRect)] = []
    var appleRect: NSRect = .zero
    var aiRect: NSRect = .zero // the combined AI pill, when it is drawn
    // the left cluster's edge just before the media pill: what the lyric's
    // width budget is measured from. Set by draw(), read by clippedTitle.
    var mediaLeftEdge: CGFloat = 0

    // Heights inside this display's bar follow ITS strip, so a release
    // — or a second display — that moves one does not leave them adrift.
    // The offsets are the ones the fixed values had at a 34 point bar, so
    // a machine reporting 34 draws exactly what it drew before.
    private var barHeight: CGFloat { surface?.barHeight ?? barHeightFallback }
    private var pillHeight: CGFloat { barHeight - 8 }
    // The workspace chip is a SQUARE, which is what a 20x20 chipBox and a
    // 20 chipPillHeight meant at the shipped bar height. Deriving the
    // height from barHeight alone turned it into a rectangle on any
    // shorter bar and shrank the icon with it. Track chipBox instead, and
    // only give way when the bracket is too short to hold it.
    // the notched display keeps the fork's taller chip (23 on a 28 pill)
    private var chipPillHeight: CGFloat {
        surface?.notched == true ? pillHeight - 5 : min(chipBox, pillHeight - 2)
    }
    private var chipIcon: CGFloat { chipPillHeight - 2 }
    // A 4 point radius on a 20 point square reads as a rounded rectangle.
    // Roughly a quarter of the side is what makes it read as a rounded
    // square, which is the shape an app icon already is.
    private var chipRadius: CGFloat { chipPillHeight * 0.28 }

    override var isFlipped: Bool { false }

    // the media capsule: transport glyphs then the title, one pill. Its
    // width is measured, not cached — sketchybar needs an md5-keyed width
    // cache here only because it cannot measure text before laying out.
    // The capsule was measured from a glyph string with spaces in it and
    // then drawn glyph-by-glyph with different spacing, so the pill came
    // out 7 px wider than its contents. One layout, used by both.
    private func mediaGlyphs() -> [(String, String)] {
        [("prev", "󰒮"), ("play", model.media.playing ? "󰏤" : "󰐊"), ("next", "󰒭")]
    }

    // Positions first, size second: the pill is as wide as what it holds
    // plus equal padding, so the two can never disagree. Both ends measure
    // INK, so the trailing edge is not padded by a character's unused
    // advance the way the leading edge is not.
    private func mediaLayout(_ titleFont: NSFont, _ iconFont: NSFont)
        -> (width: CGFloat, glyphs: [(String, String, CGFloat, CGFloat)], titleX: CGFloat) {
        var x: CGFloat = 10
        var placed: [(String, String, CGFloat, CGFloat)] = []
        // `media-controls off`: no glyphs, so none of their spacing either —
        // the title starts at the pill's own left padding and drawMedia's
        // glyph loop, and with it every non-title mediaRects entry, is empty
        if mediaControls {
            for (name, glyph) in mediaGlyphs() {
                let w = inkBox(glyph, iconFont).width
                placed.append((name, glyph, x, w))
                x += w + 6
            }
            x += 6 // transport-to-title gap, on top of the 6 already added
        }
        let titleX = x
        let ink = inkBox(clippedTitle, titleFont)
        return (titleX + ink.maxX + 10, placed, titleX)
    }

    private func mediaSize(_ titleFont: NSFont, _ iconFont: NSFont) -> CGFloat {
        guard model.media.running, !model.media.title.isEmpty else { return 0 }
        return mediaLayout(titleFont, iconFont).width
    }

    // where the title starts inside the pill, without asking mediaLayout()
    // (which asks clippedTitle, which would be this). `media-controls off`
    // leaves only the pill's own left padding.
    private func titleOffset(_ iconFont: NSFont) -> CGFloat {
        guard mediaControls else { return 10 }
        var x: CGFloat = 10
        for (_, glyph) in mediaGlyphs() { x += inkBox(glyph, iconFont).width + 6 }
        return x + 6
    }

    // A lyric may take everything between the pill's own left edge and the
    // notch: leftBudget (auxiliaryTopLeftArea) minus where the pill starts,
    // minus the pill's trailing padding, minus 2 pt so a rounding difference
    // cannot push leftEdge past the notch. Capped at the left cluster's own
    // width so a display without a notch cannot grow it without bound.
    private func lyricWidthBudget(_ iconFont: NSFont) -> CGFloat {
        let cap: CGFloat = 665
        guard let surface, surface.notched else { return cap }
        return min(cap, surface.notchLeft - (mediaLeftEdge + gap)
                       - titleOffset(iconFont) - 10 - 2)
    }

    // The synced lyric when the daemon has a fresh line for the track this
    // pill is showing; otherwise the title, clipped exactly as upstream does.
    private var clippedTitle: String {
        if let lyric = currentLyric() {
            let budget = lyricWidthBudget(nerdFont("Bold", 14))
            let clipped = clipToWidth(lyric, nerdFont("SemiBold", 13), budget)
            if !clipped.isEmpty {
                lyricDrawn(clipped, budget: budget)
                return clipped
            }
        }
        let limit = (surface?.notched ?? false) ? 20 : 28
        let title = model.media.title
        return title.count <= limit ? title : String(title.prefix(limit - 1)) + "…"
    }

    private func drawMedia(at origin: CGFloat, _ titleFont: NSFont, _ iconFont: NSFont) {
        guard model.media.running, !model.media.title.isEmpty else { return }
        let width = mediaSize(titleFont, iconFont)
        let pill = NSRect(x: origin, y: (barHeight - pillHeight) / 2, width: width, height: pillHeight)
        palette.itemBG.setFill()
        NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()

        let layout = mediaLayout(titleFont, iconFont)
        for (name, glyph, dx, w) in layout.glyphs {
            drawIcon(glyph, iconFont, palette.label,
                     centeredIn: NSRect(x: pill.minX + dx, y: pill.minY, width: w, height: pill.height))
            mediaRects.append((name, NSRect(x: pill.minX + dx - 4, y: 0, width: w + 8, height: barHeight)))
        }
        drawText(clippedTitle, titleFont, palette.label,
                 leftAt: pill.minX + layout.titleX, midY: pill.midY)
        mediaRects.append(("title", NSRect(x: pill.minX + layout.titleX, y: 0,
                                           width: advance(clippedTitle, titleFont), height: barHeight)))
    }

    private func draw(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: NSRect) {
        drawText(s, font, color, centeredIn: box)
    }

    override func draw(_ dirtyRect: NSRect) {
        chipRects.removeAll()
        itemRects.removeAll()
        mediaRects.removeAll()
        let chipFont = nerdFont("SemiBold", 13)
        let appFont = nerdFont("Bold", 13)
        let iconFont = nerdFont("Bold", 14)
        guard let surface else { return }

        // workspace chips, in one bracket — this display's set only.
        // Undocked, force-assignment parks the GUEST set (11-19) on the
        // single display, where its empty slots would render as
        // duplicate digits — so they are hidden and an empty primary
        // keeps its slot to hold the row at 1..9. Docked, this
        // surface's list IS its own set: every slot belongs on the row,
        // and filtering left the laptop showing two lonely icons.
        let allShown = surfaces.count > 1 ? surface.workspaces
            : surface.workspaces.filter {
                $0.count == 1 || model.occupied.contains($0) || $0 == model.focused
            }
        let shown = limitWorkspaces(allShown, visible: surface.visible)
        // apple pill: the system menu the hidden native menu bar carried
        let appleGlyph = "\u{f179}"
        let appleFont = nerdFont("Bold", 15)
        // A square, like the icon-only pills at the other end. The left
        // edge stays at padLeft, so only the inner edge moves.
        let appleW = pillHeight
        let apple = NSRect(x: padLeft, y: (barHeight - pillHeight) / 2, width: appleW, height: pillHeight)
        palette.itemBG.setFill()
        NSBezierPath(roundedRect: apple, xRadius: radius, yRadius: radius).fill()
        drawIcon(appleGlyph, appleFont, palette.accent, centeredIn: apple)
        appleRect = NSRect(x: apple.minX, y: 0, width: appleW, height: barHeight)

        let bracketW = CGFloat(shown.count) * (chipBox + chipPad * 2)
        let bracket = NSRect(x: apple.maxX + 10, y: (barHeight - pillHeight) / 2,
                             width: bracketW, height: pillHeight)
        palette.itemBG.setFill()
        NSBezierPath(roundedRect: bracket, xRadius: radius, yRadius: radius).fill()

        var x = bracket.minX
        for ws in shown {
            let slot = NSRect(x: x, y: 0, width: chipBox + chipPad * 2, height: barHeight)
            let box = slot.insetBy(dx: chipPad, dy: 0)
            // each display marks the workspace IT is showing. The
            // globally focused workspace is not a useful answer on the
            // other screen's bar: docked, it never matched there and
            // the laptop had no "you are here" at all.
            if ws == surface.visible {
                let pill = NSRect(x: box.minX, y: (barHeight - chipPillHeight) / 2,
                                  width: chipBox, height: chipPillHeight)
                palette.accent.setFill()
                NSBezierPath(roundedRect: pill, xRadius: chipRadius, yRadius: chipRadius).fill()
            }
            let tint: NSColor = ws == surface.visible ? palette.barBG : palette.muted
            switch workspaceIconConfig.icon(for: ws) {
            case .some(.glyph(let glyph)):
                drawIcon(glyph, iconFont, tint, centeredIn: box)
            case .some(.image(let icon)):
                icon.draw(in: NSRect(x: box.midX - chipIcon / 2, y: (barHeight - chipIcon) / 2,
                                     width: chipIcon, height: chipIcon))
            case .some(.unavailable), .none:
                if let app = model.soleApp[ws], let icon = appIcon(app) {
                    icon.draw(in: NSRect(x: box.midX - chipIcon / 2, y: (barHeight - chipIcon) / 2,
                                         width: chipIcon, height: chipIcon))
                } else {
                    draw(String(ws.suffix(1)), chipFont, tint, centeredIn: box)
                }
            }
            chipRects.append((ws, slot))
            x += chipBox + chipPad * 2
        }

        // front-app pill — clickable: it drops the app's real menus
        var leftEdge = bracket.maxX
        appPillRect = .zero
        if !model.frontApp.isEmpty {
            let textW = advance(model.frontApp, appFont)
            let pill = NSRect(x: bracket.maxX + gap, y: (barHeight - pillHeight) / 2,
                              width: textW + 20, height: pillHeight)
            palette.itemBG.setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            draw(model.frontApp, appFont, palette.accent, centeredIn: pill)
            appPillRect = pill
            leftEdge = pill.maxX
        }

        // AI usage: one pill for both providers, on the left as the
        // captain's sketchybar has it, and the only left item with a popup
        // besides the apple menu
        aiRect = .zero
        let aiW = aiPillWidth(chipFont, iconFont)
        if aiW > 0 {
            let pill = NSRect(x: leftEdge + gap, y: (barHeight - pillHeight) / 2,
                              width: aiW, height: pillHeight)
            drawAIPill(in: pill, chipFont, iconFont)
            aiRect = NSRect(x: pill.minX, y: 0, width: aiW, height: barHeight)
            leftEdge = pill.maxX
        }

        // media: centred where there is room, in the left cluster where a
        // notch owns the middle
        mediaLeftEdge = leftEdge // before mediaSize(): the lyric budget starts here
        let mediaW = mediaSize(chipFont, iconFont)
        if mediaW > 0 {
            drawMedia(at: surface.notched ? leftEdge + gap : (bounds.width - mediaW) / 2,
                      chipFont, iconFont)
        }

        // right cluster: laid out from the right edge inwards, so a pill
        // changing width never shifts the ones outside it.
        //
        // Prepass, then draw. The prepass measures every drawn item and folds
        // the members of a `group` line into ONE background unit; the draw
        // pass fills that unit's single rounded rect and then walks its
        // members. Per-member hit rectangles are an explicit output of the
        // prepass geometry, not a by-product of the fill — so hit(), the
        // mouse handlers and popup anchoring keep resolving per member even
        // though only one pill is painted.
        let labelFont = chipFont
        var units: [(members: [RightMember], width: CGFloat)] = []
        var unitOfGroup: [Int: Int] = [:]
        for name in rightOrder {
            guard let item = rightItems[name], item.drawing,
                  !(item.icon.isEmpty && item.label.isEmpty) else { continue }

            let hasIcon = !item.icon.isEmpty
            let hasLabel = !item.label.isEmpty
            // An icon-only pill is a square, like the apple pill, with the
            // glyph centred on its INK. A pill with a label flows
            // icon-then-text, and the gap between them exists
            // only when both do — the weather pill has no icon (its glyph
            // lives in the label) and inherited the gap anyway, which is the
            // 7 px it sat right of centre by.
            let member = RightMember(
                name: name, item: item,
                iconInk: hasIcon ? inkBox(item.icon, iconFont).width : 0,
                innerGap: hasIcon && hasLabel ? 7 : 0,
                labelAdv: name == "proxy-speed" ? proxySpeedWidth
                    : (hasLabel ? advance(item.label, labelFont) : 0))
            // only a run that is still adjacent HERE may share a background:
            // the loader guarantees it, and this keeps a stale group from
            // stretching a rect across an item that sits between its members
            if let group = rightGroupOf[name], let unit = unitOfGroup[group],
               unit == units.count - 1 {
                units[unit].members.append(member)
                units[unit].width += groupInnerGap + member.content
                continue
            }
            if let group = rightGroupOf[name] { unitOfGroup[group] = units.count }
            units.append(([member], 10 + member.content + 10))
        }

        var cursor = bounds.maxX - padLeft
        var rectLog: [[String]] = []
        for unit in units.reversed() {
            var unitLog: [String] = []
            // a solo icon-only pill is a square with its glyph centred on
            // the pill; a group keeps the flowing layout
            let square = unit.members.count == 1
                && unit.members[0].iconInk > 0 && unit.members[0].labelAdv == 0
            let width = square ? pillHeight : unit.width
            let pill = NSRect(x: cursor - width, y: (barHeight - pillHeight) / 2,
                              width: width, height: pillHeight)
            palette.itemBG.setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            if unit.members.count > 1 {
                unitLog.append(String(format: "[%@ %.1f..%.1f]",
                                      unit.members.map(\.name).joined(separator: "+"),
                                      pill.minX, pill.maxX))
            }
            var contentX = pill.minX + 10
            var segmentX = pill.minX
            for (index, member) in unit.members.enumerated() {
                if member.iconInk > 0 {
                    drawIcon(member.item.icon, iconFont,
                             member.item.iconColor.map { palette[keyPath: $0] } ?? palette.label,
                             centeredIn: square ? pill
                                 : NSRect(x: contentX, y: pill.minY,
                                          width: member.iconInk, height: pill.height))
                }
                if member.name == "proxy-speed" {
                    drawProxySpeed(member.item, x: contentX, midY: pill.midY)
                } else if member.labelAdv > 0 {
                    drawText(member.item.label, labelFont, palette.label,
                             leftAt: contentX + member.iconInk + member.innerGap, midY: pill.midY)
                }
                // the 8 pt between two members is split down the middle, so a
                // click in the spacing lands on whichever member it is nearer
                let segmentEnd = index == unit.members.count - 1
                    ? pill.maxX
                    : contentX + member.content + groupInnerGap / 2
                itemRects.append((member.name, NSRect(x: segmentX, y: 0,
                                                      width: segmentEnd - segmentX,
                                                      height: barHeight)))
                unitLog.append(String(format: "%@ %.1f..%.1f", member.name, segmentX, segmentEnd))
                contentX += member.content + groupInnerGap
                segmentX = segmentEnd
            }
            rectLog.append(unitLog)
            cursor = pill.minX - gap
        }
        // one-shot in practice: the rects only move when a pill's width or the
        // item set does, so a steady bar logs this once
        let rectLine = "right rects: " + rectLog.reversed().flatMap { $0 }.joined(separator: " ")
        if rectLine != lastRectLog {
            lastRectLog = rectLine
            tlog(rectLine)
        }

        let rightWidth = itemRects.isEmpty ? padLeft : bounds.maxX - cursor - gap
        let rightBudget = bounds.width - surface.notchRight - padLeft
        let leftClusterEdge = mediaW > 0
            ? (surface.notched ? leftEdge + gap : (bounds.width - mediaW) / 2) + mediaW
            : leftEdge
        tlog(String(format: "width: right=%.3f budget=%.3f headroom=%.3f leftEdge=%.3f leftBudget=%.3f ai=%.3f chips=%d",
                    rightWidth, rightBudget, rightBudget - rightWidth,
                    leftClusterEdge, surface.notchLeft, aiW, shown.count))
    }


    // Tracking areas, not a poll and not a global monitor: a global
    // monitor stops delivering once this app is itself active, which is
    // exactly what clicking the bar makes it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseExited(with event: NSEvent) { scheduleHullCheck() }

    private func hit(_ event: NSEvent) -> String? {
        let p = convert(event.locationInWindow, from: nil)
        return itemRects.first(where: { $0.1.contains(p) })?.0
    }

    var appPillRect = NSRect.zero

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if appPillRect != .zero, appPillRect.contains(p), let surface {
            appMenuStack.removeAll()
            // clicking the bar deactivated the app, which makes its menu
            // items read disabled and presses land nowhere — hand focus
            // straight back while our popup (never key) stays up
            NSWorkspace.shared.runningApplications
                .first { $0.localizedName == model.frontApp }?
                .activate()
            showPopup("appmenu", under: window?.convertToScreen(convert(appPillRect, to: nil)) ?? appPillRect,
                      on: surface, alignLeft: true)
            return
        }
        if appleRect.contains(p), let surface {
            appMenuStack.removeAll()
            NSWorkspace.shared.runningApplications
                .first { $0.localizedName == model.frontApp }?
                .activate()
            // aligned to its LEFT edge: it is the leftmost thing on the bar,
            // so a right-aligned popup would hang off the screen
            showPopup("apple", under: window?.convertToScreen(convert(appleRect, to: nil)) ?? appleRect,
                      on: surface, alignLeft: true)
            return
        }
        if aiRect.contains(p), let surface {
            // left-aligned like the apple menu: a right-aligned popup under a
            // left-cluster pill would hang toward the middle of the screen
            aiRenderRows() // the countdowns move; the click is the cue to refresh
            showPopup("ai", under: window?.convertToScreen(convert(aiRect, to: nil)) ?? aiRect,
                      on: surface, alignLeft: true)
            return
        }
        if let ws = chipRects.first(where: { $0.1.contains(p) })?.0 {
            DispatchQueue.global(qos: .userInitiated).async { focusWorkspace(ws) }
            return
        }
        if let part = mediaRects.first(where: { $0.1.contains(p) })?.0 {
            closePopup()
            if mediaSourceMPD {
                tlog("media click \(part) -> mpd")
                // no app to open: the title toggles too, which is the only
                // click a `media-controls off` pill has
                switch part {
                case "prev": mpdSend("previous")
                case "next": mpdSend("next")
                default: mpdSend(model.media.playing ? "pause 1" : "pause 0")
                }
                return
            }
            switch part {
            case "prev": spotify("previous track")
            case "play": spotify("playpause")
            case "next": spotify("next track")
            default:
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyBundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            return
        }
        guard let name = hit(event), let rect = itemRects.first(where: { $0.0 == name })?.1 else {
            closePopup()
            return
        }
        // an item with a popup toggles it; the rest still act directly
        if !popupRows(for: name).isEmpty, let surface {
            let anchor = window?.convertToScreen(convert(rect, to: nil)) ?? rect
            showPopup(name, under: anchor, on: surface)
            return
        }
        closePopup()
        switch name {
        case "battery":
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        case "caffeinate":
            toggleCaffeinate()
        case "activity":
            DispatchQueue.global(qos: .userInitiated).async {
                _ = shell("/usr/bin/open", ["-na", terminalApp, "--args", "--title=omacosy-activity", "-e", btopBinary()])
            }
        default: break
        }
    }

    // A trackpad flick delivers dozens of precise events plus a momentum
    // tail; stepping 5% on each raced through the whole range. Momentum is
    // dropped and precise deltas accumulate until a notch's worth of finger
    // travel has passed — a clicky wheel already arrives one notch at a time.
    private var scrollAccum: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        guard let name = hit(event) else { return }
        if !event.momentumPhase.isEmpty { return }
        if event.phase == .began { scrollAccum = 0 }
        scrollAccum += event.scrollingDeltaY
        let notch: CGFloat = event.hasPreciseScrollingDeltas ? 20 : 1
        if abs(scrollAccum) < notch { return }
        let step = scrollAccum > 0 ? 5 : -5
        scrollAccum = 0
        switch name {
        case "volume":
            guard let v = readVolume() else { return }
            writeVolume(v.percent + step) // the CoreAudio listener repaints
        case "brightness":
            var value: Float = 0
            guard DSGetBrightness(builtinDisplayID(), &value) == 0 else { return }
            // one continuous scale: the backlight down to 0, then shade
            if step < 0, value <= 0.001 {
                setShade(shade + 0.08)
            } else if step > 0, shade > 0.001 {
                setShade(shade - 0.08) // come out of shade before raising the backlight
            } else {
                _ = DSSetBrightness(builtinDisplayID(), min(1, max(0, value + Float(step) / 100)))
                updateBrightness()
            }
        default: break
        }
    }
}

// --- window ---------------------------------------------------------------

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// AppKit pushes an ordinary window down out of the menu-bar strip, which
// is exactly where a bar belongs — 32 px lower than asked for, measured.
// Opting out of the constraint is the supported way to sit in it.
final class BarWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// The bar owns the top strip. OMACOSY_BAR_STACK=1 drops it one bar-height
// so it can run alongside another bar for comparison, which is how this
// was built. The drop is one STRIP of the display it is on, so the stacked
// bars of two displays of different strips stay out of each other's menus.
let barStacked = ProcessInfo.processInfo.environment["OMACOSY_BAR_STACK"] != nil

// One surface per display. Each owns its screen's workspace set and its
// own window; everything else it reads from the shared model.
final class BarSurface {
    var screen: NSScreen
    var monitorID: String
    var workspaces: [String] = []
    var mine: Set<String> = []
    var visible = ""
    let notchLeft: CGFloat
    let notchRight: CGFloat
    let window: BarWindow
    let view: BarView

    // This display's own menu-bar strip, re-read every place() so a
    // resolution change moves the bar with it. The Window Server's
    // Menubar window is per-display; menuBarHeight is not.
    private(set) var barHeight: CGFloat

    // A notched display has no usable centre, so the media capsule joins
    // the left cluster there — the same rule the shell bar applies, but
    // read from the screen itself instead of asked of a helper.
    var notched: Bool { screen.safeAreaInsets.top > 0 }

    init(screen: NSScreen, monitorID: String) {
        self.screen = screen
        self.monitorID = monitorID
        notchLeft = screen.auxiliaryTopLeftArea?.width ?? screen.frame.width
        notchRight = screen.auxiliaryTopRightArea.map { $0.minX - screen.frame.minX } ?? 0
        let h = surfaceBarHeight(for: screen)
        self.barHeight = h
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - h * (barStacked ? 2 : 1),
                           width: screen.frame.width, height: h)
        window = BarWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Below normal windows, where sketchybar's own windows sat. Verified:
        // the bar still renders there and still receives clicks — AppKit
        // honours a negative level, and aerospace's outer.top gap keeps
        // tiled windows off the strip (a tiled window measures y=42 here
        // against the bar's 0..34).
        //
        // This does NOT make the fullscreen check redundant, which was the
        // hope. On a notched display a fullscreen window starts BELOW the
        // notch — measured at y=32 — so it cannot cover a bar drawn from
        // y=0 by z-order alone. Being below windows is still worth it: the
        // bar can never float over an app, and on a flat display fullscreen
        // covers it for free.
        window.level = NSWindow.Level(rawValue: -20)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.acceptsMouseMovedEvents = true // tracking areas need the moves
        view = BarView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = view
        view.surface = self
        window.orderFrontRegardless()
    }

    func place() {
        // Re-read the strip: a resolution change rescales it, and this
        // runs from the screen-parameters handler after one.
        barHeight = surfaceBarHeight(for: screen)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - barHeight * (barStacked ? 2 : 1),
                           width: screen.frame.width, height: barHeight)
        window.setFrame(frame, display: true)
        view.frame = NSRect(origin: .zero, size: frame.size)
    }
}

var surfaces: [BarSurface] = []

func screenID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

// AeroSpace monitor ids are NOT stable across a hotplug — undock and the
// built-in stops being monitor 2 and becomes monitor 1 — so they are
// resolved by display NAME every time the screens change. A cached id
// answers "Invalid monitor ID" and the snapshot comes back empty, which
// renders as the last set the bar knew, stale and silent.
func monitorIDs() -> [String: String] { // display name -> WM monitor id
    // OmniWM names monitors with NSScreen.localizedName (Monitor.current()
    // in its source), so the same name join works; its ids stay opaque
    // ("display:…") and only ever meet the query payloads they came from.
    if omniwmActive() {
        var map: [String: String] = [:]
        if let list = omniQuery("displays", ["--fields", "id,name"])?["displays"]
            as? [[String: Any]] {
            for d in list {
                if let id = d["id"] as? String, let name = d["name"] as? String { map[name] = id }
            }
        }
        return map
    }
    var map: [String: String] = [:]
    for line in aerospace(["list-monitors", "--format", "%{monitor-id}|%{monitor-name}"])
        .split(separator: "\n") {
        let f = line.split(separator: "|").map(String.init)
        if f.count == 2 { map[f[1]] = f[0] }
    }
    return map
}

// A label no window manager gave: unique per display, and it matches no
// WM id, so the display's workspace pills stay empty until one answers.
func unresolvedID(_ screen: NSScreen) -> String { "unresolved:\(screenID(screen))" }

// One bar per display, always; the window manager only labels them. A
// display the manager does not list (not up yet, a login, a switch) is
// unresolved: its workspace pills stay empty rather than show another
// manager's state. reconcile() below asks again.
func rebuildSurfaces(_ ids: [String: String]) {
    let wm = labelsFromOmniWM ? "omniwm" : "aerospace"
    var kept: [BarSurface] = []
    for screen in NSScreen.screens {
        let existing = surfaces.first(where: { screenID($0.screen) == screenID(screen) })
        let id = ids[screen.localizedName] ?? unresolvedID(screen)
        let label = id.hasPrefix("unresolved:") ? "no window manager yet" : "\(wm) monitor \(id)"
        if let existing {
            if existing.monitorID != id {
                tlog("monitor: \(screen.localizedName) is now \(label) (was \(existing.monitorID))")
                existing.monitorID = id
                // the old manager's workspaces name nothing now, and apply()
                // keeps a list it is not given: clear them for the placeholder
                if id.hasPrefix("unresolved:") {
                    existing.workspaces = []
                    existing.mine = []
                    existing.visible = ""
                }
            }
            existing.screen = screen
            existing.place()
            kept.append(existing)
        } else {
            tlog("surface: \(screen.localizedName) -> \(label)\(screen.safeAreaInsets.top > 0 ? " (notched)" : "")")
            kept.append(BarSurface(screen: screen, monitorID: id))
        }
    }
    for gone in surfaces where !kept.contains(where: { $0 === gone }) {
        tlog("surface: \(gone.screen.localizedName) went away")
        gone.window.orderOut(nil)
    }
    surfaces = kept
}

func repaint() {
    // every caller is already on the main queue; display() is synchronous
    // so the timings below cover real drawing, not just invalidation
    MainActor.assumeIsolated {
        for surface in surfaces {
            surface.view.needsDisplay = true
            surface.view.display()
        }
    }
}

// --- fullscreen ------------------------------------------------------------
// sketchybar gets this for free: its windows sit at layer -20, below
// normal windows, so a fullscreen window simply covers them while
// aerospace's outer gap keeps tiled windows off the strip. This bar sits
// above windows (it has to, to be visible while stacked under sketchybar
// for comparison), so it has to decide for itself.
//
// The test is borders.swift's, and for the same reason: `fullscreen
// --no-outer-gaps` and macOS native fullscreen are indistinguishable from
// out here, and both should take the strip. A managed window never starts
// at the display's top edge — the bar owns it.

func safeTop(for display: CGRect) -> CGFloat {
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    for screen in NSScreen.screens {
        let cgY = primaryH - screen.frame.maxY
        if abs(screen.frame.origin.x - display.origin.x) < 2, abs(cgY - display.origin.y) < 2 {
            return screen.safeAreaInsets.top
        }
    }
    return 0
}

func fullscreenDisplays() -> Set<CGDirectDisplayID> {
    var covered: Set<CGDirectDisplayID> = []
    // Under OmniWM the width test below cannot separate a tiled window
    // from a fullscreen one: its 0.6.3 dwindle applies no outer gaps
    // (resolved settings say 42, layout applies 0 — upstream bug, see
    // docs/omniwm-port.md), so ordinary tiles take the side gaps too
    // and EVERYTHING reads as fullscreen — the bar lived in
    // hover-reveal permanently. Until the gap bug is fixed the bar
    // stays visible under OmniWM, accepting that it overlaps a real
    // fullscreen window instead of ducking away.
    if omniwmActive() { return covered }
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    else { return covered }
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(8, &ids, &count) == .success else { return covered }

    for window in list {
        guard (window[kCGWindowLayer as String] as? Int) == 0,
              let b = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        for i in 0..<Int(count) {
            let display = CGDisplayBounds(ids[i])
            guard display.intersects(rect) else { continue }
            let inset = safeTop(for: display)
            // Height and top edge alone are NOT enough, measured: on a
            // notched display the notch inset (32) and the gap a tiled
            // window leaves for the bar (33) are the same edge, so an
            // ordinary tiled Arc reads as fullscreen. WIDTH is what
            // separates them — `--no-outer-gaps` means exactly that, the
            // window takes the side gaps too, and a tiled one never does.
            if rect.origin.y - display.origin.y < inset + 3,
               rect.height >= display.height - inset - 6,
               rect.width >= display.width - 2 {
                covered.insert(ids[i])
            }
        }
    }
    return covered
}

// Hidden by fullscreen, but reachable: put the pointer at the very top of
// the screen and the bar comes back, the way the menu bar does. Watching a
// film and wanting the brightness slider should not mean leaving the film.
//
// While revealed the bar has to climb ABOVE the fullscreen window — its
// resting level of -20 is what hides it in the first place — and it drops
// back down when the pointer leaves.
let barBaseLevel = NSWindow.Level(rawValue: -20)
// Revealed, the bar has to clear omacosy-borders' fullscreen shroud, which
// sits at .screenSaver (1000) and blacks out the camera strip so that
// aerospace-fullscreen reads as true fullscreen on a notched display.
// At .statusBar the shroud covered all but the bottom 2 px of the bar —
// which looked like macOS chrome winning, and was our own daemon.
let barRevealLevel = NSWindow.Level(rawValue: 1002)
let revealEdge: CGFloat = 2 // how close to the top edge counts as asking
var revealed = false

func setRevealed(_ show: Bool) {
    guard show != revealed else { return }
    revealed = show
    for surface in surfaces {
        surface.window.level = show ? barRevealLevel : barBaseLevel
    }
    updateBarVisibility()
}

// Called on every pointer move, so it stays a coordinate comparison and
// nothing more.
func pointerAtScreenTop() {
    let p = NSEvent.mouseLocation
    // The rect has to be grown, not just used: CGRect.contains treats maxY
    // as exclusive, so the pointer sitting on the very top row of pixels —
    // exactly the gesture this listens for — counts as being on NO screen.
    guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: 0, dy: -2).contains(p) })
    else { return }
    let fromTop = screen.frame.maxY - p.y
    if fromTop <= revealEdge {
        // Climb only when fullscreen actually hides the bar. Otherwise stay
        // at the -20 resting level so the auto-hidden native menu bar can
        // slide in ABOVE the bar and stay clickable — app menus are
        // unreachable by mouse without this.
        if fullscreenDisplays().contains(screenID(screen)) {
            setRevealed(true)
        }
    } else if revealed, openPopup == nil,
              fromTop > (surfaces.first(where: { screenID($0.screen) == screenID(screen) })?.barHeight
                           ?? barHeightFallback) + 12 {
        // a popup keeps it up: its anchor must not vanish under the pointer
        setRevealed(false)
    }
}

func updateBarVisibility() {
    let covered = fullscreenDisplays()
    for surface in surfaces {
        let hide = covered.contains(screenID(surface.screen)) && !revealed
        // unconditional either way: isVisible can desync from the window
        // server, which is how borders.swift ended up with a stuck shroud
        if hide {
            surface.window.orderOut(nil)
            // only this surface's own popup: another display's popup is
            // unaffected by a fullscreen window over this one
            if openPopup != nil, openPopupDisplay == screenID(surface.screen) { closePopup() }
        } else {
            surface.window.orderFrontRegardless()
        }
    }
}

// --- signals --------------------------------------------------------------

// Workspace switches arrive as a one-line file written by aerospace's
// exec-on-workspace-change hook (a bash builtin redirect — no extra
// process). A regular file, deliberately: a FIFO with no reader would
// block the hook and wedge workspace switching if this daemon died.
// borders.swift's watcher, same reasons: .attrib catches a symlink swap
// that .write alone misses, and a delete/rename re-arms instead of going
// deaf for the rest of the daemon's life.
func watch(_ path: String, create: Bool, handler: @escaping () -> Void) {
    if create, !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    let fd = open(path, O_EVTONLY)
    guard fd >= 0 else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { watch(path, create: create, handler: handler) }
        return
    }
    let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
        eventMask: [.write, .attrib, .delete, .rename], queue: .main)
    src.setEventHandler {
        let ev = src.data
        handler()
        if ev.contains(.delete) || ev.contains(.rename) { src.cancel() }
    }
    src.setCancelHandler {
        close(fd)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { watch(path, create: create, handler: handler) }
    }
    src.resume()
}

// A window sent from one HIDDEN workspace to another moves nothing on
// screen, so SkyLight reports nothing at all — measured with a probe:
// not an order change, not a visibility change, no event of any kind.
// No publisher exists for it, so the commands that do the moving say so
// themselves (omacosy-ws, and the overview's drag-reorder).
// Super+K writes this; the bar has no key tap and should not grow one
let cheatPath = "/tmp/omacosy-bar-cheatsheet"
watch(cheatPath, create: true) { toggleCheatsheet() }

let movedPath = "/tmp/omacosy-bar-moved"
watch(movedPath, create: true) {
    tlog("moved poke")
    kickRebuild()
}

let wsPath = "/tmp/omacosy-bar-ws"
watch(wsPath, create: true) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    guard let text = try? String(contentsOfFile: wsPath, encoding: .utf8) else { return }
    let ws = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !ws.isEmpty, ws != model.focused else { return }
    setFocused(ws)
    repaint()
    kickVisibility()
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    tlog(String(format: "switch %@ %.2f ms", ws, ms))
}

// --- omniwm fast path -------------------------------------------------------
// OmniWM has no exec-on-workspace-change hook to write the file above,
// and a switch between two EMPTY workspaces moves no windows, so SkyLight
// says nothing either. OmniWM publishes instead: its active-workspace
// channel emits one event per change. `watch … --exec /bin/cat` rather
// than `subscribe` because subscribe pretty-prints multi-line JSON while
// watch hands its child exactly one NDJSON line per event, and the child
// inherits this pipe (OmniWM docs/IPC-CLI.md, "watch") — so the stream
// arrives line-delimited and the bar's side never forks anything.

var omniWatch: Process?
var omniWatchBuffer = Data()

func omniWorkspaceBarEvent(_ line: Data) {
    // The workspace-bar channel, not active-workspace: measured 2026-08-29,
    // active-workspace (and focus) only fire when the FOCUSED WINDOW
    // changes, so every switch to or from an EMPTY workspace is silent —
    // OmniWM's own Super+8/9 left the pill frozen. Their bar highlights
    // empties, so its scene channel fires on every switch, and carries
    // per-monitor active flags plus each workspace's windows (occupancy
    // and the sole-app icon come free, no windows query).
    guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          root["channel"] as? String == "workspace-bar",
          let payload = (root["result"] as? [String: Any])?["payload"] as? [String: Any],
          let monitors = payload["monitors"] as? [[String: Any]]
    else { return }
    let current = payload["interactionMonitorId"] as? String ?? ""
    let t0 = DispatchTime.now().uptimeNanoseconds
    var changed = false
    var occupied = Set<String>()
    var sole: [String: String] = [:]
    var focusedNow = ""
    for m in monitors {
        guard let id = m["id"] as? String,
              let list = m["workspaces"] as? [[String: Any]] else { continue }
        var active = ""
        for w in list {
            guard let name = w["rawName"] as? String else { continue }
            if (w["isFocused"] as? Bool) == true { active = name }
            let wins = ((w["windows"] as? [[String: Any]]) ?? [])
                .filter { ($0["appName"] as? String)?.hasPrefix("omacosy") != true }
            if !wins.isEmpty {
                occupied.insert(name)
                let apps = Set(wins.compactMap { $0["appName"] as? String })
                if apps.count == 1, let app = apps.first { sole[name] = app }
            }
        }
        guard !active.isEmpty else { continue }
        if id == current { focusedNow = active }
        for surface in surfaces where surface.monitorID == id && surface.visible != active {
            surface.visible = active
            changed = true
        }
    }
    if !focusedNow.isEmpty, model.focused != focusedNow { model.focused = focusedNow; changed = true }
    if model.occupied != occupied { model.occupied = occupied; changed = true }
    if model.soleApp != sole { model.soleApp = sole; changed = true }
    guard changed else { return }
    repaint()
    kickVisibility()
    tlog(String(format: "switch %@ %.2f ms (omniwm)", focusedNow,
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

var omniWatchStarting = false
func startOmniWatch() {
    guard omniWatch == nil, !omniWatchStarting, omniwmActive() else { return }
    omniWatchStarting = true
    // a bar killed by launchd (kickstart -k is SIGKILL) leaves its
    // stream child alive under pid 1, one per restart — reap orphans
    // before spawning ours; -P 1 cannot touch a living bar's child.
    // pkill is waited for, so off the main thread.
    DispatchQueue.global(qos: .utility).async {
        let reap = Process()
        reap.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        reap.arguments = ["-P", "1", "-f", "omniwmctl watch workspace-bar"]
        try? reap.run()
        reap.waitUntilExit()
        DispatchQueue.main.async {
            omniWatchStarting = false
            guard omniWatch == nil, omniwmActive() else { return }
            spawnOmniWatch()
        }
    }
}

func spawnOmniWatch() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: omniwmctlBin)
    p.arguments = ["watch", "workspace-bar", "--exec", "/bin/cat"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return }
        DispatchQueue.main.async {
            omniWatchBuffer.append(chunk)
            while let nl = omniWatchBuffer.firstIndex(of: 0x0A) {
                let line = Data(omniWatchBuffer[omniWatchBuffer.startIndex..<nl])
                omniWatchBuffer = Data(omniWatchBuffer[omniWatchBuffer.index(after: nl)...])
                omniWorkspaceBarEvent(line)
            }
        }
    }
    p.terminationHandler = { proc in
        DispatchQueue.main.async {
            pipe.fileHandleForReading.readabilityHandler = nil
            guard omniWatch === proc else { return } // a newer watch took over
            omniWatch = nil
            // OmniWM restarting, or its IPC server not up yet, drops the
            // stream: keep knocking while OmniWM is the one running
            guard omniwmActive() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { startOmniWatch() }
        }
    }
    guard (try? p.run()) != nil else { return }
    omniWatch = p
    tlog("omniwm: watching workspace-bar")
}

func stopOmniWatch() {
    guard let p = omniWatch else { return }
    omniWatch = nil // before terminate, so the handler cannot restart it
    p.terminate()
}

// ONE routine owns which window manager labels the bar. Both managers are
// LSUIElement, so NSWorkspace posts no launch or quit for them; the list of
// running apps is KVO-observable and does change, which is the event. It
// starts or stops the OmniWM watch, drops the old manager's labels on a
// switch (they name nothing now), asks the manager for display ids and its
// focused workspace off the main thread, and while a display is unresolved
// or the focused workspace is not yet confirmed retries with backoff
// (1, 2, 4, 8, 15, 30 s, then stops). An app switch, a screen change or
// the managers changing start it again from the first step.
let aerospaceBundleID = "bobko.aerospace"
func runningWMs() -> [Bool] {
    [omniwmActive(), !NSRunningApplication.runningApplications(withBundleIdentifier: aerospaceBundleID).isEmpty]
}
var labelsFromOmniWM = omniwmActive()
var wmApps = runningWMs()
let reconcileBackoff: [Double] = [1, 2, 4, 8, 15, 30]
var reconcileStep = 0
var reconcileRetry: DispatchWorkItem?
func anyUnresolved() -> Bool { surfaces.contains { $0.monitorID.hasPrefix("unresolved:") } }
// the focused workspace as the manager itself reports it (blocking: off-main)
func managerFocused(_ omni: Bool) -> String {
    omni
        ? ((omniQuery("workspaces", ["--focused", "--fields", "raw-name"])?["workspaces"]
            as? [[String: Any]])?.first?["rawName"] as? String ?? "")
        : aerospace(["list-workspaces", "--focused"]).trimmingCharacters(in: .whitespacesAndNewlines)
}
// After a switch the ring shows what the OLD manager had focused, and the
// new one's stream can start before it answers at all. So reconcile asks the
// new manager directly, off the main thread, and keeps asking on its own
// backoff until two answers in a row agree with the ring. An empty answer
// (still starting, or a missed reply) does not count.
var refocusAgreed = 2   // 2 = nothing to confirm
func reconcile(_ why: String, restart: Bool = true) {
    let omni = omniwmActive()
    if omni { startOmniWatch() } else { stopOmniWatch() }
    // after a switch, or once a display resolves, the ring still shows the
    // workspace the OLD manager had focused: ask the new one
    if omni != labelsFromOmniWM || anyUnresolved() { refocusAgreed = 0 }
    let refocus = refocusAgreed < 2
    if omni != labelsFromOmniWM {
        labelsFromOmniWM = omni
        tlog("wm: now \(omni ? "omniwm" : "aerospace") (\(why)), relabelling the bar")
        rebuildSurfaces([:])
        repaint()
    }
    if restart { reconcileStep = 0 }
    reconcileRetry?.cancel()
    reconcileRetry = nil
    rebuildQueue.async {
        let ids = monitorIDs()
        let focused = refocus ? managerFocused(omni) : ""
        DispatchQueue.main.async {
            guard omniwmActive() == omni else { return } // a newer call owns it
            rebuildSurfaces(ids)
            if refocus, !focused.isEmpty {
                if focused == model.focused {
                    refocusAgreed += 1
                } else {
                    setFocused(focused)
                    repaint()
                    tlog("wm: focused workspace \(focused), from the manager")
                    refocusAgreed = 0
                }
            }
            kickRebuild()
            let unresolved = anyUnresolved()
            guard unresolved || refocusAgreed < 2, reconcileStep < reconcileBackoff.count else { return }
            let delay = reconcileBackoff[reconcileStep]
            reconcileStep += 1
            tlog("wm: \(unresolved ? "display unresolved" : "focus not confirmed"), asking again in \(Int(delay)) s")
            let retry = DispatchWorkItem { reconcile("retry", restart: false) }
            // two calls in flight both land here: keep only the newest retry
            reconcileRetry?.cancel()
            reconcileRetry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retry)
        }
    }
}
let wmAppsWatch = NSWorkspace.shared.observe(\.runningApplications, options: []) { _, _ in
    DispatchQueue.main.async {
        let now = runningWMs()
        guard now != wmApps else { return }
        wmApps = now
        tlog("wm: omniwm \(now[0] ? "up" : "down"), aerospace \(now[1] ? "up" : "down")")
        reconcile("wm-apps")
    }
}

// front app: a notification, not a poll and not a script
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { note in
    let t0 = DispatchTime.now().uptimeNanoseconds
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          let name = app.localizedName, name != model.frontApp,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
    // someone is using the Mac: an unresolved display is worth asking about now
    if anyUnresolved() { reconcile("activation") }
    model.frontApp = name
    repaint()
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    tlog(String(format: "frontapp %@ %.2f ms", name, ms))
}

// A display that was unplugged during a theme change, or plugged in while
// the machine was off, shows the theme before it: macOS keeps the desktop
// picture per display, and a theme change only reaches the screens
// attached at the time. The helper puts the recorded picture back.
//
// Twice: once now, and once after macOS has finished adopting the
// display, because a picture set too early does not stick. The second
// run is free when the first one worked — resync skips a screen that
// already has the right picture.
func resyncWallpaper() {
    for delay in [0.0, 4.0] {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            let out = shell("\(NSHomeDirectory())/.local/bin/omacosy-helper", ["wallpaper", "resync"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !out.isEmpty else { return }
            DispatchQueue.main.async { tlog(out) }
        }
    }
}

// Its own count, apart from monitorCount below: that one moves only after
// the grace, and this one must be able to move before it.
var resyncedCount = NSScreen.screens.count
func resyncIfGained() {
    let now = NSScreen.screens.count
    if now > resyncedCount { resyncWallpaper() }
    resyncedCount = now
}

// Displays come and go: re-resolve which aerospace monitor this screen is
// now, move the window onto it, and rebuild. Screen parameters arrive
// before the arrangement settles, so give it a beat (borders.swift learnt
// the same lesson with a stale CG-to-Cocoa flip after a replug).
//
// This is also where the guest set gets folded and unfolded. Undocked,
// AeroSpace parks workspaces 11-19 on the one display, and omacosy-ws
// only ever matches single-digit slots — so anything left on a guest
// workspace is unreachable by Super+N or Super+Tab until a display
// comes back. omacosy-ws-collapse moves those windows into
// 1-9 and remembers where they came from.
//
// It used to be driven by sketchybar's display_change.sh, which went
// out with sketchybar; nothing has called it since, so the first undock
// after that stranded a workspace's worth of apps. The bar is the only
// long-lived process already watching for this, so it owns it now.
// Guarded on the COUNT changing: this notification also fires for
// resolution and arrangement changes, and re-folding on those would
// shuffle windows for no reason.
var monitorCount = NSScreen.screens.count
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
) { _ in
    // At once, not after the grace below: until it runs, the new screen
    // shows the old theme. Checked again after the grace, in case the
    // count had not moved yet when the notification arrived.
    resyncIfGained()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        resyncIfGained()
        closePopup() // its anchor may not exist any more
        var known: [String: String] = [:] // two identical monitors share a name
        for surface in surfaces { known[surface.screen.localizedName] = surface.monitorID }
        rebuildSurfaces(known)
        applyShade() // a new display arrives at full output
        // the WM can adopt the new display after this grace: reconcile asks
        // again until it answers, with its own backoff
        reconcile("screens")
        let now = NSScreen.screens.count
        guard now != monitorCount else { return }
        monitorCount = now
        syncWorkspaceFold("displays: \(now)")
    }
}

// Fold or unfold to match the screens there are now. ws-collapse waits
// for the WM to agree on the count and does nothing when nothing is out
// of place, so calling it more often than needed costs nothing — and a
// call that raced the WM, or landed mid-sleep, is caught by the next.
// both WMs: OmniWM re-routes guest WORKSPACES on unplug but strands
// their windows "after 9"; ws-collapse folds them into 1-9.
func syncWorkspaceFold(_ why: String) {
    let n = NSScreen.screens.count
    tlog("\(why) — running ws-collapse sync \(n)")
    // off-main: it waits for the WM (up to 30 s) and moves window by window
    DispatchQueue.global(qos: .userInitiated).async {
        _ = shell("\(NSHomeDirectory())/.local/bin/omacosy-ws-collapse", ["sync", "\(n)"])
        DispatchQueue.main.async { kickRebuild() }
    }
}

// window create/destroy: the only thing that needs the slow path, and it
// is debounced off the critical path
var pending: DispatchWorkItem?
func kickRebuild() {
    pending?.cancel()
    let w = DispatchWorkItem {
        rebuildQueue.async {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let snapshot = fetchSnapshot()
            let fetched = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            DispatchQueue.main.async {
                let t1 = DispatchTime.now().uptimeNanoseconds
                guard apply(snapshot) else { return } // nothing moved
                repaint()
                let drawn = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1_000_000
                tlog(String(format: "rebuild fetch %.2f ms (off-main) + paint %.2f ms", fetched, drawn))
            }
        }
    }
    pending = w
    // 0.3s was priced against a snapshot that cost four subprocesses;
    // one call later the coalescing window can be the part a person
    // actually waits through
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
}

let cid = SLSMainConnectionID()
// move and resize only fire for SUBSCRIBED windows, and going fullscreen
// is a resize — so the subscription set is kept equal to every normal
// window, refreshed whenever one is created or destroyed (borders.swift's
// recipe, and its reason).
var subscribed: Set<UInt32> = []
func rebuildSubscriptions() {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
    else { return }
    var wids: [UInt32] = []
    for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
        if let n = w[kCGWindowNumber as String] as? Int { wids.append(UInt32(n)) }
    }
    let set = Set(wids)
    guard set != subscribed, !wids.isEmpty else { return }
    subscribed = set
    _ = wids.withUnsafeBufferPointer {
        SLSRequestNotificationsForWindows(cid, $0.baseAddress!, Int32(wids.count))
    }
}

// a fullscreen check is a window-list read, not a subprocess: cheap
// enough to run on a short debounce after any window event
var visibilityPending: DispatchWorkItem?
func kickVisibility() {
    visibilityPending?.cancel()
    let work = DispatchWorkItem { updateBarVisibility() }
    visibilityPending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
}

let notify: NotifyProc = { event, _, _, _ in
    DispatchQueue.main.async {
        if event == EVENT_WINDOW_CREATE || event == EVENT_WINDOW_DESTROY {
            kickRebuild()
            rebuildSubscriptions()
        } else if event == EVENT_WINDOW_ORDER || event == EVENT_WINDOW_VISIBILITY {
            // the chips are only as fresh as this: a window changing
            // workspace shows up here and nowhere else. A plain
            // workspace switch lands here too and fetches a snapshot
            // that changed nothing, which apply() reports so the
            // repaint is skipped.
            kickRebuild()
        }
        kickVisibility()
    }
}
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_CREATE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_DESTROY, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_MOVE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_RESIZE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_ORDER, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_VISIBILITY, nil)
rebuildSubscriptions()
var eventPort: mach_port_t = 0
if SLSGetEventPort(cid, &eventPort).rawValue == 0, eventPort != 0 {
    let drain = DispatchSource.makeMachReceiveSource(port: eventPort, queue: .main)
    drain.setEventHandler { while let e = SLEventCreateNextEvent(SLSMainConnectionID()) { e.release() } }
    drain.resume()
}

// theme switches: repaint, never rebuild. theme-set swaps the symlink
// inside this directory; the file behind the old one never changes itself.
watch(FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/omarchy/current").path, create: false) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    palette = loadPalette()
    iconCache.removeAll()
    repaint()
    if cheatWindow != nil { hideCheatsheet(); toggleCheatsheet() } // repaint in the new palette
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    tlog(String(format: "theme %.2f ms", ms))
}

// --- popup guard -----------------------------------------------------------
// popup_guard.sh polls the cursor on a loop and greps item names to decide
// whether a popup should still be open. Here the cursor is a published
// event and the geometry is already known, so the rule is exact: a popup
// closes when the pointer is in neither the bar nor the popup — which is
// what "don't close it while I'm still in the bar" actually means.
// The check runs a beat after the pointer leaves either surface, because
// travelling from the bar to its popup crosses the gap between them and
// must not read as leaving.
func scheduleHullCheck() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        if popupWindow != nil, pointerLeftTheHull() { closePopup() }
    }
}

func pointerLeftTheHull() -> Bool {
    guard let popup = popupWindow else { return false }
    let p = NSEvent.mouseLocation
    let slack: CGFloat = 6 // the gap between a bar and its popup
    if popup.frame.insetBy(dx: -slack, dy: -slack).contains(p) { return false }
    for surface in surfaces where surface.window.frame.insetBy(dx: 0, dy: -slack).contains(p) {
        return false
    }
    return true
}

// the monitor must be RETAINED — dropping the returned token deregisters
// it immediately, and the popup then never closes on its own
var popupGuardToken: Any?
var revealToken: Any?
revealToken = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in pointerAtScreenTop() }
var revealLocalToken: Any?
revealLocalToken = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in
    pointerAtScreenTop()
    return e
}

popupGuardToken = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
    // a click that lands in another app dismisses the popup; hover-exit
    // is the tracking areas' job
    if popupWindow != nil, pointerLeftTheHull() { closePopup() }
}

// --- right-cluster publishers ---------------------------------------------

// battery: IOPS fires on capacity ticks too
let powerCallback: IOPowerSourceCallbackType = { _ in DispatchQueue.main.async { updateBattery() } }
if let src = IOPSNotificationCreateRunLoopSource(powerCallback, nil)?.takeRetainedValue() {
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
} else {
    tlog("IOPSNotificationCreateRunLoopSource failed — battery pill will not update")
}

// volume: listen on the current default output device, and re-attach when
// the default changes (plugging in headphones is a different device)
var volumeListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

func attachVolumeListeners() {
    for (object, address, block) in volumeListeners {
        var a = address
        AudioObjectRemovePropertyListenerBlock(object, &a, DispatchQueue.main, block)
    }
    volumeListeners.removeAll()

    let dev = defaultOutputDevice()
    guard dev != 0 else { return }
    let block: AudioObjectPropertyListenerBlock = { _, _ in updateVolume() }
    for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListenerBlock(dev, &addr, DispatchQueue.main, block) == noErr {
            volumeListeners.append((dev, addr, block))
        }
    }
    updateVolume()
}

var defaultDeviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                    &defaultDeviceAddress, DispatchQueue.main) { _, _ in
    attachVolumeListeners()
}

var audioDevicesAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                    &audioDevicesAddress, DispatchQueue.main) { _, _ in
    updateAirPods()
}
attachVolumeListeners()

// brightness: DisplayServices publishes, so the keyboard keys land here
// without the bar being told about them by anyone else
let brightnessProc: DSBrightnessProc = { _, _, _, _ in
    DispatchQueue.main.async { updateBrightness() }
}
if DSRegisterBrightnessNotifications(builtinDisplayID(), nil, brightnessProc) != 0 {
    tlog("brightness notifications unavailable — pill updates on scroll only")
}

// night shift: same idea one layer up — the schedule flipping it is a
// change nobody else would tell an open popup about
watchNightShift()

// network: the same SCDynamicStore keys the watcher uses
var storeContext = SCDynamicStoreContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
if let store = SCDynamicStoreCreate(nil, "omacosy-bar" as CFString,
                                    { _, _, _ in DispatchQueue.main.async { updateWifi() } }, &storeContext) {
    SCDynamicStoreSetNotificationKeys(store, nil, [
        "State:/Network/Global/IPv4",
        "State:/Network/Interface/en.*/Link",
        "State:/Network/Interface/en.*/AirPort",
    ] as CFArray)
    if let src = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
    }
} else {
    tlog("SCDynamicStoreCreate failed — wifi pill will not update")
}

// location: the network name's price, same responsible-process rules
locationGate.start()

// bluetooth: gated on the privacy grant, which the watcher above also needs
bluetoothWatcher.start()

// waking clears the gamma table, so the shade has to be reasserted.
// A monitor unplugged or replugged while asleep is the case the screen
// notification handles worst: it fires at wake while the WM still holds
// the old layout. Sync after every wake, once the screens have settled.
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
) { _ in
    applyShade()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        monitorCount = NSScreen.screens.count
        syncWorkspaceFold("wake")
    }
}

// media: Spotify broadcasts every state change itself, and the payload
// already carries the track — so the pill repaints without asking anyone
// anything. Launch and quit are the one pair it cannot announce.
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("\(spotifyBundleID).PlaybackStateChanged"), object: nil, queue: .main
) { note in updateMedia(from: note.userInfo) }

for event in [NSWorkspace.didLaunchApplicationNotification,
              NSWorkspace.didTerminateApplicationNotification] {
    NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == spotifyBundleID else { return }
        if event == NSWorkspace.didLaunchApplicationNotification { primeMedia() } else { updateMedia() }
    }
}

// clock and weather have no publisher to listen to. The clock ticks on
// the minute boundary rather than every 60 s from launch, so it never
// shows a stale minute.
func scheduleClock() {
    updateClock()
    let now = Date()
    let nextMinute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0),
                                               matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
    DispatchQueue.main.asyncAfter(deadline: .now() + max(1, nextMinute.timeIntervalSinceNow)) { scheduleClock() }
}
scheduleClock()

Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in updateWeather() }
Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in updateFissionFund() }
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in updateProxySpeed() }
// same 1800 s cadence bar_daemon.sh:147 used for Open-Meteo
Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in updateOpenMeteoWeather() }
// codexbar walks the network with a 20 s timeout, so the fetch keeps the
// daemon's own 300 s cadence and never runs on main
Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in updateAIUsage() }
Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { _ in updateAirPods() }
// disablesleep can also be flipped from a terminal, so the pill re-reads
// pmset rather than trusting the last toggle
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in renderCaffeinate() }
// the panel's countdowns move by the minute, but only a visible panel is
// worth spawning bash and python3 for
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
    if openPopup == "ai" { aiRenderRows() }
}
// the lyric file changes only when the daemon's line does; one stat per 0.1 s
// is the cheapest way to never miss an os.replace (a descriptor watch sees the
// first rename and then holds a dead inode) and keeps the line within 0.1 s of
// the daemon's tick
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in lyricPoll() }

// ===== omacosy extras (fork) begin =====

// bar-items.conf is intentionally outside the repository: launchd may not
// have TCC access to a clone under Documents. OMACOSY_BAR_ITEMS_CONF exists
// only for isolated validation and leaves the normal launch path unchanged.
func barItemsConfURL() -> URL {
    ProcessInfo.processInfo.environment["OMACOSY_BAR_ITEMS_CONF"]
        .map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/omacosy/bar-items.conf")
}

// a one-value directive, e.g. `fission-estimator ~/path/to/estimator.js`.
// First occurrence wins; an absent directive is not an error, it is the
// feature being off.
//
// A leading `~` is expanded so one bar-items.conf serves every machine:
// the paths here point outside the repo, so spelling them absolutely
// hardcodes a $HOME and the file can no longer be shared between users.
// Expansion is unconditional rather than per-directive — a hardcoded list
// of "the path ones" is exactly the kind of list this repo keeps rotting.
// It is a no-op on anything not starting with `~`, so value directives that
// are not paths (airpods-name, workspaces-max, caffeinate) are untouched.
func configuredValue(_ directive: String) -> String? {
    guard let text = try? String(contentsOf: barItemsConfURL(), encoding: .utf8) else { return nil }
    for rawLine in text.components(separatedBy: .newlines) {
        let uncommented = rawLine.split(separator: "#", maxSplits: 1,
                                        omittingEmptySubsequences: false).first ?? ""
        let fields = uncommented.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 2, fields[0] == directive else { continue }
        return (fields[1] as NSString).expandingTildeInPath
    }
    return nil
}

func configuredRightLayout(_ upstream: [String])
    -> (order: [String], groups: [[String]], mediaControls: Bool) {
    let config = barItemsConfURL()
    guard let text = try? String(contentsOf: config, encoding: .utf8),
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        tlog("bar-items order: " + upstream.joined(separator: " "))
        return (upstream, [], true)
    }

    let known = Set(upstream)
    var hidden = Set<String>()
    var namedOrder: [String]?
    var groupLines: [(line: Int, members: [String])] = []
    var mediaControls = true
    for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
        let uncommented = rawLine.split(separator: "#", maxSplits: 1,
                                        omittingEmptySubsequences: false).first ?? ""
        let fields = uncommented.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let directive = fields.first else { continue }
        let items = Array(fields.dropFirst())
        switch directive {
        case "hide":
            for item in items {
                if known.contains(item) { hidden.insert(item) }
                else { tlog("bar-items.conf:\(index + 1): unknown item \(item)") }
            }
        case "order":
            var seen = Set<String>()
            let valid = items.filter { item in
                guard known.contains(item) else {
                    tlog("bar-items.conf:\(index + 1): unknown item \(item)")
                    return false
                }
                return seen.insert(item).inserted
            }
            if !valid.isEmpty { namedOrder = valid }
        case "group":
            var members: [String] = []
            for item in items {
                guard known.contains(item) else {
                    tlog("bar-items.conf:\(index + 1): unknown item \(item)")
                    continue
                }
                if !members.contains(item) { members.append(item) }
            }
            if members.count >= 2 { groupLines.append((index + 1, members)) }
            else { tlog("bar-items.conf:\(index + 1): group needs 2+ known items, ignored") }
        // value directives are read by configuredValue(); listed here only so
        // they do not report themselves as unknown
        case "fission-estimator", "weather-script", "weather-lib",
             "ai-usage-script", "codexbar", "workspaces-max", "airpods-name",
             "caffeinate", "lyrics-daemon", "lyrics-out", "media-source", "mpd-socket", "proxy-speed":
            break
        case "media-controls":
            // only `off` turns them off; anything else keeps upstream behaviour
            if items.first == "off" { mediaControls = false }
            else if items.first != "on" {
                tlog("bar-items.conf:\(index + 1): media-controls wants on|off, ignored")
            }
        default:
            tlog("bar-items.conf:\(index + 1): unknown directive \(directive)")
        }
    }

    // Named items move to the front. Unnamed items retain upstream order;
    // hide is applied last, so it wins even when an item is also ordered.
    let ordered = namedOrder.map { named in
        named + upstream.filter { !named.contains($0) }
    } ?? upstream
    var result = ordered.filter { !hidden.contains($0) }

    // A group only means anything for a contiguous run: the shared background
    // is one rounded rect. Members that `hide` removed simply leave the group;
    // members the order left scattered are MOVED next to the first of them
    // (in group-line order), because a group line that silently did nothing
    // is the worse surprise. An item can belong to one group only.
    var groups: [[String]] = []
    var claimed = Set<String>()
    for line in groupLines {
        let members = line.members.filter { result.contains($0) && !claimed.contains($0) }
        guard members.count >= 2 else {
            tlog("bar-items.conf:\(line.line): group has fewer than 2 visible items, ignored")
            continue
        }
        // every item before the first member is a non-member, so the anchor
        // index survives the removal unchanged
        let anchor = result.firstIndex(where: { members.contains($0) }) ?? 0
        if Array(result[anchor..<min(anchor + members.count, result.count)]) != members {
            var rest = result
            rest.removeAll { members.contains($0) }
            result = Array(rest[..<anchor]) + members + Array(rest[anchor...])
            tlog("bar-items.conf:\(line.line): group moved together at \(members[0])")
        }
        members.forEach { claimed.insert($0) }
        groups.append(members)
    }

    tlog("bar-items order: " + result.joined(separator: " "))
    for group in groups { tlog("bar-items group: " + group.joined(separator: " ")) }
    tlog("bar-items media-controls: " + (mediaControls ? "on" : "off"))
    return (result, groups, mediaControls)
}

// one drawn right-cluster item, measured by the layout prepass. `content` is
// everything between the paddings, so a solo pill is 10 + content + 10 and a
// group of k is 10 + sum(content) + 8*(k-1) + 10.
struct RightMember {
    let name: String
    let item: BarItem
    let iconInk: CGFloat
    let innerGap: CGFloat
    let labelAdv: CGFloat
    var content: CGFloat { iconInk + innerGap + labelAdv }
}

// name -> index of the group it belongs to; the draw prepass folds every
// member of one index into a single background unit
func groupIndexByItem(_ groups: [[String]]) -> [String: Int] {
    var map: [String: Int] = [:]
    for (index, group) in groups.enumerated() {
        for name in group { map[name] = index }
    }
    return map
}

// --- mihomo proxy throughput ----------------------------------------------
// Read credentials on every sample: Clash can rotate them without a bar restart.
var proxySpeedBusy = false
var proxySpeedPrevious: (endpoint: String, up: Double, down: Double, time: TimeInterval)?
let proxySpeedSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 3
    return URLSession(configuration: config)
}()

func proxySpeedController() -> (URL, String)? {
    let path = NSHomeDirectory() + "/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/config.yaml"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    var values: [String: String] = [:]
    for line in text.components(separatedBy: .newlines) {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t"),
              let colon = line.firstIndex(of: ":") else { continue }
        let key = String(line[..<colon])
        guard key == "external-controller" || key == "secret" else { continue }
        var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") {
            guard let data = ("[" + value + "]").data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [String],
                  let decoded = array.first else { return nil }
            value = decoded
        } else if value.hasPrefix("'"), value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        } else {
            value = value.components(separatedBy: " #")[0].trimmingCharacters(in: .whitespaces)
        }
        values[key] = value
    }
    guard var address = values["external-controller"], !address.isEmpty else { return nil }
    if address.hasPrefix("0.0.0.0:") { address = "127.0.0.1:" + address.dropFirst(8) }
    if address.hasPrefix("[::]:") { address = "[::1]:" + address.dropFirst(5) }
    guard let url = URL(string: "http://" + address + "/connections"),
          url.host != nil else { return nil }
    return (url, values["secret"] ?? "")
}

let proxySpeedFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
// Seven digits cover even multi-gigabit links without moving neighbouring pills.
let proxySpeedWidth: CGFloat = 12 + advance("0000000 KB/s", proxySpeedFont)

func proxySpeedRate(_ bytes: Double) -> String {
    String(format: "%.0f KB/s", bytes / 1_000)
}

func drawProxySpeed(_ item: BarItem, x: CGFloat, midY: CGFloat) {
    let values = item.label.components(separatedBy: "\n")
    for (index, arrow) in ["↑", "↓"].enumerated() {
        let y = midY + (index == 0 ? 5.5 : -5.5)
        let value = values.indices.contains(index) ? values[index] : "—"
        drawText(arrow, proxySpeedFont, palette.muted, leftAt: x, midY: y)
        drawText(value, proxySpeedFont, value == "—" ? palette.muted : palette.label,
                 leftAt: x + proxySpeedWidth - advance(value, proxySpeedFont), midY: y)
    }
}

func updateProxySpeed() {
    guard configuredValue("proxy-speed") == "on", !proxySpeedBusy else { return }
    func offline() {
        proxySpeedPrevious = nil
        set("proxy-speed") { $0.label = "—\n—"; $0.iconColor = \.muted }
    }
    guard let (url, secret) = proxySpeedController() else { offline(); return }
    if rightItems["proxy-speed"] == nil { offline() }
    proxySpeedBusy = true
    var request = URLRequest(url: url)
    request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
    proxySpeedSession.dataTask(with: request) { data, response, error in
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let up = (object?["uploadTotal"] as? NSNumber)?.doubleValue
        let down = (object?["downloadTotal"] as? NSNumber)?.doubleValue
        let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
        let now = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async {
            proxySpeedBusy = false
            guard ok, let up, let down, up.isFinite, down.isFinite else { offline(); return }
            let previous = proxySpeedPrevious
            proxySpeedPrevious = (url.absoluteString, up, down, now)
            guard let previous, previous.endpoint == url.absoluteString,
                  now > previous.time, up >= previous.up, down >= previous.down else {
                set("proxy-speed") { $0.label = "0 KB/s\n0 KB/s"; $0.iconColor = \.label }
                return
            }
            let elapsed = now - previous.time
            let label = proxySpeedRate((up - previous.up) / elapsed) + "\n"
                + proxySpeedRate((down - previous.down) / elapsed)
            set("proxy-speed") { $0.label = label; $0.iconColor = \.label }
        }
    }.resume()
}

// --- fission_fund (Fishing Funds) ------------------------------------------
// The estimator (`~/.config/sketchybar/plugins/fission_fund_estimator.js`)
// stays untouched: `node <script>` prints one JSON object to stdout and that
// object already carries everything the pill and the popup need. Swift owns
// the schedule the sketchybar daemon used to own (bar_daemon.sh:123-143):
// fetch every 600 s, skip while the market is closed, render in-process.

struct FissionFund {
    var main = "\u{2014}"
    var color = "flat"
    var summary = ""
    var summaryIcon = ""
    var rows: [FundLine] = []
    var total: FundLine?
}

var fissionFund: FissionFund?

// shared with the sketchybar config on purpose: the estimator re-reads this
// file for its own 30-minute stale-reuse path (fission_fund_estimator.js:441),
// so whoever runs it owes it the write fission_fund_popup.sh:47-56 did.
let fissionCacheURL = URL(fileURLWithPath: "/tmp/sketchybar_daemon/fission_fund_detail.json")

func nodeBinary() -> String {
    ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "node"
}

// The estimator lives outside this repository and nothing here may assume
// where. No directive means no pill and no Node process, ever.
func fissionEstimatorPath() -> String? {
    guard let path = configuredValue("fission-estimator") else { return nil }
    guard FileManager.default.isReadableFile(atPath: path) else {
        tlog("fission: estimator not readable at \(path)")
        return nil
    }
    return path
}

// bar_daemon.sh:128-140 verbatim: once a closed day's JSON names the next
// trading day, nothing it reports can change before that day, so the
// estimator (network fetch plus a store decrypt) stays asleep until then.
// Pure, so it can be exercised without a fetch.
func fissionShouldFetch(_ cached: [String: Any]?, today: String) -> Bool {
    guard let cached,
          cached["marketStatus"] as? String == "closed",
          let next = cached["nextTradingDay"] as? String, !next.isEmpty
    else { return true }
    return today >= next
}

func shanghaiToday() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return f.string(from: Date())
}

// `.ok == false` is a normal outcome (the Fishing Funds store is missing or
// the quote fetch failed): the pill shows an em dash, exactly as the
// sketchybar version does, and the popup still carries the reason.
func fissionParse(_ o: [String: Any]) -> FissionFund {
    var f = FissionFund()
    let ok = o["ok"] as? Bool ?? false
    f.main = ok ? (o["main"] as? String ?? "\u{2014}") : "\u{2014}"
    f.color = ok ? (o["color"] as? String ?? "flat") : "muted"
    f.summary = o["summary"] as? String ?? ""
    f.summaryIcon = o["summaryIcon"] as? String ?? ""
    // displayRows is the trimmed 16 the popup script renders; rows is the
    // full set it falls back to
    let raw = (o["displayRows"] as? [[String: Any]]) ?? (o["rows"] as? [[String: Any]]) ?? []
    f.rows = raw.prefix(16).compactMap {
        guard let name = $0["name"] as? String else { return nil }
        return FundLine(name: name,
                        rate: ($0["rate"] as? NSNumber)?.doubleValue,
                        profit: ($0["profit"] as? NSNumber)?.doubleValue ?? 0,
                        spark: ($0["spark"] as? [NSNumber] ?? []).map(\.doubleValue))
    }
    if ok, let rate = (o["totalRate"] as? NSNumber)?.doubleValue,
       let profit = (o["totalProfit"] as? NSNumber)?.doubleValue {
        f.total = FundLine(name: "\u{5408}\u{8BA1}", rate: rate, profit: profit,
                           spark: (o["totalSpark"] as? [NSNumber] ?? []).map(\.doubleValue), total: true)
    }
    return f
}

// Only the icon can be tinted per item (the label always draws in
// palette.label). Up/down use the palette's semantic roles; flat falls back
// to palette.label like every other status icon. The Material Design chart-line
// glyph matches the icon set used by wifi, volume, brightness and bluetooth.
func applyFission(_ f: FissionFund) {
    fissionFund = f
    let tint: KeyPath<Palette, NSColor>?
    switch f.color {
    case "up": tint = \.green
    case "down": tint = \.red
    default: tint = nil
    }
    set("fission") { $0.icon = "󰄪"; $0.label = f.main; $0.iconColor = tint }
}

func fissionRows() -> [PopupRow] {
    guard let f = fissionFund else { return [] }
    // the summary time rides the title row's right edge instead of a loose
    // second line, so the figures below own the grid
    var rows: [PopupRow] = [PopupRow(icon: "", text: "Fishing Funds",
                                     detail: f.summaryIcon, hero: true)]
    if let total = f.total {
        var r = PopupRow(); r.fund = total; rows.append(r)
        rows.append(PopupRow(rule: true))
    } else if !f.summary.isEmpty {
        rows.append(PopupRow(text: f.summary, dim: true))
    }
    for line in f.rows { var r = PopupRow(); r.fund = line; rows.append(r) }
    return rows
}

// off the main thread, like primeMedia(): this spawns Node, decrypts a store
// and hits the network. The cache is applied first so a fetch that is skipped
// or fails still paints the last known figure.
func updateFissionFund() {
    guard let estimator = fissionEstimatorPath() else { return }
    rebuildQueue.async {
        let cached = (try? Data(contentsOf: fissionCacheURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        if let cached {
            let f = fissionParse(cached)
            DispatchQueue.main.async { applyFission(f) }
        }
        guard fissionShouldFetch(cached, today: shanghaiToday()) else {
            tlog("fission: closed until \(cached?["nextTradingDay"] as? String ?? "?"), fetch skipped")
            return
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let out = shell(nodeBinary(), [estimator])
        guard let data = out.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] != nil else {
            tlog("fission: estimator gave no usable JSON (\(out.count) bytes)")
            return
        }
        try? FileManager.default.createDirectory(at: fissionCacheURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // .atomic is write-temp-then-rename, so the estimator and the
        // sketchybar popup never read a half-written cache
        try? data.write(to: fissionCacheURL, options: .atomic)
        let f = fissionParse(object)
        tlog(String(format: "fission %@ %@ %d rows %.0f ms", f.main, f.color, f.rows.count,
                    Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
        DispatchQueue.main.async { applyFission(f) }
    }
}

// --- weather (Open-Meteo, via the captain's sketchybar popup script) --------
// The rows are the captain's, verbatim: `weather_popup.sh rows` prints the
// same TSV its sketchybar `render` consumes, and this file only maps the two
// colour names onto omacosy's palette roles. What Swift owns is the part the
// script does NOT do: the script renders the cache and only fetches when the
// cache is ABSENT, so a stale cache would stay stale forever now that
// bar_daemon.sh is not running. bar_daemon.sh:146-171 refreshed it every
// 1800 s; that schedule moves here, with the same python one-liner and the
// same 15 s timeout, importing FORECAST_URL from weather_lib so the 市区
// coordinates live in exactly one place (weather_lib.py:41-53).
//
// Upstream's weatherRows()/updateWeather() are untouched: they still feed the
// `weather` pill. Only the clock popup's second half changes, and only when
// `weather-script` is configured.

let openMeteoCacheURL = URL(fileURLWithPath: "/tmp/sketchybar_daemon/weather.json")

var openMeteoRows: [PopupRow]?

func pythonBinary() -> String {
    ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
}

// Answered per popup open — one small file read, and it keeps the directive
// live, so adding it does not need a bar restart. Deliberately silent:
// weatherScriptPath() is the one that logs an unusable path.
func openMeteoConfigured() -> Bool { configuredValue("weather-script") != nil }

// The script lives outside this repository and nothing here may assume where.
// No directive means the clock popup keeps omacosy's own wttr.in rows.
func weatherScriptPath() -> String? {
    guard let path = configuredValue("weather-script") else { return nil }
    guard FileManager.default.isReadableFile(atPath: path) else {
        tlog("weather: script not readable at \(path)")
        return nil
    }
    return path
}

// where weather_lib.py lives; the script's own parent directory is the
// arrangement in the captain's config, so that is the default
func weatherLibDir(_ script: String) -> String {
    configuredValue("weather-lib") ?? URL(fileURLWithPath: script).deletingLastPathComponent().path
}

// bar_daemon.sh:151-161 minus the sketchybar pill: fetch, write the raw JSON.
// Written temp-then-rename so `weather_popup.sh rows` can never read a
// half-written cache (the shell version writes in place).
let openMeteoFetchSource = """
import os, pathlib, sys, urllib.request
sys.path.insert(0, sys.argv[1])
from weather_lib import FORECAST_URL
raw = urllib.request.urlopen(FORECAST_URL, timeout=15).read()
cache = pathlib.Path(sys.argv[2])
cache.parent.mkdir(parents=True, exist_ok=True)
tmp = cache.with_suffix('.tmp')
tmp.write_bytes(raw)
os.replace(tmp, cache)
print(len(raw))
"""

// TSV is `kind \t iconColour \t labelColour \t glyph \t text`
// (weather_popup.sh:57-80). The two colour names map onto palette ROLES and
// nothing else, so the rows follow whichever of the five themes is set:
// FOAM -> palette.accent (every popup glyph draws in it already, and the
// title row is the accent-bold hero), MUTED -> palette.muted, TEXT ->
// palette.label. No literal colour appears anywhere in this file.
// Three sizes out of the same five lines, because the panel is read in two
// glances: NOW is the headline (.large — glyph and text both), the day rows
// after it are the tail (.small, muted). The script prints today's forecast
// first (weather_popup.sh: `dl['time'][:3]` starting at today), so the first
// MUTED row is still today and stays body-sized and unmuted; only tomorrow
// onward recedes. A rule separates the live conditions from the forecast, the
// same break the script's own `render` draws with its `sep` item.
func openMeteoParse(_ tsv: String) -> [PopupRow] {
    var rows: [PopupRow] = []
    var forecastIndex = 0
    for line in tsv.components(separatedBy: .newlines) {
        let f = line.components(separatedBy: "\t")
        guard f.count >= 5, !f[0].isEmpty else { continue }
        let glyph = f[3], text = f[4]
        let isTitle = f[0] == "TITLE"
        let isForecast = !isTitle && f[2] == "MUTED"
        // the title is omacosy's hero row: accent and bold, the same section
        // break weatherRows() opens with
        var row = PopupRow(icon: glyph, text: text,
                           hero: isTitle, muted: isForecast && forecastIndex > 0)
        if isTitle {
            row.scale = .large
        } else if isForecast {
            if forecastIndex == 0 { rows.append(dividerRow()) }
            // .small also dims the glyph at DRAW time (iconColor below), so
            // this stays pure: no palette is baked in on the fetch queue,
            // and a theme change repaints these rows in the new accent
            row.scale = forecastIndex == 0 ? .normal : .small
            forecastIndex += 1
        }
        rows.append(row)
    }
    return rows
}

// --- the two-column panel --------------------------------------------------
// `weather_popup.sh json` prints the same cache the TSV mode renders, but as
// DATA: the mapping from WMO code to 中文 + glyph still lives in weather_lib
// alone, and the layout lives here alone. That split is the whole reason for
// a second mode rather than parsing the pre-formatted strings back apart.
struct WeatherPanel {
    var card = WeatherCard()
    var days: [TrendDay] = [] // tomorrow onward; today is the card
}

var openMeteoPanel: WeatherPanel?

func openMeteoParsePanel(_ text: String) -> WeatherPanel? {
    guard let data = text.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let current = root["current"] as? [String: Any],
          let days = root["days"] as? [[String: Any]], !days.isEmpty else { return nil }
    func num(_ d: [String: Any], _ key: String) -> Int { (d[key] as? NSNumber)?.intValue ?? 0 }
    func str(_ d: [String: Any], _ key: String) -> String { d[key] as? String ?? "" }

    let sep = "  ·  " // the separator the shell panel uses, kept verbatim
    var panel = WeatherPanel()
    let today = days[0]
    panel.card.glyph = str(current, "icon")
    panel.card.temp = "\(num(current, "temp"))°"
    panel.card.range = "\(num(today, "min"))~\(num(today, "max"))°"
    panel.card.desc = [str(current, "desc"), str(root, "location")]
        .filter { !$0.isEmpty }.joined(separator: sep)
    var detail = ["体感 \(num(current, "feels"))°", "湿度 \(num(current, "humidity"))%"]
    let tightSep = " · "
    // a probability of nothing is worth no ink; the script prints -1 when the
    // source omits it
    if num(today, "pop") >= 0 { detail.append("降水 \(num(today, "pop"))%") }
    panel.card.detail = detail.joined(separator: tightSep)

    let rest = Array(days.dropFirst())
    guard !rest.isEmpty else { return panel }
    // one window for the whole column, padded by a degree so a bar never
    // touches either end of its track
    let low = Double(rest.map { num($0, "min") }.min() ?? 0) - 2
    let high = Double(rest.map { num($0, "max") }.max() ?? 1) + 2
    // the highs' own range, which is what the tint ranks against
    let highs = rest.map { num($0, "max") }
    let coolest = Double(highs.min() ?? 0)
    let warmest = Double(highs.max() ?? 0)
    for (i, day) in rest.enumerated() {
        var d = TrendDay()
        d.name = str(day, "name")
        d.glyph = str(day, "icon")
        d.low = num(day, "min")
        d.high = num(day, "max")
        d.spanLow = low
        d.spanHigh = max(high, low + 1)
        d.fade = max(0.55, 1 - CGFloat(i) * 0.11)
        // scaled against a 5° swing, not against the week's own spread: a
        // week whose highs differ by one degree must not paint that degree
        // as the whole cool-to-warm range
        d.warmth = CGFloat(min(1, (Double(d.high) - coolest) / max(5, warmest - coolest)))
        panel.days.append(d)
    }
    return panel
}

// card, a quiet section label, then one bar per day
func weatherPanelRows() -> [PopupRow] {
    guard let panel = openMeteoPanel else { return [] }
    var card = PopupRow()
    card.card = panel.card
    var rows = [card]
    guard !panel.days.isEmpty else { return rows }
    rows.append(PopupRow(text: "未来 \(panel.days.count) 天", dim: true))
    for day in panel.days {
        var row = PopupRow()
        row.trend = day
        rows.append(row)
    }
    return rows
}

func applyOpenMeteoPanel(_ panel: WeatherPanel) {
    openMeteoPanel = panel
    tlog("weather panel: \(panel.card.temp) \(panel.card.desc) + \(panel.days.count) days")
    if openPopup == "clock" { refreshPopup() }
}

func applyOpenMeteo(_ rows: [PopupRow]) {
    openMeteoRows = rows
    for row in rows where !row.rule {
        tlog("weather row: \(row.hero ? "TITLE" : (row.muted ? "MUTED" : "TEXT"))|\(row.scale)|\(row.icon)|\(row.text)")
    }
    if openPopup == "clock" { refreshPopup() }
}

// off the main thread, like primeMedia() and updateFissionFund(): this spawns
// python twice and hits the network with a 15 s timeout. The existing cache is
// rendered first, so a fetch that fails still paints the last known weather.
func updateOpenMeteoWeather() {
    guard let script = weatherScriptPath() else { return }
    let lib = weatherLibDir(script)
    rebuildQueue.async {
        func render(_ why: String) {
            // `json` is the panel's own shape (today as a block, the days after
            // it as bars). A weather_popup.sh without that mode prints nothing
            // for it, and the flat TSV panel is still a correct answer.
            let out = shell("/bin/bash", [script, "json"])
            if let panel = openMeteoParsePanel(out) {
                DispatchQueue.main.async { applyOpenMeteoPanel(panel) }
                return
            }
            let tsv = shell("/bin/bash", [script, "rows"])
            let rows = openMeteoParse(tsv)
            guard !rows.isEmpty else {
                tlog("weather: \(why) render gave nothing (\(out.count) json, \(tsv.count) tsv bytes)")
                return
            }
            DispatchQueue.main.async { applyOpenMeteo(rows) }
        }
        // only when a cache already exists: `rows` on an absent cache runs the
        // script's own fallback fetch, which this refresh is about to do anyway
        if let size = (try? FileManager.default.attributesOfItem(atPath: openMeteoCacheURL.path)[.size]) as? Int,
           size > 0 {
            render("cached")
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let bytes = shell(pythonBinary(), ["-c", openMeteoFetchSource, lib, openMeteoCacheURL.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bytes.isEmpty else {
            tlog("weather: Open-Meteo fetch failed, keeping the cached rows")
            return
        }
        tlog(String(format: "weather: fetched %@ bytes in %.0f ms", bytes,
                    Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
        render("fresh")
    }
}

// --- AI usage (Claude / Codex quota) ---------------------------------------
// Both providers are derived here from the actual windows: Codex Pro can omit
// primary entirely, and the external script assumes fixed slots. Its TSV now
// only enables the pill and supplies extra rows. The bar fetches both raw
// caches every 300 s, off main; neither clicks nor drawing touch the network.

struct AIRow {
    let target: String // title | head2 | c.N | x.N
    let iconColor: String // colour NAMES, mapped onto the omacosy palette
    let labelColor: String
    let left: String // the row's name column
    let right: String // gauge + percent + countdown
}

struct AIUsage {
    var rows: [AIRow] = []
    var claude: (pct: Int, stale: Bool)?
    var claudeLabel = "—"
    var codex: (pct: Int, stale: Bool)?
    var codexLabel = "—"
}

var aiUsage = AIUsage()

// shared with the sketchybar daemon on purpose: same paths, same schema, so
// either side can be the one that filled them
// Override only for isolated validation; the installed bar shares the default.
let aiCacheDir = URL(fileURLWithPath:
    ProcessInfo.processInfo.environment["OMACOSY_AI_CACHE_DIR"] ?? "/tmp/sketchybar_daemon")
// a cache older than three fetch intervals is not a reading any more, it is
// the last thing the network said before it stopped answering
let aiStaleAfter: TimeInterval = 900

// The script lives outside this repository and nothing here may assume where.
// No directive means no pill, no popup and no codexbar process, ever.
let aiScript: String? = {
    guard let path = configuredValue("ai-usage-script") else { return nil }
    guard FileManager.default.isReadableFile(atPath: path) else {
        tlog("ai: usage script not readable at \(path)")
        return nil
    }
    return path
}()

let codexbarBinary: String = {
    if let path = configuredValue("codexbar") {
        if FileManager.default.isExecutableFile(atPath: path) { return path }
        tlog("ai: codexbar not executable at \(path)")
    }
    return ["/opt/homebrew/bin/codexbar", "/usr/local/bin/codexbar"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "codexbar"
}()

func aiCacheURL(_ provider: String) -> URL {
    aiCacheDir.appendingPathComponent("\(provider)_raw.json")
}

// The script names colours; the theme decides what they look like. Every
// name lands on a palette ROLE, never on a hex value, so the pill and the
// panel follow theme-set like everything else on this bar. IRIS has no
// natural role here and takes the label colour, as does anything unknown.
func aiColor(_ name: String) -> NSColor {
    switch name {
    case "MUTED": return palette.muted
    case "LOVE": return palette.red
    case "GOLD": return palette.yellow
    case "FOAM": return palette.accent
    default: return palette.label // TEXT, IRIS, and anything this fork does not know
    }
}

// bar_daemon.sh:213 verbatim in intent: structure complete or nothing is
// written — a half-fetched JSON in the cache would make the popup show
// nonsense instead of the previous round's numbers.
func aiFetch(_ provider: String) {
    guard FileManager.default.isExecutableFile(atPath: codexbarBinary) else {
        tlog("ai: no codexbar at \(codexbarBinary)")
        return
    }
    let t0 = DispatchTime.now().uptimeNanoseconds
    let out = shell(codexbarBinary,
                    ["usage", "--provider", provider, "--format", "json",
                     "--no-color", "--web-timeout", "20"])
    guard let data = out.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          array.first?["usage"] is [String: Any] else {
        tlog("ai: \(provider) gave no usable JSON (\(out.count) bytes)")
        return
    }
    try? FileManager.default.createDirectory(at: aiCacheDir, withIntermediateDirectories: true)
    try? data.write(to: aiCacheURL(provider), options: .atomic)
    tlog(String(format: "ai fetch %@ %d bytes %.0f ms", provider, data.count,
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

struct AIWindow {
    let name: String
    let pct: Int // USED percent, like Claude and the existing gauge
    let resetsAt: String?
}

// Both providers report the same shape: primary/secondary/tertiary plus
// scoped extra windows (Claude's Fable-only weekly, Codex's reviews).
func aiWindows(_ usage: [String: Any]) -> [AIWindow] {
    var candidates = ["primary", "secondary", "tertiary"].compactMap { key -> (String, [String: Any], Bool)? in
        guard let window = usage[key] as? [String: Any] else { return nil }
        return (key.capitalized, window, false)
    }
    for extra in usage["extraRateWindows"] as? [[String: Any]] ?? [] {
        if let window = extra["window"] as? [String: Any] {
            candidates.append((extra["title"] as? String ?? "Window", window, true))
        }
    }
    return candidates.compactMap { fallback, window, scoped in
        guard let number = window["usedPercent"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (0...100).contains(number.doubleValue) else { return nil }
        var name = fallback
        // Scoped windows keep their supplied title rather than all becoming "7d".
        if !scoped, let minutes = window["windowMinutes"] as? Int, minutes > 0 {
            name = minutes % 1440 == 0 ? "\(minutes / 1440)d"
                : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m")
        }
        return AIWindow(name: name, pct: Int(number.doubleValue), resetsAt: window["resetsAt"] as? String)
    }
}

func aiCachedUsage(_ provider: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: aiCacheURL(provider)),
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
    return array.first?["usage"] as? [String: Any]
}

func aiPillLabel(_ usage: [String: Any]?) -> String {
    let windows = usage.map(aiWindows) ?? []
    guard let window = windows.first(where: { $0.name == "5h" }) else { return "—" }
    return "5h \(window.pct)%"
}

// Prefer the normal primary window; weekly-only plans fall through to the
// first reported window. Missing windows are not zero usage or stale data.
func aiPrimary(_ provider: String) -> (pct: Int, stale: Bool)? {
    guard let usage = aiCachedUsage(provider), let window = aiWindows(usage).first else { return nil }
    let modified = (try? aiCacheURL(provider).resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
    return (window.pct, Date().timeIntervalSince(modified) > aiStaleAfter)
}

func aiRemaining(_ end: Date, now: Date) -> String {
    let left = max(0, Int(end.timeIntervalSince(now)))
    let d = left / 86400, h = left % 86400 / 3600, m = left % 3600 / 60
    return d > 0 ? "\(d)d\(h)h" : (h > 0 ? "\(h)h\(m)m" : "\(m)m")
}

// One provider section: a heading with the plan (brand prefix trimmed, so
// "Claude Pro" reads "Claude  ·  Pro"), then one gauge per reported window.
func aiWindowRows(_ usage: [String: Any]?, brand: String, head: String, slot: String,
                  now: Date) -> [AIRow] {
    let windows = usage.map(aiWindows) ?? []
    guard let usage, !windows.isEmpty else {
        return [AIRow(target: head, iconColor: "MUTED", labelColor: "MUTED",
                      left: "", right: "\(brand) 用量暂不可用")]
    }
    let identity = usage["identity"] as? [String: Any]
    var plan = (usage["loginMethod"] as? String ?? identity?["loginMethod"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if plan == "self_serve_business_prolite" { plan = "Pro" }
    if plan.lowercased().hasPrefix(brand.lowercased()) {
        plan = String(plan.dropFirst(brand.count)).trimmingCharacters(in: .whitespaces)
    }
    plan = plan.prefix(1).uppercased() + plan.dropFirst()
    var rows = [AIRow(target: head, iconColor: "TEXT", labelColor: "TEXT", left: "",
                      right: [brand, plan].filter { !$0.isEmpty }.joined(separator: "  ·  "))]
    let formatter = ISO8601DateFormatter()
    for (index, window) in windows.enumerated() {
        let hit = Int((Double(window.pct) / 100 * 12).rounded(.toNearestOrEven))
        var text = String(repeating: "█", count: hit) + String(repeating: "░", count: 12 - hit)
            + " \(window.pct)%"
        if let stamp = window.resetsAt, let end = formatter.date(from: stamp) {
            text += "  ↻\(aiRemaining(end, now: now))"
        }
        rows.append(AIRow(target: "\(slot).\(index + 1)", iconColor: "MUTED",
                          labelColor: window.pct > 80 ? "LOVE" : (window.pct > 60 ? "GOLD" : "TEXT"),
                          left: window.name, right: text))
    }
    return rows
}

// Saved reset credits that are usable now, as one "重置机会" row after the
// window rows. `key` is the usage field omp_usage.py fills per provider.
func aiResetRow(_ usage: [String: Any], rows: [AIRow], key: String, type: String,
                slot: String, now: Date) -> AIRow? {
    let credits = (usage[key] as? [String: Any])?["credits"] as? [[String: Any]] ?? []
    let available = credits.filter {
        ($0["reset_type"] as? String) == type && ($0["status"] as? String) == "available"
    }
    guard !available.isEmpty else { return nil }
    let count = available.reduce(0) { $0 + max(1, ($1["remaining_count"] as? Int) ?? 1) }
    var text = "\(count) 次可用"
    let formatter = ISO8601DateFormatter()
    let expiries = available.compactMap { credit -> Date? in
        guard let stamp = credit["expires_at"] as? String else { return nil }
        return formatter.date(from: stamp)
    }
    if let expiry = expiries.min() {
        text += " · 最近到期 \(aiRemaining(expiry, now: now))"
    }
    return AIRow(target: "\(slot).\(rows.count)", iconColor: "MUTED",
                 labelColor: "TEXT", left: "重置机会", right: text)
}

func aiClaudeRows(_ usage: [String: Any]?, now: Date = Date()) -> [AIRow] {
    var rows = aiWindowRows(usage, brand: "Claude", head: "title", slot: "c", now: now)
    guard let usage, rows.count > 1 else { return rows }
    if let row = aiResetRow(usage, rows: rows, key: "claudeResetCredits",
                            type: "claude_rate_limits", slot: "c", now: now) {
        rows.append(row)
    }
    return rows
}

func aiCodexRows(_ usage: [String: Any]?, now: Date = Date()) -> [AIRow] {
    var rows = aiWindowRows(usage, brand: "Codex", head: "head2", slot: "x", now: now)
    guard let usage, rows.count > 1 else { return rows }
    if let row = aiResetRow(usage, rows: rows, key: "codexResetCredits",
                            type: "codex_rate_limits", slot: "x", now: now) {
        rows.append(row)
    }
    return rows
}

func applyAIUsage(_ usage: AIUsage) {
    aiUsage = usage
    tlog("ai rows: " + usage.rows.map {
        "\($0.target)|\($0.iconColor)|\($0.labelColor)|\($0.left)|\($0.right)"
    }.joined(separator: " ~ "))
    repaint()
    if openPopup == "ai" { refreshPopup() }
}

func aiParsedUsage(_ out: String) -> AIUsage {
    var usage = AIUsage()
    for line in out.components(separatedBy: .newlines) where !line.isEmpty {
        let f = line.components(separatedBy: "\t")
        guard f.count == 5 else { continue }
        if f[0] == "head2" || f[0].hasPrefix("x.") || f[0] == "sep"
            || f[0].hasPrefix("c.") || f[0] == "title" { continue }
        let left = f[3] == "\u{25CF}" ? "" : f[3]
        let right = f[4] == "\u{25CF}" ? "" : f[4]
        if left == "__OFF__" { continue }
        usage.rows.append(AIRow(target: f[0], iconColor: f[1], labelColor: f[2],
                                left: left, right: right))
    }
    let claudeUsage = aiCachedUsage("claude")
    usage.rows.append(contentsOf: aiClaudeRows(claudeUsage))
    usage.claude = aiPrimary("claude")
    usage.claudeLabel = aiPillLabel(claudeUsage)
    let codexUsage = aiCachedUsage("codex")
    usage.rows.append(contentsOf: aiCodexRows(codexUsage))
    usage.codex = aiPrimary("codex")
    usage.codexLabel = aiPillLabel(codexUsage)
    return usage
}

// off the main thread, like primeMedia(): `rows` spawns bash and python3.
func aiRenderRows() {
    guard let script = aiScript else { return }
    rebuildQueue.async {
        let usage = aiParsedUsage(shell("/bin/bash", [script, "rows"]))
        DispatchQueue.main.async { applyAIUsage(usage) }
    }
}

func updateAIUsage() {
    guard aiScript != nil else { return }
    aiRenderRows() // paint whatever the caches already hold
    rebuildQueue.async {
        aiFetch("claude")
        aiFetch("codex")
        aiRenderRows() // same serial queue, so this runs on the fresh caches
    }
}

func aiRows() -> [PopupRow] {
    guard !aiUsage.rows.isEmpty else { return [] }
    let iconFont = nerdFont("Bold", 13)
    // one column for both providers: the two sections read as one panel only
    // if their name columns share an edge
    let column = aiUsage.rows.filter { $0.target != "title" && $0.target != "head2" }
        .map { advance($0.left, iconFont) }.max() ?? 0
    return aiUsage.rows.map { row in
        guard row.target == "title" || row.target == "head2" else {
            return PopupRow(icon: row.left, text: row.right,
                            tint: aiColor(row.labelColor), iconTint: aiColor(row.iconColor),
                            iconColumn: column)
        }
        // the section heads keep the popup's own hero accent; the script only
        // ever recolours them to say "this provider has no data"
        return PopupRow(icon: row.target == "title" ? aiClaudeGlyph : aiCodexGlyph,
                        text: row.right, hero: true,
                        tint: row.labelColor == "MUTED" ? palette.muted : nil,
                        iconTint: aiColor(row.iconColor))
    }
}

// --- the combined AI pill (left cluster) -----------------------------------
// One pill for both personal accounts: each provider's glyph followed by its
// 5h and 7d windows, the two segments 10 apart.

let aiClaudeGlyph = "\u{EC82}" // cod-claude
let aiCodexGlyph = "\u{EC81}" // cod-openai
let aiSegmentGap: CGFloat = 10

func aiTone(_ value: (pct: Int, stale: Bool)?) -> NSColor {
    guard let value, !value.stale else { return palette.muted }
    // the thresholds the popup's gauge() uses, so pill and panel agree
    return value.pct > 80 ? palette.red : (value.pct > 60 ? palette.yellow : palette.label)
}

func aiSegments() -> [(glyph: String, text: String, tint: NSColor, dim: Bool)] {
    guard aiScript != nil else { return [] }
    return [(aiClaudeGlyph, aiUsage.claudeLabel,
             aiTone(aiUsage.claude), aiUsage.claude?.stale ?? true),
            (aiCodexGlyph, aiUsage.codexLabel,
             aiTone(aiUsage.codex), aiUsage.codex?.stale ?? true)]
}
func aiPillWidth(_ labelFont: NSFont, _ iconFont: NSFont) -> CGFloat {
    let segments = aiSegments()
    guard !segments.isEmpty else { return 0 }
    var width: CGFloat = 20
    for (index, segment) in segments.enumerated() {
        if index > 0 { width += aiSegmentGap }
        width += inkBox(segment.glyph, iconFont).width + 7 + advance(segment.text, labelFont)
    }
    return width
}

func drawAIPill(in pill: NSRect, _ labelFont: NSFont, _ iconFont: NSFont) {
    palette.itemBG.setFill()
    NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
    var x = pill.minX + 10
    for (index, segment) in aiSegments().enumerated() {
        if index > 0 { x += aiSegmentGap }
        let ink = inkBox(segment.glyph, iconFont).width
        // the glyph carries the usage tone, as the fission pill does; a stale
        // reading mutes the number too, because then it is not a reading
        drawIcon(segment.glyph, iconFont, segment.tint,
                 centeredIn: NSRect(x: x, y: pill.minY, width: ink, height: pill.height))
        drawText(segment.text, labelFont, segment.dim ? palette.muted : palette.label,
                 leftAt: x + ink + 7, midY: pill.midY)
        x += ink + 7 + advance(segment.text, labelFont)
    }
}

// `workspaces-max <n>` in bar-items.conf: the left cluster is the scarcer of
// the two on a notched display, and the chips are the only part of it that
// grows without saying anything new. Absent = every slot, i.e. upstream.
let workspacesMax: Int? = configuredValue("workspaces-max").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }

// the first n slots, plus any slot past n that holds something or is the one
// being looked at — a limit that hid the workspace you are ON would be worse
// than no limit
func limitWorkspaces(_ shown: [String], visible: String) -> [String] {
    guard let limit = workspacesMax, shown.count > limit else { return shown }
    return shown.enumerated().filter { index, ws in
        index < limit || model.occupied.contains(ws) || ws == model.focused || ws == visible
    }.map(\.element)
}

func btopBinary() -> String {
    ["/opt/homebrew/bin/btop", "/usr/local/bin/btop"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "btop"
}

// --- AirPods battery -------------------------------------------------------
// The sketchybar item (`plugins/airpods.sh`, `bar_daemon.sh:180-198`) is a
// plain pill: `L/R · Case%`, hidden unless the device is CONNECTED.
// `system_profiler SPBluetoothDataType` is the heaviest poll in this bar, so
// it runs off the main queue, only every 180 s, and not at all while the
// radio is off — nothing can be connected then. `-json` reports the same
// four facts the script greps for, without its "20 lines after the name"
// heuristic, so this reads the structure instead of the text.

// nf-md-headphones, the glyph airpods.sh sets. Nerd Fonts v3 dropped the
// v2 material-design block (F500-FD46) and moved the glyph to F02CB, so the
// codepoint is chosen by what the resolved face actually covers — hardcoding
// either one draws .notdef on the other font generation.
let airpodsGlyph: String = {
    let font = nerdFont("Bold", 14) as CTFont
    let set = CTFontCopyCharacterSet(font)
    return CFCharacterSetIsLongCharacterMember(set, 0xF02CB) ? "\u{F02CB}" : "\u{F7CA}"
}()

// `airpods-name <device name>` in bar-items.conf — the device label as
// Bluetooth reports it. Absent = the item never registers and
// system_profiler never runs.
let airpodsName: String? = configuredValue("airpods-name")

// pure, so it can be exercised against a saved system_profiler dump.
// Only connected entries with a matching CoreAudio Bluetooth output count.
// BLE-only battery telemetry and paired-but-idle devices do not.
//
// Matching is two-tier: the `airpods-name` device wins whenever it is
// connected AND reports a level (the original behaviour, untouched), and any
// OTHER connected Headphones/Headset that reports one is the fallback — a
// second pair of cans on the same machine lights the same pill instead of
// leaving it blank. A connected device that reports NO level is never a
// match, so the pill still hides rather than invent a reading.
//
// Key variants: Apple's two-ear devices use device_batteryLevel{Left,Right,
// Case}; single-cell devices (over-ears, mice, keyboards) report one level
// under device_batteryLevelMain, and some macOS builds spell the whole family
// device_batteryPercent*. All of them are read, and a single level renders as
// `NN%` instead of the `L/R` pair.
func airpodsParse(_ json: Data, name: String?, connectedOutputNames: Set<String>) -> (label: String, avg: Int)? {
    guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
          let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

    // one connected entry -> its reading, or nil when it reports no level
    func reading(_ device: [String: Any]) -> (label: String, avg: Int)? {
        func level(_ keys: String...) -> Int? {
            for k in keys {
                if let v = (device[k] as? String)
                    .map({ $0.replacingOccurrences(of: "%", with: "") })
                    .flatMap(Int.init) { return v }
            }
            return nil
        }
        let left = level("device_batteryLevelLeft", "device_batteryPercentLeft")
        let right = level("device_batteryLevelRight", "device_batteryPercentRight")
        let box = level("device_batteryLevelCase", "device_batteryPercentCase")
        let single = level("device_batteryLevelMain", "device_batteryPercentMain",
                           "device_batteryLevelSingle", "device_batteryPercentSingle",
                           "device_batteryLevel", "device_batteryPercent")
        // airpods.sh:26-34: the tone follows the ear average, or the one
        // ear that reports when only one does
        switch (left, right) {
        case let (l?, r?): return (earLabel("\(l)", "\(r)", box), (l + r) / 2)
        case let (l?, nil): return (earLabel("\(l)", "?", box), l)
        case let (nil, r?): return (earLabel("?", "\(r)", box), r)
        default: break
        }
        // one cell: `NN%`, the case level standing in when it is all there is
        if let one = single ?? box { return ("\(one)%", one) }
        return nil
    }

    var fallback: (label: String, avg: Int)?
    for section in sections {
        guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
        for entry in connected {
            for (deviceName, value) in entry {
                guard connectedOutputNames.contains(deviceName),
                      let device = value as? [String: Any],
                      let found = reading(device) else { continue }
                if deviceName == name { return found }         // configured device wins
                guard fallback == nil else { continue }
                let kind = (device["device_minorType"] as? String ?? "").lowercased()
                if kind.contains("headphone") || kind.contains("headset") { fallback = found }
            }
        }
    }
    return fallback
}

// `L/R` plus the case level when the charging case reports one
func earLabel(_ left: String, _ right: String, _ box: Int?) -> String {
    var label = left + "/" + right
    if let box { label += " · \(box)%" }
    return label
}

// system_profiler is bluetoothd's PUBLISHED view, and it simply omits battery
// for W1-era devices — the Beats Solo3 (vendor 0x004C, product 0x2006) lists
// only address/firmware/rssi there, while the macOS Bluetooth menu shows a
// percentage for the same headphones. Every other public channel is silent on
// it too (ioreg AppleDeviceManagementHIDEventService and IOBluetoothDevice's
// registry node, /Library/Preferences/com.apple.Bluetooth, the ByHost defaults,
// bluetoothd's log stream). The reading does exist on IOBluetoothDevice, whose
// `batteryPercent{Single,Left,Right,Case,Combined}` accessors are undocumented
// but ObjC-visible on the PUBLIC framework, so KVC reaches them — the same
// dependency class as this bar's SkyLight/DisplayServices use, and it needs no
// entitlement, no daemon and no run loop (~66 ms off main, autolinked by the
// import).
//
// `responds(to:)` guards every read because valueForUndefinedKey raises an ObjC
// exception Swift cannot catch: a macOS that renames an accessor hides the pill
// instead of killing the bar. 0 is bluetoothd's "nothing reported" sentinel, so
// it is read as absent — a headphone at a true 0% is off, not connected.
func airpodsIOBluetooth(name: String?, connectedOutputNames: Set<String>) -> (label: String, avg: Int)? {
    func level(_ device: AnyObject, _ key: String) -> Int? {
        guard device.responds(to: Selector(key)),
              let n = device.value(forKey: key) as? Int, n > 0 else { return nil }
        return n
    }
    func reading(_ d: AnyObject) -> (label: String, avg: Int)? {
        let left = level(d, "batteryPercentLeft")
        let right = level(d, "batteryPercentRight")
        let box = level(d, "batteryPercentCase")
        switch (left, right) {
        case let (l?, r?): return (earLabel("\(l)", "\(r)", box), (l + r) / 2)
        case let (l?, nil): return (earLabel("\(l)", "?", box), l)
        case let (nil, r?): return (earLabel("?", "\(r)", box), r)
        default: break
        }
        if let one = level(d, "batteryPercentSingle")
            ?? level(d, "batteryPercentCombined") ?? box { return ("\(one)%", one) }
        return nil
    }
    var fallback: (label: String, avg: Int)?
    for case let device as IOBluetoothDevice in (IOBluetoothDevice.pairedDevices() ?? []) {
        guard let deviceName = device.name, connectedOutputNames.contains(deviceName),
              device.isConnected(), let found = reading(device) else { continue }
        if device.name == name { return found }             // configured device wins
        // major class Audio — the Beats report major 4, minor 6 (Headphones)
        if fallback == nil, device.deviceClassMajor == 0x04 { fallback = found }
    }
    return fallback
}

// airpods.sh:36-42 mapped onto palette roles: LOVE→red, GOLD→yellow,
// FOAM→accent. The label draws in palette.label, as every pill's does.
func airpodsTone(_ avg: Int) -> KeyPath<Palette, NSColor> {
    avg < 30 ? \.red : (avg < 60 ? \.yellow : \.accent)
}

func updateAirPods() {
    guard let name = airpodsName else { return }
    guard BTGetPower() != 0 else {
        tlog("airpods: bluetooth radio off, system_profiler skipped")
        set("airpods") { $0.drawing = false }
        return
    }
    guard !connectedBluetoothOutputNames().isEmpty else {
        tlog("airpods: no connected Bluetooth audio output")
        set("airpods") { $0.drawing = false }
        return
    }
    rebuildQueue.async {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let out = shell("/usr/sbin/system_profiler", ["-json", "SPBluetoothDataType"])
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        let connectedOutputNames = connectedBluetoothOutputNames()
        // Both battery sources must agree with the actual audio connection.
        guard let found = out.data(using: .utf8).flatMap({
            airpodsParse($0, name: name, connectedOutputNames: connectedOutputNames)
        }) ?? airpodsIOBluetooth(name: name, connectedOutputNames: connectedOutputNames) else {
            tlog(String(format: "airpods: no connected device reports battery (%.0f ms)", ms))
            DispatchQueue.main.async { set("airpods") { $0.drawing = false } }
            return
        }
        tlog(String(format: "airpods %@ avg %d (%.0f ms)", found.label, found.avg, ms))
        DispatchQueue.main.async {
            guard connectedBluetoothOutputNames() == connectedOutputNames else {
                updateAirPods()
                return
            }
            set("airpods") {
                $0.drawing = true
                $0.icon = airpodsGlyph
                $0.iconColor = airpodsTone(found.avg)
                $0.label = found.label
            }
        }
    }
}

// --- sleep toggle (`caffeinate on`) -----------------------------------------
// The pill flips the system-wide `pmset -a disablesleep` switch. A caffeinate
// assertion cannot stop clamshell sleep, so closing the lid used to stop
// downloads and media serving; disablesleep keeps the machine awake with the
// lid shut while the display still sleeps normally. The setting is root-owned
// and survives reboots, so the SYSTEM holds the state, not the bar: every
// render re-reads `pmset -g`. Writing needs a sudoers rule that allows exactly
// `/usr/bin/pmset -a disablesleep 0|1` without a password
// (`bin/omacosy-sleep-sudoers`); without it `sudo -n` fails, the failure is
// logged, and the pill keeps showing the real state.

let caffeineGlyphOn = "\u{F0F4}"  // nf-fa-coffee,  icons.sh ICON_CAFFEINE
let caffeineGlyphOff = "\u{F186}" // nf-fa-moon_o,  icons.sh ICON_CAFFEINE_OFF

// `caffeinate on` in bar-items.conf. Absent = the item never registers, the
// timer never renders it, and pmset is never touched.
let caffeinateEnabled = configuredValue("caffeinate") == "on"

let caffeinateQueue = DispatchQueue(label: "omacosy.caffeinate")
// main-thread state: the last value read from pmset, and a guard so two fast
// clicks cannot both read "off" and both write "on"
var sleepDisabled = false
var caffeinateBusy = false

// `pmset -g` prints ` SleepDisabled\t\t1`; nil when the line is missing, so an
// unreadable state never overwrites the last known one.
func readSleepDisabled() -> Bool? {
    for line in shell("/usr/bin/pmset", ["-g"]).components(separatedBy: .newlines) {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if fields.count == 2, fields[0] == "SleepDisabled" { return fields[1] == "1" }
    }
    return nil
}

func renderCaffeinate() {
    guard caffeinateEnabled else { return }
    caffeinateQueue.async {
        let state = readSleepDisabled()
        DispatchQueue.main.async {
            if let state { sleepDisabled = state }
            set("caffeinate") {
                $0.drawing = true
                $0.icon = sleepDisabled ? caffeineGlyphOn : caffeineGlyphOff
                // IRIS has no palette role; accent is this bar's "active" tone
                $0.iconColor = sleepDisabled ? \.accent : \.muted
                $0.label = ""
            }
        }
    }
}

func toggleCaffeinate() {
    guard caffeinateEnabled, !caffeinateBusy else { return }
    caffeinateBusy = true
    caffeinateQueue.async {
        defer {
            DispatchQueue.main.async {
                caffeinateBusy = false
                renderCaffeinate()
            }
        }
        guard let current = readSleepDisabled() else {
            tlog("sleep toggle: pmset -g reported no SleepDisabled line")
            return
        }
        let target = current ? "0" : "1"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", target]
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            tlog("sleep toggle: \(error)")
            return
        }
        let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let reason = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            tlog("sleep toggle: sudo pmset exited \(proc.terminationStatus): \(reason)")
            return
        }
        tlog("sleep toggle: disablesleep \(target)")
    }
}

// Earlier versions of this pill (and the sketchybar plugin before them) kept
// sleep off by spawning a caffeinate child; one that lost its pid file kept the
// display awake for weeks after nothing tracked it. On every bar start, reap
// those leftovers: this user's caffeinate processes whose parent is launchd
// (orphans) and whose command line is exactly one the old pill spawned. A
// caffeinate run from a terminal still has its shell as parent and is never
// touched. Runs even with the pill disabled, since the leftovers predate it.
func reapLegacyCaffeinate() {
    caffeinateQueue.async {
        let listing = shell("/bin/ps", ["-U", "\(getuid())", "-o", "pid=,ppid=,args="])
        for line in listing.components(separatedBy: .newlines) {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = pid_t(fields[0]), fields[1] == "1" else { continue }
            let args = String(fields[2]).trimmingCharacters(in: .whitespaces)
            guard args == "/usr/bin/caffeinate -dims" ||
                  args.range(of: #"^/usr/bin/caffeinate -dims -w [0-9]+$"#,
                             options: .regularExpression) != nil else { continue }
            let result = kill(pid, SIGTERM) == 0 ? "ok" : "errno \(errno)"
            tlog("reaped orphan caffeinate pid \(pid) (\(args)): \(result)")
        }
        for stale in ["/tmp/omacosy-bar/caffeinate.pid", "/tmp/omacosy-bar/caffeinate.owner",
                      "/tmp/omacosy-bar/caffeinate.lock", "/tmp/sketchybar_caffeinate.pid"] {
            try? FileManager.default.removeItem(atPath: stale)
        }
    }
}

// prime + the validation hook. OMACOSY_CAFFEINATE_TEST=toggle,toggle drives
// the toggle without clicking a live bar; it exists only for this block.
func startCaffeinate() {
    reapLegacyCaffeinate()
    guard caffeinateEnabled else { return }
    renderCaffeinate()
    guard let plan = ProcessInfo.processInfo.environment["OMACOSY_CAFFEINATE_TEST"] else { return }
    for (index, step) in plan.split(separator: ",").enumerated() where step == "toggle" {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0 * Double(index + 1)) {
            toggleCaffeinate()
        }
    }
}

// --- Spotify synced lyrics (B4) --------------------------------------------
// The captain's now_playing_daemon.py already polls Spotify at 1 Hz, fetches
// the synced LRC from lrclib.net once per track and ticks the current line at
// 5 Hz. None of that is reimplemented here. Its ONE output adapter, sb(),
// gains an OMACOSY_LYRIC_OUT branch that writes an atomic JSON file instead of
// calling sketchybar; this fork launches it with that variable set and reads
// the file. Nothing here needs sketchybar to exist.
//
// The lyric lives in its own holder, never in `struct Media`: updateMedia()
// and primeMedia() both replace the whole Media value, so a field there would
// be wiped on every player event.

let lyricDaemonScript: String? = {
    guard let path = configuredValue("lyrics-daemon") else { return nil }
    guard FileManager.default.isReadableFile(atPath: path) else {
        tlog("lyrics: daemon not readable at \(path)")
        return nil
    }
    return path
}()

let lyricOutPath: String = configuredValue("lyrics-out") ?? "/tmp/omacosy-bar/lyric.json"

// --- media-source mpd ---------------------------------------------------------
// The daemon already polls mpd at 1 Hz for the lyric; its JSON carries the
// track too, so in mpd mode Media is derived from the same read instead of a
// second poller. Clicks go straight to mpd's socket: one connect, one command,
// no subprocess. The socket (not TCP) is what lets rmpc add files outside the
// music directory, so it is the address the whole stack shares.
let mpdSocketPath: String = configuredValue("mpd-socket")
    ?? NSHomeDirectory() + "/.local/share/mpd/socket"

func mediaFromDaemon(_ obj: [String: Any]) {
    let state = obj["state"] as? String ?? "hidden"
    let artist = obj["artist"] as? String ?? ""
    let name = obj["name"] as? String ?? ""
    var next = Media()
    next.running = state != "hidden" && !name.isEmpty
    if next.running {
        next.playing = state == "playing"
        next.title = artist.isEmpty ? name : "\(artist) — \(name)"
    }
    guard next != model.media else { return }
    model.media = next
    tlog("media(mpd) \(next.playing ? "play" : "pause") \(next.title)")
}

func mpdSend(_ command: String) {
    DispatchQueue.global(qos: .userInitiated).async {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let ok = mpdSocketPath.withCString { path -> Bool in
            guard strlen(path) < capacity else { return false }
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strcpy($0, path) }
            }
            return true
        }
        guard ok else { tlog("mpd: socket path too long \(mpdSocketPath)"); return }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard connected == 0 else { tlog("mpd: connect failed errno \(errno)"); return }
        var greeting = [UInt8](repeating: 0, count: 64)
        _ = read(fd, &greeting, greeting.count) // "OK MPD x.y.z\n"
        let line = command + "\n"
        _ = line.withCString { write(fd, $0, strlen($0)) }
        var reply = [UInt8](repeating: 0, count: 256)
        let n = read(fd, &reply, reply.count)
        let text = n > 0 ? String(decoding: reply[0..<n], as: UTF8.self) : ""
        if text.hasPrefix("ACK") { tlog("mpd: \(command) -> \(text.trimmingCharacters(in: .newlines))") }
    }
}

// The daemon writes only when its line CHANGES, so a fresh file is not a
// heartbeat — but a daemon that died mid-song must not leave its last line on
// the pill either. Ten seconds is longer than any gap between sung lines that
// still reads as "the current line".
let lyricStaleAfter: TimeInterval = 10

struct LyricHold {
    var track = "" // "<artist> - <name>", the daemon's own track identity
    var text = ""
    var state = "" // playing | paused | hidden
    var ts: Double = 0 // epoch seconds, stamped by the daemon
}

var lyricHold = LyricHold()
var lyricSeenTitle = "" // the Media.title in force when the hold was taken
var lyricFileStamp: Date = .distantPast
var lyricMismatchLogged = ""
var lyricDrawnLast = ""

// what the media pill actually put on screen, logged once per change — the
// holder alone cannot say whether the lyric won the title
func lyricDrawn(_ text: String, budget: CGFloat) {
    guard lyricDrawnLast != text else { return }
    lyricDrawnLast = text
    tlog(String(format: "lyric pill: %@ (budget %.1f pt)", text, budget))
}

// --- reader: a 1 s poll, not a file-descriptor watch ------------------------
// A DispatchSource on the file's descriptor sees the FIRST os.replace and then
// nothing: the rename hands the name to a new inode and the watch is still
// holding the old one. Polling mtime costs one stat per second and cannot miss
// a write.
func lyricPoll() {
    guard lyricDaemonScript != nil else { return }
    let url = URL(fileURLWithPath: lyricOutPath)
    guard let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate, stamp != lyricFileStamp else {
        dropLyricOnTrackChange()
        return
    }
    lyricFileStamp = stamp
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        tlog("lyrics: unreadable JSON at \(lyricOutPath)")
        return
    }
    var hold = LyricHold()
    hold.track = obj["track"] as? String ?? ""
    hold.text = obj["text"] as? String ?? ""
    hold.state = obj["state"] as? String ?? ""
    hold.ts = obj["ts"] as? Double ?? Date().timeIntervalSince1970
    let changed = hold.text != lyricHold.text || hold.state != lyricHold.state || hold.track != lyricHold.track
    lyricHold = hold
    if mediaSourceMPD { mediaFromDaemon(obj) }
    lyricSeenTitle = model.media.title
    // the daemon re-stamps an unchanged line every few seconds; only a change is worth a log line or a repaint
    guard changed else { return }
    tlog("lyrics: state=\(hold.state) track=\(hold.track) text=\(hold.text)")
    repaint()
}

// A lyric belongs to the track it was written for. Media.title changing is the
// earliest signal there is — earlier than the daemon's next write — so the
// hold is dropped here rather than waited out. currentLyric() re-checks the
// match anyway, so this is belt and braces, not the only guard.
func dropLyricOnTrackChange() {
    guard model.media.title != lyricSeenTitle else { return }
    let previous = lyricSeenTitle
    lyricSeenTitle = model.media.title
    // the first title of a launch is not a track CHANGE: primeMedia() lands
    // asynchronously, so the pill is briefly titleless while the daemon is
    // already ticking a perfectly good line for that same track
    guard !previous.isEmpty, !lyricHold.text.isEmpty else { return }
    tlog("lyrics: dropped, pill moved from \(previous) to \(model.media.title)")
    lyricHold = LyricHold()
    repaint()
}

// The daemon's identity is "<artist> - <name>"; upstream's Media.title is
// "<artist> — <name>". Both come from the same AppleScript, so only the name
// half is compared (an artist list is the half either side may format
// differently), case-insensitively.
func lyricNamePart(_ s: String, after separator: String) -> String {
    guard let r = s.range(of: separator) else {
        return s.trimmingCharacters(in: .whitespaces)
    }
    return String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
}

// When no synced line covers this instant the daemon falls back to
// "<name> — <artist>" — the title, in the other order. The pill has its own
// title, and upstream's clipping for it, so that is not a lyric.
func lyricLooksLikeTitle(_ text: String) -> Bool {
    let title = model.media.title
    guard let r = title.range(of: " — ") else {
        return text.caseInsensitiveCompare(title) == .orderedSame
    }
    let artist = String(title[title.startIndex..<r.lowerBound])
    let name = String(title[r.upperBound...])
    return text.caseInsensitiveCompare("\(name) — \(artist)") == .orderedSame
}

// nil = show the title, exactly as upstream does.
func currentLyric() -> String? {
    guard lyricDaemonScript != nil, model.media.playing, lyricHold.state == "playing" else { return nil }
    let text = lyricHold.text.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    guard Date().timeIntervalSince1970 - lyricHold.ts <= lyricStaleAfter else { return nil }
    let want = lyricNamePart(model.media.title, after: " — ").lowercased()
    let have = lyricNamePart(lyricHold.track, after: " - ").lowercased()
    guard !want.isEmpty, want == have else {
        let key = "\(want)|\(have)"
        if lyricMismatchLogged != key {
            lyricMismatchLogged = key
            tlog("lyrics: track mismatch pill=\(want) daemon=\(have)")
        }
        return nil
    }
    return lyricLooksLikeTitle(text) ? nil : text
}

// Real metrics, not upstream's character count: the lyric is measured against
// the room the left cluster actually has, in the font it will be drawn in.
func clipToWidth(_ text: String, _ font: NSFont, _ maxWidth: CGFloat) -> String {
    guard maxWidth > 0 else { return "" }
    guard advance(text, font) > maxWidth else { return text }
    var chars = Array(text)
    while !chars.isEmpty {
        chars.removeLast()
        let candidate = String(chars).trimmingCharacters(in: .whitespaces) + "\u{2026}"
        if advance(candidate, font) <= maxWidth { return candidate }
    }
    return ""
}

// --- launcher: the bar owns the daemon --------------------------------------
// sketchybarrc was the only thing that ever started this script. With
// sketchybar gone there is no launcher at all, so the bar is it.

var lyricDaemon: Process?
var lyricDaemonFailures = 0
var lyricDaemonStartedAt = Date.distantPast
var lyricDaemonStopping = false
var lyricSignalSources: [DispatchSourceSignal] = []

func lyricPythonBinary() -> String {
    ["/opt/homebrew/bin/python3", "/usr/bin/python3"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
}

// daemon_kill.sh's rule, not `pkill -f`: -f matches the whole command line, so
// any editor or agent that merely MENTIONS the path would be killed too. Only
// a process carrying this exact path as a whole argv field is ours.
func killStaleLyricDaemons(_ script: String) {
    let mine = getpid()
    for line in shell("/bin/ps", ["-Ao", "pid=,args="]).components(separatedBy: .newlines) {
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let pid = fields.first.flatMap({ Int32($0) }), pid != mine,
              fields.dropFirst().contains(script) else { continue }
        kill(pid, SIGTERM)
        tlog("lyrics: killed stale daemon pid \(pid)")
    }
}

func startLyricDaemon() {
    guard let script = lyricDaemonScript, lyricDaemon == nil, !lyricDaemonStopping else { return }
    let out = URL(fileURLWithPath: lyricOutPath)
    try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    killStaleLyricDaemons(script)
    var env = ProcessInfo.processInfo.environment
    env["OMACOSY_LYRIC_OUT"] = lyricOutPath
    // the daemon's own clip() guesses 6.6/11.0 px per character for a font it
    // cannot see; this bar measures with CoreText, so the guess is switched
    // off rather than applied twice
    env["LYRIC_LABEL_WIDTH"] = "100000"
    if mediaSourceMPD { env["MPD_SOCKET"] = mpdSocketPath }
    env["PATH"] = (env["PATH"].map { $0 + ":" } ?? "") + "/opt/homebrew/bin:/usr/bin:/bin"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: lyricPythonBinary())
    p.arguments = [script, "now_playing"]
    p.environment = env
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    p.terminationHandler = { proc in
        DispatchQueue.main.async {
            guard lyricDaemon === proc else { return } // a newer launch took over
            lyricDaemon = nil
            guard !lyricDaemonStopping else { return }
            // a daemon that dies within 10 s of launch is failing, not cycling
            lyricDaemonFailures = Date().timeIntervalSince(lyricDaemonStartedAt) < 10
                ? lyricDaemonFailures + 1 : 0
            guard lyricDaemonFailures < 5 else {
                tlog("lyrics: daemon failed 5 times in a row, giving up")
                return
            }
            tlog("lyrics: daemon exited (\(proc.terminationStatus)), relaunch in 5 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { startLyricDaemon() }
        }
    }
    guard (try? p.run()) != nil else {
        tlog("lyrics: could not launch \(script)")
        return
    }
    lyricDaemon = p
    lyricDaemonStartedAt = Date()
    tlog("lyrics: daemon \(script) pid \(p.processIdentifier) out=\(lyricOutPath)")
}

func stopLyricDaemon() {
    lyricDaemonStopping = true
    guard let p = lyricDaemon else { return }
    lyricDaemon = nil
    p.terminate()
    tlog("lyrics: daemon terminated")
}

// A child outlives its parent on macOS, so the bar hands the daemon a SIGTERM
// on every exit it can observe. SIGKILL (launchctl kickstart -k) it cannot —
// which is what killStaleLyricDaemons() at the next launch is for.
func installLyricLifecycle() {
    guard lyricDaemonScript != nil else { return } // no feature, no handlers
    atexit { stopLyricDaemon() }
    NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in stopLyricDaemon() }
    for sig in [SIGTERM, SIGINT] {
        signal(sig, SIG_IGN) // the DispatchSource, not the default action, handles it
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            stopLyricDaemon()
            exit(0)
        }
        source.resume()
        lyricSignalSources.append(source)
    }
}

// ===== omacosy extras (fork) end =====

// --- go -------------------------------------------------------------------

model.frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
// startup only: from here the fast paths keep it — the hook file under
// aerospace, the watch stream under omniwm
model.focused = managerFocused(omniwmActive())
rebuildSurfaces(monitorIDs())
guard !surfaces.isEmpty else {
    FileHandle.standardError.write("omacosy-bar: no display\n".data(using: .utf8)!)
    exit(1)
}
apply(fetchSnapshot()) // blocking is fine here: the run loop has not started
rightItems["activity"] = BarItem(icon: "󰍛", iconColor: \.accent)
applyShade() // restore the level this machine was left at
updateBattery()
updateBrightness()
updateWifi()
updateWeather()
updateFissionFund()
updateProxySpeed()
updateOpenMeteoWeather()
updateAIUsage()
updateAirPods()
startCaffeinate()
repaint()
primeMedia()
installLyricLifecycle() // before the launch, so no exit path can miss the child
startLyricDaemon()
reconcile("startup") // the OmniWM watch, and retries for a manager not up yet
resyncWallpaper() // a display plugged in while the machine was off missed the last theme change
tlog("omacosy-bar up on " + surfaces.map { "\($0.screen.localizedName)=m\($0.monitorID)\($0.notched ? " (notched)" : "")" }.joined(separator: ", "))
app.run()
