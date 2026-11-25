#!/usr/bin/env bash
# TUI prompt helpers. Source after lib/common.sh.
# Designed for a plain console attached to the mini PC. No redraws,
# no ncurses — clear labels, blank lines and (FEAT-049) a few box glyphs and
# 16-colour ANSI, so the user can read from the screen while typing on a phone.
# Every glyph has an ASCII fallback and every colour is off with NO_COLOR.

set -euo pipefail

# The messages live in the catalogs (FEAT-045). lib/common.sh already sourced the
# loader; a caller that sources this file alone (the wizard UX test) gets it here.
if ! declare -F msg >/dev/null; then
    # shellcheck source=i18n.sh
    source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/i18n.sh"
fi

# Where to read interactive input from. Default to /dev/tty (real console).
# Tests can set BIB_PROMPT_INPUT=/dev/stdin to drive the wizard from a heredoc.
BIB_PROMPT_INPUT="${BIB_PROMPT_INPUT:-/dev/tty}"

# Optional names and short hints for the rows of the next prompt_choice or
# prompt_multi_choice card (parallel to its options); the prompt clears them.
BIB_PROMPT_LABELS=()
BIB_PROMPT_TAGS=()
# Optional card title and label/tag gap for the next ui_options (consumed by it).
BIB_PROMPT_CARD_TITLE=""
BIB_PROMPT_GAP="  "

# Color palette. Disabled automatically when stdout isn't a tty (so dryrun
# tests, log pipes, redirections, etc. stay clean ASCII).
# shellcheck disable=SC2034  # palette declared for use across sourcing scripts
if [[ -t 1 ]] && [[ "${BIB_NO_COLOR:-0}" != "1" ]] && [[ -z "${NO_COLOR:-}" ]]; then
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
    # Brand colour: bright blue, near the site accent (#1769ff) in 16 colours.
    BIB_BRAND=$'\e[94m'
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
    BIB_BRAND=""
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

# ---------------------------------------------------------------------------
# Visual helpers (FEAT-049). Screens call these; they never print escape codes
# or box characters themselves. Glyphs are chosen per call from the environment
# (UTF-8 locale and a TERM that can draw them, else ASCII); colour comes from the
# BIB_* palette above, which is empty when colour is off.
# ---------------------------------------------------------------------------

# True when box-drawing glyphs are safe: a UTF-8 locale and a TERM that is not
# the Linux console, a dumb terminal or unset.
ui_utf8() {
    case "${TERM:-}" in ''|linux|dumb) return 1 ;; esac
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) return 0 ;;
    esac
    return 1
}

# Set the _UI_* glyph variables (UTF-8 set, or the ASCII fallback).
_ui_glyphs() {
    if ui_utf8; then
        _UI_TL='┌' _UI_TR='┐' _UI_BL='└' _UI_BR='┘'
        _UI_RTL='╭' _UI_RTR='╮' _UI_RBL='╰' _UI_RBR='╯'
        _UI_H='─' _UI_V='│' _UI_FULL='█' _UI_EMPTY='░'
        _UI_OK='✓' _UI_WARN='!' _UI_ERR='✗' _UI_DOT='·' _UI_PROMPT='›'
        _UI_MARK1=' ▄▄▄' _UI_MARK2='█▀▀▀█' _UI_MARK3='█▄▄▄█'
    else
        _UI_TL='+' _UI_TR='+' _UI_BL='+' _UI_BR='+'
        _UI_RTL='+' _UI_RTR='+' _UI_RBL='+' _UI_RBR='+'
        _UI_H='-' _UI_V='|' _UI_FULL='#' _UI_EMPTY='.'
        _UI_OK='*' _UI_WARN='!' _UI_ERR='x' _UI_DOT='-' _UI_PROMPT='>'
        _UI_MARK1=' ___ ' _UI_MARK2='|   |' _UI_MARK3='|___|'
    fi
}

# Display width of <text> in columns: characters, not bytes, and ANSI colour
# sequences count for nothing.
ui_width() {
    local s="$1"
    if [[ "$s" == *$'\e'* ]]; then
        s="$(printf '%s' "$s" | sed 's/\x1b\[[0-9;]*m//g')"
    fi
    local LC_ALL=C.UTF-8
    printf '%s' "${#s}"
}

# <text> followed by spaces up to <width> columns (no newline).
ui_pad() {
    local s="$1" want="$2" w
    w="$(ui_width "$s")"
    printf '%s' "$s"
    (( want > w )) && printf '%*s' "$(( want - w ))" ''
    return 0
}

# <char> repeated <n> times (no newline).
_ui_rep() {
    local ch="$1" n="$2" t
    (( n > 0 )) || return 0
    printf -v t '%*s' "$n" ''
    printf '%s' "${t// /$ch}"
}

# Draw a box of inner width <inner> around the lines. $1 square|round, $2 inner,
# $3 title (may be empty), then the lines.
_ui_box() {
    local style="$1" inner="$2" title="$3" line tl tr bl br
    shift 3
    if [[ "$style" == round ]]; then tl="$_UI_RTL" tr="$_UI_RTR" bl="$_UI_RBL" br="$_UI_RBR"
    else tl="$_UI_TL" tr="$_UI_TR" bl="$_UI_BL" br="$_UI_BR"; fi
    local b="$BIB_BRAND" r="$BIB_RESET" tw=0
    if [[ -n "$title" ]]; then
        tw="$(ui_width "$title")"
        printf '  %s%s%s %s%s%s %s' "$b" "$tl" "$r" "$BIB_BOLD" "$title" "$r" "$b"
        _ui_rep "$_UI_H" "$(( inner - tw ))"
        printf '%s%s\n' "$tr" "$r"
    else
        printf '  %s%s' "$b" "$tl"
        _ui_rep "$_UI_H" "$(( inner + 2 ))"
        printf '%s%s\n' "$tr" "$r"
    fi
    for line in "$@"; do
        printf '  %s%s%s ' "$b" "$_UI_V" "$r"
        ui_pad "$line" "$inner"
        printf ' %s%s%s\n' "$b" "$_UI_V" "$r"
    done
    printf '  %s%s' "$b" "$bl"
    _ui_rep "$_UI_H" "$(( inner + 2 ))"
    printf '%s%s\n' "$br" "$r"
}

# ui_card <title> <line>...: the lines in a titled card. Under 40 columns, or
# when a line is too wide for a 40-column card, the borders are dropped and the
# content stays (R5).
ui_card() {
    local title="$1" line w cols inner
    shift
    _ui_glyphs
    cols="$(wizard_columns)"
    inner="$(ui_width "$title")"
    for line in "$@"; do
        w="$(ui_width "$line")"
        (( w > inner )) && inner="$w"
    done
    if (( cols < 40 || inner > 34 )); then
        [[ -z "$title" ]] || printf '  %s%s%s\n' "$BIB_BOLD$BIB_BRAND" "$title" "$BIB_RESET"
        for line in "$@"; do printf '  %s\n' "$line"; done
        return 0
    fi
    _ui_box square "$inner" "$title" "$@"
}

# The Builders in a Box mark: a box glyph and the wordmark in a rounded card of
# 32 columns (borderless under 40 columns).
ui_logo() {
    local cols m1 m2 m3
    _ui_glyphs
    cols="$(wizard_columns)"
    m1=" ${BIB_BRAND}${_UI_MARK1}${BIB_RESET}"
    m2=" ${BIB_BRAND}${_UI_MARK2}${BIB_RESET}  ${BIB_BOLD}builders${BIB_RESET}"
    m3=" ${BIB_BRAND}${_UI_MARK3}${BIB_RESET}  ${BIB_BRAND}in a box${BIB_RESET}"
    printf '\n'
    if (( cols < 40 )); then
        printf '%s\n%s\n%s\n' "$m1" "$m2" "$m3"
    else
        _ui_box round 30 "" "$m1" "$m2" "$m3"
    fi
}

# A mark in front of text: ui_ok (green check), ui_warn (yellow), ui_err (red).
# They take the text as arguments and print one line.
ui_ok()   { _ui_glyphs; printf '%s%s%s %s\n' "$BIB_GREEN" "$_UI_OK" "$BIB_RESET" "$*"; }
ui_warn() { _ui_glyphs; printf '%s%s%s %s\n' "$BIB_YELLOW" "$_UI_WARN" "$BIB_RESET" "$*"; }
ui_err()  { _ui_glyphs; printf '%s%s%s %s\n' "$BIB_RED" "$_UI_ERR" "$BIB_RESET" "$*"; }

# Put a mark in front of a message that already carries its own newlines, without
# touching its words. ok: every line that starts with "Done:" / "Listo:"; warn and
# err: the first non-empty line. Usage: ui_mark <ok|warn|err> <text>
ui_mark() {
    local kind="$1" text="$2" tail body line out="" first=1 mark colour
    _ui_glyphs
    case "$kind" in
        ok)   mark="$_UI_OK" colour="$BIB_GREEN" ;;
        warn) mark="$_UI_WARN" colour="$BIB_YELLOW" ;;
        *)    mark="$_UI_ERR" colour="$BIB_RED" ;;
    esac
    tail="${text##*[!$'\n']}"
    body="${text%"$tail"}"
    local done_pending=1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$kind" == ok ]]; then
            [[ "$line" =~ ^(Done|Listo): ]] && line="${colour}${mark}${BIB_RESET} ${line}"
        elif [[ "$done_pending" == 1 && -n "$line" ]]; then
            line="${colour}${mark}${BIB_RESET} ${line}"
            done_pending=0
        fi
        if [[ "$first" == 1 ]]; then out="$line"; first=0; else out+=$'\n'"$line"; fi
    done <<<"$body"
    printf '%s%s' "$out" "$tail"
}

# msg_ok / msg_warn / msg_err KEY [args]: print a catalog message with its mark.
msg_ok()   { local _t; msg_str _t "$@"; ui_mark ok "$_t"; }
msg_warn() { local _t; msg_str _t "$@"; ui_mark warn "$_t"; }
msg_err()  { local _t; msg_str _t "$@"; ui_mark err "$_t"; }

# ui_options <question> <generic title> <option>...: the numbered options as a card, one aligned row
# each: number, name and (when BIB_PROMPT_TAGS has one) a short hint. The names
# come from BIB_PROMPT_LABELS when set, else the options themselves. The question
# is the card title when it is short; else the generic title stands in and the
# question is printed above the card.
ui_options() {
    local question="$1" title="$2" i n lw=0 w
    shift 2
    local -a opts=("$@") labels=() tags=() rows=()
    local gap="${BIB_PROMPT_GAP:-  }"
    [[ -z "${BIB_PROMPT_CARD_TITLE:-}" ]] || title="$BIB_PROMPT_CARD_TITLE"
    BIB_PROMPT_CARD_TITLE="" BIB_PROMPT_GAP="  "
    _ui_glyphs
    n=${#opts[@]}
    for (( i = 0; i < n; i++ )); do
        labels+=("${BIB_PROMPT_LABELS[i]:-${opts[i]}}")
        tags+=("${BIB_PROMPT_TAGS[i]:-}")
        w="$(ui_width "${labels[i]}")"
        (( w > lw )) && lw="$w"
    done
    for (( i = 0; i < n; i++ )); do
        local num label tag
        printf -v num '%*s' "${#n}" "$(( i + 1 ))"
        label="${labels[i]}"
        tag="${tags[i]}"
        if [[ -n "$tag" ]]; then
            rows+=("${BIB_BRAND}${num}${BIB_RESET}  $(ui_pad "$label" "$lw")${gap}${BIB_DIM}${tag}${BIB_RESET}")
        else
            rows+=("${BIB_BRAND}${num}${BIB_RESET}  ${label}")
        fi
    done
    if (( $(ui_width "$question") <= 30 )); then
        title="$question"
    else
        printf '%s\n' "$question"
    fi
    ui_card "$title" "${rows[@]}"
}

# The input marker: " › " (" > " in ASCII), after the "[default]" text.
_ui_ask() { _ui_glyphs; printf '%s %s%s%s ' "$1" "$BIB_BRAND" "$_UI_PROMPT" "$BIB_RESET"; }

# Print the default welcome banner: the compact brand mark. The gift flavor
# overrides this function in its manifest.sh with the personalised 76-column
# ASCII variant, so run.sh calls wizard_banner and gets whichever applies.
wizard_banner() {
    ui_logo
}

# Print a header for a wizard step: a bold brand-coloured title with a short rule.
prompt_header() {
    _ui_glyphs
    local title="$*" w
    w="$(ui_width "$title")"
    (( w > 36 )) && w=36
    printf '\n\n  %s%s%s\n  %s' "$BIB_BOLD$BIB_BRAND" "$title" "$BIB_RESET" "$BIB_BRAND"
    _ui_rep "$_UI_H" "$w"
    printf '%s\n\n' "$BIB_RESET"
}

# Clear the screen when the terminal supports it. `clear` exits non-zero for
# TERM=dumb, which must not abort wizard scripts running under `set -e`.
wizard_clear() {
    command -v clear >/dev/null 2>&1 || return 0
    clear 2>/dev/null || true
}

# Print the compact, adaptive heading used by the first-boot wizard: "Step N of
# 6 · title" and a solid progress bar with the time left, in the brand colour.
# No fixed-width box: phone terminals can be as narrow as 40 columns.
wizard_step_header() {
    local current="$1" total="$2" title="$3" remaining="$4"
    local columns="${COLUMNS:-80}"
    local bar_width=12
    [[ "$columns" =~ ^[0-9]+$ ]] || columns=80
    (( columns < 40 )) && columns=40
    (( columns < 54 )) && bar_width=8
    local filled=$(( current * bar_width / total ))
    local empty=$(( bar_width - filled ))
    _ui_glyphs

    local step_label left_label
    msg_str step_label prompt.step.label "$current" "$total"
    msg_str left_label prompt.step.left "$remaining"
    printf '\n%s%s%s %s %s\n' \
        "$BIB_BOLD$BIB_BRAND" "$step_label" "$BIB_RESET" "$_UI_DOT" "$title"
    printf '%s' "$BIB_BRAND"
    _ui_rep "$_UI_FULL" "$filled"
    printf '%s%s' "$BIB_RESET" "$BIB_DIM"
    _ui_rep "$_UI_EMPTY" "$empty"
    printf '%s  %s\n\n' "$BIB_RESET" "$left_label"
}

# True when the wizard was launched from SSH. SSH_CONNECTION survives sudo in
# the first-boot wrapper; the parent walk covers callers that do not preserve
# it. Keep this here so run.sh and the bridge cannot drift apart.
wizard_is_ssh() {
    [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]] && return 0
    local pid=$$ depth=0 comm
    while [[ "$pid" -gt 1 && "$depth" -lt 20 ]]; do
        comm="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
        [[ "$comm" == sshd* ]] && return 0
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
        [[ -n "$pid" ]] || break
        depth=$((depth + 1))
    done
    return 1
}

# Echo the first visible milestone not yet complete. The state phases remain
# the only source of truth; this creates no wizard cursor or new persistence.
wizard_next_milestone() {
    local title eta
    if ! phase_is_done "password_set"; then
        msg_str title wizard.title.secure; msg_str eta wizard.eta.min8
        printf '1|%s|%s\n' "$title" "$eta"
    elif ! phase_is_done "tailscale_done"; then
        msg_str title wizard.title.private; msg_str eta wizard.eta.min6
        printf '2|%s|%s\n' "$title" "$eta"
    elif ! wizard_is_ssh; then
        msg_str title wizard.title.remote; msg_str eta wizard.eta.min4
        printf '3|%s|%s\n' "$title" "$eta"
    elif ! phase_is_done "ai_cli_done"; then
        msg_str title wizard.title.ai; msg_str eta wizard.eta.min3
        printf '4|%s|%s\n' "$title" "$eta"
    elif ! phase_is_done "scaffold_done"; then
        msg_str title wizard.title.workspace; msg_str eta wizard.eta.min1
        printf '5|%s|%s\n' "$title" "$eta"
    else
        msg_str title wizard.title.start; msg_str eta wizard.eta.moment
        printf '6|%s|%s\n' "$title" "$eta"
    fi
}

# Width of the user's terminal in columns. COLUMNS wins (tests and callers that
# know better), then the real tty, then 80.
wizard_columns() {
    local c="${COLUMNS:-}"
    if [[ ! "$c" =~ ^[0-9]+$ ]]; then
        c="$({ stty size < /dev/tty; } 2>/dev/null | awk '{print $2}' || true)"
    fi
    [[ "$c" =~ ^[0-9]+$ && "$c" -gt 0 ]] || c=80
    printf '%s' "$c"
}

# Draw <url> as a QR code made of half-block characters (one column per module,
# two module rows per text row), with a small quiet zone. The ANSI variant sets
# black-on-white itself, so it scans on dark and light themes alike. If the
# code is wider than the terminal it is NOT drawn: a QR that wraps is garbage,
# and a camera cannot read half of one. Prints one line saying so instead.
# Silent when qrencode is missing (the URL is always printed by the caller).
prompt_qr() {
    local url="$1" qr width cols
    command -v qrencode >/dev/null 2>&1 || return 0
    qr="$(qrencode -t ANSIUTF8 -l L -m 2 -- "$url" 2>/dev/null || qrencode -t UTF8 -l L -m 2 -- "$url" 2>/dev/null || true)"
    [[ -n "$qr" ]] || return 0
    cols="$(wizard_columns)"
    # Display width in characters, not bytes: Ubuntu's default awk (mawk) counts
    # bytes, so a 37-column QR of 3-byte blocks would read as 100+ and never draw.
    width="$(sed 's/\x1b\[[0-9;]*m//g' <<<"$qr" | LC_ALL=C.UTF-8 wc -L | tr -d ' ')"
    # A width we could not measure is a QR we do not draw.
    [[ "$width" =~ ^[0-9]+$ ]] || width=999
    if (( width + 2 > cols )); then
        msg prompt.qr.toowide
        return 0
    fi
    printf '%s\n' "$qr" | sed 's/^/  /'
    printf '\n'
}

# Print an URL prominently, plus a scannable QR code below it when
# `qrencode` is available and the QR fits the screen. The operator can either
# type the URL on their phone OR point a camera at the QR from another device.
prompt_url() {
    local label="${1:-}"
    local url="$2" scan_label
    [[ -n "$label" ]] || msg_str label prompt.url.label
    printf '\n'
    printf '%s%s%s\n' "$BIB_DIM" "$label" "$BIB_RESET"
    printf '\n'
    printf '    %s>%s  %s%s%s\n' "$BIB_BRIGHT_CYAN" "$BIB_RESET" "$BIB_BOLD$BIB_BRIGHT_YELLOW" "$url" "$BIB_RESET"
    printf '\n'
    if command -v qrencode >/dev/null 2>&1; then
        msg_str scan_label prompt.url.scan
        printf '%s%s%s\n\n' "$BIB_DIM" "$scan_label" "$BIB_RESET"
        prompt_qr "$url"
    fi
}

# Throw away keystrokes that are already waiting on the terminal. Call it right
# before handing the terminal to a CLI whose first prompt reads a line: an
# impatient second Enter would otherwise be taken as an empty answer ("Invalid
# code"). The optional argument is a settle time in seconds, waited first so a
# double-tap that is still arriving is caught too. Only a real terminal is
# drained; a file or pipe (tests, heredocs) would loop forever or eat the
# script, so those are left alone.
prompt_flush_input() {
    local settle="${1:-0}" _junk
    [[ "$BIB_PROMPT_INPUT" == "/dev/stdin" || "$BIB_PROMPT_INPUT" == "/dev/fd/0" ]] && return 0
    [[ -c "$BIB_PROMPT_INPUT" && -r "$BIB_PROMPT_INPUT" ]] || return 0
    # Opening /dev/tty with no controlling terminal fails with ENXIO even though
    # it is "readable": try the real open, as _oauth_console_attached does.
    { : < "$BIB_PROMPT_INPUT"; } 2>/dev/null || return 0
    [[ "$settle" == "0" ]] || sleep "$settle"
    while IFS= read -r -t 0.05 -n 4096 _junk < "$BIB_PROMPT_INPUT" 2>/dev/null; do :; done
    return 0
}

# Clear the screen AND the scrollback, where the terminal honours it, so a
# secret that was shown once does not stay a swipe away.
wizard_clear_secret() {
    wizard_clear
    [[ -t 1 ]] && printf '\033[3J'
    return 0
}

# Wait for the user to confirm a step is done. Blocks until Enter is pressed.
# Stdin is /dev/tty so it works even if the script is being piped.
prompt_confirm() {
    local text="${1:-}"
    [[ -n "$text" ]] || msg_str text prompt.confirm.default
    printf '%s\n' "$text"
    # Read a single line. Discard whatever the user typed. EOF is acceptable
    # here — we just wanted to wait for the user to acknowledge.
    local _discard
    _bib_read_line _discard || true
}

# Ask a single-choice question. Echoes the chosen value to stdout.
#   prompt_choice "Pick a CLI" "claude" "antigravity"
# The first option is treated as the default if the user just presses Enter.
# prompt_choice writes the chosen value into BIB_PROMPT_VALUE.
# Returns non-zero on EOF.
prompt_choice() {
    local question="$1"
    shift
    local options=("$@")
    local default="${options[0]}"

    BIB_PROMPT_VALUE=""
    local generic hint ask
    msg_str generic prompt.card.pick
    ui_options "$question" "$generic" "${options[@]}"
    BIB_PROMPT_LABELS=() BIB_PROMPT_TAGS=()
    msg_str hint prompt.choice.hint
    printf '  %s\n' "$hint"

    while true; do
        msg_str ask prompt.choice.ask "$default"
        printf '  '
        _ui_ask "$ask"
        local answer=""
        if ! _bib_read_line answer; then
            printf '\n' >&2
            warn "prompt_choice: input stream ended unexpectedly"  # i18n-ok: maintainer diagnostic
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
        msg_warn prompt.choice.invalid "$answer" >&2
    done
}

# Ask a multi-choice question (FEAT-048 R2).
#   prompt_multi_choice "Pick one or more:" "claude,codex" "claude" "antigravity" "codex" "opencode"
# Enter accepts the default comma-separated list. Users may type one or more
# 1-based numbers or option names separated by spaces or commas (e.g. "1 3").
# Writes comma-separated values into BIB_PROMPT_VALUE and the array BIB_PROMPT_VALUES.
# Returns non-zero on EOF.
prompt_multi_choice() {
    local question="$1"
    local default_csv="$2"
    shift 2
    local options=("$@")
    [[ -n "$default_csv" ]] || default_csv="${options[0]}"

    BIB_PROMPT_VALUE=""
    BIB_PROMPT_VALUES=()
    local opt generic hint ask
    msg_str generic prompt.card.pick_multi
    ui_options "$question" "$generic" "${options[@]}"
    BIB_PROMPT_LABELS=() BIB_PROMPT_TAGS=()
    msg_str hint prompt.multi.hint
    printf '  %s\n' "$hint"

    # Show the default as the menu numbers the owner types, not as internal ids.
    local default_nums="" d i
    for d in ${default_csv//,/ }; do
        for i in "${!options[@]}"; do
            [[ "${options[i]}" == "$d" ]] && default_nums+="${default_nums:+ }$((i + 1))"
        done
    done
    [[ -n "$default_nums" ]] || default_nums="$default_csv"

    while true; do
        msg_str ask prompt.multi.ask "$default_nums"
        printf '  '
        _ui_ask "$ask"
        local answer=""
        if ! _bib_read_line answer; then
            printf '\n' >&2
            warn "prompt_multi_choice: input stream ended unexpectedly"  # i18n-ok: maintainer diagnostic
            return 1
        fi
        local raw="${answer:-$default_csv}"
        raw="${raw//,/ }"
        local -a toks=() picked=()
        read -r -a toks <<< "$raw"
        local seen=" " bad="" tok matched=""
        for tok in "${toks[@]}"; do
            matched=""
            if [[ "$tok" =~ ^[0-9]{1,3}$ ]] && (( 10#$tok >= 1 && 10#$tok <= ${#options[@]} )); then
                matched="${options[10#$tok-1]}"
            else
                for opt in "${options[@]}"; do
                    if [[ "$tok" == "$opt" ]]; then
                        matched="$opt"
                        break
                    fi
                done
            fi
            if [[ -z "$matched" ]]; then
                bad="$tok"
                break
            fi
            if [[ "$seen" != *" $matched "* ]]; then
                picked+=("$matched")
                seen+="$matched "
            fi
        done
        if [[ -z "$bad" && ${#picked[@]} -gt 0 ]]; then
            # shellcheck disable=SC2034  # read by callers of prompt_multi_choice
            BIB_PROMPT_VALUES=("${picked[@]}")
            BIB_PROMPT_VALUE="$(IFS=,; printf '%s' "${picked[*]}")"
            return 0
        fi
        msg_warn prompt.multi.invalid "${bad:-$answer}" >&2
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
            warn "prompt_text: input stream ended unexpectedly"  # i18n-ok: maintainer diagnostic
            return 1
        fi
        if [[ -z "$answer" ]]; then
            msg_warn prompt.text.required >&2
            continue
        fi
        if [[ "$answer" =~ $pattern ]]; then
            BIB_PROMPT_VALUE="$answer"
            return 0
        fi
        msg_warn prompt.text.nomatch "$answer" >&2
    done
}

# Put the terminal and the signal traps back as _bib_read_secret found them.
# Shared by the normal exit and by the signal handler below.
_bib_secret_restore() {
    local sig var
    if [[ -n "${_BIB_SECRET_OLD:-}" ]]; then
        stty "$_BIB_SECRET_OLD" < /dev/tty 2>/dev/null || true
        _BIB_SECRET_OLD=""
    fi
    for sig in INT TERM HUP; do
        var="_BIB_SECRET_TRAP_${sig}"
        if [[ -n "${!var:-}" ]]; then eval "${!var}"; else trap - "$sig"; fi
    done
}

# A signal during the read: give the user their echo back, then die of the
# signal as if nothing had intercepted it.
_bib_secret_on_signal() {
    local sig="$1"
    trap '' INT TERM HUP
    _bib_secret_restore
    printf '\n'
    kill -s "$sig" "$BASHPID"
}

# Read one secret line from the terminal into <varname>, echoing one '*' per
# character (backspace and Ctrl-U erase, arrow and other escape keys are
# ignored whole). The terminal echo and line editing are switched off BEFORE
# the prompt is printed and stay off for the whole read, not per key, so neither
# a fast typist nor a pasted password is ever printed or edited by the kernel;
# they are switched back on however the read ends, Ctrl-C and SIGTERM/SIGHUP
# included. Returns 1 when there is no terminal.
# Reads /dev/tty directly.
_bib_read_secret() {
    local __var="$1" __prompt="$2" __pw="" __ch="" __rest="" __fd __old
    # A UTF-8 locale, so backspace erases one character and not one byte.
    local LC_ALL=C.UTF-8
    if ! { exec {__fd}< /dev/tty; } 2>/dev/null; then
        return 1
    fi
    if ! __old="$(stty -g <&"$__fd" 2>/dev/null)"; then
        exec {__fd}<&-
        return 1
    fi
    _BIB_SECRET_OLD="$__old"
    _BIB_SECRET_TRAP_INT="$(trap -p INT)"
    _BIB_SECRET_TRAP_TERM="$(trap -p TERM)"
    _BIB_SECRET_TRAP_HUP="$(trap -p HUP)"
    trap '_bib_secret_on_signal INT' INT
    trap '_bib_secret_on_signal TERM' TERM
    trap '_bib_secret_on_signal HUP' HUP
    # -icanon as well as -echo: `read -n1` only switches the terminal to
    # character mode while it is waiting, so between two keys the kernel's line
    # editing is on, and a backspace that arrives in that gap (a fast typist, a
    # paste, a slow box) is applied by the kernel and never reaches us.
    stty -echo -icanon <&"$__fd" 2>/dev/null || true
    printf '%s' "$__prompt"
    while :; do
        if ! IFS= read -rsn1 -u "$__fd" __ch; then
            _bib_secret_restore
            exec {__fd}<&-
            return 1
        fi
        case "$__ch" in
            ''|$'\r'|$'\n') break ;;
            $'\x7f'|$'\b')
                if [[ -n "$__pw" ]]; then
                    __pw="${__pw%?}"
                    printf '\b \b'
                fi ;;
            $'\x15')
                while [[ -n "$__pw" ]]; do
                    __pw="${__pw%?}"
                    printf '\b \b'
                done ;;
            $'\e')
                # Swallow the whole escape sequence (arrows, Delete, Home, End:
                # ESC [ ... final byte) so none of it lands in the password.
                if IFS= read -rsn1 -t 0.05 -u "$__fd" __rest; then
                    if [[ "$__rest" == "[" || "$__rest" == "O" ]]; then
                        while IFS= read -rsn1 -t 0.05 -u "$__fd" __rest; do
                            [[ "$__rest" == [A-Za-z~] ]] && break
                        done
                    fi
                fi ;;
            *) __pw+="$__ch"; printf '*' ;;
        esac
    done
    _bib_secret_restore
    exec {__fd}<&-
    printf -v "$__var" '%s' "$__pw"
}

# prompt_password asks for a password twice (one * per character) and writes
# the value to BIB_PROMPT_VALUE on success. Reads directly from /dev/tty
# regardless of BIB_PROMPT_INPUT: passwords should never come from a heredoc.
prompt_password() {
    local question="$1"
    local min_len="${2:-8}"
    BIB_PROMPT_VALUE=""
    while true; do
        printf '%s\n' "$question"
        local pw1=""
        if ! _bib_read_secret pw1 "$(msg prompt.password.ask "$min_len")"; then
            printf '\n' >&2
            warn "prompt_password: no tty available"  # i18n-ok: maintainer diagnostic
            return 1
        fi
        printf '\n'
        if [[ ${#pw1} -lt $min_len ]]; then
            msg_err prompt.password.short "${#pw1}" "$min_len" >&2
            continue
        fi
        local pw2=""
        _bib_read_secret pw2 "$(msg prompt.password.again)" || { printf '\n' >&2; return 1; }
        printf '\n\n'
        if [[ "$pw1" != "$pw2" ]]; then
            msg_err prompt.password.mismatch >&2
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
    local hint ask
    msg_str hint prompt.project.hint
    msg_str ask prompt.project.ask
    local pattern='^[a-z][a-z0-9-]{1,30}$'
    while true; do
        prompt_text "$ask" "$pattern" "$hint" || return 1
        if project_name_is_valid "$BIB_PROMPT_VALUE"; then
            return 0
        fi
        msg_warn prompt.project.reserved "$BIB_PROMPT_VALUE" >&2
    done
}
