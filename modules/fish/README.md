# fish

[English](README.md) | [简体中文](README.zh-CN.md)

Interactive shell and shortcuts.

## Install

```bash
./install.sh --modules fish
```

Run from the repository root. Homebrew packages: `fish`.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.config/fish/completions/fisher.fish`](home/.config/fish/completions/fisher.fish) | `~/.config/fish/completions/fisher.fish` |
| [`home/.config/fish/conf.d/chrome-devtools-axi.fish`](home/.config/fish/conf.d/chrome-devtools-axi.fish) | `~/.config/fish/conf.d/chrome-devtools-axi.fish` |
| [`home/.config/fish/conf.d/clojure-paths.fish`](home/.config/fish/conf.d/clojure-paths.fish) | `~/.config/fish/conf.d/clojure-paths.fish` |
| [`home/.config/fish/conf.d/locale.fish`](home/.config/fish/conf.d/locale.fish) | `~/.config/fish/conf.d/locale.fish` |
| [`home/.config/fish/config.fish`](home/.config/fish/config.fish) | `~/.config/fish/config.fish` |
| [`home/.config/fish/fish_plugins`](home/.config/fish/fish_plugins) | `~/.config/fish/fish_plugins` |
| [`home/.config/fish/functions/fisher.fish`](home/.config/fish/functions/fisher.fish) | `~/.config/fish/functions/fisher.fish` |
| [`home/.config/fish/functions/ytm.fish`](home/.config/fish/functions/ytm.fish) | `~/.config/fish/functions/ytm.fish` |

## Setup

Set `DOTFILES_PROXY_PORT` before using `proxy`; `noproxy` clears the proxy environment variables. Keep secrets in `~/.config/fish/conf.d/api_keys.local.fish`. Install the tools behind optional aliases yourself: `y` needs Yazi, `ft` needs fastfetch and the cli module, and `ytm` needs yt-dlp, ffmpeg and Chrome cookies. The `cc` alias enables Claude Code’s permission-bypass option; review it before use. Install plugins from `fish_plugins` with `fisher update`. This module does not change your login shell.
