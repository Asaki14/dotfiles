# cli

[English](README.md) | [简体中文](README.zh-CN.md)

日常命令行工具。

## 安装

```bash
./install.sh --modules cli
```

在仓库根目录运行。Homebrew 依赖：`git`、`btop`、`fastfetch`、`gh`、`md-tui`。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/btop/btop.conf`](home/.config/btop/btop.conf) | `~/.config/btop/btop.conf` |
| [`home/.config/fastfetch/config.jsonc`](home/.config/fastfetch/config.jsonc) | `~/.config/fastfetch/config.jsonc` |
| [`home/.config/fastfetch/images/phainon_clear.png`](home/.config/fastfetch/images/phainon_clear.png) | `~/.config/fastfetch/images/phainon_clear.png` |
| [`home/.config/gh/config.yml`](home/.config/gh/config.yml) | `~/.config/gh/config.yml` |
| [`home/.config/git/config`](home/.config/git/config) | `~/.config/git/config` |
| [`home/.config/git/ignore`](home/.config/git/ignore) | `~/.config/git/ignore` |
| [`home/.config/mdt/config.toml`](home/.config/mdt/config.toml) | `~/.config/mdt/config.toml` |

## 配置

Git 配置会加载 `~/.gitconfig.local`，请把身份信息写在那里。运行 `gh auth login` 登录 GitHub CLI。fastfetch 使用 Kitty 图片协议，请选择兼容终端或修改图片配置。
