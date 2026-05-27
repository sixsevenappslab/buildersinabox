#!/usr/bin/env bash
# Wizard orchestrator. Chains the per-step scripts. Each step is idempotent
# (skips if its phase is already marked done).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root
state_init

# FEAT-004 Wave 1: comfortable visual welcome before any text.
apply_wizard_font
wizard_banner

prompt_header "Hi Paco — let's set up your Builders in a Box"
cat <<'EOF'
We made this for you. In the next 15 minutes you'll have your own
personal AI development environment — accessible from your phone, with
two projects already waiting for you.

We'll walk through a few quick steps. Each step gives you a URL to open
on your phone (or laptop). Read the URL straight from this screen, type
it into your phone's browser, complete the login, and come back here and
press Enter.

Heads up — this wizard will ask you to log into three services:

  1. Tailscale  (https://tailscale.com)   <- private network for SSH from your phone
  2. GitHub     (https://github.com)      <- so this device can clone/commit/push for you
  3. Your AI CLI: Claude Code or Gemini   <- this is what you will be talking to

If you do not have a Tailscale or GitHub account yet, that's fine: the
login page for each one lets you sign up in 30 seconds. Have your phone
or laptop ready, and an email you can check.

You can interrupt at any point with Ctrl+C and rerun the bootstrap to resume.
EOF
prompt_confirm "Press Enter to begin."

run_step() {
    local script="$1"
    local full="${SCRIPT_DIR}/${script}"
    [[ -x "$full" ]] || die "wizard step not executable: $script"
    log "wizard: running $script"
    "$full"
}

run_step "01-set-password.sh"
run_step "05-choose-cli.sh"
run_step "10-tailscale-up.sh"
run_step "20-gh-login.sh"
run_step "30-ai-cli-login.sh"
run_step "35-ssh-finalize.sh"
run_step "40-scaffold.sh"
run_step "50-tmux.sh"

# Note: 60-slack-bootstrap.sh deliberately NOT in the wizard chain.
# Pasting long Slack tokens on a console keyboard is awful. The Slack
# setup is done later via the Claude Code app on the phone (much better
# clipboard), as part of implementing the coach project (FEAT-002 Wave 1).
# The script remains available for power users who prefer the console:
#   sudo /opt/buildersinabox/payload/wizard/60-slack-bootstrap.sh

# Clear the first-boot pending marker so /etc/profile.d/biab-firstboot.sh
# doesn't relaunch the wizard on subsequent logins.
rm -f "${BIB_STATE_DIR}/firstboot.pending"

prompt_header "All set, Paco!"
cat <<'EOF'
Stack installed, logins done, workspace scaffolded, tmux session ready
with Remote Control enabled in every window.

You're done with the keyboard and monitor on this device. From now on,
everything happens on your phone. There are 3 apps to install and one
sequence to remember. Take it slow, do them in order.
EOF

# --- App 1: Claude Code (primary path) ---
printf '\n%s[1/3]%s  %sInstall the Claude Code app on your phone%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}"
cat <<EOF
       App Store: search "Claude" by Anthropic
       Google Play: search "Claude" by Anthropic
       Sign in with the SAME Claude account you just used in this wizard.

       Once signed in, the app discovers this device's three sessions
       automatically (because Remote Control is on in each tmux window):
         - platform
         - $(state_get '.project_name')
         - stratops
       Tap any of them. You are now inside Claude on this device.
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n       %s...or scan to open the app store:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://claude.ai/download" 2>/dev/null | sed 's/^/         /'
fi

# --- App 2: Tailscale (network for SSH fallback) ---
printf '\n%s[2/3]%s  %sInstall Tailscale on your phone%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}"
cat <<'EOF'
       App Store / Google Play: search "Tailscale"
       Sign in with the SAME Tailscale account you used earlier.
       This puts your phone on the same private network as this device.

       Why: it is the foundation of the SSH fallback (step 3) and lets
       you reach the device from anywhere in the world securely.
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n       %s...or scan to install Tailscale:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://tailscale.com/download" 2>/dev/null | sed 's/^/         /'
fi

# --- App 3: Termius (SSH fallback) ---
printf '\n%s[3/3]%s  %sInstall Termius on your phone%s   %s(fallback only)%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_DIM:-}" "${BIB_RESET:-}"
cat <<EOF
       App Store / Google Play: search "Termius"
       This is your backup if the Claude Code app ever cannot reach
       the device. You will rarely need it but it is good to have.

       Setup in Termius:
         - Add a new host
         - Hostname: $(hostname)
         - Username: ${BIB_TARGET_USER:-${SUDO_USER:-paco}}
         - No password / no key — Tailscale SSH handles auth
       Once connected: run \`tmux attach -t main\`
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n       %s...or scan to install Termius:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://termius.com/download" 2>/dev/null | sed 's/^/         /'
fi

# --- First thing to do once inside Claude Code ---
printf '\n%s+----------------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sOnce inside the Claude Code app on your phone:%s         %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+----------------------------------------------------------+%s\n\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF
       Type:   /first-project

       That is your guided first-day walkthrough. I explain GitHub,
       help you put this project on GitHub, and then we open the
       spec that's already waiting in your project's specs/draft/ folder
       and start building it together.

       For the bigger picture first, type /whats-ahead instead.

The full guide is at ~/README.md on this device. To read it later
from inside any session: less ~/README.md

You can now unplug the monitor and keyboard. Your Builders in a Box
is alive, on your tailnet, waiting for your phone to connect.
EOF
