#!/usr/bin/env bash
# Unit driver for oauth_step's agent-friendly pause (FEAT-028 R1).
#
# Asserts: when no interactive console is attached (BIB_PROMPT_INPUT — default
# /dev/tty — isn't readable), oauth_step doesn't wait on a keypress or race
# into verify_cmd — it prints "BIB_AGENT_PAUSE: step=<label> url=<url>" and
# exits 78, the same clean "resume elsewhere" signal wizard/run.sh already
# uses for the phone-bridge step. Also asserts the interactive path (a real
# console) is unaffected — no regression on the existing behavior real users
# hit today. Does NOT touch real tailscale/OAuth; url-cmd and verify-cmd are
# fakes. Runs on a plain CI runner, no root needed.

set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "oauth-agent-pause: ok: $*"; pass=$((pass + 1)); }
bad() { echo "oauth-agent-pause: FAIL: $*" >&2; fail=$((fail + 1)); }

TMP_STATE="$(mktemp -d)"
trap 'rm -rf "$TMP_STATE"' EXIT

export BIB_STATE_DIR="$TMP_STATE/state"
export BIB_LOG_DIR="$TMP_STATE/log"

# shellcheck source=../lib/common.sh
source "${PAYLOAD_DIR}/lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${PAYLOAD_DIR}/lib/prompt.sh"
# shellcheck source=../lib/oauth.sh
source "${PAYLOAD_DIR}/lib/oauth.sh"

# Runs in a subshell: oauth_step's new pause path calls `exit 78`, and this
# is the only clean way to assert an exit code without killing the driver.
run_oauth_step() {
    (
        eval "$1"
        oauth_step --label "TestCLI" --url-cmd "$2" --verify "$3"
    ) < /dev/null > "$TMP_STATE/out" 2>&1
}

# --- Scenario 1: no console, URL captured — pauses with exit 78 ------------
if run_oauth_step 'export BIB_PROMPT_INPUT=/nonexistent/tty' \
        'echo https://example.invalid/test-login' \
        'false'; then
    bad "scenario 1 (no console, URL captured): expected exit 78, got 0"
else
    rc=$?
    if [[ "$rc" -eq 78 ]] && grep -q 'BIB_AGENT_PAUSE: step=TestCLI url=https://example.invalid/test-login' "$TMP_STATE/out"; then
        ok "scenario 1 (no console, URL captured): pauses with exit 78 and a parseable line"
    else
        bad "scenario 1 (no console, URL captured): exit=$rc, output: $(cat "$TMP_STATE/out")"
    fi
fi

# --- Scenario 2: no console, url-cmd prints nothing — still pauses cleanly -
if run_oauth_step 'export BIB_PROMPT_INPUT=/nonexistent/tty' \
        'true' \
        'false'; then
    bad "scenario 2 (no console, no URL): expected exit 78, got 0"
else
    rc=$?
    if [[ "$rc" -eq 78 ]] && grep -q 'BIB_AGENT_PAUSE: step=TestCLI url=none' "$TMP_STATE/out"; then
        ok "scenario 2 (no console, no URL): pauses cleanly, url=none instead of crashing"
    else
        bad "scenario 2 (no console, no URL): exit=$rc, output: $(cat "$TMP_STATE/out")"
    fi
fi

# --- Scenario 3: real console (BIB_PROMPT_INPUT readable), verify succeeds -
# Regression: the interactive path real users hit today must be unaffected.
if run_oauth_step 'export BIB_PROMPT_INPUT=/dev/null' \
        'echo https://example.invalid/test-login' \
        'true'; then
    if ! grep -q 'BIB_AGENT_PAUSE' "$TMP_STATE/out"; then
        ok "scenario 3 (console present, verify ok): completes normally, no pause"
    else
        bad "scenario 3 (console present, verify ok): unexpected BIB_AGENT_PAUSE line"
    fi
else
    bad "scenario 3 (console present, verify ok): expected exit 0, got $?: $(cat "$TMP_STATE/out")"
fi

# --- Scenario 4: real console, verify fails — dies as before (regression) --
if run_oauth_step 'export BIB_PROMPT_INPUT=/dev/null' \
        'echo https://example.invalid/test-login' \
        'false'; then
    bad "scenario 4 (console present, verify fails): expected non-zero exit, got 0"
else
    rc=$?
    if [[ "$rc" -ne 78 ]] && grep -qi 'verification failed' "$TMP_STATE/out"; then
        ok "scenario 4 (console present, verify fails): dies with the usual message, not a pause"
    else
        bad "scenario 4 (console present, verify fails): exit=$rc, output: $(cat "$TMP_STATE/out")"
    fi
fi

# --- Scenario 5: real no-controlling-terminal (setsid), default /dev/tty --
# Regression test for the bug found in code review: `[[ -r /dev/tty ]]` is
# true by permission bits alone even with no controlling terminal attached
# — the actual open() fails with ENXIO in that case, not a permission
# error. `_oauth_console_attached` must catch this via a real open attempt.
# Reproduces the real target scenario (an agent driving install.sh over a
# non-pty SSH exec) by fully detaching from any controlling terminal with
# setsid; times out instead of hanging forever if the pause doesn't fire.
cat > "$TMP_STATE/scenario5.sh" <<EOS
set -euo pipefail
export BIB_STATE_DIR="$TMP_STATE/state5"
export BIB_LOG_DIR="$TMP_STATE/log5"
source "${PAYLOAD_DIR}/lib/common.sh"
source "${PAYLOAD_DIR}/lib/prompt.sh"
source "${PAYLOAD_DIR}/lib/oauth.sh"
oauth_step --label TestCLI --url-cmd 'echo https://example.invalid/test-login' --verify false
EOS
if timeout -k 2 10 setsid bash "$TMP_STATE/scenario5.sh" < /dev/null > "$TMP_STATE/out5" 2>&1; then
    bad "scenario 5 (setsid, no controlling terminal): expected exit 78, got 0"
else
    rc=$?
    if [[ "$rc" -eq 78 ]] && grep -q 'BIB_AGENT_PAUSE: step=TestCLI' "$TMP_STATE/out5"; then
        ok "scenario 5 (setsid, no controlling terminal): pauses with exit 78 — reproduces the real no-pty-SSH case"
    elif [[ "$rc" -eq 124 ]]; then
        bad "scenario 5 (setsid, no controlling terminal): TIMED OUT — hung instead of pausing"
    else
        bad "scenario 5 (setsid, no controlling terminal): exit=$rc, output: $(cat "$TMP_STATE/out5")"
    fi
fi

echo "oauth-agent-pause: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
