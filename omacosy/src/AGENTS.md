# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- This tree is `paulsp94/omacosy` vendored into the dotfiles repo at `omacosy/src`, with local
  customisations committed in place; `~/.local/share/omacosy` is a symlink to it. `UPSTREAM`
  records the upstream commit it is based on. To take upstream changes, diff upstream from that
  commit to the new one and apply the patch here:
  `git -C <upstream clone> diff <UPSTREAM> <new> | git apply -3 --directory=omacosy/src`, run from
  the dotfiles root, then update `UPSTREAM`. Conflicts resolve to the UNION — upstream's new
  feature and the local customisation both stay, rewritten so both hold. The recurring conflict
  files are `README.md`, `config/aerospace/aerospace.template.toml` and `helper/bar.swift`.
  `config/omniwm/settings.toml` is state OmniWM rewrites (`[borders.color]` on every theme
  switch, gaps from the bar's layouts), so it shows up dirty as a matter of course; restore it
  rather than committing this machine's live values.

- `helper/bar.swift` is compiled as a **single main file** (`install.sh:581-583`); a second
  source file is not possible, so fork additions live in the fenced
  `omacosy extras (fork)` block just above `// --- go ---`.
- To validate a bar change without touching the running bar, build with the exact `swiftc`
  line from `install.sh:581-583` into a path inside your worktree, then run the binary with
  `OMACOSY_BAR_STACK=1` (it draws one bar-height below the live bar). Both binaries append to
  the shared `/tmp/omacosy-bar.log`, so record the file size before the run and read only the
  tail delta.
- This checkout is also the live installation. For an authorized deployment, rebuild only affected
  components rather than rerunning the whole installer. Follow `install.sh` for compile flags,
  app metadata, signing, and service handling. Its signing probe determines whether an Apple
  Development identity works; do not assume an old machine's ad-hoc signing state still applies.
  A changed signing identity can invalidate macOS permission grants.
- Right-cluster items are configured by `~/.config/omacosy/bar-items.conf`
  (`hide` / `order` / `group` directives; loader in the extras block). `media-controls off`
  is parsed by the same loader and returned in its tuple; it drops the media pill's transport
  glyphs, and absent means on.
  `OMACOSY_BAR_ITEMS_CONF` overrides that path and exists only for isolated validation —
  never write to `~/.config` from a task worktree.
- Value directives in `bar-items.conf` are read by `configuredValue(_:)`, separately from the
  `hide`/`order`/`group` parser; a new one must also get a no-op `case` in that parser's switch
  or it logs as an unknown directive. `fission-estimator <path>` is the first of them —
  absent means the pill never appears and Node never runs. Every value goes through a leading-`~`
  expansion in `configuredValue(_:)`, so path directives should be written `~/...` and the one
  `bar-items.conf` stays shareable across machines; absolute paths keep working unchanged.
- Ghostty follows the theme through a generated include, not `theme =`:
  `bin/ghostty-theme-fragment` writes `~/.local/state/omacosy/ghostty-theme.conf` and
  `pkill -USR2 -x ghostty` (one process per window, so the reload must be broadcast).
  A `config-file` include outranks every top-level key, which is why it beats a personal
  `theme = ...`. Use `GHOSTTY_THEME_NO_RELOAD=1` plus an explicit `$2` output path to test
  without touching the live windows or the real state dir.
- rmpc follows the theme the same way (`bin/rmpc-theme-fragment`, template
  `config/rmpc/theme.ron.tmpl`, output `~/.config/rmpc/themes/omacosy.ron`), but the reload
  is `rmpc remote set theme <file>`, not a signal: rmpc's config watcher only reacts to
  close-write events, which macOS never emits, so neither the theme nor `config.ron` hot-reload
  here — config.ron changes need an rmpc restart. The template is plain `sed`, tokens are
  `@name@`; a literal `@word@` anywhere else in the template trips the unrendered-token guard.
  Test with `RMPC_THEME_NO_RELOAD=1` plus an explicit `$2` path (`test/run-rmpc-theme.py`).
- yazi follows the theme with the same `sed` template scheme (`bin/yazi-theme-fragment`,
  templates `config/yazi/flavor.toml.tmpl` and `config/yazi/tmtheme.xml.tmpl`, output the
  flavor dir `~/.config/yazi/flavors/omacosy.yazi/`). Yazi reads its theme only at startup;
  the reload is `ya emit-to 0 app:theme` (receiver 0 broadcasts to every instance; the action
  exists since yazi 26.x). The flavor sections and keys mirror yazi's preset
  `theme-dark.toml` — a key yazi renames upstream silently stops applying, so re-diff against
  the preset on yazi upgrades. Test with `YAZI_THEME_NO_RELOAD=1` plus an explicit `$2` dir
  (`test/run-yazi-theme.py`).

- Weather in the clock popup comes from the sketchybar Open-Meteo script, not from omacosy's
  wttr.in path: `weather-script <path to weather_popup.sh>` (absent = upstream `weatherRows()`
  unchanged) plus optional `weather-lib <dir with weather_lib.py>`. That script's `rows` mode only
  renders `/tmp/sketchybar_daemon/weather.json` and fetches solely when the cache is ABSENT, so
  Swift owns the 1800 s refresh (`updateOpenMeteoWeather()`) and replaces the cache before
  rendering. Validate with a STALE cache (`touch -t`), not just a missing one.

- Spotify lyrics come from the dotfiles' `now_playing_daemon.py`, which the bar LAUNCHES
  itself (sketchybarrc was its only launcher): `lyrics-daemon <path>` in `bar-items.conf`
  (absent = feature off, nothing spawned) plus optional `lyrics-out <path>`. The daemon needs a
  patched `sb()` that writes `{state,icon,text,track,ts}` atomically when `OMACOSY_LYRIC_OUT` is
  set — that patch lives in the dotfiles repo, not here (the diff rides in this feature's PR body).
  The lyric is held OUTSIDE `struct Media` (`lyricHold`), because `updateMedia()`/`primeMedia()`
  replace the whole `Media` value and would wipe a field there; `clippedTitle` is the only
  rendering seam. Read the file with the 1 s poll, never a file-descriptor watch: the daemon's
  `os.replace` leaves such a watch holding a dead inode after the first write.

- `media-source mpd` in `bar-items.conf` switches the media pill off Spotify: Media is derived
  from the same lyrics-daemon JSON (`artist`/`name`/`state` fields, read in `lyricPoll()` →
  `mediaFromDaemon()`), the Spotify notification/AppleScript paths are gated off by
  `mediaSourceMPD`, and pill clicks write straight to mpd's unix socket (`mpdSend()`,
  `mpd-socket <path>`, default `~/.local/share/mpd/socket`). The daemon itself now reads mpd and
  the `.lrc` beside each song; absent directive = upstream Spotify behaviour unchanged.

- **Every new bar item takes its colours from the theme-derived `palette` roles only**
  (`struct Palette`, `helper/bar.swift:299`: `itemBG accent label muted barBG red green yellow`) —
  never a hex literal or an `NSColor.system*`, so the item follows `theme-set` under all five
  themes. External scripts that name colours are mapped onto roles
  (`GOLD`→yellow, `LOVE`→red, `MUTED`→muted, `FOAM`→accent, `TEXT`/unknown→label; see `aiColor`).
  Use the standard pill geometry and fonts (`chipFont`, `iconFont`, `pillHeight`, `radius`).
- `ai-usage-script <path>` in `bar-items.conf` enables the AI pill; the script's own
  `title`/`c.*`/`head2`/`x.*` slots are ignored. Claude and Codex rows both come from the
  actual JSON windows in `helper/bar.swift` (`aiWindows`, `aiClaudeRows`/`aiCodexRows`), and
  the pill shows each provider's glyph with its 5h window only (7d stays in the popup).
  The bar runs the configured `codexbar` command every 300 s and writes
  `/tmp/sketchybar_daemon/{claude,codex}_raw.json`. The live dotfiles configure
  `~/.config/omacosy/scripts/omp_usage.py`, a read-only OMP usage-cache adapter, not CodexBar.
  Pro can have `primary: null` and weekly `secondary` only; percentages remain USED, and
  a provider without a 5h window shows `—` in the pill. The detail popup also shows
  available `codex_rate_limits` reset credits and their nearest expiry.
  Regression: `python3 test/run-ai-usage.py`.
  `OMACOSY_AI_CACHE_DIR` isolates bar caches in tests; pair it with a fixture `ai-usage-script`
  because the external script has its own cache path. `codexbar <path>` overrides the
  executable implementing the usage JSON contract; the directive name does not require CodexBar.
  `workspaces-max <n>` caps the left chips, retaining occupied/focused/visible slots beyond n.
- `airpods-name <device name>` registers the AirPods pill (absent = no item, no poll), but it is
  now only the PREFERRED device: `airpodsParse` falls back to any `device_connected`
  Headphones/Headset that reports a level, and a single-cell device renders `NN%` instead of
  `L/R`. Data is `system_profiler -json SPBluetoothDataType` every 180 s off main, skipped while
  `BTGetPower()` is 0. That published view OMITS battery for W1-era devices (Beats Solo3), so
  when it yields nothing `airpodsIOBluetooth` reads IOBluetoothDevice's undocumented but
  ObjC-visible `batteryPercent{Single,Left,Right,Case}` by KVC — every read `responds(to:)`-guarded
  because valueForUndefinedKey raises an ObjC exception Swift cannot catch, and 0 means "not
  reported". Both parsers are pure-ish — exercise `airpodsParse` against a saved dump with the ears
  moved into `device_connected`.

- `caffeinate on` registers the sleep toggle pill (absent = no item, no timer, pmset untouched).
  It flips `pmset -a disablesleep` through `sudo -n` (rule from `bin/omacosy-sleep-sudoers`), so
  lid-close sleep is blocked too; the state is the SYSTEM's `SleepDisabled`, re-read from
  `pmset -g` on every render and a 30 s timer — the bar keeps no pid or state file. Reads and the
  write run on `caffeinateQueue`; `caffeinateBusy` on main stops two fast clicks from both
  flipping. Drive it in validation with `OMACOSY_CAFFEINATE_TEST=toggle,toggle`. Every bar start
  (pill on or off) runs `reapLegacyCaffeinate()`: it SIGTERMs this user's orphaned (ppid 1)
  `caffeinate -dims[ -w N]` left by the old child-spawning pill and deletes its /tmp pid files.

- Popup rows are one renderer (`struct PopupRow` + `PopupView`): `scale` (.large/.normal/.small)
  drives BOTH the text and glyph font plus the row height, `rule` is a hairline section break
  (`dividerRow()`/`joined()`), `cells` renders a fixed-column calendar week, `detail` is the
  right-aligned dim column (menu shortcuts), `image` a 16 pt leading app icon, and
  `navBack`/`navForward` is the only row that splits into two hit zones (by geometry, like
  `slider`). A row must never bake a palette colour in on a background queue — `.small` dims its
  own glyph at draw time so a `theme-set` repaints it. `rule` is the ONE name for a hairline:
  upstream's `separator` field was folded into it at the 2026-09-08 merge, so an upstream port
  that reads `row.separator` has to be rewritten.
- `PopupView` is the DOCUMENT view of an `NSScrollView` that `showPopup()` owns, and the
  scroll layer — not the view — carries the rounded clip and the accent border. So `draw()`
  fills `bounds` plainly, and `refreshPopup()` is exact-fit with the TOP edge pinned
  (`popupTopY`/`popupAnchorX`/`popupAlignLeft`), not grow-only. `rowRects` is keyed by the ROW,
  never an index — two columns make an index ambiguous — which is also why hover is tracked as
  `hoveredRect` rather than upstream's `hoveredRow`.
- The open popup remembers its display as `openPopupDisplay` (a `CGDirectDisplayID`, not a
  `BarSurface` — surfaces are rebuilt on screen changes): `updateBarVisibility()` hides every
  covered surface unconditionally but closes the popup only for its OWN display, so a fullscreen
  window on one screen no longer kills a popup on another.
- `calendarMonthStep` is popup-scoped state: `showPopup()` clears it, so the calendar always
  opens on the current month; the grid is always six weeks so stepping never resizes the window.
- The apple pill drops the front app's REAL Apple menu over Accessibility (`appleMenuRows()` →
  `rowsForMenu`), falling back to the hand-rolled `appleRows()` only when AX is unavailable. The
  fork's own entries (btop, Next Theme) therefore have to be appended in BOTH — put one in
  `appleRows()` alone and it disappears the moment Accessibility is granted.
- Workspace chip icons read their OWN `~/.config/omacosy/workspace-icons.conf`
  (`loadWorkspaceIconConfig`, `key = <glyph|bundle id>`), not `bar-items.conf` — a new directive
  there needs no `case` in the `hide`/`order`/`group` parser.
- **Popups can be validated WITHOUT running the bar**: a script pulls `PopupView`, the draw
  helpers and the row builders out of `bar.swift` by brace matching into a throwaway file, adds a
  `main` that loads each `themes/*/sketchybar.sh` palette and writes `cacheDisplay` PNGs. That is
  how the five themes get eyeballed from a worktree — never by launching a second bar.
- The clock label is built from `DateComponents`, not a `DateFormatter` pattern: a pattern (even
  with `zh_CN`) still answers to the user's region settings. Any new date text follows that rule.

- Right-cluster geometry: a pill is `10 + iconInk + (7 if icon&&label) + labelAdvance + 10`,
  except a solo icon-only pill, which is a `pillHeight` square; pills are separated by `gap`
  14 and laid out from the right edge inwards. Grouped members share one background:
  `10 + sum(content) + 8*(k-1) + 10`.

- **"The overview renders but the digit and the card click do nothing" is the DOCK, not the
  overview.** Root-caused 2026-08-31: with the system Mission Control gesture live in the
  running Dock, four fingers landing hands the Dock the window-server input grab — no Mission
  Control ever appears — and the event arrives at `.cgSessionEventTap` addressed to the
  overview and leaves `.cgAnnotatedSessionEventTap` addressed to the Dock, which swallows it.
  A grab outranks our front process, so nothing inside `overview.swift` can win it back. The
  cause was `macos-defaults.sh` writing the gesture keys without ever bouncing the Dock, so
  **`defaults read` reports the gesture disabled while it is still live** — never trust that
  reading; the fix is a Dock restart (`uninstall.sh` always did this, the install side did not).
- The overview's own input path is far more robust than it looks, and a whole family of
  plausible theories about it is FALSIFIED — measured the same day, pinned by
  `test/overview-inputfocus.swift`. A `.nonactivatingPanel` that AppKit has made key keeps
  receiving keys AND clicks when the process is **not** the window-server front process, when
  another app's window is made key by the private SLPS pair, and with
  `NSView.acceptsFirstMouse` at its default `false`. So none of "the grab was refused",
  "the front process was stolen" or "the click was eaten as an activation click" can explain
  a real keystroke going missing. `didResignKey -> frontmost now: <other app>` in
  `/tmp/omacosy-overview.log` only means something took front at hide time (a click outside
  the overlay's screen does it) — it is NOT evidence about the grab.
- Test-only environment variables read by `helper/overview.swift`, set by nothing in the
  shipped install: `OMACOSY_OVERVIEW_TEST_ID` (isolated pidfile/flag/log, no sibling kill) and
  `OMACOSY_OVERVIEW_TEST_FOCUS_GRAB` (`off` = never grab or verify window-server focus,
  `delay` = refuse only the first grab). Both exist so `test/run-overview-*.sh` can drive a
  throwaway daemon on a live desktop. `test/run-overview-selfactivation.sh` types the digit of
  the ALREADY focused workspace and needs a genuinely idle desktop — a stray click from the
  user reads as the behaviour under test and the run reports failures that are not real.
- Instrumenting a real user's input on this machine: two LISTEN-ONLY `CGEvent` taps, one at
  `.cgSessionEventTap` and one at `.cgAnnotatedSessionEventTap`, distinguish "an event tap ate
  it" from "the window server routed it elsewhere" from "it reached the process and was
  dropped inside it" — the annotated point carries `eventTargetUnixProcessID`. Log keys as a
  coarse CLASS only, and only while the overlay flag exists. Note `CGGetEventTapList()`: on ZZ
  a third-party app holds an ACTIVE keyDown tap at the HID point, which is upstream of both.

- `helper/overview.swift` never dismisses on a focus change nobody asked for: the
  `didResignKeyNotification` observer re-takes key (`makeKeyAndOrderFront` + `slpsFocus`) when
  `userInputAge()` — the same key/click/scroll CGEvent reading `omacosy-helper input-age` prints for
  `bin/omacosy-focus-guard` — is over 1.5 s, capped at `keyRetakeLimit` per showing and reset by
  `showOverlay()`. Self-activating apps (Electron, notification banners) used to make the overlay
  vanish under the user, so the next digit landed in the app underneath.
- The overview daemon KILLS every `omacosy-overview --daemon` sibling it finds (`overview.swift`
  singleton block), so a second instance would take down the live one. `OMACOSY_OVERVIEW_TEST_ID`
  is the TEST-ONLY escape hatch: it suffixes the pidfile, the ffm truce flag and the log, and skips
  the sibling kill. Nothing in the shipped install sets it; `test/run-overview-selfactivation.sh` is
  its only consumer and is how overview behaviour gets validated from a worktree on a live desktop.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
