#!/usr/bin/env bash
# Hermetic per-CLI wiring smoke test. Exercises the CLI-dispatch surface for
# one value of BIB_AI_CLI (claude | antigravity) WITHOUT needing root, a real
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

CLI="${BIB_AI_CLI:?BIB_AI_CLI must be set (claude|antigravity)}"
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
# Drive launch_cmd_for in isolation (it only reads $ai_cli + args). We want
# the REAL per-CLI command here, so drop the dryrun override even if CI set it.
unset BIB_TMUX_LAUNCH_CMD
# shellcheck disable=SC2034  # ai_cli is read by the sourced launch_cmd_for
ai_cli="$CLI"
eval "$(sed -n '/^launch_cmd_for()/,/^}/p' "${PAYLOAD_DIR}/tmux/launch-main.sh")"
cmd="$(launch_cmd_for ai-platform '/tutorial')"
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

# --- 5. Desktop README renders cleanly for this CLI ------------------------
readme="${PAYLOAD_DIR}/tutorial/desktop-readme.md"
rendered="$(awk -v cli="$CLI" '
    /<!-- BIB:claude:start -->/      { inblock=1; keep=(cli=="claude");      next }
    /<!-- BIB:antigravity:start -->/ { inblock=1; keep=(cli=="antigravity"); next }
    /<!-- BIB:end -->/               { inblock=0; keep=1;                     next }
    { if (!inblock || keep) print }
' "$readme")"
grep -q 'BIB:' <<<"$rendered" && fail "rendered README still contains block markers"
if [[ "$CLI" == "antigravity" ]]; then
    grep -Eq 'Claude Code app|Remote Control|claude\.ai/download' <<<"$rendered" \
        && fail "antigravity README leaks Claude-app-only phrasing"
    grep -q 'tmux attach' <<<"$rendered" || fail "antigravity README missing 'tmux attach'"
fi
ok "README renders cleanly"

rm -rf "$BIB_STATE_DIR"
echo "wiring-smoke[$CLI]: PASS"
