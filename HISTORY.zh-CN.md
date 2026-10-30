# 配置演变

[English](HISTORY.md) | [简体中文](HISTORY.zh-CN.md)

## 桌面与终端

### 2026-02

从 xrce/dots 起步，参考 kitty、Neovim 与 sketchybar 配置。窗口管理从 LOOP 换到 yabai。

### 之后几个月

Raycast 取代 Spotlight。Warp 的 Agent、补全与文件侧栏很方便，但崩溃和 AI 功能不可用让我换到 kitty 与 Neovim。Ghostty 吸引我的是速度与 GPU 渲染。cmux 加入工作区与通知，我也重新体验了 Warp，用 tmux 查看 Agent 进度。

### 2026-07

使用 Ghostty 与 Paneru，持续调整 sketchybar。终端窗口过多带来卡顿，Paneru 宕机后还要重排窗口，因此用 Herdr 把终端任务放进一个工作区。

### 2026-08

试用 Omarchy 后保留原有环境，借用了 caffeinate 的做法。引入 omacosy，让状态栏、壁纸、Ghostty 与边框同步主题，并把 Caps Lock 用作 Super。

### 2026-09

把 dooit 与 Yazi 放进终端工作区。Ghostty 已配置完善，因此没有换到 Kaku。

### 2026-10

把本地音乐播放搬进终端以避开广告，使用 rmpc 与 MPD。为了在终端 Agent 工作之外使用 GUI 能力，开始体验 Tern。加入 FreshRSS，同时用作订阅后端与阅读器。

## AI Agent 与工作流

### 之后几个月

先用 OpenCode 与 GitHub Copilot，再尝试 Claude Code 和多种接入方式。Everything Claude Code 缺少我想要的成体系构建规范。Superpowers 提供了流程，但 OpenCode 没有稳定主动调用技能。GSD 的阶段划分与原子提交更适合长期维护的个人项目。

### 2026-04

体验 Codex 并迁移 OpenCode 配置，也尝试了 Hermes 与不同模型服务。笔记没有记录停止使用 Hermes 的原因。

### 2026-06

开始用 Pi 做调研、实验与记忆扩展。相较 Claude Code，更轻的系统提示词与上下文是吸引我的地方。mem0.ts 是早期记忆扩展。

### 2026-07

建立 grilling → scaffold → implement → review 工作流。引入 firstmate，使用 worktree 隔离任务，并只与一个主 Agent 对话。记忆系统因无差别收集过多而加入门禁，之后重点提取我对 Agent 的纠正。

### 2026-08

删除自动原子提交插件，因为静默提交反而造成阻碍。继续尝试不同模型分别负责计划、审查与执行。

### 2026-09

转向 omp，看中原生模型接入与方便的账户轮换。除 Kami 外，采纳 Waza 的写作与调研技能。

### 2026-10

加入 caveman 风格的简洁输出规则，以及由反馈驱动的技能改进流程。并行任务减少后，新会话与较低缓存复用不再划算，因此暂停 firstmate 派工，保留记忆与项目管理。记忆实验在自建后端与 omp 后端之间切换，之后加入查看、编辑与删除。上下文压缩转向 handoff，在降低长上下文传输负担的同时保留决策及原因。

## 浏览器

### 之后几个月

因 Zen 的扩展生态不足转到 Firefox，又因标签页管理回到 Zen。Tabbit 因卡顿与崩溃被放弃。

### 2026-07

浏览器 Agent 实验的开发时间、执行时间与心智负担加在一起，不如手动操作。

### 2026-09

留意到 Chrome 的垂直标签页，继续比较浏览器工作流。

### 2026-10

浏览器 Agent 从操作用户 Chrome 会话改为使用 ego lite。

## 笔记：Obsidian 到 Logseq

### 2026-07

从 Obsidian 转到 Logseq，记录了明确的喜爱，并搭建自托管同步。笔记没有记录离开 Obsidian 的具体原因。

### 之后几个月

编写 logseq-db-banner、logseq-journal-time-prefix、logseq-d2 与 logseq-cloudflare-sync。

### 2026-10

关闭原有 Logseq 云同步以减少代理流量。
