#!/usr/bin/env bash
# Wizard step: create the tmux 'main' session with the three pre-configured
# windows. Runs as the target user (not root). The session persists across
# SSH disconnects, so the user attaches to it from their phone afterwards.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

if phase_is_done "tmux_done"; then
    log "50-tmux: already done, skipping"
    exit 0
fi

target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"

# In mock/dry-run mode the AI CLI isn't logged in, so launching it in tmux
# would just crash. Use a placeholder command that keeps the window open.
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    export BIB_TMUX_LAUNCH_CMD='echo "[mock] AI CLI would run here"; exec bash'
fi

log "50-tmux: launching session as $target_user"
# Drop privileges via sudo -u. We pass the env vars launch-main.sh needs.
sudo -u "$target_user" \
    BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_FILE="$BIB_LOG_FILE" \
    BIB_TMUX_LAUNCH_CMD="${BIB_TMUX_LAUNCH_CMD:-}" \
    HOME="$(getent passwd "$target_user" | cut -d: -f6)" \
    "${PAYLOAD_DIR}/tmux/launch-main.sh"

phase_done "tmux_done"
log "50-tmux: done"
