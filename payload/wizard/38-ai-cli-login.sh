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

# Verification command — runs after the auth subcommand exits.
# For claude: `claude auth status --text` prints lines like
#     Login method: Claude Max account
#     Organization: <name>'s Organization
#     Email: <email>
# when authed, and exits with an error / different output when not. We
# grep for the unique "Login method:" prefix as the success marker.
# For antigravity: `agy models` exits 0 and lists models when authed, exits
#             1 immediately when not (spike T1). It does NOT spend LLM quota
#             or trigger OAuth, so it's the ideal non-interactive health check.
#             stdin is redirected from /dev/null because agy consumes any open
#             stdin. AGY_CLI_DISABLE_AUTO_UPDATE keeps the pinned version put.
case "$cli" in
    claude)
        verify_cmd="su - $target_user -c 'claude auth status --text </dev/null' 2>&1 | grep -q '^Login method:'"
        ;;
    antigravity)
        verify_cmd="su - $target_user -c 'AGY_CLI_DISABLE_AUTO_UPDATE=1 agy models </dev/null' >/dev/null 2>&1"
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
    # Antigravity (agy) logs in through its TUI — there is no headless
    # `agy auth login` subcommand in 1.1.0. We hand the SSH session over to
    # agy; the user picks Google OAuth, copies the URL, and pastes the code
    # back. agy then asks a couple of first-run questions (colour scheme,
    # telemetry, "trust this folder") — the user just accepts them.
    cat <<EOF
Antigravity (agy) logs in through its own screen. We'll launch it now;
a few small things once it opens:

  1. It shows a login menu — choose:  Google OAuth
  2. agy prints a long sign-in URL. Long-press it in Termius to copy
     (it may wrap across several lines — copy the whole thing), open it
     in your phone's browser, and sign in with your Google account.
  3. Paste the "authorization code" it gives you back into agy.
  4. agy may ask a couple of setup questions (colour, telemetry,
     trust this folder). Accept the defaults.
  5. When you're signed in and back at the agy prompt, type:  /quit
     (or Ctrl+D) to hand control back to the installer.

When you exit agy the installer verifies the login and continues.
EOF
    prompt_confirm "Press Enter to launch agy."
    # Launch the agy TUI as the target user. Disable auto-update so the
    # pinned version can't drift mid-setup. Never pass --approve all or
    # --dangerously-skip-permissions — that would nuke agy's permission model.
    sudo -u "$target_user" -H -- env AGY_CLI_DISABLE_AUTO_UPDATE=1 agy || true
fi

# Verify with a 3-second retry to account for token-flush delays.
if ! bash -c "$verify_cmd"; then
    warn "$cli verification failed on first attempt — waiting 3s and retrying"
    sleep 3
    if ! bash -c "$verify_cmd"; then
        # EARS Unwanted: never hang waiting for an impossible local browser —
        # fail with a concrete, followable recovery path instead.
        if [[ "$cli" == "antigravity" ]]; then
            die "agy login could not be verified. To retry: re-run 'sudo /opt/buildersinabox/payload/install.sh' and complete the Google OAuth (choose 'Google OAuth', paste the authorization code). If it keeps failing, confirm you finished the sign-in in the browser — a successful login writes a token to ~${target_user}/.gemini/antigravity-cli/antigravity-oauth-token."
        fi
        die "$cli verification failed. Re-run install.sh to retry the login."
    fi
fi

log "38-ai-cli-login: $cli authenticated for $target_user"
phase_done "ai_cli_done"
