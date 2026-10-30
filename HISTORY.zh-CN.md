# 配置演变

[English](HISTORY.md) | [简体中文](HISTORY.zh-CN.md)

## 桌面与终端

### 2026-02

从 xrce/dots 起步，参考 kitty、Neovim 与 sketchybar 配置。窗口管理从 LOOP 换到 yabai。

### 之后几个月

Raycast 取代 Spotlight。Warp 的 Agent、补全与文件侧栏很方便，但崩溃和 AI 功能不可用让我换到 kitty 与 Neovim。Ghostty 吸引我的是速度与 GPU 渲染。cmux 加入工作区与通知，我也重新体验了 Warp，用 tmux 查看 Agent 进度。

Raycast 装了 Obsidian、KillProcess、Warp 和 Zen 扩展，用来速记、结束进程和打开终端或浏览器。Apple Music 扩展因键盘和 BoringNotch 已能控制播放而卸载。fish 配合 fzf 搜索目录、历史和变量。音乐播放器试过 nuclear，但网络波动造成卡顿与暂停；LX 播放器无需代理，代价是找歌时可能需要切换音源。

### 2026-07

使用 Ghostty 与 Paneru，持续调整 sketchybar。终端窗口过多带来卡顿，Paneru 宕机后还要重排窗口，因此用 Herdr 把终端任务放进一个工作区。

加入 codexbar，在菜单栏查看 AI 工具用量，不必反复打开设置或输入 /usage。删除 AlDente，改用 macOS 原生优化电池充电。

### 2026-08

试用 Omarchy 后保留原有环境，借用了 caffeinate 的做法。引入 omacosy，让状态栏、壁纸、Ghostty 与边框同步主题，并把 Caps Lock 用作 Super。

试用 FluidVoice 的听写与 Command 模式，但识别准确度、环境音下的稳定性和资源占用不及 AutoGLM。

### 2026-09

把 dooit 与 Yazi 放进终端工作区。Ghostty 已配置完善，因此没有换到 Kaku。

已有 Mole，并因喜欢 Mole 和 Kami 而继续查看 tw93 的项目。dooit 的极简任务管理、Vim 键位和自动跟随 omacosy 换主题符合我的使用习惯，但中英文输入切换仍有摩擦。试用 lap 管理本地照片和视频，看中时间轴、多视图、评分与标记。

### 2026-10

把本地音乐播放搬进终端以避开广告，使用 rmpc 与 MPD。为了在终端 Agent 工作之外使用 GUI 能力，开始体验 Tern。加入 FreshRSS，同时用作订阅后端与阅读器。

用 newsboat 自动更新 RSS，再配合 md-tui 阅读，不必逐个打开源网页。通过 Tailscale 探索 iPad 远程访问 Tern，当时只能远程放歌，RSS 与 omp 操作仍不实用。更新 Mousecape 光标主题。

## AI Agent 与工作流

### 之后几个月

先用 OpenCode 与 GitHub Copilot，再尝试 Claude Code 和多种接入方式。Everything Claude Code 缺少我想要的成体系构建规范。Superpowers 提供了流程，但 OpenCode 没有稳定主动调用技能。GSD 的阶段划分与原子提交更适合长期维护的个人项目。

试过 copilot-api、LiteLLM 与 CC Switch，把 Copilot 接到 Claude Code。CC Switch 配置更方便，但模型兼容和额度消耗仍有限制。DeepSeek API 成功驱动 Claude Code。Gemini CLI 解决代理配置后仍反应不稳定，因此放弃。Open Design 配合 Claude Code 的模板执行效果一般，换成 Pi 后速度、指令遵循和视觉效果更合适；也用 Qwen-3.5-plus 生成过个人网站的新风格。lightpanda 配好后不适合测试我的网站，openspace 的 MCP 接入失败。

### 2026-04

体验 Codex 并迁移 OpenCode 配置，也尝试了 Hermes 与不同模型服务。笔记没有记录停止使用 Hermes 的原因。

### 无日期记录

通过 OpenCode Go 试用 Kimi-k2.6、Qwen-3.5-plus 与 DeepSeek-v4。Kimi 完成了批量文献处理与 Obsidian 笔记修改；Hermes 先试 nemotron，再比较 Qwen 与响应更快、上下文更长的 DeepSeek。

仍主用 Claude Code，偶尔用 Cowork 做小任务：GUI 与沙箱不错，但不共享 CLI 配置，也不支持同样的 subagent 与模型切换流程。Codex computer use 完成过浏览器驱动的部署调整；Record&Replay 更精准地识别界面组件，但消耗较大，尚无固定使用场景。试用 huashu-design，视觉效果不错。

### 2026-06

开始用 Pi 做调研、实验与记忆扩展。相较 Claude Code，更轻的系统提示词与上下文是吸引我的地方。mem0.ts 是早期记忆扩展。

### 无日期记录

扩展了 questionnaire、pi-subagents-local、Exa、Firecrawl、hashline-editing 与 pi-station，把提问、派工、联网、编辑和终端界面按自己的需求拆开配置。通知与技能激活状态也做成小扩展。

### 2026-07

建立 grilling → scaffold → implement → review 工作流。引入 firstmate，使用 worktree 隔离任务，并只与一个主 Agent 对话。记忆系统因无差别收集过多而加入门禁，之后重点提取我对 Agent 的纠正。

从 GitHub Trending 发现 Herdr；从《跨国串门计划》发现 firstmate。

### 2026-08

删除自动原子提交插件，因为静默提交反而造成阻碍。继续尝试不同模型分别负责计划、审查与执行。

把 firstmate 的工人从 Herdr 独立 tab 改为同一 tab 的 pane，方便同时观察任务。加入 Agent pane 自动切中文、其他 pane 默认英文的输入法切换。

### 2026-09

转向 omp，看中原生模型接入与方便的账户轮换。除 Kami 外，采纳 Waza 的写作与调研技能。

### 2026-10

加入 caveman 风格的简洁输出规则，以及由反馈驱动的技能改进流程。并行任务减少后，新会话与较低缓存复用不再划算，因此暂停 firstmate 派工，保留记忆与项目管理。记忆实验在自建后端与 omp 后端之间切换，之后加入查看、编辑与删除。上下文压缩转向 handoff，在降低长上下文传输负担的同时保留决策及原因。

试用 OpenAI dots 的云端电脑与持久运行方式。尝试按量付费的 OpenCode Zen，速度和效果不错，但单个任务的消耗让我放弃长期使用。移除 Prewalk 后观察到缓存命中率改善。

## 浏览器

### 之后几个月

因 Zen 的扩展生态不足转到 Firefox，又因标签页管理回到 Zen。Tabbit 因卡顿与崩溃被放弃。

通过 Sine 安装 Nebula，搭配 Zen Internet 做透明网页。透明背景影响阅读，于是加入 Darkreader 调整亮度和对比度。Vimium 提供键盘导航、点击与关页。

### 2026-07

浏览器 Agent 实验的开发时间、执行时间与心智负担加在一起，不如手动操作。

### 2026-09

留意到 Chrome 的垂直标签页，继续比较浏览器工作流。

发现 Chrome 阅读模式，阅读时更舒服。

### 2026-10

浏览器 Agent 从操作用户 Chrome 会话改为使用 ego lite。

## 笔记：Obsidian 到 Logseq

### 无日期记录

在 Obsidian 中通过 BRAT 安装 Phycat，喜欢它的列表定位、标题层级和表格样式；也记录了 Style Settings 的定制入口。

### 2026-07

从 Obsidian 转到 Logseq。日记式随手记录、tag 聚合同主题内容和跟手的任务管理更适合我，避免一篇笔记写完后再无更新。同步先尝试 Git for Logseq 与 gitseq，之后搭建自托管同步。

试用 banner-plugin，显示日历、番茄钟和 quote；天气已有 sketchybar，不再重复。加入 Awesome-UI、Awesome-links 与 Agenda，分别调整界面、链接图标和任务视图。Logseq-graph-analysis 与内置图谱重复，因此移除。主题试过 Bujo 的 sepia/coffee 与 Laurel。

### 之后几个月

编写 logseq-db-banner、logseq-journal-time-prefix、logseq-d2 与 logseq-cloudflare-sync。

### 2026-10

关闭原有 Logseq 云同步以减少代理流量。

重启后主题丢失，发现默认配色也很好看，直接保留。
