#!/usr/bin/env bash
# Install the Claude Code CLI via npm. Runs only when ai_cli=claude.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

# Pin Anthropic's published package name. Update here if Anthropic changes it.
CLAUDE_NPM_PKG="@anthropic-ai/claude-code"

if command -v claude >/dev/null 2>&1; then
    log "40-claude-code: claude $(claude --version) already installed, skipping"
    exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
    die "40-claude-code: npm is required (install/00-base.sh should have provided it)"
fi

log "40-claude-code: npm install -g $CLAUDE_NPM_PKG"
npm install -g "$CLAUDE_NPM_PKG"

log "40-claude-code: done. $(claude --version)"
