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
run_step "40-scaffold.sh"

prompt_header "Setup complete"
cat <<'EOF'
Stack installed, logins done, workspace scaffolded.

Next: a tmux session called 'main' will start with three windows
(Wave 3 — coming soon). For now, the wizard ends here.
EOF
