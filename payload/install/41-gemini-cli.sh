#!/usr/bin/env bash
# Install the Gemini CLI via npm. Runs only when ai_cli=gemini.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

# Pin Google's published package name. Update here if Google changes it.
GEMINI_NPM_PKG="@google/gemini-cli"

if command -v gemini >/dev/null 2>&1; then
    log "41-gemini-cli: gemini $(gemini --version) already installed, skipping"
    exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
    die "41-gemini-cli: npm is required (install/00-base.sh should have provided it)"
fi

log "41-gemini-cli: npm install -g $GEMINI_NPM_PKG"
npm install -g "$GEMINI_NPM_PKG"

log "41-gemini-cli: done. $(gemini --version)"
