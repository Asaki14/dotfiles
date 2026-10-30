# yazi

[English](README.md) | [简体中文](README.zh-CN.md)

文件管理与预览。

## 安装

```bash
./install.sh --modules yazi
```

在仓库根目录运行。Homebrew 依赖：`yazi`、`ffmpeg`、`sevenzip`、`poppler`、`fd`、`ripgrep`、`fzf`、`zoxide`、`imagemagick`、`resvg`。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/yazi/keymap.toml`](home/.config/yazi/keymap.toml) | `~/.config/yazi/keymap.toml` |
| [`home/.config/yazi/theme.toml`](home/.config/yazi/theme.toml) | `~/.config/yazi/theme.toml` |
| [`home/.config/yazi/yazi.toml`](home/.config/yazi/yazi.toml) | `~/.config/yazi/yazi.toml` |

## 配置

安装器用 `ya pkg` 添加 smart-enter 与 compress。Enter 打开文件或目录，`e` 打开 Neovim，`c p` 复制路径，`c a` 压缩选中项。请安装 nvim 模块或修改打开方式。配置中的 `omacosy` 配色由 omacosy 模块生成，请安装它或在 `theme.toml` 中改用其他配色。

- [smart-enter (yazi-rs)](https://github.com/yazi-rs/plugins/tree/main/smart-enter.yazi)
- [compress (KKV9)](https://github.com/KKV9/compress.yazi)
