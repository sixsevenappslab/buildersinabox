#!/usr/bin/env bash
# Shared helpers for the Builders in a Box Claude Code hooks.
# Source this from each hook script; do not execute it directly.
#
# Every hook reads ONE JSON object on stdin (the Claude Code hook payload) and
# either stays silent (exit 0 → normal flow) or prints a single JSON object.
# These helpers keep that contract cheap and fail-safe.

set -euo pipefail

# ---------------------------------------------------------------------------
# Kill-switch. BIAB_HOOKS_DISABLED=1 (env) OR a sentinel file turns every hook
# into an immediate no-op: ~/.claude/hooks-disabled (the original one) or the
# CLI-neutral ~/.biab/hooks-disabled (FEAT-042). Cheap, reversible, documented
# — the user turned the hooks off on purpose.
# Usage:  biab_hooks_disabled && exit 0
# ---------------------------------------------------------------------------
biab_hooks_disabled() {
    biab_hooks_disabled_in "${HOME:-/nonexistent}"
}

# biab_hooks_disabled_in <home> — the same switch, read from an explicit home.
# The installer and `biab status` run as root, where $HOME is root's, while the
# sentinel lives in the BOX USER's home (OF-07): they must pass that home.
biab_hooks_disabled_in() {
    local home="${1:-/nonexistent}"
    [[ "${BIAB_HOOKS_DISABLED:-0}" == "1" ]] && return 0
    [[ -e "${home}/.claude/hooks-disabled" ]] && return 0
    [[ -e "${home}/.biab/hooks-disabled" ]] && return 0
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

# ---------------------------------------------------------------------------
# The language of a permission-prompt reason (FEAT-045 T5).
#
# biab_hook_text <key> <english> prints the reason in the owner's language, or the
# English given. English is the literal at the call site, never a catalog read, so
# an English box pays one file read and a Spanish box one short-lived process; and it is called
# only when a hook is about to ask or deny, never on the pass-through path that runs
# on every tool call. It can only return text: whatever goes wrong (no state file, no
# library, a catalog that is missing, corrupt or exits, a key that is not there, a
# language the build does not offer) the answer is the English literal, and it never
# fails, so a decision made before it cannot turn into an allow. The work runs in a
# separate process with a time limit, never in the hook's own shell: a catalog is sourced
# code, and `kill -9 $$` or `sleep 30` in it must not stop the hook from saying deny
# (an exit 1 from a hook is a non-blocking error to Claude Code, that is, an allow, and
# Codex kills a hook at 10 s).
# ---------------------------------------------------------------------------
biab_hook_text() {
    local key="$1" english="$2" out=""
    # English, the common case, costs one file read and no fork.
    if _biab_hook_is_english; then
        printf '%s' "$english"
        return 0
    fi
    # Anything else: a separate process with a hard limit (text-lookup.sh). A catalog or library that hangs, kills
    # "its" shell, closes stdout or writes garbage costs at most the limit and leaves the English text; `timeout`
    # kills the whole process group, so a background child cannot keep the pipe open either.
    out="$(timeout -s KILL 0.7 bash --noprofile --norc "${BASH_SOURCE[0]%/*}/text-lookup.sh" "$key" 2>/dev/null)" || out=""
    out="${out:0:2000}"
    printf '%s' "${out:-$english}"
}

# Is the language English as far as the state file and the environment say? A state file this misreads
# still gets the full check in text-lookup.sh.
_biab_hook_is_english() {
    local f="${BIB_STATE_FILE:-/var/lib/buildersinabox/state.json}" s=""
    if [[ -r "$f" ]]; then s="$(<"$f")" || s=""; fi
    if [[ "$s" =~ \"lang\"[[:space:]]*:[[:space:]]*\"([a-z]*)\" ]]; then
        [[ "${BASH_REMATCH[1]}" == "en" ]]
    else
        [[ "${BIB_LANG:-en}" == "en" ]]
    fi
}

# The prefixes of the guard reasons: "<prefix>: <reason>". blocked | confirm.
biab_guard_prefix() {
    case "$1" in
        blocked) biab_hook_text hook.guard.blocked "Builders in a Box guardrail blocked a destructive command" ;;
        *)       biab_hook_text hook.guard.confirm "Builders in a Box guardrail wants confirmation" ;;
    esac
}
biab_secret_prefix() {
    case "$1" in
        blocked) biab_hook_text hook.secret.blocked "Builders in a Box secret guard blocked a secret-file read" ;;
        *)       biab_hook_text hook.secret.confirm "Builders in a Box secret guard wants confirmation" ;;
    esac
}

# biab_cd_cwd — cd into the payload's cwd when present and valid (best-effort),
# so project-local tools and configs resolve. Never fails the hook.
biab_cd_cwd() {
    local cwd
    cwd="$(biab_json '.cwd')"
    [[ -n "$cwd" && -d "$cwd" ]] && cd "$cwd" 2>/dev/null || true
}
