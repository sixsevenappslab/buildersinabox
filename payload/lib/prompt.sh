#!/usr/bin/env bash
# TUI prompt helpers. Source after lib/common.sh.
# Designed for a plain console attached to the mini PC. No redraws,
# no ncurses, no color escapes — just clear labels and blank lines so
# the user can read from the screen while typing on their phone.

set -euo pipefail

# Where to read interactive input from. Default to /dev/tty (real console).
# Tests can set BIB_PROMPT_INPUT=/dev/stdin to drive the wizard from a heredoc.
BIB_PROMPT_INPUT="${BIB_PROMPT_INPUT:-/dev/tty}"

_bib_read_line() {
    local __varname="$1"
    local __line=""
    local __rc=0
    if [[ "$BIB_PROMPT_INPUT" == "/dev/stdin" ]] || [[ "$BIB_PROMPT_INPUT" == "/dev/fd/0" ]]; then
        # Read directly from inherited stdin (test mode: piped/heredoc).
        IFS= read -r __line || __rc=$?
    elif [[ -r "$BIB_PROMPT_INPUT" ]]; then
        IFS= read -r __line < "$BIB_PROMPT_INPUT" || __rc=$?
    else
        IFS= read -r __line || __rc=$?
    fi
    printf -v "$__varname" '%s' "$__line"
    # bash `read` returns non-zero when the last line of input has no trailing
    # newline, even though it did capture data. Treat that as a successful
    # read — it matches how a real user's last keystroke would look.
    if [[ "$__rc" -ne 0 && -n "$__line" ]]; then
        __rc=0
    fi
    return "$__rc"
}

# Print a header for a wizard step.
prompt_header() {
    printf '\n\n======================================================================\n'
    printf '  %s\n' "$*"
    printf '======================================================================\n\n'
}

# Print an URL in isolation so it's easy to read off the screen.
prompt_url() {
    local label="${1:-Open this URL on your phone:}"
    local url="$2"
    printf '\n'
    printf '%s\n' "$label"
    printf '\n'
    printf '    %s\n' "$url"
    printf '\n'
}

# Wait for the user to confirm a step is done. Blocks until Enter is pressed.
# Stdin is /dev/tty so it works even if the script is being piped.
prompt_confirm() {
    local msg="${1:-Press Enter when you have completed the step above.}"
    printf '%s\n' "$msg"
    # Read a single line. Discard whatever the user typed. EOF is acceptable
    # here — we just wanted to wait for the user to acknowledge.
    local _discard
    _bib_read_line _discard || true
}

# Ask a single-choice question. Echoes the chosen value to stdout.
#   prompt_choice "Pick a CLI" "claude" "gemini"
# The first option is treated as the default if the user just presses Enter.
# prompt_choice writes the chosen value into BIB_PROMPT_VALUE.
# Returns non-zero on EOF.
prompt_choice() {
    local question="$1"
    shift
    local options=("$@")
    local default="${options[0]}"

    BIB_PROMPT_VALUE=""
    printf '%s\n' "$question"
    local i=1
    for opt in "${options[@]}"; do
        if [[ "$opt" == "$default" ]]; then
            printf '  %d) %s [default]\n' "$i" "$opt"
        else
            printf '  %d) %s\n' "$i" "$opt"
        fi
        i=$((i + 1))
    done

    while true; do
        printf '\nYour choice [%s]: ' "$default"
        local answer=""
        if ! _bib_read_line answer; then
            printf '\n' >&2
            warn "prompt_choice: input stream ended unexpectedly"
            return 1
        fi
        if [[ -z "$answer" ]]; then
            BIB_PROMPT_VALUE="$default"
            return 0
        fi
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#options[@]} )); then
            BIB_PROMPT_VALUE="${options[answer-1]}"
            return 0
        fi
        for opt in "${options[@]}"; do
            if [[ "$answer" == "$opt" ]]; then
                BIB_PROMPT_VALUE="$opt"
                return 0
            fi
        done
        printf 'Sorry, "%s" is not a valid choice. Try again.\n' "$answer" >&2
    done
}

# Ask for a free-text value, validated by a regex.
#   prompt_text "Project name" '^[a-z][a-z0-9-]{1,30}$' "Use lowercase, digits, hyphens. Start with a letter."
# prompt_text writes the user's answer into the global variable
# BIB_PROMPT_VALUE on success, and returns 0. On EOF or other read failure
# it returns non-zero so callers can propagate via set -e.
#
# Using a global var instead of command substitution avoids the bash gotcha
# where `local var=$(prompt)` masks the inner command's exit code and the
# subshell's `die` cannot abort the parent script.
prompt_text() {
    local question="$1"
    local pattern="${2:-.*}"
    local hint="${3:-}"

    BIB_PROMPT_VALUE=""
    while true; do
        printf '%s\n' "$question"
        [[ -n "$hint" ]] && printf '(%s)\n' "$hint"
        printf '> '
        local answer=""
        if ! _bib_read_line answer; then
            printf '\n' >&2
            warn "prompt_text: input stream ended unexpectedly"
            return 1
        fi
        if [[ -z "$answer" ]]; then
            printf 'A value is required. Try again.\n\n' >&2
            continue
        fi
        if [[ "$answer" =~ $pattern ]]; then
            BIB_PROMPT_VALUE="$answer"
            return 0
        fi
        printf 'Sorry, "%s" does not match the expected format. Try again.\n\n' "$answer" >&2
    done
}

# Reserved project names that conflict with workspace folders.
BIB_RESERVED_PROJECT_NAMES=("platform" "stratops" "projects")

# Validate a project name slug. Echoes nothing; returns 0 if valid, 1 otherwise.
project_name_is_valid() {
    local name="$1"
    [[ "$name" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || return 1
    local reserved
    for reserved in "${BIB_RESERVED_PROJECT_NAMES[@]}"; do
        [[ "$name" == "$reserved" ]] && return 1
    done
    return 0
}

# prompt_project_name writes the validated name into BIB_PROMPT_VALUE.
# Returns non-zero on EOF.
prompt_project_name() {
    local hint="lowercase letters, digits and hyphens. 2-31 chars. Cannot be platform/stratops/projects."
    local pattern='^[a-z][a-z0-9-]{1,30}$'
    while true; do
        prompt_text "Pick a name for your first project:" "$pattern" "$hint" || return 1
        if project_name_is_valid "$BIB_PROMPT_VALUE"; then
            return 0
        fi
        printf '"%s" is a reserved name. Try again.\n\n' "$BIB_PROMPT_VALUE" >&2
    done
}
