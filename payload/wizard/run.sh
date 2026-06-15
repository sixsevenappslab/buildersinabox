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

# Intro: full welcome on first run, short greeting on resumption.
# `clear` wipes the install-phase log noise above the banner so the
# welcome screen is a clean, "this was made for me" first impression.
if ! phase_is_done "password_set"; then
    apply_wizard_font
    clear
    wizard_banner
    prompt_header "Hi${BIB_NAME:+ ${BIB_NAME}} — let's set up your Builders in a Box"
    if [[ -r "${BIB_FLAVOR_COPY_DIR:-}/welcome.txt" ]]; then
        envsubst '${BIB_NAME}' < "${BIB_FLAVOR_COPY_DIR}/welcome.txt"
    else
        warn "wizard: welcome copy not found at ${BIB_FLAVOR_COPY_DIR:-<unset>}/welcome.txt"
    fi
    prompt_confirm "Press Enter to begin."
else
    # SSH resume — DON'T show wizard_banner. Phone terminals (Termius on
    # portrait phone) are narrow (~50 cols) and the 80-col banner wraps
    # into unreadable ASCII soup. A simple header is enough.
    clear
    prompt_header "Welcome back${BIB_NAME:+ ${BIB_NAME}} — resuming from SSH"
    _bib_ssh_tty="$(tty 2>/dev/null || echo unknown)"
    cat <<EOF
You're in an SSH session ($_bib_ssh_tty), on your phone or laptop.
The console on the mini PC is paused waiting — everything from here
happens in this terminal, where copy-paste actually works.

Let's finish where we left off: Claude login, workspace setup, tmux.
About 3 minutes total.
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
run_step "05-choose-cli.sh"        # claude (default) or gemini
run_step "38-ai-cli-login.sh"      # long Claude URL, copy-paste in SSH
run_step "40-scaffold.sh"          # base ai-platform/ skeleton, no project
run_step "50-tmux.sh"              # single 'ai-platform' session, /tutorial

# Note: there is no Slack wizard step. Setting up Slack (e.g. for the
# coach example, FEAT-002) happens later from the Claude Code app, as
# part of implementing that project — not on the first-boot console.

# Clear the first-boot pending marker so /etc/profile.d/biab-firstboot.sh
# doesn't relaunch the wizard on subsequent logins.
rm -f "${BIB_STATE_DIR}/firstboot.pending"

prompt_header "All set${BIB_NAME:+, ${BIB_NAME}}!"
cat <<EOF
Stack installed. Claude logged in. Workspace scaffolded. A tmux
session called 'ai-platform' is waiting with Remote Control active.

ONE MORE STEP — install the Claude Code app and attach.
EOF

# --- Single big CTA -------------------------------------------------------
printf '\n%s+============================================================+%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sInstall Claude Code, sign in, attach to "ai-platform".%s    %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+============================================================+%s\n\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF
  Where to get it:
    - Phone:   App Store / Google Play, search "Claude" by Anthropic
    - Laptop:  https://claude.ai/download  (Mac / Windows / Linux)

  Sign in with the SAME Claude account you used here. The app
  auto-discovers this device. You'll see one session in the sidebar:

      ai-platform

  Tap it. The /tutorial skill is already running — Claude greets you
  the moment you attach and walks you through GitHub, your first
  project, and the SDD skills. ~12 minutes, conversational, skippable.

  (If you don't see the ai-platform session immediately, swipe down
  to refresh the sidebar — sometimes takes a few seconds.)
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n     %sScan to open the download page:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t ANSI256 -l L -m 2 "https://claude.ai/download" 2>/dev/null | sed 's/^/       /'
fi
cat <<'EOF'

When you're inside Claude on your phone, unplug the monitor and
keyboard from this device. You're done with the console.

The full guide is at ~/README.md on this device if you need it later.
EOF
