#!/usr/bin/env bash
# Install the pinned Paseo daemon as a root-owned system unit (FEAT-035 T1).
#
# What this does, in order, and why that order:
#   1. Preflight everything that can be checked before touching the disk.
#   2. Install the pinned tree with `npm ci` from the lockfile shipped in the
#      repo, into a staging directory, verify it, and only then move it into
#      place. Never `npm install -g`, never "latest": the lockfile's integrity
#      hashes are what pin the transitive tree.
#   3. Create the per-box credential, the BIAB-owned PASEO_HOME and the unit.
# If step 2 fails nothing is written beyond a removed staging directory: no
# unit, no credential, and SSH access is untouched (R14). A box is never left
# without an interface.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/paseo.sh
source "${SCRIPT_DIR}/../lib/paseo.sh"
# shellcheck source=../lib/pins.sh
source "${SCRIPT_DIR}/../lib/pins.sh"

# Test seam: BIB_PASEO_TEST=1 lets a non-root hermetic test drive the gate below
# (root is what makes every later step safe, so only the gate is reachable).
[[ "${BIB_PASEO_TEST:-0}" == "1" ]] || require_root

SRC_DIR="${SCRIPT_DIR}/../paseo"
changed=0   # set when the daemon must be restarted to pick up a new tree or unit

# --- 0. Gate: only a CLI that Paseo can run with its permission prompts on gets
# the daemon (the single decision point is paseo_supports_cli: claude, codex and
# antigravity through BIAB's ACP provider). Installing the daemon, its
# credential and a tailnet listener on a box that never uses them is attack
# surface for nothing, so a CLI without Paseo gets none of it. What it does get
# is the biab-workspace helper (the skills call it by absolute path). It
# listens on nothing.
cli="$(state_get '.ai_cli' 2>/dev/null || true)"
: "${cli:=${BIB_AI_CLI:-}}"
# No default: guessing "claude" would install a daemon for a box whose CLI we do
# not know.
[[ -n "$cli" ]] || die "46-paseo: could not resolve the AI CLI (state .ai_cli / BIB_AI_CLI); refusing to guess. Nothing was installed."
if ! paseo_supports_cli "$cli"; then
    # A box that had the daemon (installed under another CLI) and now uses a CLI
    # without Paseo must not keep the old unit, credential and listener.
    _td_user="$(state_get '.bib_user' 2>/dev/null || true)"
    : "${_td_user:=${BIB_USER:-}}"
    _td_home=""
    if [[ -n "$_td_user" ]] && getent passwd "$_td_user" >/dev/null 2>&1; then
        _td_home="$(getent passwd "$_td_user" | cut -d: -f6)"
    fi
    paseo_teardown_install "$_td_user" "$_td_home"
    install -m 0755 -d "$PASEO_OPT_DIR" "${PASEO_OPT_DIR}/bin"
    install -m 0755 "${SRC_DIR}/bin/biab-workspace" "${PASEO_OPT_DIR}/bin/biab-workspace"
    _why="$(paseo_not_permissioned_reason "$cli" 2>/dev/null || true)"
    log "46-paseo: ${cli} does not run under Paseo${_why:+ (${_why})}; skipping the Paseo daemon (SSH only on this box)"
    exit 0
fi

# --- 0b. Antigravity runs through `agy acp` (FEAT-041). Check that the pinned agy
# has it BEFORE anything is written, so a failure leaves no unit, credential or
# provider config behind and the box keeps its SSH way in (R9).
if [[ "$cli" == "antigravity" ]]; then
    _acp_user="$(state_get '.bib_user' 2>/dev/null || true)"
    : "${_acp_user:=${BIB_USER:-}}"
    if [[ -z "$_acp_user" ]] || ! getent passwd "$_acp_user" >/dev/null 2>&1; then
        die "46-paseo: could not resolve the box user (state .bib_user / BIB_USER)"
    fi
    _acp_why="$(paseo_acp_preflight "$_acp_user" 2>&1 >/dev/null)" \
        || die "46-paseo: Antigravity cannot run under Paseo: ${_acp_why}. Nothing was installed. SSH and the agy command keep working; run 'biab update' again to retry."
    log "46-paseo: agy acp preflight passed"
fi

# --- 1. Preflight ----------------------------------------------------------
for tool in node npm openssl envsubst jq install; do
    command -v "$tool" >/dev/null 2>&1 \
        || die "46-paseo: '$tool' is required (install/00-base.sh should have provided it; envsubst comes from the gettext-base package)"
done
[[ -f "${SRC_DIR}/package-lock.json" ]] \
    || die "46-paseo: ${SRC_DIR}/package-lock.json is missing; refusing to install without the committed lockfile"

operator_user="$(state_get '.bib_user' 2>/dev/null || true)"
: "${operator_user:=${BIB_USER:-}}"
if [[ -z "$operator_user" ]] || ! getent passwd "$operator_user" >/dev/null 2>&1; then
    die "46-paseo: could not resolve the box user (state .bib_user / BIB_USER)"
fi
user_home="$(getent passwd "$operator_user" | cut -d: -f6)"
paseo_home="$(paseo_home_for "$user_home")"

# The box user owns these paths and the agents run as that user, so a symlink
# here may be a planted one (marker -> /etc/sudoers). Refuse before doing
# anything as root; paseo_prepare_user_state checks again and writes as the user.
paseo_refuse_symlink "${user_home}/.biab" "$paseo_home" "${paseo_home}/${PASEO_MARKER_NAME}" \
    "${user_home}/.bashrc.d" "${user_home}/.bashrc.d/biab-paseo.sh" \
    || die "46-paseo: a path BIAB would write in your home folder is a symbolic link; nothing was installed. See the message above."

# A previous BIAB-owned home is fine; a non-empty directory that is not ours is
# not ours to adopt or later delete.
if [[ -d "$paseo_home" ]] && ! bib_marker_file_is_ours "${paseo_home}/${PASEO_MARKER_NAME}" "$BIB_OWNERSHIP_MARKER" \
   && [[ -n "$(ls -A "$paseo_home" 2>/dev/null)" ]]; then
    die "46-paseo: ${paseo_home} exists and is not BIAB-owned; refusing to adopt it"
fi

# --- 2. Pinned tree --------------------------------------------------------
# `biab update --latest` (FEAT-038): the newest stable @getpaseo/cli replaces the pin
# and the repo lockfile is not used. The pin constant is moved to that version here so
# the tree path, the checks below and the log all agree; an unreadable registry, or a
# latest that is not stable, installs the pin and says so.
paseo_latest_mode=0
if [[ "${BIB_PINS_MODE:-pinned}" == "latest" ]]; then
    _lrc=0
    _latest="$(pin_npm_latest_version "@getpaseo/cli")" || _lrc=$?
    if [[ "$_lrc" -eq 0 ]]; then
        PASEO_PIN="$_latest"
        PASEO_TREE_DIR="${PASEO_OPT_DIR}/${PASEO_PIN}"
        paseo_latest_mode=1
        log "46-paseo: --latest: paseo ${PASEO_PIN} (untested combination, no lockfile)"
    else
        warn "46-paseo: --latest could not get a stable @getpaseo/cli version from npm (rc ${_lrc}); installing the pinned ${PASEO_PIN} instead"
    fi
fi

installed_version() {
    "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true
}

install -o root -g root -m 0755 -d "$PASEO_OPT_DIR" "${PASEO_OPT_DIR}/bin"

if [[ "$(installed_version "${PASEO_TREE_DIR}/node_modules/.bin/paseo")" == "$PASEO_PIN" ]]; then
    log "46-paseo: paseo ${PASEO_PIN} already installed, skipping npm ci"
else
    staging="${PASEO_TREE_DIR}.partial"
    rm -rf "$staging"
    install -o root -g root -m 0755 -d "$staging"
    trap 'rm -rf "$staging"' EXIT
    # --ignore-scripts: this runs as root, and the tree's install scripts add
    # nothing on linux-x64 (SPIKE T1: node-pty ships a prebuilt pty.node, esbuild
    # a prebuilt binary, msgpackr-extract falls back). Not running third-party
    # lifecycle scripts as root is the safer default.
    if [[ "$paseo_latest_mode" -eq 1 ]]; then
        jq -n --arg v "$PASEO_PIN" '{name:"biab-paseo-latest", version:"0.0.0", private:true, dependencies:{"@getpaseo/cli":$v}}' > "${staging}/package.json"
        log "46-paseo: npm install for @getpaseo/cli@${PASEO_PIN}, no lockfile (this downloads a few hundred MB)"
        (cd "$staging" && npm install --omit=dev --no-audit --no-fund --ignore-scripts >/dev/null 2>&1) \
            || die "46-paseo: 'npm install' failed for @getpaseo/cli@${PASEO_PIN}. Check the network and re-run 'biab update'. Nothing was installed, and SSH access is untouched."
    else
        cp "${SRC_DIR}/package.json" "${SRC_DIR}/package-lock.json" "$staging/"
        log "46-paseo: npm ci for @getpaseo/cli@${PASEO_PIN} (this downloads a few hundred MB)"
        (cd "$staging" && npm ci --omit=dev --no-audit --no-fund --ignore-scripts >/dev/null 2>&1) \
            || die "46-paseo: 'npm ci' failed for @getpaseo/cli@${PASEO_PIN}. Check the network and re-run 'biab update'. Nothing was installed, and SSH access is untouched."
    fi
    if [[ "$(installed_version "${staging}/node_modules/.bin/paseo")" != "$PASEO_PIN" ]]; then
        die "46-paseo: installed tree does not report paseo ${PASEO_PIN}; refusing to use it. Nothing was installed."
    fi
    rm -rf "$PASEO_TREE_DIR"
    mv "$staging" "$PASEO_TREE_DIR"
    trap - EXIT
fi

prev_target="$(readlink "$PASEO_CURRENT_LINK" 2>/dev/null || true)"
ln -sfn "$PASEO_TREE_DIR" "$PASEO_CURRENT_LINK"
[[ "$prev_target" == "$PASEO_TREE_DIR" ]] || changed=1

# `paseo` on PATH for the user, but only when nothing else already provides it:
# a Paseo the user installed themselves is theirs.
if ! command -v paseo >/dev/null 2>&1 || [[ "$(readlink /usr/local/bin/paseo 2>/dev/null || true)" == /opt/buildersinabox/paseo/* ]]; then
    ln -sfn "$PASEO_CLI_BIN" "/usr/local/bin/paseo"
else
    log "46-paseo: another 'paseo' is already on PATH, leaving PATH alone"
fi

# A changed launcher or watchdog only takes effect in a running daemon after a
# restart (the provider guard lives in the launcher).
cmp -s "${SRC_DIR}/bin/biab-paseo-run" "$PASEO_RUN_TARGET" 2>/dev/null || changed=1
cmp -s "${SRC_DIR}/bin/biab-paseo-health" "$PASEO_HEALTH_TARGET" 2>/dev/null || changed=1
install -o root -g root -m 0755 "${SRC_DIR}/bin/biab-paseo-run" "$PASEO_RUN_TARGET"
install -o root -g root -m 0755 "${SRC_DIR}/bin/biab-paseo-health" "$PASEO_HEALTH_TARGET"
# Used by /first-project and /second-project (T4); called by absolute path, so
# nothing is added to PATH and the /opt teardown removes it.
install -o root -g root -m 0755 "${SRC_DIR}/bin/biab-workspace" "${PASEO_OPT_DIR}/bin/biab-workspace"
# The full-access switch of FEAT-035 is gone (FEAT-041); drop it from boxes that
# still have it.
rm -f -- "${PASEO_OPT_DIR}/bin/biab-paseo-antigravity"

# --- 3. Credential, home, snippet, unit ------------------------------------
# prestart creates the credential only when absent, so `biab update` never
# rotates it. It prints nothing secret.
"$PASEO_RUN_TARGET" prestart
install -o root -g root -m 0755 -d "$PASEO_HEALTH_DIR"

# Everything under the user's home is created AS the user, never as root.
paseo_prepare_user_state "$operator_user" "$user_home" \
    || die "46-paseo: could not prepare ${paseo_home} safely; nothing was changed in your home folder beyond what is listed above."
if [[ -d "${user_home}/.paseo" ]]; then
    log "46-paseo: found an existing ~/.paseo; it is left alone, BIAB uses ${paseo_home}"
fi

unit_tmp="${PASEO_UNIT}.tmp"
BIB_USER="$operator_user" PASEO_HOME="$paseo_home" \
    envsubst '${BIB_USER} ${PASEO_HOME}' < "${SRC_DIR}/systemd/biab-paseo.service.in" > "$unit_tmp"
if ! cmp -s "$unit_tmp" "$PASEO_UNIT" 2>/dev/null; then
    changed=1
fi
install -o root -g root -m 0644 "$unit_tmp" "$PASEO_UNIT"
rm -f "$unit_tmp"

# Watchdog units (T2): static files. The failed-unit recorder and the health
# pass are oneshots; only the timer is enabled.
for u in biab-paseo-failed.service biab-paseo-health.service biab-paseo-health.timer; do
    install -o root -g root -m 0644 "${SRC_DIR}/systemd/${u}" "$(dirname "$PASEO_UNIT")/${u}"
done

systemctl daemon-reload
systemctl enable biab-paseo.service >/dev/null 2>&1
systemctl enable --now biab-paseo-health.timer >/dev/null 2>&1
if [[ "$changed" -eq 1 ]]; then
    systemctl restart biab-paseo.service
else
    systemctl start biab-paseo.service
fi

# The daemon synced the provider block just before it started. Confirm it from
# here, as the box user. The start can lag (it waits for the tailnet address),
# so poll briefly and only warn: the health timer verifies it every 2 minutes.
_prov_ok=0
for _try in 1 2 3 4 5 6 7 8 9 10; do
    if paseo_as_user "$operator_user" env PASEO_HOME="$paseo_home" "$PASEO_RUN_TARGET" providers verify >/dev/null 2>&1; then
        _prov_ok=1
        break
    fi
    sleep 2
done
if [[ "$_prov_ok" -eq 1 ]]; then
    log "46-paseo: provider settings verified (Paseo's built-in antigravity provider is disabled)"
else
    warn "46-paseo: provider settings not verified yet. The service may still be waiting for the tailnet, or it refused to start because its provider config could not be read; 'biab status' names the file and what to do."
fi

# Older pinned trees (a previous version, or a .partial from an interrupted
# install) are dead weight once the unit runs from the current one.
if systemctl is-active --quiet biab-paseo.service; then
    paseo_prune_old_trees
fi

log "46-paseo: done. paseo ${PASEO_PIN}, unit biab-paseo.service, home ${paseo_home}"

# TODO(2026-10-31): remove after 2027-04-30 together with bib_paseo_migrate.
# `biab update` on a box installed with the old SSH-session layout: move its
# projects into Paseo (R8, D6). A failure here must not abort the rest of the
# install; the next update retries and nothing was removed.
bib_paseo_migrate "$operator_user" "$user_home" \
    || warn "46-paseo: migration to Paseo is incomplete; run 'biab update' again"

# An Antigravity box whose agy settings let it read outside the project without
# asking gets that setting tightened once (and is told). It does not depend on
# Paseo or on the provider check below, so it runs either way.
paseo_agy_tighten_settings "$operator_user" "$user_home"

# A box that opted in to Antigravity's old full-access mode is moved to the
# provider that asks before it acts, and told once (FEAT-041 R6). Only when the
# provider settings verified just above: otherwise the warning there already
# says what to do, the key stays and the next update retries. The function
# warns by itself when it fails, so no second warning here.
if [[ "$_prov_ok" -eq 1 ]]; then
    bib_paseo_antigravity_convert "$operator_user" "$user_home" || true
fi
paseo_agy_tighten_report
