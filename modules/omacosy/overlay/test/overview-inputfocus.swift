// Regression test for the overview's WINDOW-SERVER keyboard focus
// (helper/overview.swift verifyKeyboardFocus + ContentView.acceptsFirstMouse).
//
// The overlay is a .nonactivatingPanel in an .accessory process. AppKit
// makes the panel key INSIDE the process, and the private slpsFocus grab
// in showOverlay() is what also makes the process the window server's
// front process. That grab used to be made once, blind, with no check.
//
// Two things are pinned here:
//   * the guard — a refused grab is now noticed and re-asserted, so the
//     process cannot sit behind a fully drawn overlay having quietly lost
//     the front process
//   * the negative result — with NO grab at all, keys and clicks still
//     reach the panel. Measured 2026-08-31 against the 09:29 failure
//     report (a recorder saw two physical digits and a card click that the
//     daemon logged neither of): whatever swallowed those, it was not the
//     front process and not NSView.acceptsFirstMouse.
//
// A refused grab is the one state synthetic input cannot manufacture, so
// the daemon under test is asked for it directly with the test-only
// OMACOSY_OVERVIEW_TEST_FOCUS_GRAB:
//   off    = the daemon that shipped before the fix (no grab, no verify)
//   delay  = the grab is refused once; the verify path has to win it back
//   unset  = the normal path
//
// Every synthetic event is posted to .cghidEventTap, the tap the physical
// keyboard and trackpad feed, so window-server routing is identical to a
// real key or click. Round 1's false pass came from trusting synthetic
// input that never had to survive that routing.
//
// Run it through test/run-overview-inputfocus.sh, never by hand: the
// runner builds the overview under test and passes OVERVIEW_BIN. Every
// daemon it drives is isolated (OMACOSY_OVERVIEW_TEST_ID), so it never
// touches the installed daemon, its pidfile or its ffm flag.
//
// Needs Accessibility permission for the terminal running it (CGEvent
// posting) — see test/README.md.
import AppKit

// --- window-server front process (same primitive helper/overview.swift uses)
struct PSN: Equatable { var hi: UInt32 = 0, lo: UInt32 = 0 }
@_silgen_name("GetProcessForPID") func GetProcessForPID(_ p: pid_t, _ psn: inout PSN) -> OSStatus
@_silgen_name("_SLPSGetFrontProcess") func SLPSGetFrontProcess(_ psn: inout PSN) -> OSStatus
func psnOf(_ p: pid_t) -> PSN { var x = PSN(); return GetProcessForPID(p, &x) == noErr ? x : PSN() }
func frontIs(_ pid: pid_t) -> Bool {
    var f = PSN()
    guard SLPSGetFrontProcess(&f) == noErr else { return false }
    return f == psnOf(pid)
}

func die(_ m: String) -> Never {
    FileHandle.standardError.write("FATAL: \(m)\n".data(using: .utf8)!); exit(2)
}
let bin = ProcessInfo.processInfo.environment["OVERVIEW_BIN"] ?? ""
if !FileManager.default.isExecutableFile(atPath: bin) {
    die("set OVERVIEW_BIN to the overview binary under test (use run-overview-inputfocus.sh)")
}

func sleepFor(_ s: Double) { usleep(UInt32(s * 1_000_000)) }
var failures: [String] = []
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "  ok  " : "  FAIL") \(what)")
    if !ok { failures.append(what) }
}
func oneLine(_ s: String) -> String { s.split(separator: "\n").joined(separator: " | ") }
func inputAge() -> Double {
    let t: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
    return t.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
}
let src = CGEventSource(stateID: .hidSystemState)
func postKey(_ code: CGKeyCode) {
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    sleepFor(0.03)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
}
func clickAt(_ p: CGPoint) {
    // WARP, then click without a motion event: the isolated daemon's
    // overlay flag is test-scoped, so the live omacosy-ffm never stands
    // down for it and a real mouseMoved would let hover-focus confound
    // the measurement.
    CGWarpMouseCursorPosition(p)
    CGAssociateMouseAndMouseCursorPosition(1)
    sleepFor(0.2)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    sleepFor(0.07)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
// the workspace the overlay will show as focused: the visible one on the
// monitor under the cursor, which is the screen the overlay opens on
func focusedWorkspace() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "$(command -v aerospace || echo /opt/homebrew/bin/aerospace) list-workspaces --monitor mouse --visible"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    try? p.run()
    let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (String(data: d, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}
let digitKeys: [String: CGKeyCode] = ["1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25]

// --- one isolated daemon per scenario ----------------------------------
final class Daemon {
    static let bin = ProcessInfo.processInfo.environment["OVERVIEW_BIN"] ?? ""
    let pid: pid_t
    let flag: String
    let logPath: String
    let pidPath: String
    private let proc = Process()
    private var mark = 0
    init(grab: String?, id: String) {
        let stateDir = NSString(string: "~/.local/state/omacosy").expandingTildeInPath
        pidPath = "\(stateDir)/overview-test-\(id).pid"
        flag = "/tmp/omacosy-overlay-active-\(getuid())-test-\(id)"
        logPath = "/tmp/omacosy-overview-test-\(id).log"
        var env = ProcessInfo.processInfo.environment
        env["OMACOSY_OVERVIEW_TEST_ID"] = id
        if let g = grab { env["OMACOSY_OVERVIEW_TEST_FOCUS_GRAB"] = g }
        else { env.removeValue(forKey: "OMACOSY_OVERVIEW_TEST_FOCUS_GRAB") }
        proc.executableURL = URL(fileURLWithPath: Daemon.bin)
        proc.arguments = ["--daemon"]
        proc.environment = env
        do { try proc.run() } catch { die("cannot launch \(Daemon.bin): \(error)") }
        pid = proc.processIdentifier
        var w = 0.0
        while !FileManager.default.fileExists(atPath: pidPath), w < 10 { sleepFor(0.1); w += 0.1 }
        guard FileManager.default.fileExists(atPath: pidPath) else { kill(pid, SIGTERM); die("daemon never wrote \(pidPath)") }
        sleepFor(0.9)
    }
    func text() -> String { (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "" }
    func markLog() { mark = text().count }
    func delta() -> String { let t = text(); return t.count > mark ? String(t.dropFirst(mark)) : "" }
    var visible: Bool { FileManager.default.fileExists(atPath: flag) }
    func show() { kill(pid, SIGUSR1) }
    func hideIfUp() { if visible { kill(pid, SIGUSR2); sleepFor(0.8) } }
    // the daemon prints its own slot centres; card 1 is the first pair
    func firstCardCG() -> CGPoint? {
        let laid = text().components(separatedBy: "laid out cards").last ?? ""
        let head = laid.components(separatedBy: "chips").first ?? laid
        for m in head.components(separatedBy: CharacterSet(charactersIn: " []\"@")) {
            let p = m.components(separatedBy: ",")
            if p.count == 2, let x = Double(p[0]), let y = Double(p[1]) {
                return CGPoint(x: x, y: NSMaxY(NSScreen.screens[0].frame) - y)
            }
        }
        return nil
    }
    func stop() {
        kill(pid, SIGTERM)
        sleepFor(0.4)
        try? FileManager.default.removeItem(atPath: flag)
        try? FileManager.default.removeItem(atPath: pidPath)
    }
}

var waited = 0.0
while inputAge() < 4.0, waited < 90 { sleepFor(0.5); waited += 0.5 }
guard inputAge() >= 4.0 else { die("the keyboard/mouse never went quiet — rerun when the desktop is idle") }
let home = CGEvent(source: nil)?.location ?? .zero
let ws = focusedWorkspace()
// A digit that switches to the workspace already visible here makes the
// switch a no-op on a live desktop. Where that workspace is not a bare
// 1-9 (an external monitor holds "11".."19"), fall back to a key that is
// no workspace at all: it still proves DELIVERY, which is what the bug
// was about, and only the switchTo assertion is skipped.
let digit = digitKeys[ws]
let probeKey: CGKeyCode = digit ?? 12   // 12 = 'q', lands in the search filter
print("visible workspace on the monitor under the cursor: '\(ws)'"
    + (digit != nil ? " — typing its digit (switch is a no-op)" : " — not a bare digit, probing with 'q'"))

// --- 1. what a lost grab does NOT break --------------------------------
// Measured 2026-08-31 and pinned here because it kills a whole family of
// theories: with no grab and no verify the process is genuinely not the
// front process, and physical-equivalent keys and clicks STILL reach the
// panel. A .nonactivatingPanel that AppKit has made key wins keyboard
// input on its own, and it is exempt from the activation-click rule, so
// neither the front process nor NSView.acceptsFirstMouse can be the
// reason a real key goes missing.
print("\n[no-grab] the process is not the front process — input must still arrive")
let a = Daemon(grab: "off", id: "if-off-\(getpid())")
a.show(); sleepFor(1.6)
check(a.visible, "overlay is up")
check(!frontIs(a.pid), "the process is NOT the window-server front process")
a.markLog()
postKey(probeKey)
sleepFor(0.9)
let da = a.delta()
check(da.contains("keyDown code="),
    "the key reaches the overlay anyway (log: \(oneLine(da)))")
if let card = a.firstCardCG() {
    // the key above switched and dismissed: let the workspace change settle
    // (a fresh focus change right after it re-hides the overlay) and re-show
    sleepFor(1.5); a.show(); sleepFor(1.8)
    a.markLog()
    clickAt(card)
    sleepFor(1.0)
    let ca = a.delta()
    if ca.isEmpty && !a.visible {
        print("  skip  the overlay did not stay up for the click check")
    } else {
        check(ca.contains("mouseDown at"), "a card click reaches ContentView.mouseDown anyway (log: \(oneLine(ca)))")
        check(ca.contains("press card"), "the click is read as a card press")
    }
} else {
    print("  skip  the daemon laid out no cards; no click check")
}
a.hideIfUp(); a.stop()

// --- 2. THE FIX: a refused grab is detected and won back ---------------
print("\n[recover] the first grab is refused — verifyKeyboardFocus must win it back")
let b = Daemon(grab: "delay", id: "if-delay-\(getpid())")
b.markLog()
b.show(); sleepFor(2.0)
check(b.visible, "overlay is up")
let logb = b.delta()
check(logb.contains("keyboard focus is with"), "the daemon noticed it did not hold keyboard focus")
check(frontIs(b.pid), "the daemon holds the window-server front process again")
b.markLog()
postKey(probeKey)
sleepFor(0.9)
let db = b.delta()
check(db.contains("keyDown code=\(probeKey)"), "the key reached the overlay (log: \(oneLine(db)))")
if digit != nil { check(db.contains("switchTo \(ws)"), "the digit produced switchTo \(ws)") }
b.hideIfUp(); b.stop()

// --- 3. the normal path is unchanged -----------------------------------
print("\n[normal] the shipped path still grabs focus on the first try")
let c = Daemon(grab: nil, id: "if-on-\(getpid())")
c.markLog()
c.show(); sleepFor(1.6)
check(c.visible, "overlay is up")
check(frontIs(c.pid), "the daemon is the window-server front process")
check(!c.delta().contains("keyboard focus is with"), "no re-take was needed")
c.markLog()
postKey(probeKey)
sleepFor(0.9)
let dc = c.delta()
check(dc.contains("keyDown code=\(probeKey)"), "the key reached the overlay (log: \(oneLine(dc)))")
if let card = c.firstCardCG() {
    sleepFor(1.5); c.show(); sleepFor(1.8)
    if c.visible {
        c.markLog()
        clickAt(card)
        sleepFor(1.0)
        check(c.delta().contains("press card"), "a card click is read as a card press")
    } else {
        print("  skip  the overlay did not stay up for the click check")
    }
}
c.hideIfUp(); c.stop()

CGWarpMouseCursorPosition(home)
CGAssociateMouseAndMouseCursorPosition(1)
print("\n\(failures.isEmpty ? "PASS" : "FAIL (\(failures.count)): \(failures.joined(separator: " | "))")")
exit(failures.isEmpty ? 0 : 1)
