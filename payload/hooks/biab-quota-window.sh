#!/usr/bin/env bash
# Builders in a Box 5h quota-window pace nudge — UserPromptSubmit hook (FEAT-037).
#
# Informs the user when the rolling 5-hour window is burning cost-equivalent ($eq)
# much faster than their typical active 5-hour window over the last 14 days.
# Complements biab-quota-nudge.sh (which looks at model family and 7-day burn).
#
# Contract:
#   - Honours biab_hooks_disabled (kill-switch) before and after reading stdin.
#   - Fail-open (exit 0 with empty stdout/stderr) on every error path, missing
#     watchdog script, timeout (5s cap), or non-alert status.
#   - Throttled per session: nudges once per session and only re-nudges if the
#     burn ratio escalates by at least QUOTA_RENUDGE_FACTOR (default 1.5x).
#   - No network calls, no privilege elevation.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

biab_read_stdin
biab_hooks_disabled && exit 0   # sentinel may live under HOME; re-check post-read

[[ -n "${BIAB_STDIN:-}" ]] || exit 0

# Require a valid JSON object carrying a session_id or prompt field (fail-open on {} / garbage).
printf '%s' "${BIAB_STDIN}" | jq -e '
    type == "object" and (
        ((.session_id // "") | type == "string" and length > 0) or
        ((.prompt // "") | type == "string" and length > 0)
    )
' >/dev/null 2>&1 || exit 0

session_id="$(printf '%s' "${BIAB_STDIN}" | jq -r 'try (.session_id | select(type == "string")) catch empty' 2>/dev/null || true)"

SCRIPT="${QUOTA_WATCHDOG:-${HOME:-/nonexistent}/.claude/skills/quota/scripts/quota_watchdog.py}"
CACHE_DIR="${QUOTA_CACHE_DIR:-${HOME:-/nonexistent}/.claude/cache/quota}"
RENUDGE_FACTOR="${QUOTA_RENUDGE_FACTOR:-1.5}"

[[ -f "$SCRIPT" ]] || exit 0

mkdir -p "$CACHE_DIR" 2>/dev/null || true

# Cap runtime at 5s so a cold scan or hung script never blocks a prompt (Q-4, E-30).
status_json="$(timeout 5 python3 -B "$SCRIPT" --check 2>/dev/null | tr -d '\0' || true)"
[[ -n "$status_json" ]] || exit 0

status="$(printf '%s' "$status_json" | jq -r 'try (.status | select(type == "string")) catch empty' 2>/dev/null || true)"
[[ "$status" == "alert" ]] || exit 0

read -r cur base ratio <<<"$(printf '%s' "$status_json" \
    | jq -r 'try ([(.window_5h_cost // 0), (.baseline_active_5h // 0), (.ratio // 0)] | @tsv) catch empty' 2>/dev/null || true)"
[[ -n "${cur:-}" && -n "${base:-}" && -n "${ratio:-}" ]] || exit 0

# Per-session throttle with escalation: store the last nudged ratio and only
# speak again if the current ratio reached >= RENUDGE_FACTOR * last_ratio.
marker="${CACHE_DIR}/window-nudged-${session_id:-nosession}"
if [[ -f "$marker" ]]; then
    last_ratio="$(cat "$marker" 2>/dev/null || true)"
    escalated="$(awk -v now="$ratio" -v last="$last_ratio" -v f="$RENUDGE_FACTOR" \
        'BEGIN { if (now+0 > 0 && last+0 > 0 && now+0 >= (last+0) * f) print "yes" }' 2>/dev/null || true)"
    [[ "$escalated" == "yes" ]] || exit 0
fi

printf '%s' "$ratio" > "$marker" 2>/dev/null || true
find "$CACHE_DIR" -name 'window-nudged-*' -mtime +1 -delete 2>/dev/null || true

msg="5h quota window: \$${cur}eq burned (${ratio}x your typical active 5h pace of \$${base}eq). Data point, not a hard limit — continue if the task warrants it."

jq -cn --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $m
  }
}'
