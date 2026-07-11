#!/usr/bin/env bash
# Unit driver for the SSH-finalize decision logic (FEAT-014 T5).
#
# Mocks `ss`, `tailscale`, `sshd` and `systemctl` via PATH, redirects the
# state file and the sshd drop-in dir to temp dirs, sources
# 35-ssh-finalize.sh as a library (BIB_SSH_FINALIZE_LIB=1), and asserts the
# chosen state + drop-ins written + phase stamped for each scenario:
#
#   BIND           — no external SSH peer
#   BIND (tailnet) — inbound peer is on the tailnet
#   HOLD-HARDENED  — external peer + a key in authorized_keys
#   HOLD-OPEN      — external peer + empty authorized_keys
#   FORCE -> BIND  — external peer + no key but BIB_SSH_FORCE_TAILSCALE=1
#   NOOP           — no Tailscale IP
#   idempotent     — BIND re-run leaves the same single drop-in
#
# It touches NO real sshd and needs no root, so it runs on a plain CI runner.
# It does NOT validate the effect on the live listener — that is the manual
# multipass E2E pass (FEAT-014 T6), never CI.

set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "ssh-finalize-decision: ok: $*"; pass=$((pass + 1)); }
bad() { echo "ssh-finalize-decision: FAIL: $*" >&2; fail=$((fail + 1)); }

# --- Mock bin ---------------------------------------------------------------
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN"' EXIT

# systemctl mock: optionally records each invocation (MOCK_SYSTEMCTL_LOG) so a
# scenario can assert reload/restart was — or was NOT — called, and optionally
# fails (MOCK_SYSTEMCTL_FAIL) to simulate a reload that does not apply.
cat > "$MOCK_BIN/systemctl" <<'EOS'
#!/usr/bin/env bash
[[ -n "${MOCK_SYSTEMCTL_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_SYSTEMCTL_LOG"
[[ -n "${MOCK_SYSTEMCTL_FAIL:-}" ]] && exit 1
exit 0
EOS
cat > "$MOCK_BIN/tailscale" <<'EOS'
#!/usr/bin/env bash
# `tailscale ip -4` — used by _rebind_public_socket's anti-lockout re-check.
# Returns MOCK_TAILSCALE_IP (empty by default => interface "down", guard fails).
if [[ "$1" == "ip" ]]; then
    [[ -n "${MOCK_TAILSCALE_IP:-}" ]] && printf '%s\n' "$MOCK_TAILSCALE_IP"
fi
exit 0
EOS
chmod +x "$MOCK_BIN/systemctl" "$MOCK_BIN/tailscale"
export PATH="$MOCK_BIN:$PATH"
# Anti-lockout re-check inputs, reset per new scenario (empty = default).
export MOCK_TAILSCALE_IP=""
export MOCK_SS_LISTEN=""

# sshd mock — `sshd -t` exit code is configurable so a scenario can simulate a
# rejected config (the DANGER-ZONE revert path). Defaults to accepting.
set_sshd() {
    printf '#!/usr/bin/env bash\nexit %s\n' "${1:-0}" > "$MOCK_BIN/sshd"
    chmod +x "$MOCK_BIN/sshd"
}
set_sshd 0

# The `ss` mock answers TWO distinct queries the code makes:
#
#  * established-peer query — `ss -Htn state established '( sport = :22 )'`,
#    read by _ssh_peer_addrs. Real output has NO State column:
#        0 0 100.70.218.107:22 100.95.54.83:46466
#    (Recv-Q Send-Q Local:Port Peer:Port); column 4 is the peer. Driven by
#    MOCK_SS_PEER (empty => no established sessions).
#
#  * listening-socket query — `ss -tlnH 'sport = :22'`, read by
#    _public_listener_present (FEAT-016). Real output:
#        LISTEN 0 4096 0.0.0.0:22 0.0.0.0:*
#    column 4 is the LOCAL addr:port. Driven by MOCK_SS_LISTEN (empty => no
#    listener; 0.0.0.0/[::] => a lingering public socket; 100.x => tailnet-only).
#
# It is written once and branches on its args; set_ss / set_ss_listen just flip
# the env vars it reads.
cat > "$MOCK_BIN/ss" <<'EOS'
#!/usr/bin/env bash
if [[ "$*" == *established* ]]; then
    [[ -n "${MOCK_SS_PEER:-}" ]] && echo "0 0 100.70.218.107:22 ${MOCK_SS_PEER}:54321"
    exit 0
fi
# listening-socket query: ss -tlnH 'sport = :22'
if [[ -n "${MOCK_SS_LISTEN:-}" ]]; then
    if [[ "$MOCK_SS_LISTEN" == *:* && "$MOCK_SS_LISTEN" != *.* ]]; then
        echo "LISTEN 0 4096 [${MOCK_SS_LISTEN}]:22 [::]:*"   # IPv6 local, bracketed
    else
        echo "LISTEN 0 4096 ${MOCK_SS_LISTEN}:22 0.0.0.0:*"
    fi
fi
exit 0
EOS
chmod +x "$MOCK_BIN/ss"
set_ss()        { export MOCK_SS_PEER="${1:-}"; }
set_ss_listen() { export MOCK_SS_LISTEN="${1:-}"; }

# --- Source the finalize functions as a library ----------------------------
export BIB_SSH_FINALIZE_LIB=1
# Point state/log at a throwaway location before sourcing common.sh.
_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN" "$_SCRATCH"' EXIT
export BIB_STATE_DIR="$_SCRATCH/state"
export BIB_STATE_FILE="$_SCRATCH/state/state.json"
export BIB_LOG_DIR="$_SCRATCH/log"
export BIB_SSHD_DROPIN_DIR="$_SCRATCH/dropins"
mkdir -p "$BIB_STATE_DIR" "$BIB_LOG_DIR" "$BIB_SSHD_DROPIN_DIR"
# shellcheck source=../wizard/35-ssh-finalize.sh
source "${PAYLOAD_DIR}/wizard/35-ssh-finalize.sh"

# --- Per-scenario harness ---------------------------------------------------
# Resets the state file + drop-in dir + relevant globals, then runs decide.
SC_DIR=""
run_decide() {
    local ts_ip="$1" auth_keys="$2"
    SC_DIR="$(mktemp -d)"
    # Fresh drop-in dir + state file, wired into the sourced globals.
    BIB_SSHD_DROPIN_DIR="$SC_DIR/dropins"
    SSHD_DROPIN_DIR="$BIB_SSHD_DROPIN_DIR"
    TAILSCALE_DROPIN="${SSHD_DROPIN_DIR}/01-buildersinabox-tailscale.conf"
    BASE_DROPIN="${SSHD_DROPIN_DIR}/00-buildersinabox.conf"
    HARDENING_DROPIN="${SSHD_DROPIN_DIR}/02-buildersinabox-public-hardening.conf"
    # Keep the systemd ordering drop-in writes inside the sandbox too.
    BIB_SSH_SERVICE_DROPIN_DIR="$SC_DIR/systemd"
    SSH_SERVICE_DROPIN_DIR="$BIB_SSH_SERVICE_DROPIN_DIR"
    SSH_SERVICE_DROPIN="${SSH_SERVICE_DROPIN_DIR}/10-buildersinabox-tailscale-wait.conf"
    BIB_STATE_DIR="$SC_DIR/state"
    BIB_STATE_FILE="$BIB_STATE_DIR/state.json"
    BIB_LOG_DIR="$SC_DIR/log"
    # shellcheck disable=SC2034  # read by lib/common.sh logging helpers
    BIB_LOG_FILE="$BIB_LOG_DIR/bootstrap.log"
    mkdir -p "$BIB_SSHD_DROPIN_DIR" "$BIB_STATE_DIR" "$BIB_LOG_DIR"
    # Seed the sshd_config.d exactly like a real box after 50-ssh.sh: the base
    # 00 drop-in (PasswordAuthentication yes, ordering FIRST) plus a later
    # cloud-image drop-in that says "no". sshd honours the FIRST value, so the
    # effective password state is driven by 00 — the whole point of the fix.
    cat > "$BASE_DROPIN" <<'EOF'
# Managed by Builders in a Box (payload/install/50-ssh.sh).
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitRootLogin prohibit-password
PubkeyAuthentication yes
EOF
    cat > "${SSHD_DROPIN_DIR}/60-cloudimg-settings.conf" <<'EOF'
# Later-ordering drop-in that says "no" — ignored by sshd's first-wins rule.
PasswordAuthentication no
EOF
    printf '%s\n' '{"version":2,"phases":{}}' > "$BIB_STATE_FILE"
    BIB_SSH_STATE=""
    # Run quietly; user-facing help text goes to the scenario log.
    ssh_finalize_decide "$ts_ip" "$auth_keys" "testuser" > "$SC_DIR/out.log" 2>&1
}

phase() { jq -r ".phases.$1 // false" "$BIB_STATE_FILE"; }

# Effective PasswordAuthentication as sshd would resolve it: concatenate every
# *.conf drop-in in lexical (Include) order and take the FIRST value seen. This
# mirrors sshd's first-wins precedence without needing a real sshd — the check
# that would have caught the FEAT-014 HOLD-HARDENED no-op.
effective_password_auth() {
    local f
    for f in $(find "$SSHD_DROPIN_DIR" -maxdepth 1 -name '*.conf' | sort); do
        awk 'tolower($1)=="passwordauthentication"{print tolower($2); exit}' "$f"
    done | head -1
}

# Seed authorized_keys files.
KEY_PRESENT="$_SCRATCH/authorized_keys_present"
KEY_EMPTY="$_SCRATCH/authorized_keys_empty"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY test@client\n' > "$KEY_PRESENT"
: > "$KEY_EMPTY"

# === Scenario 1: BIND (no external peer) ===================================
set_ss ""
run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "no-peer -> BIND" || bad "no-peer expected BIND, got '$BIB_SSH_STATE'"
grep -q "ListenAddress 100.100.5.5" "$TAILSCALE_DROPIN" 2>/dev/null \
    && ok "BIND wrote 01 tailscale drop-in" || bad "BIND missing 01 drop-in"
[[ ! -e "$HARDENING_DROPIN" ]] && ok "BIND left no 02 hardening drop-in" || bad "BIND left a 02 drop-in"
[[ "$(phase ssh_finalized)" == "true" ]] && ok "BIND stamped ssh_finalized" || bad "BIND did not stamp ssh_finalized"
# On the tailnet interface password auth is acceptable: base 00 must say yes and
# the effective (first-wins) value must be yes.
grep -q "^PasswordAuthentication yes" "$BASE_DROPIN" && ok "BIND: base 00 keeps PasswordAuthentication yes" || bad "BIND: base 00 not yes"
[[ "$(effective_password_auth)" == "yes" ]] && ok "BIND: effective password auth = yes (tailnet ok)" || bad "BIND: effective password auth != yes (got '$(effective_password_auth)')"
# Anti reboot-lockout: the systemd ordering drop-in must be installed.
[[ -f "$SSH_SERVICE_DROPIN" ]] && ok "BIND installed ssh.service boot-ordering drop-in" || bad "BIND missing systemd boot-ordering drop-in"
grep -q "After=tailscaled.service" "$SSH_SERVICE_DROPIN" 2>/dev/null && ok "BIND ordering: After=tailscaled.service" || bad "BIND ordering missing After=tailscaled"

# === Scenario 2: BIND via inbound tailnet peer ============================
set_ss "100.100.1.1"     # peer on the tailnet => not an external peer
run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "tailnet-peer -> BIND" || bad "tailnet-peer expected BIND, got '$BIB_SSH_STATE'"
[[ "$(phase ssh_finalized)" == "true" ]] && ok "tailnet-peer stamped ssh_finalized" || bad "tailnet-peer did not stamp ssh_finalized"

# === Scenario 3: HOLD-HARDENED (external peer + key) ======================
# The 🔴 bug-1 guard: HOLD-HARDENED must ACTUALLY disable password auth. Since
# sshd honours the FIRST drop-in value and 00 orders first, the disable has to
# land in 00 — writing a later "no" file (the old code) was a silent no-op.
set_ss "203.0.113.5"     # public peer => external peer
run_decide "100.100.5.5" "$KEY_PRESENT"
[[ "$BIB_SSH_STATE" == "HOLD_HARDENED" ]] && ok "external+key -> HOLD-HARDENED" || bad "external+key expected HOLD_HARDENED, got '$BIB_SSH_STATE'"
grep -q "^PasswordAuthentication no" "$BASE_DROPIN" 2>/dev/null \
    && ok "HOLD-HARDENED disabled password in base 00 (where it wins)" || bad "HOLD-HARDENED did not disable password in base 00"
grep -q "^KbdInteractiveAuthentication no" "$BASE_DROPIN" 2>/dev/null \
    && ok "HOLD-HARDENED disabled keyboard-interactive in base 00" || bad "HOLD-HARDENED did not disable kbd-interactive in base 00"
[[ "$(effective_password_auth)" == "no" ]] \
    && ok "HOLD-HARDENED: EFFECTIVE password auth = no (bug-1 guard)" || bad "HOLD-HARDENED: effective password auth still '$(effective_password_auth)' — NO-OP regression!"
[[ ! -e "$TAILSCALE_DROPIN" ]] && ok "HOLD-HARDENED did NOT bind (no 01 drop-in)" || bad "HOLD-HARDENED wrote a bind drop-in"
[[ ! -e "$SSH_SERVICE_DROPIN" ]] && ok "HOLD-HARDENED did NOT install boot-ordering (no bind yet)" || bad "HOLD-HARDENED wrongly installed boot-ordering"
[[ "$(phase ssh_public_hardened)" == "true" ]] && ok "HOLD-HARDENED stamped ssh_public_hardened" || bad "HOLD-HARDENED did not stamp ssh_public_hardened"
[[ "$(phase ssh_finalized)" == "false" ]] && ok "HOLD-HARDENED did NOT stamp ssh_finalized" || bad "HOLD-HARDENED wrongly stamped ssh_finalized"

# === Scenario 4: HOLD-OPEN (external peer + no key) =======================
set_ss "203.0.113.5"
BIB_NON_INTERACTIVE=1 run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "HOLD_OPEN" ]] && ok "external+nokey -> HOLD-OPEN" || bad "external+nokey expected HOLD_OPEN, got '$BIB_SSH_STATE'"
[[ ! -e "$TAILSCALE_DROPIN" && ! -e "$HARDENING_DROPIN" ]] && ok "HOLD-OPEN wrote no drop-ins" || bad "HOLD-OPEN wrote a drop-in"
grep -q "^PasswordAuthentication yes" "$BASE_DROPIN" && ok "HOLD-OPEN left base 00 password auth untouched (yes)" || bad "HOLD-OPEN altered base 00 auth"
[[ "$(phase ssh_finalized)" == "false" ]] && ok "HOLD-OPEN did NOT stamp ssh_finalized" || bad "HOLD-OPEN wrongly stamped ssh_finalized"
[[ "$(phase ssh_public_hardened)" == "false" ]] && ok "HOLD-OPEN did NOT stamp ssh_public_hardened" || bad "HOLD-OPEN wrongly stamped ssh_public_hardened"

# === Scenario 5: FORCE -> BIND (external peer + no key, forced) ===========
set_ss "203.0.113.5"
BIB_SSH_FORCE_TAILSCALE=1 run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "FORCE overrides external peer -> BIND" || bad "FORCE expected BIND, got '$BIB_SSH_STATE'"
grep -q "ListenAddress 100.100.5.5" "$TAILSCALE_DROPIN" 2>/dev/null \
    && ok "FORCE wrote 01 tailscale drop-in" || bad "FORCE missing 01 drop-in"
[[ "$(phase ssh_finalized)" == "true" ]] && ok "FORCE stamped ssh_finalized" || bad "FORCE did not stamp ssh_finalized"

# === Scenario 6: NOOP (no Tailscale IP) ===================================
set_ss ""
run_decide "" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "NOOP" ]] && ok "no tailnet IP -> NOOP" || bad "no tailnet IP expected NOOP, got '$BIB_SSH_STATE'"
[[ "$(phase ssh_finalized)" == "false" ]] && ok "NOOP did NOT stamp ssh_finalized" || bad "NOOP wrongly stamped ssh_finalized"

# === Scenario 7: idempotent BIND re-run ===================================
set_ss ""
run_decide "100.100.5.5" "$KEY_EMPTY"
# Re-run in the same drop-in/state dir.
BIB_SSH_STATE=""
ssh_finalize_decide "100.100.5.5" "$KEY_EMPTY" "testuser" > "$SC_DIR/out2.log" 2>&1
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "BIND re-run stays BIND" || bad "BIND re-run got '$BIB_SSH_STATE'"
count=$(find "$SSHD_DROPIN_DIR" -name '01-buildersinabox-tailscale.conf' | wc -l)
[[ "$count" -eq 1 && ! -e "$HARDENING_DROPIN" ]] && ok "BIND re-run: single 01 drop-in, no 02" || bad "BIND re-run left duplicate/extra drop-ins"

# === Scenario 8: sshd -t rejects config -> revert, no reload, not secured ==
# DANGER ZONE: if the freshly written drop-in fails `sshd -t`, it must be
# removed and the running listener never touched (no reload, no restart, no
# stamp). No external peer here, so the path taken is BIND.
export MOCK_SYSTEMCTL_LOG="$_SCRATCH/systemctl-calls-8.log"
: > "$MOCK_SYSTEMCTL_LOG"
set_ss ""
set_sshd 1               # sshd -t rejects the config
run_decide "100.100.5.5" "$KEY_EMPTY"
set_sshd 0               # restore for later scenarios
[[ "$BIB_SSH_STATE" == "BIND_REVERTED" ]] && ok "sshd -t fail -> BIND_REVERTED" || bad "sshd -t fail expected BIND_REVERTED, got '$BIB_SSH_STATE'"
[[ ! -e "$TAILSCALE_DROPIN" ]] && ok "sshd -t fail: freshly written 01 drop-in removed (revert)" || bad "sshd -t fail left the 01 drop-in"
[[ ! -s "$MOCK_SYSTEMCTL_LOG" ]] && ok "sshd -t fail: no reload/restart called" || bad "sshd -t fail called systemctl: $(tr '\n' ';' < "$MOCK_SYSTEMCTL_LOG")"
[[ "$(phase ssh_finalized)" == "false" ]] && ok "sshd -t fail: not stamped ssh_finalized" || bad "sshd -t fail wrongly stamped ssh_finalized"
unset MOCK_SYSTEMCTL_LOG

# === Scenario 9: reload fails -> revert, NEVER restart, not secured ========
# DANGER ZONE (the 🔴 fix): `sshd -t` passes but `systemctl reload` fails. The
# old code fell back to `systemctl restart`, killing the operator's live
# session. It must now revert the drop-in and leave the listener running — a
# reload attempt is fine, a restart is a lockout and must NOT happen.
export MOCK_SYSTEMCTL_LOG="$_SCRATCH/systemctl-calls-9.log"
: > "$MOCK_SYSTEMCTL_LOG"
export MOCK_SYSTEMCTL_FAIL=1
set_ss ""
set_sshd 0               # sshd -t passes; only the reload fails
run_decide "100.100.5.5" "$KEY_EMPTY"
unset MOCK_SYSTEMCTL_FAIL
[[ "$BIB_SSH_STATE" == "BIND_REVERTED" ]] && ok "reload fail -> BIND_REVERTED" || bad "reload fail expected BIND_REVERTED, got '$BIB_SSH_STATE'"
[[ ! -e "$TAILSCALE_DROPIN" ]] && ok "reload fail: freshly written 01 drop-in removed (revert)" || bad "reload fail left the 01 drop-in"
grep -q 'reload' "$MOCK_SYSTEMCTL_LOG" && ok "reload fail: a reload was attempted" || bad "reload fail: reload was never attempted"
! grep -q 'restart' "$MOCK_SYSTEMCTL_LOG" && ok "reload fail: NEVER fell back to restart (no lockout)" || bad "reload fail fell back to restart: $(tr '\n' ';' < "$MOCK_SYSTEMCTL_LOG")"
[[ "$(phase ssh_finalized)" == "false" ]] && ok "reload fail: not stamped ssh_finalized" || bad "reload fail wrongly stamped ssh_finalized"
unset MOCK_SYSTEMCTL_LOG

# === Scenario 10: REAL sshd -T precedence (bug-1 / bug-3 guard) ============
# The hermetic scenarios above emulate sshd's first-wins rule. Here, when a real
# sshd is present, we prove the effective PasswordAuthentication with the ACTUAL
# parser against the real 00+60 drop-in stack — the check the driver lacked,
# which let the HOLD-HARDENED no-op ship. Skipped (never failed) where sshd is
# unavailable, e.g. some CI runners.
SSHD_BIN=""
for _c in /usr/sbin/sshd sshd; do
    command -v "$_c" >/dev/null 2>&1 && { SSHD_BIN="$(command -v "$_c")"; break; }
done
if [[ -n "$SSHD_BIN" ]]; then
    RS="$(mktemp -d)"
    ssh-keygen -q -t ed25519 -f "$RS/hostkey" -N '' </dev/null
    mkdir -p "$RS/dropins"
    printf 'HostKey %s\nInclude %s/dropins/*.conf\n' "$RS/hostkey" "$RS" > "$RS/sshd_config"
    # Reproduce a real box: base 00 says yes (orders first) + a later cloud-image
    # drop-in says no. sshd's first-wins => effective yes (the bug's ground truth).
    printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication yes\n' > "$RS/dropins/00-buildersinabox.conf"
    printf 'PasswordAuthentication no\n' > "$RS/dropins/60-cloudimg-settings.conf"
    real_pw() { "$SSHD_BIN" -T -f "$RS/sshd_config" 2>/dev/null | awk 'tolower($1)=="passwordauthentication"{print $2}'; }
    [[ "$(real_pw)" == "yes" ]] \
        && ok "real sshd -T: a later 'no' drop-in is IGNORED (reproduces bug-1)" \
        || bad "real sshd -T baseline expected yes, got '$(real_pw)'"
    # Apply the fix the production way — edit the base 00 drop-in.
    ( BASE_DROPIN="$RS/dropins/00-buildersinabox.conf"; _ssh_set_public_auth "no" )
    [[ "$(real_pw)" == "no" ]] \
        && ok "real sshd -T: HOLD-HARDENED edit of base 00 => effective password auth = no" \
        || bad "real sshd -T after 00 edit expected no, got '$(real_pw)'"
    # BIND restores it.
    ( BASE_DROPIN="$RS/dropins/00-buildersinabox.conf"; _ssh_set_public_auth "yes" )
    [[ "$(real_pw)" == "yes" ]] \
        && ok "real sshd -T: BIND restore of base 00 => effective password auth = yes" \
        || bad "real sshd -T after restore expected yes, got '$(real_pw)'"
    rm -rf "$RS"
else
    ok "real sshd -T check skipped (no sshd binary on this runner)"
fi

# === Scenario 11: BIND escalates to restart when a public socket lingers =====
# FEAT-016 core: after the BIND reload, sshd -T is tailnet-only but the kernel
# keeps the old 0.0.0.0:22 socket (a reload can't re-bind sockets). With the
# tailnet addr still present and sshd -t passing, BIND must RESTART ssh.service
# to release that socket now — safe because BIND has no external peer.
export MOCK_SYSTEMCTL_LOG="$_SCRATCH/systemctl-calls-11.log"
: > "$MOCK_SYSTEMCTL_LOG"
set_ss ""                       # no external peer => BIND path (rebind allowed)
set_ss_listen "0.0.0.0"         # a lingering public listener after the reload
export MOCK_TAILSCALE_IP="100.100.5.5"   # tailnet addr still up => guard passes
run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "lingering-socket BIND stays BIND" || bad "lingering-socket expected BIND, got '$BIB_SSH_STATE'"
[[ "$(phase ssh_finalized)" == "true" ]] && ok "lingering-socket BIND stamped ssh_finalized" || bad "lingering-socket BIND did not stamp ssh_finalized"
grep -q 'restart ssh.service' "$MOCK_SYSTEMCTL_LOG" \
    && ok "lingering public socket + tailnet up -> ssh.service RESTART (socket released now)" \
    || bad "lingering public socket did NOT trigger a restart: $(tr '\n' ';' < "$MOCK_SYSTEMCTL_LOG")"
unset MOCK_SYSTEMCTL_LOG
set_ss_listen ""; export MOCK_TAILSCALE_IP=""

# === Scenario 12: guard fails (tailnet addr gone) -> NO restart ==============
# Anti-lockout: never restart into a config that can't bind. If, immediately
# before the restart, the tailnet addr is no longer present, keep the
# reload-applied (reboot-deferred) narrowing and do NOT restart.
export MOCK_SYSTEMCTL_LOG="$_SCRATCH/systemctl-calls-12.log"
: > "$MOCK_SYSTEMCTL_LOG"
set_ss ""
set_ss_listen "0.0.0.0"                 # public socket lingers...
export MOCK_TAILSCALE_IP=""             # ...but tailnet addr is gone => guard fails
run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "guard-fail: bind still applied (BIND)" || bad "guard-fail expected BIND, got '$BIB_SSH_STATE'"
[[ "$(phase ssh_finalized)" == "true" ]] && ok "guard-fail: reload-applied bind still stamped ssh_finalized" || bad "guard-fail did not stamp ssh_finalized"
! grep -q 'restart ssh.service' "$MOCK_SYSTEMCTL_LOG" \
    && ok "guard-fail (tailnet addr gone): NO restart (no lockout; narrows on reboot)" \
    || bad "guard-fail wrongly restarted: $(tr '\n' ';' < "$MOCK_SYSTEMCTL_LOG")"
unset MOCK_SYSTEMCTL_LOG
set_ss_listen ""

# === Scenario 13: listener already tailnet-only -> NO restart ================
# If ss shows only the tailnet ListenAddress (the reload did re-bind, or a fresh
# boot), there is no public socket to release: the escalation is a no-op.
export MOCK_SYSTEMCTL_LOG="$_SCRATCH/systemctl-calls-13.log"
: > "$MOCK_SYSTEMCTL_LOG"
set_ss ""
set_ss_listen "100.100.5.5"             # only the tailnet address is listening
export MOCK_TAILSCALE_IP="100.100.5.5"
run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "tailnet-only listener stays BIND" || bad "tailnet-only listener expected BIND, got '$BIB_SSH_STATE'"
! grep -q 'restart ssh.service' "$MOCK_SYSTEMCTL_LOG" \
    && ok "no public socket present -> NO restart (idempotent no-op)" \
    || bad "tailnet-only listener wrongly restarted: $(tr '\n' ';' < "$MOCK_SYSTEMCTL_LOG")"
unset MOCK_SYSTEMCTL_LOG
set_ss_listen ""; export MOCK_TAILSCALE_IP=""

# === Scenario 14: FORCE path keeps reload-only (NO restart) ==================
# FORCE may run from a public session being migrated; a restart would break its
# "revertible while connected" guarantee. So even with a lingering public socket
# and the tailnet addr up, FORCE must NOT escalate to a restart (§2 decision).
export MOCK_SYSTEMCTL_LOG="$_SCRATCH/systemctl-calls-14.log"
: > "$MOCK_SYSTEMCTL_LOG"
set_ss ""
set_ss_listen "0.0.0.0"
export MOCK_TAILSCALE_IP="100.100.5.5"
BIB_SSH_FORCE_TAILSCALE=1 run_decide "100.100.5.5" "$KEY_EMPTY"
[[ "$BIB_SSH_STATE" == "BIND" ]] && ok "FORCE with lingering socket still BIND" || bad "FORCE expected BIND, got '$BIB_SSH_STATE'"
! grep -q 'restart ssh.service' "$MOCK_SYSTEMCTL_LOG" \
    && ok "FORCE keeps reload-only -> NO socket-rebind restart (stays revertible)" \
    || bad "FORCE wrongly restarted: $(tr '\n' ';' < "$MOCK_SYSTEMCTL_LOG")"
unset MOCK_SYSTEMCTL_LOG
set_ss_listen ""; export MOCK_TAILSCALE_IP=""

# === Scenario 15: ss absent -> _public_listener_present is a safe no-op ======
# The escalation must degrade gracefully when `ss` is missing (return "not
# present" so _rebind_public_socket warns and defers to the reboot narrowing).
_EMPTY_PATH="$(mktemp -d)"
if ( PATH="$_EMPTY_PATH"; _public_listener_present ); then
    bad "ss absent: _public_listener_present should return non-zero (no escalation)"
else
    ok "ss absent: _public_listener_present returns 'not present' (escalation skipped safely)"
fi
rmdir "$_EMPTY_PATH"

# --- Summary ----------------------------------------------------------------
echo "ssh-finalize-decision: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
