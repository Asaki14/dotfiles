#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Sleep
# @raycast.mode silent
# @raycast.packageName Omarchy
# @raycast.needsConfirmation true
#
# @raycast.icon 🌙
# @raycast.description 让这台 Mac 立即进入睡眠。

set -euo pipefail

pmset sleepnow
