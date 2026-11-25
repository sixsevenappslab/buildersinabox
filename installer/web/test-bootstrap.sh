#!/usr/bin/env bash
# Local harness for installer/web/install.sh. Builds a throwaway bare repo
# from the current tree, then runs the bootstrap against it in dry-run mode
# (no real install). No root, no network needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAKE_REMOTE="$(mktemp -d)/biab-fake-remote.git"
DEST="$(mktemp -d)/opt-biab"
trap 'rm -rf "$(dirname "$FAKE_REMOTE")" "$(dirname "$DEST")"' EXIT

# A bare repo with main = the shippable tree.
git archive HEAD | ( mkdir -p "$DEST.src" && tar -x -C "$DEST.src" )
git init -q --bare -b main "$FAKE_REMOTE"
( cd "$DEST.src" && git init -q -b main && git add -A \
    && git -c user.name=t -c user.email=t@t commit -q -m snapshot \
    && git remote add o "$FAKE_REMOTE" && git push -q o main )

echo "harness: running bootstrap (dry-run) against file://$FAKE_REMOTE"
BIB_OS_OVERRIDE=1 BIB_REPO_URL="file://$FAKE_REMOTE" BIB_DEST="$DEST" BIB_BOOTSTRAP_DRYRUN=1 \
    bash installer/web/install.sh

[ -f "$DEST/payload/install.sh" ] || { echo "FAIL: payload/install.sh missing at $DEST"; exit 1; }
echo "PASS: bootstrap cloned the repo and found payload/install.sh"
