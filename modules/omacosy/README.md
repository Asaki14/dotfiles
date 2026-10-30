# omacosy

[English](README.md) | [简体中文](README.zh-CN.md)

Desktop and theme system.

## Install

```bash
./install.sh --modules omacosy
```

Run from the repository root. Homebrew packages: `git`, `fzf`, `eza`, `zoxide`, `ripgrep`, `bat`, `lazygit`, `btop`, `jq`, `starship`, `nikitabobko/tap/aerospace`, `karabiner-elements`, `ghostty`, `raycast`, `font-jetbrains-mono-nerd-font`.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.config/karabiner/karabiner.json`](home/.config/karabiner/karabiner.json) | `~/.config/karabiner/karabiner.json` |
| [`home/.config/omacosy/bar-items.conf`](home/.config/omacosy/bar-items.conf) | `~/.config/omacosy/bar-items.conf` |
| [`home/.config/omacosy/borders.conf`](home/.config/omacosy/borders.conf) | `~/.config/omacosy/borders.conf` |
| [`home/.config/omacosy/ffm-ignore`](home/.config/omacosy/ffm-ignore) | `~/.config/omacosy/ffm-ignore` |
| [`home/.config/omacosy/gesture.json`](home/.config/omacosy/gesture.json) | `~/.config/omacosy/gesture.json` |
| [`home/.config/omacosy/scripts/ai_usage_popup.sh`](home/.config/omacosy/scripts/ai_usage_popup.sh) | `~/.config/omacosy/scripts/ai_usage_popup.sh` |
| [`home/.config/omacosy/scripts/codexbar_omp.sh`](home/.config/omacosy/scripts/codexbar_omp.sh) | `~/.config/omacosy/scripts/codexbar_omp.sh` |
| [`home/.config/omacosy/scripts/now_playing_daemon.py`](home/.config/omacosy/scripts/now_playing_daemon.py) | `~/.config/omacosy/scripts/now_playing_daemon.py` |
| [`home/.config/omacosy/scripts/weather_lib.py`](home/.config/omacosy/scripts/weather_lib.py) | `~/.config/omacosy/scripts/weather_lib.py` |
| [`home/.config/omacosy/scripts/weather_popup.sh`](home/.config/omacosy/scripts/weather_popup.sh) | `~/.config/omacosy/scripts/weather_popup.sh` |
| [overlay/](overlay/) | `~/.local/share/omacosy/` |
| [UPSTREAM](UPSTREAM) | Pinned upstream revision |

## Setup

The installer checks out upstream `59b52024a016bfe0993a880c4b455cfe4eb064ed` in `~/.local/share/omacosy`, copies [overlay](overlay/) over it, applies deletions from [overlay/.deleted](overlay/.deleted), runs upstream `install.sh`, then links [home](home/). This also applies to an existing checkout: preserve local edits yourself. The upstream installer changes macOS defaults, installs LaunchAgents, compiles helpers and sets wallpaper; file backups do not undo those system changes. It also changes other desktop configurations. Review the overlay installer before use. Upstream license: [MIT](https://github.com/paulsp94/omacosy/blob/59b52024a016bfe0993a880c4b455cfe4eb064ed/LICENSE).

Set `OMACOSY_WEATHER_LOCATION`, `OMACOSY_WEATHER_LAT` and `OMACOSY_WEATHER_LON` in the environment of the weather process. For launchd-launched apps, shell configuration alone is insufficient; set the variables in that LaunchAgent’s environment. Review `bar-items.conf`, app bindings and Karabiner mappings. Caps Lock is Super when held and Escape when tapped. AI usage needs CodexBar and a signed-in account; music integration needs the music module.
