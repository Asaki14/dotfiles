# tern

[English](README.md) | [简体中文](README.zh-CN.md)

终端输入法切换策略。

## 安装

```bash
./install.sh --modules tern
```

在仓库根目录运行。本模块不通过 Homebrew 安装软件。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/tern/plugins/input-source-policy/README.md`](home/.config/tern/plugins/input-source-policy/README.md) | `~/.config/tern/plugins/input-source-policy/README.md` |
| [`home/.config/tern/plugins/input-source-policy/plugin.toml`](home/.config/tern/plugins/input-source-policy/plugin.toml) | `~/.config/tern/plugins/input-source-policy/plugin.toml` |
| [`home/.config/tern/plugins/input-source-policy/scripts/input-source-policy`](home/.config/tern/plugins/input-source-policy/scripts/input-source-policy) | `~/.config/tern/plugins/input-source-policy/scripts/input-source-policy` |
| [`home/.config/tern/plugins/input-source-policy/src/main.swift`](home/.config/tern/plugins/input-source-policy/src/main.swift) | `~/.config/tern/plugins/input-source-policy/src/main.swift` |
| [`home/.config/tern/plugins/input-source-policy/window.luau`](home/.config/tern/plugins/input-source-policy/window.luau) | `~/.config/tern/plugins/input-source-policy/window.luau` |

## 配置

请单独安装 [Tern](https://stencil.so/tern)，目前处于封闭内测。安装 Apple Command Line Tools 以提供 `swiftc`。启用 US Extended 与非 ASCII 输入法，然后运行 `tern plugin link ~/.config/tern/plugins/input-source-policy`。插件随焦点窗格切换输入法，首次使用时将 Swift 辅助程序编译到 `~/.cache/tern-input-source-policy/`。请检查插件文件中的输入法 ID 与应用匹配规则。
