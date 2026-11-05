#!/usr/bin/env bash
# shellcheck disable=SC2034  # constants are consumed by the scripts that source this file
# Shared helpers for the pinned Paseo daemon (FEAT-035).
# Source this file; do not execute it directly.
#
# Paseo is a third-party daemon that runs shells for the box user and listens
# on the network, so everything that decides what it may do (version, bind
# address, password, relay switch) lives in root-owned places the agents it
# launches cannot edit. See install/46-paseo.sh and paseo/systemd/.

set -euo pipefail

_PASEO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The one version BIAB installs. Never "latest". A bump is three edits made
# together: "@getpaseo/cli" in payload/paseo/package.json, the regenerated
# payload/paseo/package-lock.json, and this constant. payload/test/paseo.sh
# fails when they disagree.
# Pin decided by the maintainer on 2026-10-19.
PASEO_PIN="0.12.0"

PASEO_PORT=6767

# Test seam, same shape as NIGHT_PREFIX in pack/night-shift/lib.sh: honoured
# ONLY when the caller declares test mode, so a stray env var can never
# redirect a real install or uninstall.
# Test mode (BIB_PASEO_TEST=1) is honoured only for a sandbox prefix under /tmp
# or /var/tmp (owned by the caller if it exists), or for a non-root caller on
# the real tree. In root's environment on a real install the flag is ignored:
# it must never skip require_root, the TTY check or the exec seams.
if [[ "${BIB_PASEO_TEST:-0}" == "1" ]]; then
    _bib_tp="${BIB_PASEO_ROOT_TEST:-}"
    if [[ -z "$_bib_tp" ]]; then
        [[ "$(id -u)" -ne 0 ]] || BIB_PASEO_TEST=0
    else
        case "$_bib_tp" in
            *..*) BIB_PASEO_TEST=0 ;;
            /tmp/*|/var/tmp/*) [[ ! -e "$_bib_tp" || -O "$_bib_tp" ]] || BIB_PASEO_TEST=0 ;;
            *) BIB_PASEO_TEST=0 ;;
        esac
    fi
    unset _bib_tp
fi
PASEO_PREFIX=""
if [[ "${BIB_PASEO_TEST:-0}" == "1" ]]; then
    PASEO_PREFIX="${BIB_PASEO_ROOT_TEST:-}"
fi

# Where the pinned tree and the helper scripts live. Root-owned.
PASEO_OPT_DIR="${PASEO_PREFIX}/opt/buildersinabox/paseo"
PASEO_TREE_DIR="${PASEO_OPT_DIR}/${PASEO_PIN}"
PASEO_CURRENT_LINK="${PASEO_OPT_DIR}/current"
PASEO_RUN_TARGET="${PASEO_OPT_DIR}/bin/biab-paseo-run"
PASEO_CLI_BIN="${PASEO_CURRENT_LINK}/node_modules/.bin/paseo"
PASEO_HEALTH_TARGET="${PASEO_OPT_DIR}/bin/biab-paseo-health"

# The pinned agy (install/41-antigravity-cli.sh). The ACP provider launches
# exactly this absolute path (FEAT-041), never whatever PATH resolves.
PASEO_AGY_BIN="${PASEO_PREFIX}/usr/local/bin/agy"

# The per-box credential. root:root 0600, and NOWHERE else: state.json is 0644
# and bootstrap.log is 0666, so log()/warn() must never see the value.
PASEO_ENV_DIR="${PASEO_PREFIX}/etc/buildersinabox"
PASEO_ENV_FILE="${PASEO_ENV_DIR}/paseo.env"

PASEO_UNIT="${PASEO_PREFIX}/etc/systemd/system/biab-paseo.service"

# Health record (no secrets, 0644): health.json is written only by
# biab-paseo-health; the `paired` / `repair-needed` flags sit beside it.
PASEO_HEALTH_DIR="${BIB_STATE_DIR:-/var/lib/buildersinabox}/paseo"

# Name of the marker file inside PASEO_HOME. Its content is the ownership
# string, so uninstall deletes the home only when it is ours.
PASEO_MARKER_NAME=".biab-owned"

# Echo the BIAB-owned daemon home for <home>. Never ~/.paseo: that may be the
# user's own daemon and BIAB must not adopt, overwrite or delete it.
paseo_home_for() {
    printf '%s/.biab/paseo' "$1"
}

# ---------------------------------------------------------------------------
# Hygiene for user-owned paths (FEAT-035 review cycle 1, finding 1).
#
# The box user owns ~/.biab, the Paseo home and ~/.bashrc.d, and the agents we
# launch run as that user: anything under those paths may be a symlink they
# planted (marker -> /etc/sudoers). Root must therefore never write there
# through a name the user controls. Two rules, both enforced here:
#   1. refuse (abort the step) when any such path is a symlink;
#   2. do the writes AS the user, so even a lost race cannot reach a file the
#      user could not already write.
# ---------------------------------------------------------------------------

# paseo_refuse_symlink <path...> — fail, with a clear message, if any of the
# paths is a symbolic link. Missing paths pass.
paseo_refuse_symlink() {
    local p
    for p in "$@"; do
        if [[ -L "$p" ]]; then
            printf 'paseo: refusing to continue: %s is a symbolic link. BIAB never writes through links in your home folder. Remove the link (or move it away) and run the step again.\n' "$p" >&2
            return 1
        fi
    done
    return 0
}

# paseo_as_user <user> <external command...> — run as <user>. No privilege
# drop when the caller already is <user>; BIB_PASEO_TEST=1 also skips it so a
# non-root test can drive the same code. External commands only (runuser
# cannot call a shell function).
paseo_as_user() {
    local user="$1"
    shift
    if [[ "${BIB_PASEO_TEST:-0}" == "1" ]] || [[ "$(id -un)" == "$user" ]]; then
        "$@"
    else
        runuser -u "$user" -- "$@"
    fi
}

# Write the ownership marker into a BIAB-owned PASEO_HOME, as <user> when given.
# Refuses a symlinked home or marker.
# paseo_mark_home <home> [user]
paseo_mark_home() {
    local home="$1" user="${2:-}" marker
    marker="${home}/${PASEO_MARKER_NAME}"
    paseo_refuse_symlink "$home" "$marker" || return 1
    if [[ -n "$user" ]]; then
        paseo_as_user "$user" bash -c 'umask 022; printf "%s\n" "$1" > "$2"' _ "$BIB_OWNERSHIP_MARKER" "$marker"
    else
        printf '%s\n' "$BIB_OWNERSHIP_MARKER" > "$marker"
    fi
}

# Create ~/.biab, the Paseo home, its marker and the ~/.bashrc.d snippet for
# <user>, refusing symlinks and writing as the user. Idempotent.
# paseo_prepare_user_state <user> <user_home>
paseo_prepare_user_state() {
    local user="$1" uhome="$2" home snippet_dir snippet
    home="$(paseo_home_for "$uhome")"
    snippet_dir="${uhome}/.bashrc.d"
    snippet="${snippet_dir}/biab-paseo.sh"
    paseo_refuse_symlink "${uhome}/.biab" "$home" "${home}/${PASEO_MARKER_NAME}" "$snippet_dir" "$snippet" || return 1
    paseo_as_user "$user" install -m 0700 -d "${uhome}/.biab" "$home" || return 1
    paseo_mark_home "$home" "$user" || return 1
    paseo_as_user "$user" install -m 0755 -d "$snippet_dir" || return 1
    printf '%s\n' \
        '# shellcheck shell=bash' \
        '# Builders in a Box: point the paseo CLI at the daemon BIAB runs.' \
        "export PASEO_HOME=\"${home}\"" \
        | paseo_as_user "$user" bash -c 'umask 022; cat > "$1"' _ "$snippet"
}

# Read the last 10 MiB of a user-owned file for at most 5 s (a swapped-in FIFO or
# /dev/zero must not hang or flood a root process). Never fails the caller.
# paseo_read_log_capped <file>
paseo_read_log_capped() {
    timeout 5 tail -c 10485760 -- "$1" 2>/dev/null || true
}

# Number of authenticated app connections in <daemon.log> from an address other
# than <own>, the box's own tailnet address (its CLI connects from there). The
# log lives in a user-owned folder, so: it must be a regular file with no
# symlink in its last two folders, else it counts as empty. An empty <own>
# means "unknown": 0, never "every hello is a phone". Always prints a number
# and returns 0, so it is safe under set -e / pipefail.
# paseo_foreign_hellos <daemon.log> <own>
paseo_foreign_hellos() {
    local f="$1" own="$2" n d
    if [[ -z "$own" || ! -f "$f" || -L "$f" || ! -r "$f" ]]; then printf '0\n'; return 0; fi
    d="$(dirname "$f")"
    if [[ -L "$d" || -L "$(dirname "$d")" ]]; then printf '0\n'; return 0; fi
    # Bounded read: between the checks above and the open, the box user can swap
    # the file for a FIFO or /dev/zero. `timeout tail -c` caps both time and size.
    n="$(paseo_read_log_capped "$f" | jq -Rr --arg own "$own" 'fromjson? | select(.msg == "Client connected via hello" and .remoteAddress != $own) | .remoteAddress' \
        2>/dev/null | wc -l)" || n=0
    n="${n//[[:space:]]/}"
    printf '%s\n' "${n:-0}"
}

# paseo_acp_preflight <user> — true when the pinned agy can run as an ACP server:
# `agy acp --help` must exit 0 AND say "Agent Client Protocol" (an older agy
# answers `acp --help` with its general usage, so the exit code alone proves
# nothing). Run as the box user, from the absolute path the provider uses.
# Prints the reason on stderr when it fails.
paseo_acp_preflight() {
    local user="$1" out="" rc=0 home ver=""
    home="$(getent passwd "$user" | cut -d: -f6 || true)"
    if [[ ! -x "$PASEO_AGY_BIN" ]]; then
        printf 'agy is not installed at %s, so there is no "agy acp"\n' "$PASEO_AGY_BIN" >&2
        return 1
    fi
    out="$(paseo_as_user "$user" timeout 20 env HOME="${home:-/}" AGY_CLI_DISABLE_AUTO_UPDATE=1 "$PASEO_AGY_BIN" acp --help </dev/null 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 && "$out" == *"Agent Client Protocol"* ]]; then
        return 0
    fi
    ver="$(paseo_as_user "$user" timeout 20 env HOME="${home:-/}" "$PASEO_AGY_BIN" --version </dev/null 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    printf 'the installed agy%s has no working "agy acp" (its help did not say "Agent Client Protocol")\n' "${ver:+ ${ver}}" >&2
    return 1
}

# The helper every box keeps, with or without the daemon: biab-workspace (the
# skills call it by path).
_paseo_is_kept_bin() {
    [[ "$1" == "${PASEO_OPT_DIR}/bin" || "$1" == "${PASEO_OPT_DIR}/bin/biab-workspace" ]]
}

# True when this box carries a BIAB Paseo install: our unit, our credential, or
# anything in the /opt tree beyond the helpers every box gets.
paseo_has_install() {
    [[ -e "$PASEO_UNIT" || -L "$PASEO_UNIT" || -e "$PASEO_ENV_FILE" ]] && return 0
    local e
    for e in "${PASEO_OPT_DIR}"/* "${PASEO_OPT_DIR}"/bin/*; do
        [[ -e "$e" || -L "$e" ]] || continue
        _paseo_is_kept_bin "$e" && continue
        return 0
    done
    return 1
}

# Take a BIAB-owned Paseo install off the box (the Paseo part of --uninstall):
# daemon stopped and disabled BEFORE its unit goes, then unit files, credential,
# pinned tree and helpers (biab-workspace stays),
# `paseo` link if it is ours, health record, the user's snippet, and the Paseo
# home only if it carries our marker and no link sits on the way (removal runs
# AS the user). ~/.paseo is never touched. Idempotent. Used when a box that
# had the daemon is re-installed with a CLI that does not run under Paseo.
# paseo_teardown_install [<user> <user_home>]
paseo_teardown_install() {
    local user="${1:-}" uhome="${2:-}" u e
    paseo_has_install || return 0
    log "46-paseo: removing the BIAB Paseo daemon left from a previous install (this box no longer uses it)"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now biab-paseo-health.timer >/dev/null 2>&1 || true
        systemctl disable --now biab-paseo.service >/dev/null 2>&1 || true
    fi
    for u in biab-paseo.service biab-paseo-failed.service biab-paseo-health.service biab-paseo-health.timer; do
        rm -f -- "$(dirname "$PASEO_UNIT")/${u}"
    done
    rm -f -- "$PASEO_ENV_FILE"
    rmdir "$PASEO_ENV_DIR" 2>/dev/null || true
    for e in "${PASEO_OPT_DIR}"/* "${PASEO_OPT_DIR}"/.[!.]*; do
        [[ -e "$e" || -L "$e" ]] || continue
        [[ "$e" == "${PASEO_OPT_DIR}/bin" ]] && continue
        rm -rf -- "$e"
    done
    for e in "${PASEO_OPT_DIR}"/bin/*; do
        [[ -e "$e" || -L "$e" ]] || continue
        _paseo_is_kept_bin "$e" && continue
        rm -rf -- "$e"
    done
    local link="${PASEO_PREFIX}/usr/local/bin/paseo"
    if [[ -L "$link" && "$(readlink "$link")" == */opt/buildersinabox/paseo/* ]]; then
        rm -f -- "$link"
    fi
    rm -rf -- "$PASEO_HEALTH_DIR"
    if command -v systemctl >/dev/null 2>&1; then systemctl daemon-reload >/dev/null 2>&1 || true; fi

    [[ -n "$user" && -n "$uhome" ]] || return 0
    local phome snip_dir
    phome="$(paseo_home_for "$uhome")"
    snip_dir="${uhome}/.bashrc.d"
    if [[ ! -L "$snip_dir" && ( -e "${snip_dir}/biab-paseo.sh" || -L "${snip_dir}/biab-paseo.sh" ) ]]; then
        paseo_as_user "$user" rm -f -- "${snip_dir}/biab-paseo.sh" || true
    fi
    if [[ -L "${uhome}/.biab" || -L "$phome" ]]; then
        warn "46-paseo: leaving ${phome} alone: it (or ~/.biab) is a symbolic link"
    elif [[ -d "$phome" ]]; then
        if bib_marker_file_is_ours "${phome}/${PASEO_MARKER_NAME}" "$BIB_OWNERSHIP_MARKER"; then
            paseo_as_user "$user" rm -rf -- "$phome" || true
            paseo_as_user "$user" rmdir "${uhome}/.biab" 2>/dev/null || true
        else
            warn "46-paseo: leaving ${phome} alone: it is not BIAB-owned"
        fi
    fi
    return 0
}

# Remove the pinned trees of OTHER versions (and leftover .partial staging dirs)
# under PASEO_OPT_DIR. Each tree is ~560 MB and a pin bump installs a new one
# beside the old, so without this the disk grows by one tree per bump. Call it
# only after the daemon runs from PASEO_TREE_DIR. Only directories named like a
# version are touched; bin/ and anything else in the folder stay.
paseo_prune_old_trees() {
    local d
    for d in "${PASEO_OPT_DIR}"/[0-9]*.[0-9]*.[0-9]* "${PASEO_OPT_DIR}"/*.partial; do
        [[ -d "$d" && ! -L "$d" ]] || continue
        [[ "$d" == "$PASEO_TREE_DIR" ]] && continue
        rm -rf -- "$d"
    done
}
# ---------------------------------------------------------------------------
# Wizard side (FEAT-035 T3). Needs lib/ai-cli.sh sourced for the CLI verbs.
# ---------------------------------------------------------------------------

# Text the user sees in the app, so BIAB is named as the origin of the setup
# (R9). Paseo's own name appears only where the user must find their app.
PASEO_TITLE_PREFIX="BIAB · "
PASEO_WORKSPACE_NAME="${PASEO_TITLE_PREFIX}ai-platform"
PASEO_AGENT_TITLE="${PASEO_TITLE_PREFIX}Start here"

# How the user pairs after the wizard (delivered by `biab paseo pair`, T2).
PASEO_PAIR_LATER_CMD="sudo biab paseo pair"

# Background flag of `paseo run` in the pinned version (0.11.x called it
# -d/--background). payload/test/paseo.sh checks it against the pinned --help.
PASEO_RUN_BACKGROUND_FLAG="--no-wait"

# Where the box state lives. Same file as common.sh's BIB_STATE_FILE; paseo.sh
# is also sourced without common.sh.
paseo_state_file() {
    printf '%s' "${BIB_STATE_FILE:-${PASEO_PREFIX}/var/lib/buildersinabox/state.json}"
}

# The ONE decision point for "does this CLI get the Paseo interface?": a CLI
# that Paseo can run with its permission prompts on. Two ways to be one:
#   - `paseo-permissioned`: claude, codex and antigravity (through BIAB's ACP
#     provider) always ask, by construction;
#   - `paseo-seeded` (OpenCode, FEAT-040): its own defaults allow everything, so
#     it counts only while the rules BIAB seeds in the box user's own config
#     still hold, checked here on every call (ai_cli_permissions_ok).
# Flip a CLI by declaring the capability in its adapter, not by editing a caller.
paseo_supports_cli() {
    local cli="$1" home
    ai_cli_has_capability "$cli" paseo-permissioned && return 0
    ai_cli_has_capability "$cli" paseo-seeded || return 1
    home="$(paseo_box_home)" || return 1
    ai_cli_permissions_ok "$cli" "$home"
}

# The box user's home folder, for the checks that read the user's own config.
# From the state's box user and the passwd entry, never from $HOME (which the
# user controls). Prints nothing and fails when it cannot be resolved, so the
# gate above fails closed. Test seam BIB_PERMISSIONS_HOME, test mode only.
paseo_box_home() {
    local u h
    if [[ "${BIB_PASEO_TEST:-0}" == "1" && -n "${BIB_PERMISSIONS_HOME:-}" ]]; then
        printf '%s' "$BIB_PERMISSIONS_HOME"
        return 0
    fi
    u="$(jq -r '.bib_user // empty' "$(paseo_state_file)" 2>/dev/null)" || return 1
    [[ -n "$u" && "$u" != "root" ]] || return 1
    h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
    [[ "$h" == /* && "$h" != "/" ]] || return 1
    printf '%s' "$h"
}

# paseo_not_permissioned_reason <cli> — one sentence on why a CLI that declares
# `paseo-seeded` is not on Paseo right now; empty for any other CLI.
paseo_not_permissioned_reason() {
    local cli="$1" home
    ai_cli_has_capability "$cli" paseo-seeded || return 0
    home="$(paseo_box_home)" || { printf '%s' "the box user could not be found in the setup state"; return 0; }
    ai_cli_permissions_reason "$cli" "$home" || true
}

# bib_paseo_antigravity_convert <user> <user_home>
# TODO(2026-10-31): remove after 2027-04-30 (FEAT-041 D4), once no box can still
# carry the old full-access opt-in key.
# Called from install/46-paseo.sh on every install and `biab update`, right
# after the daemon start. A box that opted in to Antigravity's old full-access
# mode keeps a state key; this moves it to the provider that asks before it
# acts and deletes the key. Root, like bib_paseo_migrate. Returns 0 when there
# is nothing to do or it converged; 1 when the provider settings did not verify
# (the key stays and the next update retries). Needs lib/common.sh sourced.
#   - key absent: nothing happens, nothing is printed;
#   - provider settings checked AS the box user with the root-owned launcher
#     in an empty environment (it reads the user's config.json, root never
#     follows a link in the user's home);
#   - key was `true`: the notice is printed first (printf, no secret in it),
#     the key is deleted second, so a crash in between repeats the notice;
#   - key was anything else, or the box does not use Antigravity: deleted
#     silently, without a check.
bib_paseo_antigravity_convert() {
    local user="$1" user_home="$2" was file
    file="$(paseo_state_file)"
    [[ -r "$file" ]] || return 0
    jq -e 'has("paseo_antigravity_optin")' "$file" >/dev/null 2>&1 || return 0
    was="$(jq -r 'if .paseo_antigravity_optin == true and .ai_cli == "antigravity" then "true" else "other" end' "$file" 2>/dev/null || echo other)"
    if [[ "$(jq -r '.ai_cli // empty' "$file" 2>/dev/null || true)" != "antigravity" ]]; then
        # A stale key on a box that does not use Antigravity: nothing to convert.
        state_del '.paseo_antigravity_optin' || { warn "paseo: could not remove the old Antigravity opt-in key from the box state"; return 1; }
        return 0
    fi
    local -a cenv=(PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                   HOME="$user_home" PASEO_HOME="$(paseo_home_for "$user_home")")
    # Test mode only: the launcher must see the same sandbox this function does.
    if [[ "${BIB_PASEO_TEST:-0}" == "1" ]]; then
        cenv=(PATH="${PATH}" HOME="$user_home" PASEO_HOME="$(paseo_home_for "$user_home")"
              BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${BIB_PASEO_ROOT_TEST:-}")
    fi
    if ! paseo_as_user "$user" env -i "${cenv[@]}" "$PASEO_RUN_TARGET" providers verify >/dev/null 2>&1; then
        warn "paseo: Antigravity's provider settings are not verified yet, so the old opt-in key was kept (see 'biab status' for the file and what to do)"
        return 1
    fi
    if [[ "$was" == "true" ]]; then
        printf '\nAntigravity now runs in the Paseo app. It asks before it runs shell commands and\n'
        printf 'before it writes files in your project, your home folder, ~/.biab or /var/tmp'
        if paseo_agy_reads_ask "$user" "$user_home"; then
            printf ',\nand before it reads files outside your project.\n'
        else
            printf '.\n'
        fi
        printf 'It does not ask before it reads inside the project, searches the web, opens web\n'
        printf 'pages or writes in /tmp. The prompt offers only allow once or reject, with no\n'
        printf 'always-allow; the Auto Accept switch in the app is separate. (Measured with agy 1.4.11.)\n'
        if [[ "${PASEO_AGY_TIGHTENED:-0}" == "1" ]]; then
            printf 'Your agy setting allowNonWorkspaceAccess was true; it is now false, which is\n'
            printf 'what makes reads outside the project ask.\n'
            PASEO_AGY_TIGHTENED=told
        elif ! paseo_agy_reads_ask "$user" "$user_home"; then
            printf 'Reads outside your project do not ask on this box: allowNonWorkspaceAccess in\n'
            printf '%s/.gemini/antigravity-cli/settings.json is not false.\n' "$user_home"
        fi
        printf 'Conversations started in the old full-access mode stay in the app but cannot\n'
        printf 'be continued: start a new agent. Applying this restarts the phone-app service,\n'
        printf 'which ends any agent that was running.\n\n'
    fi
    state_del '.paseo_antigravity_optin' || { warn "paseo: could not remove the old Antigravity opt-in key from the box state"; return 1; }
    log "paseo: the retired Antigravity opt-in key was removed from the box state"
}

# paseo_agy_tighten_settings <user> <user_home> — FEAT-041, a ONE-TIME migration.
# An Antigravity box installed before reads outside the project without asking
# because BIAB used to seed agy's allowNonWorkspaceAccess as true. The first
# update that can look at the file flips a `true` to `false`, and nothing else;
# when it finishes (whether it had to change anything or not) it writes
# `.agy_reads_tightened=true` in the box state and never acts again, so a
# `true` the user sets afterwards is theirs. The change is made as the box user
# (never root, never through a link: the folders and the file must not be
# symbolic links and the file must be a regular file holding a JSON object),
# through a temporary file in the same folder, mode kept, other settings kept.
# A link, a file that is not a JSON object or a write that fails is NOT silent:
# it warns, naming the file and what to set by hand, and leaves no mark, so the
# next update tries again. A missing file or any value other than `true` is
# nothing to change (marked). Sets PASEO_AGY_TIGHTENED=1 when it flipped the
# setting, so the conversion notice (or paseo_agy_tighten_report) says so once.
# Returns 0 always: a setting that could not be changed must not stop an update.
# TODO(2026-10-31): remove after 2027-04-30 together with bib_paseo_antigravity_convert.
paseo_agy_tighten_settings() {
    local user="$1" user_home="$2" file state rc=0
    state="$(paseo_state_file)"
    [[ "$(jq -r '.ai_cli // empty' "$state" 2>/dev/null || true)" == "antigravity" ]] || return 0
    [[ "$(jq -r '.agy_reads_tightened // empty' "$state" 2>/dev/null || true)" != "true" ]] || return 0
    file="${user_home}/.gemini/antigravity-cli/settings.json"
    paseo_as_user "$user" bash -c '
        f="$1"; d="$(dirname "$f")"
        [[ ! -L "$(dirname "$d")" && ! -L "$d" && ! -L "$f" ]] || exit 4
        [[ -e "$f" ]] || exit 3
        [[ -f "$f" ]] || exit 4
        jq -e "type == \"object\"" "$f" >/dev/null 2>&1 || exit 4
        jq -e ".allowNonWorkspaceAccess == true" "$f" >/dev/null 2>&1 || exit 3
        tmp="$(mktemp "${f}.XXXXXX")" || exit 1
        if jq ".allowNonWorkspaceAccess = false" "$f" > "$tmp" && chmod --reference="$f" "$tmp" && mv -f "$tmp" "$f"; then exit 0; fi
        rm -f "$tmp"; exit 1' _ "$file" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0|3)
            [[ "$rc" -ne 0 ]] || { PASEO_AGY_TIGHTENED=1; log "paseo: agy setting allowNonWorkspaceAccess set to false (reads outside the project ask)"; }
            state_set '.agy_reads_tightened' true || warn "paseo: could not record that the agy setting was checked; the next update will check it again" ;;
        4) warn "paseo: ${file} (or a folder above it) is a symbolic link, not a regular file or not a JSON object, so BIAB left it alone. Reads outside your project will not ask until it holds \"allowNonWorkspaceAccess\": false; set that by hand. 'biab update' will look again." ;;
        *) warn "paseo: could not change allowNonWorkspaceAccess in ${file}. Reads outside your project will not ask until it holds \"allowNonWorkspaceAccess\": false; set that by hand. 'biab update' will try again." ;;
    esac
    return 0
}

# paseo_agy_reads_ask <user> <user_home> — true when agy's settings say reads
# outside the project ask (allowNonWorkspaceAccess is exactly false), read as
# the box user without following links. The conversion notice only claims
# what this says.
paseo_agy_reads_ask() {
    local user="$1" user_home="$2" file
    file="${user_home}/.gemini/antigravity-cli/settings.json"
    paseo_as_user "$user" bash -c '
        f="$1"; d="$(dirname "$f")"
        [[ ! -L "$(dirname "$d")" && ! -L "$d" && ! -L "$f" && -f "$f" ]] || exit 1
        jq -e "type == \"object\" and .allowNonWorkspaceAccess == false" "$f" >/dev/null 2>&1' _ "$file" >/dev/null 2>&1
}

# Says it once for a box that was not told by the conversion notice (it had no
# full-access opt-in): only when the setting was flipped in this run.
paseo_agy_tighten_report() {
    [[ "${PASEO_AGY_TIGHTENED:-0}" == "1" ]] || return 0
    printf '\nAntigravity now asks before it reads files outside your project: your agy setting\n'
    printf 'allowNonWorkspaceAccess was true and is now false. Your skills folder is not\n'
    printf 'affected.\n\n'
    PASEO_AGY_TIGHTENED=told
}

# paseo_run_as <user> <home> <paseo args...> — run the PINNED paseo CLI against
# the BIAB-owned daemon home, as the box user. The absolute pinned binary, not
# PATH: the user may have their own `paseo`. No privilege drop when the caller
# already is <user> (biab-workspace runs as the box user). Test seam:
# BIB_PASEO_TEST=1 also skips it so a non-root test can drive the wizard step.
paseo_run_as() {
    local user="$1" home="$2"
    shift 2
    if [[ "${BIB_PASEO_TEST:-0}" == "1" ]] || [[ "$(id -un)" == "$user" ]]; then
        env PASEO_HOME="$home" "$PASEO_CLI_BIN" "$@"
    else
        sudo -u "$user" -H env PASEO_HOME="$home" "$PASEO_CLI_BIN" "$@"
    fi
}

# Wait until the daemon answers. The CLI's own wait defaults to 10 minutes.
paseo_wait_ready() {
    local user="$1" home="$2"
    local limit="${BIB_PASEO_READY_TIMEOUT:-120}" step="${BIB_PASEO_POLL_SEC:-2}" waited=0
    while :; do
        if paseo_run_as "$user" "$home" daemon status --json 2>/dev/null \
            | jq -e '.connectedDaemon == "reachable"' >/dev/null 2>&1; then
            return 0
        fi
        (( waited >= limit )) && return 1
        sleep "$step"
        waited=$((waited + step))
    done
}

# Find or create the workspace for <path>; print its id. `paseo run` without
# --workspace creates a new workspace every time (SPIKE T1), so the id is
# always passed. `workspace create` also registers the project. Idempotent by
# the absolute path, which is what `workspace ls` reports as cwd. The title is
# data for the app only; the path is what identifies the workspace.
# paseo_ensure_workspace <user> <home> <path> [title]
paseo_ensure_workspace() {
    local user="$1" home="$2" path="$3" title="${4:-$PASEO_WORKSPACE_NAME}" id
    id="$(paseo_run_as "$user" "$home" workspace ls --json \
        | jq -r --arg p "$path" '[.[] | select(.cwd == $p)][0].workspaceId // empty')"
    if [[ -z "$id" ]]; then
        id="$(paseo_run_as "$user" "$home" workspace create --isolation local \
            --path "$path" --title "$title" --json \
            | jq -r '.workspaceId // empty')"
    fi
    [[ -n "$id" ]] || return 1
    printf '%s' "$id"
}

# The name the app asks for as "Host": the MagicDNS name, else the tailnet IP.
paseo_pair_host() {
    local h
    h="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || true)"
    [[ -n "$h" ]] || h="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    printf '%s' "$h"
}

# Print the three values the app asks for. printf only, never log().
paseo_print_pairing() {
    local host="$1" password
    password="$(sed -n 's/^PASEO_PASSWORD=//p' "$PASEO_ENV_FILE")"
    printf 'In the Paseo app, open Settings, then Add host,\nthen choose Direct connection and enter:\n\n'
    printf '  Host:      %s\n' "$host"
    printf '  Port:      %s\n' "$PASEO_PORT"
    printf '  Password:\n  %s\n\n' "$password"
    printf 'Leave "Use SSL" off. Your phone needs Tailscale\nswitched on (you set it up earlier).\n\n'
}

# "paseo" when this CLI gets the Paseo interface, "ssh" when it can only be
# reached over SSH. Skills and /etc/profile.d read this instead of testing a
# CLI name, so paseo_supports_cli stays the only place that decides.
paseo_mode() {
    if paseo_supports_cli "$1"; then printf 'paseo'; else printf 'ssh'; fi
}

# paseo_ssh_fallback_text <cli> <user> <host> — the way in that needs no Paseo.
paseo_ssh_fallback_text() {
    printf 'You can always work over SSH, with no app:\n\nssh %s@%s\n\nThen run:  %s\n' \
        "$2" "$3" "$(ai_cli_command "$1")"
}

# The last text of the wizard.
# paseo_finale <cli> <user> <host> <paired:0|1>
paseo_finale() {
    local cli="$1" user="$2" host="$3" paired="$4"
    printf '%s is logged in and your first agent is running.\n\n' "$(ai_cli_display_name "$cli")"
    if [[ "$paired" == "1" ]]; then
        cat <<EOF
Open the Paseo app on your phone. You will find the workspace
"${PASEO_WORKSPACE_NAME}" and the agent "${PASEO_AGENT_TITLE}".

The /tutorial guide is already running. It will help you create your first project.
EOF
    else
        cat <<EOF
Your phone is not paired yet. When you are ready, run this on the box:

${PASEO_PAIR_LATER_CMD}

$(paseo_ssh_fallback_text "$cli" "$user" "$host")
EOF
    fi
}

# ---------------------------------------------------------------------------
# TODO(2026-10-31): remove after 2027-04-30 (FEAT-041 D5): this whole block and
# its tmux_done read, once no box can still carry the old layout.
# Migration of a box installed with the tmux layout (FEAT-035 R8, D6).
# ---------------------------------------------------------------------------

# bib_paseo_migrate <user> <user_home>
# Called at the end of install/46-paseo.sh, i.e. on every `biab update` (which
# never runs the wizard). Converges a tmux-layout box to Paseo:
#   1. one Paseo workspace for ~/ai-platform and for each ~/ai-platform/projects/*/
#      (idempotent by path, titles "BIAB · <name>");
#   2. no tutorial agent;
#   3. the first-boot trigger, if this box has one (ISO installs only), is
#      refreshed so it no longer auto-attaches a tmux session (this refresh is
#      where an old ISO box loses the auto-attach);
#   4. tmux sessions, ~/.tmux.conf and every project directory are untouched
#      (R10: nothing here removes or rewrites them, and the tmux package stays);
#   5. paseo_done + .paseo_migrated are written LAST, so any failure leaves the
#      next update to retry. Nothing is ever deleted.
# Gated on paseo_supports_cli, which is true for every CLI that has Paseo.
# Needs lib/common.sh and lib/ai-cli.sh sourced. Returns 0 when there is
# nothing to do or when it converged; 1 when a step failed (retry next update).
bib_paseo_migrate() {
    local user="$1" user_home="$2"
    # New installs never write tmux_done; only a box installed before FEAT-041 carries it.
    phase_is_done "tmux_done" || return 0
    phase_is_done "paseo_done" && return 0
    local cli
    cli="$(state_get '.ai_cli')"
    : "${cli:=claude}"
    if ! paseo_supports_cli "$cli"; then
        log "paseo-migrate: $cli is not set up for Paseo on this box; leaving it on its SSH-session interface"
        return 0
    fi

    local home root dir name failed=0
    home="$(paseo_home_for "$user_home")"
    root="${user_home}/ai-platform"
    if ! paseo_wait_ready "$user" "$home"; then
        warn "paseo-migrate: the Paseo daemon is not answering; will retry on the next 'biab update'"
        return 1
    fi
    if [[ -d "$root" ]]; then
        paseo_ensure_workspace "$user" "$home" "$root" >/dev/null \
            || { warn "paseo-migrate: could not register $root"; failed=1; }
        shopt -s nullglob
        for dir in "$root"/projects/*/; do
            dir="${dir%/}"
            name="$(basename "$dir")"
            paseo_ensure_workspace "$user" "$home" "$dir" "${PASEO_TITLE_PREFIX}${name}" >/dev/null \
                || { warn "paseo-migrate: could not register $dir"; failed=1; }
        done
        shopt -u nullglob
    fi
    if [[ "$failed" -ne 0 ]]; then
        warn "paseo-migrate: some projects were not registered; nothing was removed, will retry on the next 'biab update'"
        return 1
    fi

    # The first-boot trigger exists only on ISO installs; refresh it, never create it.
    local trigger="${PASEO_PREFIX}/etc/profile.d/biab-firstboot.sh"
    if [[ -e "$trigger" ]]; then
        install -m 0644 "${_PASEO_LIB_DIR}/../profile.d/biab-firstboot.sh" "$trigger"
    fi

    phase_done "paseo_done"
    state_set ".paseo_migrated" "true"
    # The two messages below talk to a box that had the tmux layout; a new box never reaches them.
    log "paseo-migrate: done; projects are Paseo workspaces, tmux left as it was"

    local host
    # `biab update` may be run by an agent whose output lands in a transcript,
    # so the phone password is NEVER printed here; only how to get it.
    printf '\nYour projects are now in the Paseo app (workspaces named "%s...").\n' "$PASEO_TITLE_PREFIX"
    printf 'Your tmux sessions were not touched.\n\n'
    printf 'To pair your phone, run this in a terminal:  %s\n\n' "$PASEO_PAIR_LATER_CMD"
}
