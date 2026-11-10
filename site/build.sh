#!/usr/bin/env bash
# Cloudflare Pages build step. Copies the installer bootstrap into the
# site output so it's served at /install.sh, and fails the build if the
# committed copy ever drifts from the source of truth (installer/web/).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/installer/web/install.sh"
OUT="$ROOT/site/install.sh"

[ -f "$SRC" ] || { echo "build: source bootstrap missing at $SRC" >&2; exit 1; }
cp "$SRC" "$OUT"

# Sanity: served copy must be byte-identical to the source.
if ! diff -q "$SRC" "$OUT" >/dev/null; then
    echo "build: site/install.sh drifted from installer/web/install.sh" >&2
    exit 1
fi
echo "build: site/install.sh in sync with installer/web/install.sh"
