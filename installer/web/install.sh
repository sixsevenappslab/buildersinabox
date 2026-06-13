#!/usr/bin/env bash
# Builders in a Box — one-line installer bootstrap.
#
#   curl -fsSL https://buildersinabox.com/install.sh | sudo bash
#
# This thin script fetches the installer repo and hands off to the real
# installer (payload/install.sh). It's deliberately small so you can read
# it before piping to bash:  curl -fsSL https://buildersinabox.com/install.sh
#
# Env overrides:
#   BIB_OS_OVERRIDE=1       skip the Ubuntu 24.04 check
#   BIB_REF=<tag|branch>    clone a specific ref (default: main)
#   BIB_REPO_URL=<url>      clone from a fork/mirror (default: the public repo)
#   BIB_DEST=<path>         install location (default: /opt/buildersinabox)
#   BIB_BOOTSTRAP_DRYRUN=1  fetch only, don't exec the installer (testing)
# Any extra args (e.g. --flavor=gift) pass through to payload/install.sh.

set -euo pipefail

REPO_URL="${BIB_REPO_URL:-https://github.com/sixsevenapps/buildersinabox-installer}"
REF="${BIB_REF:-main}"
DEST="${BIB_DEST:-/opt/buildersinabox}"

die() { echo "biab install: $*" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------
# Dry-run (testing) fetches into a custom BIB_DEST and never touches apt or
# /opt, so it doesn't require root. The real install does.
if [ "${BIB_BOOTSTRAP_DRYRUN:-0}" != "1" ]; then
    [ "$(id -u)" -eq 0 ] || die "must run as root. Try: curl -fsSL https://buildersinabox.com/install.sh | sudo bash"
fi

if [ "${BIB_OS_OVERRIDE:-0}" != "1" ]; then
    os_id=""; os_ver=""
    if [ -r /etc/os-release ]; then
        os_id="$(. /etc/os-release && echo "${ID:-}")"
        os_ver="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    fi
    if [ "$os_id" != "ubuntu" ] || [ "$os_ver" != "24.04" ]; then
        die "this installer targets Ubuntu 24.04 (detected: ${os_id:-unknown} ${os_ver:-?}). Set BIB_OS_OVERRIDE=1 to proceed anyway."
    fi
fi

# --- Ensure git ------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    echo "biab install: installing git…"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y git >/dev/null 2>&1 || die "could not install git"
fi

# --- Fetch the repo (clone fresh, or update an existing checkout) ----------
if [ -d "$DEST/.git" ]; then
    echo "biab install: updating existing checkout at $DEST"
    git -C "$DEST" fetch --quiet --all || die "git fetch failed"
    git -C "$DEST" checkout --quiet "$REF" || die "git checkout $REF failed"
    git -C "$DEST" pull --quiet --ff-only origin "$REF" 2>/dev/null || true
elif [ -e "$DEST" ] && [ ! -d "$DEST/.git" ]; then
    die "$DEST exists but is not a git checkout. Move it aside or run: rm -rf $DEST, then retry."
else
    echo "biab install: cloning $REPO_URL ($REF) → $DEST"
    cleanup_dest() { rm -rf "$DEST"; }
    trap cleanup_dest ERR
    git clone --quiet --branch "$REF" --depth 1 "$REPO_URL" "$DEST" \
        || die "git clone failed (network? wrong BIB_REF=$REF? repo private?)"
    trap - ERR
fi

INSTALLER="$DEST/payload/install.sh"
[ -x "$INSTALLER" ] || chmod +x "$INSTALLER" 2>/dev/null || true
[ -f "$INSTALLER" ] || die "installer not found at $INSTALLER after fetch"

if [ "${BIB_BOOTSTRAP_DRYRUN:-0}" = "1" ]; then
    echo "biab install: dry-run — fetched to $DEST, would exec $INSTALLER $*"
    exit 0
fi

echo "biab install: handing off to the installer…"
exec "$INSTALLER" "$@"
