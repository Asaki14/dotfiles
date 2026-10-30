# cli

[English](README.md) | [简体中文](README.zh-CN.md)

Everyday command-line tools.

## Install

```bash
./install.sh --modules cli
```

Run from the repository root. Homebrew packages: `git`, `btop`, `fastfetch`, `gh`, `md-tui`.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.config/btop/btop.conf`](home/.config/btop/btop.conf) | `~/.config/btop/btop.conf` |
| [`home/.config/fastfetch/config.jsonc`](home/.config/fastfetch/config.jsonc) | `~/.config/fastfetch/config.jsonc` |
| [`home/.config/fastfetch/images/phainon_clear.png`](home/.config/fastfetch/images/phainon_clear.png) | `~/.config/fastfetch/images/phainon_clear.png` |
| [`home/.config/gh/config.yml`](home/.config/gh/config.yml) | `~/.config/gh/config.yml` |
| [`home/.config/git/config`](home/.config/git/config) | `~/.config/git/config` |
| [`home/.config/git/ignore`](home/.config/git/ignore) | `~/.config/git/ignore` |
| [`home/.config/mdt/config.toml`](home/.config/mdt/config.toml) | `~/.config/mdt/config.toml` |

## Setup

Set Git identity in `~/.gitconfig.local`, which the included Git config loads. Authenticate GitHub CLI with `gh auth login`. fastfetch uses the Kitty image protocol; choose a compatible terminal or change its logo configuration.
