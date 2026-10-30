#!/usr/bin/env python3
"""天气文案与图标映射 — 状态栏与弹层共用这一份，避免两处走样。

数据源为 Open-Meteo：它给 WMO 数字代码，中文与 Nerd Font 图标都在这里落地。
describe() 保留给文字描述的旧路径，describe_code() 走数字代码的新路径。
"""

# 关键词按从具体到笼统排序，命中即停；顺序即优先级。
_RULES = [
    (("thunder", "雷"), "雷雨", ""),
    (("sleet", "雨夹雪"), "雨夹雪", ""),
    (("snow", "blizzard", "雪"), "雪", ""),
    (("heavy rain", "大雨"), "大雨", ""),
    (("drizzle", "patchy rain", "light rain", "小雨"), "小雨", ""),
    (("rain", "shower", "雨"), "雨", ""),
    (("fog", "mist", "haze", "雾", "霾"), "雾霾", ""),
    (("overcast", "阴"), "阴", ""),
    (("partly cloudy", "多云"), "多云", ""),
    (("cloud", "云"), "云", ""),
    (("sunny", "clear", "晴"), "晴", ""),
]

_FALLBACK = ("—", "")


def describe(text):
    """英文或中文描述 -> (中文描述, 图标)。认不出就原样保留文字配默认图标。"""
    raw = (text or "").strip()
    low = raw.lower()
    for keys, zh, icon in _RULES:
        if any(k in low for k in keys):
            return zh, icon
    return (raw or _FALLBACK[0]), _FALLBACK[1]


# ── 数据源：Open-Meteo（免密钥，按精确经纬取网格点） ─────────────
import os

LOCATION = os.environ.get("OMACOSY_WEATHER_LOCATION", "上海")
LATITUDE = float(os.environ.get("OMACOSY_WEATHER_LAT", "31.23"))
LONGITUDE = float(os.environ.get("OMACOSY_WEATHER_LON", "121.47"))

FORECAST_URL = (
    "https://api.open-meteo.com/v1/forecast"
    "?latitude={lat}&longitude={lon}"
    "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code"
    "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
    "&timezone=Asia%2FShanghai&forecast_days=6"
).format(lat=LATITUDE, lon=LONGITUDE)

# WMO 天气代码 -> (中文, 字形)。字形沿用上面 _RULES 那套，两条路径同一套视觉。
_WMO = {
    0: ("晴", ""),        1: ("少云", ""),      2: ("多云", ""),   3: ("阴", ""),
    45: ("雾", ""),       48: ("冻雾", ""),
    51: ("小雨", ""),    53: ("小雨", ""),    55: ("小雨", ""),
    56: ("冻雨", ""),   57: ("冻雨", ""),
    61: ("小雨", ""),    63: ("中雨", ""),    65: ("大雨", ""),
    66: ("冻雨", ""),   67: ("冻雨", ""),
    71: ("小雪", ""),    73: ("中雪", ""),    75: ("大雪", ""),  77: ("雪粒", ""),
    80: ("阵雨", ""),    81: ("强阵雨", ""),  82: ("暴雨", ""),
    85: ("阵雪", ""),    86: ("强阵雪", ""),
    95: ("雷雨", ""), 96: ("雷雨冰雹", ""), 99: ("强雷雨冰雹", ""),
}


def describe_code(code):
    """WMO 数字代码 -> (中文描述, 图标)。认不出的代码退回统一兜底，不猜。"""
    try:
        return _WMO[int(code)]
    except (TypeError, ValueError, KeyError):
        return _FALLBACK


WEEKDAY_CN = ["一", "二", "三", "四", "五", "六", "日"]

# 数据源的地名与风向只给英文，这里补中文；查不到就原样显示，不猜。
PLACE_ZH = {"Shanghai": "上海"}

WIND_ZH = {
    "N": "北", "NNE": "东北偏北", "NE": "东北", "ENE": "东北偏东",
    "E": "东", "ESE": "东南偏东", "SE": "东南", "SSE": "东南偏南",
    "S": "南", "SSW": "西南偏南", "SW": "西南", "WSW": "西南偏西",
    "W": "西", "WNW": "西北偏西", "NW": "西北", "NNW": "西北偏北",
}


def place(name):
    return PLACE_ZH.get((name or "").strip(), (name or "").strip())


def wind(point):
    return WIND_ZH.get((point or "").strip(), (point or "").strip())
