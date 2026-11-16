#!/usr/bin/env python3
"""Exercise the installed calendar command, with CoreBrightness mocked, never live."""
import os
from pathlib import Path
import plistlib
import subprocess

REPO = Path(__file__).resolve().parent.parent
BUILD = REPO / "build" / "test-nightshift-schedule"
LABEL = "com.omacosy.nightshift"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    home = BUILD / "home"
    agents = home / "Library/LaunchAgents"
    agents.mkdir(parents=True, exist_ok=True)
    helper = home / ".local/bin/omacosy-helper"
    helper.parent.mkdir(parents=True, exist_ok=True)
    install = (REPO / "install.sh").read_text()
    block = install.split("# --- nightshift schedule ---\n", 1)[1].split(
        "# --- end nightshift schedule ---", 1)[0]
    # Execute only this installation block. A shell function intercepts ALL
    # launchctl calls, so not even an unload can reach the running installation.
    calls = BUILD / "launchctl.calls"
    calls.write_text("")
    shell = 'set -eu\nlaunchctl() { printf "%s\\n" "$*" >> "$CALLS"; }\n' + block
    env = {**os.environ, "HOME": str(home), "CALLS": str(calls)}
    for _ in range(2):
        subprocess.run(["bash", "-c", shell], env=env, check=True)
    uninstall = (REPO / "uninstall.sh").read_text()
    plists = []
    expected_calls = []
    for label, mode, hour, minute in [(LABEL, "on", 19, 30), (LABEL + "-off", "off", 9, 0)]:
        plist_path = agents / f"{label}.plist"
        with plist_path.open("rb") as f:
            plist = plistlib.load(f)
        assert plist == {
            "Label": label,
            "ProgramArguments": [str(helper), "nightshift", mode],
            "StartCalendarInterval": {"Hour": hour, "Minute": minute},
        }, plist  # No startup, periodic, timezone or keepalive override.
        plists.append(plist)
        expected_calls.extend(f"{verb} {plist_path}" for verb in ("unload", "load"))
        assert f'launchctl unload "$HOME/Library/LaunchAgents/{label}.plist"' in uninstall
        assert f'rm -f "$HOME/Library/LaunchAgents/{label}.plist"' in uninstall
    assert calls.read_text().splitlines() == expected_calls * 2

    source = (REPO / "helper/main.swift").read_text()
    nightshift = source.split('case "nightshift":\n', 1)[1].split('\ncase "lock":', 1)[0]
    # Replace ONLY the framework/client lookup. The shipped CLI dispatch,
    # reflection, status layout, setter and status reader run unchanged.
    start = nightshift.index('    guard dlopen(')
    end = nightshift.index('    let client = cls.init()', start)
    nightshift = nightshift[:start] + '    let cls: NSObject.Type = FakeBlueLight.self\n' + nightshift[end:]
    harness = '''import AppKit

final class FakeBlueLight: NSObject {
    static var enabled = false
    static var writes: [Bool] = []
    @objc func setEnabled(_ on: Bool) -> Bool {
        Self.enabled = on
        Self.writes.append(on)
        return true
    }
    @objc func getBlueLightStatus(_ raw: UnsafeMutableRawPointer) -> Bool {
        // active deliberately stays true: only enabled is the menu's state.
        raw.storeBytes(of: ObjCBool(true), as: ObjCBool.self)
        raw.advanced(by: MemoryLayout<ObjCBool>.size)
            .storeBytes(of: ObjCBool(Self.enabled), as: ObjCBool.self)
        return true
    }
}
func fail(_ message: String) -> Never { fatalError(message) }
func scheduledCommand(_ args: [String]) {
    precondition(args.count == 3 && args[1] == "nightshift")
''' + nightshift + r'''
}
precondition(["on", "off"].contains(CommandLine.arguments[2]))
let expected = CommandLine.arguments[2] == "on"
for initiallyOn in [false, true] {
    FakeBlueLight.enabled = initiallyOn
    FakeBlueLight.writes = []
    for _ in 0..<2 {
        scheduledCommand(CommandLine.arguments)
        precondition(FakeBlueLight.enabled == expected, "scheduled command must set explicit state")
    }
    precondition(FakeBlueLight.writes == [expected, expected], "must set state, never toggle")
}
print("PASS: scheduled command sets \(CommandLine.arguments[2]) twice from both off and on")
'''
    main_file = BUILD / "main.swift"
    main_file.write_text(harness)
    subprocess.run(["swiftc", "-O", str(main_file), "-o", str(helper)], check=True)
    for plist in plists:
        subprocess.run(plist["ProgramArguments"], check=True)
    print("PASS: daily local 19:30 on / 09:00 off plists, repeat installation and uninstall wiring")


if __name__ == "__main__":
    main()
