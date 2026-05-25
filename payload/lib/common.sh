#!/usr/bin/env bash
# Shared helpers for the Builders in a Box payload scripts.
# Source this file; do not execute it directly.

set -euo pipefail

# Paths
BIB_STATE_DIR="${BIB_STATE_DIR:-/var/lib/buildersinabox}"
BIB_STATE_FILE="${BIB_STATE_FILE:-${BIB_STATE_DIR}/state.json}"
BIB_LOG_DIR="${BIB_LOG_DIR:-/var/log/buildersinabox}"
BIB_LOG_FILE="${BIB_LOG_FILE:-${BIB_LOG_DIR}/bootstrap.log}"

# State schema version. Bump when the JSON shape changes incompatibly.
BIB_STATE_SCHEMA_VERSION=1

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_bib_log_init() {
    mkdir -p "$BIB_LOG_DIR"
    if [[ ! -e "$BIB_LOG_FILE" ]]; then
        touch "$BIB_LOG_FILE"
        # World-writable so unprivileged steps (e.g. tmux launch under the
        # target user) can append. For v1 this is acceptable; later we can
        # introduce a dedicated 'biab' group.
        chmod 0666 "$BIB_LOG_FILE" 2>/dev/null || true
    fi
}

log() {
    local msg="$*"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _bib_log_init
    printf '[%s] %s\n' "$ts" "$msg" | tee -a "$BIB_LOG_FILE"
}

warn() {
    local msg="$*"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _bib_log_init
    printf '[%s] WARN: %s\n' "$ts" "$msg" | tee -a "$BIB_LOG_FILE" >&2
}

die() {
    local msg="$*"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _bib_log_init
    printf '[%s] ERROR: %s\n' "$ts" "$msg" | tee -a "$BIB_LOG_FILE" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

is_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

require_root() {
    is_root || die "must run as root (use sudo)"
}

# Returns 0 if the running OS is Ubuntu 24.04. Otherwise returns 1.
is_ubuntu_2404() {
    [[ -r /etc/os-release ]] || return 1
    # shellcheck disable=SC1091
    local id version_id
    id="$(. /etc/os-release && echo "${ID:-}")"
    version_id="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    [[ "$id" == "ubuntu" && "$version_id" == "24.04" ]]
}

require_supported_os() {
    if ! is_ubuntu_2404; then
        if [[ "${BIB_OS_OVERRIDE:-0}" == "1" ]]; then
            warn "OS is not Ubuntu 24.04 but --i-know-what-im-doing was passed; continuing"
        else
            die "this payload only supports Ubuntu 24.04. Pass --i-know-what-im-doing to override."
        fi
    fi
}

# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------
# Schema (v1):
# {
#   "version": 1,
#   "ai_cli": "claude" | "gemini" | null,
#   "phases": {
#     "stack_installed": false,
#     "tailscale_done": false,
#     "gh_done": false,
#     "ai_cli_done": false,
#     "scaffold_done": false,
#     "tmux_done": false
#   },
#   "first_boot_at": "2026-05-25T22:00:00Z"
# }

state_init() {
    mkdir -p "$BIB_STATE_DIR"
    if [[ ! -f "$BIB_STATE_FILE" ]]; then
        local now
        now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        local empty
        empty=$(jq -n --argjson v "$BIB_STATE_SCHEMA_VERSION" --arg now "$now" '{
            version: $v,
            ai_cli: null,
            phases: {
                stack_installed: false,
                tailscale_done: false,
                gh_done: false,
                ai_cli_done: false,
                scaffold_done: false,
                tmux_done: false
            },
            first_boot_at: $now
        }')
        printf '%s\n' "$empty" > "${BIB_STATE_FILE}.tmp"
        mv "${BIB_STATE_FILE}.tmp" "$BIB_STATE_FILE"
        chmod 0644 "$BIB_STATE_FILE"
        log "state initialised at $BIB_STATE_FILE"
    fi
    # Validate it parses
    if ! jq -e . "$BIB_STATE_FILE" >/dev/null 2>&1; then
        die "state file is corrupted: $BIB_STATE_FILE. Remove it and rerun."
    fi
}

# state_get <jq-path>     e.g. state_get '.ai_cli'  or  '.phases.stack_installed'
state_get() {
    jq -r "$1 // empty" "$BIB_STATE_FILE"
}

# state_set <jq-path> <value>    value is treated as a JSON value when possible,
#                                falling back to a string.
state_set() {
    local path="$1"
    local value="$2"
    local tmp
    tmp="$(mktemp --tmpdir="$BIB_STATE_DIR" state.XXXXXX.json)"
    # Try to parse value as JSON (bool / number / object). Fall back to string.
    if jq -n --argjson v "$value" 'empty' >/dev/null 2>&1; then
        jq --argjson v "$value" "$path = \$v" "$BIB_STATE_FILE" > "$tmp"
    else
        jq --arg v "$value" "$path = \$v" "$BIB_STATE_FILE" > "$tmp"
    fi
    mv "$tmp" "$BIB_STATE_FILE"
    chmod 0644 "$BIB_STATE_FILE"
}

# Mark a phase as completed.
phase_done() {
    state_set ".phases.$1" "true"
    log "phase done: $1"
}

# Returns 0 if the phase is already done.
phase_is_done() {
    [[ "$(state_get ".phases.$1")" == "true" ]]
}

# Reset a phase to false.
phase_reset() {
    state_set ".phases.$1" "false"
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

# Run a command and log its outcome. Idempotent helper for apt operations.
apt_install() {
    local pkgs=("$@")
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
}

apt_update_once() {
    if [[ "${BIB_APT_UPDATED:-0}" != "1" ]]; then
        log "apt update"
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        BIB_APT_UPDATED=1
        export BIB_APT_UPDATED
    fi
}
