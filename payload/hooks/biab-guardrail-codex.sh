#!/usr/bin/env bash
# Builders in a Box guardrail — Codex CLI PreToolUse hook on Bash (FEAT-042).
#
# A thin wrapper like biab-guardrail.sh: it reads Codex's payload
# (tool_input.command), asks biab_guard_decide (guardrail-rules.sh, the one list of
# patterns) and prints the answer Codex understands.
#   - deny → permissionDecision:"deny" (exit 0)
#   - ask  → NOTHING. Codex parses "ask" but marks the hook failed and lets the call
#            continue, so printing it would only add noise; Codex's own approval policy
#            and sandbox decide (decision D6, FEAT-042 §2 (b)). Never "allow" either.
#   - pass → nothing
# An unreadable payload never blocks Codex wholesale: exit 0, no output, one line in
# ~/.biab/guard.log (never the command text). Codex continues when a hook fails, so
# silence is the only safe answer here; Claude's wrapper can ask, this one cannot.
# A command given as an array of strings is joined with spaces and judged (Codex may
# send argv); Claude's wrapper passes such an input, this one is stricter (EC-04).

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

# log_unreadable <reason>: one line, never the payload. Never follows a link, never
# grows past 1 MB, creates ~/.biab only as a plain directory, and never fails the hook.
log_unreadable() {
    local d="${HOME:-}/.biab" f="${HOME:-}/.biab/guard.log" size
    [[ -n "${HOME:-}" && ! -L "$d" && ! -L "$f" ]] || return 0
    [[ -d "$d" ]] || mkdir -m 0700 -- "$d" 2>/dev/null || return 0
    [[ ! -L "$d" ]] || return 0
    if [[ -e "$f" ]]; then
        [[ -f "$f" ]] || return 0
        size="$(stat -c %s -- "$f" 2>/dev/null || echo 0)"
        [[ "$size" =~ ^[0-9]+$ && "$size" -lt 1048576 ]] || return 0
    fi
    printf '%s codex %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo unknown-time)" "$1" >> "$f" 2>/dev/null || true
}

# Without its rules the guard cannot judge anything: say so in the log and let Codex
# carry on (it cannot be asked to confirm); `biab status` reports the state as blocked.
# shellcheck source=./guardrail-rules.sh
source "${HOOK_DIR}/guardrail-rules.sh" 2>/dev/null \
    || { log_unreadable "rules-missing"; exit 0; }

biab_read_stdin
biab_hooks_disabled && exit 0   # sentinel may live under HOME; re-check post-read

# A string, or an array of strings joined with spaces. Anything else (absent, null,
# empty, a number, an object) is unreadable.
cmd="$(printf '%s' "${BIAB_STDIN:-}" | jq -r '
    try (.tool_input.command
         | if type == "string" then .
           elif type == "array" and all(.[]; type == "string") then join(" ")
           else empty end) catch empty' 2>/dev/null || true)"
if [[ -z "$cmd" ]]; then
    log_unreadable "unreadable-input"
    exit 0
fi

biab_guard_decide "$cmd"
if [[ "$BIAB_GUARD_DECISION" == deny ]]; then
    jq -cn --arg r "Builders in a Box guardrail blocked a destructive command: ${BIAB_GUARD_REASON}" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
exit 0
