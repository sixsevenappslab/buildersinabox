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

prompt_header "Builders in a Box — setup wizard"
cat <<'EOF'
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

prompt_header "Setup complete"
cat <<'EOF'
Stack installed, logins done, workspace scaffolded, tmux session ready.

To connect from your phone:
  1. Install Termius (or any SSH client).
  2. Add a new host: this device's name on your tailnet (run
     `tailscale status` to see it).
  3. Connect — Tailscale SSH handles auth, no key paste needed.
  4. Once in, run: tmux attach -t main

You'll land in a session with three windows: platform / <your project> / stratops,
each already running your AI CLI.

Want a fuller guide? `~/README.md` has the list of installed skills,
how to type /remote-control to share your session, and what to do when
something feels off. Read it from any tmux window with `less ~/README.md`.

You can unplug the monitor and keyboard now. The device will keep working.
EOF
