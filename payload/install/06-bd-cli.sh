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

# `bd` is a common enough name that someone may already have one. Overwriting it
# silently would be bad on its own; --uninstall then deleting it would take their
# script with us. Only claim the name if it is unclaimed or already ours.
#
# Two ways to be ours, and the second one matters: every bd installed before the
# marker existed has no marker. Matching on the marker alone would classify those
# boxes' own bd as a stranger's the first time the stack_installed phase is reset,
# freezing it forever — no more updates, and uninstall would leave it behind.
# The legacy header line identifies those copies. Keep both checks.
#
# The pattern itself lives in lib/common.sh (FEAT-024): install.sh's
# do_uninstall has to reach the same verdict, and #44 is what happens when the
# two copies drift.
bd_is_ours() {
    bib_path_is_ours "$1" "$BIB_BD_OWNERSHIP_PATTERN"
}

if [[ -e "$target" ]] && ! bd_is_ours "$target"; then
    warn "06-bd-cli: $target already exists and is not ours — leaving it alone"
    warn "06-bd-cli: the brain-dump CLI is still available at $src"
    exit 0
fi

cp "$src" "$target"
chmod 0755 "$target"
log "06-bd-cli: $target installed"
