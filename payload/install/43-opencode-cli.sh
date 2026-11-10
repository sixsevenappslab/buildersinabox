#!/usr/bin/env bash
# Install OpenCode (`opencode`) from a pinned, hash-checked GitHub release
# tarball (FEAT-040 T1). Runs only when ai_cli=opencode.
#
# Why the release tarball and not `npm i -g opencode-ai`?
#   The npm package is ~726 MB and runs postinstall scripts, as root, on a
#   box nobody is watching. The release asset is one static binary (a ~60 MB tarball, about 180 MB extracted) with
#   a published sha256, which is what 41-antigravity-cli.sh does for agy.
#   Do not "simplify" this to npm.
#
# It also seeds the permission rules (see seed_permissions below): Paseo's
# daemon (46-paseo.sh) is installed only while OpenCode is known to ask before it
# acts, and that step runs BEFORE the wizard's scaffold, so the rules must exist
# by the time this script ends. Every run (including the no-op one) re-checks them.
#
# The binary lands root-owned at /usr/local/bin/opencode. Every BIAB call to
# OpenCode uses that absolute path: Paseo's daemon PATH does not include
# ~/.local/bin, and a user-planted `opencode` earlier on PATH must never win.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"

# --- Pin (update all three together; source: GitHub release asset digests) ---
# https://github.com/anomalyco/opencode/releases
# Bumping this: re-run `BIAB_GUARD_REAL=1 bash payload/test/cli-guard.sh` (CF-46): the OpenCode guard keys were measured on 1.18.31.
OPENCODE_VERSION="1.18.31"                              # release tag without the "v"
OPENCODE_SHA256_LINUX_X64="e9312be75ed803b7415fc2aeabda1f4fe938912a39673762dc0c38c0e11ebde4"
OPENCODE_SHA256_LINUX_X64_BASELINE="b283e8dbe9e6fc224bb4b79992ce3bd2174b8b7b0c3e7d1b4e6024a1d11edc84"
OPENCODE_RELEASE_BASE="https://github.com/anomalyco/opencode/releases/download"

# TODO(2026-11-05): add an opencode leg to tools/bump-pins.sh and `biab update
# --latest` (FEAT-038 follow-up); until then a bump is these three edits by hand.
# Test seam, same shape as lib/paseo.sh: honoured ONLY for a sandbox prefix
# under /tmp or /var/tmp (no "..", owned by the caller if it exists), so a stray
# variable can never redirect a real install.
OPENCODE_PREFIX=""
OPENCODE_TEST=0
if [[ "${BIB_OPENCODE_TEST:-0}" == "1" ]]; then
    _oc_tp="${BIB_OPENCODE_ROOT_TEST:-}"
    case "$_oc_tp" in
        *..*) ;;
        /tmp/*|/var/tmp/*)
            if [[ ! -e "$_oc_tp" || -O "$_oc_tp" ]]; then
                OPENCODE_TEST=1
                OPENCODE_PREFIX="$_oc_tp"
            fi ;;
    esac
    unset _oc_tp
fi

OPENCODE_INSTALL_PATH="${OPENCODE_PREFIX}/usr/local/bin/opencode"
OPENCODE_MARKER="${OPENCODE_PREFIX}/etc/buildersinabox/opencode.owned"
CANONICAL_PATH="/usr/local/bin/opencode"
VERSION_TIMEOUT=10
UNAME_M="$(uname -m)"
CPUINFO="${OPENCODE_PREFIX}/proc/cpuinfo"

if [[ "$OPENCODE_TEST" == "1" ]]; then
    OPENCODE_VERSION="${BIB_OPENCODE_VERSION-$OPENCODE_VERSION}"
    OPENCODE_SHA256_LINUX_X64="${BIB_OPENCODE_SHA256_X64-$OPENCODE_SHA256_LINUX_X64}"
    OPENCODE_SHA256_LINUX_X64_BASELINE="${BIB_OPENCODE_SHA256_X64_BASELINE-$OPENCODE_SHA256_LINUX_X64_BASELINE}"
    OPENCODE_RELEASE_BASE="${BIB_OPENCODE_BASE_URL-$OPENCODE_RELEASE_BASE}"
    UNAME_M="${BIB_OPENCODE_UNAME_M-$UNAME_M}"
    VERSION_TIMEOUT="${BIB_OPENCODE_VERSION_TIMEOUT-$VERSION_TIMEOUT}"
else
    require_root
fi

# Seed (or complete) the box user's OpenCode permission rules, as that user and
# never through a link: see _ai_cli_seed_settings__opencode in lib/ai-cli.sh.
# Never fails the step; paseo_supports_cli decides at every use whether the rules
# hold. Test seam: BIB_OPENCODE_SEED_HOME (test mode only; without it nothing runs).
seed_permissions() {
    local user home
    if [[ "$OPENCODE_TEST" == "1" ]]; then
        [[ -n "${BIB_OPENCODE_SEED_HOME:-}" ]] || return 0
        home="$BIB_OPENCODE_SEED_HOME"
    else
        user="$(bib_user_resolve)"
        home="$(getent passwd "$user" | cut -d: -f6)"
    fi
    ai_cli_seed_settings opencode "$home" "${home}/ai-platform" || true
}

# An empty or malformed pin is a build bug, not something to download around.
for _oc_hash in "$OPENCODE_SHA256_LINUX_X64" "$OPENCODE_SHA256_LINUX_X64_BASELINE"; do
    [[ "$_oc_hash" =~ ^[0-9a-f]{64}$ ]] \
        || die "43-opencode-cli: digest missing or malformed in the pin ('${_oc_hash}'). Refusing to download an unverifiable binary."
done
unset _oc_hash

# Only x86_64 is pinned; fail loudly rather than install an unverified binary.
if [[ "$UNAME_M" != "x86_64" && "$UNAME_M" != "amd64" ]]; then
    die "43-opencode-cli: unsupported architecture '$UNAME_M'. OpenCode is pinned for x86_64 only; install opencode manually or add a verified checksum for your arch."
fi

# The default build needs AVX2 and crashes without it; the baseline build runs
# everywhere. Anything short of a readable cpuinfo with an avx2 flag is baseline.
# One awk, not `grep | grep -q`: under pipefail the second grep closing the pipe
# early kills the first with SIGPIPE on a many-core machine (a long cpuinfo) and
# the test reads "no avx2" at random (seen in the LXD pass).
if [[ -r "$CPUINFO" ]] && awk '/^flags[[:space:]]*:/ { for (i = 1; i <= NF; i++) if ($i == "avx2") found = 1 } END { exit !found }' "$CPUINFO"; then
    asset="opencode-linux-x64.tar.gz"
    expected_sha="$OPENCODE_SHA256_LINUX_X64"
else
    asset="opencode-linux-x64-baseline.tar.gz"
    expected_sha="$OPENCODE_SHA256_LINUX_X64_BASELINE"
fi

# `biab update --latest` (FEAT-038) has no OpenCode leg yet: there is no published
# digest cross-check wired for it, so the pin is what gets installed.
if [[ "${BIB_PINS_MODE:-pinned}" == "latest" ]]; then
    log "43-opencode-cli: --latest does not cover OpenCode yet; installing the pinned ${OPENCODE_VERSION}"
fi

# Idempotent: skip only when the installed binary reports exactly the pin. The
# first semver-looking token counts, so "v1.18.31" and "opencode 1.18.31" match
# while "1.18.31-beta.1" is a different version. No match, a non-zero exit or a
# hang all mean reinstall (a downgrade is intended).
if [[ -x "$OPENCODE_INSTALL_PATH" ]]; then
    installed="$(timeout "$VERSION_TIMEOUT" "$OPENCODE_INSTALL_PATH" --version </dev/null 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?' | head -n1 || true)"
    if [[ "$installed" == "$OPENCODE_VERSION" ]]; then
        log "43-opencode-cli: opencode ${OPENCODE_VERSION} already installed, skipping"
        seed_permissions
        exit 0
    fi
    log "43-opencode-cli: opencode present but version '${installed}' != pinned '${OPENCODE_VERSION}', reinstalling"
fi

for tool in curl tar sha256sum install; do
    command -v "$tool" >/dev/null 2>&1 \
        || die "43-opencode-cli: '$tool' is required (install/00-base.sh should have provided it)"
done

# Shadow check: resolve `opencode` the way the box user's login shell does. A
# leftover ~/.local/bin/opencode would win over ours for the user's own shell.
if [[ "$OPENCODE_TEST" == "1" ]]; then
    # Seam: an executable that prints what the user's shell would resolve.
    shadow=""
    [[ -n "${BIB_OPENCODE_SHADOW_CMD:-}" && -x "${BIB_OPENCODE_SHADOW_CMD}" ]] && shadow="$("$BIB_OPENCODE_SHADOW_CMD" 2>/dev/null || true)"
else
    shadow="$(su - "$(bib_user_resolve)" -c 'command -v opencode' 2>/dev/null || true)"
fi
if [[ -n "$shadow" && "$shadow" != "$CANONICAL_PATH" ]]; then
    die "43-opencode-cli: another opencode shadows ours on the box user's PATH: ${shadow}. Remove or rename it, then run the step again."
fi

url="${OPENCODE_RELEASE_BASE}/v${OPENCODE_VERSION}/${asset}"

tmp="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$tmp'" EXIT

log "43-opencode-cli: downloading ${asset} (v${OPENCODE_VERSION})"
if ! curl -fsSL "$url" -o "${tmp}/${asset}"; then
    die "43-opencode-cli: failed to download ${url} — check network and that release ${OPENCODE_VERSION} still exists."
fi

log "43-opencode-cli: verifying sha256"
if ! printf '%s  %s\n' "$expected_sha" "${tmp}/${asset}" | sha256sum -c - >/dev/null 2>&1; then
    got="$(sha256sum "${tmp}/${asset}" | awk '{print $1}')"
    die "43-opencode-cli: sha256 mismatch for ${asset} (expected ${expected_sha}, got ${got}). Refusing to install."
fi

log "43-opencode-cli: extracting binary"
tar -xzf "${tmp}/${asset}" -C "$tmp" opencode \
    || die "43-opencode-cli: tarball did not contain the expected 'opencode' binary"

# Ownership marker for uninstall: two lines, the shared marker then the version.
# Written BEFORE the binary moves: a death between the two moves then leaves at
# worst a marker without a binary (uninstall checks the binary first), never a
# binary of ours that uninstall would call foreign.
mkdir -p "$(dirname "$OPENCODE_MARKER")"
printf '%s\n%s\n' "$BIB_OWNERSHIP_MARKER" "$OPENCODE_VERSION" > "${OPENCODE_MARKER}.new"
if [[ "$OPENCODE_TEST" != "1" ]]; then
    chown root:root "${OPENCODE_MARKER}.new"
fi
chmod 0644 "${OPENCODE_MARKER}.new"
mv -f "${OPENCODE_MARKER}.new" "$OPENCODE_MARKER"

# Temp name beside the target, then mv: a crash never leaves a half-written
# binary under the real name.
mkdir -p "$(dirname "$OPENCODE_INSTALL_PATH")"
install -m 0755 "${tmp}/opencode" "${OPENCODE_INSTALL_PATH}.new"
mv -f "${OPENCODE_INSTALL_PATH}.new" "$OPENCODE_INSTALL_PATH"

log "43-opencode-cli: installed opencode -> ${OPENCODE_INSTALL_PATH}"

seed_permissions
