#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Toggle Appearance
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# @raycast.icon 🌗
# @raycast.description 切换 macOS 深色 / 浅色外观。首次运行 Raycast 会申请「自动化 → 系统事件」权限。

set -euo pipefail

osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'
mode=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
[ "$mode" = "true" ] && echo "Dark mode" || echo "Light mode"
