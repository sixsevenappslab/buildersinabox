#!/usr/bin/env bash
# Installs /usr/local/bin/biab — a short wrapper around install.sh.
# Lets the user type `biab` after SSH'ing in (instead of the 50-char
# `sudo /opt/buildersinabox/payload/install.sh`).
#
# Idempotent: just overwrites the wrapper on every install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

target=/usr/local/bin/biab
log "05-biab-command: installing $target"

cat > "$target" <<'WRAPPER'
#!/usr/bin/env bash
# Builders in a Box — short command.
#
#   biab                — resume the wizard from the last completed step
#   biab status         — print state.json
#   biab logs           — tail the bootstrap log
#   biab update         — git pull the BIAB repo + re-run install scripts
#
# `update` is the recommended way to receive bug fixes and new bundled
# skills/specs without reinstalling. Requires the upstream repo at
# /opt/buildersinabox to be a git checkout (it is, by default).

exec_bootstrap() {
    exec sudo --preserve-env=SSH_CONNECTION,SSH_CLIENT,SSH_TTY \
        /opt/buildersinabox/payload/install.sh "$@"
}

SKILLS_SRC=/opt/buildersinabox/payload/skills
MANIFEST="$SKILLS_SRC/manifest.tsv"

# install_optional_skill <name> — copy a bundled optional skill into
# ~/.agents/skills (the source of truth) and symlink it into each CLI's
# global skills dir this box uses. Mirrors 40-scaffold.sh's install_skill.
# Idempotent. Runs as the box user (writes to that user's HOME).
install_optional_skill() {
    local name="$1"
    local src="$SKILLS_SRC/$name"
    if [[ ! -d "$src" ]]; then
        echo "biab add: skill '$name' not found in the bundled payload." >&2
        exit 1
    fi
    local agents_dir="$HOME/.agents/skills"
    local target="$agents_dir/$name"
    mkdir -p "$agents_dir"
    if [[ -e "$target" || -L "$target" ]]; then
        echo "'$name' is already installed — nothing to do."
    else
        cp -r "$src" "$target"
        echo "Installed skill '$name' -> $target"
    fi
    # Claude Code boxes: symlink into ~/.claude/skills.
    local claude_link="$HOME/.claude/skills/$name"
    if [[ ! -e "$claude_link" && ! -L "$claude_link" ]]; then
        mkdir -p "$HOME/.claude/skills"
        ln -s "$target" "$claude_link"
    fi
    # Antigravity boxes: symlink into ~/.gemini/skills (present only there).
    if [[ -d "$HOME/.gemini/skills" ]]; then
        local agy_link="$HOME/.gemini/skills/$name"
        [[ -e "$agy_link" || -L "$agy_link" ]] || ln -s "$target" "$agy_link"
    fi
    echo "Type / in your AI CLI and look for /$name."
}

do_add() {
    # `biab add <group>` installs a bundled optional skill (tier `optional`
    # in the skills manifest) via the same copy+symlink mechanism the scaffold
    # uses. Core skills are already on every box.
    local group="${1:-}"
    case "$group" in
        sdd)
            # Was `biab add sdd` before v0.2. Now a friendly no-op.
            echo "SDD skills are installed by default since v0.2 — nothing to do."
            echo "Type / in your AI CLI and look for /sdd-coordinator to get started."
            exit 0
            ;;
        "")
            echo "biab add: missing group name." >&2
            echo "Usage: biab add <group>   (optional: $(awk -F'\t' '$2=="optional"{print $1}' "$MANIFEST" 2>/dev/null | paste -sd ', ' -))" >&2
            exit 1
            ;;
        *)
            local tier
            tier="$(awk -F'\t' -v g="$group" '$1==g {print $2}' "$MANIFEST" 2>/dev/null)"
            if [[ "$tier" == "optional" ]]; then
                install_optional_skill "$group"
                exit 0
            elif [[ "$tier" == "core" ]]; then
                echo "'$group' is a core skill — already installed on every box."
                exit 0
            fi
            echo "biab add: unknown group '${group}'." >&2
            echo "Usage: biab add <group>   (optional: $(awk -F'\t' '$2=="optional"{print $1}' "$MANIFEST" 2>/dev/null | paste -sd ', ' -))" >&2
            exit 1
            ;;
    esac
}

do_update() {
    set -e
    repo=/opt/buildersinabox
    if [[ ! -d "$repo/.git" ]]; then
        echo "biab update: $repo is not a git checkout — nothing to update" >&2
        echo "(this device was installed before remote updates were supported, or the .git folder was removed)" >&2
        exit 1
    fi
    echo "==> Syncing latest BIAB into $repo"
    # Releases are fresh-history snapshots (publish.sh force-pushes) and
    # tag-pinned installs have a tag-only fetch refspec — a plain pull can
    # never fast-forward here. Hard-sync to the latest published main.
    sudo git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    sudo git -C "$repo" fetch --quiet --force --tags origin
    sudo git -C "$repo" checkout --quiet -B main refs/remotes/origin/main
    echo "==> Re-running install scripts (idempotent, no wizard)"
    # install.sh --skip-wizard runs every install/*.sh again. The
    # individual scripts are idempotent (apt installs no-op if present,
    # file copies overwrite). Stack-installed flag is cleared first so
    # the install step is not silently skipped.
    sudo jq 'del(.phases.stack_installed)' /var/lib/buildersinabox/state.json \
        > /tmp/s.json && sudo mv /tmp/s.json /var/lib/buildersinabox/state.json
    sudo chmod 644 /var/lib/buildersinabox/state.json
    sudo "$repo/payload/install.sh" --skip-wizard
    echo "==> Done."
    echo "If new wizard steps were added you can resume them with: biab"
}

case "${1:-}" in
    "")        exec_bootstrap ;;
    status)    sudo cat /var/lib/buildersinabox/state.json | jq . ;;
    logs)      sudo tail -f /var/log/buildersinabox/bootstrap.log ;;
    update)    do_update ;;
    add)       shift; do_add "$@" ;;
    help|-h|--help)
        cat <<EOF
biab — Builders in a Box CLI
  biab           resume the installer from the last completed step
  biab status    print state.json
  biab logs      follow the bootstrap log
  biab update    pull latest BIAB + re-run install scripts (no reinstall needed)
  biab add       install an optional bundled skill (e.g. 'biab add incident')
  biab help      this message
EOF
        ;;
    *)         exec_bootstrap "$@" ;;
esac
WRAPPER

chmod 0755 "$target"
log "05-biab-command: /usr/local/bin/biab ready"
