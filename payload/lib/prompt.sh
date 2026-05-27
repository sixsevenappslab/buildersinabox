#!/usr/bin/env bash
# TUI prompt helpers. Source after lib/common.sh.
# Designed for a plain console attached to the mini PC. No redraws,
# no ncurses, no color escapes — just clear labels and blank lines so
# the user can read from the screen while typing on their phone.

set -euo pipefail

# Where to read interactive input from. Default to /dev/tty (real console).
# Tests can set BIB_PROMPT_INPUT=/dev/stdin to drive the wizard from a heredoc.
BIB_PROMPT_INPUT="${BIB_PROMPT_INPUT:-/dev/tty}"

# Color palette. Disabled automatically when stdout isn't a tty (so dryrun
# tests, log pipes, redirections, etc. stay clean ASCII).
# shellcheck disable=SC2034  # palette declared for use across sourcing scripts
if [[ -t 1 ]] && [[ "${BIB_NO_COLOR:-0}" != "1" ]]; then
    BIB_BOLD=$'\e[1m'
    BIB_DIM=$'\e[2m'
    BIB_RED=$'\e[31m'
    BIB_GREEN=$'\e[32m'
    BIB_YELLOW=$'\e[33m'
    BIB_BLUE=$'\e[34m'
    BIB_MAGENTA=$'\e[35m'
    BIB_CYAN=$'\e[36m'
    BIB_BRIGHT_YELLOW=$'\e[93m'
    BIB_BRIGHT_CYAN=$'\e[96m'
    BIB_BRIGHT_MAGENTA=$'\e[95m'
    BIB_RESET=$'\e[0m'
else
    BIB_BOLD=""
    BIB_DIM=""
    BIB_RED=""
    BIB_GREEN=""
    BIB_YELLOW=""
    BIB_BLUE=""
    BIB_MAGENTA=""
    BIB_CYAN=""
    BIB_BRIGHT_YELLOW=""
    BIB_BRIGHT_CYAN=""
    BIB_BRIGHT_MAGENTA=""
    BIB_RESET=""
fi

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

# Apply a bigger, readable console font to tty1 so the wizard is legible
# from a couch. Silently no-ops if setfont or the font file aren't present.
# Also persists the change so future console sessions keep the bigger font.
apply_wizard_font() {
    local font="/usr/share/consolefonts/Lat15-TerminusBold24x12.psf.gz"
    if [[ -f "$font" ]] && command -v setfont >/dev/null 2>&1; then
        setfont "$font" 2>/dev/null || true
    fi
    if [[ -w /etc/default/console-setup ]]; then
        sed -i 's|^FONTFACE=.*|FONTFACE="TerminusBold"|; s|^FONTSIZE=.*|FONTSIZE="24x12"|' \
            /etc/default/console-setup 2>/dev/null || true
        command -v setupcon >/dev/null 2>&1 && setupcon 2>/dev/null || true
    fi
}

# Print the personalised PACO welcome banner with color. ASCII art so it
# renders in any console font; the colors degrade gracefully on terminals
# without ANSI support (the helper above zeros them out).
wizard_banner() {
    printf '\n'
    printf '  %s+==============================================+%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|                                              |%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|%s          %s ____   _    ____ ___ %s              %s|%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD$BIB_BRIGHT_MAGENTA" "$BIB_RESET" "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|%s          %s|  _ \ / \  / ___/ _ \%s              %s|%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD$BIB_BRIGHT_MAGENTA" "$BIB_RESET" "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|%s          %s| |_) / _ \| |  | | | |%s             %s|%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD$BIB_BRIGHT_MAGENTA" "$BIB_RESET" "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|%s          %s|  __/ ___ \ |__| |_| |%s             %s|%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD$BIB_BRIGHT_MAGENTA" "$BIB_RESET" "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|%s          %s|_| /_/   \_\____\___/%s              %s|%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD$BIB_BRIGHT_MAGENTA" "$BIB_RESET" "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|                                              |%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|%s     %sWelcome to your Builders in a Box%s        %s|%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD" "$BIB_RESET" "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s|                                              |%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '  %s+==============================================+%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET"
    printf '\n'
}

# Print a header for a wizard step, framed in bright cyan with a bold title.
prompt_header() {
    local line='======================================================================'
    printf '\n\n%s%s%s\n' "$BIB_BRIGHT_CYAN" "$line" "$BIB_RESET"
    printf '  %s%s%s\n' "$BIB_BOLD" "$*" "$BIB_RESET"
    printf '%s%s%s\n\n' "$BIB_BRIGHT_CYAN" "$line" "$BIB_RESET"
}

# Print an URL in isolation, highlighted so the user immediately spots it
# among the surrounding text.
prompt_url() {
    local label="${1:-Open this URL on your phone:}"
    local url="$2"
    printf '\n'
    printf '%s%s%s\n' "$BIB_DIM" "$label" "$BIB_RESET"
    printf '\n'
    printf '    %s>%s  %s%s%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD$BIB_BRIGHT_YELLOW" "$url" "$BIB_RESET"
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

# prompt_password asks for a password twice (hidden) and writes the value
# to BIB_PROMPT_VALUE on success. Reads directly from /dev/tty regardless of
# BIB_PROMPT_INPUT — passwords should never come from a heredoc.
prompt_password() {
    local question="$1"
    local min_len="${2:-8}"
    BIB_PROMPT_VALUE=""
    while true; do
        printf '%s\n' "$question"
        printf 'Password (minimum %d characters, not shown as you type): ' "$min_len"
        local pw1=""
        if ! IFS= read -rs pw1 < /dev/tty; then
            printf '\n' >&2
            warn "prompt_password: no tty available"
            return 1
        fi
        printf '\n'
        if [[ ${#pw1} -lt $min_len ]]; then
            printf 'Too short (got %d chars, need at least %d). Try again.\n\n' "${#pw1}" "$min_len" >&2
            continue
        fi
        printf 'Confirm: '
        local pw2=""
        IFS= read -rs pw2 < /dev/tty || { printf '\n' >&2; return 1; }
        printf '\n\n'
        if [[ "$pw1" != "$pw2" ]]; then
            printf "Passwords don't match. Try again.\n\n" >&2
            continue
        fi
        BIB_PROMPT_VALUE="$pw1"
        return 0
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
