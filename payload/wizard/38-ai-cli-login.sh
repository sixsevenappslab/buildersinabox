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
target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"

# Mock mode: short-circuit without launching the CLI.
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "38-ai-cli-login: mock mode, marking ai_cli_done"
    phase_done "ai_cli_done"
    exit 0
fi

# Verification command — runs after the auth subcommand exits.
# For claude: `claude auth status --text` prints lines like
#     Login method: Claude Max account
#     Organization: <name>'s Organization
#     Email: <email>
# when authed, and exits with an error / different output when not. We
# grep for the unique "Login method:" prefix as the success marker.
# For gemini: there's no headless auth subcommand, so we fall back to a
#             round-trip prompt test.
case "$cli" in
    claude)
        verify_cmd="su - $target_user -c 'claude auth status --text </dev/null' 2>&1 | grep -q '^Login method:'"
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

if [[ "$cli" == "claude" ]]; then
    # Headless OAuth via `claude auth login --claudeai`. Prints the URL
    # and the short device code, then polls until the user authorises in
    # the browser. Exits 0 on success. NO need for the user to type /exit
    # afterwards — control returns to the wizard automatically.
    cat <<EOF
Claude has a one-shot login command. We're going to run it now:

  1. The terminal will print a URL and a short code.

  2. Open the URL on your phone browser (long-press to copy it, then
     paste — or scan if you see a QR), type the code, complete the
     OAuth with your Claude account.

  3. As soon as you approve in the browser, this terminal detects it
     and the installer continues by itself. NOTHING to type back here.

EOF
    prompt_confirm "Press Enter to start the Claude login."
    # Run the headless auth subcommand as the target user.
    sudo -u "$target_user" -H -- claude auth login --claudeai || true
else
    # Gemini still has to use the interactive TUI route — no headless
    # auth subcommand exists today. Same "type /exit when done" caveat.
    cat <<EOF
$cli's first login is an interactive slash command. We'll hand the SSH
session to $cli; four small things once it opens:

  1. Type:  /login
  2. $cli prints an OAuth URL — long-press it in Termius to copy, paste
     into your phone's browser.
  3. Complete the OAuth, paste the auth code back into $cli.
  4. When $cli says you're logged in, type:  /exit  (or Ctrl+D).

When you exit $cli the installer continues by itself.
EOF
    prompt_confirm "Press Enter to launch $cli."
    sudo -u "$target_user" -H -- "$cli" || true
fi

# Verify with a 3-second retry to account for token-flush delays.
if ! bash -c "$verify_cmd"; then
    warn "$cli verification failed on first attempt — waiting 3s and retrying"
    sleep 3
    if ! bash -c "$verify_cmd"; then
        die "$cli verification failed. Re-run install.sh to retry the login."
    fi
fi

log "38-ai-cli-login: $cli authenticated for $target_user"
phase_done "ai_cli_done"
