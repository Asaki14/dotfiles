# nvim

[English](README.md) | [简体中文](README.zh-CN.md)

编辑、搜索与补全。

## 安装

```bash
./install.sh --modules nvim
```

在仓库根目录运行。Homebrew 依赖：`neovim`、`ripgrep`、`fd`。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/nvim/init.lua`](home/.config/nvim/init.lua) | `~/.config/nvim/init.lua` |
| [`home/.config/nvim/lazy-lock.json`](home/.config/nvim/lazy-lock.json) | `~/.config/nvim/lazy-lock.json` |
| [`home/.config/nvim/lua/configs.lua`](home/.config/nvim/lua/configs.lua) | `~/.config/nvim/lua/configs.lua` |
| [`home/.config/nvim/lua/keymaps.lua`](home/.config/nvim/lua/keymaps.lua) | `~/.config/nvim/lua/keymaps.lua` |
| [`home/.config/nvim/lua/plugins.lua`](home/.config/nvim/lua/plugins.lua) | `~/.config/nvim/lua/plugins.lua` |

## 配置

运行 `nvim`，首次启动由 lazy.nvim 下载插件，需要 Git 与网络。空格是 leader 键，`<leader>ff` 查找文件，`<leader>fg` 搜索文本。启动页引用的 `~/.config/nvim/assets/nyde.jpeg` 未包含在仓库中，请自行提供图片并安装 `chafa`，或删除对应启动页配置。
