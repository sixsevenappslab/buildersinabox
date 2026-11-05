#!/usr/bin/env bash
# Builders in a Box quota nudge — UserPromptSubmit hook.
#
# When the session runs on an expensive model (Opus/Fable/Mythos) and a cached
# usage summary exists, inject a once-per-session-per-day reminder with the
# week's cost-equivalent burn so the user can decide to downgrade (/model
# sonnet, /effort low). Neutral by design: BIAB informs cost, it does not
# impose a model policy.
#
# Contract (mirrors the other BIAB hooks):
#   - exit 0 on EVERY path — a nudge must never block or dirty a prompt.
#   - the only stdout is a single JSON object with additionalContext, and only
#     in the trigger case.
#   - heavy work (parsing transcripts) runs in the BACKGROUND, never inline.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

# jq is required to read the summary and emit JSON; degrade to a no-op without it.
command -v jq >/dev/null 2>&1 || exit 0

CACHE_DIR="${HOME:-/nonexistent}/.claude/cache/quota"
SUMMARY="${CACHE_DIR}/summary.json"
SCRIPT="${HOME:-/nonexistent}/.claude/skills/quota/scripts/quota_report.py"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

biab_read_stdin
biab_hooks_disabled && exit 0   # sentinel may live under HOME; re-check post-read

transcript_path="$(biab_json '.transcript_path')"
session_id="$(biab_json '.session_id')"

# Kick a background refresh when the summary is missing or older than 6h.
# flock prevents a pileup if two prompts fire at once; nohup + & keeps it off
# the hot path. Never blocks the prompt.
if command -v python3 >/dev/null 2>&1 && [ -f "$SCRIPT" ]; then
    if [ ! -f "$SUMMARY" ] || [ -n "$(find "$SUMMARY" -mmin +360 2>/dev/null)" ]; then
        ( flock -n 9 && nohup python3 "$SCRIPT" --refresh >/dev/null 2>&1 & ) \
            9>"${CACHE_DIR}/refresh.lock" 2>/dev/null || true
    fi
fi

# No cached summary yet (fresh box, first sessions) → stay silent.
[ -f "$SUMMARY" ] || exit 0
[ -n "$transcript_path" ] && [ -f "$transcript_path" ] || exit 0

# Current model from the transcript tail (last assistant message carrying one).
# Failure-safe: the transcript can vanish / rotate / turn unreadable between the
# [ -f ] check above and this read (a real TOCTOU window). Under `pipefail`,
# `tac` failing — or `jq` catching SIGPIPE when `head -1` closes the pipe early —
# would propagate a non-zero status, and `set -e` would kill the hook with a
# non-zero exit, violating the exit-0 contract. Swallow it with `|| true` and
# bail quietly when no model could be read.
model="$(tac "$transcript_path" 2>/dev/null \
    | head -500 \
    | jq -r -R 'fromjson? | select(.message.model != null) | .message.model' 2>/dev/null \
    | head -1)" || true
[ -n "${model:-}" ] || exit 0

# Only nudge on expensive models — Sonnet/Haiku sessions get nothing.
case "$model" in
    *opus* | *fable* | *mythos*) ;;
    *) exit 0 ;;
esac

# At most once per session per day.
marker="${CACHE_DIR}/nudged-$(date +%F)-${session_id:-nosession}"
[ -e "$marker" ] && exit 0
touch "$marker" 2>/dev/null || true
# Purge stale markers so the cache dir doesn't grow unbounded.
find "$CACHE_DIR" -name 'nudged-*' -mtime +2 -delete 2>/dev/null || true

read -r week heavy <<<"$(jq -r \
    '[(.week_cost // 0), ((.heavy_share_week // 0) * 100 | floor)] | @tsv' \
    "$SUMMARY" 2>/dev/null)"
[ -n "${week:-}" ] || exit 0

msg="This session runs on ${model}. Last 7 days: \$${week}eq burned, ${heavy}% on expensive models. For routine work consider /model sonnet or /effort low. Run the quota skill for a full breakdown."

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $m
  }
}'
