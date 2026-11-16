#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Weather
# @raycast.mode inline
# @raycast.packageName Omarchy
# @raycast.refreshTime 30m
#
# @raycast.icon 🌦️
# @raycast.description 一行显示本地实况天气，优先读取 OMacOSy 天气缓存。

set -uo pipefail

CACHE=/tmp/sketchybar_daemon/weather.json
PLUGINS="$HOME/.config/omacosy/scripts"

# 天气分类、中文文案和地点复用 OMacOSy 的 weather_lib，只有图标换成 emoji：
# 启动器的行内输出走系统字体，状态栏那套 Nerd Font 字形在这里会显示成豆腐块。
render() {
  python3 - "$1" "$PLUGINS" <<'PY'
import json, sys

sys.path.insert(0, sys.argv[2])
from weather_lib import describe_code, LOCATION

EMOJI = {
    "雷雨": "⛈️", "雨夹雪": "🌨️", "雪": "❄️", "大雨": "🌧️", "小雨": "🌦️",
    "雨": "🌧️", "雾霾": "🌫️", "阴": "☁️", "多云": "⛅", "云": "☁️", "晴": "☀️",
}

cur = json.load(open(sys.argv[1]))["current"]
zh, _ = describe_code(cur["weather_code"])
icon = EMOJI.get(zh, "🌡️")
print(f'{icon}  {LOCATION} · {cur["temperature_2m"]:.0f}° · {zh} · 湿度 {cur["relative_humidity_2m"]}%')
PY
}

if [ -s "$CACHE" ] && render "$CACHE" 2>/dev/null; then
  exit 0
fi

tmp=$(mktemp -t tinycast-weather)
trap 'rm -f "$tmp"' EXIT
url=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from weather_lib import FORECAST_URL; print(FORECAST_URL)' "$PLUGINS")
if curl -sf --connect-timeout 8 --max-time 15 "$url" -o "$tmp" && render "$tmp" 2>/dev/null; then
  exit 0
fi

echo "天气数据暂不可用"
