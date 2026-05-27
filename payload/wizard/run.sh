#!/usr/bin/env bash
# Wizard orchestrator. Two-phase flow:
#
#   PHASE A (console): set up enough for the user to SSH in from their
#   phone — password, CLI choice, Tailscale, GitHub, sshd hardening.
#   At step 36 the wizard pauses with a guide that tells the user to
#   install Tailscale + Termius on their phone and SSH in.
#
#   PHASE B (SSH from phone): the user re-runs bootstrap.sh from the
#   Termius session. The wizard resumes from where it paused, completes
#   Claude's OAuth (where copy-paste between Termius and the mobile
#   browser is easy), scaffolds the workspace, launches tmux, and prints
#   the final 'All set' message.
#
# A wizard step that returns exit code 78 means "pause here cleanly,
# we'll resume in another context" — currently only 36-phone-bridge
# uses this.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root
state_init

# Intro: full welcome on first run, short greeting on resumption.
if ! phase_is_done "password_set"; then
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

About halfway through we'll pause briefly so you can install Tailscale
and Termius on your phone and SSH in. The Claude login is much smoother
from a phone-side terminal than from this monitor, so we wait until then.

If you do not have a Tailscale or GitHub account yet, that's fine: the
login page for each one lets you sign up in 30 seconds. Have your phone
or laptop ready, and an email you can check.

You can interrupt at any point with Ctrl+C and rerun the bootstrap to resume.
EOF
    prompt_confirm "Press Enter to begin."
else
    wizard_banner
    prompt_header "Welcome back, Paco — resuming setup"
    cat <<'EOF'
We paused on the console so you could move to your phone via SSH. You
should be reading this in Termius now. Let's finish where we left off:
Claude login, then your workspace, then tmux. Two minutes.
EOF
    prompt_confirm "Press Enter to continue."
fi

# Each step is idempotent (skips if its phase is already done).
# Exit code 78 from a step is a clean "pause here" signal — used by
# 36-phone-bridge.sh on console to wait for the user to move to phone.
run_step() {
    local script="$1"
    local full="${SCRIPT_DIR}/${script}"
    [[ -x "$full" ]] || die "wizard step not executable: $script"
    log "wizard: running $script"
    local rc=0
    "$full" || rc=$?
    if [[ "$rc" -eq 78 ]]; then
        log "wizard: paused at $script — will resume from another context"
        exit 0
    elif [[ "$rc" -ne 0 ]]; then
        exit "$rc"
    fi
}

run_step "01-set-password.sh"
run_step "05-choose-cli.sh"
run_step "10-tailscale-up.sh"
run_step "20-gh-login.sh"
run_step "35-ssh-finalize.sh"
run_step "36-phone-bridge.sh"      # pauses here on console
run_step "38-ai-cli-login.sh"      # runs in SSH context
run_step "40-scaffold.sh"
run_step "50-tmux.sh"

# Note: 60-slack-bootstrap.sh deliberately NOT in the wizard chain.
# Pasting long Slack tokens on a console keyboard is awful. The Slack
# setup happens later from the Claude Code app on the phone, as part
# of implementing the coach project (FEAT-002 Wave 1).

# Clear the first-boot pending marker so /etc/profile.d/biab-firstboot.sh
# doesn't relaunch the wizard on subsequent logins.
rm -f "${BIB_STATE_DIR}/firstboot.pending"

prompt_header "All set, Paco!"
cat <<EOF
Stack installed, logins done, workspace scaffolded, tmux session ready
with Remote Control enabled in every window.

You're already on your phone in Termius — Tailscale and Termius are
done. One more app to install and then you're in:
EOF

# --- Final step: install the Claude Code app ------------------------------
printf '\n%s[final step]%s  %sInstall the Claude Code app on your phone%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}"
cat <<EOF
       App Store / Google Play: search "Claude" by Anthropic
       Sign in with the SAME Claude account you used in this wizard.

       The app discovers this device's three sessions automatically
       (Remote Control is on in each tmux window):
         - platform
         - $(state_get '.project_name')
         - stratops
       Tap any of them. You are now inside Claude on this device.
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n       %s...or scan to open the app store:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://claude.ai/download" 2>/dev/null | sed 's/^/         /'
fi

# --- What to do first in the app ------------------------------------------
printf '\n%s+----------------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sOnce inside the Claude Code app on your phone:%s         %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+----------------------------------------------------------+%s\n\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<'EOF'
       Type:   /first-project

       That's your guided first-day walkthrough. Claude explains GitHub,
       puts your project on GitHub, and opens the spec already waiting
       in your project's specs/draft/ folder — and you start building.

       For the bigger picture first, type /whats-ahead instead.

The full guide is at ~/README.md on this device. Read it from any
session with: less ~/README.md

You can unplug the monitor and keyboard from the device. Builders in
a Box is alive on your tailnet, waiting for the Claude Code app.
EOF
