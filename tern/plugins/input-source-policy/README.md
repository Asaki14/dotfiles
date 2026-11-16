# Input Source Policy (Tern plugin `input-source-policy`)

macOS-only Tern plugin that picks the keyboard input source from what the
**focused Tern pane** runs. It replaces the Herdr poller in
`herdr/plugins/yazi-input-source`, which stays as the reference implementation.

## Policy

| Focused pane | Class | `reason` |
|---|---|---|
| Title starts with an ASCII app (`yazi`, `dooit`, `rmpc`) | `ascii` | `<app>` |
| Agent block (`PaneInfo.kind == "agent"`) | `cjk` | `agent` |
| Anything else (shell, browser, file block, …) | `ascii` | `other` |

ASCII apps are declared once, in `ASCII_APPS` in `window.luau`. A title matches
when it equals the name or continues with `:` or a space, case-insensitively:
`dooit ~`, `Yazi: Downloads`, `rmpc ~`. Titles are the only usable signal for
these apps: Tern reports yazi's and rmpc's `program` as the shell.

Agent detection uses Tern's block kind, never the title. Tern marks native omp
blocks, Firstmate's launch-script agents and `PI_TUI_NATIVE=0` omp workers as
`kind = "agent"` (verified 2026-10-15 on Tern 0.8.3).

`cjk` resolves to the source remembered in
`~/.local/state/tern-input-source-policy/previous-input-source` (written when
the plugin last displaced a non-ASCII source), else the first enabled non-ASCII
keyboard source, else `im.rime.inputmethod.Squirrel.Hans`. `ascii` is US Extended
(`com.apple.keylayout.USExtended`).

## Trigger: focus edges, no polling

Tern runs window-side `focus` hooks for every focus change inside the client,
keyboard included (verified: the hook fired 44–51 ms after a key-down, with no
click for minutes before). That is the gap that forced the Herdr version to
poll. Here `focus` and `title` feed an edge detector:

- The policy applies only when the focused (pane, class) pair changes: a new
  pane got focus, or the focused pane's class changed in place (yazi launched
  or quit). A `title` event that keeps the class does nothing, so agent
  retitles never re-apply and a manual switch inside a pane sticks.
- A pair counts once it has held for 700 ms (`SETTLE_MS`), so programmatic
  focus blips (focus a tab, act, restore) do not flap the input source.

The switch runs `scripts/input-source-policy ascii|cjk`, which builds
`src/main.swift` into `~/.cache/tern-input-source-policy/` on first use (outside
the plugin directory, because Tern reloads a linked plugin when a file under it
changes). It selects the source unconditionally, re-reads it 300 ms later,
retries once if it did not take, and appends one line per apply to
`~/.local/state/tern-input-source-policy/policy.log`:

    pane=<id> reason=yazi desired=ascii before=im.rime.inputmethod.Squirrel.Hans after=com.apple.keylayout.USExtended

## Install

    tern plugin link ~/.config/tern/plugins/input-source-policy

## Commands

    scripts/input-source-policy status   # current source, its class, remembered CJK source
    scripts/input-source-policy ascii    # select US Extended (remembers what it displaced)
    scripts/input-source-policy cjk      # select the CJK source

## Known limitations

- The macOS input source is global. A change made behind Tern's back stays
  until the next focus edge — by design, so a manual switch is not fought.
- Rime's own ASCII sub-mode is invisible to the system: `Squirrel.Hans` reports
  not ASCII-capable in both modes.
- Every Tern window runs the plugin. Loading or reloading it applies the policy
  once per window for that window's focused pane.
- Pane-level granularity only: an agent's own file picker or `/` menu also gets
  CJK.
