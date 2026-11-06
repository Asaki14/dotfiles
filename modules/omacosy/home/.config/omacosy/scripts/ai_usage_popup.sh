#!/bin/bash
# ai_usage_popup.sh - AI usage rows for OMacOSy.
# Reads the bar's cached usage JSON and prints the TSV consumed by omacosy-bar.

CLAUDE_ROWS=3
CODEX_ROWS=2
CACHE_DIR="/tmp/sketchybar_daemon"

# TSV: target suffix, glyph color, text color, left column, right column.
rows() {
  python3 - "$CACHE_DIR" "$CLAUDE_ROWS" "$CODEX_ROWS" <<'PY'
import datetime, json, pathlib, sys

cache = pathlib.Path(sys.argv[1])
CLAUDE_MAX, CODEX_MAX = int(sys.argv[2]), int(sys.argv[3])
SEP = "  ·  "
CELLS = 12
PLACEHOLDER = "●"


def load(name):
    try:
        d = json.loads((cache / name).read_text())
        return d[0] if isinstance(d, list) and d else (d if isinstance(d, dict) else None)
    except Exception:
        return None


def gauge(pct):
    """Convert percentage to a bar and tone."""
    p = max(0, min(100, int(pct)))
    hit = round(p / 100 * CELLS)
    tone = "LOVE" if p > 80 else "GOLD" if p > 60 else "TEXT"
    return "█" * hit + "░" * (CELLS - hit), tone


def countdown(stamp):
    """Convert an ISO timestamp to remaining time."""
    try:
        end = datetime.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc)
    except Exception:
        return None
    left = max(0, int((end - datetime.datetime.now(datetime.timezone.utc)).total_seconds()))
    d, h, m = left // 86400, left % 86400 // 3600, left % 3600 // 60
    return f"{d}d{h}h" if d else (f"{h}h{m}m" if h else f"{m}m")


out = []


def emit(target, icon_color, label_color, icon, label):
    out.append("\t".join([target, icon_color, label_color, icon or PLACEHOLDER,
                          label or PLACEHOLDER]))


def plan_of(usage, brand):
    """Remove a repeated brand prefix from the plan name."""
    name = (usage.get("loginMethod") or "").strip()
    if name.lower().startswith(brand.lower()):
        name = name[len(brand):].strip()
    return name[:1].upper() + name[1:] if name else ""


def window_row(prefix, slot, name, win):
    """Emit one rate-limit window row; skip windows without a percentage."""
    if not isinstance(win, dict) or win.get("usedPercent") is None:
        return False
    pct = int(win["usedPercent"])
    track, tone = gauge(pct)
    left = countdown(win.get("resetsAt") or "")
    text = f"{track} {pct}%"
    if left:
        text += f"  ↻{left}"
    emit(f"{prefix}.{slot}", "MUTED", tone, name, text)
    return True


# Claude: title plus 5h, 7d, and Fable-only weekly windows.
claude_rows = 0
claude = load("claude_raw.json")
if claude:
    u = claude.get("usage") or {}
    emit("title", "TEXT", "TEXT", "", SEP.join(x for x in ["Claude", plan_of(u, "Claude")] if x))
    for name, win in (("5h", u.get("primary")), ("7d", u.get("secondary"))):
        if window_row("c", claude_rows + 1, name, win):
            claude_rows += 1
    for extra in (u.get("extraRateWindows") or []):
        if "fable" in (extra.get("id", "") + extra.get("title", "")).lower():
            if window_row("c", claude_rows + 1, "Fable", (extra.get("window") or {})):
                claude_rows += 1
            break
else:
    emit("title", "MUTED", "MUTED", "", "Claude 用量暂不可用")

# Codex: heading plus 5h and 7d windows.
codex_rows = 0
codex = load("codex_raw.json")
if codex:
    u = codex.get("usage") or {}
    emit("head2", "TEXT", "TEXT", "", SEP.join(x for x in ["Codex", plan_of(u, "Codex")] if x))
    for name, win in (("5h", u.get("primary")), ("7d", u.get("secondary"))):
        if window_row("x", codex_rows + 1, name, win):
            codex_rows += 1
else:
    emit("head2", "MUTED", "MUTED", "", "Codex 用量暂不可用")

# Draw the separator only when both providers have usage rows.
print("\t".join(["sep", "MUTED", "MUTED",
                 "ON" if claude_rows and codex_rows else "OFF", PLACEHOLDER]))
for line in out:
    print(line)
# Turn off unused slots so stale rows are not left visible.
for i in range(claude_rows + 1, CLAUDE_MAX + 1):
    print("\t".join([f"c.{i}", "MUTED", "MUTED", "__OFF__", PLACEHOLDER]))
for i in range(codex_rows + 1, CODEX_MAX + 1):
    print("\t".join([f"x.{i}", "MUTED", "MUTED", "__OFF__", PLACEHOLDER]))
PY
}

rows
