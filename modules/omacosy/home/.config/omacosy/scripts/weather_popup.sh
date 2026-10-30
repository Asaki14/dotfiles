#!/bin/bash
# weather_popup.sh - weather rows and JSON for OMacOSy.
# Reads the Open-Meteo cache and prints data consumed by omacosy-bar.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="/tmp/sketchybar_daemon/weather.json"

# Fetch once when the cache is missing; a failed fetch leaves the data unavailable.
ensure_cache() {
  if [ ! -s "$CACHE" ]; then
    mkdir -p "$(dirname "$CACHE")"
    python3 - "$CACHE" "$SCRIPT_DIR" <<'PYFETCH' 2>/dev/null
import pathlib, sys, urllib.request
sys.path.insert(0, sys.argv[2])
from weather_lib import FORECAST_URL
pathlib.Path(sys.argv[1]).write_bytes(urllib.request.urlopen(FORECAST_URL, timeout=15).read())
PYFETCH
  fi
}

# TSV: row type, glyph color, text color, glyph, text.
rows() {
  ensure_cache
  python3 - "$CACHE" "$SCRIPT_DIR" <<'PY'
import json, sys, datetime
sys.path.insert(0, sys.argv[2])
from weather_lib import describe_code, LOCATION, WEEKDAY_CN

SEP = "  ·  "
try:
    d = json.load(open(sys.argv[1]))
    cur = d['current']
    zh, icon = describe_code(cur['weather_code'])
    print("TITLE\tFOAM\tTEXT\t%s\t%s" % (icon, SEP.join(
        [LOCATION, zh, "%.0f°" % cur['temperature_2m']])))
    print("ROW\tFOAM\tTEXT\t󰔏\t%s" % SEP.join(
        ["体感 %.0f°" % cur['apparent_temperature'],
         "湿度 %d%%" % cur['relative_humidity_2m']]))
    today = datetime.date.today()
    dl = d['daily']
    for i, stamp in enumerate(dl['time'][:3]):
        day = datetime.date.fromisoformat(stamp)
        name = ("今天" if day == today else
                "明天" if day == today + datetime.timedelta(days=1) else
                "周" + WEEKDAY_CN[day.weekday()])
        dzh, dicon = describe_code(dl['weather_code'][i])
        print("ROW\tFOAM\tMUTED\t%s\t%s" % (dicon, SEP.join(
            [name + " %d/%d" % (day.month, day.day), dzh,
             "%.0f~%.0f°" % (dl['temperature_2m_min'][i], dl['temperature_2m_max'][i])])) )
except Exception:
    print("TITLE\tMUTED\tMUTED\t\t天气数据暂不可用")
PY
}

# JSON: structured current conditions and forecast days for the OMacOSy bar.
json() {
  ensure_cache
  python3 - "$CACHE" "$SCRIPT_DIR" <<'PYJSON'
import json, sys, datetime
sys.path.insert(0, sys.argv[2])
from weather_lib import describe_code, LOCATION, WEEKDAY_CN

try:
    d = json.load(open(sys.argv[1]))
    cur = d['current']
    zh, icon = describe_code(cur['weather_code'])
    dl = d['daily']
    pops = dl.get('precipitation_probability_max') or []
    today = datetime.date.today()
    days = []
    for i, stamp in enumerate(dl['time']):
        day = datetime.date.fromisoformat(stamp)
        name = ("今天" if day == today else
                "明天" if day == today + datetime.timedelta(days=1) else
                "周" + WEEKDAY_CN[day.weekday()])
        dzh, dicon = describe_code(dl['weather_code'][i])
        pop = pops[i] if i < len(pops) and pops[i] is not None else -1
        days.append({"name": name, "date": "%d/%d" % (day.month, day.day),
                     "min": round(dl['temperature_2m_min'][i]),
                     "max": round(dl['temperature_2m_max'][i]),
                     "pop": int(pop), "desc": dzh, "icon": dicon})
    print(json.dumps({
        "location": LOCATION,
        "current": {"temp": round(cur['temperature_2m']),
                    "feels": round(cur['apparent_temperature']),
                    "humidity": int(cur['relative_humidity_2m']),
                    "desc": zh, "icon": icon},
        "days": days,
    }, ensure_ascii=False))
except Exception as exc:
    print(json.dumps({"error": str(exc)}, ensure_ascii=False))
PYJSON
}

case "${1:-rows}" in
  rows) rows ;;
  json) json ;;
  *) rows ;;
esac
