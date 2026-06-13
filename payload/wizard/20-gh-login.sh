#!/usr/bin/env bash
# Wizard step: gh auth login (device flow).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"
# shellcheck source=../lib/oauth.sh
source "${SCRIPT_DIR}/../lib/oauth.sh"

if phase_is_done "gh_done"; then
    log "20-gh-login: already done, skipping"
    exit 0
fi

# Resolve the unprivileged user that will own credentials. Defaults to SUDO_USER.
target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"

# Short-circuit if gh is already authed for the target user.
if su - "$target_user" -c "gh auth status" >/dev/null 2>&1; then
    log "20-gh-login: gh already authenticated for $target_user, marking phase done"
    phase_done "gh_done"
    exit 0
fi

oauth_step \
    --label "GitHub" \
    --url-cmd "su - $target_user -c 'gh auth login --hostname github.com --git-protocol https --web'" \
    --verify "su - $target_user -c 'gh auth status'"

# gh emits "credentials saved in plain text" as a security warning. On a
# headless Ubuntu Server without a desktop keyring that's expected, and
# the file is protected by Unix permissions. Soften the impression so a
# non-technical reader doesn't think something went wrong.
target_home="$(getent passwd "$target_user" | cut -d: -f6)"
chmod 600 "${target_home}/.config/gh/hosts.yml" 2>/dev/null || true
printf '\n  %sNote:%s gh stored your token in ~/.config/gh/hosts.yml.\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}"
printf '  %sThe "plain text" warning above is normal on a headless server%s\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}"
printf '  %s(no desktop keyring). The file is mode 600, owner-only.%s\n\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}"

# Belt-and-suspenders: import the user's GitHub SSH keys into
# ~/.ssh/authorized_keys. Tailscale SSH is the primary access path
# (we set it up in 35-ssh-finalize), but if Tailscale is ever
# unreachable, raw `ssh <username>@<tailscale-ip>` from any machine with
# the user's GitHub key still works. 35-ssh-finalize couldn't do
# this earlier because gh wasn't authenticated yet.
ssh_dir="$(getent passwd "$target_user" | cut -d: -f6)/.ssh"
auth_keys="${ssh_dir}/authorized_keys"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
touch "$auth_keys"
chmod 600 "$auth_keys"
chown -R "$target_user:$target_user" "$ssh_dir"
if keys_json="$(su - "$target_user" -c 'gh api /user/keys --jq ".[].key"' 2>/dev/null)"; then
    added=0
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        if ! grep -Fqx "$key" "$auth_keys"; then
            printf '%s\n' "$key" >> "$auth_keys"
            added=$((added + 1))
        fi
    done <<< "$keys_json"
    log "20-gh-login: imported $added GitHub SSH key(s) for $target_user"
else
    warn "20-gh-login: could not fetch GitHub keys (rare; check gh auth scopes)"
fi

phase_done "gh_done"
