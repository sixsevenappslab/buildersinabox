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
target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"

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

phase_done "gh_done"
