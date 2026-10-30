# music

[English](README.md) | [简体中文](README.zh-CN.md)

Local music library and playback.

## Install

```bash
./install.sh --modules music
```

Run from the repository root. Homebrew packages: `mpd`, `rmpc`, `beets`, `cava`.

## Files and destinations

| Source | Destination |
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

## Setup

The library is `~/Music/lib`; beets moves imported files into it. Review paths before importing. Create `~/Music/lib`, `~/.local/share/mpd/playlists` and `~/.local/share/beets`, then start MPD with `mpd ~/.config/mpd/mpd.conf` and open `rmpc`. The installer does not start services. For macOS media keys and Now Playing integration, install Apple Command Line Tools and run `sh ~/.config/mpd/nowplaying/install.sh`; it compiles a helper and loads a LaunchAgent. Only an empty example playlist is included.
