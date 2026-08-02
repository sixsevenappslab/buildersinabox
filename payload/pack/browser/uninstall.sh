#!/usr/bin/env bash
# Builders in a Box browser pack — uninstaller (FEAT-017). Idempotent:
# safe to run even if the pack (or parts of it) was never installed.
#
# Removes: biab-browse, the sudoers rule, the skill (+symlinks), profiles,
# engine caches, the driver, the home dir, and the biab-browser user itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "${SCRIPT_DIR}/../../lib/common.sh"
# shellcheck source=../../lib/ai-cli.sh
source "${SCRIPT_DIR}/../../lib/ai-cli.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

found_anything=0

if [[ -e "$BROWSER_SUDOERS_FILE" ]]; then
    rm -f "$BROWSER_SUDOERS_FILE"
    echo "browser pack uninstall: removed $BROWSER_SUDOERS_FILE"
    found_anything=1
fi

if [[ -e "$BROWSER_BIN_TARGET" ]]; then
    rm -f "$BROWSER_BIN_TARGET"
    echo "browser pack uninstall: removed $BROWSER_BIN_TARGET"
    found_anything=1
fi

# Skill: remove the operator's copy + symlinks (best-effort; the operator
# account may already be gone or unresolvable).
operator_user="$(resolve_operator_user || true)"
if [[ -n "$operator_user" ]]; then
    operator_home="$(getent passwd "$operator_user" | cut -d: -f6)"
    # Sweep the skill symlink from EVERY registered CLI's skills dirs (union,
    # deduped) — uninstall must clean up no matter which CLI the box ran.
    while IFS= read -r _skills_dir; do
        link="${operator_home}/${_skills_dir}/browser"
        if [[ -e "$link" || -L "$link" ]]; then
            rm -f "$link"
            echo "browser pack uninstall: removed $link"
            found_anything=1
        fi
    done < <(for c in "${BIB_SUPPORTED_AI_CLIS[@]}"; do ai_cli_skills_dirs "$c"; done | awk '!seen[$0]++')
    skill_src="${operator_home}/.agents/skills/browser"
    if [[ -e "$skill_src" ]]; then
        rm -rf -- "$skill_src"
        echo "browser pack uninstall: removed $skill_src"
        found_anything=1
    fi
fi

# Home dir: driver, caches, profiles, out dir — everything owned by
# biab-browser lives under here.
if [[ -e "$BROWSER_HOME" ]]; then
    rm -rf -- "$BROWSER_HOME"
    echo "browser pack uninstall: removed $BROWSER_HOME"
    found_anything=1
fi

# System user last (nothing above needs it to still exist, but removing it
# first would leave the home dir's ownership dangling).
if getent passwd "$BROWSER_USER" >/dev/null; then
    userdel "$BROWSER_USER" 2>/dev/null || true
    echo "browser pack uninstall: removed system user $BROWSER_USER"
    found_anything=1
fi

if [[ "$found_anything" -eq 0 ]]; then
    echo "browser pack uninstall: nothing to remove"
else
    echo "browser pack uninstall: complete"
fi
exit 0
