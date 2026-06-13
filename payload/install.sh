#!/usr/bin/env bash
# Builders in a Box — installer entry point.
#
# Run on a fresh Ubuntu 24.04 install (mini PC or VM). Idempotent.
# Installs the base stack, then runs the setup wizard.
#
# Modes:
#   default              Interactive install: prompts for required values
#                        when missing, runs the stack and the wizard.
#   --non-interactive    Reads BIB_USER / BIB_NAME / BIB_FLAVOR /
#                        BIB_AI_CLI from the environment. Fails fast if
#                        any required var is missing. Used by CI and the
#                        autoinstall flow.
#   --update             Re-runs idempotently on a box that already went
#                        through install once. Skips completed phases.
#   --uninstall          Removes everything BIAB-owned and exits. Leaves
#                        ${HOME}, Tailscale, gh, and Claude auth alone.
#   --selftest           Runs tools/check-no-personal-refs.sh against the
#                        install tree + verifies state.json schema.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/ai-cli.sh
source "${SCRIPT_DIR}/lib/ai-cli.sh"

# ---------------------------------------------------------------------------
# Defaults + arg parsing
# ---------------------------------------------------------------------------

FORCE=0
SKIP_WIZARD=0
OS_OVERRIDE=0
NON_INTERACTIVE=0
UPDATE_MODE=0
UNINSTALL_MODE=0
SELFTEST_MODE=0
AI_CLI_ARG=""
FLAVOR_ARG=""

usage() {
    cat <<'EOF'
Usage: sudo install.sh [options]

Options:
  --ai-cli=<claude|gemini>   Pick the AI CLI to install (default: claude).
  --flavor=<default|gift>    Pick the copy/banner flavor (default: default).
  --force                    Reset wizard-phase state so the wizard runs again.
                             Does not reinstall the stack.
  --skip-wizard              Install the stack and exit (no OAuth steps).
                             Useful for CI / image baking.
  --non-interactive          Read BIB_USER, BIB_NAME, BIB_FLAVOR, BIB_AI_CLI
                             from the environment. Fail fast if any required
                             var is missing. Used by CI and autoinstall.
  --update                   Re-run idempotently on a box that already went
                             through install once. Skips completed phases.
  --uninstall                Remove everything BIAB-owned and exit.
                             Leaves user home, Tailscale, gh, Claude auth.
  --selftest                 Run the personal-refs guard against the install
                             tree and verify state.json schema; exit.
  --i-know-what-im-doing     Continue even if the OS is not Ubuntu 24.04.
  -h, --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)              FORCE=1; shift ;;
        --skip-wizard)        SKIP_WIZARD=1; shift ;;
        --non-interactive)    NON_INTERACTIVE=1; shift ;;
        --update)             UPDATE_MODE=1; shift ;;
        --uninstall)          UNINSTALL_MODE=1; shift ;;
        --selftest)           SELFTEST_MODE=1; shift ;;
        --i-know-what-im-doing) OS_OVERRIDE=1; shift ;;
        --ai-cli=*)           AI_CLI_ARG="${1#--ai-cli=}"; shift ;;
        --ai-cli)             AI_CLI_ARG="${2:-}"; shift 2 ;;
        --flavor=*)           FLAVOR_ARG="${1#--flavor=}"; shift ;;
        --flavor)             FLAVOR_ARG="${2:-}"; shift 2 ;;
        -h|--help)            usage; exit 0 ;;
        *)                    usage >&2; die "unknown argument: $1" ;;
    esac
done

# Export OS override so common.sh sees it.
[[ "$OS_OVERRIDE" -eq 1 ]] && export BIB_OS_OVERRIDE=1

# Surface --flavor as BIB_FLAVOR so bib_flavor_resolve sees it.
if [[ -n "$FLAVOR_ARG" ]]; then
    export BIB_FLAVOR="$FLAVOR_ARG"
fi

# Surface --ai-cli as BIB_AI_CLI so non-interactive validation is symmetrical
# with the other vars.
if [[ -n "$AI_CLI_ARG" ]]; then
    export BIB_AI_CLI="$AI_CLI_ARG"
fi

# ---------------------------------------------------------------------------
# Non-interactive validation
# ---------------------------------------------------------------------------
# Required vars when --non-interactive is set. Empty values fail; the
# resolvers in lib/common.sh die with named-var errors so the caller knows
# exactly what is missing.

if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    : "${BIB_USER:?BIB_USER is required in --non-interactive mode}"
    : "${BIB_FLAVOR:?BIB_FLAVOR is required in --non-interactive mode (default|gift)}"
    : "${BIB_AI_CLI:?BIB_AI_CLI is required in --non-interactive mode (claude|gemini)}"
    # BIB_NAME may legitimately be empty (default flavor drops the line).
    # Treat unset as empty; do not require.
    export BIB_NAME="${BIB_NAME:-}"
fi

# ---------------------------------------------------------------------------
# Mode: uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    require_root
    local found_anything=0

    local target_user="${SUDO_USER:-${USER:-}}"
    if [[ -f "$BIB_STATE_FILE" ]]; then
        local stored_user
        stored_user="$(jq -r '.bib_user // empty' "$BIB_STATE_FILE" 2>/dev/null || true)"
        [[ -n "$stored_user" ]] && target_user="$stored_user"
    fi

    # BIB-owned dirs and files. Order: smallest blast radius first.
    local paths_to_remove=(
        /usr/local/bin/biab
        /usr/local/bin/bd
        /etc/profile.d/biab-firstboot.sh
        /etc/systemd/system/getty@tty1.service.d/autologin.conf
        "$BIB_LOG_DIR"
        "$BIB_STATE_DIR"
        /opt/buildersinabox
    )
    local p
    for p in "${paths_to_remove[@]}"; do
        if [[ -e "$p" ]]; then
            log "uninstall: removing $p"
            rm -rf -- "$p"
            found_anything=1
        fi
    done

    # User-level shell snippets installed under ~${target_user}/.bashrc.d/biab-*.
    if [[ -n "$target_user" ]] && getent passwd "$target_user" >/dev/null; then
        local home
        home="$(getent passwd "$target_user" | cut -d: -f6)"
        if [[ -d "${home}/.bashrc.d" ]]; then
            local snippet
            for snippet in "${home}/.bashrc.d"/biab-*; do
                [[ -e "$snippet" ]] || continue
                log "uninstall: removing $snippet"
                rm -f -- "$snippet"
                found_anything=1
            done
        fi
    fi

    if [[ "$found_anything" -eq 0 ]]; then
        log "uninstall: nothing to remove — no BIAB state found"
    else
        log "uninstall: complete. User home, Tailscale, gh, and Claude auth untouched."
    fi
    exit 0
}

if [[ "$UNINSTALL_MODE" -eq 1 ]]; then
    do_uninstall
fi

# ---------------------------------------------------------------------------
# Mode: selftest
# ---------------------------------------------------------------------------

do_selftest() {
    local guard="${SCRIPT_DIR%/payload}/tools/check-no-personal-refs.sh"
    # Locate the guard relative to the installed tree or the dev checkout.
    if [[ ! -x "$guard" ]]; then
        if [[ -x "/opt/buildersinabox/tools/check-no-personal-refs.sh" ]]; then
            guard="/opt/buildersinabox/tools/check-no-personal-refs.sh"
        else
            die "selftest: guard script not found at $guard or /opt/buildersinabox/tools/"
        fi
    fi
    log "selftest: running $guard"
    "$guard"
    # Verify state.json schema version (if state exists).
    if [[ -f "$BIB_STATE_FILE" ]]; then
        local ver
        ver="$(jq -r '.version' "$BIB_STATE_FILE")"
        if [[ "$ver" != "$BIB_STATE_SCHEMA_VERSION" ]]; then
            die "selftest: state.json schema is v${ver}, expected v${BIB_STATE_SCHEMA_VERSION}"
        fi
        log "selftest: state.json schema v${ver} OK"
    fi
    log "selftest: clean"
    exit 0
}

if [[ "$SELFTEST_MODE" -eq 1 ]]; then
    do_selftest
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

require_root
require_supported_os

# ---------------------------------------------------------------------------
# Interactive identity prompt
# ---------------------------------------------------------------------------
# On a first-time interactive install, ask the operator for their name so
# the wizard banner can greet them. BIB_USER auto-resolves from SUDO_USER
# silently (no need to ask — they're already logged in as themselves).
# BIB_NAME is the only one we surface to the operator because there's no
# system source for it.
#
# Skipped when: --non-interactive is set, state.json already exists
# (re-runs and --update), BIB_NAME is already provided via env.

if [[ "$NON_INTERACTIVE" -eq 0 && ! -f "$BIB_STATE_FILE" && -z "${BIB_NAME:-}" ]]; then
    printf '\nWhat name should the wizard greet you by? '
    printf '(leave blank to skip the personalised line) '
    printf '\n> '
    read -r BIB_NAME || BIB_NAME=""
    export BIB_NAME
fi

# The gift flavor's welcome copy refers to the operator by name without
# a fallback — selecting gift flavor without BIB_NAME would render an
# odd "..., ." line. Fail fast with a clear error.
if [[ "${BIB_FLAVOR:-default}" == "gift" && -z "${BIB_NAME:-}" ]]; then
    die "BIB_FLAVOR=gift requires BIB_NAME to be set (the personalised welcome refers to it). Either set BIB_NAME or use --flavor=default."
fi

state_init

# Source the flavor manifest (created by Wave 2 FEAT-006 T4). Until that
# directory exists, this is a no-op — install still works with the default
# wizard heredocs.
BIB_FLAVOR_RESOLVED="$(bib_flavor_resolve)"
export BIB_FLAVOR_RESOLVED
BIB_INSTALL_ROOT="${SCRIPT_DIR%/payload}"
export BIB_INSTALL_ROOT
_flavor_manifest="${SCRIPT_DIR}/flavors/${BIB_FLAVOR_RESOLVED}/manifest.sh"
if [[ -f "$_flavor_manifest" ]]; then
    # shellcheck source=/dev/null
    source "$_flavor_manifest"
fi
unset _flavor_manifest

# Render systemd autologin drop-in from its .in template, substituting
# ${BIB_USER}. Idempotent — re-renders even if the file already exists
# so --update keeps the autologin user in sync with state.json.
_autologin_in="${SCRIPT_DIR}/systemd/getty@tty1.service.d/autologin.conf.in"
_autologin_out="/etc/systemd/system/getty@tty1.service.d/autologin.conf"
if [[ -f "$_autologin_in" ]] && command -v envsubst >/dev/null 2>&1; then
    BIB_USER_RESOLVED="$(state_get '.bib_user')"
    : "${BIB_USER_RESOLVED:=$(bib_user_resolve)}"
    mkdir -p "$(dirname "$_autologin_out")"
    BIB_USER="$BIB_USER_RESOLVED" envsubst '${BIB_USER}' < "$_autologin_in" > "${_autologin_out}.tmp"
    mv "${_autologin_out}.tmp" "$_autologin_out"
    chmod 0644 "$_autologin_out"
    log "install: autologin rendered for user=${BIB_USER_RESOLVED}"
    unset BIB_USER_RESOLVED
fi
unset _autologin_in _autologin_out

# Resolve the chosen CLI. CLI arg wins over state file value.
CHOSEN_CLI="$(ai_cli_resolve "$AI_CLI_ARG")"
ai_cli_persist "$CHOSEN_CLI"

log "install: ai_cli=${CHOSEN_CLI} flavor=${BIB_FLAVOR_RESOLVED} force=${FORCE} skip_wizard=${SKIP_WIZARD} non_interactive=${NON_INTERACTIVE} update=${UPDATE_MODE}"

if [[ "$FORCE" -eq 1 ]]; then
    log "install: --force given, resetting wizard phases"
    for phase in tailscale_done gh_done ai_cli_done scaffold_done tmux_done; do
        phase_reset "$phase"
    done
fi

# ---------------------------------------------------------------------------
# Install stack
# ---------------------------------------------------------------------------

run_install() {
    local script="$1"
    local full="${SCRIPT_DIR}/${script}"
    [[ -x "$full" ]] || die "install script not executable or missing: $script"
    log "install: running ${script}"
    "$full"
}

if phase_is_done "stack_installed"; then
    log "install: stack already installed, skipping (use --force to re-run wizard, or remove state.json to fully reinstall)"
else
    run_install "install/00-base.sh"
    run_install "install/10-tmux.sh"
    run_install "install/20-tailscale.sh"
    run_install "install/30-gh.sh"
    run_install "$(ai_cli_install_script "$CHOSEN_CLI")"
    run_install "install/50-ssh.sh"
    phase_done "stack_installed"
fi

# ---------------------------------------------------------------------------
# Wizard
# ---------------------------------------------------------------------------

if [[ "$SKIP_WIZARD" -eq 1 ]]; then
    log "install: --skip-wizard, exiting after stack install"
    exit 0
fi

if [[ -x "${SCRIPT_DIR}/wizard/run.sh" ]]; then
    log "install: launching wizard"
    "${SCRIPT_DIR}/wizard/run.sh"
else
    log "install: wizard not found at ${SCRIPT_DIR}/wizard/run.sh"
    exit 0
fi
