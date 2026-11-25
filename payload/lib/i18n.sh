#!/usr/bin/env bash
# Message catalogs and the language choice (FEAT-045).
# Source this file; do not execute it directly. lib/common.sh sources it.
#
# What lives where:
#   payload/i18n/<lang>/<area>.sh   one file per area, only lines of the form
#                                   BIB_MSG[area.topic.detail]='printf format'
#                                   (single line; the value carries its own \n).
#                                   Keys are never the English sentence.
#   this file                       the loader, `msg`, and the language
#                                   resolution (flag, env, state, prompt, en).
#
# English is the default and the fallback. Everything here is pure bash: a
# message costs one associative-array lookup, and a catalog is sourced once per
# process, the first time a message is printed.

set -euo pipefail

# Every language a catalog may exist for.
BIB_LANGS_ALLOWED=(en es)
# The languages the installer OFFERS. A catalog can be merged before it is
# offered: this constant is what stops an owner from landing on a half-translated
# screen (FEAT-045 risk 5). FEAT-045's last wave flipped it to "en es"; a new
# language is added here only once its catalog and README are complete.
# A plain assignment on purpose: no environment variable can offer a language.
BIB_LANGS_AVAILABLE="en es"
BIB_LANG_DEFAULT="en"

# The catalogs are sourced as root, so their directory never comes from the
# environment outside the test suite, and never for root at all: the seam is
# honoured only for a caller that is not root (`id -u`, so a test can stub it).
if [[ "${BIB_I18N_TEST:-0}" == "1" && -n "${BIB_I18N_DIR:-}" && "$(id -u)" -ne 0 ]]; then
    :
else
    # Through symlinks: a caller may link this file next to the libs it sources.
    BIB_I18N_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../i18n" 2>/dev/null && pwd || true)"
fi

declare -gA BIB_I18N_LOADED
BIB_LANG_ACTIVE=""
BIB_LANG_PICKED=""

# ---------------------------------------------------------------------------
# Log file only (never the console)
# ---------------------------------------------------------------------------
# Like log() in common.sh this creates the log directory, so it must not be
# called while uninstalling. It never fails the caller: a hook running as the
# box user, or a test with no log directory, just loses the line.
bib_i18n_note() {
    local dir="${BIB_LOG_DIR:-/var/log/buildersinabox}"
    local file="${BIB_LOG_FILE:-${dir}/bootstrap.log}"
    {
        mkdir -p "$(dirname "$file")"
        printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$file"
    } 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# Language codes
# ---------------------------------------------------------------------------

bib_lang_valid() {
    local want="${1:-}" l
    for l in "${BIB_LANGS_ALLOWED[@]}"; do
        [[ "$want" == "$l" ]] && return 0
    done
    return 1
}

# Is <code> offered by this build (BIB_LANGS_AVAILABLE)?
bib_lang_available() {
    local want="${1:-}" l
    for l in $BIB_LANGS_AVAILABLE; do
        [[ "$want" == "$l" ]] && return 0
    done
    return 1
}

# Dies on an unknown code. Fail fast, with nothing touched: a typo must never
# degrade to English on a box whose owner asked for something else.
bib_lang_require_valid() {
    local want="$1" origin="${2:-language}"
    bib_lang_valid "$want" && return 0
    local list="${BIB_LANGS_ALLOWED[*]}"
    local msg="unknown language '${want}' (from ${origin}); allowed: ${list// /|}"
    if declare -F die >/dev/null; then
        die "$msg"
    fi
    printf 'ERROR: %s\n' "$msg" >&2
    exit 1
}

# What an owner types at the language screen, normalised to a code. Prints
# nothing and returns 1 when it is not one of the options. The accented
# spelling is matched with `?` so this file stays free of accents (they live
# in the catalogs): `?` is one character in a UTF-8 locale and half of one in C.
bib_lang_normalize() {
    local a="${1:-}"
    a="${a,,}"
    a="${a#"${a%%[![:space:]]*}"}"
    a="${a%"${a##*[![:space:]]}"}"
    case "$a" in
        1|en|english)                  printf 'en' ;;
        2|es|espanol|espa?ol|espa??ol) printf 'es' ;;
        *) return 1 ;;
    esac
}

# The language the owner's locale suggests: Spanish for es*, English for the rest.
bib_lang_locale_default() {
    local loc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    loc="${loc,,}"
    case "$loc" in
        es|es_*|es.*|es@*) printf 'es' ;;
        *) printf 'en' ;;
    esac
}

# The valid language persisted in state.json, or nothing. A state file written
# before this feature has no key: that reads as "nothing persisted".
bib_lang_persisted() {
    local f="${BIB_STATE_FILE:-/var/lib/buildersinabox/state.json}" v=""
    [[ -f "$f" ]] || return 0
    v="$(jq -r '.lang // empty' "$f" 2>/dev/null || true)"
    if bib_lang_valid "$v"; then
        printf '%s' "$v"
    fi
    return 0
}

# The language to use right now, for any script in any process (the `biab`
# command, a hook, a wizard step). Persisted state first: once a box has a
# language, only `biab lang` changes it, and a stray BIB_LANG in the environment
# does not (the same rule as the install profile). Then the environment, which
# is how install.sh hands its choice to the wizard before state exists. A
# language this build does not offer reads as English.
bib_lang_current() {
    local l
    l="$(bib_lang_persisted)"
    [[ -n "$l" ]] || l="${BIB_LANG:-}"
    if bib_lang_valid "$l" && bib_lang_available "$l"; then
        printf '%s' "$l"
    else
        printf '%s' "$BIB_LANG_DEFAULT"
    fi
}

# The value state_init writes at creation.
bib_lang_for_state() {
    local l="${BIB_LANG:-}"
    if bib_lang_valid "$l" && bib_lang_available "$l"; then
        printf '%s' "$l"
    else
        printf '%s' "$BIB_LANG_DEFAULT"
    fi
}

# ---------------------------------------------------------------------------
# Catalogs and msg
# ---------------------------------------------------------------------------

# Sources every area file of <lang> into BIB_MSG_<lang>. The nameref makes the
# plain `BIB_MSG[key]=...` lines of the catalog files land in the right array.
bib_i18n_load() {
    local l="$1" f
    [[ "${BIB_I18N_LOADED[$l]:-}" == "1" ]] && return 0
    # The code becomes part of a sourced path: only allow-listed languages.
    bib_lang_valid "$l" || return 1
    declare -gA "BIB_MSG_${l}"
    # shellcheck disable=SC2034  # read by the sourced catalog files
    local -n BIB_MSG="BIB_MSG_${l}"
    for f in "${BIB_I18N_DIR}/${l}"/*.sh; do
        [[ -f "$f" ]] || continue
        # shellcheck source=/dev/null
        source "$f"
    done
    BIB_I18N_LOADED[$l]="1"
}

# Sets REPLY to the format of <key> in <lang>; returns 1 when it is not there.
_bib_msg_get() {
    local l="$1" key="$2"
    bib_i18n_load "$l" || return 1
    local -n _bib_arr="BIB_MSG_${l}"
    [[ -v "_bib_arr[$key]" ]] || return 1
    REPLY="${_bib_arr[$key]}"
}

# Makes <lang> the language of `msg`. A language this build does not offer reads
# as English.
bib_lang_activate() {
    local l="${1:-}"
    if ! { bib_lang_valid "$l" && bib_lang_available "$l"; }; then
        l="$BIB_LANG_DEFAULT"
    fi
    BIB_LANG_ACTIVE="$l"
    bib_i18n_load "$BIB_LANG_DEFAULT"
    bib_i18n_load "$l"
}

# Sets REPLY to the printf format for <key> in <lang>, with the fallbacks of R7:
# the English text (and one log line), or [[key]] (and one log line) when even
# English lacks it, so the bug is visible and nothing prints blank.
_bib_msg_format() {
    local l="$1" key="$2"
    if _bib_msg_get "$l" "$key"; then
        return 0
    fi
    if [[ "$l" != "$BIB_LANG_DEFAULT" ]] && _bib_msg_get "$BIB_LANG_DEFAULT" "$key"; then
        bib_i18n_note "i18n: key '${key}' is missing in '${l}', printed in ${BIB_LANG_DEFAULT}"
        return 0
    fi
    bib_i18n_note "i18n: key '${key}' is missing in '${BIB_LANG_DEFAULT}'"
    REPLY=""
    return 1
}

# msg <key> [args...]       print the message, formatted
# msg_in <lang> <key> [...] the same, in a given language (the bilingual screen)
# msg_str <var> <key> [...] into a variable instead of stdout
# msg_has <key>             0 when the active language has the key
msg_in() {
    local l="$1" key="$2"
    shift 2
    if _bib_msg_format "$l" "$key"; then
        # shellcheck disable=SC2059  # the catalog value is the format on purpose
        printf -- "$REPLY" "$@"
    else
        printf '[[%s]]' "$key"
    fi
}

msg() {
    [[ -n "$BIB_LANG_ACTIVE" ]] || bib_lang_activate "$(bib_lang_current)"
    msg_in "$BIB_LANG_ACTIVE" "$@"
}

msg_str() {
    local __var="$1" __key="$2"
    shift 2
    [[ -n "$BIB_LANG_ACTIVE" ]] || bib_lang_activate "$(bib_lang_current)"
    if _bib_msg_format "$BIB_LANG_ACTIVE" "$__key"; then
        # shellcheck disable=SC2059  # the catalog value is the format on purpose
        printf -v "$__var" -- "$REPLY" "$@"
    else
        printf -v "$__var" '[[%s]]' "$__key"
    fi
}

msg_has() {
    [[ -n "$BIB_LANG_ACTIVE" ]] || bib_lang_activate "$(bib_lang_current)"
    _bib_msg_get "$BIB_LANG_ACTIVE" "$1"
}

# ---------------------------------------------------------------------------
# The language screen and the resolution order (R1, R2, R3)
# ---------------------------------------------------------------------------

# Is there a point in asking? Several languages offered, a person who can answer
# (not --non-interactive, not an update, not an image bake) and an input that
# opens. A tty that cannot be opened, as under cron, answers "no" here.
bib_lang_prompt_allowed() {
    local n=0 l
    for l in $BIB_LANGS_AVAILABLE; do n=$((n + 1)); done
    [[ "$n" -gt 1 ]] || return 1
    [[ "${NON_INTERACTIVE:-0}" != "1" && "${UPDATE_MODE:-0}" != "1" && "${SKIP_WIZARD:-0}" != "1" ]] || return 1
    declare -F _bib_read_line >/dev/null || return 1
    ( : < "${BIB_PROMPT_INPUT:-/dev/tty}" ) 2>/dev/null
}

# The bilingual screen. Sets BIB_LANG_PICKED. Enter takes the language in $1, or
# the locale's when none is given; a wrong answer asks again (three times) and
# then takes it too; ended input takes it at once and sets BIB_LANG_PROMPT_ENDED=1.
# Returns 1 only when there is no way to read at all.
bib_lang_prompt() {
    declare -F _bib_read_line >/dev/null || return 1
    local def n answer picked="" tries=0
    BIB_LANG_PROMPT_ENDED=0
    def="${1:-}"
    [[ -n "$def" ]] || def="$(bib_lang_locale_default)"
    bib_lang_available "$def" || def="$BIB_LANG_DEFAULT"
    if [[ "$def" == "es" ]]; then n=2; else n=1; fi

    local _lt
    _lt="$(msg_in en lang.screen.title) / $(msg_in es lang.screen.title)"
    printf '\n'
    if declare -F ui_card >/dev/null; then
        ui_card "$_lt" "1  $(msg_in en lang.name.en)" "2  $(msg_in es lang.name.es)"
    else
        printf '%s\n\n  1) %s\n  2) %s\n' "$_lt" "$(msg_in en lang.name.en)" "$(msg_in es lang.name.es)"
    fi
    printf '\n'
    while [[ "$tries" -lt 3 ]]; do
        if declare -F _ui_ask >/dev/null; then
            printf '  '
            _ui_ask "$(msg_in en lang.screen.choose) / $(msg_in es lang.screen.choose) [1-2] (Enter = $n)"
        else
            printf '%s / %s [1-2] (Enter = %s): ' "$(msg_in en lang.screen.choose)" "$(msg_in es lang.screen.choose)" "$n"
        fi
        if ! _bib_read_line answer; then
            printf '\n'
            bib_i18n_note "language: the prompt input ended, using the locale default (${def})"
            BIB_LANG_PROMPT_ENDED=1
            picked="$def"
            break
        fi
        if [[ -z "${answer//[[:space:]]/}" ]]; then
            picked="$def"
            break
        fi
        if picked="$(bib_lang_normalize "$answer")"; then
            break
        fi
        picked=""
        printf '%s\n%s\n' "$(msg_in en lang.screen.invalid)" "$(msg_in es lang.screen.invalid)"
        tries=$((tries + 1))
    done
    [[ -n "$picked" ]] || picked="$def"
    bib_lang_available "$picked" || picked="$BIB_LANG_DEFAULT"
    BIB_LANG_PICKED="$picked"
    return 0
}

# Resolves the language of this install and exports BIB_LANG (the code) and
# BIB_LANG_SOURCE (who decided: state, flag, env, prompt or default).
#
#   persisted in state.json > --lang flag ($1) > BIB_LANG > the screen > en
#
# Once a box has a language the flag and the environment are ignored (with a
# line in the log): only `biab lang` changes it. Nothing is written to state
# here; state_init and bib_lang_persist do that.
bib_lang_resolve() {
    local flag="${1:-}" requested="" source="default" persisted result=""
    persisted="$(bib_lang_persisted)"

    if [[ -n "$flag" ]]; then
        requested="$flag"
        source="flag"
    elif [[ -n "${BIB_LANG:-}" ]]; then
        requested="$BIB_LANG"
        source="env"
    fi
    [[ -z "$requested" ]] || bib_lang_require_valid "$requested" "$source"

    if [[ -n "$persisted" ]]; then
        result="$persisted"
        if [[ -n "$requested" && "$requested" != "$persisted" ]]; then
            bib_i18n_note "language: ${source} '${requested}' ignored, this box is already set to '${persisted}' (biab lang changes it)"
        fi
        source="state"
    elif [[ -n "$requested" ]]; then
        result="$requested"
    elif bib_lang_prompt_allowed && bib_lang_prompt; then
        result="$BIB_LANG_PICKED"
        source="prompt"
    else
        result="$BIB_LANG_DEFAULT"
        bib_i18n_note "language: none given and nobody to ask (or only ${BIB_LANGS_AVAILABLE} is offered), using ${result}"
    fi

    if ! bib_lang_available "$result"; then
        bib_i18n_note "language: '${result}' (${source}) is not offered by this build (offered: ${BIB_LANGS_AVAILABLE}), using ${BIB_LANG_DEFAULT}"
        result="$BIB_LANG_DEFAULT"
    fi

    export BIB_LANG="$result"
    export BIB_LANG_SOURCE="$source"
    bib_lang_activate "$result"
}

# R5: the first wizard run asks once when the owner did not see the language
# screen (a cloud render, --non-interactive, the gift ISO's first boot, a flag):
# the same bilingual 1/2 screen as the install, with Enter = the language of the
# box. Either way phases.lang_confirmed is set, so a resume never asks again.
# Nothing is asked when it is already confirmed, when fewer than two languages
# are offered, or when nobody can answer (no tty); ended input keeps the language
# and does not confirm. Needs common.sh (state_set) and prompt.sh (_bib_read_line).
bib_lang_confirm() {
    local f="${BIB_STATE_FILE:-/var/lib/buildersinabox/state.json}" cur picked
    [[ -f "$f" ]] || return 0
    [[ "$(jq -r '.phases.lang_confirmed // false' "$f" 2>/dev/null || true)" != "true" ]] || return 0
    bib_lang_prompt_allowed || return 0
    cur="$(bib_lang_current)"
    bib_lang_prompt "$cur" || return 0
    if [[ "${BIB_LANG_PROMPT_ENDED:-0}" == "1" ]]; then
        bib_i18n_note "language: the confirmation input ended, keeping '${cur}' unconfirmed"
        return 0
    fi
    picked="$BIB_LANG_PICKED"
    if [[ "$picked" != "$cur" ]]; then
        state_set '.lang' "$picked"
        export BIB_LANG="$picked"
        export BIB_LANG_SOURCE="prompt"
        bib_lang_activate "$picked"
        bib_i18n_note "language: the owner changed '${cur}' to '${picked}' at the first wizard run"
    fi
    state_set '.phases.lang_confirmed' "true"
    printf '\n'
}

# Writes the language into state.json when the file has none. Never replaces a
# persisted language. Needs common.sh (state_set). A box created by state_init
# already has it; this covers a state file from before FEAT-045.
bib_lang_persist() {
    local want="${1:-${BIB_LANG:-}}"
    [[ -f "${BIB_STATE_FILE:-}" ]] || return 0
    bib_lang_valid "$want" || return 0
    [[ -z "$(bib_lang_persisted)" ]] || return 0
    state_set '.lang' "$want"
}
