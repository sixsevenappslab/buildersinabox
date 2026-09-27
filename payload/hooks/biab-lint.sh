#!/usr/bin/env bash
# Builders in a Box linter feedback — PostToolUse hook on Edit|Write.
#
# Reads tool_input.file_path + cwd, runs the project's linter (chosen by
# extension, FEAT-015 §2.3) and returns any findings to the agent through the
# NON-BLOCKING additionalContext channel:
#   {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}
# Fail-open: always exit 0, NEVER exit 2 (that would block the edit). Silent
# (no additionalContext) when the file is clean or no linter is available.

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
[[ "$ext" == "$file_path" ]] && exit 0

out=""
case ".${ext}" in
    .js|.jsx|.ts|.tsx|.json|.css|.md|.yaml|.yml)
        shopt -s nullglob
        eslint_cfg=(.eslintrc* eslint.config.*)
        shopt -u nullglob
        if (( ${#eslint_cfg[@]} > 0 )) && biab_have eslint; then
            out="$("$(biab_bin eslint)" --format compact "$file_path" 2>&1 || true)"
        fi ;;
    .py)
        if biab_have ruff; then
            # -q: print diagnostics only (no "All checks passed!" noise).
            out="$(ruff check -q "$file_path" 2>&1 || true)"
        elif biab_have flake8; then
            out="$(flake8 "$file_path" 2>&1 || true)"
        fi ;;
    .go)
        if biab_have gofmt; then
            out="$(gofmt -l "$file_path" 2>&1 || true)"
        fi ;;
    .rs)
        if biab_have cargo-clippy || biab_have clippy-driver; then
            out="$(cargo clippy 2>&1 || true)"
        fi ;;
    .sh|.bash)
        if biab_have shellcheck; then
            out="$(shellcheck -f gcc "$file_path" 2>&1 || true)"
        fi ;;
    *)
        : ;;  # unknown extension → no-op
esac

# Emit additionalContext only when the linter produced non-whitespace output.
if [[ -n "${out//[[:space:]]/}" ]]; then
    jq -cn --arg c "$out" \
        '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
fi

exit 0
