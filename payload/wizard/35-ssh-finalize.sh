#!/usr/bin/env bash
# Wizard step: finalize SSH so the user can reach the box from their phone.
# Auth is the account password (set in 01-set-password) or a key. This script
# only prepares an empty ~/.ssh/authorized_keys with safe permissions; the
# GitHub key import happens later, in /tutorial Beat 2, once gh is authenticated
# (see the note at ssh_finalize_main). We do NOT use Tailscale SSH:
# 10-tailscale-up.sh runs plain `tailscale up`, deliberately, because the phone
# SSH clients people actually use (Termius, ConnectBot) speak password and key
# auth only. Full reasoning in install/50-ssh.sh.
#
# Tailscale-only bind of sshd is applied here (now that Tailscale is up we
# know which interface to listen on) — but never in a way that can lock the
# only admin out of their own box. It picks between THREE states:
#
#   BIND          — safe end state. No external SSH session depends on the
#                   public listener (NAT / mini PC, or VPS driven from the
#                   provider's web console), OR an inbound session already
#                   arrives over the tailnet (positive proof of reachability).
#                   => write ListenAddress <tailscale-ip>, drop the public
#                   hardening file if present, sshd -t + reload, stamp
#                   `ssh_finalized`. Public exposure removed. Because a SIGHUP
#                   reload does NOT re-bind sshd's listening sockets, the old
#                   public 0.0.0.0:22 socket would linger until the next reboot
#                   (FEAT-014 E2E finding). So BIND also RESTARTS ssh.service to
#                   release it immediately — safe ONLY here, because BIND is
#                   reached exclusively with no external SSH peer, so no live
#                   external session can be dropped (FEAT-016).
#
#   HOLD-HARDENED — the only SSH session is external (a VPS you're driving
#                   over its public IP) AND a usable key is already in
#                   authorized_keys. => turn OFF password / keyboard-interactive
#                   auth (key-only, not brute-forceable) but keep listening
#                   publicly (no bind yet — no lockout). The auth change is made
#                   in the BASE drop-in (00-buildersinabox.conf), which orders
#                   first and therefore actually wins — a later-ordering "no"
#                   file is ignored by sshd (the FEAT-014 E2E bug). Stamp
#                   `ssh_public_hardened`, NOT `ssh_finalized`, so a later
#                   FORCE re-run completes the bind (which restores password
#                   auth in 00 — fine on the tailnet-only interface).
#
#   HOLD-OPEN     — the only SSH session is external AND authorized_keys is
#                   empty (the password is the only credential). Disabling it
#                   would lock the user out, so auth is left untouched and the
#                   box is NOT stamped as secured. A blocking acknowledgement
#                   makes the residual exposure a conscious choice (never a
#                   silent completion); Beat 2 of /tutorial closes it once a
#                   key exists.
#
# Recovery (documented in SECURITY.md and ~/README.md "If SSH ever fails"):
#   - VPS provider web/serial console:
#       sudo rm -f /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf \
#         /etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf \
#         && sudo systemctl daemon-reload && sudo systemctl reload ssh
#     restores the public 0.0.0.0:22 listener.
#   - Re-apply the bind once the tailnet routes:
#       sudo BIB_SSH_FORCE_TAILSCALE=1 \
#         /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh
#   - Physical console (mini PC): keyboard + monitor, same edit as above.
#
# BIB_SSH_FORCE_TAILSCALE=1 is a documented escape hatch: it binds to the
# tailnet directly WITHOUT verifying tailnet reachability first (a blind
# bind). It stays deliberately blind — it is an advanced, self-inflicted flag.
# Because we `reload` (never `restart`) sshd, an active public session
# survives the bind, so a mistaken FORCE can be reverted while still connected
# (see recovery above). The FEAT-016 socket-rebind restart is therefore NOT
# applied on the FORCE path (only on the non-FORCE BIND path, which is proven to
# have no external peer): a mistaken FORCE must stay revertible while connected,
# so FORCE keeps reload-only and its public socket narrows on the next reboot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

# Where sshd drop-ins live. Overridable so the unit test
# (payload/test/ssh-finalize-decision.sh) can redirect writes to a temp
# directory instead of the real /etc/ssh/sshd_config.d.
SSHD_DROPIN_DIR="${BIB_SSHD_DROPIN_DIR:-/etc/ssh/sshd_config.d}"
TAILSCALE_DROPIN="${SSHD_DROPIN_DIR}/01-buildersinabox-tailscale.conf"
# Base drop-in written by payload/install/50-ssh.sh. It orders FIRST, and sshd
# honours the FIRST value it sees for each keyword, so this is the ONLY place a
# public-interface auth change actually takes effect. HOLD-HARDENED rewrites its
# PasswordAuthentication / KbdInteractiveAuthentication lines to `no`; BIND
# restores them to `yes` (password is fine on the tailnet-only interface).
BASE_DROPIN="${SSHD_DROPIN_DIR}/00-buildersinabox.conf"
# Legacy layout (pre-fix): a later-ordering hardening drop-in that sshd IGNORED
# because 00 wins. Never written any more; only removed if a stale one exists.
HARDENING_DROPIN="${SSHD_DROPIN_DIR}/02-buildersinabox-public-hardening.conf"

# systemd drop-in that keeps ssh.service from binding the Tailscale ListenAddress
# before tailscaled has brought that address up at boot (else bind() fails
# EADDRNOTAVAIL → no listener → reboot lockout). Installed only when BIND is
# applied; removed when the bind is reverted/removed. Overridable for tests.
SSH_SERVICE_DROPIN_DIR="${BIB_SSH_SERVICE_DROPIN_DIR:-/etc/systemd/system/ssh.service.d}"
SSH_SERVICE_DROPIN="${SSH_SERVICE_DROPIN_DIR}/10-buildersinabox-tailscale-wait.conf"

# Chosen state, for logging and for the unit test to assert against:
# BIND | HOLD_HARDENED | HOLD_OPEN | NOOP  (+ *_REVERTED on sshd -t failure).
# shellcheck disable=SC2034  # read by payload/test/ssh-finalize-decision.sh
BIB_SSH_STATE=""

# ---------------------------------------------------------------------------
# Tailnet classification / peer detection
# ---------------------------------------------------------------------------

# Tailnet address spaces: IPv4 CGNAT 100.64.0.0/10, IPv6 fd7a:115c:a1e0::/48.
_is_tailnet_addr() {
    local ip="${1#::ffff:}"
    [[ "$ip" == fd7a:115c:a1e0:* ]] && return 0
    [[ "$ip" == 100.* ]] || return 1
    local second="${ip#100.}"
    second="${second%%.*}"
    [[ "$second" =~ ^[0-9]+$ ]] && (( second >= 64 && second <= 127 ))
}

# List peer addresses of established connections to sshd (port 22).
_ssh_peer_addrs() {
    command -v ss >/dev/null 2>&1 || return 0
    local peer
    while read -r peer; do
        [[ -z "$peer" ]] && continue
        if [[ "$peer" == \[* ]]; then
            peer="${peer#[}"; peer="${peer%%]*}"    # [v6addr]:port
        else
            peer="${peer%:*}"                        # v4addr:port
        fi
        printf '%s\n' "$peer"
    done < <(ss -Htn state established '( sport = :22 )' 2>/dev/null | awk '{print $4}')
}

# Echo the first established SSH peer that is NOT on the tailnet (and not
# loopback). Empty output => no external session depends on the public
# listener, so binding to the tailnet is safe.
_external_ssh_peer() {
    local addr
    while read -r addr; do
        [[ -z "$addr" ]] && continue
        [[ "$addr" == 127.* || "$addr" == "::1" ]] && continue
        if ! _is_tailnet_addr "$addr"; then
            printf '%s\n' "$addr"
            return 0
        fi
    done < <(_ssh_peer_addrs)
}

# authorized_keys has a usable key when it holds at least one non-blank,
# non-comment line.
_authorized_keys_present() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    grep -Eq '^[[:space:]]*[^[:space:]#]' "$f"
}

# Set PasswordAuthentication + KbdInteractiveAuthentication to <yes|no> in the
# BASE drop-in (00-buildersinabox.conf). Because sshd honours the FIRST value
# per keyword and 00 orders first, editing it here is the only change that
# actually takes effect on the public listener — a later "no" drop-in is
# silently ignored (the FEAT-014 E2E bug). Idempotent. Returns non-zero if the
# base drop-in is missing, so callers never mis-stamp "hardened" without having
# actually disabled password auth.
_ssh_set_public_auth() {
    local value="$1"
    [[ -f "$BASE_DROPIN" ]] || return 1
    local tmp="${BASE_DROPIN}.auth.tmp"
    awk -v v="$value" '
        {
            kw = tolower($1)
            if (kw == "passwordauthentication")      { print "PasswordAuthentication " v; pw=1; next }
            if (kw == "kbdinteractiveauthentication") { print "KbdInteractiveAuthentication " v; kbd=1; next }
            print
        }
        END {
            if (!pw)  print "PasswordAuthentication " v
            if (!kbd) print "KbdInteractiveAuthentication " v
        }
    ' "$BASE_DROPIN" > "$tmp" && mv "$tmp" "$BASE_DROPIN"
}

# Install the systemd ordering drop-in so ssh.service waits for the Tailscale
# address before binding at boot (anti reboot-lockout). Idempotent.
_install_ssh_boot_ordering() {
    mkdir -p "$SSH_SERVICE_DROPIN_DIR"
    cat > "${SSH_SERVICE_DROPIN}.tmp" <<'EOF'
# Managed by Builders in a Box (payload/wizard/35-ssh-finalize.sh).
# sshd is bound to the Tailscale ListenAddress (01-buildersinabox-tailscale.conf).
# That address only exists once tailscaled has brought the interface up, so at
# boot sshd must not bind() before then — otherwise bind() fails EADDRNOTAVAIL,
# ssh.service dies with no listener, and the box is unreachable (reboot lockout).
# Order after tailscaled and wait (bounded) for the IPv4 address; if the bind
# still races, retry instead of failing permanently.
[Unit]
After=tailscaled.service
Wants=tailscaled.service
StartLimitIntervalSec=300
StartLimitBurst=20

[Service]
ExecStartPre=/bin/bash -c 'for _ in $(seq 1 60); do [ -n "$(tailscale ip -4 2>/dev/null)" ] && exit 0; sleep 1; done; exit 0'
Restart=on-failure
RestartSec=2
EOF
    mv "${SSH_SERVICE_DROPIN}.tmp" "$SSH_SERVICE_DROPIN"
    systemctl daemon-reload 2>/dev/null || true
}

# Remove the systemd ordering drop-in (used on BIND revert / recovery). Idempotent.
_remove_ssh_boot_ordering() {
    [[ -f "$SSH_SERVICE_DROPIN" ]] || return 0
    rm -f "$SSH_SERVICE_DROPIN"
    rmdir "$SSH_SERVICE_DROPIN_DIR" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# sshd apply helper — validate then reload. NEVER restart: a restart would
# drop live sessions, including the public one the operator may be on — the
# exact lockout the "reload, never restart" model exists to prevent. So a
# failed reload is treated as a failure (return 1) just like a failed
# `sshd -t`: the caller reverts the drop-in it just wrote and leaves the
# running listener untouched. Returns 0 only when `sshd -t` passed AND the
# reload succeeded.
# ---------------------------------------------------------------------------
_sshd_check_and_reload() {
    if ! sshd -t 2>/dev/null; then
        return 1
    fi
    if systemctl reload ssh.service 2>/dev/null; then
        return 0
    fi
    warn "35-ssh-finalize: ssh.service reload failed — leaving the running listener untouched (no restart, no lockout); check 'systemctl status ssh.service'"
    return 1
}

# ---------------------------------------------------------------------------
# Socket rebind (FEAT-016)
# ---------------------------------------------------------------------------

# True (0) when sshd still has a public (all-interfaces / non-tailnet) :22
# listening socket. A SIGHUP reload updates sshd's effective config but does
# NOT re-bind its listening sockets, so after a BIND reload `sshd -T` shows the
# tailnet-only ListenAddress while the kernel keeps the previous 0.0.0.0:22
# socket until the next reboot. Detect that lingering socket so BIND can close
# it now. Guards for `ss` being absent (returns 1 => "nothing to escalate").
_public_listener_present() {
    command -v ss >/dev/null 2>&1 || return 1
    local local_addr
    while read -r local_addr; do
        [[ -z "$local_addr" ]] && continue
        # Strip the :port suffix. IPv6 locals are bracketed: [::]:22 / [fd7a:..]:22.
        if [[ "$local_addr" == \[* ]]; then
            local_addr="${local_addr#[}"; local_addr="${local_addr%%]*}"
        else
            local_addr="${local_addr%:*}"
        fi
        case "$local_addr" in
            127.*|::1)          continue ;;   # loopback — never public
            0.0.0.0|'*'|::)     return 0 ;;   # all-interfaces wildcard => public
        esac
        # Any remaining non-tailnet listener is also public exposure.
        _is_tailnet_addr "$local_addr" || return 0
    done < <(ss -tlnH 'sport = :22' 2>/dev/null | awk '{print $4}')
    return 1
}

# After a successful BIND reload, force sshd to release any lingering public
# :22 socket by RESTARTING ssh.service (a reload/SIGHUP cannot re-bind sockets).
#
# Why a restart is safe HERE and nowhere else: this runs only on the non-FORCE
# BIND path, which ssh_finalize_decide reaches exclusively when there is NO
# external SSH peer (NAT/console => no session at all, or a tailnet-only session
# that reconnects over a proven-up tailnet). By construction no live external
# session depends on the public listener, so a restart cannot cut anyone off —
# the exact condition the "reload, never restart" rule protects elsewhere.
#
# Anti-lockout guards, re-checked IMMEDIATELY before the restart (FEAT-014
# invariant): (a) the tailnet address we bound still exists locally, so bind()
# will succeed — never restart into a config that cannot bind; and (b) sshd -t
# still passes. If either fails, do NOT restart: keep the reload-applied
# (reboot-deferred) narrowing and warn. The boot-ordering drop-in
# (_install_ssh_boot_ordering: After=tailscaled, ExecStartPre waits <=60s for
# the addr, Restart=on-failure) is the recovery net for a bind that still races.
# Best-effort: never changes BIB_SSH_STATE or the ssh_finalized stamp.
_rebind_public_socket() {
    local tailscale_ip="$1"
    if ! command -v ss >/dev/null 2>&1; then
        warn "35-ssh-finalize: ss unavailable; cannot confirm/close the lingering public :22 socket — it narrows on the next reboot"
        return 0
    fi
    _public_listener_present || return 0   # already tailnet-only, nothing to do

    local ip_now=""
    if command -v tailscale >/dev/null 2>&1; then
        ip_now="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    fi
    if [[ "$ip_now" != "$tailscale_ip" ]] || ! sshd -t 2>/dev/null; then
        warn "35-ssh-finalize: public :22 socket still open after reload, but the tailnet-addr / sshd -t re-check failed — NOT restarting (no lockout); it narrows on the next reboot"
        return 0
    fi
    if systemctl restart ssh.service 2>/dev/null; then
        log "35-ssh-finalize: restarted ssh.service to release the lingering public :22 socket (now tailnet-only; no external session existed to drop)"
    else
        warn "35-ssh-finalize: lingering public :22 socket detected but ssh.service restart failed — it narrows on the next reboot; check 'systemctl status ssh.service'"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# State handlers
# ---------------------------------------------------------------------------

# BIND: restrict sshd to the Tailscale address and remove public exposure.
# allow_socket_rebind=1 additionally restarts ssh.service to release the
# lingering public socket (see _rebind_public_socket) — passed only by the
# non-FORCE BIND path, which is proven to have no external peer.
_ssh_bind_tailnet() {
    local tailscale_ip="$1"
    local allow_socket_rebind="${2:-0}"
    mkdir -p "$SSHD_DROPIN_DIR"

    # Back up the base drop-in so a failed reload can be reverted cleanly.
    local base_bak=""
    if [[ -f "$BASE_DROPIN" ]]; then
        base_bak="${BASE_DROPIN}.bak"
        cp -p "$BASE_DROPIN" "$base_bak"
    fi
    # The listener becomes tailnet-only, where password auth is acceptable (only
    # your own devices are on the tailnet, and phone SSH clients use it). Restore
    # it in case a prior HOLD-HARDENED turned it off in the base drop-in.
    _ssh_set_public_auth "yes" || true
    # Drop any stale public-hardening drop-in from the legacy layout.
    rm -f "$HARDENING_DROPIN"

    cat > "${TAILSCALE_DROPIN}.tmp" <<EOF
# Managed by Builders in a Box (payload/wizard/35-ssh-finalize.sh).
# Restrict sshd to listen only on the Tailscale interface address.
ListenAddress ${tailscale_ip}
EOF
    mv "${TAILSCALE_DROPIN}.tmp" "$TAILSCALE_DROPIN"

    # Validate the combined config before touching the running listener.
    if _sshd_check_and_reload; then
        [[ -n "$base_bak" ]] && rm -f "$base_bak"
        # sshd now binds a Tailscale-only address that does not exist until
        # tailscaled is up: order ssh.service after it so a reboot can't lock out.
        _install_ssh_boot_ordering
        phase_done "ssh_finalized"
        BIB_SSH_STATE="BIND"
        log "35-ssh-finalize: sshd bound to Tailscale address ${tailscale_ip} (public exposure removed)"
        # A reload does not re-bind sockets, so the old public 0.0.0.0:22 socket
        # lingers until reboot. On the non-FORCE BIND path (no external peer) it
        # is safe to restart ssh.service now to release it (FEAT-016).
        [[ "$allow_socket_rebind" == "1" ]] && _rebind_public_socket "$tailscale_ip"
        return 0
    fi

    # Revert every change we made this call; leave the running listener as-is.
    # No tailnet ListenAddress remains, so drop any boot-ordering drop-in too
    # (a stale one from a prior successful bind would otherwise linger).
    rm -f "$TAILSCALE_DROPIN"
    [[ -n "$base_bak" ]] && mv "$base_bak" "$BASE_DROPIN"
    _remove_ssh_boot_ordering
    BIB_SSH_STATE="BIND_REVERTED"
    warn "35-ssh-finalize: sshd validate-or-reload failed, reverted Tailscale bind (running listener left as-is, no restart, no lockout)"
    return 1
}

# HOLD-HARDENED: keep the public listener but make it key-only. Password and
# keyboard-interactive auth are turned OFF in the BASE drop-in (00) — NOT in a
# later-ordering file, which sshd would ignore (the FEAT-014 E2E bug). A usable
# key is already present, so key-only is not a lockout.
_ssh_hold_hardened() {
    local target_user="$1" tailscale_ip="$2" external_peer="$3"
    mkdir -p "$SSHD_DROPIN_DIR"

    # Back up the base drop-in so a failed reload can be reverted cleanly.
    local base_bak=""
    if [[ -f "$BASE_DROPIN" ]]; then
        base_bak="${BASE_DROPIN}.bak"
        cp -p "$BASE_DROPIN" "$base_bak"
    fi
    # Disable password auth where it actually wins. If the base drop-in is
    # missing we cannot guarantee the effect, so do NOT stamp hardened.
    if ! _ssh_set_public_auth "no"; then
        BIB_SSH_STATE="HOLD_HARDENED_REVERTED"
        warn "35-ssh-finalize: base sshd drop-in missing, cannot disable password auth safely — not marking hardened"
        return 1
    fi
    # Drop any stale public-hardening drop-in from the legacy layout.
    rm -f "$HARDENING_DROPIN"

    if _sshd_check_and_reload; then
        [[ -n "$base_bak" ]] && rm -f "$base_bak"
        phase_done "ssh_public_hardened"
        BIB_SSH_STATE="HOLD_HARDENED"
        log "35-ssh-finalize: external SSH peer ${external_peer}, key present — hardened public sshd to key-only (no bind yet)"
        _print_reconnect_help "$target_user" "$tailscale_ip"
        return 0
    fi

    [[ -n "$base_bak" ]] && mv "$base_bak" "$BASE_DROPIN"
    BIB_SSH_STATE="HOLD_HARDENED_REVERTED"
    warn "35-ssh-finalize: hardening validate-or-reload failed, reverted (running listener left as-is, no restart, no lockout)"
    return 1
}

# HOLD-OPEN: password is the only credential; leave auth untouched, do NOT
# stamp as secured, and require a conscious acknowledgement of the exposure.
_ssh_hold_open() {
    local target_user="$1" tailscale_ip="$2" external_peer="$3"
    BIB_SSH_STATE="HOLD_OPEN"

    prompt_header "SSH is still open to the internet on this box"
    cat <<EOF
This machine is reachable over SSH from ${external_peer}, which is OUTSIDE
your Tailscale network — and there is no SSH key on file yet, so a password
is the only way in. Disabling it now would lock you out, so Builders in a
Box has NOT marked SSH as secured on this box.

What this means: until you close it, anyone on the internet can try to
brute-force your password over SSH.

To close it, do EITHER of these:

  1. Reconnect to this box over Tailscale, then run:
       ssh ${target_user}@${tailscale_ip}      # verify tailnet reachability
       sudo BIB_SSH_FORCE_TAILSCALE=1 \\
           /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh
     (binds sshd to your private Tailscale address only)

  2. Finish /tutorial in the Claude Code app — Beat 2 imports your GitHub
     SSH key and closes this automatically.

Recovery if you ever get locked out is documented in ~/README.md
("If SSH ever fails") and SECURITY.md.
EOF

    # Blocking acknowledgement (never complete HOLD-OPEN silently). Once
    # acknowledged we don't nag again. Non-interactive escape hatch:
    # BIB_SSH_ACK_PUBLIC_EXPOSURE=1.
    if phase_is_done "ssh_public_exposure_ack"; then
        return 0
    fi
    if [[ "${BIB_SSH_ACK_PUBLIC_EXPOSURE:-0}" == "1" ]]; then
        phase_done "ssh_public_exposure_ack"
        warn "35-ssh-finalize: public SSH exposure acknowledged via BIB_SSH_ACK_PUBLIC_EXPOSURE=1"
        return 0
    fi
    if [[ "${BIB_NON_INTERACTIVE:-0}" == "1" ]]; then
        warn "35-ssh-finalize: non-interactive; SSH left password-exposed on a public interface. Set BIB_SSH_ACK_PUBLIC_EXPOSURE=1 to acknowledge, or reconnect over Tailscale and re-run. Not marking as secured."
        return 0
    fi
    if prompt_choice \
        "I understand my SSH is still exposed to the internet with a password. What now?" \
        "reconnect-over-tailscale-first" \
        "I-understand-continue-exposed-for-now"; then
        if [[ "$BIB_PROMPT_VALUE" == "I-understand-continue-exposed-for-now" ]]; then
            phase_done "ssh_public_exposure_ack"
            warn "35-ssh-finalize: user acknowledged the residual public SSH exposure"
        else
            log "35-ssh-finalize: user chose to reconnect over Tailscale first; not marking secured, will re-check on re-run"
        fi
    else
        warn "35-ssh-finalize: no interactive input to confirm SSH exposure; leaving public listener, not marking secured"
    fi
    return 0
}

# Help text printed after HOLD-HARDENED.
_print_reconnect_help() {
    local target_user="$1" tailscale_ip="$2"
    prompt_header "SSH hardened to key-only (still reachable, not yet tailnet-only)"
    cat <<EOF
You're connected from outside your Tailscale network, so SSH still listens
on the public interface — but password login is now OFF, so it can't be
brute-forced (key-only).

To finish locking SSH to your private Tailscale address only, reconnect over
Tailscale first (so you can't get locked out), then run:

    ssh ${target_user}@${tailscale_ip}      # verify tailnet reachability
    sudo BIB_SSH_FORCE_TAILSCALE=1 \\
        /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh

Recovery if you get locked out is in ~/README.md ("If SSH ever fails")
and SECURITY.md.
EOF
}

# ---------------------------------------------------------------------------
# Decision: pick BIND / HOLD-HARDENED / HOLD-OPEN (or NOOP without a tailnet).
# Separated from the plumbing so the unit test can drive it with mocks.
#   ssh_finalize_decide <tailscale_ip> <authorized_keys_path> <target_user>
# ---------------------------------------------------------------------------
ssh_finalize_decide() {
    local tailscale_ip="$1"
    local auth_keys="$2"
    local target_user="$3"

    if [[ -z "$tailscale_ip" ]]; then
        # shellcheck disable=SC2034  # read by payload/test/ssh-finalize-decision.sh
        BIB_SSH_STATE="NOOP"
        log "35-ssh-finalize: no Tailscale IP available, leaving sshd on its default bind"
        return 0
    fi

    # FORCE re-run: bind directly (blind — no tailnet-reachability check). Keep
    # reload-only (allow_socket_rebind=0): FORCE may run from a public session
    # being migrated, and a restart would break its "revertible while connected"
    # guarantee. The public socket narrows on the next reboot instead (FEAT-016).
    if [[ "${BIB_SSH_FORCE_TAILSCALE:-0}" == "1" ]]; then
        _ssh_bind_tailnet "$tailscale_ip" "0" || true
        return 0
    fi

    local external_peer=""
    external_peer="$(_external_ssh_peer)"

    # No external session depends on the public listener (NAT, or an inbound
    # tailnet session proves reachability) => safe to bind, AND safe to restart
    # ssh.service to release the lingering public socket now (allow_socket_rebind
    # =1): with no external peer there is no live external session to drop.
    if [[ -z "$external_peer" ]]; then
        _ssh_bind_tailnet "$tailscale_ip" "1" || true
        return 0
    fi

    # External SSH session present and not forced: never blind-bind (lockout).
    # Harden to key-only if a key exists; otherwise hold open (no auth change).
    if _authorized_keys_present "$auth_keys"; then
        _ssh_hold_hardened "$target_user" "$tailscale_ip" "$external_peer" || true
    else
        _ssh_hold_open "$target_user" "$tailscale_ip" "$external_peer"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ssh_finalize_main() {
    # BIB_SSH_FORCE_TAILSCALE=1 re-runs this step and applies the bind even
    # once ssh_finalized — the escape hatch for boxes that first held open.
    if [[ "${BIB_SSH_FORCE_TAILSCALE:-0}" != "1" ]] && phase_is_done "ssh_finalized"; then
        log "35-ssh-finalize: already done, skipping"
        return 0
    fi

    # Resolve the target user with a state.json fallback so the printed
    # BIB_SSH_FORCE_TAILSCALE re-run works from a plain root session too
    # (bib_user_resolve dies when it can only see root).
    local target_user target_home
    target_user="${BIB_TARGET_USER:-$(state_get '.bib_user')}"
    [[ -n "$target_user" ]] || target_user="$(bib_user_resolve)"
    target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
    [[ -n "$target_home" ]] || die "35-ssh-finalize: cannot resolve home for $target_user"

    # Prepare ~/.ssh and an empty authorized_keys with safe perms. GitHub key
    # import happens later in /tutorial (Beat 2), after gh is authenticated.
    local ssh_dir auth_keys
    ssh_dir="${target_home}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    touch "$auth_keys"
    chmod 600 "$auth_keys"
    chown -R "$target_user:$target_user" "$ssh_dir"

    # Get the Tailscale IPv4 address. Skip entirely in mock mode (hermetic
    # tests): behave as today — stamp ssh_finalized and return.
    if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
        log "35-ssh-finalize: mock mode, skipping Tailscale-only sshd bind"
        phase_done "ssh_finalized"
        return 0
    fi

    local tailscale_ip=""
    if command -v tailscale >/dev/null 2>&1; then
        tailscale_ip="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    fi

    ssh_finalize_decide "$tailscale_ip" "$auth_keys" "$target_user"
}

# Run unless sourced as a library (the unit test sets BIB_SSH_FINALIZE_LIB=1
# to source the functions without executing).
if [[ "${BIB_SSH_FINALIZE_LIB:-0}" != "1" ]]; then
    require_root
    ssh_finalize_main
fi
