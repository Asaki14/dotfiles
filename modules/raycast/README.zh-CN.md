# raycast

[English](README.md) | [简体中文](README.zh-CN.md)

系统脚本命令。

## 安装

```bash
./install.sh --modules raycast
```

在仓库根目录运行。Homebrew 依赖：`raycast`。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/raycast/scripts/README.md`](home/.config/raycast/scripts/README.md) | `~/.config/raycast/scripts/README.md` |
| [`home/.config/raycast/scripts/appearance-toggle.sh`](home/.config/raycast/scripts/appearance-toggle.sh) | `~/.config/raycast/scripts/appearance-toggle.sh` |
| [`home/.config/raycast/scripts/lock-screen.sh`](home/.config/raycast/scripts/lock-screen.sh) | `~/.config/raycast/scripts/lock-screen.sh` |
| [`home/.config/raycast/scripts/paneru-restart.sh`](home/.config/raycast/scripts/paneru-restart.sh) | `~/.config/raycast/scripts/paneru-restart.sh` |
| [`home/.config/raycast/scripts/sleep.sh`](home/.config/raycast/scripts/sleep.sh) | `~/.config/raycast/scripts/sleep.sh` |
| [`home/.config/raycast/scripts/weather-status.sh`](home/.config/raycast/scripts/weather-status.sh) | `~/.config/raycast/scripts/weather-status.sh` |

## 配置

在 Raycast Settings > Extensions > + > Add Script Directory 中添加 `~/.config/raycast/scripts`。命令包括切换外观、锁屏、睡眠、重启 Paneru 与显示天气。按 macOS 提示授予自动化或辅助功能权限。重启 Paneru 需要已有的 `com.github.karinushka.paneru` LaunchAgent，本模块不安装 Paneru。天气脚本导入 omacosy 模块的 Python 辅助程序，`weather-status.sh` 的备用请求使用固定地点，请自行修改。商店扩展需单独安装：

- [Spotify Player](https://www.raycast.com/mattisssa/spotify-player) (mattisssa)
- [Obsidian](https://www.raycast.com/marcjulian/obsidian) (marcjulian)
- [Downloads Manager](https://www.raycast.com/thomas/downloads-manager) (thomas)
- [Zen Browser](https://www.raycast.com/Keyruu/zen-browser) (Keyruu)
- [Kill Process](https://www.raycast.com/rolandleth/kill-process) (rolandleth)
