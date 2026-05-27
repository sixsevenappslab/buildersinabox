#!/usr/bin/env bash
# Wizard step: log into the chosen AI CLI (claude or gemini).
#
# This step runs AFTER 36-phone-bridge, which means we are guaranteed to
# be in an SSH session (the user moved to their phone's Termius). The
# CLIs authenticate via an INTERACTIVE slash command (/login) inside the
# running CLI — there's no headless 'claude login' subcommand. We hand
# the SSH terminal over to the CLI; the user types /login, the URL
# appears in Termius (copy-pasteable via long-press), they complete OAuth
# in their phone browser, paste the short auth code back into Termius.
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
target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"

# Mock mode: short-circuit without launching the CLI.
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "38-ai-cli-login: mock mode, marking ai_cli_done"
    phase_done "ai_cli_done"
    exit 0
fi

# Verification command — runs after the user reports they finished login.
# Heuristic: if the CLI's status check contains the phrase "Logged in"
# (case-sensitive on the capitalised L), we treat it as authenticated.
# "Not logged in" uses lowercase "logged" so it correctly doesn't match.
case "$cli" in
    claude)
        verify_cmd="su - $target_user -c 'claude /status </dev/null' 2>&1 | grep -q 'Logged in'"
        ;;
    gemini)
        verify_cmd="su - $target_user -c 'echo health | gemini -p \"reply with the single word OK\"' 2>&1 | grep -qi 'OK'"
        ;;
    *)
        die "38-ai-cli-login: unsupported cli '$cli'"
        ;;
esac

# Already authenticated? Skip cleanly.
if bash -c "$verify_cmd"; then
    log "38-ai-cli-login: $cli already logged in for $target_user, marking phase done"
    phase_done "ai_cli_done"
    exit 0
fi

prompt_header "Login: $cli"
cat <<EOF
$cli's first login uses an interactive slash command. We'll hand the
SSH session to $cli now. Four small things to do once it opens:

  1. Type the slash command (leading slash is important):
        /login

  2. $cli prints an OAuth URL. You're in Termius, so long-press the
     URL to copy it, then paste into your phone's browser.

  3. Complete the OAuth login with your Claude account. The browser
     shows a short auth code at the end.

  4. Copy that short code, switch back to Termius, paste it into the
     $cli prompt. When $cli confirms you're logged in, exit with:
        /exit
     (or press Ctrl+D)

You'll come back here automatically; the wizard will verify and continue.
EOF
prompt_confirm "Press Enter to launch $cli."

# Hand the terminal to the CLI, running as the target user (not root).
# sudo -u with -H so HOME resolves for the CLI's config files. The wizard
# waits here until the user exits the CLI.
sudo -u "$target_user" -H -- "$cli" || true

# Verify with a 3-second retry to account for token-flush delays.
if ! bash -c "$verify_cmd"; then
    warn "$cli verification failed on first attempt — waiting 3s and retrying"
    sleep 3
    if ! bash -c "$verify_cmd"; then
        die "$cli verification failed. Re-run bootstrap.sh to retry the login."
    fi
fi

log "38-ai-cli-login: $cli authenticated for $target_user"
phase_done "ai_cli_done"
