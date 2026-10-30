# History

[English](HISTORY.md) | [简体中文](HISTORY.zh-CN.md)

## Desktop and terminal

### 2026-02

Started from xrce/dots, learning from its kitty, Neovim and sketchybar setup. yabai replaced LOOP for window management.

### Over the following months

Raycast replaced Spotlight. Warp was useful for its agent, completion and file sidebar, but crashes and unavailable AI features led to kitty with Neovim. Ghostty appealed for its speed and GPU rendering. cmux added workspaces and notifications; I also revisited Warp and used tmux to watch agent progress.

Raycast extensions included Obsidian, KillProcess, Warp and Zen for quick notes, ending processes and opening terminals or browser pages. Removed its Apple Music extension because the keyboard and BoringNotch already controlled playback. Used fzf in fish to search directories, history and variables. Tried nuclear for music, but network interruptions caused lag and pauses. LX Player needed no proxy, though finding songs could require switching sources.

### 2026-07

Used Ghostty with Paneru and kept refining sketchybar. Too many terminal windows caused lag, and Paneru failures meant rearranging windows. Herdr brought those terminal tasks into one workspace.

Added codexbar to check AI tool usage in the menu bar instead of reopening settings or typing /usage. Removed AlDente in favor of macOS optimized battery charging.

### 2026-08

Tried Omarchy but kept the existing setup, borrowing its caffeinate idea. Adopted omacosy for coordinated bar, wallpaper, Ghostty and border themes, plus Caps Lock as Super.

Tried FluidVoice dictation and Command mode, but recognition accuracy, stability with background noise and resource use compared poorly with AutoGLM.

### 2026-09

Brought dooit and Yazi into the terminal workspace. Kept the already configured Ghostty instead of moving to Kaku.

Already had Mole, and liking Mole and Kami led me to explore more of tw93's projects. dooit suited me with minimal task management, Vim keys and automatic omacosy theme switching, though switching Chinese and English input remained awkward. Tried lap for local photos and videos, appreciating its timeline, multiple views, ratings and flags.

### 2026-10

Moved local music playback into the terminal to avoid ads, using rmpc with MPD. Tried Tern because I wanted GUI capabilities alongside terminal agent work. Added FreshRSS as both feed backend and reader.

Used newsboat with md-tui for automatically updated RSS without opening each source website. Explored remote Tern access from an iPad through Tailscale; music playback worked, but RSS and omp interaction were not practical yet. Changed the Mousecape cursor theme.

## AI agents and workflow

### Over the following months

Used OpenCode with GitHub Copilot, then explored Claude Code and several integrations. Everything Claude Code lacked the coherent build rules I wanted. Superpowers added structure, but skills were not consistently invoked in OpenCode. GSD fit longer-lived personal projects through phases and atomic commits.

Tried copilot-api, LiteLLM and CC Switch to connect Copilot to Claude Code. CC Switch was easier to configure, but model compatibility and quota consumption remained limitations. Successfully ran Claude Code through the DeepSeek API. Dropped Gemini CLI after proxy configuration still left inconsistent responsiveness. Open Design followed templates poorly with Claude Code; Pi offered a better fit for speed, instruction following and visual results. Also used Qwen-3.5-plus to generate a new personal-site style. Configured lightpanda but found it unsuitable for testing my website; openspace's MCP integration failed.

### 2026-04

Tried Codex and migrated OpenCode configuration. Also explored Hermes and different model providers; the notes do not establish why I stopped using Hermes.

### Undated notes

Tried Kimi-k2.6, Qwen-3.5-plus and DeepSeek-v4 through OpenCode Go. Kimi handled batches of papers and Obsidian note edits. Tried nemotron with Hermes, then compared Qwen with DeepSeek's faster responses and longer context.

Kept Claude Code as the main tool and Cowork for occasional small tasks: Cowork's GUI and sandbox were useful, but it did not share CLI configuration or support the same subagent and model-switching workflow. Codex computer use handled browser-led deployment changes; Record&Replay recognized interface components more precisely, but consumed more tokens and had no recurring use case yet. Tried huashu-design with good visual results.

### 2026-06

Started using Pi for research, experiments and memory extensions. Its lighter system prompt and context were the attraction after Claude Code. mem0.ts was an early memory extension.

### Undated notes

Added questionnaire, pi-subagents-local, Exa, Firecrawl, hashline-editing and pi-station to configure questions, delegation, web access, editing and the terminal interface separately. Notifications and skill-activation status became small extensions too.

### 2026-07

Built a grilling → scaffold → implement → review workflow. Adopted firstmate for worktree isolation and a single main-agent conversation. Added memory gates because indiscriminate storage collected too much; later focused extraction on my corrections to the agent.

Found Herdr through GitHub Trending and firstmate through the podcast 跨国串门计划.

### 2026-08

Removed an automatic atomic-commit plugin because silent commits got in the way. Continued trying different planning, review and execution model combinations.

Moved firstmate workers from separate Herdr tabs into panes in one tab so their progress was visible together. Added input switching: Chinese in agent panes and English elsewhere.

### 2026-09

Moved to omp for native model access and convenient account rotation. Adopted Waza’s writing and research skills alongside Kami.

### 2026-10

Added caveman-style concise output rules and a feedback-driven skill-improvement loop. Paused firstmate task dispatch as less parallel work made fresh sessions and poor cache reuse less worthwhile; kept its memory and project management. Memory experiments alternated between a custom backend and omp’s backend, then added viewing, editing and deletion. Adopted handoff-based context compaction to retain decisions and their reasons while reducing long-context transfer overhead.

Tried OpenAI dots with its cloud computer and persistent runtime. Tried pay-as-you-go OpenCode Zen and liked its speed and results, but a single task's consumption ruled out long-term use. Observed better cache reuse after removing Prewalk.

## Browsers

### Over the following months

Moved from Zen to Firefox because Zen’s extension ecosystem felt insufficient, then returned to Zen for its tab management. Dropped Tabbit after lag and crashes.

Installed Nebula through Sine and used Zen Internet for transparent pages. Added Darkreader to adjust brightness and contrast when transparency hurt readability. Vimium supplied keyboard navigation, clicking and tab closing.

### 2026-07

Browser-agent experiments were not worth the combined development time, execution time and mental overhead compared with doing the task manually.

### 2026-09

Noted Chrome’s vertical tabs while continuing to compare browser workflows.

Discovered Chrome's reading mode and found it easier on the eyes.

### 2026-10

Switched browser-agent work from the user’s Chrome session to ego lite.

## Notes: Obsidian to Logseq

### Undated notes

Installed Phycat in Obsidian through BRAT and liked its list-position cues, heading hierarchy and table styling. Also recorded Style Settings as its customization entry point.

### 2026-07

Moved from Obsidian to Logseq. Quick journal entries, tags that gathered related material and responsive task management suited me better than notes that were written once and never updated. Tried Git for Logseq and gitseq before setting up self-hosted synchronization.

Tried banner-plugin for a calendar, Pomodoro timer and quotes; skipped weather because sketchybar already showed it. Added Awesome-UI, Awesome-links and Agenda for interface customization, link icons and task views. Removed Logseq-graph-analysis because the built-in graph already covered that need. Tried Bujo's sepia/coffee themes and Laurel.

### Over the following months

Built logseq-db-banner, logseq-journal-time-prefix, logseq-d2 and logseq-cloudflare-sync.

### 2026-10

Turned off the existing Logseq cloud synchronization to reduce proxy traffic.

When a restart lost the theme, I liked the default colors enough to keep them.
