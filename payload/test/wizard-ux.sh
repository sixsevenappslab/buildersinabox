#!/usr/bin/env bash
# Hermetic checks for the guided wizard presentation and state-derived progress.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

ok() { printf 'wizard-ux: ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'wizard-ux: FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

assert_contains() {
    local text="$1" needle="$2" label="$3"
    if [[ "$text" == *"$needle"* ]]; then ok "$label"; else bad "$label"; fi
}

assert_not_contains() {
    local text="$1" needle="$2" label="$3"
    if [[ "$text" != *"$needle"* ]]; then ok "$label"; else bad "$label"; fi
}

assert_max_width() {
    local text="$1" width="$2" label="$3"
    if awk -v width="$width" 'length > width { exit 1 }' <<<"$text"; then
        ok "$label"
    else
        bad "$label"
    fi
}

# CI's wiring-smoke job exports these; the console-bridge checks below read the
# real OAuth/Paseo seams and fail when they leak in (pre-existing on main,
# recorded in FEAT-035 §5 review cycle 3). This driver needs none of them.
unset BIB_OAUTH_MOCK BIB_PASEO_RUN_CMD BIB_PASEO_TEST BIB_AI_CLI
export BIB_NO_COLOR=1
export COLUMNS=40
export TERM=dumb
# shellcheck source=../lib/prompt.sh
source "$REPO/payload/lib/prompt.sh"

clear_output="$(wizard_clear)"
[[ -z "$clear_output" ]] && ok "TERM=dumb screen clear is a silent no-op" || bad "TERM=dumb screen clear is a silent no-op"

header="$(wizard_step_header 3 6 "Continue remotely" "4 minutes")"
assert_contains "$header" "Step 3 of 6" "progress heading survives no-color mode"
assert_contains "$header" "About 4 minutes left" "progress gives a remaining-time estimate"
assert_max_width "$header" 40 "progress header fits 40 columns"
if [[ "$header" != *$'\033'* ]]; then ok "progress header has no ANSI when disabled"; else bad "progress header has no ANSI when disabled"; fi

welcome="$(<"$REPO/payload/flavors/default/copy/welcome.txt")"
assert_contains "$welcome" "First, choose a password" "welcome gives the immediate next action"
assert_not_contains "$welcome" "Path A" "welcome does not anticipate remote routes"
assert_max_width "$welcome" 40 "welcome fits 40 columns"

phase_is_done() {
    [[ ",${BIB_TEST_DONE:-}," == *",$1,"* ]]
}
wizard_is_ssh() { [[ "${BIB_TEST_SSH:-no}" == "yes" ]]; }

BIB_TEST_DONE="password_set,tailscale_done" BIB_TEST_SSH=yes
assert_contains "$(wizard_next_milestone)" "4|Connect your AI" "SSH resume starts at AI login"
BIB_TEST_DONE="password_set,tailscale_done" BIB_TEST_SSH=no
assert_contains "$(wizard_next_milestone)" "3|Continue remotely" "console resume stays at bridge"
BIB_TEST_DONE="password_set,tailscale_done,ai_cli_done,scaffold_done" BIB_TEST_SSH=yes
assert_contains "$(wizard_next_milestone)" "6|Start building" "completed state reaches final milestone"

export BIB_BRIDGE_LIB=1
# shellcheck source=../wizard/36-phone-bridge.sh
source "$REPO/payload/wizard/36-phone-bridge.sh"

laptop="$(render_laptop_bridge builder biabox 100.64.1.2)"
assert_contains "$laptop" "ssh builder@biabox" "laptop route gives its SSH command"
assert_not_contains "$laptop" "Termius" "laptop route excludes phone instructions"
assert_max_width "$laptop" 40 "laptop route fits 40 columns"

test_input="$(mktemp)"
trap 'rm -f "$test_input"' EXIT
printf '\n\n' > "$test_input"
export BIB_PROMPT_INPUT="$test_input"
phone="$(render_phone_bridge builder biabox 100.64.1.2)"
assert_contains "$phone" "Termius" "phone route includes its SSH app"
assert_not_contains "$phone" "Use your laptop" "phone route excludes laptop instructions"
assert_max_width "$phone" 40 "phone route fits 40 columns"

require_root() { :; }
log() { :; }
bib_user_resolve() { printf 'builder\n'; }
hostname() { printf 'biabox\n'; }
tailscale() { printf '100.64.1.2\n'; }
phase_is_done() { return 1; }
BIB_TEST_DONE=""
BIB_TEST_SSH=no
set +e
bridge_output="$(bridge_main)"
bridge_rc=$?
set -e
[[ "$bridge_rc" -eq 78 ]] && ok "console bridge keeps the exit 78 pause contract" || bad "console bridge keeps the exit 78 pause contract"
assert_contains "$bridge_output" "ssh builder@biabox" "bridge defaults to the selected laptop route"

# --- FEAT-049: glyphs, width and colour --------------------------------------
# Each case runs in a clean environment so the caller's TERM/LANG/COLUMNS cannot leak in.
ui_env() { # <VAR=val>... -- <bash code>: run code with prompt.sh sourced
    local -a e=()
    while [[ "$1" != -- ]]; do e+=("$1"); shift; done
    shift
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" "${e[@]}" bash -c 'source "$1/payload/lib/prompt.sh"; '"$1" _ "$REPO"
}
ui_screens='wizard_banner; wizard_step_header 4 6 "Connect your AI" "3 minutes"; ui_card "Choose one" "1  Claude Code  Claude" "2  OpenCode     several"'
border_re='[┌┐└┘╭╮╰╯│─+|]'

# R5: under 40 columns the cards and the mark keep their content but drop the borders.
narrow="$(ui_env COLUMNS=36 TERM=xterm LANG=C.UTF-8 BIB_NO_COLOR=1 -- "$ui_screens")"
assert_contains "$narrow" "Claude Code" "R5: a card under 40 columns keeps its content"
assert_contains "$narrow" "builders" "R5: the mark under 40 columns keeps its wordmark"
if grep -q "$border_re" <<<"$narrow"; then bad "R5: COLUMNS=36 prints no border characters"; else ok "R5: COLUMNS=36 prints no border characters"; fi
wide="$(ui_env COLUMNS=40 TERM=xterm LANG=C.UTF-8 BIB_NO_COLOR=1 -- "$ui_screens")"
assert_contains "$wide" "╭" "R1: at 40 columns the mark is drawn in a rounded card"
assert_contains "$wide" "┌ Choose one" "R3: at 40 columns the card has a titled border"
too_wide="$(export LC_ALL=C.UTF-8; while IFS= read -r line; do (( ${#line} > 40 )) && printf '%s|' "$line"; done <<<"$wide"; true)"
[[ -z "$too_wide" ]] && ok "R1/R2/R3: every line at 40 columns is at most 40 characters" || bad "R1/R2/R3: lines over 40 characters: $too_wide"
assert_contains "$wide" "█" "R2: the step bar is solid in UTF-8"

# R6: no non-ASCII byte when the locale is not UTF-8 or TERM is linux/dumb/unset.
for ctx in "LANG=C TERM=xterm" "LANG=C.UTF-8 TERM=linux" "LANG=C.UTF-8 TERM=dumb" "LANG=C.UTF-8"; do
    # shellcheck disable=SC2086  # the context is two assignments, word-split on purpose
    ascii_out="$(ui_env COLUMNS=40 BIB_NO_COLOR=1 $ctx -- "$ui_screens")"
    if LC_ALL=C grep -q -P '[^\x00-\x7F]' <<<"$ascii_out"; then bad "R6: no non-ASCII byte in the mark, header and card with $ctx"; else ok "R6: no non-ASCII byte in the mark, header and card with $ctx"; fi
done
assert_contains "$ascii_out" "+" "R6: the ASCII fallback still draws a card"
assert_contains "$ascii_out" "#" "R6: the ASCII fallback draws the bar with #"
assert_max_width "$ascii_out" 40 "R6: the ASCII layout stays within 40 columns"

# R7: no escape byte when colour is off; the same code on a terminal does print colour.
if command -v script >/dev/null 2>&1; then
    colour_env() { # <VAR=val>...: the screens on a pseudo-terminal
        local -a e=("$@")
        local cmd
        cmd="$(printf '%q ' env -i PATH="$PATH" HOME="${HOME:-/tmp}" "${e[@]}" bash -c 'source "$1/payload/lib/prompt.sh"; '"$ui_screens" _ "$REPO")"
        script -qec "$cmd" /dev/null
    }
    on="$(colour_env COLUMNS=40 TERM=xterm LANG=C.UTF-8)"
    [[ "$on" == *$'\033['* ]] && ok "R7 (control): on a terminal with colour on, the screens do print colour" || bad "R7 (control): on a terminal with colour on, the screens do print colour"
    for off in BIB_NO_COLOR=1 NO_COLOR=1; do
        out="$(colour_env COLUMNS=40 TERM=xterm LANG=C.UTF-8 "$off")"
        [[ "$out" != *$'\033'* ]] && ok "R7: $off prints no escape byte, even on a terminal" || bad "R7: $off prints no escape byte, even on a terminal"
    done
else
    ok "R7: skipped, script(1) is not installed here"
fi
piped="$(ui_env COLUMNS=40 TERM=xterm LANG=C.UTF-8 -- "$ui_screens; ui_ok done; ui_warn careful; ui_err failed")"
[[ "$piped" != *$'\033'* ]] && ok "R7: output that is not a terminal has no escape byte" || bad "R7: output that is not a terminal has no escape byte"
assert_contains "$piped" "✓ done" "R4: ui_ok starts with a check"
assert_contains "$piped" "! careful" "R4: ui_warn starts with a mark"
assert_contains "$piped" "✗ failed" "R4: ui_err starts with a mark"
width_cjk="$(ui_env LANG=C.UTF-8 -- 'ui_width "añ█"')"
[[ "$width_cjk" == 3 ]] && ok "ui_width counts characters, not bytes" || bad "ui_width counts characters, not bytes (got $width_cjk)"

if (( FAIL > 0 )); then
    printf 'wizard-ux: %d passed, %d failed\n' "$PASS" "$FAIL" >&2
    exit 1
fi
printf 'wizard-ux: %d passed, 0 failed\n' "$PASS"
