#!/usr/bin/env bash
# Builders in a Box secret-read guard — Antigravity (agy) PreToolUse hook (FEAT-037 / FEAT-044).
#
# Thin wrapper around secret-guard-rules.sh (the single source of truth).
# Covers run_command (string or argv array) as well as direct file-read tools
# (read_file, view_file) on danger-zone / credential paths.
# Emits {"decision":"ask"|"deny","reason":"..."} on match; stays silent (exit 0)
# on pass. If secret-guard-rules.sh is missing or unreadable, asks for confirmation.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

command -v jq >/dev/null 2>&1 || exit 0

emit() {  # <deny|ask> <reason>
    jq -cn --arg d "$1" --arg r "$2" '{decision:$d,reason:$r}'
    exit 0
}

# shellcheck source=./secret-guard-rules.sh
source "${HOOK_DIR}/secret-guard-rules.sh" 2>/dev/null \
    || emit ask "Builders in a Box secret guard wants confirmation: secret-guard-rules.sh missing or unreadable (run: biab status)"

biab_read_stdin
biab_hooks_disabled && exit 0

[[ -n "${BIAB_STDIN:-}" ]] || exit 0

tool="$(printf '%s' "${BIAB_STDIN}" | jq -r 'try (.toolCall.name | select(type == "string")) catch empty' 2>/dev/null || true)"
[[ -n "$tool" ]] || exit 0

case "$tool" in
    run_command)
        cmd="$(printf '%s' "${BIAB_STDIN}" | jq -r '
            try (.toolCall.args.CommandLine
                 | if type == "string" then .
                   elif type == "array" and all(.[]; type == "string") then join(" ")
                   else empty end) catch empty' 2>/dev/null || true)"
        [[ -n "$cmd" ]] || exit 0
        biab_secret_decide "$cmd"
        ;;
    read_file|view_file)
        target="$(printf '%s' "${BIAB_STDIN}" | jq -r '
            try ([.toolCall.args.Path, .toolCall.args.TargetFile, .toolCall.args.AbsolutePath, .toolCall.args.path, .toolCall.args.file_path]
                 | map(select(type == "string" and length > 0)) | first // empty) catch empty' 2>/dev/null || true)"
        [[ -n "$target" ]] || exit 0
        biab_secret_path_decide "$target"
        ;;
    *)
        exit 0
        ;;
esac

if [[ "$BIAB_SECRET_DECISION" == ask || "$BIAB_SECRET_DECISION" == deny ]]; then
    emit "$BIAB_SECRET_DECISION" "$BIAB_SECRET_REASON"
fi
exit 0
