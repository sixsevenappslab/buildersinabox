#!/usr/bin/env bash
# Shared helpers for the Builders in a Box Claude Code hooks.
# Source this from each hook script; do not execute it directly.
#
# Every hook reads ONE JSON object on stdin (the Claude Code hook payload) and
# either stays silent (exit 0 → normal flow) or prints a single JSON object.
# These helpers keep that contract cheap and fail-safe.

set -euo pipefail

# ---------------------------------------------------------------------------
# Kill-switch. BIAB_HOOKS_DISABLED=1 (env) OR the sentinel file
# ~/.claude/hooks-disabled turns every hook into an immediate no-op. Cheap,
# reversible, documented — the user turned the hooks off on purpose.
# Usage:  biab_hooks_disabled && exit 0
# ---------------------------------------------------------------------------
biab_hooks_disabled() {
    [[ "${BIAB_HOOKS_DISABLED:-0}" == "1" ]] && return 0
    [[ -e "${HOME:-/nonexistent}/.claude/hooks-disabled" ]] && return 0
    return 1
}

# Read all of stdin into BIAB_STDIN. Best-effort: never fails the hook.
biab_read_stdin() {
    BIAB_STDIN="$(cat 2>/dev/null || true)"
}

# biab_json <jq-filter> — pull a value out of BIAB_STDIN via jq. Prints the
# raw value, or an empty string on any parse error / absent field. Never throws
# (so an unparseable payload degrades to "field absent", not a crash).
biab_json() {
    printf '%s' "${BIAB_STDIN:-}" | jq -r "$1 // empty" 2>/dev/null || true
}

# biab_have <bin> — is <bin> runnable from here? Prefers a project-local
# node_modules/.bin/<bin> (resolved from the current dir) over a global one.
biab_have() {
    local bin="$1"
    [[ -x "./node_modules/.bin/${bin}" ]] && return 0
    command -v "$bin" >/dev/null 2>&1
}

# biab_bin <bin> — echo the path to invoke for <bin>, preferring the local one.
biab_bin() {
    local bin="$1"
    if [[ -x "./node_modules/.bin/${bin}" ]]; then
        printf '%s' "./node_modules/.bin/${bin}"
    else
        printf '%s' "$bin"
    fi
}

# biab_cd_cwd — cd into the payload's cwd when present and valid (best-effort),
# so project-local tools and configs resolve. Never fails the hook.
biab_cd_cwd() {
    local cwd
    cwd="$(biab_json '.cwd')"
    [[ -n "$cwd" && -d "$cwd" ]] && cd "$cwd" 2>/dev/null || true
}
