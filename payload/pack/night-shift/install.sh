#!/usr/bin/env bash
# Builders in a Box night-shift pack — installer (FEAT-025). OPT-IN: this only
# runs when the operator explicitly asks for it (`biab pack add night-shift`).
# Nothing in payload/install.sh or the skills manifest calls this script.
#
# Idempotent. Installs:
#   - /usr/local/bin/biab-night-shift (the runner)
#   - /etc/systemd/system/biab-night-shift.{service,timer} (SYSTEM units,
#     root-owned — see the header of systemd/biab-night-shift.service.in for
#     why they are not user units)
#   - the rendered settings that register the PreToolUse no-merge guard
#   - the state tree under /var/lib/buildersinabox/night-shift/
#
# It ENABLES the timer and does NOT start it, and it does NOT create the mode
# file. A freshly installed pack simulates: it will tell you which spec it
# would pick and spend nothing. Turning that into real work is a separate,
# deliberate act (`sudo biab-night-shift arm`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "${SCRIPT_DIR}/../../lib/common.sh"
# shellcheck source=../../lib/ai-cli.sh
source "${SCRIPT_DIR}/../../lib/ai-cli.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

for arg in "$@"; do
    case "$arg" in
        *) die "night-shift pack install: unknown argument: $arg" ;;  # i18n-ok: a wrong call by a maintainer, the installer takes no arguments
    esac
done

# ---------------------------------------------------------------------------
# Preflight FIRST, before anything is written. Half a pack installed in
# silence is worse than none: the units would exist with no binary behind
# them, or the binary with no guard settings to load.
#
# payload/install.sh treats envsubst as optional (`command -v` guard, :517)
# because there the autologin drop-in is a nice-to-have. Here it is not: no
# rendered units, no night shift.
# ---------------------------------------------------------------------------
if ! command -v envsubst >/dev/null 2>&1; then
    die "$(msg nightshift.install.no_envsubst)"
fi

operator_user="$(resolve_operator_user || true)"
if [[ -z "$operator_user" ]]; then
    die "$(msg nightshift.install.no_operator)"
fi

ai_cli="$(state_get '.ai_cli' 2>/dev/null || true)"
: "${ai_cli:=${BIB_SUPPORTED_AI_CLIS[0]}}"

# ---------------------------------------------------------------------------
# Runner on PATH.
# ---------------------------------------------------------------------------
install -o root -g root -m 0755 "${SCRIPT_DIR}/bin/biab-night-shift" "$NIGHT_BIN_TARGET"
log "night-shift pack: installed $NIGHT_BIN_TARGET"

# ---------------------------------------------------------------------------
# State tree. The split of ownership is the whole security model:
#   night-shift/        root:root 0755 — the operator may look, not create
#   night-shift/mode    root:root 0644 — created only by `arm`, never here
#   night-shift/state/  operator 0750  — stamps, summary, lock, guard log:
#                                        the runner writes these AS the operator
# ---------------------------------------------------------------------------
install -o root -g root -m 0755 -d "$NIGHT_ROOT_DIR"
install -o root -g root -m 0755 -d "$NIGHT_GUARD_DIR"
install -o "$operator_user" -g "$operator_user" -m 0750 -d "$NIGHT_STATE_DIR"
install -o "$operator_user" -g "$operator_user" -m 0750 -d "$NIGHT_ATTEMPT_DIR"
log "night-shift pack: state tree ready under $NIGHT_ROOT_DIR"

# ---------------------------------------------------------------------------
# Render the three templates. The envsubst variable allowlist is explicit
# ('${BIB_USER}') so a template can never expand anything else that happens to
# be in the environment, and each file is written to .tmp and moved into place
# so a half-written unit never exists (payload/install.sh:521's pattern).
# ---------------------------------------------------------------------------
render() {
    local src="$1" dest="$2"
    BIB_USER="$operator_user" envsubst '${BIB_USER}' < "$src" > "${dest}.tmp"
    install -o root -g root -m 0644 "${dest}.tmp" "$dest"
    rm -f "${dest}.tmp"
}

render "${SCRIPT_DIR}/systemd/biab-night-shift.service.in" "$NIGHT_SERVICE_UNIT"
render "${SCRIPT_DIR}/systemd/biab-night-shift.timer.in"   "$NIGHT_TIMER_UNIT"
render "${SCRIPT_DIR}/hooks/night-settings.json.in"        "$NIGHT_SETTINGS_FILE"

# The per-pass spend cap, written where the CLI adapter can find it. Root-owned
# like everything else in the guard directory: a budget the agent could raise
# is not a budget.
printf '%s\n' "$NIGHT_MAX_BUDGET_USD" > "${NIGHT_BUDGET_FILE}.tmp"
install -o root -g root -m 0644 "${NIGHT_BUDGET_FILE}.tmp" "$NIGHT_BUDGET_FILE"
rm -f "${NIGHT_BUDGET_FILE}.tmp"
# FEAT-039: the independent review's own ceiling and the default danger list,
# root-owned for the same reason.
printf '%s\n' "$NIGHT_REVIEW_BUDGET_USD" > "${NIGHT_REVIEW_BUDGET_FILE}.tmp"
install -o root -g root -m 0644 "${NIGHT_REVIEW_BUDGET_FILE}.tmp" "$NIGHT_REVIEW_BUDGET_FILE"
rm -f "${NIGHT_REVIEW_BUDGET_FILE}.tmp"
install -o root -g root -m 0644 "${SCRIPT_DIR}/hooks/danger-paths.default" "$NIGHT_DANGER_PATHS_FILE"
log "night-shift pack: rendered units and guard directory for user=${operator_user}"

chmod 0755 "${SCRIPT_DIR}/hooks/no-merge-guard.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Schedule it, but do NOT start it. `enable` without --now is the difference
# between "there is a night shift on this box" and "a night shift is running
# right now, and you did not ask for one".
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable biab-night-shift.timer
log "night-shift pack: timer enabled (first window is 03:00, plus up to 15 min of jitter)"

# ---------------------------------------------------------------------------
# The spending warning. Shown at install time, not at arm time: a user who
# installs something they can never switch on deserves to hear it now.
# ---------------------------------------------------------------------------
night_install_notice "$ai_cli"

log "night-shift pack: install complete (disarmed)"
