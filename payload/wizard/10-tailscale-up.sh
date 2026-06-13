#!/usr/bin/env bash
# Wizard step: tailscale up with device flow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"
# shellcheck source=../lib/oauth.sh
source "${SCRIPT_DIR}/../lib/oauth.sh"

require_root

if phase_is_done "tailscale_done"; then
    log "10-tailscale-up: already done, skipping"
    exit 0
fi

# Short-circuit if Tailscale is already up on this machine.
if tailscale status >/dev/null 2>&1; then
    log "10-tailscale-up: tailscale already up on this device, marking phase done"
    phase_done "tailscale_done"
    exit 0
fi

# Before we open the login URL, explain WHY. Most users have never
# heard of Tailscale; without context the next QR feels random.
prompt_header "Tailscale — the private network for your devices"
cat <<'EOF'
This is the piece that lets your phone reach this mini PC — from
anywhere. Not just at home, not just on the same WiFi. Anywhere.

Imagine a small private network with only your stuff in it: this
device, your phone, your laptop. They can all talk to each other
directly, end-to-end encrypted, no firewall to fight, no port
forwarding, no IP addresses to memorise. From a coffee shop, from a hotel,
from a flight — "ssh <username>@biab" just works.

Without it, this would be a desktop chained to your house.

It's free for personal use. You'll either sign in with an existing
Google / Microsoft / GitHub / Apple account, or create one in
30 seconds with an email.

Sign in on your phone (or laptop) — same account you'll use later
from the Tailscale phone app. Then come back to this screen.
EOF
echo
prompt_confirm "Press Enter to open the Tailscale login URL."

oauth_step \
    --label "Tailscale" \
    --url-cmd "tailscale up --hostname=\$(hostname)" \
    --verify "tailscale status"

phase_done "tailscale_done"
