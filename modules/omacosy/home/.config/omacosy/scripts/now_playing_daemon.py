#!/usr/bin/env python3
"""mpd synced lyrics client — ticks the current lyric line for the menu bar.

Source: mpd over its unix socket (status + currentsong at 1 Hz, position
interpolated between polls). Lyrics: the `.lrc` beside the song inside the
music directory; absent → LRCLIB once per track, and a synced hit whose
duration matches is written back as that `.lrc` so rmpc sees it too.

Output: an atomic JSON file consumed by omacosy-bar.
"""
import json
import os
import socket
import time
from urllib.parse import urlencode
from urllib.request import urlopen, Request

LRCLIB_GET = "https://lrclib.net/api/get?"
LRCLIB_SEARCH = "https://lrclib.net/api/search?"
LYRIC_OFFSET = float(os.environ.get("LYRIC_OFFSET", "0.0"))
POLL_INTERVAL = float(os.environ.get("MPD_POLL_INTERVAL", "1.0"))
MPD_SOCKET = os.path.expanduser(os.environ.get("MPD_SOCKET", "~/.local/share/mpd/socket"))
MUSIC_DIR = os.path.expanduser(os.environ.get("MPD_MUSIC_DIR", "~/Music/lib"))
LRC_WRITE = os.environ.get("LYRIC_LRC_WRITE", "1") != "0"
LYRIC_OUT = os.environ.get("OMACOSY_LYRIC_OUT", "/tmp/omacosy-bar/lyric.json")

last_key = None
lyrics = []
track = None
sampled_at = 0.0
last_poll = 0.0
last_label = None


def write_output(label):
    state, icon, text = label
    payload = {
        "state": state,
        "icon": icon,
        "text": text,
        "track": f'{track["artist"]} - {track["name"]}' if track and track.get("name") else "",
        "artist": track["artist"] if track else "",
        "name": track["name"] if track else "",
        "ts": time.time(),
    }
    directory = os.path.dirname(LYRIC_OUT)
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp = LYRIC_OUT + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(payload, fh, ensure_ascii=False)
    os.replace(tmp, LYRIC_OUT)



# --- mpd ---------------------------------------------------------------------
# One short-lived connection per poll: a persistent one would need idle/noidle
# bookkeeping and reconnect logic for nothing — the socket is local and the
# two commands answer in well under a millisecond.
def mpd_command(conn, cmd):
    conn.sendall((cmd + "\n").encode())
    buf = b""
    while True:
        chunk = conn.recv(65536)
        if not chunk:
            raise ConnectionError("mpd closed the connection")
        buf += chunk
        if buf.endswith(b"OK\n") or b"\nACK " in buf or buf.startswith(b"ACK "):
            break
    out = {}
    for line in buf.decode("utf-8", "replace").splitlines():
        if ": " in line:
            k, v = line.split(": ", 1)
            out.setdefault(k, v)  # 同名键取第一个（多艺人标签时 mpd 会重复 Artist 行）
    return out


def mpd():
    """Current track as the rest of the daemon understands it, or None."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(2)
            conn.connect(MPD_SOCKET)
            conn.recv(64)  # "OK MPD x.y.z"
            status = mpd_command(conn, "status")
            if status.get("state") not in ("play", "pause"):
                return None
            song = mpd_command(conn, "currentsong")
    except (OSError, ConnectionError, socket.timeout):
        return None
    name = song.get("Title") or os.path.splitext(os.path.basename(song.get("file", "")))[0]
    if not name:
        return None
    return {
        "state": "playing" if status["state"] == "play" else "paused",
        "name": name,
        "artist": song.get("Artist", ""),
        "album": song.get("Album", ""),
        "duration": int(float(status.get("duration") or song.get("Time") or 0)),
        "pos": float(status.get("elapsed") or 0),
        "file": song.get("file", ""),
    }


# --- lyrics ------------------------------------------------------------------
def parse_lrc(text):
    rows = []
    for line in text.splitlines():
        if not line.startswith("[") or "]" not in line:
            continue
        stamp, lyric = line[1:].split("]", 1)
        try:
            minute, second = stamp.split(":", 1)
            rows.append((int(minute) * 60 + float(second), lyric.strip()))
        except ValueError:
            pass
    return rows


def normalized(text):
    # Tiny Traditional-to-Simplified fallback for common tag/LRCLIB title mismatches.
    return text.translate(str.maketrans("愛妳體後臺", "爱你体后台"))


def fetch_json(url):
    req = Request(url, headers={"User-Agent": "omacosy-bar-NowPlaying/1.0"})
    with urlopen(req, timeout=5) as r:
        return json.load(r)


def lrc_path(t):
    if not t.get("file"):
        return None
    return os.path.join(MUSIC_DIR, os.path.splitext(t["file"])[0] + ".lrc")


def load_lyrics(t):
    path = lrc_path(t)
    if path and os.path.exists(path):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                return parse_lrc(fh.read())
        except OSError:
            pass

    queries = [
        (LRCLIB_GET, {
            "track_name": t["name"],
            "artist_name": t["artist"],
            "album_name": t["album"],
            "duration": t["duration"],
        }),
        (LRCLIB_SEARCH, {
            "track_name": t["name"],
            "artist_name": t["artist"],
        }),
        (LRCLIB_SEARCH, {
            "track_name": normalized(t["name"]),
            "artist_name": normalized(t["artist"]),
        }),
    ]
    for base, params in queries:
        try:
            data = fetch_json(base + urlencode(params))
            rows = data if isinstance(data, list) else [data]
            # search 结果不校验时长会拿到同名别曲，只收时长相差 8 s 以内的同步歌词
            best = next((x for x in rows if x.get("syncedLyrics")
                         and (not t["duration"] or abs((x.get("duration") or 0) - t["duration"]) <= 8)), None)
            if best:
                if LRC_WRITE and path and not os.path.exists(path):
                    try:
                        with open(path, "w", encoding="utf-8") as fh:
                            fh.write(best["syncedLyrics"].strip() + "\n")
                    except OSError:
                        pass
                return parse_lrc(best["syncedLyrics"])
        except Exception:
            pass
    return []


def line_at(rows, pos):
    current = ""
    for ts, text in rows:
        if ts > pos:
            break
        if text:
            current = text
    return current


def current_pos():
    if not track:
        return 0.0
    if track["state"] != "playing":
        return track["pos"]
    return track["pos"] + time.monotonic() - sampled_at


def poll_mpd(force=False):
    global last_key, lyrics, track, sampled_at, last_poll

    now = time.monotonic()
    if not force and now - last_poll < POLL_INTERVAL:
        return

    last_poll = now
    fresh = mpd()
    sampled_at = time.monotonic()
    track = fresh

    if not fresh:
        return

    key = (fresh["file"], fresh["name"], fresh["artist"], fresh["duration"])
    if key != last_key:
        last_key = key
        lyrics = load_lyrics(fresh)


def update_bar():
    global last_label

    poll_mpd()

    if not track or not track["name"]:
        label = ("hidden", "", "")
    elif track["state"] == "playing":
        text = line_at(lyrics, current_pos() + LYRIC_OFFSET) or f'{track["name"]} — {track["artist"]}'
        label = ("playing", "", text)
    elif track["state"] == "paused":
        label = ("paused", "⏸", "暂停中")
    else:
        label = ("hidden", "", "")

    if label == last_label:
        return
    last_label = label
    write_output(label)


if __name__ == "__main__":
    write_output(("hidden", "", ""))
    poll_mpd(force=True)
    while True:
        try:
            update_bar()
        except Exception:
            pass
        time.sleep(0.2)


