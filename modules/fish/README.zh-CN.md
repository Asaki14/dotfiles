# fish

[English](README.md) | [简体中文](README.zh-CN.md)

交互式 Shell 与快捷命令。

## 安装

```bash
./install.sh --modules fish
```

在仓库根目录运行。Homebrew 依赖：`fish`。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/fish/completions/fisher.fish`](home/.config/fish/completions/fisher.fish) | `~/.config/fish/completions/fisher.fish` |
| [`home/.config/fish/conf.d/chrome-devtools-axi.fish`](home/.config/fish/conf.d/chrome-devtools-axi.fish) | `~/.config/fish/conf.d/chrome-devtools-axi.fish` |
| [`home/.config/fish/conf.d/clojure-paths.fish`](home/.config/fish/conf.d/clojure-paths.fish) | `~/.config/fish/conf.d/clojure-paths.fish` |
| [`home/.config/fish/conf.d/locale.fish`](home/.config/fish/conf.d/locale.fish) | `~/.config/fish/conf.d/locale.fish` |
| [`home/.config/fish/config.fish`](home/.config/fish/config.fish) | `~/.config/fish/config.fish` |
| [`home/.config/fish/fish_plugins`](home/.config/fish/fish_plugins) | `~/.config/fish/fish_plugins` |
| [`home/.config/fish/functions/fisher.fish`](home/.config/fish/functions/fisher.fish) | `~/.config/fish/functions/fisher.fish` |
| [`home/.config/fish/functions/ytm.fish`](home/.config/fish/functions/ytm.fish) | `~/.config/fish/functions/ytm.fish` |

## 配置

使用 `proxy` 前设置 `DOTFILES_PROXY_PORT`，`noproxy` 清除代理环境变量。密钥放在 `~/.config/fish/conf.d/api_keys.local.fish`。可选快捷命令的工具需自行安装：`y` 需要 Yazi，`ft` 需要 fastfetch 与 cli 模块，`ytm` 需要 yt-dlp、ffmpeg 与 Chrome cookies。`cc` 别名启用 Claude Code 的权限绕过选项，使用前请检查。运行 `fisher update` 安装 `fish_plugins` 中的插件。本模块不更改登录 Shell。
