#!/usr/bin/env bash
# Basic sshd hardening: ensure sshd is installed, listens persistently
# (not via socket activation — that would override our Tailscale-only
# ListenAddress in 35-ssh-finalize.sh), and accepts both password and
# public-key auth. The Tailscale-only ListenAddress is applied later
# in 35-ssh-finalize.sh, after `tailscale up`.
#
# Security model: this base drop-in opens a password-capable listener on
# 0.0.0.0 so the operator can complete the console/SSH wizard. It is NOT the
# end state — 35-ssh-finalize.sh restricts the listener to the Tailscale
# interface once Tailscale is up, choosing an anti-lockout path (BIND /
# HOLD-HARDENED / HOLD-OPEN) so a VPS operated over its public IP is never
# cut off mid-session. On the tailnet interface, password auth is acceptable
# because only the user's own devices are on the tailnet by default, and
# phone-side SSH clients (Termius / ConnectBot / etc.) typically support only
# password or key auth, not Tailscale SSH — the sudo password from
# 01-set-password is the credential. See 35-ssh-finalize.sh for the full model.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN_FILE="${SSHD_DROPIN_DIR}/00-buildersinabox.conf"

log "50-ssh: ensuring openssh-server is installed"
if ! dpkg -s openssh-server >/dev/null 2>&1; then
    apt_update_once
    apt_install openssh-server
fi

# Defensive setup before running `sshd -t`. On fresh autoinstall environments,
# two things can be missing:
#  1. Host keys — if openssh-server's postinst didn't run ssh-keygen -A,
#     sshd -t fails with "could not load host key".
#  2. /run/sshd — the privilege separation directory, normally created by
#     systemd-tmpfiles/sshd at first start. sshd -t fails with
#     "Missing privilege separation directory: /run/sshd" if absent.
# Both fixes are idempotent.
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    log "50-ssh: generating missing SSH host keys"
    ssh-keygen -A
fi
mkdir -p /run/sshd
chmod 0755 /run/sshd

# Apply our settings via a drop-in. Idempotent: we overwrite the file each run
# but its contents are deterministic, so reruns produce no real change.
#
# PasswordAuthentication=yes is INTENTIONAL — see header comment for the
# security model. The user's sudo password is the SSH credential, and
# the listener will be Tailscale-only after 35-ssh-finalize runs.
mkdir -p "$SSHD_DROPIN_DIR"
cat > "${SSHD_DROPIN_FILE}.tmp" <<'EOF'
# Managed by Builders in a Box (payload/install/50-ssh.sh).
# Tailscale-only bind is added in 35-ssh-finalize.sh.
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitRootLogin prohibit-password
PubkeyAuthentication yes
EOF
mv "${SSHD_DROPIN_FILE}.tmp" "$SSHD_DROPIN_FILE"

if ! sshd -t -f "$SSHD_CONFIG" 2>/dev/null; then
    die "50-ssh: sshd config check failed after writing $SSHD_DROPIN_FILE"
fi

# Ubuntu 22.04+ uses socket activation (ssh.socket) for SSH by default.
# The socket binds 0.0.0.0:22 and hands connections to sshd via stdin —
# which means sshd's ListenAddress directive is IGNORED in that mode.
# To make Tailscale-only binding work in 35-ssh-finalize.sh, we MUST
# disable the socket and run sshd as a long-running service instead.
log "50-ssh: switching from ssh.socket activation to ssh.service"
systemctl disable --now ssh.socket >/dev/null 2>&1 || true
systemctl enable --now ssh.service >/dev/null 2>&1 || true
# Reload (not restart) so existing sessions survive. If ssh.service won't
# (re)start — e.g. in a constrained VM where the socket/service conflict —
# warn but don't abort the whole install: the stack is otherwise complete
# and SSH can be recovered separately. On real hardware this path succeeds.
systemctl reload ssh.service 2>/dev/null \
    || systemctl restart ssh.service 2>/dev/null \
    || warn "50-ssh: ssh.service did not (re)start cleanly — check 'systemctl status ssh.service'. Continuing."

log "50-ssh: done. password + key auth enabled, sshd running as service"
