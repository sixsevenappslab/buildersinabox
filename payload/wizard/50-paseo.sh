#!/usr/bin/env bash
# Wizard step: start the user's first agent in Paseo and guide pairing the
# phone app (FEAT-035). Every CLI that runs under Paseo with its permission
# prompts on (claude, codex, antigravity, and OpenCode while its seeded rules
# hold) gets it; a CLI that does not stops
# here and is shown the SSH way in (see paseo_supports_cli in lib/paseo.sh).
#
# Pairing is allowed to fail: a skipped or failed pairing still finishes the
# wizard, prints how to pair later, and the SSH way in keeps working (R13).
# The phone password is printed with printf only; log()/warn() write to the
# world-writable bootstrap.log and must never see it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"
# shellcheck source=../lib/paseo.sh
source "${SCRIPT_DIR}/../lib/paseo.sh"

# paseo_wait_ready, paseo_ensure_workspace and paseo_print_pairing live in
# lib/paseo.sh: the project helper and the update-time migration share them.

# Start the first agent unless one with our title already exists. The prompt is
# natural language and the provider comes from the registry.
paseo_ensure_agent() {
    local user="$1" home="$2" cli="$3" ws_id="$4" ws_path="$5"
    if paseo_run_as "$user" "$home" ls --json \
        | jq -e --arg t "$PASEO_AGENT_TITLE" 'any(.[]; .name == $t)' >/dev/null; then
        log "50-paseo: agent '${PASEO_AGENT_TITLE}' already exists, not starting another"
        return 0
    fi
    local -a runner
    # Test seam: honoured ONLY in test mode, like every other seam in lib/paseo.sh,
    # so a stray env var can never swap the real `paseo run` for something else.
    if [[ "${BIB_PASEO_TEST:-0}" == "1" && -n "${BIB_PASEO_RUN_CMD:-}" ]]; then
        read -ra runner <<<"$BIB_PASEO_RUN_CMD"   # dryrun/test stand-in for `paseo run`
    else
        runner=(paseo_run_as "$user" "$home" run)
    fi
    "${runner[@]}" --provider "$(ai_cli_paseo_provider "$cli")" --cwd "$ws_path" \
        --workspace "$ws_id" "$PASEO_RUN_BACKGROUND_FLAG" --title "$PASEO_AGENT_TITLE" \
        --json "$(ai_cli_initial_prompt "$cli")" >/dev/null
}

# True when an authenticated app from another device has connected since the
# baseline <before> (the count taken before the pairing values were shown, so a
# hello from an earlier attempt or session is not mistaken for this phone). The
# box's own CLI connects from the box's own tailnet address, so any other
# remote address is a phone. Reads the daemon log (no secrets in it) through
# paseo_foreign_hellos, which refuses a symlinked log and an unknown own address.
paseo_phone_seen() {
    local home="$1" own="$2" before="${3:-0}" now
    now="$(paseo_foreign_hellos "${home}/daemon.log" "$own")"
    (( now > before ))
}

# Guide the pairing. Returns 0 once the phone is seen, 1 if the user skips,
# input ends, or three attempts find nothing. Never blocks past the user's input.
paseo_pairing_guide() {
    local home="$1" host="$2" own="$3"
    local attempts=0 answer waited before
    local wait_max="${BIB_PASEO_PAIR_WAIT:-15}"
    before="$(paseo_foreign_hellos "${home}/daemon.log" "$own")"
    printf 'Install the Paseo app on your phone from its app store.\n\n'
    paseo_print_pairing "$host"
    while (( attempts < 3 )); do
        printf 'When the app shows your box, press Enter.\nType s to skip and pair later.\n> '
        answer=""
        _bib_read_line answer || { printf '\n'; return 1; }
        [[ "${answer,,}" == s* ]] && return 1
        waited=0
        while :; do
            paseo_phone_seen "$home" "$own" "$before" && return 0
            (( waited >= wait_max )) && break
            sleep 1
            waited=$((waited + 1))
        done
        attempts=$((attempts + 1))
        printf 'The box does not see your phone yet. Check the password,\nthat Tailscale is on, and that "Use SSL" is off.\n\n'
    done
    return 1
}

paseo_step_main() {
    require_root

    if phase_is_done "paseo_done"; then
        log "50-paseo: already done, skipping"
        return 0
    fi

    local cli user user_home
    cli="$(ai_cli_resolve "")"
    user="${BIB_TARGET_USER:-$(bib_user_resolve)}"
    user_home="$(getent passwd "$user" | cut -d: -f6)"
    if ! paseo_supports_cli "$cli"; then
        warn "50-paseo: $cli does not run under Paseo on this box"
        printf '%s does not run in the Paseo app yet.\n\n' "$(ai_cli_display_name "$cli")"
        # A CLI whose own defaults allow everything runs in the app only while its
        # settings make it ask first; say which rule is not holding (R9).
        _why="$(paseo_not_permissioned_reason "$cli" 2>/dev/null || true)"
        if [[ -n "$_why" ]]; then
            printf '%s runs in the app only while its own settings make it ask before it edits\nfiles or runs commands. Right now: %s\nFix that and run "biab" again.\n\n' \
                "$(ai_cli_display_name "$cli")" "$_why"
        fi
        paseo_ssh_fallback_text "$cli" "$user" "$(hostname)"
        return 1
    fi

    local home ws_path host pair_host own_addr ws_id paired=0
    home="$(paseo_home_for "$user_home")"
    ws_path="${user_home}/ai-platform"
    [[ -d "$ws_path" ]] || die "50-paseo: ${ws_path} does not exist (40-scaffold should have created it)"
    host="$(hostname)"

    wizard_step_header 6 6 "Open your box in the app" "2 minutes"
    printf 'Starting your first agent...\n\n'

    if ! paseo_wait_ready "$user" "$home"; then
        warn "50-paseo: the Paseo daemon did not answer within ${BIB_PASEO_READY_TIMEOUT:-120}s"
        printf 'The app service is not answering yet.\n\n'
        paseo_ssh_fallback_text "$cli" "$user" "$host"
        return 1
    fi
    ws_id="$(paseo_ensure_workspace "$user" "$home" "$ws_path")" \
        || die "50-paseo: could not create the workspace for ${ws_path}"
    paseo_ensure_agent "$user" "$home" "$cli" "$ws_id" "$ws_path" \
        || die "50-paseo: could not start the first agent"
    log "50-paseo: first agent running in workspace ${ws_id}"

    own_addr="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    pair_host="$(paseo_pair_host)"
    if paseo_pairing_guide "$home" "$pair_host" "$own_addr"; then
        paired=1
        install -d -m 0755 "$PASEO_HEALTH_DIR"
        install -m 0644 /dev/null "${PASEO_HEALTH_DIR}/paired"
        log "50-paseo: phone paired"
    else
        printf '\nNo problem. To pair later, run this on the box:\n\n%s\n\n' "$PASEO_PAIR_LATER_CMD"
        log "50-paseo: pairing skipped or not completed; the user can pair later"
    fi

    phase_done "paseo_done"
    log "50-paseo: done (paired=${paired})"
}

if [[ "${BIB_PASEO_STEP_LIB:-0}" != "1" ]]; then
    paseo_step_main
fi
