#!/usr/bin/python3
"""omp_usage.py - AI usage for omacosy-bar (bar-items.conf `codexbar` directive).

omp already fetches Claude and Codex rate limits for its own logins and caches
the reports in ~/.omp/agent/agent.db. This reads the newest report for the
requested provider and prints it in the codexbar JSON shape omacosy-bar parses:
  usage --provider claude|codex --format json ...
No network calls and no tokens leave omp. A report older than STALE_AFTER
prints nothing, so the bar keeps its previous cache and dims it.
"""

import datetime
import json
import os
import sqlite3
import sys
import time

DB = os.path.expanduser("~/.omp/agent/agent.db")
PROVIDERS = {"claude": "anthropic", "codex": "openai-codex"}
SLOTS = {"5h": "primary", "7d": "secondary"}
# provider -> (usage field, credit reset_type) read by the bar's aiResetRow
RESET_CREDITS = {"anthropic": ("claudeResetCredits", "claude_rate_limits"),
                 "openai-codex": ("codexResetCredits", "codex_rate_limits")}
STALE_AFTER = 900  # seconds; matches the bar's own dim threshold


def iso(ms):
    if not ms:
        return None
    stamp = datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc)
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_text(stamp):
    """Drop fractional seconds; the bar's ISO8601DateFormatter rejects them."""
    try:
        parsed = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None
    return parsed.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def latest_report(provider):
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT value FROM cache WHERE key LIKE ?",
            (f"usage_cache:report:%:{provider}:%",)).fetchall()
    finally:
        con.close()
    reports = []
    for (value,) in rows:
        try:
            report = json.loads(value)["value"]
        except (ValueError, KeyError, TypeError):
            continue
        if isinstance(report, dict) and report.get("fetchedAt"):
            reports.append(report)
    return max(reports, key=lambda r: r["fetchedAt"], default=None)


def window(limit):
    amount = limit.get("amount") or {}
    win = limit.get("window") or {}
    used = amount.get("used")
    if used is None or amount.get("unit") != "percent":
        return None
    out = {"usedPercent": round(used)}
    if win.get("durationMs"):
        out["windowMinutes"] = int(win["durationMs"] // 60000)
    if win.get("resetsAt"):
        out["resetsAt"] = iso(win["resetsAt"])
    return out


def usage(provider, report):
    result = {}
    extra = []
    for limit in report.get("limits") or []:
        scope = limit.get("scope") or {}
        win = window(limit)
        if win is None:
            continue
        slot = SLOTS.get(scope.get("windowId")) if scope.get("shared", True) else None
        if slot and slot not in result:
            result[slot] = win
        else:
            extra.append({"id": limit.get("id", ""), "title": limit.get("label", ""), "window": win})
    if extra:
        result["extraRateWindows"] = extra
    plan = (report.get("metadata") or {}).get("planType")
    if plan:
        result["loginMethod"] = plan
    credits = (report.get("resetCredits") or {}).get("credits") or []
    tag = RESET_CREDITS.get(provider)
    if tag and credits:
        result[tag[0]] = {"credits": [
            {"reset_type": tag[1], "status": c.get("status"),
             "remaining_count": c.get("remainingCount") or 1,
             "expires_at": iso_text(c.get("expiresAt"))}
            for c in credits]}
    return result


def main(argv):
    name = argv[argv.index("--provider") + 1] if "--provider" in argv[:-1] else None
    provider = PROVIDERS.get(name)
    if provider is None:
        print(f"omp_usage: unsupported provider {name!r}", file=sys.stderr)
        return 1
    report = latest_report(provider)
    if report is None:
        print(f"omp_usage: omp has no {provider} usage report", file=sys.stderr)
        return 1
    if time.time() - report["fetchedAt"] / 1000 > STALE_AFTER:
        print(f"omp_usage: {provider} report is stale", file=sys.stderr)
        return 1
    print(json.dumps([{"provider": name, "source": "omp", "usage": usage(provider, report)}]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
