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

do_add() {
    # biab add sdd — install the optional Spec-Driven Development skills
    # (sdd-base, sdd-coordinator, sdd-docs, sdd-growth, sdd-qa, sdd-spec-writer)
    # that are shipped but not installed by default.
    local group="${1:-}"
    if [[ "$group" != "sdd" ]]; then
        echo "biab add: unknown group '${group}'. Available: sdd" >&2
        echo "Usage: biab add sdd" >&2
        exit 1
    fi
    local skills_src=/opt/buildersinabox/payload/skills
    local manifest="${skills_src}/manifest.tsv"
    local home agents_dir claude_dir agy_dir ai_cli
    home="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
    agents_dir="${home}/.agents/skills"
    claude_dir="${home}/.claude/skills"
    # Mirror 40-scaffold: on antigravity boxes also symlink into agy's global
    # skills dir (~/.gemini/skills), since agy doesn't scan ~/.agents/skills.
    agy_dir="${home}/.gemini/skills"
    ai_cli="$(jq -r '.ai_cli // "claude"' /var/lib/buildersinabox/state.json 2>/dev/null || echo claude)"
    mkdir -p "$agents_dir" "$claude_dir"
    [[ "$ai_cli" == "antigravity" ]] && mkdir -p "$agy_dir"
    local added=0
    while IFS=$'\t' read -r name tier; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        [[ "$tier" == "optional" && "$name" == sdd-* ]] || continue
        if [[ -e "${agents_dir}/${name}" || -L "${agents_dir}/${name}" ]]; then
            echo "biab add: ${name} already installed, skipping"
        else
            cp -r "${skills_src}/${name}" "${agents_dir}/${name}"
            [[ -e "${claude_dir}/${name}" || -L "${claude_dir}/${name}" ]] || ln -s "${agents_dir}/${name}" "${claude_dir}/${name}"
            if [[ "$ai_cli" == "antigravity" ]]; then
                [[ -e "${agy_dir}/${name}" || -L "${agy_dir}/${name}" ]] || ln -s "${agents_dir}/${name}" "${agy_dir}/${name}"
            fi
            echo "biab add: installed ${name}"
            added=$((added+1))
        fi
    done < "$manifest"
    echo "==> Added ${added} SDD skill(s). Type / in your AI CLI to see them."
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
  biab add sdd   install the optional spec-driven-development skills
  biab help      this message
EOF
        ;;
    *)         exec_bootstrap "$@" ;;
esac
WRAPPER

chmod 0755 "$target"
log "05-biab-command: /usr/local/bin/biab ready"
