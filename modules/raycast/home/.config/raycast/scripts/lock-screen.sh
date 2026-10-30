#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Lock Screen
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# @raycast.icon 🔒
# @raycast.description 立即锁屏并要求输入密码。首次运行需给 Raycast 开启「辅助功能」权限。

set -euo pipefail

# 本机 sysadminctl -screenLock 宽限期为 300s，pmset displaysleepnow 只熄屏不锁；
# macOS 26 已移除 CGSession，因此用系统锁屏快捷键 ⌃⌘Q（立即要求密码，不受宽限期影响）。
osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}'
