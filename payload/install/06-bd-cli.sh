#!/usr/bin/env bash
# Installs /usr/local/bin/bd — the brain-dump capture CLI.
# Idempotent: just copies the payload script every time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

src="${PAYLOAD_DIR}/scripts/bd"
target=/usr/local/bin/bd

if [[ ! -f "$src" ]]; then
    warn "06-bd-cli: source $src not found, skipping"
    exit 0
fi

cp "$src" "$target"
chmod 0755 "$target"
log "06-bd-cli: $target installed"
