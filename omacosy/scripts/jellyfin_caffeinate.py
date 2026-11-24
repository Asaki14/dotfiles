#!/usr/bin/env python3
"""Keep the Mac awake (pmset disablesleep) while Jellyfin is playing.

Reads Jellyfin's log for "started/stopped playback" events, so no API key is
needed. Run every 30 s from a LaunchAgent. Turns disablesleep on when a session
is active and off GRACE seconds after the last one ends, but only if this script
turned it on: a manual caffeinate pill is never overridden.
Needs the omacosy `sudo -n pmset -a disablesleep 0|1` sudoers rule.
"""
import glob
import os
import re
import subprocess
import sys
import time

LOG_DIR = os.path.expanduser("~/Library/Logs/jellyfin")
STATE = os.path.expanduser("~/.cache/jellyfin-caffeinate.state")
GRACE = 300

EVENT = re.compile(r'User ".*?" (started|stopped) playback of (.*) \((".*?" ".*?")\)$')


def active_sessions():
    logs = sorted(glob.glob(os.path.join(LOG_DIR, "log_*.log")))[-2:]
    sessions = set()
    for path in logs:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if "Sending shutdown notifications" in line:
                    sessions.clear()
                    continue
                if "SessionManager: User" not in line:
                    continue
                m = EVENT.search(line.rstrip())
                if not m:
                    continue
                key = (m.group(2).split(" at ")[0], m.group(3))
                (sessions.add if m.group(1) == "started" else sessions.discard)(key)
    return sessions


def sleep_disabled():
    out = subprocess.run(["pmset", "-g"], capture_output=True, text=True).stdout
    return bool(re.search(r"SleepDisabled\s+1", out))


def set_sleep_disabled(on):
    r = subprocess.run(
        ["sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "1" if on else "0"],
        capture_output=True, text=True,
    )
    if r.returncode:
        sys.exit(f"pmset failed: {r.stderr.strip()}")


def read_state():
    try:
        owned, last = open(STATE).read().split()
        return owned == "1", float(last)
    except (OSError, ValueError):
        return False, 0.0


def write_state(owned, last):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        f.write(f"{int(owned)} {last}")


def main():
    now = time.time()
    owned, last_active = read_state()
    disabled = sleep_disabled()
    if not disabled:
        owned = False
    if active_sessions():
        if not disabled:
            set_sleep_disabled(True)
            owned = True
        write_state(owned, now)
    elif owned and now - last_active > GRACE:
        set_sleep_disabled(False)
        write_state(False, now)
    else:
        write_state(owned, last_active)


if __name__ == "__main__":
    main()
