<div align="center">
  <h1>dotfiles</h1>
  <p><b>一套 macOS <code>~/.config</code>：omarchy 风格的平铺桌面、本地音乐库和自托管新闻阅读器，一个 <code>install.sh</code> 装好。</b></p>
  <p><a href="README.md">English</a> · 中文</p>
  <img src="https://img.shields.io/badge/macOS-26_Tahoe-black?style=flat-square&logo=apple" alt="macOS 26">
  <a href="https://github.com/Asaki14/dotfiles/commits"><img src="https://img.shields.io/github/last-commit/Asaki14/dotfiles?style=flat-square" alt="Last commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Asaki14/dotfiles?style=flat-square" alt="License"></a>
</div>

## 功能

- **平铺桌面**：[omacosy](https://github.com/paulsp94/omacosy)（AeroSpace、原生状态栏、窗口边框、手势、主题）连同本配置的改动一起放在 `omacosy/src`
- **状态栏数据**：天气、AI 额度、同步歌词、网速和基金盘中估值
- **本地音乐**：beets 管理曲库，MPD 播放，rmpc 作播放器；Swift 桥接程序把 MPD 接入 macOS「正在播放」和媒体键
- **新闻阅读**：Docker 里的 FreshRSS，阅读扩展在后台翻译外文文章
- **终端与编辑器**：fish、Neovim（lazy.nvim）、带插件的 yazi、btop、fastfetch
- **输入法跟随窗格**：Tern 插件按终端窗格切换 macOS 输入法
- **系统操作**：锁屏、睡眠、切换外观和天气，做成 [Tinycast](https://tinycast.dev) 脚本命令

## 快速开始

```bash
git clone https://github.com/Asaki14/dotfiles.git ~/.config
cd ~/.config && ./install.sh
```

如果 `~/.config` 已存在，克隆到其他目录即可：`install.sh` 会把各配置目录链接进 `~/.config`，被替换的文件移到 `~/.dotfiles-backup/<时间>/`。

| 选项 | 作用 |
|---|---|
| `--modules yazi,fish` | 只装这些配置目录及其所需软件；列出 `omacosy` 时才装桌面 |
| `--dry-run` | 只打印每一步，不做改动 |
| `--no-brew` | 跳过 `Brewfile` 里的 Homebrew 软件 |
| `--no-desktop` | 跳过 omacosy 桌面（窗口管理、状态栏、主题） |
| `--no-network` | 不按 IP 地址查询所在城市 |

`install.sh` 把本机的值写进 gitignore 的文件，仓库本身不含任何个人值：

| 文件 | 来源 |
|---|---|
| `omacosy/bar-items.local.conf` | 已配对的 AirPods 或耳机，状态栏显示其电量 |
| `omacosy/scripts/location.local.json` | IP 地址所在城市（ip-api.com），用于天气 |
| `omacosy/scripts/fission_fund_wallet.json` | 从示例复制；填入基金代码和份额，或从 `bar-items.conf` 删掉 `fission-estimator` |

## 安装前须知

- [Tern](https://stencil.so/tern) 处于封闭内测，需自行安装。AI 额度和文章翻译依赖 [omp](https://github.com/can1357/oh-my-pi)，需自行安装并登录。
- FreshRSS 需手动部署，见 [freshrss/README.md](freshrss/README.md)。
- omacosy 安装器会修改 macOS defaults、加载 LaunchAgents、编译辅助程序、设置壁纸，并覆盖桌面配置。文件备份不能还原这些系统设置。先读 [omacosy/src/README.md](omacosy/src/README.md)，或加 `--no-desktop`。
- API key 写入 `fish/conf.d/api_keys.local.fish`，该文件已被 gitignore。

## 目录

| 路径 | 内容 |
|---|---|
| `omacosy/src/` | 桌面本体：状态栏、窗口管理配置、主题及其安装器；`UPSTREAM` 记录所基于的上游提交 |
| `omacosy/` | 状态栏布局（`bar-items.conf`）及数据脚本：天气、AI 用量、歌词、基金估值 |
| `fish/` `nvim/` `yazi/` `btop/` `fastfetch/` | Shell、编辑器、文件管理器和终端工具 |
| `mpd/` `rmpc/` `beets/` | 曲库、播放、歌单和「正在播放」桥接 |
| `freshrss/` | FreshRSS compose 文件、阅读扩展和翻译进程 |
| `tern/plugins/` `tinycast/scripts/` | Tern 终端插件和 Tinycast 系统命令 |
| `karabiner/` `linearmouse/` | 键盘和鼠标 |

因机器而异、但不会自动检测的路径：曲库（`mpd/mpd.conf` 和 `beets/config.yaml` 中的 `~/Music/lib`）和 `omp` 程序（`freshrss/reader-settings.json`）。

## 说明

- `AGENTS.md` 说明各部分之间的数据流。
- [HISTORY.zh-CN.md](HISTORY.zh-CN.md) 记录这套配置的演变。
- 以 [MIT](LICENSE) 许可发布。omacosy 的许可见 `omacosy/src/LICENSE`。
