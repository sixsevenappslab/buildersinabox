#!/usr/bin/env python3
"""Quota watchdog — alerts when the rolling 5-hour window burns much hotter than usual.

Computes $eq (API-price-weighted cost) of local transcripts over the rolling
last-5h window and compares it with the median of active 5h windows over the
last 14 days. Real subscription quota (5h window / weekly %) is NOT
programmatically accessible — this is a local pace proxy ("this window is
running Nx hotter than your typical active window"), consumed by the
biab-quota-window.sh UserPromptSubmit hook.

Modes:
  --check   Print JSON status and refresh the hourly cache (default).

Cache: ~/.claude/cache/quota/files_hourly.json (per-transcript timestamped $eq).
Sidechain (subagent) transcripts are included on purpose: they consume the same
plan quota as the main thread.

Stdlib only — no third-party dependencies, no network calls.
"""
import argparse
import json
import os
import statistics
import sys
import tempfile
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from quota_report import AGY_BRAIN_DIR, PROJECTS_DIR, cost_usd, load_json, parse_messages

CACHE_DIR = os.path.join(os.path.expanduser("~"), ".claude", "cache", "quota")
HOURLY_CACHE = os.path.join(CACHE_DIR, "files_hourly.json")
CACHE_VERSION = 3

WINDOW_HOURS = 5
BASELINE_DAYS = 14
RATIO_THRESHOLD = 1.5
# Ignore small absolute spend: a quiet window must not look "1.5x hot".
FLOOR_COST = 2.0


def parse_file_events(path):
    return [
        (message["timestamp"], cost_usd(message["m"], message))
        for message in parse_messages(path)
    ]


def save_hourly_cache(data):
    """Atomically replace the cache without sharing a temporary file name."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    fd, temporary = tempfile.mkstemp(
        dir=CACHE_DIR, prefix="files_hourly.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(temporary, HOURLY_CACHE)
    except OSError:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def scan_events(days):
    """Incrementally scan transcript costs with their exact timestamps."""
    cutoff = datetime.now(timezone.utc).timestamp() - days * 86400
    cache = load_json(HOURLY_CACHE, {})
    cached_files = (
        cache.get("files", {}) if cache.get("version") == CACHE_VERSION else {}
    )
    new_cache = {}
    messages = {}
    for base_dir in (PROJECTS_DIR, AGY_BRAIN_DIR):
        if not os.path.isdir(base_dir):
            continue
        for root, _dirs, files in os.walk(base_dir):
            for name in files:
                if not name.endswith(".jsonl"):
                    continue
                path = os.path.join(root, name)
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                if st.st_mtime < cutoff:
                    continue
                entry = cached_files.get(path)
                if (
                    entry
                    and entry.get("mtime") == st.st_mtime
                    and entry.get("size") == st.st_size
                ):
                    per = entry.get("messages", [])
                else:
                    per = parse_messages(path)
                per = [message for message in per if message["timestamp"] >= cutoff]
                new_cache[path] = {
                    "mtime": st.st_mtime,
                    "size": st.st_size,
                    "messages": per,
                }
                for message in per:
                    key = message["key"]
                    if key not in messages:
                        messages[key] = dict(message)
                    else:
                        for field in ("in", "out", "cr", "cw5", "cw1"):
                            messages[key][field] = max(
                                messages[key][field], message[field]
                            )
    try:
        save_hourly_cache({"version": CACHE_VERSION, "files": new_cache})
    except OSError:
        pass
    return [
        (message["timestamp"], cost_usd(message["m"], message))
        for message in messages.values()
    ]


def window_cost(events, end_dt, span=WINDOW_HOURS):
    end = end_dt.timestamp()
    start = end - span * 3600
    return sum(cost for timestamp, cost in events if start <= timestamp <= end)


def baseline_cost(events, now, days=BASELINE_DAYS):
    """Median of active (non-zero) 5h windows over the last `days` days."""
    vals = []
    t = now - timedelta(hours=days * 24)
    latest = now - timedelta(hours=WINDOW_HOURS)
    while t <= latest:
        c = window_cost(events, t)
        if c > 0:
            vals.append(c)
        t += timedelta(hours=1)
    return (statistics.median(vals) if vals else 0.0), len(vals)


def build_status():
    now = datetime.now(timezone.utc)
    events = scan_events(BASELINE_DAYS)
    current = round(window_cost(events, now), 2)
    baseline, n_windows = baseline_cost(events, now)
    baseline = round(baseline, 2)
    ratio = round(current / baseline, 2) if baseline else 0.0

    if current < FLOOR_COST:
        status = "ok"
    elif baseline <= 0:
        status = "ok"
    elif current >= RATIO_THRESHOLD * baseline:
        status = "alert"
    else:
        status = "ok"

    return {
        "checked_at": now.isoformat(timespec="seconds"),
        "status": status,
        "window_5h_cost": current,
        "baseline_active_5h": baseline,
        "ratio": ratio,
        "active_windows": n_windows,
        "threshold_ratio": RATIO_THRESHOLD,
        "floor_cost": FLOOR_COST,
    }


def main():
    ap = argparse.ArgumentParser(
        description="5-hour rolling quota-window pace watchdog"
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="Print JSON status for the rolling 5-hour window (default)",
    )
    ap.parse_args()
    print(json.dumps(build_status()))


if __name__ == "__main__":
    main()
