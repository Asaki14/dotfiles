# omp

[English](README.md) | [简体中文](README.zh-CN.md)

编程助手配置与扩展。

## 安装

```bash
./install.sh --modules omp
```

在仓库根目录运行。本模块不通过 Homebrew 安装软件。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.omp/agent/AGENTS.md`](home/.omp/agent/AGENTS.md) | `~/.omp/agent/AGENTS.md` |
| [`home/.omp/agent/config.yml`](home/.omp/agent/config.yml) | `~/.omp/agent/config.yml` |
| [`home/.omp/agent/derive-status-theme.mjs`](home/.omp/agent/derive-status-theme.mjs) | `~/.omp/agent/derive-status-theme.mjs` |
| [`home/.omp/agent/extensions/caveman.ts`](home/.omp/agent/extensions/caveman.ts) | `~/.omp/agent/extensions/caveman.ts` |
| [`home/.omp/agent/extensions/turn-notify.ts`](home/.omp/agent/extensions/turn-notify.ts) | `~/.omp/agent/extensions/turn-notify.ts` |
| [`home/.omp/agent/themes/dark-tokyo-night-status.json`](home/.omp/agent/themes/dark-tokyo-night-status.json) | `~/.omp/agent/themes/dark-tokyo-night-status.json` |
| [`home/.omp/agent/themes/light-catppuccin-status.json`](home/.omp/agent/themes/light-catppuccin-status.json) | `~/.omp/agent/themes/light-catppuccin-status.json` |

## 配置

请单独安装 [oh-my-pi](https://github.com/can1357/oh-my-pi) 并登录模型服务。启动 Agent 前检查 `config.yml` 的模型 ID 与 `approvalMode: yolo`，此模式允许工具执行时跳过常规审批提示。模块包含 `AGENTS.md`、两套状态栏主题、`derive-status-theme.mjs`、`caveman.ts` 与 `turn-notify.ts`。主题生成需要 Node.js。通知扩展使用 macOS 通知。可选记忆界面：[Asaki14/omp-mnemopi-memory](https://github.com/Asaki14/omp-mnemopi-memory)。
