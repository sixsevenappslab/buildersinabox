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

# Before we open the login URL, explain only the immediate outcome.
wizard_step_header 2 6 "Connect privately" "6 minutes"
cat <<'EOF'
Tailscale creates the private connection between this box and your
phone or laptop. Sign in with the account you will use on that device.
EOF
echo
prompt_confirm "Press Enter to open the Tailscale sign-in page."

oauth_step \
    --label "Tailscale" \
    --url-cmd "tailscale up --hostname=\$(hostname)" \
    --verify "tailscale status"

phase_done "tailscale_done"
