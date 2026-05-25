#!/usr/bin/env bash
# Wizard step: log into the chosen AI CLI (claude or gemini).
# Dispatches based on state.ai_cli.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"
# shellcheck source=../lib/oauth.sh
source "${SCRIPT_DIR}/../lib/oauth.sh"

if phase_is_done "ai_cli_done"; then
    log "30-ai-cli-login: already done, skipping"
    exit 0
fi

cli="$(ai_cli_resolve "")"
target_user="${BIB_TARGET_USER:-${SUDO_USER:-ubuntu}}"

# Verification commands that check whether the CLI is logged in.
case "$cli" in
    claude)
        verify_cmd="su - $target_user -c 'claude /status </dev/null' 2>&1 | grep -q 'Logged in'"
        login_cmd="su - $target_user -c 'claude login'"
        ;;
    gemini)
        # `gemini auth login` triggers the device flow; status is verified by
        # checking that a subsequent `gemini -p` call succeeds quickly.
        verify_cmd="su - $target_user -c 'echo health | gemini -p \"reply with the single word OK\"' 2>&1 | grep -qi 'OK'"
        login_cmd="su - $target_user -c 'gemini auth login'"
        ;;
    *)
        die "30-ai-cli-login: unsupported cli '$cli'"
        ;;
esac

# Short-circuit if already logged in.
if bash -c "$verify_cmd"; then
    log "30-ai-cli-login: $cli already logged in for $target_user, marking phase done"
    phase_done "ai_cli_done"
    exit 0
fi

oauth_step \
    --label "$cli" \
    --url-cmd "$login_cmd" \
    --verify "$verify_cmd"

phase_done "ai_cli_done"
