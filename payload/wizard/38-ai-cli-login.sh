#!/usr/bin/env bash
# Wizard step: log into the chosen AI CLI (claude or antigravity).
#
# This step runs AFTER 36-phone-bridge, which means we are guaranteed to
# be in an SSH session (the user moved to their phone's Termius) where
# copy-paste between the terminal and the mobile browser actually works.
#
#   - claude:      `claude auth login --claudeai` prints a URL + short code,
#                  then returns automatically once the user approves.
#   - antigravity: agy 1.1.0 has NO `agy auth login` subcommand. Login is
#                  the TUI itself: launch `agy`, pick "Google OAuth", it
#                  prints a long OAuth URL, the user signs in on their phone
#                  and pastes the authorization code back (spike T1).
#
# Skipped if the phase is already done. Mock mode short-circuits cleanly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

if phase_is_done "ai_cli_done"; then
    log "38-ai-cli-login: already done, skipping"
    exit 0
fi

cli="$(ai_cli_resolve "")"
target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"

# Mock mode: short-circuit without launching the CLI.
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "38-ai-cli-login: mock mode, marking ai_cli_done"
    phase_done "ai_cli_done"
    exit 0
fi

# Verification command — runs after the auth subcommand exits. Comes from
# the CLI's adapter in lib/ai-cli.sh (non-interactive, no quota spend).
verify_cmd="$(ai_cli_login_verify_cmd "$cli" "$target_user")"

# Already authenticated? Skip cleanly.
if bash -c "$verify_cmd"; then
    log "38-ai-cli-login: $cli already logged in for $target_user, marking phase done"
    phase_done "ai_cli_done"
    exit 0
fi

prompt_header "Login: $cli"

# Intro copy + the CLI's interactive login flow, from the adapter.
ai_cli_login_run "$cli" "$target_user"

# Verify with a 3-second retry to account for token-flush delays. On repeat
# failure, die with the CLI's own recovery hint (never hang waiting for an
# impossible local browser — EARS Unwanted).
if ! bash -c "$verify_cmd"; then
    warn "$cli verification failed on first attempt — waiting 3s and retrying"
    sleep 3
    if ! bash -c "$verify_cmd"; then
        die "$(ai_cli_login_failure_hint "$cli" "$target_user")"
    fi
fi

log "38-ai-cli-login: $cli authenticated for $target_user"
phase_done "ai_cli_done"
