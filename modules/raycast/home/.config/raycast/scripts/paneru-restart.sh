#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Restart Paneru
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# @raycast.icon 🪟
# @raycast.description 重启 Paneru 平铺窗口管理器的 LaunchAgent（键盘失灵 / 扫到 0 窗口时用）。

set -euo pipefail

launchctl kickstart -k "gui/$(id -u)/com.github.karinushka.paneru"
echo "Paneru restarted"
