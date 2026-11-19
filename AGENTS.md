# Repository Guidelines

## Project Overview

This repository is the public `Asaki14/dotfiles`, checked out as `~/.config` itself. It tracks macOS user configuration plus scripts integrating the desktop, terminal, news reader, and music library. It has no single application entry point or repository-wide build. Keep application-specific changes in their existing directories. `.gitignore` is an allowlist: only the directories it names are tracked, so add a new app directory there deliberately. Personal data (holdings, credentials, hostnames, locations, device names, machine state) stays in gitignored `*.local.*` files that `install.sh` writes.

## Architecture & Data Flow

| Integration | Flow and ownership |
| --- | --- |
| Desktop | `omacosy/src/` is a vendored copy of [omacosy](https://github.com/paulsp94/omacosy) with local changes; `~/.local/share/omacosy` is a symlink to it, and its LaunchAgents run from there. `omacosy/src/UPSTREAM` is the upstream commit it is based on: take upstream changes as `git diff <UPSTREAM>..<new>` from an upstream clone, apply with `git apply -3 --directory=omacosy/src`, then update `UPSTREAM`. `omacosy/bar-items.conf` and `omacosy/scripts/` feed the bar; `omacosy/bar-items.local.conf` overrides directives per machine. |
| Themes | OMacOSy reads `omarchy/current/theme` and renders app-specific themes. Preserve this theme entry point even though its name looks historical. |
| Music | Beets manages `~/Music/lib`; MPD serves it to rmpc. `mpd/playlist-sync` links the local playlists for MPD, removes duplicates, fetches missing tracks, and refreshes MPD. Playlists are local only; only `mpd/playlists/example.m3u` is tracked. |
| System media | `mpd/nowplaying/mpd-nowplaying.swift` polls MPD through its Unix socket, publishes macOS Now Playing state, and sends media-key commands back to MPD. |
| News | FreshRSS runs in Docker (`freshrss/compose.yaml`); its `LocalReader` extension and `freshrss/reader.py` translate articles in the background. Setup and operation are in the README's FreshRSS section. |
| Input source | Tern focus/title events enter a Luau policy, which debounces pane changes and invokes a Swift helper to select the macOS input source. |

`/tmp/sketchybar_daemon` is a cache interface still used by OMacOSy helpers, not evidence of an active SketchyBar installation. Do not rename it without migrating its consumers.

Active bar helpers live in `omacosy/scripts/`. In `omacosy/bar-items.conf`, the `codexbar` directive points to `omacosy/scripts/omp_usage.py`: it reads OMP's usage cache from `~/.omp/agent/agent.db` read-only and emits the JSON shape consumed by the bar. The directive name is not a requirement to install CodexBar.

## Key Directories

| Path | Maintenance boundary |
| --- | --- |
| `fish/`, `nvim/`, `yazi/` | Shell environment, editor configuration, and file-manager configuration. |
| `omacosy/` | Bar layout and status-bar data providers; the desktop itself is in `omacosy/src/`, which has its own `AGENTS.md`. |
| `mpd/`, `rmpc/`, `beets/` | Playlist automation, macOS media bridge, playback configuration, and library management. |
| `freshrss/` | FreshRSS deployment, reader extension, and translation worker. |
| `tern/plugins/input-source-policy/` | Luau event policy, Swift helper source, and compile-on-demand wrapper. |
| `tinycast/scripts/` | Tinycast system commands in Raycast script format. Import the directory on each machine as the README's Tinycast section describes. |
| `homebrew/` | Local trust records, excluded from Git. `/opt/homebrew/etc/homebrew/brew.env` selects this directory through `HOMEBREW_XDG_CONFIG_HOME`. |

## Development Commands

Run commands from the repository root. There is no root `build`, `test`, or `lint` command; select checks for the changed files.

| Purpose | Command |
| --- | --- |
| Fish syntax | `for f in fish/config.fish fish/conf.d/locale.fish; do fish -n "$f" || exit; done` |
| Shell syntax | `for f in tinycast/scripts/*.sh omacosy/scripts/*.sh; do bash -n "$f" || exit; done` |
| JavaScript syntax | `node --check omacosy/scripts/fission_fund_estimator.js` |
| Python syntax without bytecode | `python3 -c 'import ast,pathlib; ast.parse(pathlib.Path("omacosy/scripts/weather_lib.py").read_text())'` |
| Media bridge plists | `plutil -lint mpd/nowplaying/Info.plist mpd/nowplaying/local.mpd-nowplaying.plist` |
| Installer | `bash -n install.sh && ./install.sh --dry-run --no-brew --no-desktop` |
| Install media bridge | `sh mpd/nowplaying/install.sh` compiles, installs, and restarts its LaunchAgent. Run only when deployment is requested. |

Syntax-check other changed Fish or shell files individually. A shell's `-n` option checks one script; passing several script paths is not a batch check. To exercise shell startup, run `fish -i -c 'printf "LANG=%s\n" "$LANG"'`; this loads local configuration.

## Code Conventions & Common Patterns

Use concise Conventional Commit subjects such as `fix: ...` or `chore: ...`.

| Pattern | Preserve when changing code |
| --- | --- |
| Process boundaries | Existing CLIs, configuration files, and stdout TSV/JSON connect tools. There is no shared dependency-injection container or global application state. |
| Concurrent article processing | `freshrss/reader.py` uses file locks and temporary-file replacement. Preserve duplicate-job prevention and atomic cache updates. |
| Input-source events | Tern debounces changes and queues the latest requested state during a switch. Keep policy in Luau and macOS input operations in Swift. |
| Failure handling | Follow each tool's current error contract. The music bridge clears unavailable playback state; playlist synchronization reports failed downloads and skips MPD refresh when unreachable. Do not hide failures with success-shaped fallbacks. |
| Shared data | Weather mappings live in `omacosy/scripts/weather_lib.py`. MPD FIFO format/path must agree with `rmpc/config.ron`; playlists contain paths relative to the music library. |
| Portable paths | Use `~/.config/omacosy/scripts/...` in `omacosy/bar-items.conf`, not a machine-specific absolute home path. |

## Important Files

| File | Why it matters |
| --- | --- |
| `.gitignore` | Allowlist of tracked directories and the local-only files inside them. |
| `install.sh`, `Brewfile` | Links configs, installs packages, writes `*.local.*` values, runs `omacosy/src/install.sh`. |
| `fish/config.fish`, `fish/conf.d/locale.fish` | Shell entry point and fallback UTF-8 environment. |
| `nvim/init.lua`, `nvim/lua/plugins.lua`, `nvim/lazy-lock.json` | Load order, lazy.nvim plugin declarations, and pinned plugin versions. |
| `omacosy/bar-items.conf`, `omacosy/scripts/` | Desktop-to-script contracts, including weather, AI usage, funds, and lyrics. |
| `mpd/mpd.conf`, `mpd/playlist-sync`, `mpd/nowplaying/install.sh` | Music paths, playlist synchronization, and media-bridge deployment. |
| `freshrss/compose.yaml`, `freshrss/reader.py` | News deployment and translation worker. |
| `tern/plugins/input-source-policy/plugin.toml` | Tern plugin entry points; helper wrapper is under `scripts/`, native source under `src/`. |

## Runtime/Tooling Preferences

This is a macOS repository. Native helpers require Apple frameworks and `swiftc` or `xcrun swiftc`. Use Fish for `.fish`, the declared shebang for scripts, Python 3, and Node.js for the JavaScript helpers. There is no repository-wide Node package manager, lockfile, or Bun requirement.

Keep generated OMacOSy configuration and themes out of Git: examples include `aerospace`, `omacosy/apps.conf`, `omarchy/`, `rmpc/themes/omacosy.ron`, and `yazi/flavors/omacosy.yazi/`. Change their source in `omacosy/src/` instead of editing through symlinks. Tern helper binaries belong in `~/.cache/tern-input-source-policy/`; MPD runtime data belongs in `~/.local/share/mpd/`.

Never commit credentials, `.env`, private keys, `*.local.*` files, `gh/hosts.yml`, `omacosy/scripts/fission_fund_wallet.json`, `fish/fish_variables`, playlists, caches, or generated bundles. Before committing, grep the staged tree for home paths, names, emails, hostnames and locations. Do not print credential-bearing app configuration during inspection. Scripts for AI usage, funds, and lyrics may access local accounts, make network requests, update caches, or write `.lrc` files; they are not read-only checks. `mpd/playlist-sync` can download files.

Herdr, personal Ghostty configuration, Raycast, Newsboat, md-tui and fastfetch were removed. Do not recreate them incidentally. Keep documentation in the root `README.md` / `README.zh-CN.md` and this file; do not add per-directory READMEs.

## Testing & QA

No repository-wide test framework, CI workflow, or coverage threshold was found. Syntax checks establish parsing only. After behavioral changes, exercise the affected consumer: open a feed article, verify playback and media controls, switch Tern panes, or inspect the changed desktop/Tinycast command. Avoid unrelated installers, service restarts, package-manager operations, or system-action commands.

For Tinycast, follow the import and permission table in the README's Tinycast section. For native helpers, distinguish compilation from installation and service reloads. Review the scoped diff for secrets and generated state before committing.
