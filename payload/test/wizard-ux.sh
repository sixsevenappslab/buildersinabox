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

if (( FAIL > 0 )); then
    printf 'wizard-ux: %d passed, %d failed\n' "$PASS" "$FAIL" >&2
    exit 1
fi
printf 'wizard-ux: %d passed, 0 failed\n' "$PASS"
