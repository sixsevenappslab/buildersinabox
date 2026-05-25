#!/usr/bin/env bash
# Builders in a Box — first-boot bootstrap.
#
# Run on a fresh Ubuntu 24.04 install (mini PC or VM). Idempotent.
# Installs the base stack, then runs the setup wizard. In Wave 1 the wizard
# is not yet implemented; use --skip-wizard to test the install path.

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
AI_CLI_ARG=""

usage() {
    cat <<'EOF'
Usage: sudo bootstrap.sh [options]

Options:
  --ai-cli=<claude|gemini>   Pick the AI CLI to install (default: claude).
  --force                    Reset wizard-phase state so the wizard runs again.
                             Does not reinstall the stack.
  --skip-wizard              Install the stack and exit (no OAuth steps).
                             Useful for CI / image baking. Required during
                             Wave 1 since the wizard is not yet implemented.
  --i-know-what-im-doing     Continue even if the OS is not Ubuntu 24.04.
  -h, --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)              FORCE=1; shift ;;
        --skip-wizard)        SKIP_WIZARD=1; shift ;;
        --i-know-what-im-doing) OS_OVERRIDE=1; shift ;;
        --ai-cli=*)           AI_CLI_ARG="${1#--ai-cli=}"; shift ;;
        --ai-cli)             AI_CLI_ARG="${2:-}"; shift 2 ;;
        -h|--help)            usage; exit 0 ;;
        *)                    usage >&2; die "unknown argument: $1" ;;
    esac
done

# Export OS override so common.sh sees it.
[[ "$OS_OVERRIDE" -eq 1 ]] && export BIB_OS_OVERRIDE=1

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

require_root
require_supported_os
state_init

# Resolve the chosen CLI. CLI arg wins over state file value.
CHOSEN_CLI="$(ai_cli_resolve "$AI_CLI_ARG")"
ai_cli_persist "$CHOSEN_CLI"

log "bootstrap: ai_cli=${CHOSEN_CLI} force=${FORCE} skip_wizard=${SKIP_WIZARD}"

if [[ "$FORCE" -eq 1 ]]; then
    log "bootstrap: --force given, resetting wizard phases"
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
    log "bootstrap: running ${script}"
    "$full"
}

if phase_is_done "stack_installed"; then
    log "bootstrap: stack already installed, skipping (use --force to re-run wizard, or remove state.json to fully reinstall)"
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
# Wizard (Wave 2 — not yet implemented)
# ---------------------------------------------------------------------------

if [[ "$SKIP_WIZARD" -eq 1 ]]; then
    log "bootstrap: --skip-wizard, exiting after stack install"
    exit 0
fi

if [[ -x "${SCRIPT_DIR}/wizard/run.sh" ]]; then
    log "bootstrap: launching wizard"
    "${SCRIPT_DIR}/wizard/run.sh"
else
    log "bootstrap: wizard not yet implemented (Wave 2). Rerun with --skip-wizard for now."
    exit 0
fi
