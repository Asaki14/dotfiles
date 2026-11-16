<div align="center">
  <h1>dotfiles</h1>
  <p><b>A macOS <code>~/.config</code>: an omarchy-style tiling desktop, a local music library and a self-hosted news reader, set up by one <code>install.sh</code>.</b></p>
  <p>English · <a href="README.zh-CN.md">中文</a></p>
  <img src="https://img.shields.io/badge/macOS-26_Tahoe-black?style=flat-square&logo=apple" alt="macOS 26">
  <a href="https://github.com/Asaki14/dotfiles/commits"><img src="https://img.shields.io/github/last-commit/Asaki14/dotfiles?style=flat-square" alt="Last commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Asaki14/dotfiles?style=flat-square" alt="License"></a>
</div>

## Features

- **Tiling desktop**: [omacosy](https://github.com/paulsp94/omacosy) (AeroSpace, a native status bar, borders, gestures, themes) is vendored in `omacosy/src` with this setup's changes
- **Status bar data**: weather, AI quota, synced lyrics, net speed and an intraday fund estimate
- **Local music**: beets keeps the library, MPD plays it, rmpc is the player, and a Swift bridge puts MPD on macOS Now Playing and the media keys
- **News reader**: FreshRSS in Docker with a reader extension that translates articles in the background
- **Terminal and editor**: fish, Neovim (lazy.nvim), yazi with plugins, btop, fastfetch
- **Input that follows the pane**: a Tern plugin switches the macOS input source per terminal pane
- **System actions**: lock, sleep, appearance and weather as [Tinycast](https://tinycast.dev) script commands

## Quick Start

```bash
git clone https://github.com/Asaki14/dotfiles.git ~/.config
cd ~/.config && ./install.sh
```

If `~/.config` already exists, clone anywhere else: `install.sh` then links each config directory into `~/.config` and moves what it replaces to `~/.dotfiles-backup/<time>/`.

| Option | Effect |
|---|---|
| `--modules yazi,fish` | Only these config directories and the packages they need; the desktop runs only when `omacosy` is listed |
| `--dry-run` | Print every action, change nothing |
| `--no-brew` | Skip the Homebrew packages in `Brewfile` |
| `--no-desktop` | Skip the omacosy desktop (window manager, bar, themes) |
| `--no-network` | Do not look up the city from the IP address |

`install.sh` writes this machine's values into gitignored files, so the repo itself holds none:

| File | Detected from |
|---|---|
| `omacosy/bar-items.local.conf` | The paired AirPods or headphones, whose battery the bar shows |
| `omacosy/scripts/location.local.json` | The city of your IP address (ip-api.com), for the weather |
| `omacosy/scripts/fission_fund_wallet.json` | Copied from the example; list your fund codes and shares, or drop `fission-estimator` from `bar-items.conf` |

## Before installing

- [Tern](https://stencil.so/tern) is in closed beta; install it yourself. The AI quota and article translation use [omp](https://github.com/can1357/oh-my-pi), which you install and log in to yourself.
- FreshRSS is set up by hand: see [freshrss/README.md](freshrss/README.md).
- The omacosy installer changes macOS defaults, loads LaunchAgents, compiles helpers, sets the wallpaper and overwrites desktop configuration. File backups do not undo system settings. Read [omacosy/src/README.md](omacosy/src/README.md) first, or pass `--no-desktop`.
- API keys go in `fish/conf.d/api_keys.local.fish`, which is gitignored.

## What's Inside

| Path | What it is |
|---|---|
| `omacosy/src/` | The desktop: bar, window manager config, themes and their installer. `UPSTREAM` records the upstream commit it is based on |
| `omacosy/` | Bar layout (`bar-items.conf`) and its data scripts: weather, AI usage, lyrics, fund estimate |
| `fish/` `nvim/` `yazi/` `btop/` `fastfetch/` | Shell, editor, file manager and terminal tools |
| `mpd/` `rmpc/` `beets/` | Music library, playback, playlists and the Now Playing bridge |
| `freshrss/` | FreshRSS compose file, reader extension and translation worker |
| `tern/plugins/` `tinycast/scripts/` | Tern terminal plugin and Tinycast system commands |
| `karabiner/` `linearmouse/` | Keyboard and mouse |

Paths that differ per machine but are not detected: the music library (`~/Music/lib` in `mpd/mpd.conf` and `beets/config.yaml`) and the `omp` binary (`freshrss/reader-settings.json`).

## Notes

- `AGENTS.md` describes how the pieces talk to each other.
- [HISTORY.md](HISTORY.md) is the log of how this setup came to be.
- Licensed under [MIT](LICENSE). omacosy keeps its own license in `omacosy/src/LICENSE`.
