#!/usr/bin/env bash
# Install the GitHub CLI from the official apt repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

KEYRING=/etc/apt/keyrings/githubcli-archive-keyring.gpg
LISTFILE=/etc/apt/sources.list.d/github-cli.list

if command -v gh >/dev/null 2>&1; then
    log "30-gh: gh $(gh --version | head -1) already installed, skipping"
    exit 0
fi

log "30-gh: adding apt repo"
mkdir -p /etc/apt/keyrings
chmod 755 /etc/apt/keyrings
if [[ ! -f "$KEYRING" ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee "$KEYRING" > /dev/null
    chmod go+r "$KEYRING"
fi
if [[ ! -f "$LISTFILE" ]]; then
    arch="$(dpkg --print-architecture)"
    printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' \
        "$arch" "$KEYRING" \
        | tee "$LISTFILE" > /dev/null
fi

log "30-gh: apt install gh"
DEBIAN_FRONTEND=noninteractive apt-get update -y
apt_install gh

log "30-gh: done. $(gh --version | head -1)"
