#!/usr/bin/env bash
# Builders in a Box — installer entry point.
#
# Run on a fresh Ubuntu 24.04 install (mini PC or VM). Idempotent.
# Installs the base stack, then runs the setup wizard.
#
# Modes:
#   default              Interactive install: prompts for required values
#                        when missing, runs the stack and the wizard.
#   --non-interactive    Reads BIB_USER / BIB_NAME / BIB_FLAVOR /
#                        BIB_AI_CLI from the environment. Fails fast if
#                        any required var is missing. Used by CI and the
#                        autoinstall flow.
#   --update             Re-runs idempotently on a box that already went
#                        through install once. Skips completed phases.
#   --uninstall          Removes everything BIAB-owned and exits. Leaves
#                        ${HOME}, Tailscale, gh, and Claude auth alone.
#   --selftest           Runs tools/check-no-personal-refs.sh against the
#                        install tree + verifies state.json schema.
#   --latest             With --update or --skip-wizard (what `biab update
#                        --latest` passes): install the newest stable upstream
#                        version of each tool instead of the tested pins.
#   --auto-update ...    `on [schedule] | off | status`: the opt-in update timer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/ai-cli.sh
source "${SCRIPT_DIR}/lib/ai-cli.sh"
# shellcheck source=lib/prompt.sh
source "${SCRIPT_DIR}/lib/prompt.sh"
# shellcheck source=lib/pins.sh
source "${SCRIPT_DIR}/lib/pins.sh"

# ---------------------------------------------------------------------------
# Defaults + arg parsing
# ---------------------------------------------------------------------------

FORCE=0
SKIP_WIZARD=0
OS_OVERRIDE=0
NON_INTERACTIVE=0
UPDATE_MODE=0
UNINSTALL_MODE=0
SELFTEST_MODE=0
LATEST_MODE=0
AUTOUPDATE_MODE=0
AUTOUPDATE_ARGS=()
AI_CLI_ARG=""
FLAVOR_ARG=""
PROFILE_ARG=""

# FEAT-024: root prefix for every absolute path do_uninstall touches, so the
# unit driver can point the whole teardown at a mktemp -d instead of the real
# /etc. Empty on a real box — the paths below are byte-identical to what they
# were. Honoured ONLY when the file is sourced as a library, so a stray
# BIB_UNINSTALL_ROOT_TEST in someone's environment can never redirect (or
# escape) a genuine uninstall.
BIB_UNINSTALL_ROOT=""
if [[ "${BIB_INSTALL_LIB:-0}" == "1" ]]; then
    BIB_UNINSTALL_ROOT="${BIB_UNINSTALL_ROOT_TEST:-}"
fi

usage() {
    cat <<'EOF'
Usage: sudo install.sh [options]

Options:
  --ai-cli=<claude|antigravity|codex|opencode>  Pick the AI CLI to install (default: claude).
  --flavor=<default|gift>    Pick the copy/banner flavor (default: default).
  --profile=<dedicated|cloud>  Who owns SSH on this box (default: dedicated).
                             'cloud' is for a provider-managed VPS: BIAB then
                             never writes an sshd drop-in, never enables
                             password auth and never binds sshd to the tailnet.
                             Persisted on first install; survives biab update.
  --force                    Reset wizard-phase state so the wizard runs again.
                             Does not reinstall the stack.
  --skip-wizard              Install the stack and exit (no OAuth steps).
                             Useful for CI / image baking.
  --non-interactive          Read BIB_USER, BIB_NAME, BIB_FLAVOR, BIB_AI_CLI
                             from the environment. Fail fast if any required
                             var is missing. Used by CI and autoinstall.
  --update                   Re-run idempotently on a box that already went
                             through install once. Skips completed phases.
  --uninstall                Remove everything BIAB-owned and exit.
                             Leaves user home, Tailscale, gh, Claude auth.
  --selftest                 Run the personal-refs guard against the install
                             tree and verify state.json schema; exit.
  --latest                   With --update or --skip-wizard: install the newest
                             stable upstream versions instead of the tested pins.
                             Untested and unsupported; `biab update` returns.
  --auto-update on [schedule] | off | status
                             The opt-in update timer (never uses --latest).
  --i-know-what-im-doing     Continue even if the OS is not Ubuntu 24.04.
  -h, --help                 Show this help.
EOF
}

# FEAT-024: payload/test/uninstall-contract.sh sources this file to unit-test
# do_uninstall. The guard belongs in the loop CONDITION, not around it: when
# sourced, "$@" is whatever the *caller* was invoked with, so the `case *)`
# below would kill the test driver with "unknown argument".
while [[ "${BIB_INSTALL_LIB:-0}" != "1" && $# -gt 0 ]]; do
    case "$1" in
        --force)              FORCE=1; shift ;;
        --skip-wizard)        SKIP_WIZARD=1; shift ;;
        --non-interactive)    NON_INTERACTIVE=1; shift ;;
        --update)             UPDATE_MODE=1; shift ;;
        --uninstall)          UNINSTALL_MODE=1; shift ;;
        --selftest)           SELFTEST_MODE=1; shift ;;
        --latest)             LATEST_MODE=1; shift ;;
        --auto-update)        AUTOUPDATE_MODE=1; shift; AUTOUPDATE_ARGS=("$@"); shift $# ;;
        --i-know-what-im-doing) OS_OVERRIDE=1; shift ;;
        --ai-cli=*)           AI_CLI_ARG="${1#--ai-cli=}"; shift ;;
        --ai-cli)             AI_CLI_ARG="${2:-}"; shift 2 ;;
        --flavor=*)           FLAVOR_ARG="${1#--flavor=}"; shift ;;
        --flavor)             FLAVOR_ARG="${2:-}"; shift 2 ;;
        --profile=*)          PROFILE_ARG="${1#--profile=}"; shift ;;
        --profile)            PROFILE_ARG="${2:-}"; shift 2 ;;
        -h|--help)            usage; exit 0 ;;
        *)                    usage >&2; die "unknown argument: $1" ;;
    esac
done

# FEAT-038: --latest only makes sense on an update (`biab update --latest` passes
# --skip-wizard). Refuse it anywhere else before anything is touched.
if [[ "$LATEST_MODE" -eq 1 ]]; then
    if [[ "$UPDATE_MODE" -ne 1 && "$SKIP_WIZARD" -ne 1 ]] || [[ "$UNINSTALL_MODE" -eq 1 || "$SELFTEST_MODE" -eq 1 || "$AUTOUPDATE_MODE" -eq 1 ]]; then
        usage >&2
        die "--latest is only valid together with --update or --skip-wizard (use: biab update --latest)"
    fi
fi

# Export OS override so common.sh sees it.
[[ "$OS_OVERRIDE" -eq 1 ]] && export BIB_OS_OVERRIDE=1

# Surface --flavor as BIB_FLAVOR so bib_flavor_resolve sees it.
if [[ -n "$FLAVOR_ARG" ]]; then
    export BIB_FLAVOR="$FLAVOR_ARG"
fi

# Surface --ai-cli as BIB_AI_CLI so non-interactive validation is symmetrical
# with the other vars.
if [[ -n "$AI_CLI_ARG" ]]; then
    export BIB_AI_CLI="$AI_CLI_ARG"
fi

# FEAT-029: surface --profile as BIB_INSTALL_PROFILE so the profile helpers in
# common.sh see it, including in the preflight below that runs before
# state_init. Validate here so a typo fails before anything is installed
# rather than after the stack is half up.
if [[ -n "$PROFILE_ARG" ]]; then
    export BIB_INSTALL_PROFILE="$PROFILE_ARG"
fi
if [[ -n "${BIB_INSTALL_PROFILE:-}" ]]; then
    bib_profile_validate "$BIB_INSTALL_PROFILE"
fi

# ---------------------------------------------------------------------------
# Non-interactive validation
# ---------------------------------------------------------------------------
# Required vars when --non-interactive is set. Empty values fail; the
# resolvers in lib/common.sh die with named-var errors so the caller knows
# exactly what is missing.

if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    : "${BIB_USER:?BIB_USER is required in --non-interactive mode}"
    : "${BIB_FLAVOR:?BIB_FLAVOR is required in --non-interactive mode (default|gift)}"
    : "${BIB_AI_CLI:?BIB_AI_CLI is required in --non-interactive mode (claude|antigravity|codex|opencode)}"
    # BIB_NAME may legitimately be empty (default flavor drops the line).
    # Treat unset as empty; do not require.
    export BIB_NAME="${BIB_NAME:-}"
fi

# ---------------------------------------------------------------------------
# Mode: uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    require_root
    local found_anything=0

    local target_user="${SUDO_USER:-${USER:-}}"
    if [[ -f "$BIB_STATE_FILE" ]]; then
        local stored_user
        stored_user="$(jq -r '.bib_user // empty' "$BIB_STATE_FILE" 2>/dev/null || true)"
        [[ -n "$stored_user" ]] && target_user="$stored_user"
    fi

    # This guard runs FIRST, before anything is torn down. It offers to abort,
    # and "abort" has to mean the machine is untouched — the pack teardown below
    # removes a system user and a sudoers rule, so asking after it would make
    # the abort message a lie.
    #
    # Removing the auth drop-in later hands PasswordAuthentication back to the
    # distribution default, which on cloud images is "no". Our own security
    # model says the account password is the SSH credential (install/50-ssh.sh),
    # so a user who never added a key is relying entirely on that drop-in — and
    # taking it away can leave a headless box unreachable. 35-ssh-finalize.sh
    # treats this exact hazard as a hard stop (HOLD-OPEN); so does uninstall.
    if [[ -e "${BIB_UNINSTALL_ROOT}/etc/ssh/sshd_config.d/00-buildersinabox.conf" ]]; then
        local _ak=""
        if [[ -n "$target_user" ]] && getent passwd "$target_user" >/dev/null; then
            _ak="$(getent passwd "$target_user" | cut -d: -f6)/.ssh/authorized_keys"
        fi
        if [[ -z "$_ak" ]] || ! bib_authorized_keys_present "$_ak"; then
            printf '\n'
            printf '  WARNING — %s has no SSH key in authorized_keys.\n' "${target_user:-the target user}"
            printf '  Password login works right now because of a drop-in this uninstall\n'
            printf '  removes. Your distribution decides what happens next, and on cloud\n'
            printf '  images that default is "PasswordAuthentication no".\n'
            printf '  If this box is headless, open a SECOND SSH session and confirm you\n'
            printf '  can still get in BEFORE you close this one.\n\n'
            # FEAT-024: /dev/tty is never readable on a CI runner, so the abort
            # path would be untestable if we kept reading it directly. Take the
            # source from BIB_PROMPT_INPUT — but ONLY in library mode, because
            # otherwise anyone with that variable exported (payload/test/dryrun.sh
            # exports it) would turn a real uninstall's "warn and continue" into
            # an abort. On a real box this stays exactly `/dev/tty`.
            local _prompt_src="/dev/tty"
            if [[ "${BIB_INSTALL_LIB:-0}" == "1" ]]; then
                _prompt_src="${BIB_PROMPT_INPUT:-/dev/tty}"
            fi
            if [[ "$NON_INTERACTIVE" -eq 0 && "$FORCE" -eq 0 && -r "$_prompt_src" ]]; then
                printf '  Type yes to continue: '
                local _ack=""
                # `|| true` is load-bearing: read returns non-zero on EOF, and
                # this file runs under `set -e`, so without it an empty input
                # would kill do_uninstall BEFORE the abort message below prints.
                read -r _ack < "$_prompt_src" || true
                if [[ "$_ack" != "yes" ]]; then
                    printf 'uninstall: aborted, nothing was changed.\n'
                    exit 1
                fi
            fi
        fi
    fi

    # FEAT-017: best-effort teardown of opt-in packs (e.g. browser) BEFORE
    # /opt/buildersinabox itself is removed below — the pack's own
    # uninstall.sh has to still exist to run. Never fails the overall
    # uninstall: a pack that isn't installed, or whose script is missing, is
    # silently skipped (source of truth for what to remove lives in the
    # pack itself, per FEAT-017 §2.2).
    local pack_dir
    # Quote the prefix but NOT the trailing glob: an unquoted for-list word-
    # splits, so a BIB_UNINSTALL_ROOT containing a space would split into words,
    # match nothing, and skip every pack teardown in silence.
    for pack_dir in "${BIB_UNINSTALL_ROOT}"/opt/buildersinabox/payload/pack/*/; do
        [[ -d "$pack_dir" ]] || continue
        local pack_uninstall="${pack_dir}uninstall.sh"
        if [[ -x "$pack_uninstall" ]]; then
            printf 'uninstall: running pack teardown %s\n' "$pack_uninstall"
            "$pack_uninstall" || printf 'uninstall: pack teardown %s failed, continuing\n' "$pack_uninstall"
        fi
    done

    # FEAT-035: the Paseo daemon. Stop and disable it BEFORE its unit file is
    # deleted below (same order as the night-shift pack), or systemd keeps a
    # dangling enablement symlink for a unit that no longer exists. It runs
    # shells for the user, so it must also be down before /opt goes.
    if [[ -e "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-paseo.service" ]] \
       && command -v systemctl >/dev/null 2>&1; then
        printf 'uninstall: stopping biab-paseo\n'
        # The health timer first: while it runs it would restart the daemon we
        # are about to stop.
        systemctl disable --now biab-paseo-health.timer >/dev/null 2>&1 || true
        systemctl disable --now biab-paseo.service >/dev/null 2>&1 || true
    fi

    # FEAT-038: the opt-in update timer. Disabled BEFORE its unit files are deleted
    # below, or systemd keeps a dangling enablement for a unit that no longer exists.
    if [[ -e "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-update.timer" ]] \
       && command -v systemctl >/dev/null 2>&1; then
        printf 'uninstall: disabling biab-update.timer\n'
        systemctl disable --now biab-update.timer >/dev/null 2>&1 || true
    fi

    # BIB-owned dirs and files. Order: smallest blast radius first.
    # NOTE: we print progress with plain printf to stdout, NOT log(), because
    # log() re-creates BIB_LOG_DIR (via _bib_log_init) every call — which would
    # resurrect /var/log/buildersinabox right after we remove it. Uninstall is
    # tearing the logging infra down, so it must not write into it.
    local paths_to_remove=(
        "${BIB_UNINSTALL_ROOT}/usr/local/bin/biab"
        "${BIB_UNINSTALL_ROOT}/etc/profile.d/biab-firstboot.sh"
        # FEAT-014 SSH drop-ins: the auth policy, the Tailscale-only bind, the
        # (legacy) public hardening file, and the systemd ordering drop-in that
        # makes ssh.service wait for the tailnet at boot. Removing the bind
        # restores a public listener so the box stays reachable after uninstall.
        #
        # 00- MUST be in this list. It sets PasswordAuthentication yes, and
        # because sshd takes the FIRST value it sees for a keyword and 00 sorts
        # ahead of everything, leaving it behind keeps password auth forced on
        # for good — overriding the user's own hardening drop-ins — on a box
        # they believe they have uninstalled us from.
        "${BIB_UNINSTALL_ROOT}/etc/ssh/sshd_config.d/00-buildersinabox.conf"
        "${BIB_UNINSTALL_ROOT}/etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf"
        "${BIB_UNINSTALL_ROOT}/etc/ssh/sshd_config.d/02-buildersinabox-public-hardening.conf"
        "${BIB_UNINSTALL_ROOT}/etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf"
        # FEAT-035: the Paseo unit and its root-only credential directory.
        # (The pinned tree is under /opt, the health record under the state dir.)
        "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-paseo.service"
        "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-paseo-failed.service"
        "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-paseo-health.service"
        "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-paseo-health.timer"
        # FEAT-038: the opt-in update timer and its service.
        "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-update.timer"
        "${BIB_UNINSTALL_ROOT}/etc/systemd/system/biab-update.service"
        "${BIB_UNINSTALL_ROOT}/etc/buildersinabox"
        "$BIB_LOG_DIR"
        "$BIB_STATE_DIR"
        "${BIB_UNINSTALL_ROOT}/opt/buildersinabox"
    )

    # /usr/local/bin/paseo is ours only when it is the symlink 46-paseo.sh made
    # into our tree; a paseo the user installed themselves is left alone.
    local _paseo_link="${BIB_UNINSTALL_ROOT}/usr/local/bin/paseo"
    if [[ -L "$_paseo_link" && "$(readlink "$_paseo_link")" == */opt/buildersinabox/paseo/* ]]; then
        paths_to_remove+=("$_paseo_link")
    fi

    # FEAT-038: /usr/local/bin/claude and codex are ours only when they are the
    # symlinks 40/42 made into our tools tree (under /opt, removed below).
    local _tool_link
    for _tool_link in claude codex; do
        _tool_link="${BIB_UNINSTALL_ROOT}/usr/local/bin/${_tool_link}"
        if [[ -L "$_tool_link" && "$(readlink "$_tool_link")" == */opt/buildersinabox/tools/* ]]; then
            paths_to_remove+=("$_tool_link")
        fi
    done

    # Only remove these two if they are ours. The installer refuses to overwrite
    # a `bd` or a tty1 autologin the machine already had, so removing them here
    # unconditionally would delete the user's own files on our way out.
    #
    # The patterns are specific rather than just "Builders in a Box", so a file
    # that merely mentions the product is not mistaken for one of ours. They
    # live in lib/common.sh (FEAT-024) because install/06-bd-cli.sh asks the
    # same question on the way in — the two drifting apart is exactly how #44
    # happened.
    local _own _pat
    for _own in "${BIB_UNINSTALL_ROOT}/usr/local/bin/bd" \
                "${BIB_UNINSTALL_ROOT}/etc/systemd/system/getty@tty1.service.d/autologin.conf"; do
        [[ -e "$_own" ]] || continue
        case "$_own" in
            */bd) _pat="$BIB_BD_OWNERSHIP_PATTERN" ;;
            *)    _pat="$BIB_AUTOLOGIN_OWNERSHIP_PATTERN" ;;
        esac
        if bib_path_is_ours "$_own" "$_pat"; then
            paths_to_remove+=("$_own")
        else
            printf 'uninstall: leaving %s alone — it is not ours\n' "$_own"
        fi
    done

    # The bwrap AppArmor profile (install/42-codex-cli.sh) is a security config
    # we put outside /opt, so uninstall has to take it back out — but only if it
    # is ours. Unload it first; a profile file removed while still loaded stays
    # in force until the next boot.
    local _bwrap="${BIB_UNINSTALL_ROOT}/etc/apparmor.d/bwrap"
    if [[ -e "$_bwrap" ]]; then
        if bib_path_is_ours "$_bwrap" "$BIB_OWNERSHIP_MARKER"; then
            command -v apparmor_parser >/dev/null 2>&1 \
                && apparmor_parser -R "$_bwrap" 2>/dev/null || true
            paths_to_remove+=("$_bwrap")
        else
            printf 'uninstall: leaving %s alone — it is not ours\n' "$_bwrap"
        fi
    fi

    # FEAT-040: /usr/local/bin/opencode is ours only when 43-opencode-cli.sh left
    # its marker AND the file is a regular file, never a link. Ownership is the
    # marker, not a hash, so a binary from an older pin is still ours after a bump;
    # a user's own opencode (no marker, or a symlink) is left alone. The check runs
    # here, before the loop below deletes /etc/buildersinabox with the marker in it.
    local _oc="${BIB_UNINSTALL_ROOT}/usr/local/bin/opencode"
    if [[ -e "$_oc" || -L "$_oc" ]]; then
        if [[ -f "$_oc" && ! -L "$_oc" ]] \
           && bib_marker_file_is_ours "${BIB_UNINSTALL_ROOT}/etc/buildersinabox/opencode.owned" "$BIB_OWNERSHIP_MARKER"; then
            paths_to_remove+=("$_oc")
        else
            printf 'uninstall: leaving %s alone — it is not ours\n' "$_oc"
        fi
    fi

    local p
    local removed_ssh_dropin=0 removed_update_unit=0
    for p in "${paths_to_remove[@]}"; do
        # -L as well: /usr/local/bin/paseo points into /opt, which is removed in
        # this same loop, so by the time we reach it the link is dangling and
        # `-e` alone would leave it behind.
        if [[ -e "$p" || -L "$p" ]]; then
            printf 'uninstall: removing %s\n' "$p"
            rm -rf -- "$p"
            found_anything=1
            [[ "$p" == "${BIB_UNINSTALL_ROOT}"/etc/systemd/system/biab-update.* ]] && removed_update_unit=1
            [[ "$p" == "${BIB_UNINSTALL_ROOT}"/etc/ssh/sshd_config.d/* || "$p" == "${BIB_UNINSTALL_ROOT}"/etc/systemd/system/ssh.service.d/* ]] \
                && removed_ssh_dropin=1
        fi
    done

    # The update units are gone: tell systemd (after the disable above, never before).
    if [[ "$removed_update_unit" -eq 1 ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload 2>/dev/null || true
    fi

    # If we removed any SSH drop-in, refresh systemd + sshd so the unit no longer
    # waits on the (now-removed) Tailscale bind and the listener returns to its
    # public default immediately (reload keeps live sessions — no lockout).
    if [[ "$removed_ssh_dropin" -eq 1 ]] && command -v systemctl >/dev/null 2>&1; then
        rmdir "${BIB_UNINSTALL_ROOT}/etc/systemd/system/ssh.service.d" 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        systemctl reload ssh.service 2>/dev/null || true

        # 50-ssh.sh switched the box off Ubuntu's default socket activation so
        # that sshd would honour ListenAddress. Put that back, but WITHOUT
        # --now: an uninstall is very often run over SSH, and stopping
        # ssh.service to hand port 22 to the socket would drop the listener
        # mid-command. Disabled-but-running is fine until the next boot, when
        # socket activation takes over again.
        if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
            : # already back on socket activation, nothing to do
        else
            systemctl disable ssh.service >/dev/null 2>&1 || true
            systemctl enable ssh.socket >/dev/null 2>&1 || true
            printf 'uninstall: restored ssh.socket activation (takes effect on next boot; current sshd left running)\n'
        fi
    fi

    # User-level shell snippets installed under ~${target_user}/.bashrc.d/biab-*.
    if [[ -n "$target_user" ]] && getent passwd "$target_user" >/dev/null; then
        local home
        home="$(getent passwd "$target_user" | cut -d: -f6)"
        if [[ -L "${home}/.bashrc.d" ]]; then
            # The box user owns this folder; a link here may be planted, and a
            # root sweep of biab-* through it would delete files elsewhere.
            printf 'uninstall: leaving %s alone — it is a symbolic link\n' "${home}/.bashrc.d"
        elif [[ -d "${home}/.bashrc.d" ]]; then
            local snippet
            for snippet in "${home}/.bashrc.d"/biab-*; do
                [[ -e "$snippet" || -L "$snippet" ]] || continue
                printf 'uninstall: removing %s\n' "$snippet"
                # AS the user (review cycle 2): even a lost race cannot reach a
                # file the user could not already delete.
                runuser -u "$target_user" -- rm -f -- "$snippet" || true
                found_anything=1
            done
        fi
        # FEAT-035: the BIAB-owned Paseo home, only if it carries our marker.
        # ~/.paseo (the user's own daemon, if any) is never touched.
        local _phome="${home}/.biab/paseo"
        if [[ -L "${home}/.biab" || -L "$_phome" ]]; then
            # A link here may be planted by the box user; root must not follow it.
            printf 'uninstall: leaving %s alone — it (or ~/.biab) is a symbolic link\n' "$_phome"
        elif [[ -d "$_phome" ]]; then
            if bib_marker_file_is_ours "${_phome}/.biab-owned" "$BIB_OWNERSHIP_MARKER"; then
                printf 'uninstall: removing %s\n' "$_phome"
                # AS the user: the checks above are a time-of-check, and the
                # box user can swap a path for a link before the delete.
                runuser -u "$target_user" -- rm -rf -- "$_phome" || true
                runuser -u "$target_user" -- rmdir "${home}/.biab" 2>/dev/null || true
                found_anything=1
            else
                printf 'uninstall: leaving %s alone — it is not ours\n' "$_phome"
            fi
        fi
    fi

    if [[ "$found_anything" -eq 0 ]]; then
        printf 'uninstall: nothing to remove — no BIAB state found\n'
    else
        printf 'uninstall: complete. sshd is back to your distribution defaults.\n'
        printf 'uninstall: left alone on purpose — your home directory (so your\n'
        printf '           projects under ~/ai-platform/projects/ and the first-project\n'
        printf '           progress in ~/.config/biab-first-project/ stay), the\n'
        printf '           tailnet membership, your GitHub and agent logins, your account\n'
        printf '           password, and the packages we installed (jq, gh, node,\n'
        printf '           tailscale, the AI CLI).\n'
    fi
    exit 0
}
if [[ "$UNINSTALL_MODE" -eq 1 ]]; then
    do_uninstall
fi

# FEAT-024: everything above this line is definitions and no-ops; everything
# below installs a machine. payload/test/uninstall-contract.sh sources the file
# to get do_uninstall, so stop here for it. `return` ends the sourcing without
# reindenting the 250 lines below into an `if`; the `|| exit 0` covers someone
# running install.sh with BIB_INSTALL_LIB exported by accident, where `return`
# at top level is an error and would abort under `set -e`.
if [[ "${BIB_INSTALL_LIB:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

# ---------------------------------------------------------------------------
# Mode: auto-update (FEAT-038 R7). Opt-in, never touched by an install or update.
# ---------------------------------------------------------------------------
if [[ "$AUTOUPDATE_MODE" -eq 1 ]]; then
    require_root
    _au_rc=0
    pin_autoupdate "${AUTOUPDATE_ARGS[@]}" || _au_rc=$?
    exit "$_au_rc"
fi

# ---------------------------------------------------------------------------
# Mode: selftest
# ---------------------------------------------------------------------------

do_selftest() {
    local guard="${SCRIPT_DIR%/payload}/tools/check-no-personal-refs.sh"
    # Locate the guard relative to the installed tree or the dev checkout.
    if [[ ! -x "$guard" ]]; then
        if [[ -x "/opt/buildersinabox/tools/check-no-personal-refs.sh" ]]; then
            guard="/opt/buildersinabox/tools/check-no-personal-refs.sh"
        else
            die "selftest: guard script not found at $guard or /opt/buildersinabox/tools/"
        fi
    fi
    log "selftest: running $guard"
    "$guard"
    # Verify state.json schema version (if state exists).
    if [[ -f "$BIB_STATE_FILE" ]]; then
        local ver
        ver="$(jq -r '.version' "$BIB_STATE_FILE")"
        if [[ "$ver" != "$BIB_STATE_SCHEMA_VERSION" ]]; then
            die "selftest: state.json schema is v${ver}, expected v${BIB_STATE_SCHEMA_VERSION}"
        fi
        log "selftest: state.json schema v${ver} OK"
    fi
    log "selftest: clean"
    exit 0
}

if [[ "$SELFTEST_MODE" -eq 1 ]]; then
    do_selftest
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

require_root
require_supported_os
# --skip-wizard never runs wizard/run.sh, so 35-ssh-finalize.sh (the only
# step that actually restricts sshd) can't run either — nothing for this
# preflight to protect against. Also skips CI/image-baking pipelines that
# run over SSH with neither a tty nor an ack.
# FEAT-029: the cloud profile never restricts sshd either, so the preflight has
# nothing to protect against there — and its whole premise ("you may lose this
# SSH session") is false on a box whose SSH we never touch.
if [[ "$SKIP_WIZARD" -ne 1 ]] && ! bib_profile_is_cloud; then
    check_ssh_install_preflight
fi

# FEAT-038: which versions this run installs. pinned = the ones this release was
# tested with; latest = the newest stable upstream (R5). Exported for 40/41/42/46.
# The warning comes before ANY installer runs, once. A box whose stack phase is
# already done would skip the installers and leave the warning a lie, so --latest
# re-runs the stack, as `biab update` does.
export BIB_PINS_MODE="pinned"
if [[ "$LATEST_MODE" -eq 1 ]]; then
    export BIB_PINS_MODE="latest"
    printf '\n%s\n\n' "$(bib_pins_latest_warning)"
fi

# ---------------------------------------------------------------------------
# Root-only host (typical fresh VPS): offer to create the human user
# ---------------------------------------------------------------------------
# bib_user_resolve refuses to operate as root because the workspace it
# scaffolds belongs to a human account. On a fresh DigitalOcean/Hetzner box
# you're root with no other user — create one here instead of dying.

_resolved_user="${BIB_USER:-${SUDO_USER:-${USER:-}}}"
# Re-runs as plain root (ssh root@vps → biab / --update) must reuse the user
# already persisted in state.json instead of re-asking or dying.
if [[ -z "$_resolved_user" || "$_resolved_user" == "root" ]] && [[ -f "$BIB_STATE_FILE" ]]; then
    _state_user="$(jq -r '.bib_user // empty' "$BIB_STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$_state_user" ]]; then
        _resolved_user="$_state_user"
        export BIB_USER="$_state_user"
    fi
    unset _state_user
fi
if [[ -z "$_resolved_user" || "$_resolved_user" == "root" ]]; then
    _manual_hint="create one and re-run:
    adduser --gecos '' <username> && usermod -aG sudo <username>
    BIB_USER=<username> $0"
    if [[ "$NON_INTERACTIVE" -eq 1 || ! -r /dev/tty ]]; then
        die "running as root with no target user account. Either set BIB_USER=<existing user>, or ${_manual_hint}"
    fi
    printf '\nYou are running as root and this machine has no target user account.\n'
    printf 'Builders in a Box sets up the workspace for a regular user, not root.\n'
    printf 'I can create that account now (you pick its password in the next step).\n'
    printf '\nUsername to create (lowercase; leave blank to abort): '
    _new_user=""
    read -r _new_user < /dev/tty || _new_user=""
    [[ -n "$_new_user" ]] || die "aborted. To do it by hand, ${_manual_hint}"
    [[ "$_new_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
        || die "'${_new_user}' is not a valid username (lowercase letters, digits, - and _)."
    if getent passwd "$_new_user" >/dev/null; then
        log "install: user ${_new_user} already exists, using it"
    else
        useradd -m -s /bin/bash -G sudo "$_new_user" \
            || die "could not create user ${_new_user}"
        log "install: created user ${_new_user} (in sudo group; password set by the wizard)"
    fi
    export BIB_USER="$_new_user"
    unset _new_user
fi
unset _resolved_user _manual_hint

# ---------------------------------------------------------------------------
# Interactive identity prompt
# ---------------------------------------------------------------------------
# On a first-time interactive install, ask the operator for their name so
# the wizard banner can greet them. BIB_USER auto-resolves from SUDO_USER
# silently (no need to ask — they're already logged in as themselves).
# BIB_NAME is the only one we surface to the operator because there's no
# system source for it.
#
# Skipped when: --non-interactive is set, state.json already exists
# (re-runs and --update), BIB_NAME is already provided via env.

if [[ "$NON_INTERACTIVE" -eq 0 && ! -f "$BIB_STATE_FILE" && -z "${BIB_NAME:-}" ]]; then
    printf '\nWhat name should the wizard greet you by? '
    printf '(leave blank to skip the personalised line) '
    printf '\n> '
    # Read from /dev/tty, not stdin — under `curl | sudo bash` stdin is the
    # script pipe (already at EOF), so a plain read would silently skip.
    if [[ -r /dev/tty ]]; then
        read -r BIB_NAME < /dev/tty || BIB_NAME=""
    else
        read -r BIB_NAME || BIB_NAME=""
    fi
    export BIB_NAME
fi

# The gift flavor's welcome copy refers to the operator by name without
# a fallback — selecting gift flavor without BIB_NAME would render an
# odd "..., ." line. Fail fast with a clear error.
if [[ "${BIB_FLAVOR:-default}" == "gift" && -z "${BIB_NAME:-}" ]]; then
    die "BIB_FLAVOR=gift requires BIB_NAME to be set (the personalised welcome refers to it). Either set BIB_NAME or use --flavor=default."
fi

state_init

# FEAT-029: resolve and persist the install profile immediately after state
# exists. Every SSH-touching step downstream reads it from state.json, which
# is what makes it survive `biab update` re-running this installer with no
# arguments at all.
bib_profile_persist

# Source the flavor manifest (created by Wave 2 FEAT-006 T4). Until that
# directory exists, this is a no-op — install still works with the default
# wizard heredocs.
BIB_FLAVOR_RESOLVED="$(bib_flavor_resolve)"
export BIB_FLAVOR_RESOLVED
BIB_INSTALL_ROOT="${SCRIPT_DIR%/payload}"
export BIB_INSTALL_ROOT
_flavor_manifest="${SCRIPT_DIR}/flavors/${BIB_FLAVOR_RESOLVED}/manifest.sh"
if [[ -f "$_flavor_manifest" ]]; then
    # shellcheck source=/dev/null
    source "$_flavor_manifest"
fi
unset _flavor_manifest

# Render systemd autologin drop-in from its .in template, substituting
# ${BIB_USER}. Idempotent — re-renders even if the file already exists
# so --update keeps the autologin user in sync with state.json.
#
# ISO/USB path only. There, the autoinstall hands over a box nobody has ever
# logged into, and autologin on tty1 is what lets the first-boot wizard run at
# all (see profile.d/biab-firstboot.sh). The ISO renders this file itself in
# user-data's late-commands; we re-render so --update can follow a changed
# bib_user.
#
# On a `curl | sudo bash` install we must NOT touch it: the user is already at
# a shell, so autologin buys nothing, and switching their console to
# passwordless login is a physical-access downgrade they never asked for. The
# firstboot trigger is the ISO's fingerprint — it exists on no other path.
_autologin_in="${SCRIPT_DIR}/systemd/getty@tty1.service.d/autologin.conf.in"
_autologin_out="/etc/systemd/system/getty@tty1.service.d/autologin.conf"
#
# Gate on the trigger ALONE. An earlier version also proceeded when an
# autologin.conf already existed, meaning a machine that had set up its own
# tty1 autologin (a common kiosk recipe) got it silently rewritten to our user
# — the exact clobber this change exists to stop. The trigger is never removed
# after first boot, so ISO boxes stay managed across --update regardless.
_firstboot_trigger="/etc/profile.d/biab-firstboot.sh"
if [[ ! -e "$_firstboot_trigger" ]]; then
    log "install: not an ISO/first-boot install, leaving tty1 autologin alone"
elif [[ -f "$_autologin_in" ]] && command -v envsubst >/dev/null 2>&1; then
    BIB_USER_RESOLVED="$(state_get '.bib_user')"
    : "${BIB_USER_RESOLVED:=$(bib_user_resolve)}"
    mkdir -p "$(dirname "$_autologin_out")"
    BIB_USER="$BIB_USER_RESOLVED" envsubst '${BIB_USER}' < "$_autologin_in" > "${_autologin_out}.tmp"
    mv "${_autologin_out}.tmp" "$_autologin_out"
    chmod 0644 "$_autologin_out"
    log "install: autologin rendered for user=${BIB_USER_RESOLVED}"
    unset BIB_USER_RESOLVED
fi
unset _autologin_in _autologin_out _firstboot_trigger

# Resolve the chosen CLI. An explicit choice (flag / env / state file) wins.
# Without one, ASK before persisting: silently persisting the default here
# used to make the wizard's 05-choose-cli step always skip (it honours
# state.ai_cli), so interactive users never actually got the choice the
# README promises.
if [[ "$NON_INTERACTIVE" -eq 0 && -z "$AI_CLI_ARG" && -z "${BIB_AI_CLI:-}" \
      && -z "$(state_get '.ai_cli')" ]]; then
    printf '\n'
    cat <<'EOF'
Pick the AI coding CLI this box will run.
All of them sign in from your phone:
EOF
    # Menu lines come from the registry, so a newly registered CLI shows up
    # here without touching this file.
    for _cli in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
        printf '  - %-13s%s\n' "$_cli" "$(ai_cli_choice_hint "$_cli")"
    done
    unset _cli
    if prompt_choice "Which one?" "${BIB_SUPPORTED_AI_CLIS[@]}"; then
        AI_CLI_ARG="$BIB_PROMPT_VALUE"
    else
        warn "install: no interactive input available — defaulting to ${BIB_SUPPORTED_AI_CLIS[0]} (use --ai-cli=antigravity to override)"
        AI_CLI_ARG="${BIB_SUPPORTED_AI_CLIS[0]}"
    fi
fi
CHOSEN_CLI="$(ai_cli_resolve "$AI_CLI_ARG")"
ai_cli_persist "$CHOSEN_CLI"

log "install: ai_cli=${CHOSEN_CLI} flavor=${BIB_FLAVOR_RESOLVED} force=${FORCE} skip_wizard=${SKIP_WIZARD} non_interactive=${NON_INTERACTIVE} update=${UPDATE_MODE}"

if [[ "$FORCE" -eq 1 ]]; then
    log "install: --force given, resetting wizard phases"
    for phase in tailscale_done ai_cli_done scaffold_done paseo_done; do
        phase_reset "$phase"
    done
fi

# ---------------------------------------------------------------------------
# Install stack
# ---------------------------------------------------------------------------

run_install() {
    local script="$1"
    local full="${SCRIPT_DIR}/${script}"
    [[ -x "$full" ]] || die "install script not executable or missing: $script"
    log "install: running ${script}"
    "$full"
}

if [[ "$LATEST_MODE" -eq 1 ]]; then
    phase_reset "stack_installed"
    # Off-pin is recorded now, not at the end: an installer that dies half way must still
    # leave the box marked (biab status, /morning-check) as off the tested versions.
    bib_pins_begin_latest
fi
if phase_is_done "stack_installed"; then
    log "install: stack already installed, skipping (use --force to re-run wizard, or remove state.json to fully reinstall)"
else
    run_install "install/00-base.sh"
    run_install "install/05-biab-command.sh"
    run_install "install/06-bd-cli.sh"
    run_install "install/20-tailscale.sh"
    run_install "install/30-gh.sh"
    run_install "$(ai_cli_install_script "$CHOSEN_CLI")"
    # SSH first: it is the way in that needs nothing else, and 46-paseo.sh
    # downloads ~560 MB and dies on a flaky network. A failed Paseo install
    # must never leave the box without its SSH setup (FEAT-035 review).
    run_install "install/50-ssh.sh"
    run_install "install/46-paseo.sh"
    run_install "install/47-cli-guard.sh"
    phase_done "stack_installed"
    bib_pins_record
fi

# ---------------------------------------------------------------------------
# Wizard
# ---------------------------------------------------------------------------

if [[ "$SKIP_WIZARD" -eq 1 ]]; then
    log "install: --skip-wizard, exiting after stack install"
    exit 0
fi

if [[ -x "${SCRIPT_DIR}/wizard/run.sh" ]]; then
    log "install: launching wizard"
    "${SCRIPT_DIR}/wizard/run.sh"
else
    log "install: wizard not found at ${SCRIPT_DIR}/wizard/run.sh"
    exit 0
fi
