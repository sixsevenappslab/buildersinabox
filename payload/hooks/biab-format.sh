#!/usr/bin/env bash
# Builders in a Box formatter — PostToolUse hook on Edit|Write.
#
# Reads tool_input.file_path + cwd, formats the touched file with the project's
# formatter (chosen by extension, FEAT-015 §2.3). Language-agnostic with a clean
# no-op: if the tool is absent or the extension is unknown it changes nothing.
# Fail-open by design — always exit 0, never emit stdout, never a partial write
# (the formatters themselves write atomically and only run when present).

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0
biab_read_stdin
biab_hooks_disabled && exit 0

file_path="$(biab_json '.tool_input.file_path')"
[[ -n "$file_path" ]] || exit 0
biab_cd_cwd

ext="${file_path##*.}"
# No dot in the basename → no extension → unknown → no-op.
[[ "$ext" == "$file_path" ]] && exit 0

case ".${ext}" in
    .js|.jsx|.ts|.tsx|.json|.css|.md|.yaml|.yml)
        if biab_have prettier; then
            "$(biab_bin prettier)" --write "$file_path" >/dev/null 2>&1 || true
        fi ;;
    .py)
        if biab_have black; then
            black -q "$file_path" >/dev/null 2>&1 || true
        elif biab_have ruff; then
            ruff format "$file_path" >/dev/null 2>&1 || true
        fi ;;
    .go)
        if biab_have gofmt; then
            gofmt -w "$file_path" >/dev/null 2>&1 || true
        fi ;;
    .rs)
        if biab_have rustfmt; then
            rustfmt "$file_path" >/dev/null 2>&1 || true
        fi ;;
    .sh|.bash)
        if biab_have shfmt; then
            shfmt -w "$file_path" >/dev/null 2>&1 || true
        fi ;;
    *)
        : ;;  # unknown extension → no-op
esac

exit 0
