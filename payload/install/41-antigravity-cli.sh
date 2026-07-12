#!/usr/bin/env bash
# Install Google's Antigravity CLI (`agy`) from a pinned GitHub release.
# Runs only when ai_cli=antigravity.
#
# Why a pinned GitHub release and not the official installer?
#   The official `curl https://antigravity.google/cli/install.sh | bash`
#   always fetches "latest" from a Cloud Run manifest and offers no version
#   pin. Un-pinned installs are exactly the mistake we made with the old
#   npm-installed second CLI, so here we download a specific release asset
#   and verify its sha256 before putting anything on PATH. (Spike T1.)
#
# The release tarball is a single Go binary named `antigravity`; the command
# users type is `agy`, so we install it as /usr/local/bin/agy.
#
# No keyring dependencies: agy 1.1.0 persists its OAuth token to a plain
# 0600 file (~/.gemini/antigravity-cli/antigravity-oauth-token) and survives
# reboots WITHOUT gnome-keyring/libsecret/dbus-x11 (verified in spike T1).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

# --- Pin (update all three together; source: GitHub releases page) ----------
# https://github.com/google-antigravity/antigravity-cli/releases
AGY_VERSION="1.1.0"                                    # release tag (no "v")
AGY_SHA256_LINUX_X64="7ee512440af5ed0c819065cd7cc14eec90699214df4be32280ac346f0100577e"
AGY_INSTALL_PATH="/usr/local/bin/agy"

# Antigravity publishes linux assets for x64 and arm64, but only the x64
# checksum is pinned here (the target hardware is x86_64 mini PCs / VMs).
# Fail loudly on other arches rather than install an unverified binary.
arch="$(uname -m)"
if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
    die "41-antigravity-cli: unsupported architecture '$arch'. Antigravity is pinned for x86_64 only; install agy manually or add a verified checksum for your arch."
fi
asset="agy_cli_linux_x64.tar.gz"
expected_sha="$AGY_SHA256_LINUX_X64"

# Idempotent: if the pinned version is already installed, do nothing.
# Extract the semver from `agy --version` rather than matching the whole line —
# the binary may wrap the number in a banner ("agy version 1.1.0"), and a strict
# string compare would silently reinstall on every run.
if command -v agy >/dev/null 2>&1; then
    installed="$(agy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    if [[ "$installed" == "$AGY_VERSION" ]]; then
        log "41-antigravity-cli: agy ${AGY_VERSION} already installed, skipping"
        exit 0
    fi
    log "41-antigravity-cli: agy present but version '${installed}' != pinned '${AGY_VERSION}', reinstalling"
fi

for tool in curl tar sha256sum; do
    command -v "$tool" >/dev/null 2>&1 \
        || die "41-antigravity-cli: '$tool' is required (install/00-base.sh should have provided it)"
done

url="https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/${asset}"

tmp="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$tmp'" EXIT

log "41-antigravity-cli: downloading ${asset} (v${AGY_VERSION})"
if ! curl -fsSL "$url" -o "${tmp}/${asset}"; then
    die "41-antigravity-cli: failed to download ${url} — check network and that release ${AGY_VERSION} still exists."
fi

log "41-antigravity-cli: verifying sha256"
if ! printf '%s  %s\n' "$expected_sha" "${tmp}/${asset}" | sha256sum -c - >/dev/null 2>&1; then
    got="$(sha256sum "${tmp}/${asset}" | awk '{print $1}')"
    die "41-antigravity-cli: sha256 mismatch for ${asset} (expected ${expected_sha}, got ${got}). Refusing to install."
fi

log "41-antigravity-cli: extracting binary"
tar -xzf "${tmp}/${asset}" -C "$tmp" antigravity \
    || die "41-antigravity-cli: tarball did not contain the expected 'antigravity' binary"

install -m 0755 "${tmp}/antigravity" "$AGY_INSTALL_PATH"

log "41-antigravity-cli: installed agy -> ${AGY_INSTALL_PATH}"
log "41-antigravity-cli: done. $(agy --version 2>/dev/null || echo '(version check failed)')"
