// Regression test for the overview's self-activation defence
// (helper/overview.swift didResignKey observer).
//
// macOS lets an app activate itself, and the overlay used to hide on
// ANY loss of key — so the overlay vanished under the user and the
// digit they pressed next landed in whatever app had taken front. The
// fix re-takes key when no deliberate CGEvent (key/click/scroll) is
// less than 1.5s old, capped at 3 re-takes per showing.
//
// Four scenarios, each asserted from the daemon's own log delta:
//   steal — an app self-activates: overlay survives >=2s, a digit still
//           produces switchTo
//   cap   — four consecutive steals: the fourth hides, exactly 3 re-takes
//   esc   — Esc (a real keyDown, so input age is fresh) hides at once
//   click — a backdrop click hides at once
//
// Run it through test/run-overview-selfactivation.sh, never by hand:
// the runner builds the overview under test and passes OVERVIEW_BIN.
// The daemon it drives is fully isolated (OMACOSY_OVERVIEW_TEST_ID), so
// it never touches the installed daemon, its pidfile or its ffm flag.
//
// Needs Accessibility permission for the terminal running it (CGEvent
// posting) — see test/README.md.
import AppKit

let stealerMode = CommandLine.arguments.contains("--stealer")

// --- the stealer -------------------------------------------------------
// A throwaway regular app whose only job is to be activated. Using our
// own process instead of one of the user's apps keeps the test from
// perturbing a live desktop's focus/workspace state.
if stealerMode {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
        styleMask: [.titled], backing: .buffered, defer: false)
    w.title = "overview test stealer"
    w.orderFrontRegardless()
    // SIGUSR1 = "do what an Electron app does": activate YOURSELF. A
    // cooperative activate() from the harness is refused (the harness is
    // not frontmost and holds no activation right), and self-activation
    // is the mechanism the real bug rides in on anyway.
    signal(SIGUSR1, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    src.setEventHandler {
        app.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
    src.resume()
    print("STEALER READY \(getpid())")
    fflush(stdout)
    app.run()
    exit(0)
}

// --- harness -----------------------------------------------------------

func die(_ m: String) -> Never { FileHandle.standardError.write("FATAL: \(m)\n".data(using: .utf8)!); exit(2) }

guard let bin = ProcessInfo.processInfo.environment["OVERVIEW_BIN"], FileManager.default.isExecutableFile(atPath: bin)
else { die("set OVERVIEW_BIN to the overview binary under test (use run-overview-selfactivation.sh)") }
let selfPath = CommandLine.arguments[0]

let testID = "regress-\(getpid())"
let stateDir = NSString(string: "~/.local/state/omacosy").expandingTildeInPath
let pidPath = "\(stateDir)/overview-test-\(testID).pid"
let activeFlag = "/tmp/omacosy-overlay-active-\(getuid())-test-\(testID)"
let logPath = "/tmp/omacosy-overview-test-\(testID).log"

var failures: [String] = []
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "  ok  " : "  FAIL") \(what)")
    if !ok { failures.append(what) }
}
func sleepFor(_ s: Double) { usleep(UInt32(s * 1_000_000)) }

func logText() -> String { (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "" }
var mark = 0
func markLog() { mark = logText().count }
func delta() -> String { let t = logText(); return t.count > mark ? String(t.dropFirst(mark)) : "" }

// --- isolated daemon ---------------------------------------------------
var env = ProcessInfo.processInfo.environment
env["OMACOSY_OVERVIEW_TEST_ID"] = testID
let daemon = Process()
daemon.executableURL = URL(fileURLWithPath: bin)
daemon.arguments = ["--daemon"]
daemon.environment = env
do { try daemon.run() } catch { die("cannot launch \(bin): \(error)") }
let dpid = daemon.processIdentifier
print("isolated daemon pid=\(dpid) log=\(logPath)")

// the stealer, started as a child of this test
let stealer = Process()
stealer.executableURL = URL(fileURLWithPath: selfPath)
stealer.arguments = ["--stealer"]
let spipe = Pipe()
stealer.standardOutput = spipe
do { try stealer.run() } catch { die("cannot launch the stealer: \(error)") }
let stealerPid = stealer.processIdentifier

func cleanup() {
    kill(dpid, SIGTERM)
    kill(stealerPid, SIGTERM)
    sleepFor(0.4)
    try? FileManager.default.removeItem(atPath: activeFlag)
    try? FileManager.default.removeItem(atPath: pidPath)
}

// the daemon writes its pidfile before it is ready to be signalled
var waited = 0.0
while !FileManager.default.fileExists(atPath: pidPath), waited < 10 { sleepFor(0.1); waited += 0.1 }
guard FileManager.default.fileExists(atPath: pidPath) else { cleanup(); die("daemon never wrote \(pidPath)") }
sleepFor(1.0)
guard NSRunningApplication(processIdentifier: stealerPid) != nil else { cleanup(); die("the stealer did not register as an app") }

// A real user's keys and clicks would be read as "the user did this" by
// the very test under test, so wait for a quiet keyboard first.
func inputAge() -> Double {
    let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
    return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
}
waited = 0
while inputAge() < 4.0, waited < 90 { sleepFor(0.5); waited += 0.5 }
guard inputAge() >= 4.0 else { cleanup(); die("the keyboard/mouse never went quiet — rerun when the desktop is idle") }

let src = CGEventSource(stateID: .hidSystemState)
func postKey(_ code: CGKeyCode) {
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    sleepFor(0.03)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
}

func show() { kill(dpid, SIGUSR1); sleepFor(1.6) }
func hideIfUp() {
    if FileManager.default.fileExists(atPath: activeFlag) { kill(dpid, SIGUSR2); sleepFor(0.8) }
}
func visible() -> Bool { FileManager.default.fileExists(atPath: activeFlag) }
func steal() { kill(stealerPid, SIGUSR1); sleepFor(1.2) }

// --- 1. an app self-activates ------------------------------------------
print("\n[steal] a background app activates itself with no user input")
show()
guard visible() else { cleanup(); die("the overlay never came up — is SIGUSR1 reaching pid \(dpid)?") }
markLog()
steal()
sleepFor(1.4) // >=2s total since the steal
check(visible(), "overlay still visible >=2s after the self-activation")
check(delta().contains("re-taking key"), "the daemon logged a key re-take")
check(!delta().contains("hideOverlay"), "the daemon did not hide")

// a digit must still switch. Target the ALREADY focused workspace so
// the switch is a no-op on a live desktop.
func focusedWorkspace() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "$(command -v aerospace || echo /opt/homebrew/bin/aerospace) list-workspaces --focused"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    try? p.run()
    let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (String(data: d, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}
let digitKeys: [String: CGKeyCode] = ["1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25]
let ws = focusedWorkspace()
markLog()
if let code = digitKeys[ws] {
    postKey(code)
    sleepFor(0.8)
    check(delta().contains("keyDown code=\(code)"), "the digit reached the overlay after the re-take")
    check(delta().contains("switchTo \(ws)"), "the digit produced switchTo \(ws)")
} else {
    print("  skip  focused workspace '\(ws)' is not a 1-9 digit; not typing one")
}
hideIfUp()

// --- 2. the re-take cap ------------------------------------------------
print("\n[cap] four consecutive steals — the fourth must hide")
show()
guard visible() else { cleanup(); die("the overlay never came up for the cap scenario") }
markLog()
for i in 1...4 {
    steal()
    print("  after steal \(i): visible=\(visible())")
    if i < 4 { check(visible(), "overlay survived steal \(i)") }
}
sleepFor(0.8)
check(!visible(), "overlay hid on the 4th steal")
let retakes = delta().components(separatedBy: "re-taking key").count - 1
check(retakes == 3, "exactly 3 re-takes were logged (saw \(retakes))")
hideIfUp()

// --- 3. Esc still hides at once ----------------------------------------
print("\n[esc] Esc is a real keyDown, so input age is fresh — hide immediately")
show()
guard visible() else { cleanup(); die("the overlay never came up for the esc scenario") }
markLog()
postKey(53)
sleepFor(0.9)
check(!visible(), "Esc hid the overlay")
check(!delta().contains("re-taking key"), "Esc did not trigger a re-take")
hideIfUp()

// --- 4. a backdrop click still hides at once ---------------------------
print("\n[click] a backdrop click hides immediately")
let restore = NSEvent.mouseLocation
show()
if !visible() {
    print("  skip  the overlay never came up for the click scenario")
} else {
    markLog()
    // the daemon logs its slot and chip centres; pick the screen corner
    // furthest from all of them so the click is guaranteed backdrop
    let laid = logText().components(separatedBy: "laid out cards").last ?? ""
    var centres: [CGPoint] = []
    for m in laid.components(separatedBy: CharacterSet(charactersIn: " []@")) {
        let parts = m.components(separatedBy: ",")
        if parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) {
            centres.append(CGPoint(x: x, y: y))
        }
    }
    let screen = NSScreen.screens.first { $0.frame.contains(restore) } ?? NSScreen.main!
    let inset: CGFloat = 12
    let corners = [CGPoint(x: inset, y: screen.frame.height - inset),
                   CGPoint(x: screen.frame.width - inset, y: screen.frame.height - inset),
                   CGPoint(x: inset, y: inset),
                   CGPoint(x: screen.frame.width - inset, y: inset)]
    let best = corners.max { a, b in
        let da = centres.map { hypot($0.x - a.x, $0.y - a.y) }.min() ?? .infinity
        let db = centres.map { hypot($0.x - b.x, $0.y - b.y) }.min() ?? .infinity
        return da < db
    }!
    // content point -> global NS -> CG (y flips about the main screen's top)
    let gx = screen.frame.minX + best.x
    let gy = screen.frame.minY + best.y
    let p = CGPoint(x: gx, y: NSMaxY(NSScreen.screens[0].frame) - gy)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    sleepFor(0.15)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    sleepFor(0.06)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    sleepFor(0.9)
    check(delta().contains("backdrop -> hide"), "the click landed on the backdrop")
    check(!visible(), "the backdrop click hid the overlay")
    check(!delta().contains("re-taking key"), "the backdrop click did not trigger a re-take")
    CGWarpMouseCursorPosition(CGPoint(x: restore.x, y: NSMaxY(NSScreen.screens[0].frame) - restore.y))
    CGAssociateMouseAndMouseCursorPosition(1)
}
hideIfUp()

cleanup()
print("\n\(failures.isEmpty ? "PASS" : "FAIL (\(failures.count)): \(failures.joined(separator: " | "))")")
print("full daemon log: \(logPath)")
exit(failures.isEmpty ? 0 : 1)
