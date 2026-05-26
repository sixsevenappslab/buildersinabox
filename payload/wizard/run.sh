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
run_step "60-slack-bootstrap.sh"

# Clear the first-boot pending marker so /etc/profile.d/biab-firstboot.sh
# doesn't relaunch the wizard on subsequent logins.
rm -f "${BIB_STATE_DIR}/firstboot.pending"

prompt_header "All set, Paco!"
cat <<'EOF'
Stack installed, logins done, workspace scaffolded, tmux session ready
with Remote Control enabled in every window.

You can unplug the monitor and keyboard now. From here on, everything
happens from your phone.

To connect:
  1. Install the Claude Code app from your phone's app store.
  2. Sign in with the same Claude account you just used in this wizard.
  3. The app will list your three sessions — platform / <your project> /
     stratops — automatically (they appear because Remote Control is on).
  4. Tap any of them. You're inside.

No SSH client. No keys. No host setup. Just the Claude Code app.

You'll land in a session with three windows, each already running your
AI CLI. The first thing to type is /first-project — that's your guided
walkthrough.

Want a fuller guide? `~/README.md` has the list of installed skills and
what to do when something feels off. Read it from any window with
`less ~/README.md`.

(Fallback: if the Claude Code app ever can't reach the device, Termius +
Tailscale SSH still works. See ~/README.md → "Backup access".)

You can unplug the monitor and keyboard now. The device will keep working.
EOF
