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

# FEAT-029: install profile. Decides who owns the box's SSH policy.
#   dedicated  the box is ours end to end (mini PC, gift USB, a VM you own the
#              console of). 50-ssh.sh writes a drop-in and 35-ssh-finalize.sh
#              binds sshd to the tailnet. This is the historical behaviour and
#              stays the default.
#   cloud      the box is a provider-managed VPS reached over its public IP.
#              BIAB touches NO part of SSH: no drop-in, no socket/service
#              toggle, no password auth, no bind, no authorized_keys. Closing
#              inbound TCP/22 is the owner's action in the provider console.
BIB_ALLOWED_PROFILES=(dedicated cloud)
BIB_DEFAULT_PROFILE=dedicated

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_bib_log_init() {
    mkdir -p "$BIB_LOG_DIR"
    if [[ ! -e "$BIB_LOG_FILE" ]]; then
        touch "$BIB_LOG_FILE"
        # World-writable so unprivileged steps (e.g. a wizard step running
        # as the target user) can append. For v1 this is acceptable; later we
        # can introduce a dedicated 'biab' group.
        # TODO(2026-08-13): 0666 also lets any local user forge or truncate
        # this log. Audited today: no secret reaches it — the OAuth login URL
        # goes to a 0600 mktemp and the password goes to chpasswd on stdin —
        # but that is a property to re-check before adding any log() call
        # carrying a token or URL. Proper fix is the 'biab' group above.
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
# Install profile (FEAT-029)
# ---------------------------------------------------------------------------

# Dies unless $1 is one of BIB_ALLOWED_PROFILES. An unknown profile must never
# degrade to the default: on this code path "unrecognised" would silently mean
# "dedicated", i.e. write an sshd drop-in on a public IP.
bib_profile_validate() {
    local want="$1" p
    for p in "${BIB_ALLOWED_PROFILES[@]}"; do
        [[ "$want" == "$p" ]] && return 0
    done
    die "unknown install profile: '${want}' (allowed: ${BIB_ALLOWED_PROFILES[*]})"
}

# Dies unless the persisted profile can be trusted. MUST be called in the
# caller's own shell, never inside $( ), because that is the whole point: a
# `die` inside a command substitution only kills the subshell, and the caller
# carries on with an empty string.
#
# This exists because the failure mode is asymmetric. "Unreadable state"
# resolving to the default means a corrupt state.json on a public-IP box takes
# the dedicated path through 50-ssh.sh on the next `biab update` — which writes
# PasswordAuthentication yes and toggles socket activation. Refusing to run is
# always the cheaper mistake.
bib_profile_require_readable() {
    [[ -f "$BIB_STATE_FILE" ]] || return 0
    local raw
    raw="$(jq -r '.install_profile // empty' "$BIB_STATE_FILE" 2>/dev/null)" \
        || die "cannot read the install profile from ${BIB_STATE_FILE} (corrupt or unreadable). Refusing to guess it: on a cloud box the wrong guess enables password authentication on a public IP. Fix or remove the state file and re-run."
    # No key at all is a state file written before this feature existed. That
    # box was installed under the dedicated policy by definition, so it is a
    # known value rather than an unreadable one.
    [[ -n "$raw" ]] || return 0
    bib_profile_validate "$raw"
}

# The profile actually in force, for any script in any process.
#
# Persisted state is consulted FIRST and deliberately: `biab update` re-runs
# install.sh --skip-wizard with no arguments and no environment, so state.json
# is the only carrier that survives it. Once a state file exists, the
# environment is ignored entirely — a legacy file without the key means
# dedicated, not "ask the environment".
bib_profile_effective() {
    local persisted=""
    if [[ -f "$BIB_STATE_FILE" ]]; then
        persisted="$(jq -r '.install_profile // empty' "$BIB_STATE_FILE" 2>/dev/null || true)"
        printf '%s\n' "${persisted:-$BIB_DEFAULT_PROFILE}"
        return 0
    fi
    printf '%s\n' "${BIB_INSTALL_PROFILE:-$BIB_DEFAULT_PROFILE}"
}

# Returns 0 on a provider-managed cloud box. The single predicate every
# SSH-touching step asks before it mutates anything. It validates first, in
# this shell, so an unreadable or bogus profile aborts instead of quietly
# answering "not cloud".
bib_profile_is_cloud() {
    bib_profile_require_readable
    [[ "$(bib_profile_effective)" == "cloud" ]]
}

# Resolves the profile once per install and writes it to state.json.
# Requires state_init to have run.
#
# A persisted profile is never silently replaced: switching an existing box
# between dedicated and cloud changes who owns sshd, which is exactly the kind
# of change that must be a decision rather than a side effect of a re-run with
# a different flag (RF-6).
bib_profile_persist() {
    local requested="${BIB_INSTALL_PROFILE:-}"
    local persisted=""
    [[ -n "$requested" ]] && bib_profile_validate "$requested"
    bib_profile_require_readable
    if [[ -f "$BIB_STATE_FILE" ]]; then
        persisted="$(jq -r '.install_profile // empty' "$BIB_STATE_FILE" 2>/dev/null || true)"
        # A state file from before this feature has no install_profile, but the
        # box it describes was installed under the dedicated policy and very
        # likely still has BIAB's drop-in on disk. Treating it as dedicated is
        # what forces a flip to cloud through the mismatch check below, instead
        # of adopting the box and orphaning a drop-in nobody manages any more.
        [[ -n "$persisted" ]] || persisted="$BIB_DEFAULT_PROFILE"
    fi
    if [[ -n "$persisted" && -n "$requested" && "$persisted" != "$requested" ]]; then
        die "install profile mismatch: this box was installed as '${persisted}' but '${requested}' was requested. Switching profiles changes who owns sshd, so reconcile it deliberately: keep '${persisted}', or uninstall and reinstall with --profile=${requested}."
    fi
    local effective="${persisted:-${requested:-$BIB_DEFAULT_PROFILE}}"
    bib_profile_validate "$effective"
    state_set '.install_profile' "$effective"
    export BIB_INSTALL_PROFILE="$effective"
    log "profile: install profile is '${effective}'"
}

# FEAT-027 R2: warn before installing over an SSH session with no private
# network yet. The wizard later restricts sshd to the tailnet-only address
# (35-ssh-finalize.sh) — if this SSH session isn't reachable over that
# network, it gets cut off. Hits two cases: a console-less VM (multipass,
# whose `shell` is itself SSH) and a curious sysadmin installing over plain
# LAN SSH. Fails closed: no tty and no ack means abort, not proceed.
_biab_ssh_session_active() {
    # Env vars survive when sudo doesn't strip them (sudo -E, or a shell
    # that already exported them into root's environment) — but the
    # documented `curl | sudo bash` one-liner hits plain sudo's env_reset,
    # which wipes SSH_CONNECTION/SSH_TTY before this script even starts.
    # `ss` is the fallback for that path: same reason 35-ssh-finalize.sh
    # detects SSH peers via `ss` instead of trusting env vars.
    [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] && return 0
    command -v ss >/dev/null 2>&1 || return 1
    [[ -n "$(ss -Htn state established '( sport = :22 )' 2>/dev/null)" ]]
}

check_ssh_install_preflight() {
    _biab_ssh_session_active || return 0

    # Already on the private network (or Tailscale reachable) — this
    # session will very likely survive the later sshd restriction.
    if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
        return 0
    fi

    if [[ "${BIB_SSH_INSTALL_ACK:-0}" == "1" ]]; then
        warn "installing over SSH with no private network up yet (BIB_SSH_INSTALL_ACK=1 set, continuing)"
        return 0
    fi

    printf '\n⚠ You are installing over an SSH connection and the private network\n'
    printf '  (Tailscale) is not up yet. Later in setup, SSH gets restricted to that\n'
    printf '  private network only — if this session is not reachable over it, you\n'
    printf '  will be locked out.\n\n'
    printf '  Expected and safe on a VPS: the wizard hardens to key-only first and\n'
    printf '  never locks you out mid-session. NOT safe inside a console-less VM\n'
    printf '  (e.g. multipass, whose shell is itself SSH) — that is not supported.\n'
    printf '  Use a hypervisor with a real console instead (VirtualBox, UTM,\n'
    printf '  virt-manager/Proxmox).\n\n'

    if [[ "${NON_INTERACTIVE:-0}" == "1" || ! -r /dev/tty ]]; then
        die "no tty to confirm from (or --non-interactive). Set BIB_SSH_INSTALL_ACK=1 if you understand the risk, or install from a console."
    fi

    printf 'Continue anyway? [y/N] '
    local _ack=""
    read -r _ack < /dev/tty || _ack=""
    [[ "$_ack" =~ ^[Yy]$ ]] || die "aborted. Install from a console, or set BIB_SSH_INSTALL_ACK=1 if you understand the risk."
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
#   "ai_cli": "claude" | "antigravity" | null,
#   "bib_user": "<resolved operator account>",
#   "bib_name": "<display name, may be empty>",
#   "flavor": "default" | "gift",
#   "phases": {
#     "stack_installed": false,
#     "tailscale_done": false,
#     "ai_cli_done": false,
#     "scaffold_done": false,
#     "paseo_done": false
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
            --arg f "$f" \
            --arg p "$(bib_profile_effective)" '{
            version: $v,
            ai_cli: null,
            bib_user: $u,
            bib_name: $n,
            flavor: $f,
            install_profile: $p,
            phases: {
                stack_installed: false,
                tailscale_done: false,
                ai_cli_done: false,
                scaffold_done: false,
                paseo_done: false
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

# state_del <jq-path>    delete a key (a no-op when it is absent), atomically.
state_del() {
    local tmp
    tmp="$(mktemp --tmpdir="$BIB_STATE_DIR" state.XXXXXX.json)"
    if jq "del($1)" "$BIB_STATE_FILE" > "$tmp"; then
        mv "$tmp" "$BIB_STATE_FILE"
        chmod 0644 "$BIB_STATE_FILE"
    else
        rm -f "$tmp"
        return 1
    fi
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

# ---------------------------------------------------------------------------
# Ownership predicates (FEAT-024)
# ---------------------------------------------------------------------------
# One definition each, because the install side and the uninstall side asking
# the same question in two places is how #44 happened: the installer refused to
# overwrite a file that the uninstaller then deleted. If these ever need to
# change, they change here and both sides move together.
#
# The SC2034 disables below are because these constants are read by the scripts
# that source this file, never here — a one-file-at-a-time linter cannot see it.

# The marker every file we write carries.
BIB_OWNERSHIP_MARKER='Installed by Builders in a Box'

# `bd` has two ways to be ours. The second matters: every bd installed before
# the marker existed carries no marker, and matching on the marker alone would
# classify those boxes' own bd as a stranger's — freezing updates forever and
# leaving it behind on uninstall. See install/06-bd-cli.sh.
# shellcheck disable=SC2034
BIB_BD_OWNERSHIP_PATTERN="${BIB_OWNERSHIP_MARKER}|brain-dump capture CLI"

# The tty1 autologin drop-in. Deliberately specific: a file that merely
# mentions the product is not ours. Note the em dash (U+2014) — it must match
# payload/systemd/getty@tty1.service.d/autologin.conf.in byte for byte.
# shellcheck disable=SC2034
BIB_AUTOLOGIN_OWNERSHIP_PATTERN='Builders in a Box — autologin'

# True when <file> exists and matches <extended-regex>. Silent; never fails the
# caller under `set -e` (a non-match is an answer, not an error).
bib_path_is_ours() {
    local f="$1" pat="$2"
    [[ -e "$f" ]] || return 1
    grep -Eq "$pat" "$f" 2>/dev/null
}

# True when <file> is a regular file (never a symlink) holding a line that is
# EXACTLY <marker>. Fixed-string, whole-line: a file that merely mentions the
# marker (or a symlink to one that does) is not ours. Used for ownership
# markers that sit in user-writable places, where a planted file must never
# be mistaken for ours and then deleted by a root uninstall (FEAT-035).
bib_marker_file_is_ours() {
    local f="$1" marker="$2"
    [[ -f "$f" && ! -L "$f" ]] || return 1
    grep -Fxq -- "$marker" "$f" 2>/dev/null
}

# authorized_keys has a usable key when it holds at least one non-blank,
# non-comment line. Consumed by the wizard's SSH finalize step and by the
# uninstall lockout guard — they must agree on what "has a key" means.
bib_authorized_keys_present() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    grep -Eq '^[[:space:]]*[^[:space:]#]' "$f"
}
