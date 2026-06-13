#!/usr/bin/env bash
# Basic sshd hardening: ensure sshd is installed, listens persistently
# (not via socket activation — that would override our Tailscale-only
# ListenAddress in 35-ssh-finalize.sh), and accepts both password and
# public-key auth. The Tailscale-only ListenAddress is applied later
# in 35-ssh-finalize.sh, after `tailscale up`.
#
# Security model: sshd is reachable only via the Tailscale interface
# (the user's private network). On that interface, password auth is
# acceptable because only the user's own devices are on the tailnet
# by default. Phone-side SSH clients (Termius / ConnectBot / etc.)
# typically only support password or key auth, not Tailscale SSH —
# we choose password for simplicity, with the sudo password the user
# sets in 01-set-password as the credential.

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
# Reload (not restart) so existing sessions survive.
systemctl reload ssh.service 2>/dev/null || systemctl restart ssh.service

log "50-ssh: done. password + key auth enabled, sshd running as service"
