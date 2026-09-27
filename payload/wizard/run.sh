#!/usr/bin/env bash
# Wizard orchestrator. Two-phase flow:
#
#   PHASE A (console): set up enough for the user to SSH in from their
#   phone — password, CLI choice, Tailscale, GitHub, sshd hardening.
#   At step 36 the wizard pauses with a guide that tells the user to
#   install Tailscale + Termius on their phone and SSH in.
#
#   PHASE B (SSH from phone): the user re-runs install.sh from the
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
BIB_INSTALL_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export BIB_INSTALL_ROOT
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root
state_init

# Hydrate BIB_NAME from state so display strings substitute consistently
# even when the wizard is launched via the firstboot trigger (no env vars).
: "${BIB_NAME:=$(state_get '.bib_name')}"
export BIB_NAME

# Source the flavor manifest (default | gift) so wizard_banner and
# BIB_FLAVOR_COPY_DIR are wired to the right copy set. The flavor was
# persisted by install.sh into state.json; fall back to default if state
# doesn't have it yet (very early wizard launches).
_flavor="$(state_get '.flavor')"
: "${_flavor:=default}"
_flavor_manifest="${SCRIPT_DIR}/../flavors/${_flavor}/manifest.sh"
if [[ -f "$_flavor_manifest" ]]; then
    # shellcheck source=/dev/null
    source "$_flavor_manifest"
fi
unset _flavor _flavor_manifest

# Intro: a brief outcome and the next action. The detailed route belongs to
# the step that needs it, not to the first screen.
if ! phase_is_done "password_set"; then
    apply_wizard_font
    wizard_clear
    wizard_step_header 1 6 "Secure this box" "8 minutes"
    printf 'Hi%s. In a few short steps, this box will be ready\nto build from your phone or laptop.\n\n' \
        "${BIB_NAME:+ ${BIB_NAME}}"
    if [[ -r "${BIB_FLAVOR_COPY_DIR:-}/welcome.txt" ]]; then
        envsubst '${BIB_NAME}' < "${BIB_FLAVOR_COPY_DIR}/welcome.txt"
    else
        warn "wizard: welcome copy not found at ${BIB_FLAVOR_COPY_DIR:-<unset>}/welcome.txt"
    fi
    prompt_confirm "Press Enter to begin."
else
    wizard_clear
    IFS='|' read -r _bib_step _bib_title _bib_remaining < <(wizard_next_milestone)
    wizard_step_header "$_bib_step" 6 "$_bib_title" "$_bib_remaining"
    if wizard_is_ssh; then
        printf 'You are connected remotely. We will continue from this terminal.\n\n'
    else
        printf 'We will continue from the next unfinished step.\n\n'
    fi
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

# PHASE A (console): bare minimum to get the user onto SSH.
run_step "01-set-password.sh"
run_step "10-tailscale-up.sh"
run_step "35-ssh-finalize.sh"
run_step "36-phone-bridge.sh"      # pauses here on console (exit 78)

# PHASE B (SSH from phone or laptop): the heavy OAuth steps land here.
# Per FEAT-005:
#  - GitHub auth is NOT a wizard step. It happens inside the /tutorial
#    skill (Beat 2), where copy-paste + Claude's reaction loop are
#    available; that beat also imports the user's GitHub SSH keys.
#  - 40-scaffold builds the BASE workspace only. Project picker + FEAT
#    spec copy + GitHub repo creation live inside Claude (/tutorial
#    Beat 4 → /first-project).
run_step "05-choose-cli.sh"        # claude (default) or antigravity
run_step "38-ai-cli-login.sh"      # OAuth URL, copy-paste in SSH
run_step "40-scaffold.sh"          # base ai-platform/ skeleton, no project
run_step "50-tmux.sh"              # single 'ai-platform' session, /tutorial

# Note: there is no Slack wizard step. Setting up Slack (e.g. for the
# coach example, FEAT-002) happens later from the Claude Code app, as
# part of implementing that project — not on the first-boot console.

# Clear the first-boot pending marker so /etc/profile.d/biab-firstboot.sh
# doesn't relaunch the wizard on subsequent logins.
rm -f "${BIB_STATE_DIR}/firstboot.pending"

wizard_clear
wizard_step_header 6 6 "Start building" "a moment"
printf 'Your Builders in a Box is ready%s.\n\n' "${BIB_NAME:+, ${BIB_NAME}}"

# The finale is capability-specific: CLIs with remote-control attach through
# the Claude Code app; CLIs without it attach over SSH + tmux (no
# remote-control channel, no companion app).
_finale_ai_cli="$(state_get '.ai_cli')"
: "${_finale_ai_cli:=${BIB_SUPPORTED_AI_CLIS[0]}}"

if ! ai_cli_has_capability "$_finale_ai_cli" remote-control; then
    _finale_user="$(state_get '.bib_user')"
    : "${_finale_user:=$(bib_user_resolve 2>/dev/null || echo "$USER")}"
    _finale_host="$(hostname)"
    cat <<EOF
$(ai_cli_display_name "$_finale_ai_cli") is logged in and your workspace is ready.

From your phone or laptop, connect over Tailscale:

ssh ${_finale_user}@${_finale_host}

Then open your session:

tmux attach -t ai-platform

The /tutorial guide is already running. It will help you create your first project.
EOF
else
    cat <<EOF
Claude is logged in and the ai-platform session is waiting.

1. Install the Claude app on your phone or laptop.
2. Sign in with the same Claude account.
3. Open the session named: ai-platform

The /tutorial guide starts there and helps you create your first project.
EOF
fi
