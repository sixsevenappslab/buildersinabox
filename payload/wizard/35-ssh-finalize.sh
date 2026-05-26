#!/usr/bin/env bash
# Wizard step: finalize SSH so the user can reach the box from their phone.
# Defense in depth: Tailscale SSH (set up in 10-tailscale-up.sh via `tailscale up --ssh`)
# as the primary path, plus the user's GitHub SSH keys imported into
# ~/.ssh/authorized_keys as a fallback for raw `ssh ubuntu@<tailscale-ip>`.
#
# Tailscale-only bind of sshd is also applied here (now that Tailscale is up
# we know which interface to listen on).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

if phase_is_done "ssh_finalized"; then
    log "35-ssh-finalize: already done, skipping"
    exit 0
fi

target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"
target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
[[ -n "$target_home" ]] || die "35-ssh-finalize: cannot resolve home for $target_user"

# ---------------------------------------------------------------------------
# 1. Import GitHub SSH keys.
# ---------------------------------------------------------------------------
ssh_dir="${target_home}/.ssh"
auth_keys="${ssh_dir}/authorized_keys"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
touch "$auth_keys"
chmod 600 "$auth_keys"
chown -R "$target_user:$target_user" "$ssh_dir"

if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "35-ssh-finalize: mock mode, skipping GitHub key import"
else
    log "35-ssh-finalize: importing GitHub SSH keys for $target_user"
    # gh requires auth context of the right user. Read keys via the API and
    # append only those not already present.
    if keys_json="$(su - "$target_user" -c 'gh api /user/keys --jq ".[].key"' 2>/dev/null)"; then
        added=0
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            if ! grep -Fqx "$key" "$auth_keys"; then
                printf '%s\n' "$key" >> "$auth_keys"
                added=$((added + 1))
            fi
        done <<< "$keys_json"
        log "35-ssh-finalize: imported $added new GitHub key(s)"
    else
        warn "35-ssh-finalize: could not fetch GitHub keys (gh may be unauthenticated). Skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Bind sshd to the Tailscale interface only.
# ---------------------------------------------------------------------------
# Get the Tailscale IPv4 address. Skip if mock mode or Tailscale not up.
tailscale_ip=""
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "35-ssh-finalize: mock mode, skipping Tailscale-only sshd bind"
else
    if command -v tailscale >/dev/null 2>&1; then
        tailscale_ip="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    fi
fi

if [[ -n "$tailscale_ip" ]]; then
    drop_in=/etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf
    cat > "${drop_in}.tmp" <<EOF
# Managed by Builders in a Box (payload/wizard/35-ssh-finalize.sh).
# Restrict sshd to listen only on the Tailscale interface address.
ListenAddress ${tailscale_ip}
EOF
    mv "${drop_in}.tmp" "$drop_in"
    if sshd -t 2>/dev/null; then
        systemctl reload ssh.service 2>/dev/null || systemctl restart ssh.service
        log "35-ssh-finalize: sshd bound to Tailscale address ${tailscale_ip}"
    else
        rm -f "$drop_in"
        warn "35-ssh-finalize: sshd config check failed, reverted Tailscale bind"
    fi
else
    log "35-ssh-finalize: no Tailscale IP available, leaving sshd on its default bind"
fi

phase_done "ssh_finalized"
