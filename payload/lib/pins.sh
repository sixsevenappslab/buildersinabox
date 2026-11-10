#!/usr/bin/env bash
# Pins for the third-party tools BIAB installs (FEAT-038).
#
# One place per tool:
#   Claude Code, Codex  payload/pins/<tool>/{package.json,package-lock.json}
#   Paseo               payload/paseo/{package.json,package-lock.json} + PASEO_PIN
#   agy                 AGY_VERSION + AGY_SHA256_LINUX_X64 in install/41-*.sh
#
# This file is sourced (by install/40, 42, and by tools/bump-pins.sh). It sets no
# shell options of its own. The pure helpers (pin_is_stable, the upstream lookups)
# need nothing else; the install helpers call log/warn/die from lib/common.sh at
# call time. "What counts as a stable release" lives here once, so the weekly bot
# and `biab update --latest` cannot disagree about it.

_PINS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test seams, like PASEO_PREFIX: an empty prefix is the real filesystem.
PINS_PREFIX="${PINS_PREFIX:-}"
PINS_SRC_DIR="${PINS_SRC_DIR:-${_PINS_LIB_DIR}/../pins}"
PINS_TOOLS_DIR="${PINS_PREFIX}/opt/buildersinabox/tools"
PINS_BIN_DIR="${PINS_PREFIX}/usr/local/bin"

# A version is stable only when it is exactly MAJOR.MINOR.PATCH. This is a rule on
# the version string, not on the dist-tag: a maintainer can point `latest` at
# 1.0.0-rc.1, and Paseo already ships a `beta` tag next to `latest`.
PINS_STABLE_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

PINS_AGY_REPO="google-antigravity/antigravity-cli"
PINS_AGY_ASSET="agy_cli_linux_x64.tar.gz"

pin_is_stable() {
    [[ "${1:-}" =~ $PINS_STABLE_RE ]]
}

# Versions are compared with sort -V so "0.9.0" < "0.12.0".
pin_version_gt() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

# pin_npm_pkg_version <dir> <pkg> : the exact version package.json pins.
pin_npm_pkg_version() {
    local v
    v="$(jq -er --arg p "$2" '.dependencies[$p]' "$1/package.json" 2>/dev/null)" || return 1
    pin_is_stable "$v" || return 1
    printf '%s\n' "$v"
}

# pin_probe_version <binary> : first semver `<binary> --version` prints (empty if none).
pin_probe_version() {
    "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true
}

# pin_run_isolated <command...> : runs code that was DOWNLOADED (a new Paseo tree, an agy binary) with
# nothing of the CI step around it. `env -u GH_TOKEN` is not enough: GITHUB_ENV, GITHUB_PATH, GITHUB_OUTPUT
# and GITHUB_STATE stay writable, so a hostile tool could plant BASH_ENV/LD_PRELOAD/PATH for the later steps
# that DO carry the token. `env -i` leaves PATH, a throwaway HOME and display basics, no GITHUB_*, RUNNER_*,
# ACTIONS_* or secret-like variable.
pin_run_isolated() {
    local h rc=0
    h="$(mktemp -d)" || return 1
    env -i PATH="$PATH" HOME="$h" TMPDIR="$h" LANG=C.UTF-8 COLUMNS=80 NO_COLOR=1 "$@" || rc=$?
    rm -rf -- "${h:?}"
    return "$rc"
}

# --- Upstream lookups (shared by the bot and `biab update --latest`) -----------
# Only the small `/<pkg>/latest` document is fetched. The full packument of some
# packages is ~18 MB and its dist-tags hold dozens of alpha/release tags.
#   rc 1  unreachable or malformed answer
#   rc 2  the answer is not a stable version (never followed)
pin_npm_latest_version() {
    local pkg="$1" url body ver
    url="${BUMP_NPM_REGISTRY:-https://registry.npmjs.org}/${pkg//\//%2F}/latest"
    body="$(curl -fsS --max-time 30 "$url" 2>/dev/null)" || return 1
    ver="$(jq -er '.version' <<<"$body" 2>/dev/null)" || return 1
    pin_is_stable "$ver" || return 2
    printf '%s\n' "$ver"
}

# pin_npm_repo_url <pkg> : the https GitHub URL from the package's own
# `repository` field, empty when it has none (the caller falls back to the npm page).
pin_npm_repo_url() {
    local pkg="$1" url body repo
    url="${BUMP_NPM_REGISTRY:-https://registry.npmjs.org}/${pkg//\//%2F}/latest"
    body="$(curl -fsS --max-time 30 "$url" 2>/dev/null)" || return 0
    repo="$(jq -r '(.repository // empty) | if type == "object" then .url else . end // empty' <<<"$body" 2>/dev/null)" || return 0
    repo="${repo#git+}"; repo="${repo%.git}"
    # Only a plain https://github.com/<owner>/<repo> is trusted as a link in a pull request body.
    [[ "$repo" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] && printf '%s\n' "$repo"
    return 0
}

# pin_agy_latest : prints "<version> <sha256-digest> <asset-url> <release-url>".
# The digest is the server-side `digest` GitHub publishes next to each asset.
#   rc 1  unreachable, malformed, or the release is a draft/pre-release
#   rc 2  the release is not a stable version
#   rc 3  the x64 asset has no published digest (the bot then does not bump agy)
pin_agy_latest() {
    local url body tag draft pre digest asset_url html
    url="${BUMP_GH_API:-https://api.github.com}/repos/${PINS_AGY_REPO}/releases/latest"
    body="$(curl -fsS --max-time 30 -H 'Accept: application/vnd.github+json' "$url" 2>/dev/null)" || return 1
    tag="$(jq -er '.tag_name' <<<"$body" 2>/dev/null)" || return 1
    # No -e here: `jq -e` exits 1 on a false value, which is the answer we want.
    draft="$(jq -r '.draft' <<<"$body" 2>/dev/null)" || return 1
    pre="$(jq -r '.prerelease' <<<"$body" 2>/dev/null)" || return 1
    [[ "$draft" == "false" && "$pre" == "false" ]] || return 1
    tag="${tag#v}"
    pin_is_stable "$tag" || return 2
    asset_url="$(jq -er --arg a "$PINS_AGY_ASSET" '.assets[] | select(.name == $a) | .browser_download_url' <<<"$body" 2>/dev/null)" || return 1
    # The asset must come from the project's own release downloads, whatever the API says.
    [[ "$asset_url" == "${BUMP_AGY_DL_PREFIX:-https://github.com/${PINS_AGY_REPO}/releases/download/}"* ]] || return 1
    html="$(jq -r '.html_url // empty' <<<"$body" 2>/dev/null)" || html=""
    [[ "$html" == "https://github.com/${PINS_AGY_REPO}/releases/"* ]] || html=""
    digest="$(jq -r --arg a "$PINS_AGY_ASSET" '.assets[] | select(.name == $a) | .digest // empty' <<<"$body" 2>/dev/null)" || digest=""
    digest="${digest#sha256:}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 3
    printf '%s %s %s %s\n' "$tag" "$digest" "$asset_url" "${html:-https://github.com/${PINS_AGY_REPO}/releases/tag/${tag}}"
}

# --- Where each npm tool's binary lives in its installed tree -------------------
# Codex's wrapper script finds its platform package by itself, so scripts are not
# needed. Claude Code's `bin` is a placeholder that its postinstall script replaces
# with the platform binary; installs run with --ignore-scripts (as root, third-party
# lifecycle scripts do not run), so the platform binary, which is a locked
# optionalDependency with its own integrity hash, is used directly (SPIKE T1).
pin_bin_codex() { printf '%s/node_modules/.bin/codex\n' "$1"; }
pin_bin_paseo() { printf '%s/node_modules/.bin/paseo\n' "$1"; }

pin_bin_claude() {
    local arch plat
    arch="${PINS_UNAME_M:-$(uname -m)}"
    case "$arch" in
        x86_64|amd64)  plat="linux-x64" ;;
        aarch64|arm64) plat="linux-arm64" ;;
        *) return 1 ;;
    esac
    printf '%s/node_modules/@anthropic-ai/claude-code-%s/claude\n' "$1" "$plat"
}

# --- Old `npm install -g` copies -------------------------------------------------
# Before FEAT-038, 40/42 ran `npm install -g`. That copy would shadow nothing on
# the default PATH (/usr/local/bin comes first) but would stay as a second,
# unpinned, never-updated copy. It is removed only when it is provably BIAB's.
# state.json never recorded that, so the record is the legacy installer's own log
# line, which it wrote only when it actually installed (the skip path logged
# something else). A copy of the user's own is left alone and reported.
pin_global_copy_dirs() {
    printf '%s\n' "${PINS_PREFIX}/usr/lib/node_modules/$1" "${PINS_PREFIX}/usr/local/lib/node_modules/$1"
}

pin_legacy_install_logged() { # <pkg>
    [[ -r "${BIB_LOG_FILE:-}" ]] || return 1
    grep -qF ": npm install -g $1" "$BIB_LOG_FILE" 2>/dev/null
}

pin_retire_global_copy() { # <log-tag> <pkg> <cmd>
    local tag="$1" pkg="$2" d found=""
    while IFS= read -r d; do
        if [[ -e "$d" ]]; then found="$d"; break; fi
    done < <(pin_global_copy_dirs "$pkg")
    [[ -n "$found" ]] || return 0
    if ! pin_legacy_install_logged "$pkg"; then
        warn "${tag}: a copy of ${pkg} you installed yourself is at ${found}; leaving it alone. The pinned copy at ${PINS_BIN_DIR#"$PINS_PREFIX"}/${3} is the one BIAB uses."
        return 0
    fi
    log "${tag}: removing the old global copy of ${pkg} (${found}) so the pinned copy is the only one"
    npm uninstall -g "$pkg" >/dev/null 2>&1 || true
    if [[ -e "$found" ]]; then
        warn "${tag}: could not remove ${found}; the pinned copy still wins on PATH, remove the old one by hand with: sudo npm uninstall -g ${pkg}"
    fi
}

# pin_install_npm_tool <log-tag> <tool-dir> <npm-pkg> <command> <bin-function>
#
# Installs the tool at the exact version its committed package.json pins, with
# `npm ci` from the committed lockfile, into /opt/buildersinabox/tools/<tool>/<ver>,
# staged then moved so a failed install leaves the previous version running.
# "Installed version == pin" is the only skip condition: a different installed
# version (newer or older) is replaced, because the point is that the pins were
# tested together.
pin_install_npm_tool() {
    local tag="$1" tool="$2" pkg="$3" cmd="$4" binfn="$5"
    local src="${PINS_SRC_DIR}/${tool}"
    local root="${PINS_TOOLS_DIR}/${tool}" pin tree current staging bin

    [[ -f "${src}/package.json" && -f "${src}/package-lock.json" ]] \
        || die "${tag}: ${src}/package.json or package-lock.json is missing; refusing to install without the committed lockfile"
    pin="$(pin_npm_pkg_version "$src" "$pkg")" \
        || die "${tag}: ${src}/package.json does not pin ${pkg} to an exact stable version"
    command -v npm >/dev/null 2>&1 \
        || die "${tag}: npm is required (install/00-base.sh should have provided it)"

    # `biab update --latest`: the newest STABLE upstream version replaces the pin and
    # the repo lockfile is not used. If upstream cannot be read, or its latest is not
    # a stable version, the pin is installed instead and the user is told.
    local latest_mode=0 lrc=0
    if [[ "${BIB_PINS_MODE:-pinned}" == "latest" ]]; then
        pin="$(pin_npm_latest_version "$pkg")" || lrc=$?
        if [[ "$lrc" -eq 0 ]]; then
            latest_mode=1
        else
            pin="$(pin_npm_pkg_version "$src" "$pkg")"
            warn "${tag}: --latest could not get a stable ${pkg} version from npm (rc ${lrc}); installing the pinned ${pin} instead"
        fi
    fi

    tree="${root}/${pin}"
    current="${root}/current"
    bin="$("$binfn" "$current")" || die "${tag}: unsupported CPU architecture for ${tool}"

    if [[ "$(readlink "$current" 2>/dev/null || true)" == "$tree" && "$(pin_probe_version "$bin")" == "$pin" ]]; then
        log "${tag}: ${cmd} ${pin} already installed, skipping npm ci"
    else
        staging="${tree}.partial"
        rm -rf -- "$staging"
        mkdir -p "$staging" && chmod 0755 "${PINS_TOOLS_DIR}" "$root" "$staging"
        # --ignore-scripts: this runs as root and the tree's lifecycle scripts add
        # nothing (see pin_bin_claude). Not running third-party scripts as root is
        # the safer default.
        if [[ "$latest_mode" -eq 1 ]]; then
            jq -n --arg p "$pkg" --arg v "$pin" '{name:"biab-latest", version:"0.0.0", private:true, dependencies:{($p):$v}}' > "${staging}/package.json"
            log "${tag}: --latest: npm install for ${pkg}@${pin} (no lockfile, untested combination)"
            if ! (cd "$staging" && npm install --omit=dev --no-audit --no-fund --ignore-scripts >/dev/null 2>&1); then
                rm -rf -- "$staging"
                die "${tag}: 'npm install' failed for ${pkg}@${pin}. Check the network and re-run 'biab update'. The previous version, if any, is untouched."
            fi
        else
            cp "${src}/package.json" "${src}/package-lock.json" "$staging/"
            log "${tag}: npm ci for ${pkg}@${pin}"
            if ! (cd "$staging" && npm ci --omit=dev --no-audit --no-fund --ignore-scripts >/dev/null 2>&1); then
                rm -rf -- "$staging"
                die "${tag}: 'npm ci' failed for ${pkg}@${pin}. Check the network and re-run 'biab update'. The previous version, if any, is untouched."
            fi
        fi
        if [[ "$(pin_probe_version "$("$binfn" "$staging")")" != "$pin" ]]; then
            rm -rf -- "$staging"
            die "${tag}: the installed tree does not report ${cmd} ${pin}; refusing to use it. The previous version, if any, is untouched."
        fi
        # Same version already there (a corrupt or stale tree)? Move it aside and delete it only
        # after the new one is in place. Not atomic: there is a minimal window (microseconds) between the two mv
        # calls, and only when the same version is repaired; a different version never touches the old tree.
        rm -rf -- "${tree}.old"
        if [[ -e "$tree" ]]; then mv "$tree" "${tree}.old"; fi
        if ! mv "$staging" "$tree"; then
            [[ ! -e "${tree}.old" ]] || mv "${tree}.old" "$tree"
            die "${tag}: could not move the new ${cmd} ${pin} tree into place; the previous version is back"
        fi
        rm -rf -- "${tree}.old"
    fi

    ln -sfn "$tree" "$current"
    # Retire BIAB's old global copy BEFORE linking: with the npm prefix /usr/local its bin is in
    # the same directory as ours, and `npm uninstall -g` deletes a bin by name.
    pin_retire_global_copy "$tag" "$pkg" "$cmd"
    pin_link_command "$tag" "$cmd" "$("$binfn" "$current")" "$pkg"
    pin_prune_old_trees "$root" "$tree"
}

# pin_link_command <log-tag> <cmd> <target> <npm-pkg>: /usr/local/bin/<cmd> -> target.
# Replaces a link that is ours (into our tools tree) or the old `npm -g` link of THIS
# package when BIAB's own install record says it made it. Any other file or link is the
# user's: it is left and reported, never repointed to another version.
pin_link_command() {
    local tag="$1" cmd="$2" target="$3" pkg="$4" link existing
    link="${PINS_BIN_DIR}/${cmd}"
    mkdir -p "$PINS_BIN_DIR"
    if [[ -L "$link" ]]; then
        existing="$(readlink "$link")"
        case "$existing" in
            */opt/buildersinabox/tools/*)
                ln -sfn "$target" "$link"; return 0 ;;
            */node_modules/"${pkg}"/*)
                if pin_legacy_install_logged "$pkg"; then ln -sfn "$target" "$link"; return 0; fi ;;
        esac
        warn "${tag}: ${link} is a link to ${existing}, which is not BIAB's; leaving it. The pinned ${cmd} is at ${target}"
        return 0
    fi
    if [[ -e "$link" ]]; then
        warn "${tag}: ${link} exists and is not BIAB's; leaving it. The pinned ${cmd} is at ${target}"
        return 0
    fi
    ln -s "$target" "$link"
}

# Older versions, and a .partial from an interrupted install, are dead weight once
# `current` points at the pinned tree. Only directories named like a version go.
pin_prune_old_trees() { # <root> <keep>
    local d
    for d in "$1"/*; do
        [[ -d "$d" && ! -L "$d" && "$d" != "$2" ]] || continue
        case "${d##*/}" in
            *.partial|*.old) rm -rf -- "$d" ;;
            *) pin_is_stable "${d##*/}" && rm -rf -- "$d" ;;
        esac
    done
    return 0
}

# --- `biab update --latest` and the off-pin record (FEAT-038 R5, R6) ---------------
PINS_LATEST_WARNING="WARNING: --latest installs the newest upstream version of Claude Code, Codex, Paseo and agy, ignoring the versions Builders in a Box tested together. This combination is untested and unsupported. Run 'biab update' to return to the tested versions."

bib_pins_latest_warning() { printf '%s\n' "$PINS_LATEST_WARNING"; }

# bib_pins_offpin_line <since> : the one line every diagnostic surface prints.
bib_pins_offpin_line() { printf 'OFF-PIN since %s: untested versions. Return with: biab update\n' "$1"; }

# bib_pins_record : writes `.pins` to state.json at the end of the stack phase.
# pinned -> {mode, release, updated}; latest -> {mode, since, versions}. `since` is
# kept across repeated --latest runs so it says when the box LEFT the pins.
bib_pins_record() {
    local now mode release since versions v c
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mode="${BIB_PINS_MODE:-pinned}"
    if [[ "$mode" == "latest" ]]; then
        since="$(state_get '.pins | select(.mode == "latest") | .since' 2>/dev/null || true)"
        : "${since:=$now}"
        versions='{}'
        for c in claude codex paseo agy; do
            v="$(pin_probe_version "${PINS_BIN_DIR}/${c}")"
            [[ -n "$v" ]] && versions="$(jq -c --arg k "$c" --arg v "$v" '. + {($k): $v}' <<<"$versions")"
        done
        state_set '.pins' "$(jq -nc --arg s "$since" --argjson v "$versions" '{mode:"latest", since:$s, versions:$v}')"
        bib_pins_offpin_line "$since"
    else
        release="$(git -C "${BIB_INSTALL_ROOT:-${_PINS_LIB_DIR}/../..}" describe --tags --always 2>/dev/null || echo unknown)"
        state_set '.pins' "$(jq -nc --arg r "$release" --arg u "$now" '{mode:"pinned", release:$r, updated:$u}')"
    fi
}

# bib_pins_begin_latest : called when a --latest run STARTS. The box is off-pin from the first
# installer on, so the record exists before any of them can die; bib_pins_record completes
# `versions` at the end. `since` and earlier versions survive repeated --latest runs.
bib_pins_begin_latest() {
    local now since versions
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    since="$(state_get '.pins | select(.mode == "latest") | .since' 2>/dev/null || true)"
    : "${since:=$now}"
    versions="$(state_get '.pins | select(.mode == "latest") | .versions' 2>/dev/null || true)"
    [[ -n "$versions" ]] || versions='{}'
    state_set '.pins' "$(jq -nc --arg s "$since" --argjson v "$versions" '{mode:"latest", since:$s, versions:$v}')"
}

# --- Opt-in auto-update timer (FEAT-038 R7, R12) -----------------------------------
# Never enabled by an install or an update, and never passes --latest: a timer that
# moved a box off-pin unattended would break "unsupported means you asked for it".
PINS_UNIT_DIR="${PINS_PREFIX}/etc/systemd/system"
PINS_TIMER_NAME="biab-update.timer"
PINS_SERVICE_NAME="biab-update.service"
PINS_SCHEDULE_HELP="daily, weekly, monthly, a weekday and time like 'Mon 03:30', or every day at a time like '*-*-* 03:30'"

pin_schedule_valid() {
    local s="${1:-}"
    [[ "$s" =~ ^(daily|weekly|monthly)$ ]] && return 0
    [[ "$s" =~ ^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\ ([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && return 0
    [[ "$s" =~ ^\*-\*-\*\ ([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

pin_autoupdate_render_service() {
    cat <<'UNIT'
[Unit]
Description=Builders in a Box: update to the tested versions
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/biab update
UNIT
}

pin_autoupdate_render_timer() { # <schedule>
    cat <<UNIT
[Unit]
Description=Builders in a Box: scheduled update (opt-in, 'biab auto-update off' removes it)

[Timer]
OnCalendar=$1
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
UNIT
}

# pin_autoupdate <on|off|status> [schedule]
pin_autoupdate() {
    local action="${1:-}" sched="${2-}" tmp
    local svc="${PINS_UNIT_DIR}/${PINS_SERVICE_NAME}" tim="${PINS_UNIT_DIR}/${PINS_TIMER_NAME}"
    case "$action" in
        on)
            [[ -n "$sched" ]] || sched="weekly"
            if ! pin_schedule_valid "$sched"; then
                warn "auto-update: '${sched}' is not a valid schedule. Use ${PINS_SCHEDULE_HELP}. Nothing was changed."
                return 2
            fi
            mkdir -p "$PINS_UNIT_DIR"
            tmp="$(mktemp "${PINS_UNIT_DIR}/.biab-update.XXXXXX")"
            pin_autoupdate_render_service > "$tmp" && mv "$tmp" "$svc" && chmod 0644 "$svc"
            tmp="$(mktemp "${PINS_UNIT_DIR}/.biab-update.XXXXXX")"
            pin_autoupdate_render_timer "$sched" > "$tmp" && mv "$tmp" "$tim" && chmod 0644 "$tim"
            systemctl daemon-reload
            systemctl enable --now "$PINS_TIMER_NAME" >/dev/null
            log "auto-update: on (${sched}). It runs 'biab update', never '--latest'. Turn it off with: biab auto-update off"
            ;;
        off)
            if [[ ! -e "$tim" && ! -e "$svc" ]]; then
                log "auto-update: already off, nothing to remove"
                return 0
            fi
            # Disable before the unit file goes, or systemd keeps a dangling enablement.
            systemctl disable --now "$PINS_TIMER_NAME" >/dev/null 2>&1 || true
            rm -f -- "$tim" "$svc"
            systemctl daemon-reload
            log "auto-update: off"
            ;;
        status)
            if [[ -e "$tim" ]]; then
                log "auto-update: on, schedule $(sed -n 's/^OnCalendar=//p' "$tim")"
                systemctl list-timers "$PINS_TIMER_NAME" --no-pager 2>/dev/null || true
            else
                log "auto-update: off (turn it on with: biab auto-update on [weekly])"
            fi
            ;;
        *)
            warn "usage: biab auto-update on [schedule] | off | status   (schedule: ${PINS_SCHEDULE_HELP}; default weekly)"
            return 2
            ;;
    esac
}
