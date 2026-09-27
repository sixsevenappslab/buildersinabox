#!/usr/bin/env bash
# Builders in a Box browser pack — installer (FEAT-017). OPT-IN: this only
# runs when the operator explicitly asks for it (`biab pack add browser`).
# Nothing in payload/install.sh or the skills manifest calls this script.
#
# Idempotent. Installs:
#   - a dedicated system user `biab-browser` (nologin, no sudo)
#   - a pinned Playwright + full Chromium engine under its home (full
#     Chromium, not chromium-headless-shell — see the note above the
#     chromium install step below for why)
#   - /usr/local/bin/biab-browse (the agent-facing CLI)
#   - the `browser` skill, symlinked the same way core skills are
#   - a narrowly-scoped NOPASSWD sudoers rule limited to biab-browse itself
#     (needed so an agent invoking it repeatedly never blocks on a password
#     prompt it cannot answer — see bin/biab-browse's header comment)
#
# Flags:
#   --with-xvfb              also pre-install the --headful-xvfb fallback's
#                             xvfb dependency (the engine itself is the same
#                             full Chromium installed above). Optional; the
#                             fallback lazily installs itself on first use
#                             otherwise.
#   --ensure-xvfb-fallback    internal — invoked by biab-browse the first
#                             time --headful-xvfb is used. Idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "${SCRIPT_DIR}/../../lib/common.sh"
# shellcheck source=../../lib/ai-cli.sh
source "${SCRIPT_DIR}/../../lib/ai-cli.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

WITH_XVFB=0
ENSURE_XVFB_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --with-xvfb)           WITH_XVFB=1 ;;
        --ensure-xvfb-fallback) ENSURE_XVFB_ONLY=1 ;;
        *) die "browser pack install: unknown argument: $arg" ;;
    esac
done

# Pinned exact version — keep in sync with driver/package.json.
PLAYWRIGHT_VERSION="1.61.1"

# ---------------------------------------------------------------------------
# install_xvfb_fallback — lazily (or eagerly, with --with-xvfb) install the
# --headful-xvfb path's only extra dependency: xvfb (apt). The engine itself
# (full Chromium + its bundled setuid sandbox helper) is now the *default*
# engine too (see the chromium install step below — this changed 2026-07-12,
# FEAT-017 §2.9 sandbox-finding resolution), so --headful-xvfb reuses the
# exact same binary and sandbox helper already installed under
# $BROWSER_CACHE_DIR instead of downloading a second copy of Chromium.
# Idempotent: a marker file skips the work on repeat calls.
# ---------------------------------------------------------------------------
install_xvfb_fallback() {
    local marker="${BROWSER_HOME}/.xvfb-fallback-installed"
    if [[ -f "$marker" ]]; then
        log "browser pack: --headful-xvfb fallback already installed, skipping"
        return 0
    fi
    log "browser pack: installing --headful-xvfb fallback (xvfb only — reuses the default Chromium engine + sandbox helper under ${BROWSER_CACHE_DIR})"
    apt_update_once
    # Often a no-op by this point: `install-deps chromium` (main install,
    # above) already pulls xvfb in as one of full Chromium's own listed OS
    # dependencies on Ubuntu 24.04. apt_install is idempotent either way —
    # kept explicit so this fallback doesn't silently depend on that detail.
    apt_install xvfb

    touch "$marker"
    chown "${BROWSER_USER}:${BROWSER_USER}" "$marker"
    log "browser pack: --headful-xvfb fallback ready"
}

if [[ "$ENSURE_XVFB_ONLY" -eq 1 ]]; then
    install_xvfb_fallback
    exit 0
fi

# ---------------------------------------------------------------------------
# Dedicated system user (idempotent). nologin, no sudo, own home — never the
# operator, never root.
# ---------------------------------------------------------------------------
if ! getent passwd "$BROWSER_USER" >/dev/null; then
    useradd --system --home-dir "$BROWSER_HOME" --create-home \
        --shell /usr/sbin/nologin "$BROWSER_USER"
    log "browser pack: created system user $BROWSER_USER"
else
    log "browser pack: system user $BROWSER_USER already exists, skipping"
fi
install -d -o "$BROWSER_USER" -g "$BROWSER_USER" -m 0750 "$BROWSER_HOME"
install -d -o "$BROWSER_USER" -g "$BROWSER_USER" -m 0750 "$BROWSER_PROFILES_DIR"
install -d -o "$BROWSER_USER" -g "$BROWSER_USER" -m 0750 "$BROWSER_OUT_DIR"

# ---------------------------------------------------------------------------
# Node project + pinned Playwright + full Chromium (NOT chromium-headless-
# shell, NOT the snap). FEAT-017's spike originally picked headless-shell for
# its smaller footprint (~250-300MB vs ~646MB), but real testing on Ubuntu
# 24.04 found headless-shell does not ship Chromium's setuid sandbox helper
# — and this box's AppArmor (kernel.apparmor_restrict_unprivileged_userns=1,
# enforced) blocks the sandbox from initialising without it, so the default
# path aborted (fail-closed, by design — see browse.mjs) on every real box.
# Full Chromium ships its own setuid sandbox helper (chrome_sandbox, enabled
# below), so it works out-of-the-box with no escape hatch. Decided by Jesús
# 2026-07-12 (FEAT-017 §2.9 addendum): accept the larger footprint (~646MB)
# to keep the "never --no-sandbox by default" boundary intact.
# ---------------------------------------------------------------------------
mkdir -p "$BROWSER_DRIVER_DIR"
cp "${SCRIPT_DIR}/driver/package.json" "${BROWSER_DRIVER_DIR}/package.json"
cp "${SCRIPT_DIR}/driver/browse.mjs" "${BROWSER_DRIVER_DIR}/browse.mjs"
chown -R "${BROWSER_USER}:${BROWSER_USER}" "$BROWSER_DRIVER_DIR"

log "browser pack: npm install (playwright-core@${PLAYWRIGHT_VERSION}) under ${BROWSER_DRIVER_DIR}"
sudo -u "$BROWSER_USER" env HOME="$BROWSER_HOME" npm --prefix "$BROWSER_DRIVER_DIR" install --no-audit --no-fund \
    || die "browser pack: npm install failed"

# Full Chromium (unlike chromium-headless-shell) is linked against the
# desktop shared-library stack (GTK/ATK/X11/font libs) even when only ever
# run with --headless=new — found via real VM testing on a bare Ubuntu
# 24.04 server (no desktop packages): `chrome` failed to start at all with
# "error while loading shared libraries: libatk-1.0.so.0". `install-deps`
# is Playwright's own supported way to pull in the exact package set for
# the pinned Chromium build; must run as root (apt), unlike the download
# step above which runs unprivileged as $BROWSER_USER.
log "browser pack: installing Chromium's OS-level shared-library dependencies (apt)"
apt_update_once
DEBIAN_FRONTEND=noninteractive node "${BROWSER_DRIVER_DIR}/node_modules/playwright-core/cli.js" install-deps chromium \
    || die "browser pack: failed to install Chromium's OS dependencies"

mkdir -p "$BROWSER_CACHE_DIR"
chown -R "${BROWSER_USER}:${BROWSER_USER}" "${BROWSER_HOME}/.cache"
log "browser pack: installing full Chromium (PLAYWRIGHT_BROWSERS_PATH=${BROWSER_CACHE_DIR})"
sudo -u "$BROWSER_USER" env HOME="$BROWSER_HOME" PLAYWRIGHT_BROWSERS_PATH="$BROWSER_CACHE_DIR" \
    node "${BROWSER_DRIVER_DIR}/node_modules/playwright-core/cli.js" install chromium \
    || die "browser pack: failed to install chromium"

# Enable Chromium's own bundled setuid sandbox helper (chrome_sandbox):
# chown root + chmod 4755, scoped to this one binary. This is what actually
# lets the sandbox initialise on Ubuntu 24.04's AppArmor-restricted userns —
# no /etc/apparmor.d/ changes, no global sysctl (FEAT-017 §2.9 preference).
sandbox_helper="$(find "$BROWSER_CACHE_DIR" -maxdepth 3 -type f -name chrome_sandbox 2>/dev/null | head -1)"
if [[ -n "$sandbox_helper" ]]; then
    chown root:root "$sandbox_helper"
    chmod 4755 "$sandbox_helper"
    log "browser pack: enabled setuid sandbox helper at $sandbox_helper"
else
    warn "browser pack: chrome_sandbox helper not found in the Chromium download — the default engine will fail closed (exit 3) if the sandbox can't start"
fi

cache_size="$(du -sh "$BROWSER_CACHE_DIR" 2>/dev/null | cut -f1 || echo unknown)"
log "browser pack: engine cache size: ${cache_size} (full Chromium, ~646MB expected)"

# ---------------------------------------------------------------------------
# CLI on PATH.
# ---------------------------------------------------------------------------
install -o root -g root -m 0755 "${SCRIPT_DIR}/bin/biab-browse" "$BROWSER_BIN_TARGET"
log "browser pack: installed $BROWSER_BIN_TARGET"

# ---------------------------------------------------------------------------
# Scoped NOPASSWD sudoers rule, limited to this exact binary path — see
# bin/biab-browse's header comment for why this is needed. `visudo -c`
# validates the file before it's trusted; a bad file is removed rather than
# left in a state that could break sudo system-wide.
# ---------------------------------------------------------------------------
tmp_sudoers="$(mktemp)"
printf '# Builders in a Box browser pack (FEAT-017) — opt-in, removed by `biab pack remove browser`.\n' > "$tmp_sudoers"
printf '# Scoped to this exact binary only: lets an operator (sudo group) invoke\n' >> "$tmp_sudoers"
printf '# biab-browse without a password each time (an agent cannot type one).\n' >> "$tmp_sudoers"
printf '# Grants no privilege beyond what sudo-group members already have.\n' >> "$tmp_sudoers"
printf '%%sudo ALL=(root) NOPASSWD: %s\n' "$BROWSER_BIN_TARGET" >> "$tmp_sudoers"
# sudo's default env_reset strips the caller's environment on elevation.
# Keep exactly the two operator-facing overrides biab-browse reads, scoped
# to this one command only (Defaults! applies only when running it) — the
# explicit, logged BIAB_UNSAFE_NO_SANDBOX opt-out (FEAT-017 §1 Boundaries)
# would otherwise be silently unreachable through the CLI. Note that the env
# var alone is NOT sufficient to actually disable the sandbox: biab-browse
# additionally requires a human-created sentinel file
# (BROWSER_UNSAFE_SANDBOX_SENTINEL in lib.sh, root-owned, mode 0600) before
# honouring it — see validate_unsafe_sandbox_gate() in lib.sh. That keeps
# sandbox relaxation an actual "Ask First" human decision even though the
# env var itself is reachable by any process (including an agent session).
printf 'Defaults!%s env_keep += "BIAB_UNSAFE_NO_SANDBOX BIAB_NAV_TIMEOUT_MS"\n' "$BROWSER_BIN_TARGET" >> "$tmp_sudoers"
chmod 0440 "$tmp_sudoers"
if visudo -c -f "$tmp_sudoers" >/dev/null 2>&1; then
    install -o root -g root -m 0440 "$tmp_sudoers" "$BROWSER_SUDOERS_FILE"
    log "browser pack: installed $BROWSER_SUDOERS_FILE"
else
    rm -f "$tmp_sudoers"
    die "browser pack: generated sudoers file failed validation, aborting (not installed)"
fi
rm -f "$tmp_sudoers"

# ---------------------------------------------------------------------------
# Skill: copy to ~/.agents/skills (source of truth) + symlink into
# ~/.claude/skills and, on antigravity boxes, ~/.gemini/skills. Mirrors
# install_skill() in payload/wizard/40-scaffold.sh, but deliberately NOT
# wired through payload/skills/manifest.tsv — that's what keeps this skill
# out of every default install (FEAT-017 §2.2 / AC-R2).
# ---------------------------------------------------------------------------
operator_user="$(resolve_operator_user || true)"
if [[ -n "$operator_user" ]]; then
    operator_home="$(getent passwd "$operator_user" | cut -d: -f6)"
    agents_skills_dir="${operator_home}/.agents/skills"
    # The box's CLI decides which skills dirs get the symlink (registry).
    # No persisted choice yet (pack added before the wizard ran) — fall back
    # to the default CLI's dirs, like the rest of the payload does.
    ai_cli="$(state_get '.ai_cli' 2>/dev/null || true)"
    : "${ai_cli:=${BIB_SUPPORTED_AI_CLIS[0]}}"

    mkdir -p "$agents_skills_dir"
    skill_target="${agents_skills_dir}/browser"
    if [[ -e "$skill_target" || -L "$skill_target" ]]; then
        log "browser pack: skill already present at $skill_target, skipping"
    else
        cp -r "${SCRIPT_DIR}/skill/browser" "$skill_target"
        log "browser pack: installed skill -> $skill_target"
    fi
    mapfile -t skill_link_dirs < <(ai_cli_skills_dirs "$ai_cli")
    for skills_dir in "${skill_link_dirs[@]}"; do
        mkdir -p "${operator_home}/${skills_dir}"
        skill_link="${operator_home}/${skills_dir}/browser"
        if [[ ! -e "$skill_link" && ! -L "$skill_link" ]]; then
            ln -s "$skill_target" "$skill_link"
            log "browser pack: symlinked $skill_link -> $skill_target"
        fi
    done
    chown -R "${operator_user}:${operator_user}" "$agents_skills_dir" \
        "${skill_link_dirs[@]/#/${operator_home}/}" 2>/dev/null || true
else
    warn "browser pack: could not resolve the operator account, skipping skill install (run 'biab pack add browser' again after the base wizard has run)"
fi

if [[ "$WITH_XVFB" -eq 1 ]]; then
    install_xvfb_fallback
fi

log "browser pack: install complete. Default engine is full Chromium with its bundled sandbox helper enabled — see FEAT-017 §2.9 for the headless-shell/AppArmor finding this resolves."
