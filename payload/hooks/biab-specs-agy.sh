#!/usr/bin/env bash
# Builders in a Box pending-specs surface — Antigravity (agy) SessionStart hook (FEAT-037).
#
# Translates Antigravity's SessionStart payload (.workspacePaths[0]) into the
# payload expected by biab-specs.sh and wraps any resulting additionalContext
# into Antigravity's `injectSteps` systemMessage envelope. Fail-open.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0
biab_read_stdin
biab_hooks_disabled && exit 0

command -v jq >/dev/null 2>&1 || exit 0

cwd="$(printf '%s' "${BIAB_STDIN:-}" | jq -r 'try ((.workspacePaths[0] // .cwd) | select(type == "string")) catch empty' 2>/dev/null || true)"
[[ -n "$cwd" && -d "$cwd" ]] || cwd="$PWD"

out="$(jq -cn --arg c "$cwd" '{cwd:$c}' | "${HOOK_DIR}/biab-specs.sh" 2>/dev/null || true)"
if [[ -n "$out" ]]; then
    msg="$(printf '%s' "$out" | jq -r 'try (.hookSpecificOutput.additionalContext | select(type == "string" and length > 0)) catch empty' 2>/dev/null || true)"
    if [[ -n "$msg" ]]; then
        jq -cn --arg m "$msg" '{injectSteps:[{systemMessage:{systemMessage:$m}}]}'
        exit 0
    fi
fi

printf '{}\n'
exit 0
