#!/usr/bin/env bash
# Builders in a Box formatter — Antigravity (agy) PostToolUse hook on file writes (FEAT-037).
#
# Translates Antigravity's toolCall payload (write_file, edit_file, write_to_file,
# replace_file_content) into the Claude-format payload consumed by biab-format.sh,
# then prints `{}` as expected by Antigravity PostToolUse hooks. Fail-open.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0
biab_read_stdin
biab_hooks_disabled && exit 0

command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "${BIAB_STDIN:-}" | jq -r 'try (.toolCall.name | select(type == "string")) catch empty' 2>/dev/null || true)"
case "$tool" in
    write_file|edit_file|write_to_file|replace_file_content)
        target="$(printf '%s' "${BIAB_STDIN:-}" | jq -r '
            try ([.toolCall.args.Path, .toolCall.args.TargetFile, .toolCall.args.AbsolutePath, .toolCall.args.path, .toolCall.args.file_path]
                 | map(select(type == "string" and length > 0)) | first // empty) catch empty' 2>/dev/null || true)"
        cwd="$(printf '%s' "${BIAB_STDIN:-}" | jq -r 'try (.workspacePaths[0] | select(type == "string")) catch empty' 2>/dev/null || true)"
        if [[ -n "$target" ]]; then
            jq -cn --arg fp "$target" --arg cwd "${cwd:-$PWD}" '{cwd:$cwd,tool_input:{file_path:$fp}}' \
                | "${HOOK_DIR}/biab-format.sh" >/dev/null 2>&1 || true
        fi
        ;;
esac

printf '{}\n'
exit 0
