#!/usr/bin/env bash
# Base system stack: apt update, build essentials, Node 20 (NodeSource), jq.
# Idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

log "00-base: installing base packages"
apt_update_once
apt_install ca-certificates curl gnupg jq build-essential git qrencode

# Optionally set the timezone. By default we leave the system timezone
# untouched — the operator's box already has whatever they configured.
# Set BIB_TIMEZONE=Area/City to override (e.g. on a fresh autoinstall image
# where the clock is UTC and you want local time on the console).
if [[ -n "${BIB_TIMEZONE:-}" ]] && command -v timedatectl >/dev/null 2>&1; then
    current_tz="$(timedatectl show --property=Timezone --value 2>/dev/null || echo unknown)"
    if [[ "$current_tz" != "$BIB_TIMEZONE" ]]; then
        log "00-base: setting timezone ${BIB_TIMEZONE} (was $current_tz)"
        timedatectl set-timezone "$BIB_TIMEZONE" 2>/dev/null || \
            warn "00-base: could not set timezone (timedatectl returned non-zero)"
    fi
fi

# Node.js 20.x via NodeSource if not already at >= 20.
need_node20=1
if command -v node >/dev/null 2>&1; then
    major="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "$major" -ge 20 ]]; then
        need_node20=0
        log "00-base: node $(node --version) already present, skipping NodeSource"
    fi
fi

if [[ "$need_node20" -eq 1 ]]; then
    log "00-base: installing Node.js 20 via NodeSource"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt_install nodejs
fi

log "00-base: done. node=$(node --version) npm=$(npm --version)"
