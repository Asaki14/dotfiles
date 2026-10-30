# nvim

[English](README.md) | [简体中文](README.zh-CN.md)

Editing, search and completion.

## Install

```bash
./install.sh --modules nvim
```

Run from the repository root. Homebrew packages: `neovim`, `ripgrep`, `fd`.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.config/nvim/init.lua`](home/.config/nvim/init.lua) | `~/.config/nvim/init.lua` |
| [`home/.config/nvim/lazy-lock.json`](home/.config/nvim/lazy-lock.json) | `~/.config/nvim/lazy-lock.json` |
| [`home/.config/nvim/lua/configs.lua`](home/.config/nvim/lua/configs.lua) | `~/.config/nvim/lua/configs.lua` |
| [`home/.config/nvim/lua/keymaps.lua`](home/.config/nvim/lua/keymaps.lua) | `~/.config/nvim/lua/keymaps.lua` |
| [`home/.config/nvim/lua/plugins.lua`](home/.config/nvim/lua/plugins.lua) | `~/.config/nvim/lua/plugins.lua` |

## Setup

Run `nvim`; lazy.nvim downloads plugins on first launch, so Git and network access are required. Space is the leader; `<leader>ff` finds files and `<leader>fg` searches text. The dashboard references `~/.config/nvim/assets/nyde.jpeg`, which is not included; supply your own image and install `chafa`, or remove that dashboard section.
