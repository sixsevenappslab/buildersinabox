#!/usr/bin/env bash
# Install the OpenAI Codex CLI via npm, plus what its sandbox needs to work.
# Runs only when ai_cli=codex.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

# Pin OpenAI's published package name. Update here if OpenAI changes it.
CODEX_NPM_PKG="@openai/codex"

# Codex sandboxes every command it runs with bubblewrap. Two things are missing
# on a stock Ubuntu 24.04 box, and without them Codex reports a broken sandbox
# and falls back to asking the user to approve each command by hand — painful
# on a phone, which is where this product is used from.
#
#   1. bwrap is not installed at all, so Codex uses its bundled copy.
#   2. Ubuntu 24.04 sets kernel.apparmor_restrict_unprivileged_userns=1, and
#      bubblewrap needs unprivileged user namespaces.
#
# For (2) we give bwrap its own AppArmor profile granting just `userns`. The fix
# people usually find online is `sysctl kernel.apparmor_restrict_unprivileged_userns=0`,
# which lifts the restriction for every binary on the machine; this grants it to
# one. Verified on a clean 24.04 VM: the warning goes away, the sandbox stays at
# workspace-write, and the global sysctl remains 1.
#
# Best-effort throughout: a box without AppArmor still gets a working Codex.

# Lets us tell our own profile apart from one a future Ubuntu package might ship.
BWRAP_PROFILE_MARKER="# Installed by Builders in a Box so the Codex CLI sandbox can start."

bwrap_apparmor_profile() {
    cat <<PROFILE
$BWRAP_PROFILE_MARKER
# Grants unprivileged user namespaces to bwrap ONLY. The system-wide
# kernel.apparmor_restrict_unprivileged_userns setting is left untouched.
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
PROFILE
}

setup_codex_sandbox() {
    if ! command -v bwrap >/dev/null 2>&1; then
        log "42-codex-cli: installing bubblewrap (Codex sandbox)"
        # Guard the update too, not just the install. Each install/*.sh runs as
        # its own process, so BIB_APT_UPDATED does not carry over from 00-base
        # and this really does hit the network — a transient DNS or apt-lock
        # failure here would take the whole installer down through set -e, for
        # a step that is meant to be optional.
        if apt_update_once; then
            apt_install bubblewrap || warn "42-codex-cli: bubblewrap install failed; Codex will use its bundled copy"
        else
            warn "42-codex-cli: apt update failed; skipping bubblewrap, Codex will use its bundled copy"
        fi
    fi

    if [[ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)" != "1" ]]; then
        return 0
    fi
    if [[ ! -d /etc/apparmor.d ]] || ! command -v apparmor_parser >/dev/null 2>&1; then
        return 0
    fi
    # Canonical already uses the profile-name == file-name == binary-basename
    # convention for half a dozen binaries (Discord, vivaldi-bin, ...), so a
    # future Ubuntu package could start shipping its own /etc/apparmor.d/bwrap.
    # Match on our own marker rather than mere existence, so we can tell "ours,
    # already done" apart from "the distro's, do not touch".
    if [[ -e /etc/apparmor.d/bwrap ]]; then
        if grep -q "$BWRAP_PROFILE_MARKER" /etc/apparmor.d/bwrap 2>/dev/null; then
            log "42-codex-cli: bwrap AppArmor profile already installed by us"
        else
            log "42-codex-cli: /etc/apparmor.d/bwrap exists and is not ours, leaving it alone"
        fi
        return 0
    fi

    log "42-codex-cli: granting /usr/bin/bwrap the userns capability via AppArmor"
    # Best-effort, like the rest of this function: a read-only or full /etc must
    # not abort the whole installer through set -e.
    #
    # Write to a temp file and rename, so a machine that loses power mid-write
    # never ends up with a half-file at the real path — which the marker check
    # above would then read as either "already ours" (leaving invalid AppArmor
    # in place) or "somebody else's" (never retrying). eMMC mini PCs are exactly
    # the hardware this ships to.
    if ! bwrap_apparmor_profile >/etc/apparmor.d/bwrap.tmp 2>/dev/null \
       || ! mv /etc/apparmor.d/bwrap.tmp /etc/apparmor.d/bwrap 2>/dev/null; then
        warn "42-codex-cli: could not write the bwrap AppArmor profile; Codex still works, with a degraded sandbox"
        rm -f /etc/apparmor.d/bwrap.tmp
        return 0
    fi

    if ! apparmor_parser -r /etc/apparmor.d/bwrap 2>/dev/null; then
        warn "42-codex-cli: could not load the bwrap AppArmor profile; removing it"
        rm -f /etc/apparmor.d/bwrap
    fi
}

if command -v codex >/dev/null 2>&1; then
    log "42-codex-cli: codex $(codex --version) already installed"
    setup_codex_sandbox
    exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
    die "42-codex-cli: npm is required (install/00-base.sh should have provided it)"
fi

log "42-codex-cli: npm install -g $CODEX_NPM_PKG"
npm install -g "$CODEX_NPM_PKG"

setup_codex_sandbox

log "42-codex-cli: done. $(codex --version)"
