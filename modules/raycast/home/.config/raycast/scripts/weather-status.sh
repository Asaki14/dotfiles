#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Weather
# @raycast.mode inline
# @raycast.packageName Omarchy
# @raycast.refreshTime 30m
#
# @raycast.icon 🌦️
# @raycast.description 一行显示成都实况天气，优先读取 OMacOSy 天气缓存。

set -uo pipefail

CACHE=/tmp/sketchybar_daemon/weather.json
PLUGINS="$HOME/.config/omacosy/scripts"

# 天气分类与中文文案复用 OMacOSy 的 weather_lib，只有图标换成 emoji：
# Raycast 的行内输出走系统字体，状态栏那套 Nerd Font 字形在这里会显示成豆腐块。
render() {
  python3 - "$1" "$PLUGINS" <<'PY'
import json, sys

sys.path.insert(0, sys.argv[2])
from weather_lib import describe, describe_code, place, LOCATION

EMOJI = {
    "雷雨": "⛈️", "雨夹雪": "🌨️", "雪": "❄️", "大雨": "🌧️", "小雨": "🌦️",
    "雨": "🌧️", "雾霾": "🌫️", "阴": "☁️", "多云": "⛅", "云": "☁️", "晴": "☀️",
}

d = json.load(open(sys.argv[1]))
if "current" in d:
    cur = d["current"]
    city = LOCATION
    zh, _ = describe_code(cur["weather_code"])
    temperature = f'{cur["temperature_2m"]:.0f}'
    humidity = cur["relative_humidity_2m"]
else:
    cur = d["current_condition"][0]
    city = place(d["nearest_area"][0]["areaName"][0]["value"])
    zh, _ = describe(cur["weatherDesc"][0]["value"])
    temperature = cur["temp_C"]
    humidity = cur["humidity"]
icon = EMOJI.get(zh, "🌡️")
print(f'{icon}  {city} · {temperature}° · {zh} · 湿度 {humidity}%')
PY
}

if [ -s "$CACHE" ] && render "$CACHE" 2>/dev/null; then
  exit 0
fi

tmp=$(mktemp -t raycast-weather)
trap 'rm -f "$tmp"' EXIT
if curl -sf --connect-timeout 8 --max-time 15 "https://wttr.in/Chengdu?format=j1" -o "$tmp" && render "$tmp" 2>/dev/null; then
  exit 0
fi

echo "天气数据暂不可用"
