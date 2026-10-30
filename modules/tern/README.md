# tern

[English](README.md) | [简体中文](README.zh-CN.md)

Terminal input-source policy.

## Install

```bash
./install.sh --modules tern
```

Run from the repository root. No Homebrew packages are installed by this module.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.config/tern/plugins/input-source-policy/README.md`](home/.config/tern/plugins/input-source-policy/README.md) | `~/.config/tern/plugins/input-source-policy/README.md` |
| [`home/.config/tern/plugins/input-source-policy/plugin.toml`](home/.config/tern/plugins/input-source-policy/plugin.toml) | `~/.config/tern/plugins/input-source-policy/plugin.toml` |
| [`home/.config/tern/plugins/input-source-policy/scripts/input-source-policy`](home/.config/tern/plugins/input-source-policy/scripts/input-source-policy) | `~/.config/tern/plugins/input-source-policy/scripts/input-source-policy` |
| [`home/.config/tern/plugins/input-source-policy/src/main.swift`](home/.config/tern/plugins/input-source-policy/src/main.swift) | `~/.config/tern/plugins/input-source-policy/src/main.swift` |
| [`home/.config/tern/plugins/input-source-policy/window.luau`](home/.config/tern/plugins/input-source-policy/window.luau) | `~/.config/tern/plugins/input-source-policy/window.luau` |

## Setup

Install [Tern](https://stencil.so/tern) separately; it is in closed beta. Install Apple Command Line Tools for `swiftc`. Enable US Extended and a non-ASCII input source, then run `tern plugin link ~/.config/tern/plugins/input-source-policy`. The plugin switches input sources when focused panes change and compiles its Swift helper into `~/.cache/tern-input-source-policy/` on first use. Review source IDs and app matching in the plugin files.
