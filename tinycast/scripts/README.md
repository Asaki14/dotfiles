# Tinycast 系统脚本

Tinycast 负责唤起这些 Omarchy 风格系统动作。脚本保留 `@raycast.*` 元数据，供 Tinycast 的 Raycast 脚本导入器读取。

## 每台机器导入一次

1. 在 Tinycast 的设置 → 命令中启用自定义命令。
2. 点击导入，选择 `~/.config/tinycast/scripts`。
3. 编辑 Weather，打开「显示输出」。Tinycast 不支持 Raycast 的 `inline` 自动刷新，天气需手动执行。

导入后，命令仍引用这个目录中的脚本。不要删除该目录。快捷键可在命令编辑器中设置。早期从 `~/.config/raycast/scripts` 导入的机器，在本地保留指向这里的软链接 `raycast/scripts` 即可，无需重新导入。

## 脚本清单

| 脚本 | 命令标题 | 模式 | 做什么 |
|---|---|---|---|
| `appearance-toggle.sh` | Toggle Appearance | silent | 切换 macOS 深色 / 浅色 |
| `weather-status.sh` | Weather | 显示输出 | 手动查询本地实况天气（地点见 `omacosy/scripts/location.local.json`） |
| `lock-screen.sh` | Lock Screen | silent | 立即锁屏，要求密码 |
| `sleep.sh` | Sleep | silent + 确认 | 执行 `pmset sleepnow`，运行前由 Tinycast 确认 |

## 首次运行需要的系统权限

| 脚本 | 权限 | 位置 |
|---|---|---|
| `appearance-toggle.sh` | 自动化 → 控制「系统事件」 | 系统设置 → 隐私与安全性 → 自动化 → Tinycast |
| `lock-screen.sh` | 辅助功能，脚本模拟 ⌃⌘Q 锁屏 | 系统设置 → 隐私与安全性 → 辅助功能 → Tinycast |

首次触发时 macOS 会自己弹窗申请，允许一次即可；被拒过的话要去上表位置手动打开。

## 实现上的两个取舍

- **锁屏用 ⌃⌘Q，不用 `pmset displaysleepnow`。** 本机 `sysadminctl -screenLock` 宽限期是
  300 秒，熄屏后五分钟内不需要密码，等于没锁；macOS 26 又移除了老办法 `CGSession -suspend`。
  系统锁屏快捷键 ⌃⌘Q 不受宽限期影响，立即要求密码。
- **天气图标用 emoji，不用 Nerd Font 字形。** 天气分类和中文文案复用
  `omacosy/scripts/weather_lib.py`（和状态栏同一份口径），但图标另映射成
  emoji，避免启动器使用系统字体时将 Nerd Font 字形显示成豆腐块。
  数据优先读 OMacOSy 的 Open-Meteo 缓存 `/tmp/sketchybar_daemon/weather.json`，缺失才回源 wttr.in。

## 不在这批里的东西

保持不动，避免和现有配置重复：

- **caffeinate / 防休眠开关**：OMacOSy 状态栏已经有一个。
- **启动 App 的快捷键**：使用 Tinycast 的 App 快捷键，不需要脚本。
- **任何装软件的动作**：Omarchy 的 Install / Update 分组在这台机器上没有对应物。
