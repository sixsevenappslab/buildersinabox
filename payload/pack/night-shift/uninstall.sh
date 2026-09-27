#!/usr/bin/env bash
# Builders in a Box night-shift pack — uninstaller (FEAT-025). Idempotent:
# safe to run even if the pack (or parts of it) was never installed.
#
# Removes the timer, the service, the runner, the rendered guard settings, the
# mode file and the whole state tree. Order matters: the timer is disabled
# BEFORE its unit file is deleted, or systemd is left with a dangling symlink
# in timers.target.wants/ trying to fire a unit that no longer exists, every
# night, on a box the user believes we are off.
#
# payload/test/uninstall-contract.sh (cases NS-1..NS-11) runs THIS file for
# real against a sandbox and asserts every path below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "${SCRIPT_DIR}/../../lib/common.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Root is required against the real filesystem. Under the declared test seam
# (NIGHT_PREFIX, set only when BIB_NIGHT_SHIFT_TEST=1) the teardown runs
# against a mktemp -d the caller already owns, and the uninstall contract
# refuses to run as root at all — same shape as FEAT-024's BIB_UNINSTALL_ROOT.
if [[ -z "$NIGHT_PREFIX" ]]; then
    require_root
fi

# The teardown list, spelled out rather than looped out of lib.sh: this list
# IS the contract, and tests/test-pack.sh asserts it has not drifted from the
# constants the installer uses.
night_paths=(
    "${NIGHT_PREFIX}/etc/systemd/system/biab-night-shift.timer"
    "${NIGHT_PREFIX}/etc/systemd/system/biab-night-shift.service"
    "${NIGHT_PREFIX}/usr/local/bin/biab-night-shift"
    "$NIGHT_GUARD_DIR"
    "$NIGHT_MODE_FILE"
    "$NIGHT_UNPROTECTED_OK_FILE"
    "$NIGHT_STATE_DIR"
)

found_anything=0
for p in "${night_paths[@]}"; do
    [[ -e "$p" || -L "$p" ]] || continue
    found_anything=1
    break
done

if [[ "$found_anything" -eq 0 ]]; then
    echo "night-shift pack uninstall: nothing to remove"
    exit 0
fi

# Disable first, delete second (see the header).
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now biab-night-shift.timer >/dev/null 2>&1 \
        || echo "night-shift pack uninstall: timer was not enabled, continuing"
fi

for p in "${night_paths[@]}"; do
    if [[ -e "$p" || -L "$p" ]]; then
        echo "night-shift pack uninstall: removing $p"
        rm -rf -- "$p"
    fi
done

# The parent only goes if it is empty: on a real box `payload/install.sh
# --uninstall` takes the whole of /var/lib/buildersinabox anyway, and on a
# `biab pack remove` we must not take state that is not ours.
rmdir "$NIGHT_ROOT_DIR" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi

echo "night-shift pack uninstall: complete"
exit 0
