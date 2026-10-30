# Raycast Script Commands — Omarchy 风格系统菜单

这一批脚本把 Omarchy 的 `omarchy-menu`（System 那一组）搬到 macOS：Raycast 负责唤起，
每个动作一个脚本，靠文件头的 `@raycast.*` 注释向 Raycast 声明标题、图标和运行模式。
`packageName` 统一是 `Omarchy`，所以在 Raycast 里它们会归到同一组、一起被搜到。

## 每台机器注册一次

Raycast 不读仓库，只读你告诉它的目录，所以每台机器都要手动加一次（GUI 操作，无法脚本化）：

**Raycast → Settings（`⌘,`）→ Extensions → 左下角 `+` → Add Script Directory →
选择 `~/.config/raycast/scripts` → Open。**

加完之后在 Raycast 主界面直接搜脚本标题即可；想给某个脚本配快捷键，在同一个 Extensions
列表里选中它，在右侧 Record Hotkey 里录。

## 脚本清单

| 脚本 | Raycast 标题 | 模式 | 做什么 |
|---|---|---|---|
| `paneru-restart.sh` | Restart Paneru | silent | `launchctl kickstart -k` 重启 Paneru 的 LaunchAgent |
| `appearance-toggle.sh` | Toggle Appearance | silent | 切换 macOS 深色 / 浅色 |
| `weather-status.sh` | Weather | inline | 一行成都实况天气，直接显示在 Raycast 列表里 |
| `lock-screen.sh` | Lock Screen | silent | 立即锁屏（要求密码） |
| `sleep.sh` | Sleep | silent + 确认 | `pmset sleepnow`，执行前 Raycast 会弹确认 |

## 首次运行需要的系统权限

| 脚本 | 权限 | 位置 |
|---|---|---|
| `appearance-toggle.sh` | 自动化 → 控制「系统事件」 | 系统设置 → 隐私与安全性 → 自动化 → Raycast |
| `lock-screen.sh` | 辅助功能（脚本靠模拟 ⌃⌘Q 锁屏） | 系统设置 → 隐私与安全性 → 辅助功能 → Raycast |

首次触发时 macOS 会自己弹窗申请，允许一次即可；被拒过的话要去上表位置手动打开。

## 实现上的两个取舍

- **锁屏用 ⌃⌘Q，不用 `pmset displaysleepnow`。** 本机 `sysadminctl -screenLock` 宽限期是
  300 秒，熄屏后五分钟内不需要密码，等于没锁；macOS 26 又移除了老办法 `CGSession -suspend`。
  系统锁屏快捷键 ⌃⌘Q 不受宽限期影响，立即要求密码。
- **天气图标用 emoji，不用 Nerd Font 字形。** 天气分类和中文文案复用
  `omacosy/scripts/weather_lib.py`（和状态栏同一份口径），但图标另映射成
  emoji —— Raycast 行内输出走系统字体，状态栏那套 Nerd Font 字形在这里会变豆腐块。
  数据优先读 OMacOSy 的 Open-Meteo 缓存 `/tmp/sketchybar_daemon/weather.json`，缺失才回源 wttr.in。

## 不在这批里的东西

保持不动，避免和现有配置重复：

- **caffeinate / 防休眠开关** —— OMacOSy 状态栏已经有一个。
- **启动 App 的快捷键** —— 直接用 Raycast 自带的 Applications 快捷键，不需要脚本。
- **任何装软件的动作** —— Omarchy 的 Install / Update 分组在这台机器上没有对应物。
