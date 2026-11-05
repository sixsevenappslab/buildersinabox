#!/usr/bin/env bash
# Unit driver for check_ssh_install_preflight (FEAT-027 R2).
#
# Asserts the fail-closed contract: installing over SSH with no private
# network up yet must warn and require an explicit ack (BIB_SSH_INSTALL_ACK=1
# or a tty confirmation) before continuing, and must abort with no side
# effects when neither is available. Mocks `tailscale` via PATH and /dev/tty
# via a fifo; touches no real sshd and needs no root, so it runs on a plain
# CI runner. It does NOT validate the live VM/VPS lockout scenario — that is
# the manual pass in FEAT-027 R4.

set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "ssh-install-preflight: ok: $*"; pass=$((pass + 1)); }
bad() { echo "ssh-install-preflight: FAIL: $*" >&2; fail=$((fail + 1)); }

# --- Mock bin ---------------------------------------------------------------
MOCK_BIN="$(mktemp -d)"
TMP_STATE="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN" "$TMP_STATE"' EXIT

# tailscale mock: `tailscale status` exit code driven by MOCK_TAILSCALE_UP.
cat > "$MOCK_BIN/tailscale" <<'EOS'
#!/usr/bin/env bash
[[ "$1" == "status" ]] || exit 0
[[ "${MOCK_TAILSCALE_UP:-0}" == "1" ]] && exit 0
exit 1
EOS
# ss mock: `_biab_ssh_session_active`'s fallback for when SSH_CONNECTION/
# SSH_TTY are absent (stripped by plain sudo's env_reset on the real
# `curl | sudo bash` path). Must not see this sandbox's own ambient SSH
# session — MOCK_SS_ESTABLISHED drives what it reports.
cat > "$MOCK_BIN/ss" <<'EOS'
#!/usr/bin/env bash
[[ -n "${MOCK_SS_ESTABLISHED:-}" ]] && printf '%s\n' "$MOCK_SS_ESTABLISHED"
exit 0
EOS
chmod +x "$MOCK_BIN/tailscale" "$MOCK_BIN/ss"
export PATH="$MOCK_BIN:$PATH"
export MOCK_TAILSCALE_UP=0
export MOCK_SS_ESTABLISHED=""

export BIB_STATE_DIR="$TMP_STATE/state"
export BIB_LOG_DIR="$TMP_STATE/log"

# shellcheck source=../lib/common.sh
source "${PAYLOAD_DIR}/lib/common.sh"

run_preflight() {
    # Runs in a subshell: `die` calls exit, and this is the only clean way
    # to assert an exit code without killing the test driver itself.
    (
        unset SSH_CONNECTION SSH_TTY BIB_SSH_INSTALL_ACK NON_INTERACTIVE
        eval "$1"
        check_ssh_install_preflight
    ) < /dev/null > "$TMP_STATE/out" 2>&1
}

# --- Scenario 1: no SSH session — silent pass, no prompt, no warning -------
if run_preflight 'true'; then
    if grep -qi 'warn\|private network' "$TMP_STATE/out"; then
        bad "scenario 1 (console, no SSH): unexpected warning printed"
    else
        ok "scenario 1 (console, no SSH): silent pass"
    fi
else
    bad "scenario 1 (console, no SSH): expected exit 0, got $?"
fi

# --- Scenario 2: SSH session, tailnet already up — silent pass -------------
if run_preflight 'export SSH_CONNECTION="1.2.3.4 1 5.6.7.8 22"; export MOCK_TAILSCALE_UP=1'; then
    ok "scenario 2 (SSH + tailnet up): silent pass"
else
    bad "scenario 2 (SSH + tailnet up): expected exit 0, got $?"
fi

# --- Scenario 3: SSH session, no tailnet, explicit ack — warns, continues --
if run_preflight 'export SSH_CONNECTION="1.2.3.4 1 5.6.7.8 22"; export BIB_SSH_INSTALL_ACK=1'; then
    if grep -qi 'BIB_SSH_INSTALL_ACK=1 set, continuing' "$TMP_STATE/out"; then
        ok "scenario 3 (SSH + no tailnet + ack): warns and continues"
    else
        bad "scenario 3 (SSH + no tailnet + ack): expected warning not found"
    fi
else
    bad "scenario 3 (SSH + no tailnet + ack): expected exit 0, got $?"
fi

# --- Scenario 4: SSH session, no tailnet, no ack, no tty — fails closed ----
# Two valid closed-fail paths depending on whether this environment's
# `/dev/tty` passes the `-r` access check but then fails to open (ENXIO,
# common when there's no controlling terminal at all) or fails `-r` outright:
# either way it must abort with a non-zero exit and no state written.
if run_preflight 'export SSH_CONNECTION="1.2.3.4 1 5.6.7.8 22"'; then
    bad "scenario 4 (SSH + no tailnet + no ack + no tty): expected non-zero exit, got 0"
elif grep -qi 'no tty to confirm\|aborted' "$TMP_STATE/out"; then
    ok "scenario 4 (SSH + no tailnet + no ack + no tty): fails closed"
else
    bad "scenario 4 (SSH + no tailnet + no ack + no tty): wrong error, got: $(cat "$TMP_STATE/out")"
fi

# --- Scenario 5: SSH session, no tailnet, NON_INTERACTIVE=1 — fails closed -
if run_preflight 'export SSH_CONNECTION="1.2.3.4 1 5.6.7.8 22"; export NON_INTERACTIVE=1'; then
    bad "scenario 5 (SSH + no tailnet + non-interactive): expected non-zero exit, got 0"
else
    ok "scenario 5 (SSH + no tailnet + non-interactive): fails closed"
fi

# --- Scenario 6: SSH detected via `ss` only (env vars stripped, as on the
# real `curl | sudo bash` one-liner under plain sudo's env_reset) — must
# still trigger the warning instead of silently returning 0. Regression
# test for the bug where env-var-only detection missed the exact install
# path R2 was written to protect.
if run_preflight 'export MOCK_SS_ESTABLISHED="ESTAB 0 0 10.0.0.5:22 1.2.3.4:5678"; export NON_INTERACTIVE=1'; then
    bad "scenario 6 (SSH via ss only, no env vars): expected non-zero exit, got 0"
else
    ok "scenario 6 (SSH via ss only, no env vars): detected and fails closed"
fi

echo "ssh-install-preflight: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
