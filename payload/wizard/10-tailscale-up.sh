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

# Before we open the login URL, say what Tailscale is for and what is needed.
wizard_step_header 2 6 "$(msg wizard.title.private)" "$(msg wizard.eta.min6)"
msg wizard.ts.intro
prompt_confirm "$(msg wizard.confirm.ts_link)"

# A short name, not the machine's full cloud host name (FEAT-046 H9/H12).
ts_name="$(bib_tailscale_hostname)"

oauth_step \
    --label "Tailscale" \
    --url-cmd "tailscale up --hostname=${ts_name}" \
    --verify "tailscale status"

phase_done "tailscale_done"

ts_ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
[[ -n "$ts_ip" ]] || msg_str ts_ip wizard.ts.addr_none
msg_ok wizard.ts.done "$ts_name" "$ts_ip"
