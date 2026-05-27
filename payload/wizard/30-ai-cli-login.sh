#!/usr/bin/env bash
# Wizard step: log into the chosen AI CLI (claude or gemini).
#
# Both CLIs authenticate via an INTERACTIVE slash command (/login) inside
# the running CLI — there is no headless `claude login` or `gemini login`
# subcommand we can capture a URL from. So this step:
#
#  1. Tells the user what to type once the CLI launches.
#  2. Hands the controlling terminal over to the CLI as the target user.
#  3. After the user exits the CLI, verifies authentication actually worked.
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
    log "30-ai-cli-login: already done, skipping"
    exit 0
fi

cli="$(ai_cli_resolve "")"
target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"

# Mock mode: short-circuit without launching the CLI.
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "30-ai-cli-login: mock mode, marking ai_cli_done"
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
        die "30-ai-cli-login: unsupported cli '$cli'"
        ;;
esac

# Already authenticated? Skip cleanly.
if bash -c "$verify_cmd"; then
    log "30-ai-cli-login: $cli already logged in for $target_user, marking phase done"
    phase_done "ai_cli_done"
    exit 0
fi

prompt_header "Login: $cli"
cat <<EOF
The $cli CLI uses an interactive slash command for OAuth — we can't
automate it from this wizard. We'll hand the screen over to $cli now,
and you'll do three small things:

  1. Once $cli opens, type the slash command:
        /login
     (the leading slash is important)

  2. $cli prints a URL. Open it on your phone or laptop and complete
     the OAuth login with your $cli account.

  3. When $cli confirms you're logged in, exit it with:
        /exit
     (or press Ctrl+D)

You'll come back here automatically and the wizard will verify and continue.

PRO TIP — the URL is long. If it's hard to type on your phone or your
phone's OCR can't capture it cleanly from this screen, the easiest
workaround is to SSH into this device from a laptop. Tailscale is
already up (we did that step), so from any computer on your tailnet:

    ssh ${target_user}@\$(hostname)

…and run \`claude\` there instead. The URL appears in your laptop's
terminal where copy-paste works normally. Just press Ctrl+C here to
cancel, do the login from the laptop, then rerun bootstrap.sh.
EOF
prompt_confirm "Press Enter to launch $cli (or Ctrl+C if you want the SSH route)."

# Hand the terminal to the CLI, running as the target user (not root).
# sudo -u with explicit shell so HOME/PATH resolve correctly for the CLI's
# config files. The wizard waits here until the user exits the CLI.
sudo -u "$target_user" -H -- "$cli" || true

# Now verify. Give the user one retry if it fails — sometimes they exit
# Claude/Gemini before the auth file is flushed.
if ! bash -c "$verify_cmd"; then
    warn "$cli verification failed on first attempt — waiting 3s and retrying"
    sleep 3
    if ! bash -c "$verify_cmd"; then
        die "$cli verification failed. Re-run bootstrap.sh to retry the login."
    fi
fi

log "30-ai-cli-login: $cli authenticated for $target_user"
phase_done "ai_cli_done"
