#!/usr/bin/env bash
# Hermetic per-CLI wiring smoke test. Exercises the CLI-dispatch surface for
# one value of BIB_AI_CLI (claude | antigravity | codex | opencode) WITHOUT needing root, a real
# box, systemd, Tailscale, or network access — so it runs on a plain CI runner.
#
# What it validates (the "wiring", per FEAT-013 acceptance criterion #4):
#   - the CLI identifier resolves and validates,
#   - it maps to an install script that exists and parses (`bash -n`),
#   - the retired `gemini` identifier is rejected,
#   - the desktop README renders cleanly for the CLI (no leftover block
#     markers; antigravity render carries no Claude-app-only phrasing).
#
# What it does NOT validate: the agy OAuth token actually persisting across a
# reboot (risk R1). That is covered ONLY by the manual multipass E2E pass in
# the FEAT-013 QA plan (CP-02), never by CI.
#
# Usage:  BIB_AI_CLI=antigravity payload/test/wiring-smoke.sh

set -euo pipefail

CLI="${BIB_AI_CLI:?BIB_AI_CLI must be set (claude|antigravity|codex|opencode)}"
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

# --- 4. Desktop README renders cleanly for this CLI ------------------------
# shellcheck source=../lib/paseo.sh
source "${PAYLOAD_DIR}/lib/paseo.sh"
# OpenCode counts as permissioned only while the rules BIAB seeds in the box
# user's own config hold, so it gets a scratch home carrying exactly that seed.
# The seam is honoured in test mode only (BIB_PASEO_TEST=1 in CI).
if [[ "$CLI" == "opencode" ]]; then
    OC_HOME="${BIB_STATE_DIR}/oc-home"
    mkdir -p "$OC_HOME"
    ( ai_cli_seed_settings opencode "$OC_HOME" "${OC_HOME}/ai-platform" ) >/dev/null 2>&1 \
        || fail "the OpenCode permission seed failed in a scratch home"
    export BIB_PERMISSIONS_HOME="$OC_HOME"
fi
readme="${PAYLOAD_DIR}/tutorial/desktop-readme.md"
rendered="$(ai_cli_render_readme "$CLI" "$readme")"
grep -q 'BIB:' <<<"$rendered" && fail "rendered README still contains block markers"
if [[ "$CLI" == "antigravity" ]]; then
    grep -Eq 'Claude Code app|Remote Control|claude\.ai/download' <<<"$rendered" \
        && fail "antigravity README leaks Claude-app-only phrasing"
fi
# Every CLI is on the Paseo path (FEAT-035, FEAT-041; OpenCode while its seeded
# rules hold, FEAT-040): the README teaches the app, never tmux.
grep -q 'Paseo app' <<<"$rendered" || fail "$CLI README does not teach the Paseo app"
grep -Eq 'tmux (attach|new)|launch-main\.sh' <<<"$rendered" \
    && fail "$CLI README still teaches the tmux interface"
ok "README renders cleanly"

# --- 5. Registry completeness (FEAT-020) -----------------------------------
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
    [[ -n "$(ai_cli_paseo_provider "$reg_cli")" ]] \
        || fail "registry[$reg_cli]: ai_cli_paseo_provider is empty"
    reg_prompt="$(ai_cli_initial_prompt "$reg_cli")"
    [[ -n "$reg_prompt" && "$reg_prompt" != /* && "$reg_prompt" != '$'* ]] \
        || fail "registry[$reg_cli]: ai_cli_initial_prompt must be natural language (agy has slash commands off under Paseo, codex uses \$skill): '$reg_prompt'"
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

# --- 6. The `unattended` capability is a security promise (FEAT-025) --------
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

# --- 7. Which CLIs get the Paseo interface (FEAT-035 R11, FEAT-041, FEAT-040) --
# Pinned per CLI, like `unattended`. claude, codex and antigravity run under
# Paseo with their permission prompts; antigravity does so through BIAB's own
# ACP provider (Paseo's built-in one passes --dangerously-skip-permissions, BIAB
# never does). No state key is needed. OpenCode is the exception that proves the
# rule: its own defaults allow everything, so it is on Paseo only while its seeded
# permission rules hold (never from the state alone). Flipping this is a
# deliberate edit of this test AND of the adapter, never a side effect.
_empty_state="$(mktemp)"
printf '{}\n' > "$_empty_state"
if [[ "$CLI" == "opencode" ]]; then
    BIB_STATE_FILE="$_empty_state" paseo_supports_cli "$CLI" \
        || fail "opencode should use the Paseo interface while its seeded rules hold (scratch home ${BIB_PERMISSIONS_HOME:-unset})"
    # The same call with no way to find a seeded home must fail closed.
    ( unset BIB_PERMISSIONS_HOME; BIB_STATE_FILE="$_empty_state" paseo_supports_cli "$CLI" ) \
        && fail "opencode reached Paseo with no seeded home to check"
    ai_cli_has_capability "$CLI" paseo-permissioned && fail "opencode must not declare paseo-permissioned (its defaults allow everything)"
else
    BIB_STATE_FILE="$_empty_state" paseo_supports_cli "$CLI" || fail "$CLI should use the Paseo interface with an empty state"
fi
if [[ "$CLI" == "antigravity" ]]; then
    for _st in '{"ai_cli":"antigravity","paseo_antigravity_optin":false}' '{"paseo_antigravity_optin":"true"}' 'not json'; do
        printf '%s\n' "$_st" > "$_empty_state"
        BIB_STATE_FILE="$_empty_state" paseo_supports_cli "$CLI" || fail "antigravity depends on state again ($_st)"
    done
fi
rm -f "$_empty_state"
ai_cli_has_capability "$CLI" paseo-optin && fail "$CLI declares a capability that no longer exists"
# Antigravity runs through BIAB's own ACP provider, not Paseo's built-in one (FEAT-041).
_want_provider="$CLI"
[[ "$CLI" != "antigravity" ]] || _want_provider="antigravity-acp"
[[ "$(ai_cli_paseo_provider "$CLI")" == "$_want_provider" ]] \
    || fail "paseo provider id for $CLI is '$(ai_cli_paseo_provider "$CLI")', expected '$_want_provider'"
ok "Paseo interface decision pinned for $CLI (no opt-in; opencode only while its seeded rules hold)"

# --- 9. The `guard*` capabilities are a security promise (FEAT-042) ----------
# `guard` says BIAB registers a shell-command guard for this CLI that denies the
# destructive patterns; `guard-ask` that it can also ask; `guard-exact` that its
# pattern coverage equals Claude's. None of them is `hooks` (Claude-format settings
# hooks). Pinned per CLI like `unattended`: a CLI gets a token in the same PR that
# makes a test block with it, never as a side effect. Codex followed in FEAT-042 wave
# 2, OpenCode in wave 4, Antigravity in a one-line PR after the hardware pass.
_guard_home="$(mktemp -d)"
for reg_cli in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
    g=0 ga=0 ge=0
    ai_cli_has_capability "$reg_cli" guard && g=1
    ai_cli_has_capability "$reg_cli" guard-ask && ga=1
    ai_cli_has_capability "$reg_cli" guard-exact && ge=1
    case "$reg_cli" in
        claude)
            [[ "$g$ga$ge" == "111" ]] \
                || fail "registry[$reg_cli]: expected guard, guard-ask and guard-exact (got $g$ga$ge)" ;;
        codex)
            # FEAT-042 wave 2: a Codex hook can deny but cannot ask (no guard-ask), and it
            # has Claude's pattern coverage (guard-exact). Declared with the test that
            # makes it block (payload/test/cli-guard.sh).
            [[ "$g$ga$ge" == "101" ]] \
                || fail "registry[$reg_cli]: expected exactly guard and guard-exact, never guard-ask (got $g$ga$ge)" ;;
        opencode)
            # FEAT-042 wave 4: deny keys in permission.bash, shown to block with the real
            # binary (payload/test/cli-guard.sh CF-46). Partial coverage, so never
            # guard-exact; and no guard-ask, because no test can watch the engine ask.
            [[ "$g$ga$ge" == "100" ]] \
                || fail "registry[$reg_cli]: expected exactly guard, never guard-ask or guard-exact (got $g$ga$ge)" ;;
        *)
            [[ "$g$ga$ge" == "000" ]] \
                || fail "registry[$reg_cli]: declares a guard* token ($g$ga$ge). That is a promise a test must back: see FEAT-042 (a wave per CLI; Antigravity only after the hardware pass)." ;;
    esac
    if [[ "$g" -eq 1 ]]; then
        declare -F "_ai_cli_guard_state__${reg_cli}" >/dev/null \
            || fail "registry[$reg_cli]: declares guard without _ai_cli_guard_state__${reg_cli}"
    fi
    [[ -n "$(ai_cli_guard_state "$reg_cli" "$_guard_home")" ]] \
        || fail "registry[$reg_cli]: ai_cli_guard_state printed nothing"
    [[ "$g" -eq 1 || "$(ai_cli_guard_state "$reg_cli" "$_guard_home")" == "none" ]] \
        || fail "registry[$reg_cli]: no guard declared but the state is not 'none'"
done
rm -rf "$_guard_home"
ok "guard* capabilities pinned per CLI (claude: guard guard-ask guard-exact; codex: guard guard-exact; opencode: guard; none elsewhere yet)"

# An UNREGISTERED identifier must fail cleanly through ai_cli_validate on
# every getter — never a bash "command not found" from composing a missing
# function name (FEAT-020 EC-01). (`codex` used to be the stand-in here; it
# became a real CLI in FEAT-021, so use a name that can never be registered.)
for bad_getter in ai_cli_display_name ai_cli_skills_dirs ai_cli_install_script; do
    if ( "$bad_getter" nosuchcli ) >/dev/null 2>&1; then
        fail "$bad_getter accepted the unregistered 'nosuchcli' identifier"
    fi
done
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
