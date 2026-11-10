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
#   biab status         — human-readable summary (add --json for state.json)
#   biab paseo pair     — reprint the phone-app values (sudo; --rotate = new password)
#   biab paseo restart  — restart the phone-app service and clear GIVEN_UP (sudo)
#   biab logs           — tail the bootstrap log
#   biab update         — git pull the BIAB repo + re-run install scripts
#   biab update --latest — same, but install the newest upstream tools (unsupported)
#   biab auto-update    — opt-in scheduled `biab update` (on [schedule] | off | status)
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
if [[ -r /opt/buildersinabox/payload/lib/user-content.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/buildersinabox/payload/lib/user-content.sh
    set +euo pipefail
fi

# install_optional_skill <name> — copy a bundled optional skill into
# ~/.agents/skills (the source of truth) and symlink it into each CLI's
# global skills dir this box uses. Mirrors 40-scaffold.sh's uc_install_skill.
# Idempotent. Runs as the box user (writes to that user's HOME).
install_optional_skill() {
    local name="$1"
    local src="$SKILLS_SRC/$name"
    if [[ ! -d "$src" ]]; then
        echo "biab add: skill '$name' not found in the bundled payload." >&2
        return 1
    fi
    if declare -F uc_refuse_symlink >/dev/null 2>&1; then
        uc_refuse_symlink "$HOME" "$HOME/.agents" "$HOME/.agents/skills" || return 1
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
    # Per-CLI skills link dirs come from the adapter registry, sourced in a
    # SUBSHELL on purpose: the registry sets `set -euo pipefail` and this
    # wrapper doesn't (and must not inherit it). Default-CLI dirs are created
    # if missing (the ~/.claude/skills semantics); any other registered CLI's
    # dir is only linked when it already exists on this box (the
    # ~/.gemini/skills semantics — present only on antigravity boxes).
    local registry=/opt/buildersinabox/payload/lib/ai-cli.sh
    local default_dirs all_dirs
    default_dirs="$(bash -c "source '$registry'; ai_cli_skills_dirs \"\${BIB_SUPPORTED_AI_CLIS[0]}\"")"
    all_dirs="$(bash -c "source '$registry'; for c in \"\${BIB_SUPPORTED_AI_CLIS[@]}\"; do ai_cli_skills_dirs \"\$c\"; done" | awk '!seen[$0]++')"
    local d link
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        if grep -qxF "$d" <<<"$default_dirs"; then
            mkdir -p "$HOME/$d"
        fi
        [[ -d "$HOME/$d" ]] || continue
        link="$HOME/$d/$name"
        [[ -e "$link" || -L "$link" ]] || ln -s "$target" "$link"
    done <<<"$all_dirs"
    echo "Type / in your AI CLI and look for /$name."
    return 0
}

_biab_add_options() {
    awk -F'\t' '
        { sub(/\r$/, "") }
        !/^#/ && NF {
            if ($3 != "" && !seen[$3]++) items[++n] = $3
            if ($2 == "optional" && !seen[$1]++) items[++n] = $1
        }
        END {
            for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? ", " : ""), items[i]
        }
    ' "$MANIFEST" 2>/dev/null
}

do_add() {
    # `biab add <skill-or-group>` installs a bundled optional skill or skill
    # group (tier `optional` or column 3 `group` in the skills manifest) via
    # the same copy+symlink mechanism the scaffold uses. Resolves first as a
    # skill name, then as a group name. Core skills are already on every box.
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
            echo "Usage: biab add <group>   (optional: $(_biab_add_options))" >&2
            exit 1
            ;;
        *)
            local tier
            tier="$(awk -F'\t' -v g="$group" '{sub(/\r$/,"")} !/^#/ && NF && $1==g {print $2; exit}' "$MANIFEST" 2>/dev/null)"
            if [[ "$tier" == "optional" ]]; then
                install_optional_skill "$group" || exit 1
                exit 0
            elif [[ "$tier" == "core" ]]; then
                echo "'$group' is a core skill — already installed on every box."
                exit 0
            fi
            local grp_rows=()
            mapfile -t grp_rows < <(awk -F'\t' -v g="$group" '{sub(/\r$/,"")} !/^#/ && NF && $3==g {printf "%s\t%s\n", $1, $2}' "$MANIFEST" 2>/dev/null)
            if [[ "${#grp_rows[@]}" -gt 0 ]]; then
                local rc_grp=0 row sname stier
                for row in "${grp_rows[@]}"; do
                    IFS=$'\t' read -r sname stier <<<"$row"
                    if [[ "$stier" == "core" ]]; then
                        echo "'$sname' is a core skill — already installed on every box."
                    else
                        install_optional_skill "$sname" || rc_grp=1
                    fi
                done
                exit "$rc_grp"
            fi
            echo "biab add: unknown group '${group}'." >&2
            echo "Usage: biab add <group>   (optional: $(_biab_add_options))" >&2
            exit 1
            ;;
    esac
}

do_pack() {
    # `biab pack add|remove|list <name>` manages heavyweight opt-in packs
    # (system packages, a dedicated user, a CLI on PATH). Skill-only groups
    # still go through `biab add`. Packs live in the shipped-but-not-installed
    # payload/pack/<name>/ tree; add/remove just exec their scripts.
    local action="${1:-}"; shift || true
    local name="${1:-}"
    local packroot=/opt/buildersinabox/payload/pack
    case "$action" in
        list)
            if [[ ! -d "$packroot" ]]; then
                echo "no packs available"
                return 0
            fi
            for d in "$packroot"/*/; do
                [[ -d "$d" ]] || continue
                local n; n="$(basename "$d")"
                # Prefer each pack's own lib.sh (pack_is_installed) — a
                # pack's CLI binary name doesn't necessarily match
                # `biab-<name>` (e.g. the browser pack ships biab-browse,
                # not biab-browser). Fall back to that guess if lib.sh
                # doesn't define the function.
                local installed=0
                if [[ -f "${d}lib.sh" ]] && (
                    # shellcheck disable=SC1090
                    source "${d}lib.sh" 2>/dev/null && declare -F pack_is_installed >/dev/null && pack_is_installed
                ); then
                    installed=1
                elif command -v "biab-${n}" >/dev/null 2>&1; then
                    installed=1
                fi
                if [[ "$installed" -eq 1 ]]; then
                    printf '%s\tinstalled\n' "$n"
                else
                    printf '%s\tnot installed\n' "$n"
                fi
            done ;;
        add)
            [[ -n "$name" ]] || { echo "usage: biab pack add <name>" >&2; exit 1; }
            shift || true
            exec sudo "$packroot/$name/install.sh" "$@" ;;
        remove)
            [[ -n "$name" ]] || { echo "usage: biab pack remove <name>" >&2; exit 1; }
            exec sudo "$packroot/$name/uninstall.sh" ;;
        *)
            echo "usage: biab pack {list|add|remove} <name>" >&2; exit 1 ;;
    esac
}

do_update() {
    set -e
    local latest=""
    case "${1:-}" in
        "") ;;
        --latest) latest="--latest" ;;
        *) echo "usage: biab update [--latest]" >&2; exit 1 ;;
    esac
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
    # The temp file is created by root INSIDE the root-owned state dir (never a
    # path under world-writable /tmp that root would then move into place).
    state_tmp="$(sudo mktemp /var/lib/buildersinabox/state.XXXXXX)"
    sudo jq 'del(.phases.stack_installed)' /var/lib/buildersinabox/state.json \
        | sudo tee "$state_tmp" >/dev/null
    sudo mv "$state_tmp" /var/lib/buildersinabox/state.json
    sudo chmod 644 /var/lib/buildersinabox/state.json
    sudo "$repo/payload/install.sh" --skip-wizard $latest
    echo "==> Done."
    echo "If new wizard steps were added you can resume them with: biab"
}

# `biab status`: a short human summary with the Paseo block first. The raw
# state.json dump the command used to print is `biab status --json`, unchanged.
do_status() {
    local state="${BIB_STATE_FILE:-/var/lib/buildersinabox/state.json}"
    case "${1:-}" in
        --json) sudo cat "$state" | jq . ; return ;;
        "") ;;
        *) echo "usage: biab status [--json]" >&2; exit 1 ;;
    esac
    echo "Builders in a Box: status"
    local helper=/opt/buildersinabox/paseo/bin/biab-paseo-health
    if [[ -x "$helper" ]]; then
        "$helper" block || true
    else
        # No Paseo daemon on this box (the Paseo step failed or never ran): say so
        # and give the SSH way in, so a box is never left without an interface.
        local lib=/opt/buildersinabox/payload/lib cli user
        cli="$(jq -r '.ai_cli // empty' "$state" 2>/dev/null || true)"
        user="$(jq -r '.bib_user // empty' "$state" 2>/dev/null || true)"
        echo "Phone app service: not installed on this box (retry with: sudo biab update)"
        if [[ -n "$cli" && -r "$lib/ai-cli.sh" && -r "$lib/paseo.sh" ]]; then
            bash -c 'source "$1"; source "$2"; paseo_ssh_fallback_text "$3" "$4" "$5"' \
                _ "$lib/ai-cli.sh" "$lib/paseo.sh" "$cli" "${user:-<user>}" "$(hostname)" 2>/dev/null || true
        fi
    fi
    if [[ -r "$state" ]]; then
        jq -r '"Box: user \(.bib_user // "?"), AI CLI \(.ai_cli // "not chosen yet"), profile \(.install_profile // "?")",
               (([.phases // {} | to_entries[] | select(.value == true) | .key] | join(", ")) as $d
                | "Steps done: \(if $d == "" then "none" else $d end)"),
               (([.phases // {} | to_entries[] | select(.value != true) | .key] | join(", ")) as $p
                | if $p == "" then empty else "Not done yet: \($p)  (run: biab)" end)' "$state" 2>/dev/null \
            || echo "(state.json could not be read)"
    else
        echo "(no state.json yet: run biab to start the setup)"
    fi
    # FEAT-042 R7: what protects this box on the AI CLI it runs. Read from the BOX
    # USER's home (this may run under sudo, where $HOME is root's). A cold source, like
    # the Paseo fallback above; if anything here fails, the rest of the report stands.
    if [[ -r "$state" ]]; then
        local scli suser shome slib=/opt/buildersinabox/payload/lib
        scli="$(jq -r '.ai_cli // empty' "$state" 2>/dev/null || true)"
        suser="$(jq -r '.bib_user // empty' "$state" 2>/dev/null || true)"
        shome=""
        [[ -n "$suser" ]] && shome="$(getent passwd "$suser" 2>/dev/null | cut -d: -f6 || true)"
        if [[ -n "$scli" && -n "$shome" && -r "$slib/ai-cli.sh" && -r "$slib/guard.sh" ]]; then
            bash -c 'source "$1"; [[ ! -r "$2" ]] || source "$2"; source "$3"; guard_status_block "$4" "$5"' \
                _ "$slib/ai-cli.sh" "$slib/paseo.sh" "$slib/guard.sh" "$scli" "$shome" 2>/dev/null || true
        fi
    fi
    # FEAT-038 R6: a box that left the tested versions says so, and how to return.
    if [[ -r "$state" ]] && [[ "$(jq -r '.pins.mode // empty' "$state" 2>/dev/null || true)" == "latest" ]]; then
        echo "OFF-PIN since $(jq -r '.pins.since // "unknown"' "$state" 2>/dev/null): untested versions. Return with: biab update"
    fi
    echo "Raw state: biab status --json"
}

# `biab paseo pair|restart`: the phone-app service. Both need root (the
# credential is root-only, the unit is a system unit); the helper does the work.
do_paseo() {
    local helper=/opt/buildersinabox/paseo/bin/biab-paseo-health
    case "${1:-}" in
        pair|restart)
            [[ -x "$helper" ]] || { echo "biab paseo: the phone-app service is not installed on this box (see: biab status). Retry with: sudo biab update" >&2; exit 1; }
            exec sudo "$helper" "$@" ;;
        antigravity)
            # TODO(2026-10-31): remove after 2027-04-30. Kept so an old README or muscle memory does not hit "unknown subcommand".
            echo "Antigravity now runs in the Paseo app and asks before it runs shell commands, writes files in your project, home folder, ~/.biab or /var/tmp, and reads files outside your project; there is nothing to switch."
            exit 0 ;;
        *)
            echo "usage: biab paseo {pair [--rotate]|restart}" >&2; exit 1 ;;
    esac
}

case "${1:-}" in
    "")        exec_bootstrap ;;
    status)    shift; do_status "$@" ;;
    paseo)     shift; do_paseo "$@" ;;
    logs)      sudo tail -f /var/log/buildersinabox/bootstrap.log ;;
    # `exit` inside the branch: do_update rewrites this very file (the installer
    # regenerates the wrapper), and bash reads a script lazily, so anything after the
    # case would run from a stale offset into the new file ("s: command not found").
    update)    shift; do_update "$@"; exit $? ;;
    auto-update) shift; exec sudo /opt/buildersinabox/payload/install.sh --auto-update "$@" ;;
    add)       shift; do_add "$@" ;;
    pack)      shift; do_pack "$@" ;;
    help|-h|--help)
        cat <<EOF
biab — Builders in a Box CLI
  biab           resume the installer from the last completed step
  biab status    short summary: phone-app service, setup steps (--json for state.json)
  biab logs      follow the bootstrap log
  biab update    pull latest BIAB + re-run install scripts (no reinstall needed)
                 biab update --latest   install the newest upstream Claude Code, Codex,
                                        Paseo and agy instead of the tested versions
                                        (unsupported; 'biab update' returns to them)
  biab auto-update  scheduled 'biab update', off until you turn it on
                 biab auto-update on [weekly|daily|monthly|'Mon 03:30']  |  off  |  status
                                        (it runs plain 'biab update': on a box that used
                                         --latest, the next run puts it back on the tested versions)
  biab add       install an optional bundled skill or skill group (e.g. 'biab add incident', 'biab add handover', 'biab add marketing')
  biab pack      manage opt-in heavyweight capability packs
                 (browser: a sandboxed headless Chromium the agent can drive.
                  night-shift: overnight work on specs you have validated —
                  installed switched OFF, and it spends your subscription
                  once you switch it on, so read what it prints.)
                 biab pack list            show available packs + status
                 biab pack add <name>      install a pack
                 biab pack remove <name>   uninstall a pack
  biab paseo     the phone-app service (needs sudo)
                 biab paseo pair [--rotate]   show host/port/password and confirm
                                              pairing; --rotate makes a new password
                 biab paseo restart           restart it and clear a "gave up" state
  biab help      this message
EOF
        ;;
    *)         exec_bootstrap "$@" ;;
esac
WRAPPER

chmod 0755 "$target"
log "05-biab-command: /usr/local/bin/biab ready"
