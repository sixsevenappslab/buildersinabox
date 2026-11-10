#!/usr/bin/env bash
# Builders in a Box secret-read guard — Claude Code PreToolUse hook on Bash (FEAT-037 / FEAT-044).
#
# Thin wrapper around secret-guard-rules.sh (the single source of truth across
# all four supported AI CLIs). Blocks or asks before shell commands read
# danger-zone / credential files (.env, secrets, auth tokens, SSH keys, security
# rules) whose stdout would otherwise be persisted in plaintext into the session
# transcript forever.
#
# Contract:
#   - Honours biab_hooks_disabled (kill-switch) before and after reading stdin.
#   - Fail-open (exit 0 with empty stdout/stderr) on empty, malformed, or `{}`
#     stdin, or when jq / python3 is unavailable.
#   - Emits permissionDecision:"deny" when permission_mode == "bypassPermissions"
#     (unattended run), and permissionDecision:"ask" otherwise.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# shellcheck source=./secret-guard-rules.sh
source "${HOOK_DIR}/secret-guard-rules.sh" 2>/dev/null || exit 0

biab_read_stdin
biab_hooks_disabled && exit 0   # sentinel may live under HOME; re-check post-read

[[ -n "${BIAB_STDIN:-}" ]] || exit 0

cmd="$(printf '%s' "${BIAB_STDIN}" | jq -r 'try (.tool_input.command | select(type == "string")) catch empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

mode="$(printf '%s' "${BIAB_STDIN}" | jq -r 'try (.permission_mode | select(type == "string")) catch empty' 2>/dev/null || true)"

biab_secret_decide "$cmd" "$mode"
if [[ "$BIAB_SECRET_DECISION" == ask || "$BIAB_SECRET_DECISION" == deny ]]; then
    jq -cn --arg d "$BIAB_SECRET_DECISION" --arg r "$BIAB_SECRET_REASON" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
fi
exit 0
