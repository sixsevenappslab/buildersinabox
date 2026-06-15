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
BIB_STATE_SCHEMA_VERSION=2

# Allowed values for ${BIB_FLAVOR}. Keep in sync with payload/flavors/.
BIB_ALLOWED_FLAVORS=(default gift)

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

# Color helpers. We can't `source` lib/prompt.sh from here (circular dep risk
# during sourcing order), so we redefine the tty-detection inline. These are
# zeroed out automatically when stdout isn't a tty.
if [[ -t 1 ]] && [[ "${BIB_NO_COLOR:-0}" != "1" ]]; then
    _C_DIM=$'\e[2m'
    _C_GREEN=$'\e[32m'
    _C_YELLOW=$'\e[33m'
    _C_RED=$'\e[31m'
    _C_RESET=$'\e[0m'
else
    _C_DIM="" _C_GREEN="" _C_YELLOW="" _C_RED="" _C_RESET=""
fi

log() {
    local msg="$*"
    local ts_short ts_full
    ts_short="$(date +%H:%M:%S)"
    ts_full="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _bib_log_init
    # Short HH:MM:SS to the console (less noisy for a non-technical user),
    # full ISO-8601 UTC to the persistent log for debugging.
    printf '%s[%s]%s %s\n' "$_C_DIM" "$ts_short" "$_C_RESET" "$msg"
    printf '[%s] %s\n' "$ts_full" "$msg" >> "$BIB_LOG_FILE"
}

warn() {
    local msg="$*"
    local ts_short ts_full
    ts_short="$(date +%H:%M:%S)"
    ts_full="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _bib_log_init
    printf '%s[%s]%s %sWARN:%s %s\n' "$_C_DIM" "$ts_short" "$_C_RESET" "$_C_YELLOW" "$_C_RESET" "$msg" >&2
    printf '[%s] WARN: %s\n' "$ts_full" "$msg" >> "$BIB_LOG_FILE"
}

die() {
    local msg="$*"
    local ts_short ts_full
    ts_short="$(date +%H:%M:%S)"
    ts_full="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _bib_log_init
    printf '%s[%s]%s %sERROR:%s %s\n' "$_C_DIM" "$ts_short" "$_C_RESET" "$_C_RED" "$_C_RESET" "$msg" >&2
    printf '[%s] ERROR: %s\n' "$ts_full" "$msg" >> "$BIB_LOG_FILE"
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
# Operator identity (resolved at runtime, persisted into state file)
# ---------------------------------------------------------------------------

# Resolve the operating system user. Precedence:
#   1. BIB_USER env var (caller is explicit)
#   2. SUDO_USER (whoever ran sudo install.sh)
#   3. USER (running as a non-sudo user)
# Dies if the result is empty or "root" — install.sh refuses to operate as
# root since the workspace it scaffolds belongs to a human.
bib_user_resolve() {
    local u="${BIB_USER:-${SUDO_USER:-${USER:-}}}"
    if [[ -z "$u" || "$u" == "root" ]]; then
        die "BIB_USER could not be resolved. Set BIB_USER=<username> explicitly (the user account that will own ~/ai-platform)."
    fi
    if ! getent passwd "$u" >/dev/null; then
        die "BIB_USER=$u does not exist on this system. Create the account first or pick a different BIB_USER."
    fi
    printf '%s' "$u"
}

# Resolve the display name shown in greetings and banners. Optional;
# empty default is fine — banner copy must handle the empty case
# (e.g. "Hi${BIB_NAME:+ ${BIB_NAME}}").
bib_name_resolve() {
    printf '%s' "${BIB_NAME:-}"
}

# Resolve the flavor (which copy/banner set to source). Defaults to
# "default"; "gift" is the maintainer flavor with personalised welcome.
bib_flavor_resolve() {
    local f="${BIB_FLAVOR:-default}"
    local allowed
    for allowed in "${BIB_ALLOWED_FLAVORS[@]}"; do
        if [[ "$f" == "$allowed" ]]; then
            printf '%s' "$f"
            return 0
        fi
    done
    die "BIB_FLAVOR=$f is not a valid flavor. Allowed: ${BIB_ALLOWED_FLAVORS[*]}."
}

# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------
# Schema (v2):
# {
#   "version": 2,
#   "ai_cli": "claude" | "gemini" | null,
#   "bib_user": "<resolved operator account>",
#   "bib_name": "<display name, may be empty>",
#   "flavor": "default" | "gift",
#   "phases": {
#     "stack_installed": false,
#     "tailscale_done": false,
#     "ai_cli_done": false,
#     "scaffold_done": false,
#     "tmux_done": false
#   },
#   "first_boot_at": "2026-05-25T22:00:00Z"
# }
#
# Schema v1 lacked bib_user / bib_name / flavor. state_migrate_v1_to_v2
# upgrades existing v1 files in place, backing up to state.json.v1.bak.

# Migrate a v1 state file to v2 schema in place. No-op if already v2+.
# Non-destructive: original phases are preserved verbatim; only the new
# fields are added with sensible defaults. Backs up the original to
# state.json.v1.bak before writing.
state_migrate_v1_to_v2() {
    [[ -f "$BIB_STATE_FILE" ]] || return 0
    local current_version
    current_version="$(jq -r '.version // 1' "$BIB_STATE_FILE")"
    if [[ "$current_version" != "1" ]]; then
        return 0
    fi
    log "state: migrating schema v1 → v2"
    cp -p "$BIB_STATE_FILE" "${BIB_STATE_FILE}.v1.bak"
    local u n f
    u="$(bib_user_resolve)"
    n="$(bib_name_resolve)"
    f="$(bib_flavor_resolve)"
    local tmp
    tmp="$(mktemp --tmpdir="$BIB_STATE_DIR" state.XXXXXX.json)"
    jq --arg u "$u" --arg n "$n" --arg f "$f" '
        .version = 2 |
        .bib_user = $u |
        .bib_name = $n |
        .flavor = $f
    ' "$BIB_STATE_FILE" > "$tmp"
    mv "$tmp" "$BIB_STATE_FILE"
    chmod 0644 "$BIB_STATE_FILE"
    log "state: v2 migration done (backup at ${BIB_STATE_FILE}.v1.bak)"
}

state_init() {
    mkdir -p "$BIB_STATE_DIR"
    if [[ ! -f "$BIB_STATE_FILE" ]]; then
        local now u n f
        now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        u="$(bib_user_resolve)"
        n="$(bib_name_resolve)"
        f="$(bib_flavor_resolve)"
        local empty
        empty=$(jq -n \
            --argjson v "$BIB_STATE_SCHEMA_VERSION" \
            --arg now "$now" \
            --arg u "$u" \
            --arg n "$n" \
            --arg f "$f" '{
            version: $v,
            ai_cli: null,
            bib_user: $u,
            bib_name: $n,
            flavor: $f,
            phases: {
                stack_installed: false,
                tailscale_done: false,
                ai_cli_done: false,
                scaffold_done: false,
                tmux_done: false
            },
            first_boot_at: $now
        }')
        printf '%s\n' "$empty" > "${BIB_STATE_FILE}.tmp"
        mv "${BIB_STATE_FILE}.tmp" "$BIB_STATE_FILE"
        chmod 0644 "$BIB_STATE_FILE"
        log "state initialised at $BIB_STATE_FILE (schema v${BIB_STATE_SCHEMA_VERSION})"
    else
        # Existing file: migrate if it's still v1.
        state_migrate_v1_to_v2
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
