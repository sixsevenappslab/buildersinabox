#!/usr/bin/env bash
# AI CLI abstraction. Source after lib/common.sh.
# Resolves the chosen CLI (claude or antigravity) and exposes a uniform
# interface the rest of the payload uses regardless of which one is installed.

set -euo pipefail

# Valid CLI identifiers. Codex is deferred to v1.x (no OAuth device flow yet).
# The second slot used to be Google's consumer CLI, retired on 2026-06-18 and
# replaced by its successor, the Antigravity CLI (`agy`).
BIB_SUPPORTED_AI_CLIS=("claude" "antigravity")

# Resolve the chosen CLI: argument > env var > state file > default.
ai_cli_resolve() {
    local from_arg="${1:-}"
    local chosen=""

    if [[ -n "$from_arg" ]]; then
        chosen="$from_arg"
    elif [[ -n "${BIB_AI_CLI:-}" ]]; then
        chosen="$BIB_AI_CLI"
    else
        chosen="$(state_get '.ai_cli')"
    fi

    if [[ -z "$chosen" ]]; then
        chosen="claude"
    fi

    ai_cli_validate "$chosen"
    printf '%s' "$chosen"
}

# Validate a CLI identifier or die.
ai_cli_validate() {
    local candidate="$1"
    local supported
    for supported in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
        [[ "$candidate" == "$supported" ]] && return 0
    done
    die "unsupported ai-cli: '$candidate' (supported: ${BIB_SUPPORTED_AI_CLIS[*]})"
}

# Persist the chosen CLI in the state file.
ai_cli_persist() {
    local cli="$1"
    ai_cli_validate "$cli"
    state_set '.ai_cli' "\"$cli\""
    log "ai_cli set to: $cli"
}

# Print the path to the install script for a CLI.
ai_cli_install_script() {
    local cli="$1"
    ai_cli_validate "$cli"
    case "$cli" in
        claude)      printf '%s' "install/40-claude-code.sh" ;;
        antigravity) printf '%s' "install/41-antigravity-cli.sh" ;;
    esac
}
