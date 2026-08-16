#!/usr/bin/env bash
# Hermetic per-CLI wiring smoke test. Exercises the CLI-dispatch surface for
# one value of BIB_AI_CLI (claude | antigravity | codex) WITHOUT needing root, a real
# box, systemd, Tailscale, or network access — so it runs on a plain CI runner.
#
# What it validates (the "wiring", per FEAT-013 acceptance criterion #4):
#   - the CLI identifier resolves and validates,
#   - it maps to an install script that exists and parses (`bash -n`),
#   - the retired `gemini` identifier is rejected,
#   - the tmux launcher builds the right launch command for the CLI,
#   - the desktop README renders cleanly for the CLI (no leftover block
#     markers; antigravity render carries no Claude-app-only phrasing).
#
# What it does NOT validate: the agy OAuth token actually persisting across a
# reboot (risk R1). That is covered ONLY by the manual multipass E2E pass in
# the FEAT-013 QA plan (CP-02), never by CI.
#
# Usage:  BIB_AI_CLI=antigravity payload/test/wiring-smoke.sh

set -euo pipefail

CLI="${BIB_AI_CLI:?BIB_AI_CLI must be set (claude|antigravity|codex)}"
PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "wiring-smoke[$CLI]: FAIL: $*" >&2; exit 1; }
ok()   { echo "wiring-smoke[$CLI]: ok: $*"; }

# --- 1. Identifier resolves + validates ------------------------------------
# Use an isolated state dir so common.sh's helpers never touch a real box.
BIB_STATE_DIR="$(mktemp -d)"
export BIB_STATE_DIR
export BIB_STATE_FILE="${BIB_STATE_DIR}/state.json"
export BIB_LOG_DIR="${BIB_STATE_DIR}/log"
# shellcheck source=../lib/common.sh
source "${PAYLOAD_DIR}/lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${PAYLOAD_DIR}/lib/ai-cli.sh"

resolved="$(ai_cli_resolve "")"
[[ "$resolved" == "$CLI" ]] || fail "ai_cli_resolve returned '$resolved', expected '$CLI'"
ok "resolves to $resolved"

# --- 2. Install script exists and parses -----------------------------------
script="$(ai_cli_install_script "$CLI")"
[[ -f "${PAYLOAD_DIR}/${script}" ]] || fail "install script ${script} missing"
bash -n "${PAYLOAD_DIR}/${script}" || fail "install script ${script} has syntax errors"
ok "install script ${script} exists and parses"

# --- 3. The retired gemini identifier is rejected --------------------------
if ( ai_cli_validate "gemini" ) 2>/dev/null; then
    fail "ai_cli_validate accepted the retired 'gemini' identifier"
fi
ok "gemini identifier rejected"

# --- 4. tmux launcher builds the right command -----------------------------
# The launch command now comes from the adapter registry (already sourced) —
# the launcher's launch_cmd_for is a shim over ai_cli_launch_cmd that only
# adds the BIB_TMUX_LAUNCH_CMD dryrun override. We want the REAL per-CLI
# command here, so query the registry directly.
cmd="$(ai_cli_launch_cmd "$CLI" ai-platform '/tutorial')"
case "$CLI" in
    claude)
        [[ "$cmd" == *"claude --remote-control"* && "$cmd" == *"/tutorial"* ]] \
            || fail "claude launch cmd unexpected: $cmd" ;;
    antigravity)
        [[ "$cmd" == *"agy -i"* && "$cmd" == *"/tutorial"* ]] \
            || fail "antigravity launch cmd unexpected: $cmd"
        [[ "$cmd" == *"AGY_CLI_DISABLE_AUTO_UPDATE=1"* ]] \
            || fail "antigravity launch cmd missing auto-update disable: $cmd" ;;
esac
ok "launch cmd: $cmd"

# Injection safety (FEAT-020 EC-04): window name and initial prompt must be
# %q-escaped, so a hostile value can never break out when the command line is
# eventually executed (tmux send-keys types it into a shell). Run it under a
# stub PATH that has `touch` but NOT the real CLI: if the escaping regressed,
# the injected `touch` runs and creates the marker; if it's correct, the whole
# hostile value stays one argument and nothing is created.
marker="${BIB_STATE_DIR}/pwned"
stub_bin="${BIB_STATE_DIR}/stub-bin"
mkdir -p "$stub_bin"
ln -s "$(command -v touch)" "${stub_bin}/touch"
hostile_cmd="$(ai_cli_launch_cmd "$CLI" "w;touch $marker" "/tut;touch $marker")"
PATH="$stub_bin" bash -c "$hostile_cmd" >/dev/null 2>&1 || true
[[ ! -e "$marker" ]] || fail "launch cmd is injectable: '$hostile_cmd' created $marker"
ok "launch cmd escapes window/prompt (no injection)"

# --- 5. Desktop README renders cleanly for this CLI ------------------------
readme="${PAYLOAD_DIR}/tutorial/desktop-readme.md"
rendered="$(ai_cli_render_readme "$CLI" "$readme")"
grep -q 'BIB:' <<<"$rendered" && fail "rendered README still contains block markers"
if [[ "$CLI" == "antigravity" ]]; then
    grep -Eq 'Claude Code app|Remote Control|claude\.ai/download' <<<"$rendered" \
        && fail "antigravity README leaks Claude-app-only phrasing"
    grep -q 'tmux attach' <<<"$rendered" || fail "antigravity README missing 'tmux attach'"
fi
ok "README renders cleanly"

# --- 6. Registry completeness (FEAT-020) -----------------------------------
# Every registered CLI must answer the full adapter API, so a half-added
# entry fails here with the getter's name instead of breaking a real box.
for reg_cli in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
    reg_script="$(ai_cli_install_script "$reg_cli")" \
        || fail "registry[$reg_cli]: ai_cli_install_script failed"
    [[ -f "${PAYLOAD_DIR}/${reg_script}" ]] \
        || fail "registry[$reg_cli]: install script ${reg_script} missing"
    bash -n "${PAYLOAD_DIR}/${reg_script}" \
        || fail "registry[$reg_cli]: install script ${reg_script} has syntax errors"
    [[ -n "$(ai_cli_display_name "$reg_cli")" ]] \
        || fail "registry[$reg_cli]: ai_cli_display_name is empty"
    [[ -n "$(ai_cli_choice_hint "$reg_cli")" ]] \
        || fail "registry[$reg_cli]: ai_cli_choice_hint is empty"
    [[ -n "$(ai_cli_launch_cmd "$reg_cli" ai-platform '/tutorial')" ]] \
        || fail "registry[$reg_cli]: ai_cli_launch_cmd is empty"
    [[ -n "$(ai_cli_skills_dirs "$reg_cli")" ]] \
        || fail "registry[$reg_cli]: ai_cli_skills_dirs is empty"
    [[ -n "$(ai_cli_login_verify_cmd "$reg_cli" ubuntu)" ]] \
        || fail "registry[$reg_cli]: ai_cli_login_verify_cmd is empty"
    [[ -n "$(ai_cli_login_failure_hint "$reg_cli" ubuntu)" ]] \
        || fail "registry[$reg_cli]: ai_cli_login_failure_hint is empty"
    # has_capability must return 0/1 without aborting, for real and bogus caps.
    caps_probe=0
    ai_cli_has_capability "$reg_cli" hooks || caps_probe=$?
    [[ "$caps_probe" -le 1 ]] || fail "registry[$reg_cli]: ai_cli_has_capability hooks aborted (rc=$caps_probe)"
    caps_probe=0
    ai_cli_has_capability "$reg_cli" bogus-cap || caps_probe=$?
    [[ "$caps_probe" -eq 1 ]] || fail "registry[$reg_cli]: ai_cli_has_capability bogus-cap should be false, rc=$caps_probe"
done
ok "registry completeness (${BIB_SUPPORTED_AI_CLIS[*]})"

# --- 7. The `unattended` capability is a security promise (FEAT-025) --------
# Declaring it asserts three things at once: a headless mode, a per-run spend
# cap, and a mechanical tool guard. Only claude has all three today. This is
# pinned per CLI rather than left to whatever the registry happens to say,
# because adding a CLI to it silently is how a box ends up spending unattended
# with no guard (FEAT-025 §3 Ask First).
for reg_cli in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
    unattended=0
    ai_cli_has_capability "$reg_cli" unattended && unattended=1
    case "$reg_cli" in
        claude)
            [[ "$unattended" -eq 1 ]] \
                || fail "registry[$reg_cli]: expected the 'unattended' capability" ;;
        *)
            [[ "$unattended" -eq 0 ]] \
                || fail "registry[$reg_cli]: declares 'unattended' — that is a security promise (headless + spend cap + tool guard), not a name check. See FEAT-025 §3 Ask First." ;;
    esac
    if [[ "$unattended" -eq 1 ]]; then
        # Third argument is an OPAQUE guard directory: the adapter decides
        # what inside it matters (hooks settings here, execpolicy rules for
        # another CLI). Naming one CLI's knobs in the signature would force
        # the next one in through an `if` on the CLI name.
        ucmd="$(ai_cli_unattended_cmd "$reg_cli" /tmp/x /tmp/guard 'implement the spec')"
        for needle in ' -p ' '--settings' '--max-budget-usd'; do
            [[ "$ucmd" == *"$needle"* ]] \
                || fail "registry[$reg_cli]: unattended cmd is missing $needle: $ucmd"
        done
        [[ "$ucmd" == *"/tmp/guard/"* ]] \
            || fail "registry[$reg_cli]: unattended cmd ignores the guard directory: $ucmd"
    else
        ( ai_cli_unattended_cmd "$reg_cli" /tmp/x /tmp/guard p ) >/dev/null 2>&1 \
            && fail "registry[$reg_cli]: ai_cli_unattended_cmd answered for a CLI without the capability"
    fi
done
# Injection safety, same probe as the launch command: the prompt and the paths
# are %q-escaped, so a hostile spec path cannot break out of the argument when
# the string is handed to a shell.
u_marker="${BIB_STATE_DIR}/unattended-pwned"
u_stub="${BIB_STATE_DIR}/u-stub-bin"
mkdir -p "$u_stub"
ln -sf "$(command -v touch)" "${u_stub}/touch"
hostile_ucmd="$(ai_cli_unattended_cmd claude "/tmp;touch $u_marker" /tmp/guard "go;touch $u_marker")"
PATH="$u_stub" bash -c "$hostile_ucmd" >/dev/null 2>&1 || true
[[ ! -e "$u_marker" ]] || fail "unattended cmd is injectable: '$hostile_ucmd' created $u_marker"
ok "unattended capability pinned per CLI and the command escapes its arguments"

# An UNREGISTERED identifier must fail cleanly through ai_cli_validate on
# every getter — never a bash "command not found" from composing a missing
# function name (FEAT-020 EC-01). (`codex` used to be the stand-in here; it
# became a real CLI in FEAT-021, so use a name that can never be registered.)
for bad_getter in ai_cli_display_name ai_cli_skills_dirs ai_cli_install_script; do
    if ( "$bad_getter" nosuchcli ) >/dev/null 2>&1; then
        fail "$bad_getter accepted the unregistered 'nosuchcli' identifier"
    fi
done
( ai_cli_launch_cmd nosuchcli w '/tutorial' ) >/dev/null 2>&1 \
    && fail "ai_cli_launch_cmd accepted the unregistered 'nosuchcli' identifier"
ok "unregistered CLI identifiers fail cleanly"

# The registry must be sourceable COLD — no lib/common.sh, no state dir, no
# side effects — because the biab wrapper sources it standalone (EC-05).
cold_dirs="$(env -i bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_skills_dirs '$CLI'")" \
    || fail "ai-cli.sh not sourceable without lib/common.sh"
[[ -n "$cold_dirs" ]] || fail "cold-sourced ai_cli_skills_dirs returned nothing"
env -i bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_skills_dirs nope" >/dev/null 2>&1 \
    && fail "cold-sourced registry accepted an unregistered CLI (die guard missing)"
ok "registry sources cold (no common.sh) with the die guard in place"

rm -rf "$BIB_STATE_DIR"
echo "wiring-smoke[$CLI]: PASS"
