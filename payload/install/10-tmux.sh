#!/usr/bin/env bash
# Install tmux. tmux config + the 3-window launcher script are owned by
# payload/tmux/ and applied in Wave 3 (scaffold step + launch-main.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

log "10-tmux: installing tmux"
apt_update_once
apt_install tmux

log "10-tmux: done. tmux $(tmux -V | awk '{print $2}')"
