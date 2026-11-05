#!/usr/bin/env bash
# Builders in a Box guardrail — Claude Code PreToolUse hook on Bash.
#
# A thin wrapper (FEAT-042): it reads Claude's payload (tool_input.command), asks
# biab_guard_decide (guardrail-rules.sh, the one list of patterns) and prints
# Claude's answer.
#   - deny → permissionDecision:"deny" (exit 0)
#   - ask  → permissionDecision:"ask"  (exit 0)
#   - pass → exit 0 with NO stdout (normal permission flow)
# Fail-closed ACOTADO: unparseable input / no command → "ask" (never a blind
# deny that would brick the box, never a silent allow that would let a
# destructive command through).

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

emit() {  # <deny|ask> <prefix> <reason>
    jq -cn --arg d "$1" --arg r "$2: $3" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
    exit 0
}

# Without its rules the guard cannot judge anything. A failed `source` under set -e would
# exit 1, which Claude Code treats as a non-blocking error: every command would pass in
# silence. Ask instead (the same bounded fail-closed as for an unreadable payload).
# shellcheck source=./guardrail-rules.sh
source "${HOOK_DIR}/guardrail-rules.sh" 2>/dev/null \
    || emit ask "Builders in a Box guardrail wants confirmation" "guard rules missing or unreadable (run: biab status)"

biab_read_stdin
biab_hooks_disabled && exit 0   # sentinel may live under HOME; re-check post-read

cmd="$(biab_json '.tool_input.command')"
# Fail-closed acotado: no intelligible command (unparseable stdin or absent
# field) → ask. Never deny-blind, never silent-allow.
[[ -n "$cmd" ]] || emit ask "Builders in a Box guardrail wants confirmation" "could not read the command from the tool input"

biab_guard_decide "$cmd"
case "$BIAB_GUARD_DECISION" in
    deny) emit deny "Builders in a Box guardrail blocked a destructive command" "$BIAB_GUARD_REASON" ;;
    ask)  emit ask  "Builders in a Box guardrail wants confirmation" "$BIAB_GUARD_REASON" ;;
esac
exit 0
