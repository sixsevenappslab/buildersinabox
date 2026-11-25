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
#   browser is easy), scaffolds the workspace, starts the first agent, and prints
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
# shellcheck source=../lib/paseo.sh
source "${SCRIPT_DIR}/../lib/paseo.sh"

require_root
state_init

# The wizard's screens say what the user needs; the per-item detail of every
# step goes to the log file only (FEAT-046 H7). warn and die still print.
export BIB_LOG_QUIET=1

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

# R5 (FEAT-045): when the owner did not see the language screen, confirm the
# language once, in one line, before step 1. Never again on resume.
bib_lang_confirm

# Intro: a brief outcome and the next action. The detailed route belongs to
# the step that needs it, not to the first screen.
if ! phase_is_done "password_set"; then
    apply_wizard_font
    wizard_clear
    wizard_banner
    _intro_title="$(msg wizard.title.secure)"
    _intro_eta="$(msg wizard.eta.min8)"
    wizard_step_header 1 6 "$_intro_title" "$_intro_eta"
    msg wizard.intro.hi "${BIB_NAME:+ ${BIB_NAME}}"
    # The flavor's welcome copy, in the owner's language when it has one
    # (welcome.<lang>.txt), else the English file.
    _intro_welcome="${BIB_FLAVOR_COPY_DIR:-}/welcome.txt"
    _intro_lang="$(bib_lang_current)"
    if [[ "$_intro_lang" != "$BIB_LANG_DEFAULT" && -r "${BIB_FLAVOR_COPY_DIR:-}/welcome.${_intro_lang}.txt" ]]; then
        _intro_welcome="${BIB_FLAVOR_COPY_DIR}/welcome.${_intro_lang}.txt"
    fi
    if [[ -r "$_intro_welcome" ]]; then
        envsubst '${BIB_NAME}' < "$_intro_welcome"
    else
        warn "wizard: welcome copy not found at ${BIB_FLAVOR_COPY_DIR:-<unset>}/welcome.txt"  # i18n-ok: maintainer diagnostic
    fi
    _intro_cli="$(state_get '.ai_cli')"
    _intro_need="" _intro_step3=""
    msg_str _intro_need wizard.intro.need_default
    # Name one CLI's account only when the choice is already fixed (forced with
    # BIB_AI_CLI, or its login is done). Otherwise step 4 offers every CLI and
    # the owner may pick any of them (FEAT-048), so the intro names them all.
    if [[ -n "${BIB_AI_CLI:-}" ]] || phase_is_done "ai_cli_done"; then :; else _intro_cli=""; fi
    if [[ -n "$_intro_cli" && "$_intro_cli" != "null" ]] && ( ai_cli_validate "$_intro_cli" ) >/dev/null 2>&1; then
        _intro_need="  - $(ai_cli_account_hint "$_intro_cli")"
    fi
    if bib_profile_is_cloud; then
        msg_str _intro_step3 wizard.intro.step3_cloud
    else
        msg_str _intro_step3 wizard.intro.step3_default
    fi
    msg wizard.intro.need "$_intro_need" "$_intro_step3"
    unset _intro_cli _intro_need _intro_step3 _intro_title _intro_eta _intro_welcome _intro_lang
    prompt_confirm "$(msg wizard.confirm.begin)"
else
    wizard_clear
    IFS='|' read -r _bib_step _bib_title _bib_remaining < <(wizard_next_milestone)
    wizard_step_header "$_bib_step" 6 "$_bib_title" "$_bib_remaining"
    if wizard_is_ssh; then
        msg wizard.resume.ssh
    else
        msg wizard.resume.local
    fi
    prompt_confirm "$(msg wizard.confirm.continue)"
fi

# Each step is idempotent (skips if its phase is already done).
# Exit code 78 from a step is a clean "pause here" signal — used by
# 36-phone-bridge.sh on console to wait for the user to move to phone.
run_step() {
    local script="$1"
    local full="${SCRIPT_DIR}/${script}"
    [[ -x "$full" ]] || die "wizard step not executable: $script"  # i18n-ok: maintainer diagnostic
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
run_step "50-paseo.sh"             # first agent in Paseo + phone pairing

# Note: there is no Slack wizard step. Setting up Slack (e.g. for the
# coach example, FEAT-002) happens later from the Claude Code app, as
# part of implementing that project — not on the first-boot console.

# Clear the first-boot pending marker so /etc/profile.d/biab-firstboot.sh
# doesn't relaunch the wizard on subsequent logins.
rm -f "${BIB_STATE_DIR}/firstboot.pending"

wizard_clear
wizard_banner
_finale_title="$(msg wizard.title.start)"
_finale_eta="$(msg wizard.eta.moment)"
wizard_step_header 6 6 "$_finale_title" "$_finale_eta"
unset _finale_title _finale_eta
msg wizard.finale.ready "${BIB_NAME:+, ${BIB_NAME}}"

# The finale: how to find the first agent in the Paseo app, and the SSH way in.
# The CLI 50-paseo started the first agent with: the primary, or the first
# installed one that runs under Paseo when the primary is SSH-only (FEAT-048).
if [[ -n "${BIB_AI_CLI:-}" ]]; then
    _finale_ai_cli="$(ai_cli_resolve "")"
else
    _finale_ai_cli="$(paseo_app_cli)"
fi
: "${_finale_ai_cli:=${BIB_SUPPORTED_AI_CLIS[0]}}"
_finale_user="$(state_get '.bib_user')"
: "${_finale_user:=$(bib_user_resolve 2>/dev/null || echo "$USER")}"
_finale_paired=0
[[ -e "${PASEO_HEALTH_DIR}/paired" ]] && _finale_paired=1
# The way in over SSH: the tailnet address, not the machine's own name (a cloud
# box's hostname is the provider's FQDN, which no other device can resolve).
_finale_host="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
: "${_finale_host:=$(hostname)}"
paseo_finale "$_finale_ai_cli" "$_finale_user" "$_finale_host" "$_finale_paired"
# A Codex guard waits for the owner to approve it once; say so before they leave (never
# a claim that it is active). Silent for every other state and CLI.
_finale_home="$(getent passwd "$_finale_user" | cut -d: -f6 || true)"
# shellcheck source=../lib/guard.sh
if [[ -n "$_finale_home" ]]; then
    # shellcheck source=../lib/guard.sh
    source "${SCRIPT_DIR}/../lib/guard.sh"
    while IFS= read -r _fcli; do
        [[ -n "$_fcli" ]] || continue
        guard_pending_note "$_fcli" "$_finale_home" || true
    done < <(ai_cli_resolve_list "")
fi
