# music

[English](README.md) | [简体中文](README.zh-CN.md)

本地音乐库与播放。

## 安装

```bash
./install.sh --modules music
```

在仓库根目录运行。Homebrew 依赖：`mpd`、`rmpc`、`beets`、`cava`。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/beets/config.yaml`](home/.config/beets/config.yaml) | `~/.config/beets/config.yaml` |
| [`home/.config/mpd/mpd.conf`](home/.config/mpd/mpd.conf) | `~/.config/mpd/mpd.conf` |
| [`home/.config/mpd/nowplaying/Info.plist`](home/.config/mpd/nowplaying/Info.plist) | `~/.config/mpd/nowplaying/Info.plist` |
| [`home/.config/mpd/nowplaying/fun.asaki.mpd-nowplaying.plist`](home/.config/mpd/nowplaying/fun.asaki.mpd-nowplaying.plist) | `~/.config/mpd/nowplaying/fun.asaki.mpd-nowplaying.plist` |
| [`home/.config/mpd/nowplaying/install.sh`](home/.config/mpd/nowplaying/install.sh) | `~/.config/mpd/nowplaying/install.sh` |
| [`home/.config/mpd/nowplaying/mpd-nowplaying.swift`](home/.config/mpd/nowplaying/mpd-nowplaying.swift) | `~/.config/mpd/nowplaying/mpd-nowplaying.swift` |
| [`home/.config/mpd/playlist-sync`](home/.config/mpd/playlist-sync) | `~/.config/mpd/playlist-sync` |
| [`home/.config/mpd/playlists/example.m3u`](home/.config/mpd/playlists/example.m3u) | `~/.config/mpd/playlists/example.m3u` |
| [`home/.config/rmpc/config.ron`](home/.config/rmpc/config.ron) | `~/.config/rmpc/config.ron` |

## 配置

曲库位于 `~/Music/lib`，beets 导入时会把文件移动到这里。导入前请检查路径。创建 `~/Music/lib`、`~/.local/share/mpd/playlists` 与 `~/.local/share/beets`，运行 `mpd ~/.config/mpd/mpd.conf` 启动 MPD，然后打开 `rmpc`。安装器不启动服务。如需 macOS 媒体键与正在播放集成，安装 Apple Command Line Tools 后运行 `sh ~/.config/mpd/nowplaying/install.sh`，它会编译辅助程序并加载 LaunchAgent。仓库只包含空的示例歌单。
