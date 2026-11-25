#!/usr/bin/env bash
# Sync missing core skills and re-seed hooks on `biab update` (FEAT-037 T1).
#
# Runs in the stack after 47-cli-guard.sh. No-op unless `scaffold_done` is set
# in state.json (on a fresh box the wizard's 40-scaffold.sh has not run yet).
# When `scaffold_done` is set, runs as the box user (`paseo_as_user` pattern)
# and only adds missing core skills and missing hook commands — never
# overwriting, refreshing or deleting an existing skill directory or hook.

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
# shellcheck source=../lib/user-content.sh
source "${SCRIPT_DIR}/../lib/user-content.sh"

[[ "${BIB_PASEO_TEST:-0}" == "1" ]] || require_root

if ! phase_is_done "scaffold_done"; then
    log "48-user-content: scaffold_done is not set — skipping (no-op before wizard scaffold)"
    exit 0
fi

box_user="$(state_get '.bib_user // .user' 2>/dev/null || true)"
: "${box_user:=${BIB_TARGET_USER:-${BIB_USER:-}}}"
if [[ -z "$box_user" ]]; then
    log "48-user-content: could not resolve box user from state.json — skipping"
    exit 0
fi

user_home="${BIB_USER_HOME:-$(getent passwd "$box_user" 2>/dev/null | cut -d: -f6 || true)}"
if [[ -z "$user_home" || ! -d "$user_home" ]]; then
    log "48-user-content: home directory for '${box_user}' not found — skipping"
    exit 0
fi

_raw_clis="$(ai_cli_list | paste -sd, -)"
: "${_raw_clis:=${BIB_AI_CLI:-${BIB_SUPPORTED_AI_CLIS[0]}}}"
mapfile -t _box_clis < <(ai_cli_parse_list "$_raw_clis")
clis_csv="$(IFS=,; printf '%s' "${_box_clis[*]}")"

if ! uc_refuse_symlink "$user_home" "${user_home}/.agents" "${user_home}/.agents/skills" "${user_home}/.claude"; then
    log "48-user-content: refused symlink in ${user_home} — leaving user content untouched"
    exit 0
fi

paseo_as_user "$box_user" env HOME="$user_home" PAYLOAD_DIR="$PAYLOAD_DIR" \
    BIB_STATE_DIR="${BIB_STATE_DIR:-}" BIB_STATE_FILE="${BIB_STATE_FILE:-}" \
    BIB_LOG_DIR="${BIB_LOG_DIR:-}" BIB_LOG_FILE="${BIB_LOG_FILE:-}" \
    bash -c '
        set -euo pipefail
        source "$1/lib/common.sh"
        source "$1/lib/ai-cli.sh"
        source "$1/lib/guard.sh"
        source "$1/lib/user-content.sh"
        IFS=, read -r -a _clis <<< "$3"
        for _c in "${_clis[@]}"; do
            uc_sync_core_skills "$2" "$_c" "$1/skills"
            uc_seed_hooks "$2" "$_c"
        done
    ' _ "$PAYLOAD_DIR" "$user_home" "$clis_csv"

log "48-user-content: synced missing core skills and hooks for ${box_user} (ai_clis=${clis_csv})"
