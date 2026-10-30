#!/bin/sh
# Build mpd-nowplaying into ~/.local/bin and (re)load its launchd agent.
# Re-run after editing mpd-nowplaying.swift or Info.plist.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
label=fun.asaki.mpd-nowplaying
bin="$HOME/.local/bin/mpd-nowplaying"
agent="$HOME/Library/LaunchAgents/$label.plist"

mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
# the embedded Info.plist gives the process a bundle identifier; without one
# MediaRemote never lists it as a Now Playing source and media keys ignore it
swiftc -O -framework MediaPlayer -framework AppKit \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$here/Info.plist" \
  -o "$bin" "$here/mpd-nowplaying.swift"

sed "s#__HOME__#$HOME#g" "$here/$label.plist" > "$agent"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent"
launchctl kickstart -k "gui/$(id -u)/$label"
echo "$label running: $(launchctl print "gui/$(id -u)/$label" | awk '/pid =/{print $3}')"
