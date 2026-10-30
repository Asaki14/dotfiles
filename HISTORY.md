# History

[English](HISTORY.md) | [简体中文](HISTORY.zh-CN.md)

## Desktop and terminal

### 2026-02

Started from xrce/dots, learning from its kitty, Neovim and sketchybar setup. yabai replaced LOOP for window management.

### Over the following months

Raycast replaced Spotlight. Warp was useful for its agent, completion and file sidebar, but crashes and unavailable AI features led to kitty with Neovim. Ghostty appealed for its speed and GPU rendering. cmux added workspaces and notifications; I also revisited Warp and used tmux to watch agent progress.

### 2026-07

Used Ghostty with Paneru and kept refining sketchybar. Too many terminal windows caused lag, and Paneru failures meant rearranging windows. Herdr brought those terminal tasks into one workspace.

### 2026-08

Tried Omarchy but kept the existing setup, borrowing its caffeinate idea. Adopted omacosy for coordinated bar, wallpaper, Ghostty and border themes, plus Caps Lock as Super.

### 2026-09

Brought dooit and Yazi into the terminal workspace. Kept the already configured Ghostty instead of moving to Kaku.

### 2026-10

Moved local music playback into the terminal to avoid ads, using rmpc with MPD. Tried Tern because I wanted GUI capabilities alongside terminal agent work. Added FreshRSS as both feed backend and reader.

## AI agents and workflow

### Over the following months

Used OpenCode with GitHub Copilot, then explored Claude Code and several integrations. Everything Claude Code lacked the coherent build rules I wanted. Superpowers added structure, but skills were not consistently invoked in OpenCode. GSD fit longer-lived personal projects through phases and atomic commits.

### 2026-04

Tried Codex and migrated OpenCode configuration. Also explored Hermes and different model providers; the notes do not establish why I stopped using Hermes.

### 2026-06

Started using Pi for research, experiments and memory extensions. Its lighter system prompt and context were the attraction after Claude Code. mem0.ts was an early memory extension.

### 2026-07

Built a grilling → scaffold → implement → review workflow. Adopted firstmate for worktree isolation and a single main-agent conversation. Added memory gates because indiscriminate storage collected too much; later focused extraction on my corrections to the agent.

### 2026-08

Removed an automatic atomic-commit plugin because silent commits got in the way. Continued trying different planning, review and execution model combinations.

### 2026-09

Moved to omp for native model access and convenient account rotation. Adopted Waza’s writing and research skills alongside Kami.

### 2026-10

Added caveman-style concise output rules and a feedback-driven skill-improvement loop. Paused firstmate task dispatch as less parallel work made fresh sessions and poor cache reuse less worthwhile; kept its memory and project management. Memory experiments alternated between a custom backend and omp’s backend, then added viewing, editing and deletion. Adopted handoff-based context compaction to retain decisions and their reasons while reducing long-context transfer overhead.

## Browsers

### Over the following months

Moved from Zen to Firefox because Zen’s extension ecosystem felt insufficient, then returned to Zen for its tab management. Dropped Tabbit after lag and crashes.

### 2026-07

Browser-agent experiments were not worth the combined development time, execution time and mental overhead compared with doing the task manually.

### 2026-09

Noted Chrome’s vertical tabs while continuing to compare browser workflows.

### 2026-10

Switched browser-agent work from the user’s Chrome session to ego lite.

## Notes: Obsidian to Logseq

### 2026-07

Moved from Obsidian to Logseq and recorded a strong preference for it. Set up self-hosted synchronization. The notes do not record a specific reason for leaving Obsidian.

### Over the following months

Built logseq-db-banner, logseq-journal-time-prefix, logseq-d2 and logseq-cloudflare-sync.

### 2026-10

Turned off the existing Logseq cloud synchronization to reduce proxy traffic.
