#!/usr/bin/env python3
"""Quota coach aggregator — reconstructs Claude Code usage from local transcripts.

Reads ~/.claude/projects/**/*.jsonl assistant messages (model + usage blocks)
and produces cost-equivalent totals (USD-weighted tokens, a proxy for plan
quota consumption, which weighs models by price). Real quota (5h window /
weekly %) is NOT programmatically accessible; this is the best local proxy.

Everything runs locally: transcripts and aggregates never leave the box.

Modes:
  --report [--days N]   Full human-readable report (default 14 days). Also
                        refreshes the cache and summary.json.
  --refresh             Incremental cache refresh + summary.json, no output.
  --summary             Print summary.json to stdout (no scan).

Cache: ~/.claude/cache/quota/files.json (per-transcript aggregates keyed by
path+mtime+size — only changed files are re-parsed) and summary.json (compact
rollup consumed by the quota-nudge hook and the statusline).

Known limitation: dedup is per-file by message id (streaming writes one line
per content block). Forked/resumed sessions that copy history into a new file
can double-count; treat totals as an upper bound.

Stdlib only — no third-party dependencies.
"""
import argparse
import json
import os
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

HOME = os.path.expanduser("~")
PROJECTS_DIR = os.path.join(HOME, ".claude", "projects")
CACHE_DIR = os.path.join(HOME, ".claude", "cache", "quota")
FILES_CACHE = os.path.join(CACHE_DIR, "files.json")
SUMMARY_FILE = os.path.join(CACHE_DIR, "summary.json")

# Per-Mtok USD (input, output). Cache read = 0.1x input; cache write
# 5m TTL = 1.25x input, 1h TTL = 2x input. This is the ONLY place prices
# live — update the table if Anthropic reprices. "$eq" is a cost-equivalent
# proxy for quota consumption, not a real invoice (fixed-quota plans).
PRICES = {
    "fable": (10.0, 50.0),     # fable / mythos
    "opus": (5.0, 25.0),       # opus family
    "sonnet": (3.0, 15.0),     # sonnet family
    "haiku": (1.0, 5.0),       # haiku family
}


def model_family(model):
    m = (model or "").lower()
    if "fable" in m or "mythos" in m:
        return "fable"
    if "opus" in m:
        return "opus"
    if "haiku" in m:
        return "haiku"
    if "sonnet" in m:
        return "sonnet"
    return None  # <synthetic> and unknown models are skipped


def cost_usd(family, rec):
    pin, pout = PRICES[family]
    return (
        rec["in"] * pin
        + rec["out"] * pout
        + rec["cr"] * pin * 0.1
        + rec["cw5"] * pin * 1.25
        + rec["cw1"] * pin * 2.0
    ) / 1_000_000


def project_from_path(path):
    """Best-effort project name from a Claude Code transcript path.

    Claude Code encodes the session cwd as the directory name, flattening
    path separators into dashes (e.g. ``-home-user-projects-myproject``).
    """
    parent = os.path.dirname(path)
    # Subagent transcripts live at <project-dir>/<session-id>/subagents/agent-*.jsonl
    if os.path.basename(parent) == "subagents":
        parent = os.path.dirname(os.path.dirname(parent))
    d = os.path.basename(parent)
    if d.startswith("-tmp-"):
        return "(scratchpad)"
    if "worktrees" in d:
        return "(worktrees)"
    marker = "-projects-"
    if marker in d:
        return d.split(marker, 1)[1]
    return d.lstrip("-") or d


def parse_file(path):
    """Aggregate one transcript into records keyed by (date, family, sidechain)."""
    agg = defaultdict(lambda: {"in": 0, "out": 0, "cr": 0, "cw5": 0, "cw1": 0, "n": 0})
    seen = set()
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"usage"' not in line or '"assistant"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue  # malformed line — skip, never abort
                msg = d.get("message") or {}
                usage = msg.get("usage")
                if not usage or d.get("type") != "assistant":
                    continue
                fam = model_family(msg.get("model"))
                if fam is None:
                    continue  # <synthetic> / unknown model
                key_id = (msg.get("id"), d.get("requestId"))
                if key_id in seen:
                    continue
                seen.add(key_id)
                ts = d.get("timestamp", "")[:10]
                if len(ts) != 10:
                    continue
                cc = usage.get("cache_creation") or {}
                cw5 = cc.get("ephemeral_5m_input_tokens")
                cw1 = cc.get("ephemeral_1h_input_tokens", 0)
                if cw5 is None:  # older format: lump into the 5m bucket
                    cw5 = usage.get("cache_creation_input_tokens", 0)
                    cw1 = 0
                rec = agg[(ts, fam, bool(d.get("isSidechain")))]
                rec["in"] += usage.get("input_tokens", 0)
                rec["out"] += usage.get("output_tokens", 0)
                rec["cr"] += usage.get("cache_read_input_tokens", 0)
                rec["cw5"] += cw5
                rec["cw1"] += cw1
                rec["n"] += 1
    except OSError:
        return []
    return [{"d": k[0], "m": k[1], "sc": k[2], **v} for k, v in agg.items()]


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return default


def save_json(path, data):
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def any_transcripts():
    """True if at least one transcript exists (fresh / Antigravity boxes have none)."""
    if not os.path.isdir(PROJECTS_DIR):
        return False
    for _root, _dirs, files in os.walk(PROJECTS_DIR):
        if any(f.endswith(".jsonl") for f in files):
            return True
    return False


def scan(days):
    """Incremental scan of transcripts modified in the window. Returns records
    [{d, m, sc, project, in, out, cr, cw5, cw1, n}]."""
    cutoff = datetime.now().timestamp() - days * 86400
    cache = load_json(FILES_CACHE, {})
    new_cache = {}
    records = []
    for root, _dirs, files in os.walk(PROJECTS_DIR):
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
            entry = cache.get(path)
            if entry and entry["mtime"] == st.st_mtime and entry["size"] == st.st_size:
                recs = entry["recs"]
            else:
                recs = parse_file(path)
            new_cache[path] = {"mtime": st.st_mtime, "size": st.st_size, "recs": recs}
            proj = project_from_path(path)
            is_subagent = os.path.basename(os.path.dirname(path)) == "subagents"
            for r in recs:
                records.append({**r, "project": proj, "sc": r["sc"] or is_subagent})
    save_json(FILES_CACHE, new_cache)
    return records


def build_summary(records):
    today = date.today()
    day_cost = defaultdict(float)
    model_week = defaultdict(float)
    proj_week = defaultdict(float)
    sc_week = 0.0
    week_start = today - timedelta(days=6)
    prev_start = today - timedelta(days=13)
    for r in records:
        if r["m"] not in PRICES:
            continue  # unknown family (e.g. a cache from an older version)
        try:
            d = date.fromisoformat(r["d"])
        except ValueError:
            continue
        c = cost_usd(r["m"], r)
        day_cost[r["d"]] += c
        if d >= week_start:
            model_week[r["m"]] += c
            proj_week[r["project"]] += c
            if r["sc"]:
                sc_week += c
    week = sum(v for k, v in day_cost.items()
               if date.fromisoformat(k) >= week_start)
    prev = sum(v for k, v in day_cost.items()
               if prev_start <= date.fromisoformat(k) < week_start)
    heavy = model_week.get("opus", 0) + model_week.get("fable", 0)
    return {
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "today_cost": round(day_cost.get(today.isoformat(), 0), 2),
        "week_cost": round(week, 2),
        "prev_week_cost": round(prev, 2),
        "heavy_share_week": round(heavy / week, 3) if week else 0,
        "sidechain_share_week": round(sc_week / week, 3) if week else 0,
        "by_model_week": {k: round(v, 2) for k, v in sorted(
            model_week.items(), key=lambda x: -x[1])},
        "top_projects_week": {k: round(v, 2) for k, v in sorted(
            proj_week.items(), key=lambda x: -x[1])[:5]},
    }


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def print_report(records, days):
    by_day = defaultdict(float)
    by_model = defaultdict(lambda: {"cost": 0.0, "in": 0, "out": 0, "cr": 0,
                                    "cw": 0, "n": 0})
    by_proj = defaultdict(float)
    sc_cost = total = 0.0
    for r in records:
        if r["m"] not in PRICES:
            continue  # unknown family (e.g. a cache from an older version)
        c = cost_usd(r["m"], r)
        total += c
        by_day[r["d"]] += c
        m = by_model[r["m"]]
        m["cost"] += c
        m["in"] += r["in"]
        m["out"] += r["out"]
        m["cr"] += r["cr"]
        m["cw"] += r["cw5"] + r["cw1"]
        m["n"] += r["n"]
        by_proj[r["project"]] += c
        if r["sc"]:
            sc_cost += c

    print(f"# Claude Code usage — last {days} days "
          f"(API cost-equivalent, a proxy for plan quota)\n")
    print(f"Total: ${total:,.2f}eq   subagents: "
          f"{100 * sc_cost / total if total else 0:.0f}%\n")

    print("## By model")
    print(f"{'model':<10} {'$eq':>10} {'%':>5} {'msgs':>7} {'out tok':>9} {'cache hit':>10}")
    for fam, m in sorted(by_model.items(), key=lambda x: -x[1]["cost"]):
        ctx = m["in"] + m["cr"] + m["cw"]
        hit = 100 * m["cr"] / ctx if ctx else 0
        print(f"{fam:<10} {m['cost']:>9,.2f} "
              f"{100 * m['cost'] / total if total else 0:>4.0f}% "
              f"{m['n']:>7} {fmt_tokens(m['out']):>9} {hit:>9.0f}%")

    print("\n## By project (top 10)")
    for p, c in sorted(by_proj.items(), key=lambda x: -x[1])[:10]:
        print(f"  {p:<35} ${c:>9,.2f}  {100 * c / total if total else 0:.0f}%")

    print("\n## By day")
    peak = max(by_day.values()) if by_day else 0
    for d in sorted(by_day):
        bar = "#" * min(60, int(by_day[d] / peak * 40)) if peak else ""
        print(f"  {d}  ${by_day[d]:>8,.2f}  {bar}")

    heavy = (by_model.get("opus", {}).get("cost", 0)
             + by_model.get("fable", {}).get("cost", 0))
    print("\n## Flags")
    flagged = False
    if total and heavy / total > 0.5:
        flagged = True
        print(f"  [!] {100 * heavy / total:.0f}% of spend on Opus/Fable — the "
              f"most expensive models. For routine work, /model sonnet covers "
              f"most tasks at a fraction of the cost.")
    if total and sc_cost / total > 0.4:
        flagged = True
        print(f"  [!] {100 * sc_cost / total:.0f}% of spend on subagents — check "
              f"for unnecessary fan-outs and orphaned agent-* worktrees.")
    for fam, m in by_model.items():
        ctx = m["in"] + m["cr"] + m["cw"]
        if ctx > 5_000_000 and m["cr"] / ctx < 0.5:
            flagged = True
            print(f"  [!] low cache hit on {fam} ({100 * m['cr'] / ctx:.0f}%) — "
                  f"long sessions with pauses >5min lose the cache (5m TTL); "
                  f"group work or /clear between topics.")
    if not flagged:
        print("  none — usage looks balanced.")


def main():
    ap = argparse.ArgumentParser(description="Claude Code quota coach aggregator")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--days", type=int, default=14)
    args = ap.parse_args()

    if args.summary:
        s = load_json(SUMMARY_FILE, None)
        print(json.dumps(s) if s else "{}")
        return

    if not any_transcripts():
        if args.report:
            print("no Claude Code transcripts found yet")
        return  # nothing to summarise; leave any stale summary untouched

    records = scan(max(args.days, 14))
    save_json(SUMMARY_FILE, build_summary(records))
    if args.report:
        cutoff = (date.today() - timedelta(days=args.days - 1)).isoformat()
        print_report([r for r in records if r["d"] >= cutoff], args.days)


if __name__ == "__main__":
    main()
