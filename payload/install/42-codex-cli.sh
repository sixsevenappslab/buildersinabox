#!/usr/bin/env bash
# Install the OpenAI Codex CLI via npm. Runs only when ai_cli=codex.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

# Pin OpenAI's published package name. Update here if OpenAI changes it.
CODEX_NPM_PKG="@openai/codex"

if command -v codex >/dev/null 2>&1; then
    log "42-codex-cli: codex $(codex --version) already installed, skipping"
    exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
    die "42-codex-cli: npm is required (install/00-base.sh should have provided it)"
fi

log "42-codex-cli: npm install -g $CODEX_NPM_PKG"
npm install -g "$CODEX_NPM_PKG"

log "42-codex-cli: done. $(codex --version)"
