---
name: quota
description: Usage coach for your Claude plan — reconstructs real Claude Code consumption from local transcripts (cost-equivalent per model / project / day, subagent share, cache hit rate) and suggests where to cut. Use when the user asks "how much have I burned this week?", about token usage, or wants to get more out of their plan before hitting the rate limit. Claude Code only.
---

# quota — usage coach for your Claude plan

Your plan's real quota (the 5-hour window and weekly limit) is **not accessible
programmatically** — only the interactive `/usage` command shows it. This skill
uses the best local proxy: tokens from your Claude Code transcripts weighted by
each model's API price ("$eq"). It's for comparing weeks, spotting leaks, and
deciding where to cut — not for reading the exact percentage of your limit.

Everything runs locally. Transcripts and aggregates never leave the box.

## Process

1. Run the aggregator (the first run can take up to a minute; later runs are
   cached and finish in seconds):
   ```bash
   python3 ~/.claude/skills/quota/scripts/quota_report.py --report --days 14
   ```
2. Present the report and put the `[!]` flags **first**, each with one concrete,
   actionable recommendation (see the map below).
3. If the user wants the official quota figure, remind them it's only available
   via `/usage` (interactive).

## Recommendation map (real levers)

| Signal | Lever |
|--------|-------|
| Opus/Fable dominate spend | `/model sonnet` for the session — Sonnet handles most routine work at a fraction of the cost. Opus/Fable are worth it for hard reasoning, not mechanical edits. |
| Simple tasks with a lot of thinking | `/effort low` (or `medium`) for the session — current models use adaptive thinking, so effort is the lever (tuning `MAX_THINKING_TOKENS` no longer applies). |
| Cache hit <50% with high volume | Sessions with pauses >5 min lose the cache (5m TTL). Group work; use `/clear` instead of re-opening a huge session for one-off questions. |
| Subagents >40% of spend | Review unnecessary fan-outs and orphaned `agent-*` worktrees (`git worktree list`); pin subagents to a cheaper model where it fits. |
| Context growing unchecked | `/compact` manually before the auto-compact threshold; `/clear` when switching topics. |
| One project dominates with little to show | Check that project's background jobs / crons. |

## Interpretation notes

- "$eq" = API cost-equivalent, not a real invoice (fixed-quota plans). It's a
  reasonable proxy because the quota weighs models by cost.
- Dedup is per message id within each file; forked sessions (`--resume` into a
  new file) can double-count history, so totals are an upper bound.
- Prices are hard-coded in the `PRICES` table inside the script — update it if
  Anthropic reprices.
- The quota-nudge hook and the statusline read
  `~/.claude/cache/quota/summary.json`, which this script refreshes on each run.
- **Claude Code only.** On an Antigravity box there are no Claude Code
  transcripts, so the report prints "no Claude Code transcripts found yet".
