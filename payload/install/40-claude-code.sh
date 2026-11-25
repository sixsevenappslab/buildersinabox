#!/usr/bin/env bash
# Install the Claude Code CLI at the version pinned in payload/pins/claude-code
# (FEAT-038). Runs only when ai_cli=claude.
#
# `npm ci` from the committed lockfile into /opt/buildersinabox/tools/claude-code,
# never a global npm install and never "latest": the lockfile's integrity hashes pin
# the whole tree, and `biab update` moves the box to the pin that was tested.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/pins.sh
source "${SCRIPT_DIR}/../lib/pins.sh"

require_root

pin_install_npm_tool "40-claude-code" "claude-code" "@anthropic-ai/claude-code" "claude" pin_bin_claude

log "40-claude-code: done. claude $(pin_probe_version "${PINS_BIN_DIR}/claude")"
