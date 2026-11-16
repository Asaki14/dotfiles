#!/usr/bin/env bash
# System-level tweaks for the omarchy look. uninstall.sh reverses these.

set -euo pipefail

# Record each key's PRE-omacosy value (type + value, ABSENT if unset)
# into the install manifest, once — uninstall.sh restores exactly that
# instead of guessing Apple's defaults.
MANIFEST="${MANIFEST:-$HOME/.local/state/omacosy/manifest}"
mkdir -p "$(dirname "$MANIFEST")"
touch "$MANIFEST"
record_default() { # domain key
  grep -q "^default $1 $2 " "$MANIFEST" && return 0
  local t v
  if v="$(defaults read "$1" "$2" 2>/dev/null)"; then
    t="$(defaults read-type "$1" "$2" 2>/dev/null | awk '{print $3}')"
    printf 'default %s %s %s %s\n' "$1" "$2" "${t:-string}" "$v" >> "$MANIFEST"
  else
    printf 'default %s %s ABSENT ABSENT\n' "$1" "$2" >> "$MANIFEST"
  fi
}
record_default NSGlobalDomain _HIHideMenuBar
record_default NSGlobalDomain SLSMenuBarUseBlurredAppearance
record_default com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture
record_default com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture
record_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture
record_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture
record_default com.apple.dock showMissionControlGestureEnabled

# One bar, not two: auto-hide the native menu bar (sketchybar takes the top).
# cfprefsd must be killed so the OS re-reads the pref without a logout.
defaults write NSGlobalDomain _HIHideMenuBar -bool true
# "Show menu bar background": Tahoe (26.0-26.2+, unfixed) sometimes
# reveals the auto-hidden menu bar WITHOUT its glass material — text
# soup over whatever sits in the strip. An opaque background keeps
# even a wedged reveal readable. killall SystemUIServer resets a
# wedge; a Focus mode's menu-bar item is one known trigger.
defaults write NSGlobalDomain SLSMenuBarUseBlurredAppearance -bool true
killall cfprefsd 2>/dev/null || true
sleep 1
killall SystemUIServer 2>/dev/null || true

echo "macos-defaults: menu bar set to auto-hide (log out/in if it doesn't apply immediately)"

# The 4-finger swipes belong to omacosy-gesture (workspaces + the
# omacosy overview). Left enabled, the SYSTEM claims the same gesture
# for Mission Control / Spaces — and it does not have to SHOW Mission
# Control to break things: the Dock takes the window-server input grab
# the moment four fingers land, and keeps it, so the overview draws
# perfectly while every keystroke and card click goes to the Dock. (SCK
# captures also catch windows mid-MC-zoom.) Trackpad -> More Gestures
# equivalents: off.
# Writing the keys is NOT enough, and the "Dock restart applies" this
# block used to only PROMISE is the whole point: the Dock keeps its
# gesture recognizers in memory and re-reads them when it relaunches.
# Measured on a live install 2026-08-31 — every key below already read
# 0/false while the running Dock still claimed the four-finger swipe up
# for Mission Control. So `defaults read` gives a false all-clear, and
# the Dock GRABS window-server input: the overview's keystrokes and card
# clicks arrive at the session event tap addressed to the overview and
# leave the annotated tap addressed to the Dock, which swallows them —
# the overlay renders perfectly and does nothing. uninstall.sh has
# always bounced the Dock after restoring these; the install side never
# did, so on any machine installed before this fix the keys look right
# and the gesture is still live.
#
# Only bounce it when something actually changed: install.sh is re-run
# to rebuild helpers and a Dock restart every time would be obnoxious.
# The marker is what covers those pre-fix installs, where the keys are
# already 0 but the running Dock was never told.
gesture_changed=0
note_change() { # domain key want
  [ "$(defaults read "$1" "$2" 2>/dev/null || true)" = "$3" ] || gesture_changed=1
}
note_change com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture 0
note_change com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture 0
note_change com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture 0
note_change com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture 0
note_change com.apple.dock showMissionControlGestureEnabled 0

defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture -int 0 2>/dev/null || true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture -int 0 2>/dev/null || true
defaults write com.apple.dock showMissionControlGestureEnabled -bool false

if [ "$gesture_changed" = 1 ] || ! grep -qxF 'gestures-applied' "$MANIFEST"; then
  killall cfprefsd 2>/dev/null || true
  sleep 1
  killall Dock 2>/dev/null || true
  printf 'gestures-applied\n' >> "$MANIFEST"
  echo "macos-defaults: 4-finger swipes released to omacosy-gesture (Dock restarted to apply)"
else
  echo "macos-defaults: 4-finger swipes already released to omacosy-gesture"
fi
