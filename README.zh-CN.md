<div align="center">
  <h1>Dotfiles</h1>
  <p><b>一套 macOS 桌面、终端与 AI Agent 配置。</b></p>
  <p><a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a></p>
</div>

- 按工具拆分，支持单独安装
- omacosy 联动桌面与终端主题
- omp 配置、自研扩展与技能

## 模块

| 模块 | 作用 | 主要工具 |
|---|---|---|
| [omacosy](modules/omacosy/README.zh-CN.md) | 桌面与主题系统 | omacosy, Ghostty, AeroSpace, Karabiner |
| [fish](modules/fish/README.zh-CN.md) | 交互式 Shell 与快捷命令 | fish, Fisher |
| [nvim](modules/nvim/README.zh-CN.md) | 编辑、搜索与补全 | Neovim, lazy.nvim, Telescope |
| [yazi](modules/yazi/README.zh-CN.md) | 文件管理与预览 | Yazi, smart-enter, compress |
| [cli](modules/cli/README.zh-CN.md) | 日常命令行工具 | git, btop, fastfetch, gh, md-tui |
| [linearmouse](modules/linearmouse/README.zh-CN.md) | 鼠标配置 | LinearMouse |
| [music](modules/music/README.zh-CN.md) | 本地音乐库与播放 | MPD, rmpc, beets, cava |
| [tern](modules/tern/README.zh-CN.md) | 终端输入法切换策略 | Tern, Swift, Luau |
| [freshrss](modules/freshrss/README.zh-CN.md) | RSS 阅读与中文翻译 | FreshRSS, Docker, omp |
| [raycast](modules/raycast/README.zh-CN.md) | 系统脚本命令 | Raycast |
| [codexbar](modules/codexbar/README.zh-CN.md) | 菜单栏 AI 账户用量 | CodexBar |
| [omp](modules/omp/README.zh-CN.md) | 编程助手配置与扩展 | oh-my-pi |
| [skills](modules/skills/README.zh-CN.md) | 项目结构与技能改进 | project-scaffold, skill-improve |

## 安装

需要 macOS、Git 与 Homebrew。先阅读下方安装前须知。

```bash
git clone https://github.com/Asaki14/dotfiles.git
cd dotfiles
./install.sh
```

通过 fzf 多选，未安装 fzf 时使用编号菜单。

```bash
./install.sh --list
./install.sh --all
./install.sh --modules fish,nvim,yazi
./install.sh --modules fish,nvim --dry-run
./install.sh --modules fish,nvim --no-brew
```

`--modules` 会安装所选模块的依赖模块。`--dry-run` 只打印操作，不安装软件或写文件。`--no-brew` 跳过全部 Homebrew 操作，包括 omacosy 上游调用，依赖软件需已安装。

`home/` 内文件逐个软链到 `$HOME`，现有冲突文件移到 `~/.dotfiles-backup/<timestamp>-<pid>/`。保留仓库目录，移动它会使软链失效。omacosy 还会运行上游安装脚本，见下方。

## 安装前须知

- omacosy 会修改 macOS defaults、加载 LaunchAgents、编译辅助程序并设置壁纸，还会覆盖桌面配置。文件备份不能还原这些系统设置。先读 [omacosy 模块](modules/omacosy/README.zh-CN.md)。
- [Tern](https://stencil.so/tern) 处于封闭内测，需自行安装。[omp](https://github.com/can1357/oh-my-pi) 也需自行安装并登录模型服务。
- omp 配置启用 `approvalMode: yolo`，fish 的 `cc` 别名启用权限绕过。使用前按自己的审批要求修改。
- FreshRSS 扩展要求创建名为 `reader` 的账户。初始化与后台处理见 [FreshRSS 模块](modules/freshrss/README.zh-CN.md)。
- 天气位置通过 `OMACOSY_WEATHER_LOCATION`、`OMACOSY_WEATHER_LAT`、`OMACOSY_WEATHER_LON` 配置，需要传入天气进程环境。
- Git 身份写入 `~/.gitconfig.local`，不写进仓库：

```gitconfig
[user]
    name = Your Name
    email = you@example.com
```

## 使用

修改各模块中链接的配置文件，操作入口见模块 README。[配置演变](HISTORY.zh-CN.md)记录桌面、AI Agent、浏览器与笔记的选择。

## 致谢

- [xrce/dots](https://github.com/xrce/dots)，2026 年 2 月的起点。
- [paulsp94/omacosy](https://github.com/paulsp94/omacosy)，Paul Spende 编写的桌面与主题基础，MIT 许可。安装器保留上游 checkout 与许可证。
- [tw93/Waza](https://github.com/tw93/Waza) 与 [tw93/Kami](https://github.com/tw93/Kami)，工程与文档技能。
- [mattpocock/skills](https://github.com/mattpocock/skills)，grilling 与技能编写参考。
- [zenbu-labs/terminal-browser](https://github.com/zenbu-labs/terminal-browser)，浏览器技能。
- [lennney/stop-that-shit](https://github.com/lennney/stop-that-shit)，约束 Agent 任务范围。
- [Asaki14/omp-mnemopi-memory](https://github.com/Asaki14/omp-mnemopi-memory)，我单独维护的记忆扩展。
- [Raycast 扩展作者](modules/raycast/README.zh-CN.md)与 [Yazi 插件作者](modules/yazi/README.zh-CN.md)。

## License

[MIT](LICENSE)。omacosy 上游代码继续适用其 MIT 许可证，第三方工具与插件保留各自许可证。
