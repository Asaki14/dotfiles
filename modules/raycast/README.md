# raycast

[English](README.md) | [简体中文](README.zh-CN.md)

System script commands.

## Install

```bash
./install.sh --modules raycast
```

Run from the repository root. Homebrew packages: `raycast`.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.config/raycast/scripts/README.md`](home/.config/raycast/scripts/README.md) | `~/.config/raycast/scripts/README.md` |
| [`home/.config/raycast/scripts/appearance-toggle.sh`](home/.config/raycast/scripts/appearance-toggle.sh) | `~/.config/raycast/scripts/appearance-toggle.sh` |
| [`home/.config/raycast/scripts/lock-screen.sh`](home/.config/raycast/scripts/lock-screen.sh) | `~/.config/raycast/scripts/lock-screen.sh` |
| [`home/.config/raycast/scripts/paneru-restart.sh`](home/.config/raycast/scripts/paneru-restart.sh) | `~/.config/raycast/scripts/paneru-restart.sh` |
| [`home/.config/raycast/scripts/sleep.sh`](home/.config/raycast/scripts/sleep.sh) | `~/.config/raycast/scripts/sleep.sh` |
| [`home/.config/raycast/scripts/weather-status.sh`](home/.config/raycast/scripts/weather-status.sh) | `~/.config/raycast/scripts/weather-status.sh` |

## Setup

In Raycast Settings > Extensions > + > Add Script Directory, add `~/.config/raycast/scripts`. Commands toggle appearance, lock the screen, sleep, restart Paneru and show weather. Grant Automation or Accessibility access when macOS requests it. Restart Paneru requires an existing `com.github.karinushka.paneru` LaunchAgent; this module does not install Paneru. Weather imports the omacosy module’s Python helpers and has a fixed fallback location in `weather-status.sh`; edit it for your location. Store extensions are installed separately:

- [Spotify Player](https://www.raycast.com/mattisssa/spotify-player) (mattisssa)
- [Obsidian](https://www.raycast.com/marcjulian/obsidian) (marcjulian)
- [Downloads Manager](https://www.raycast.com/thomas/downloads-manager) (thomas)
- [Zen Browser](https://www.raycast.com/Keyruu/zen-browser) (Keyruu)
- [Kill Process](https://www.raycast.com/rolandleth/kill-process) (rolandleth)
