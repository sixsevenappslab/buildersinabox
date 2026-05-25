#!/usr/bin/env bash
# Basic sshd hardening: ensure sshd is installed and enabled, disable
# password authentication, keep key-based auth. The Tailscale-only ListenAddress
# is applied later (Wave 3, after `tailscale up`).

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

# Apply our settings via a drop-in. Idempotent: we overwrite the file each run
# but its contents are deterministic, so reruns produce no real change.
mkdir -p "$SSHD_DROPIN_DIR"
cat > "${SSHD_DROPIN_FILE}.tmp" <<'EOF'
# Managed by Builders in a Box (payload/install/50-ssh.sh).
# Keep ssh available but only via keys. Tailscale-only bind is added later.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
EOF
mv "${SSHD_DROPIN_FILE}.tmp" "$SSHD_DROPIN_FILE"

if ! sshd -t -f "$SSHD_CONFIG" 2>/dev/null; then
    die "50-ssh: sshd config check failed after writing $SSHD_DROPIN_FILE"
fi

log "50-ssh: enabling + reloading ssh.service"
systemctl enable ssh.service >/dev/null 2>&1 || true
# Reload (not restart) so existing sessions survive.
systemctl reload ssh.service 2>/dev/null || systemctl restart ssh.service

log "50-ssh: done. password auth disabled, key auth enforced"
