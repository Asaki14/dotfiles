# omacosy

[English](README.md) | [简体中文](README.zh-CN.md)

桌面与主题系统。

## 安装

```bash
./install.sh --modules omacosy
```

在仓库根目录运行。Homebrew 依赖：`git`、`fzf`、`eza`、`zoxide`、`ripgrep`、`bat`、`lazygit`、`btop`、`jq`、`starship`、`nikitabobko/tap/aerospace`、`karabiner-elements`、`ghostty`、`raycast`、`font-jetbrains-mono-nerd-font`。

## 文件与链接目标

| 源文件 | 目标 |
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
| [UPSTREAM](UPSTREAM) | 固定的上游版本 |

## 配置

安装器在 `~/.local/share/omacosy` 检出上游 `59b52024a016bfe0993a880c4b455cfe4eb064ed`，覆盖 [overlay](overlay/)，按 [overlay/.deleted](overlay/.deleted) 删除文件，执行上游 `install.sh`，最后链接 [home](home/)。如果 `~/.local/share/omacosy` 已存在且不是本安装器创建的，会先整体移入备份目录；本安装器创建的 checkout 重跑时会重置到固定版本。上游安装器会修改 macOS defaults、安装 LaunchAgents、编译辅助程序并设置壁纸，还会更改其他桌面配置。文件备份不能撤销这些系统更改，使用前请检查 overlay 中的安装脚本。上游许可证：[MIT](https://github.com/paulsp94/omacosy/blob/59b52024a016bfe0993a880c4b455cfe4eb064ed/LICENSE)。

osaka-jade 的壁纸轮换包含 [xrce/dots 的 Diane 原图](https://github.com/xrce/dots/blob/main/dots/diane/wallpaper/diane.jpg)，保存为 `themes/osaka-jade/backgrounds/4-diane.jpg`。

在天气进程的环境中设置 `OMACOSY_WEATHER_LOCATION`、`OMACOSY_WEATHER_LAT` 与 `OMACOSY_WEATHER_LON`。如果应用由 launchd 启动，只改 Shell 配置不够，需要在对应 LaunchAgent 的环境中设置。请检查 `bar-items.conf`、应用快捷键与 Karabiner 映射。Caps Lock 按住是 Super，单击是 Escape。AI 用量需要 CodexBar 与已登录账户，音乐集成需要 music 模块。

Fishing Funds 弹窗按固定列排版：基金名、近 20 个交易日净值曲线、涨跌幅、盈亏，顶部为合计行。曲线和数值来自 `bar-items.conf` 中 `fission-estimator` 指定的外部脚本（不在本仓库）。该脚本须在每个 `displayRows` 项输出 `rate`、`profit`、`spark`（净值序列），并在顶层输出 `totalSpark`；缺失时数值显示短横线，不画曲线。
