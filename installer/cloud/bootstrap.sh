#!/usr/bin/env bash
# Builders in a Box — cloud first-boot preparation (FEAT-029).
#
# Runs once as root from cloud-init, on a VPS the reader owns. It prepares the
# stack and then STOPS. It never logs anything in: no Tailscale, no GitHub, no
# AI CLI, no agent invocation. Those are the owner's to do from an
# authenticated terminal, because doing them unattended would mean baking
# credentials into user-data or into a reusable image.
#
# Three properties this file exists to guarantee:
#
#   1. It installs an EXACT commit, verified after fetch. There is no fallback
#      to main. The published bootstrap (installer/web/install.sh) defaults
#      BIB_REF to main and force-syncs over an existing tree, which is fine
#      when a human is watching and wrong when the result is an unattended
#      public-IP box.
#   2. It installs under --profile=cloud, so BIAB never touches the provider's
#      sshd, authorized_keys or socket activation. See payload/install/50-ssh.sh.
#   3. It finishes in the state `awaiting-owner-setup`, never `ready`.
#
# It is restartable: each stage stamps itself, so re-running after an
# interruption preserves what already succeeded.
#
# Env (all optional, for tests):
#   BIB_CLOUD_STATE_DIR         where the stage stamps and status file live
#   BIB_CLOUD_DEST              checkout destination (default /opt/buildersinabox)
#   BIB_CLOUD_BOOTSTRAP_LIB=1   source the functions without running them

set -euo pipefail

CLOUD_STATE_DIR="${BIB_CLOUD_STATE_DIR:-/var/lib/buildersinabox}"
CLOUD_STATUS_FILE="${CLOUD_STATE_DIR}/cloud-bootstrap.status"
CLOUD_STAGE_DIR="${CLOUD_STATE_DIR}/cloud-stages"
DEST="${BIB_CLOUD_DEST:-/opt/buildersinabox}"

cloud_log() { echo "cloud-bootstrap: $*"; }

cloud_status() {
    mkdir -p "$CLOUD_STATE_DIR"
    printf '%s\n' "$1" > "${CLOUD_STATUS_FILE}.tmp"
    mv "${CLOUD_STATUS_FILE}.tmp" "$CLOUD_STATUS_FILE"
    chmod 0644 "$CLOUD_STATUS_FILE"
}

# Diagnostics must stay non-secret: this text ends up in the provider's serial
# console, readable by anyone with console access to the project.
cloud_die() {
    cloud_log "FAILED: $*" >&2
    cloud_status "failed"
    exit 1
}

# Stages record WHAT they completed, not merely that they did.
#
# An empty stamp would make a retry with a DIFFERENT commit skip the fetch and
# the install, then report awaiting-owner-setup — claiming the reviewed commit
# is on the box while the old tree is still there, with the verification in
# cloud_fetch_source never running at all. So the stamp carries the identity
# and a changed identity is a refusal, not a silent re-adoption (RF-6).
stage_done() {
    mkdir -p "$CLOUD_STAGE_DIR"
    printf '%s\n' "$2" > "${CLOUD_STAGE_DIR}/$1"
}

# 0 = already done with these exact inputs, skip it.
# 1 = not done, run it.
# dies  = done with different inputs, which is the operator's to reconcile.
stage_check() {
    local name="$1" identity="$2" file="${CLOUD_STAGE_DIR}/$1" was
    [[ -e "$file" ]] || return 1
    was="$(cat "$file" 2>/dev/null || true)"
    [[ "$was" == "$identity" ]] && return 0
    cloud_die "stage '${name}' already completed with different inputs. This instance was prepared with '${was}', but '${identity}' was requested. Re-running would leave the status claiming something the disk does not match. Keep the existing install, or start from a fresh instance."
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
# The same patterns render.sh applies offline, re-applied here. Validating in
# both places is deliberate: the renderer protects the operator from a typo,
# this protects the booting instance from a user-data file that was edited by
# hand after rendering.

cloud_valid_user()   { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [[ "$1" != "root" ]]; }
cloud_valid_commit() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
cloud_valid_repo()   { [[ "$1" =~ ^https://[A-Za-z0-9._~/-]+$ ]]; }
cloud_valid_cli()    { [[ "$1" =~ ^(claude|antigravity|codex|opencode)$ ]]; }

# ---------------------------------------------------------------------------
# Stages
# ---------------------------------------------------------------------------

# Refuses anything that is not the platform the payload is tested on. An
# unsupported base would otherwise surface much later as a confusing apt or
# systemd failure on a box nobody is watching.
cloud_check_platform() {
    local id="" ver="" arch
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release && echo "${ID:-}")"
        ver="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    fi
    [[ "$id" == "ubuntu" && "$ver" == "24.04" ]] \
        || cloud_die "expected Ubuntu 24.04, found '${id:-unknown} ${ver:-?}'"
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] \
        || cloud_die "expected x86-64, found '${arch}'"
}

# The workspace belongs to a human account, so the installer refuses to run as
# root. On the Ubuntu cloud images the provider has already created this user
# from the project's SSH keys; we verify rather than create, because creating
# one here would mean inventing a credential.
cloud_check_user() {
    local user="$1"
    cloud_valid_user "$user" || cloud_die "invalid target user"
    getent passwd "$user" >/dev/null \
        || cloud_die "target user does not exist on this instance. Create it in the provider console (or add its SSH key) and re-run."
}

# Fetches the repo and verifies the tree IS the requested commit. Deliberately
# not a branch clone followed by trust: a mutable ref can move between
# rendering the user-data and the instance booting.
cloud_fetch_source() {
    local repo="$1" commit="$2"
    cloud_valid_repo "$repo"     || cloud_die "invalid source repository URL"
    cloud_valid_commit "$commit" || cloud_die "source commit must be a full 40-character sha"

    if ! command -v git >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y git >/dev/null 2>&1 || cloud_die "could not install git"
    fi

    if [[ ! -d "${DEST}/.git" ]]; then
        [[ -e "$DEST" ]] && cloud_die "${DEST} exists but is not a git checkout"
        mkdir -p "$DEST"
        git -C "$DEST" init --quiet              || cloud_die "git init failed"
        git -C "$DEST" remote add origin "$repo" || cloud_die "could not set the source remote"
    else
        git -C "$DEST" remote set-url origin "$repo" || cloud_die "could not set the source remote"
    fi

    # Fetch the single commit. If the source is private or unreachable this
    # fails here, and that is the end of it — there is no second attempt
    # against a different ref.
    git -C "$DEST" fetch --quiet --depth 1 origin "$commit" \
        || cloud_die "could not fetch ${commit} from the source repository (unreachable, private, or no such commit)"
    git -C "$DEST" reset --quiet --hard FETCH_HEAD \
        || cloud_die "could not materialise the fetched commit"

    local actual
    actual="$(git -C "$DEST" rev-parse HEAD)"
    [[ "$actual" == "$commit" ]] \
        || cloud_die "source verification failed: expected ${commit}, tree is ${actual}"
    cloud_log "source verified at ${commit}"
}

# Runs the stack install only. --skip-wizard is what keeps this unattended
# stage away from every OAuth step, and --profile=cloud is what keeps it away
# from the provider's sshd.
cloud_install_stack() {
    local user="$1" name="$2" cli="$3"
    cloud_valid_cli "$cli" || cloud_die "invalid AI CLI"
    local installer="${DEST}/payload/install.sh"
    [[ -f "$installer" ]] || cloud_die "installer not found at ${installer} after fetch"
    chmod +x "$installer" 2>/dev/null || true

    BIB_USER="$user" BIB_NAME="$name" BIB_AI_CLI="$cli" BIB_FLAVOR=default \
        "$installer" --non-interactive --skip-wizard --profile=cloud \
        || cloud_die "stack install failed — see /var/log/biab-cloud-bootstrap.log, and /var/log/buildersinabox/bootstrap.log for the installer's own trace"
}

cloud_bootstrap_main() {
    local repo="${BIB_CLOUD_REPO:-}" commit="${BIB_CLOUD_COMMIT:-}"
    local user="${BIB_CLOUD_USER:-}" name="${BIB_CLOUD_NAME:-}"
    local cli="${BIB_CLOUD_AI_CLI:-claude}"

    [[ -n "$repo" && -n "$commit" && -n "$user" ]] \
        || cloud_die "missing required values in user-data (repo, commit, user)"

    cloud_status "preparing"

    local id_platform="ubuntu-24.04-x86_64"
    local id_source="${repo}@${commit}"
    local id_stack="${user}:${cli}"

    stage_check platform "$id_platform" || { cloud_check_platform; stage_done platform "$id_platform"; }
    stage_check user     "$user"        || { cloud_check_user "$user"; stage_done user "$user"; }
    stage_check source   "$id_source"   || { cloud_fetch_source "$repo" "$commit"; stage_done source "$id_source"; }
    stage_check stack    "$id_stack"    || { cloud_install_stack "$user" "$name" "$cli"; stage_done stack "$id_stack"; }

    # NOT "ready". The box has a stack and no identity: nobody is logged into
    # Tailscale, GitHub or the AI CLI, and nothing has been run on the owner's
    # behalf. Claiming ready here is the one lie this file must never tell.
    cloud_status "awaiting-owner-setup"
    cloud_log "stack prepared. Status: awaiting-owner-setup"
    cloud_log "Finish setup from an authenticated terminal on this instance: sudo biab"
}

if [[ "${BIB_CLOUD_BOOTSTRAP_LIB:-0}" != "1" ]]; then
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || cloud_die "must run as root"
    cloud_bootstrap_main
fi
