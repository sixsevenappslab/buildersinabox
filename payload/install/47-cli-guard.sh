#!/usr/bin/env bash
# Register BIAB's shell-command guard for the box's AI CLI (FEAT-042 wave 2).
#
# Runs in the stack, after 46-paseo.sh, so `biab update` re-runs it too: that is the
# way a box installed before this step gets a Codex guard (the scaffold, which seeds
# Claude's hooks, does not re-run on update, and Claude's install here is a no-op). What it does:
#   - nothing for a CLI whose adapter declares no `guard` (a promise is only made by
#     the registry, never by this script). One exception, for the hardware pass:
#     BIB_GUARD_PROVE=1 installs the not-yet-declared Antigravity guard, as UNVERIFIED;
#   - nothing while the kill switch is set (BIAB_HOOKS_DISABLED=1, ~/.claude/hooks-disabled
#     or ~/.biab/hooks-disabled in the BOX USER's home): the owner turned it off, an
#     update must not put it back;
#   - otherwise `biab-guard install`, as the box user, which ADDS our entry to the CLI's
#     own config without touching anything the user has. A config it cannot merge into
#     (a symlink, invalid JSON) is left alone and reported; that never fails the stack.
# It never writes under /etc, never approves a hook for the user and never uses sudo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/paseo.sh
source "${SCRIPT_DIR}/../lib/paseo.sh"
# shellcheck source=../lib/guard.sh
source "${SCRIPT_DIR}/../lib/guard.sh"

# Same test seam as 46-paseo.sh: a hermetic non-root test drives the real code.
[[ "${BIB_PASEO_TEST:-0}" == "1" ]] || require_root

cli="$(state_get '.ai_cli' 2>/dev/null || true)"
: "${cli:=${BIB_AI_CLI:-}}"
[[ -n "$cli" ]] || die "47-cli-guard: could not resolve the AI CLI (state .ai_cli / BIB_AI_CLI); refusing to guess."
ai_cli_validate "$cli"

if ! ai_cli_guard_installable "$cli"; then
    log "47-cli-guard: ${cli} declares no guard; nothing to install"
    exit 0
fi
# A guard whose code exists but is not declared yet (Antigravity, FEAT-042 D4) installs only
# on request, for the hardware pass: `biab status` keeps saying `guard none`.
proving=0
ai_cli_has_capability "$cli" guard || proving=1

box_user="$(state_get '.bib_user' 2>/dev/null || true)"
: "${box_user:=${BIB_USER:-}}"
if [[ -z "$box_user" ]] || ! getent passwd "$box_user" >/dev/null 2>&1; then
    die "47-cli-guard: could not resolve the box user (state .bib_user / BIB_USER)"
fi
user_home="$(getent passwd "$box_user" | cut -d: -f6)"

if biab_hooks_disabled_in "$user_home"; then
    log "47-cli-guard: the hooks are switched off by you (kill switch set); installing nothing"
    exit 0
fi

# The box user owns ~/.biab and the agents run as them, so a link here may be planted.
paseo_refuse_symlink "${user_home}/.biab" \
    || die "47-cli-guard: ${user_home}/.biab is a symbolic link; nothing was installed. See the message above."

_note="$(ai_cli_guard_note "$cli" "$user_home" 2>/dev/null || true)"
[[ -z "$_note" ]] || log "47-cli-guard: ${_note}"
[[ "$proving" -eq 0 ]] || log "47-cli-guard: BIB_GUARD_PROVE=1: installing the UNVERIFIED ${cli} guard. It is not counted as a guard until the hardware pass has seen it block (FEAT-042 T6)."

rc_inst=0
paseo_as_user "$box_user" env HOME="$user_home" bash "${PAYLOAD_DIR}/scripts/biab-guard" install "$cli" "$user_home" || rc_inst=$?
if [[ "$rc_inst" -eq 0 ]]; then
    if [[ "$proving" -eq 1 ]]; then
        log "47-cli-guard: ${cli} guard installed, UNVERIFIED (see 'biab status')"
    else
        log "47-cli-guard: guard registered for ${cli} (state: $(paseo_as_user "$box_user" env HOME="$user_home" bash "${PAYLOAD_DIR}/scripts/biab-guard" state "$cli" "$user_home" 2>/dev/null || echo unknown))"
    fi
elif [[ "$rc_inst" -eq 3 ]]; then
    # Deferred, not a failure: the config the guard goes into does not exist yet (a first install:
    # the scaffold seeds it after this step and adds the guard then).
    log "47-cli-guard: the ${cli} guard is deferred: its config does not exist yet. It is added once BIAB seeds it, or by the next 'biab update'."
else
    warn "47-cli-guard: the ${cli} guard was NOT installed: its config was left untouched (see above). 'biab status' shows the guard state."
fi
