# test/

Runnable checks for omacosy's parsers and window-server behaviour.
They use worktree-local fixtures or isolated helper instances, never the
installed daemons.

## Night Shift schedule

    python3 test/run-nightshift-schedule.py

Renders the actual `install.sh` schedule block twice into a worktree-local HOME
with `launchctl` intercepted; verifies the daily 19:30 on / 09:00 off calendars
and uninstall wiring. Compiles the existing helper's Night Shift command with only the
CoreBrightness client lookup replaced by a fake, then executes the plist's
commands twice each from both off and on. No live display state or agents are touched.
Outputs stay under `build/test-nightshift-schedule/`.

The installed user LaunchAgents run the existing helper commands in local time:

- `com.omacosy.nightshift`: `~/.local/bin/omacosy-helper nightshift on` at **19:30**.
- `com.omacosy.nightshift-off`: `~/.local/bin/omacosy-helper nightshift off` at **09:00**.

Both use the same `CBBlueLightClient.setEnabled:` state as the bar's brightness
menu. Install/update recreates the agents; they load again at login without
executing immediately. macOS delivers calendar events missed during sleep on
wake (coalescing multiple missed events per agent). If sleep spans both actions,
their execution order is not guaranteed; no custom catch-up logic is added.
Time spent logged out or powered off is not replayed. Existing macOS Night Shift
schedules remain unchanged; the bar's manual on/off control remains available.

## rmpc theme

    python3 test/run-rmpc-theme.py

Renders `config/rmpc/theme.ron.tmpl` for every `themes/<name>/colors.toml` into a
temp file with `RMPC_THEME_NO_RELOAD=1`, so neither `~/.config/rmpc` nor a running
rmpc is touched. Checks that no template token survives, every hex colour in the
output comes from that palette, the accent drives the playing row, active tab,
progress bar and cava bars, the background stays `None`, re-rendering is byte-identical,
and an invalid palette is rejected without overwriting the previous output. Whether
rmpc parses the result is not covered here: launch `rmpc -c <config pointing at the file>`
for that.

## yazi theme

    python3 test/run-yazi-theme.py

Renders `config/yazi/flavor.toml.tmpl` and `config/yazi/tmtheme.xml.tmpl` for every
`themes/<name>/colors.toml` into a temp flavor dir with `YAZI_THEME_NO_RELOAD=1`, so
neither `~/.config/yazi` nor a running yazi is touched. Checks that no template token
survives, both files parse (TOML and plist), every hex colour comes from that palette,
the accent drives the hovered row, active tab and mode badge, re-rendering is
byte-identical, and an invalid palette is rejected without overwriting the previous
output. Whether yazi accepts every key is not covered here: run yazi on the rendered
flavor for that.

## Tern theme

    python3 test/run-tern-theme.py

Renders `config/tern/omp-theme.json.tmpl` for every `themes/<name>/colors.toml` into a
temp file with `TERN_THEME_NO_RELOAD=1`, so neither `~/.omp/agent/themes` nor a running
Tern is touched. Checks that the output is JSON, its `terminal` section resolves to the
palette's `background`, `foreground` and `color0`–`color15` in order, every colour role
resolves to a hex colour, re-rendering is byte-identical, and an invalid palette is
rejected without overwriting the previous output. Whether Tern repaints is not covered
here: run `tern-theme-fragment` and read a pane's colours with `tern capture <pane> --html`.

## AI usage

    python3 test/run-ai-usage.py

Extracts and compiles the actual parsers from `helper/bar.swift` with Swift/Foundation;
no network, external scripts, live caches or AppKit process. Outputs stay under `build/`.
Covers weekly-only Codex Pro, normal dual/primary-only windows, dynamic durations and
scoped titles, reset-credit availability and expiry, stale/malformed/missing caches, invalid
percentages, and Claude rows and pill derived from its cache. Sanitized codexbar 0.56.4 responses are in
`fixtures/ai-usage/`; reproduction and pill/popup images are in [`docs/ai-usage-pro`](../docs/ai-usage-pro/README.md).

## overview-selfactivation

    test/run-overview-selfactivation.sh

Regression test for the overview's self-activation defence: an app that
activates itself must not dismiss the overlay (the old
`didResignKey -> hideOverlay` policy did, and the digit the user pressed
next landed in the app underneath). Asserts the re-take, the 3-re-take
cap, and that Esc and a backdrop click still hide immediately.

Requirements:

* **Accessibility permission** for the terminal or app running the
  script — the test posts synthetic keys and clicks with `CGEventPost`,
  which silently does nothing without it. System Settings → Privacy &
  Security → Accessibility.
* **An idle keyboard and mouse.** The behaviour under test is decided by
  "seconds since the last deliberate CGEvent", so a keystroke of your
  own during the run is indistinguishable from the test's. The harness
  waits (up to 90 s) for 4 s of quiet before it starts, then runs
  unattended for ~30 s. Don't type through it.
* AeroSpace running, so the digit check has a focused workspace to
  target. It always types the digit of the workspace that is ALREADY
  focused, so the switch it triggers is a no-op.

Side effects while it runs: the overlay appears and disappears four
times on the screen under the cursor, and the cursor is moved to a
screen corner and put back for the backdrop-click check. The isolated
daemon and the throwaway "stealer" app are both terminated at the end.

## overview-inputfocus

    test/run-overview-inputfocus.sh

Regression test for the overlay's WINDOW-SERVER keyboard focus. AppKit's
"key window" is bookkeeping inside the process; physical keys arrive only
if the window server also agrees, and the only thing that arranges that
for a `.nonactivatingPanel` in an `.accessory` process is the private
`slpsFocus` grab in `showOverlay()`. That grab used to be made once,
blind. This test drives a refused grab on purpose — the one state
synthetic input cannot manufacture — with the test-only
`OMACOSY_OVERVIEW_TEST_FOCUS_GRAB` (`off` = no grab and no recovery,
`delay` = the first grab is refused and the verify path has to win it
back) and asserts:

* `off`   — the process really is not the front process, and keys and
            clicks reach the panel **anyway**. This is a pinned NEGATIVE
            result: it rules the front process and
            `NSView.acceptsFirstMouse` out as explanations for a real key
            going missing.
* `delay` — the daemon notices, logs the re-take, holds the front process
            again, and the key reaches the overlay
* normal  — the first grab still lands, no re-take is needed

Every synthetic event is posted to `.cghidEventTap`, the tap the physical
keyboard and trackpad feed, so window-server routing is identical to a
real key or click. Requirements and side effects are the same as
`overview-selfactivation` above, plus: it drives three isolated daemons
in sequence (~25 s) and types the digit of the workspace already visible
on the monitor under the cursor, so the switch is a no-op. Where that
workspace is not a bare 1-9 (an external monitor holding "11".."19") it
probes with `q` instead and only the `switchTo` assertion is skipped.

`OMACOSY_OVERVIEW_TEST_ID` and `OMACOSY_OVERVIEW_TEST_FOCUS_GRAB` (both
read in `helper/overview.swift`) exist only for these harnesses; nothing
in the shipped install sets either.
