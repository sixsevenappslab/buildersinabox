#!/usr/bin/env bash
# Install Tailscale from the official Tailscale apt repo. Does NOT run
# `tailscale up` — that happens in the wizard (Wave 2).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

KEYRING=/usr/share/keyrings/tailscale-archive-keyring.gpg
LISTFILE=/etc/apt/sources.list.d/tailscale.list

if command -v tailscale >/dev/null 2>&1; then
    log "20-tailscale: tailscale $(tailscale version | head -1) already installed, skipping"
    exit 0
fi

log "20-tailscale: adding apt repo"
if [[ ! -f "$KEYRING" ]]; then
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
        | tee "$KEYRING" > /dev/null
fi
if [[ ! -f "$LISTFILE" ]]; then
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
        | tee "$LISTFILE" > /dev/null
fi

log "20-tailscale: apt install tailscale"
DEBIAN_FRONTEND=noninteractive apt-get update -y
apt_install tailscale

log "20-tailscale: done. $(tailscale version | head -1)"
