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
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root

# BIB_SSH_FORCE_TAILSCALE=1 re-runs this step and applies the Tailscale-only
# bind without asking — the escape hatch for users who first chose to keep
# non-tailnet SSH access and want to harden later.
if [[ "${BIB_SSH_FORCE_TAILSCALE:-0}" != "1" ]] && phase_is_done "ssh_finalized"; then
    log "35-ssh-finalize: already done, skipping"
    exit 0
fi

# Resolve the target user with a state.json fallback so the printed
# BIB_SSH_FORCE_TAILSCALE re-run works from a plain root session too
# (bib_user_resolve dies when it can only see root).
target_user="${BIB_TARGET_USER:-$(state_get '.bib_user')}"
[[ -n "$target_user" ]] || target_user="$(bib_user_resolve)"
target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
[[ -n "$target_home" ]] || die "35-ssh-finalize: cannot resolve home for $target_user"

# ---------------------------------------------------------------------------
# 1. Prepare ~/.ssh and an empty authorized_keys with safe perms.
#    GitHub key import happens later in /tutorial (Beat 2), after gh is
#    actually authenticated. Here we only set up the directory so the
#    import has somewhere to write.
# ---------------------------------------------------------------------------
ssh_dir="${target_home}/.ssh"
auth_keys="${ssh_dir}/authorized_keys"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
touch "$auth_keys"
chmod 600 "$auth_keys"
chown -R "$target_user:$target_user" "$ssh_dir"

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

# ---------------------------------------------------------------------------
# 2b. Lockout guard: binding sshd to the Tailscale address kills every other
#     SSH path — including the public-IP session someone on a VPS is likely
#     connected through RIGHT NOW. If any established SSH session comes from
#     outside the tailnet, make the bind opt-in, and default to keeping
#     current access.
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

if [[ -n "$tailscale_ip" ]]; then
    external_peer=""
    while read -r addr; do
        [[ -z "$addr" ]] && continue
        [[ "$addr" == 127.* || "$addr" == "::1" ]] && continue
        _is_tailnet_addr "$addr" || external_peer="$addr"
    done < <(_ssh_peer_addrs)

    if [[ -n "$external_peer" && "${BIB_SSH_FORCE_TAILSCALE:-0}" != "1" ]]; then
        prompt_header "Heads-up before locking SSH to Tailscale"
        cat <<EOF
There is an active SSH connection to this machine from ${external_peer},
which is NOT on your Tailscale network. (On a VPS, that's probably you,
connected via the public IP.)

The next step normally restricts SSH to your private Tailscale address
only — more secure, but it would cut off connections like that one. If
Tailscale isn't working when you reconnect, you'd be locked out.

Safe order: keep current access now, verify you can reach this box over
Tailscale (ssh ${target_user}@${tailscale_ip} from another terminal),
then apply the restriction with:

  sudo BIB_SSH_FORCE_TAILSCALE=1 \\
      /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh
EOF
        choice="keep-current-access"
        if prompt_choice "Restrict SSH now?" "keep-current-access" "tailscale-only"; then
            choice="$BIB_PROMPT_VALUE"
        else
            warn "35-ssh-finalize: no interactive input — keeping current SSH access"
        fi
        if [[ "$choice" != "tailscale-only" ]]; then
            log "35-ssh-finalize: user kept current SSH access; not binding sshd to Tailscale"
            tailscale_ip=""
        fi
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
