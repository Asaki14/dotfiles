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

The installer checks out upstream `59b52024a016bfe0993a880c4b455cfe4eb064ed` in `~/.local/share/omacosy`, copies [overlay](overlay/) over it, applies deletions from [overlay/.deleted](overlay/.deleted), runs upstream `install.sh`, then links [home](home/). An existing `~/.local/share/omacosy` that this installer did not create is moved to the backup directory first; a checkout it created is reset to the pinned revision on rerun. The upstream installer changes macOS defaults, installs LaunchAgents, compiles helpers and sets wallpaper; file backups do not undo those system changes. It also changes other desktop configurations. Review the overlay installer before use. Upstream license: [MIT](https://github.com/paulsp94/omacosy/blob/59b52024a016bfe0993a880c4b455cfe4eb064ed/LICENSE).

The osaka-jade wallpaper rotation includes the [original Diane wallpaper from xrce/dots](https://github.com/xrce/dots/blob/main/dots/diane/wallpaper/diane.jpg), saved as `themes/osaka-jade/backgrounds/4-diane.jpg`.

Set `OMACOSY_WEATHER_LOCATION`, `OMACOSY_WEATHER_LAT` and `OMACOSY_WEATHER_LON` in the environment of the weather process. For launchd-launched apps, shell configuration alone is insufficient; set the variables in that LaunchAgent’s environment. Review `bar-items.conf`, app bindings and Karabiner mappings. Caps Lock is Super when held and Escape when tapped. AI usage needs CodexBar and a signed-in account; music integration needs the music module.

`proxy-speed on` in `bar-items.conf` enables a fixed-width, two-line speed cell immediately left of Fishing Funds: upload above download, with dim arrows and right-aligned monospaced digits. Both lines show integer KB/s (1 KB = 1,000 bytes), never B/s or MB/s. The bar samples mihomo `/connections` totals every two seconds and reads `external-controller` and `secret` from Clash Verge Rev's local `config.yaml` at each sample; credentials are never stored here. Unavailable controllers show two muted dashes. Set `proxy-speed off` or remove the directive, then reload with `launchctl kickstart -k "gui/$(id -u)/com.omacosy.bar"` to disable it.

The Fishing Funds popup lays each fund on a fixed grid: name, 20-trading-day NAV curve, rate, profit, with a portfolio total row on top. The curve and figures come from the external estimator named by `fission-estimator` in `bar-items.conf` (not in this repository). It must print `rate`, `profit` and `spark` (NAV series) per `displayRows` entry and a top-level `totalSpark`; without them rows show an em dash in place of the figures and no curve.
