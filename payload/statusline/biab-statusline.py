#!/usr/bin/env python3
"""Minimal Builders in a Box statusline for Claude Code.

Reads the Claude Code statusline JSON on stdin and prints one line:

    <model> · ctx <N>k <pct>% · wk $<N>eq

The final `wk $Neq` segment is the week's cost-equivalent burn from the quota
coach summary (~/.claude/cache/quota/summary.json), coloured by the trend vs
the previous week (green steady/down, yellow up, red sharply up). It only
appears when a fresh summary exists.

Defensive by contract: any missing/corrupt input degrades to a shorter line —
never a traceback to the user. Stdlib only.
"""
import json
import os
import sys
import time

GREEN, YELLOW, RED, DIM, RESET = "\033[32m", "\033[33m", "\033[31m", "\033[2m", "\033[0m"

SUMMARY_FILE = os.path.join(
    os.path.expanduser("~"), ".claude", "cache", "quota", "summary.json"
)


def read_stdin():
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def context_tokens(transcript_path):
    """Total context tokens from the last message with a usage block. Reads
    only the tail of the file for speed."""
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as f:
            if size > 262144:
                f.seek(size - 262144)
                f.readline()  # discard the partial first line
            tail = f.read().decode("utf-8", "replace")
    except Exception:
        return None
    last = None
    for line in tail.splitlines():
        line = line.strip()
        if not line or '"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        msg = d.get("message", {})
        u = msg.get("usage") if isinstance(msg, dict) else None
        if u:
            last = u
    if not last:
        return None
    return (
        last.get("input_tokens", 0)
        + last.get("cache_read_input_tokens", 0)
        + last.get("cache_creation_input_tokens", 0)
    )


def weekly_burn():
    """(text, color) for the week's cost-equivalent burn, or None. Skips a
    summary older than 26h. Never raises on a corrupt file."""
    try:
        if os.path.getmtime(SUMMARY_FILE) < time.time() - 26 * 3600:
            return None
        with open(SUMMARY_FILE) as f:
            s = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(s, dict):
        return None
    week = s.get("week_cost")
    if not week:
        return None
    prev = s.get("prev_week_cost") or 0
    try:
        color = GREEN if prev == 0 or week <= prev * 1.05 else (
            YELLOW if week <= prev * 1.3 else RED
        )
        return f"wk ${week:,.0f}eq", color
    except (TypeError, ValueError):
        return None


def main():
    d = read_stdin()
    model = (d.get("model") or {}).get("display_name", "?")
    transcript = d.get("transcript_path", "")
    exceeds_200k = d.get("exceeds_200k_tokens", False)

    parts = [f"{DIM}{model}{RESET}"]

    toks = context_tokens(transcript)
    if toks is not None:
        window = 1_000_000 if (toks > 200_000 or exceeds_200k) else 200_000
        pct = toks / window * 100
        try:
            ac = float(os.environ.get("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "75"))
        except ValueError:
            ac = 75.0
        color = GREEN if pct < ac * 0.66 else (YELLOW if pct < ac else RED)
        warn = " !compact" if pct >= ac else ""
        parts.append(f"{color}ctx {toks / 1000:.0f}k {pct:.0f}%{warn}{RESET}")

    burn = weekly_burn()
    if burn:
        parts.append(f"{burn[1]}{burn[0]}{RESET}")

    print(f" {DIM}·{RESET} ".join(parts))


if __name__ == "__main__":
    main()
