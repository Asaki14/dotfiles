# omp

[English](README.md) | [简体中文](README.zh-CN.md)

Coding agent settings and extensions.

## Install

```bash
./install.sh --modules omp
```

Run from the repository root. No Homebrew packages are installed by this module.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.omp/agent/AGENTS.md`](home/.omp/agent/AGENTS.md) | `~/.omp/agent/AGENTS.md` |
| [`home/.omp/agent/config.yml`](home/.omp/agent/config.yml) | `~/.omp/agent/config.yml` |
| [`home/.omp/agent/derive-status-theme.mjs`](home/.omp/agent/derive-status-theme.mjs) | `~/.omp/agent/derive-status-theme.mjs` |
| [`home/.omp/agent/extensions/caveman.ts`](home/.omp/agent/extensions/caveman.ts) | `~/.omp/agent/extensions/caveman.ts` |
| [`home/.omp/agent/extensions/turn-notify.ts`](home/.omp/agent/extensions/turn-notify.ts) | `~/.omp/agent/extensions/turn-notify.ts` |
| [`home/.omp/agent/themes/dark-tokyo-night-status.json`](home/.omp/agent/themes/dark-tokyo-night-status.json) | `~/.omp/agent/themes/dark-tokyo-night-status.json` |
| [`home/.omp/agent/themes/light-catppuccin-status.json`](home/.omp/agent/themes/light-catppuccin-status.json) | `~/.omp/agent/themes/light-catppuccin-status.json` |

## Setup

Install [oh-my-pi](https://github.com/can1357/oh-my-pi) separately and authenticate your providers. Review model IDs and `approvalMode: yolo` in `config.yml` before starting an agent; this approval mode allows tool execution without normal approval prompts. The module includes `AGENTS.md`, two status themes, `derive-status-theme.mjs`, `caveman.ts` and `turn-notify.ts`. Theme derivation needs Node.js. The notification extension uses macOS notifications. Optional memory UI: [Asaki14/omp-mnemopi-memory](https://github.com/Asaki14/omp-mnemopi-memory).
