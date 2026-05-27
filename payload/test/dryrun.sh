#!/usr/bin/env bash
# Wizard dry-run driver. Runs the full bootstrap with mocked OAuth and
# scripted answers, so we can validate the wiring without human input.

set -uo pipefail

# Wipe state and any scaffold artefacts from previous runs.
sudo rm -f /var/lib/buildersinabox/state.json /var/log/buildersinabox/bootstrap.log
sudo rm -rf /home/ubuntu/ai-platform /home/ubuntu/.agents /home/ubuntu/.claude
# Kill any leftover tmux from previous dry-runs.
sudo -u ubuntu tmux kill-server 2>/dev/null || true

# In BIB_OAUTH_MOCK=1, oauth_step returns immediately without prompting.
# When --ai-cli is given on the CLI, 05-choose-cli is skipped.
# So the only prompts that consume input are:
#   1. prompt_confirm "Press Enter to begin" (run.sh)
#   2. prompt_project_name (40-scaffold.sh)
# Two lines: one for prompt_confirm "Press Enter to begin",
# one for the project picker (empty = accept default = finance dashboard,
# project_name auto-resolves to "finance-dashboard").
# $'...' preserves the trailing \n that command substitution would strip.
ANSWERS=$'\n\n'

export BIB_OAUTH_MOCK=1
export BIB_TARGET_USER=ubuntu
export BIB_PROMPT_INPUT=/dev/stdin

printf '%s' "$ANSWERS" | sudo -E /repo/payload/bootstrap.sh --ai-cli=claude
echo "exit=$?"
