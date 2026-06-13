#!/usr/bin/env bash
# Wizard dry-run driver. Runs the full installer with mocked OAuth and
# scripted answers, so we can validate the wiring without human input.
#
# This is the smoke test for `install.sh --non-interactive`. It exports
# the BIB_* env vars install.sh requires in that mode, plus the mock flag
# the OAuth library checks. The wizard answers are still piped via stdin
# because some wizard sub-steps prompt for project name etc.

set -uo pipefail

# Wipe state and any scaffold artefacts from previous runs.
sudo rm -f /var/lib/buildersinabox/state.json /var/log/buildersinabox/bootstrap.log
sudo rm -rf /home/ubuntu/ai-platform /home/ubuntu/.agents /home/ubuntu/.claude
# Kill any leftover tmux from previous dry-runs.
sudo -u ubuntu tmux kill-server 2>/dev/null || true

# Required env vars for --non-interactive mode (validated by install.sh).
export BIB_USER=ubuntu
export BIB_NAME=""             # Default flavor; no greeting line.
export BIB_FLAVOR=default
export BIB_AI_CLI=claude

# Test-mode env vars used by the existing libraries.
export BIB_OAUTH_MOCK=1
export BIB_TARGET_USER=ubuntu
export BIB_PROMPT_INPUT=/dev/stdin

# In BIB_OAUTH_MOCK=1, oauth_step returns immediately without prompting.
# So the only prompts that consume input are:
#   1. prompt_confirm "Press Enter to begin" (run.sh)
#   2. prompt_project_name (40-scaffold.sh)
# Two lines: one for prompt_confirm "Press Enter to begin",
# one for the project picker (empty = accept default = finance dashboard,
# project_name auto-resolves to "finance-dashboard").
# $'...' preserves the trailing \n that command substitution would strip.
ANSWERS=$'\n\n'

printf '%s' "$ANSWERS" | sudo -E /repo/payload/install.sh --non-interactive
echo "exit=$?"
