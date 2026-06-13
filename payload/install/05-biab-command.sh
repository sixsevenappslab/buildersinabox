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
# skills/specs without re-flashing the USB. Requires the upstream repo
# at /opt/buildersinabox to be a git checkout (it is, by default).

exec_bootstrap() {
    exec sudo --preserve-env=SSH_CONNECTION,SSH_CLIENT,SSH_TTY \
        /opt/buildersinabox/payload/install.sh "$@"
}

do_update() {
    set -e
    repo=/opt/buildersinabox
    if [[ ! -d "$repo/.git" ]]; then
        echo "biab update: $repo is not a git checkout — nothing to update" >&2
        echo "(this device was installed before remote updates were supported, or the .git folder was removed)" >&2
        exit 1
    fi
    echo "==> Pulling latest BIAB into $repo"
    sudo git -C "$repo" fetch --quiet --all
    sudo git -C "$repo" pull --ff-only
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
    help|-h|--help)
        cat <<EOF
biab — Builders in a Box CLI
  biab           resume the installer from the last completed step
  biab status    print state.json
  biab logs      follow the bootstrap log
  biab update    pull latest BIAB + re-run install scripts (no re-flash needed)
  biab help      this message
EOF
        ;;
    *)         exec_bootstrap "$@" ;;
esac
WRAPPER

chmod 0755 "$target"
log "05-biab-command: /usr/local/bin/biab ready"
