#!/usr/bin/env bash
# Builders in a Box guardrail — Antigravity (agy) PreToolUse hook on run_command (FEAT-042).
#
# A thin wrapper like biab-guardrail.sh: it reads agy's payload
# (toolCall.name, toolCall.args.CommandLine), asks biab_guard_decide (guardrail-rules.sh,
# the one list of patterns) and prints agy's answer, {"decision","reason"}:
#   - deny → {"decision":"deny",...}
#   - ask  → {"decision":"ask",...}   (agy has `ask`; Codex does not)
#   - pass → NOTHING. Not {"decision":"allow"}: if agy took `allow` as "no need to ask",
#            its own prompts would vanish in silence. What agy does with an empty answer
#            is not documented by Google; the hardware pass measures it (FEAT-042 T6).
# Any tool other than run_command prints nothing. An unreadable payload, or one in
# another shape, asks (the bounded fail-closed of Claude's wrapper): never a blind deny,
# never a silent pass. A command given as an array of strings is joined and judged.
# Not yet declared as a guard for anyone: see ai-cli.sh (decision D4).

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

emit() {  # <deny|ask> <prefix> <reason>
    jq -cn --arg d "$1" --arg r "$2: $3" '{decision:$d,reason:$r}'
    exit 0
}

# Without its rules the guard cannot judge anything: ask, never exit non-zero.
# shellcheck source=./guardrail-rules.sh
source "${HOOK_DIR}/guardrail-rules.sh" 2>/dev/null \
    || emit ask "Builders in a Box guardrail wants confirmation" "guard rules missing or unreadable (run: biab status)"

biab_read_stdin
biab_hooks_disabled && exit 0   # sentinel may live under HOME; re-check post-read

# Empty when the payload is not JSON or toolCall.name is absent or not a string.
tool="$(printf '%s' "${BIAB_STDIN:-}" | jq -r 'try (.toolCall.name | select(type == "string")) catch empty' 2>/dev/null || true)"
if [[ -n "$tool" && "$tool" != run_command ]]; then exit 0; fi

cmd="$(printf '%s' "${BIAB_STDIN:-}" | jq -r '
    try (.toolCall.args.CommandLine
         | if type == "string" then .
           elif type == "array" and all(.[]; type == "string") then join(" ")
           else empty end) catch empty' 2>/dev/null || true)"
[[ "$tool" == run_command && -n "$cmd" ]] \
    || emit ask "Builders in a Box guardrail wants confirmation" "could not read the command from the tool input"

biab_guard_decide "$cmd"
case "$BIAB_GUARD_DECISION" in
    deny) emit deny "Builders in a Box guardrail blocked a destructive command" "$BIAB_GUARD_REASON" ;;
    ask)  emit ask  "Builders in a Box guardrail wants confirmation" "$BIAB_GUARD_REASON" ;;
esac
exit 0
