#!/usr/bin/env bash
# Wizard step: pick the AI CLI. Persists the choice in state.json.
# Skipped if state.ai_cli is already set — which install.sh guarantees today
# (it asks interactively, or takes --ai-cli/BIB_AI_CLI, before the stack
# install). Kept as a fallback for state files that lack ai_cli.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

current="$(state_get '.ai_cli')"
if [[ -n "$current" && "$current" != "null" ]]; then
    log "05-choose-cli: ai_cli already = $current, skipping"
    exit 0
fi

prompt_header "Choose your AI coding CLI"
cat <<'EOF'
This is the CLI that will run in your tmux session after setup,
and the one your coach (if you set it up later) will invoke headlessly.

Both choices have OAuth logins that work from your phone:
  - claude       needs a paid Claude subscription (Pro or above).
  - antigravity  Google's Antigravity CLI (agy) — needs a Google account.
EOF

prompt_choice "Pick one:" "claude" "antigravity" || die "05-choose-cli: aborted"
ai_cli_persist "$BIB_PROMPT_VALUE"
log "05-choose-cli: chose $BIB_PROMPT_VALUE"
