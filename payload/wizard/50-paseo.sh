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

# The address to put in an "ssh user@..." line: the tailnet IPv4, else the
# hostname. A cloud box's hostname is the provider's FQDN, which no other device
# can resolve (FEAT-046).
paseo_ssh_host() {
    local h
    h="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    [[ -n "$h" ]] || h="$(hostname)"
    printf '%s' "$h"
}

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
    msg wizard.paseo.pair_intro
    paseo_print_pairing "$host"
    while (( attempts < 3 )); do
        msg wizard.paseo.pair_ask
        answer=""
        _bib_read_line answer || { printf '\n'; return 1; }
        # Only these skip: a Spanish "si", "sí" or "siguiente" must not.
        answer="${answer#"${answer%%[![:space:]]*}"}"
        answer="${answer%"${answer##*[![:space:]]}"}"
        case "${answer,,}" in s|skip|saltar) return 1 ;; esac
        waited=0
        while :; do
            paseo_phone_seen "$home" "$own" "$before" && return 0
            (( waited >= wait_max )) && break
            sleep 1
            waited=$((waited + 1))
        done
        attempts=$((attempts + 1))
        msg wizard.paseo.pair_notseen
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
    # The app's CLI: the primary, or the first installed one that runs under
    # Paseo when the primary is SSH-only (FEAT-048). A forced BIB_AI_CLI keeps
    # the old single-CLI resolution.
    if [[ -n "${BIB_AI_CLI:-}" ]]; then
        cli="$(ai_cli_resolve "")"
    else
        cli="$(paseo_app_cli)"
        [[ -n "$cli" ]] || cli="$(ai_cli_resolve "")"
    fi
    user="${BIB_TARGET_USER:-$(bib_user_resolve)}"
    user_home="$(getent passwd "$user" | cut -d: -f6)"
    if ! paseo_supports_cli "$cli"; then
        warn "50-paseo: $cli does not run under Paseo on this box"  # i18n-ok: maintainer diagnostic
        msg wizard.paseo.no_app "$(ai_cli_display_name "$cli")"
        # A CLI whose own defaults allow everything runs in the app only while its
        # settings make it ask first; say which rule is not holding (R9).
        _why="$(paseo_not_permissioned_reason "$cli" 2>/dev/null || true)"
        if [[ -n "$_why" ]]; then
            msg wizard.paseo.not_permissioned "$(ai_cli_display_name "$cli")" "$_why"
        fi
        paseo_ssh_fallback_text "$cli" "$user" "$(paseo_ssh_host)"
        return 1
    fi

    local home ws_path host pair_host own_addr ws_id paired=0
    home="$(paseo_home_for "$user_home")"
    ws_path="${user_home}/ai-platform"
    [[ -d "$ws_path" ]] || die "50-paseo: ${ws_path} does not exist (40-scaffold should have created it)"  # i18n-ok: maintainer diagnostic
    host="$(paseo_ssh_host)"

    wizard_step_header 6 6 "$(msg wizard.title.app)" "$(msg wizard.eta.min2)"
    msg wizard.paseo.intro
    msg wizard.paseo.starting

    if ! paseo_wait_ready "$user" "$home"; then
        warn "50-paseo: the Paseo daemon did not answer within ${BIB_PASEO_READY_TIMEOUT:-120}s"  # i18n-ok: maintainer diagnostic
        msg wizard.paseo.not_answering
        paseo_ssh_fallback_text "$cli" "$user" "$host"
        return 1
    fi
    ws_id="$(paseo_ensure_workspace "$user" "$home" "$ws_path")" \
        || die "50-paseo: could not create the workspace for ${ws_path}"  # i18n-ok: maintainer diagnostic
    paseo_ensure_agent "$user" "$home" "$cli" "$ws_id" "$ws_path" \
        || die "50-paseo: could not start the first agent"  # i18n-ok: maintainer diagnostic
    log "50-paseo: first agent running in workspace ${ws_id}"

    own_addr="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    pair_host="$(paseo_pair_host)"
    if paseo_pairing_guide "$home" "$pair_host" "$own_addr"; then
        paired=1
        install -d -m 0755 "$PASEO_HEALTH_DIR"
        install -m 0644 /dev/null "${PASEO_HEALTH_DIR}/paired"
        log "50-paseo: phone paired"
    else
        log "50-paseo: pairing skipped or not completed; the user can pair later"
    fi
    # The password was shown on this screen once. Take it off the screen and
    # the scrollback, and say how to get it again (FEAT-046 H10).
    wizard_clear_secret
    if [[ "$paired" == "1" ]]; then
        msg_ok wizard.paseo.paired "$PASEO_PAIR_LATER_CMD"
    else
        msg wizard.paseo.pair_later "$PASEO_PAIR_LATER_CMD"
    fi

    # FEAT-048 R5: list any additional Paseo providers and any SSH-only CLIs.
    local -a _all_clis=() _extra_paseo=() _extra_ssh=()
    local _ec
    while IFS= read -r _ec; do
        [[ -n "$_ec" && "$_ec" != "$cli" ]] || continue
        _all_clis+=("$_ec")
        if paseo_supports_cli "$_ec"; then
            _extra_paseo+=("$(ai_cli_display_name "$_ec")")
        else
            _extra_ssh+=("$_ec")
        fi
    done < <(ai_cli_resolve_list "")
    if [[ ${#_extra_paseo[@]} -gt 0 ]]; then
        msg wizard.paseo.extra_providers "$(IFS=,; printf '%s' "${_extra_paseo[*]}" | sed 's/,/, /g')"
    fi
    for _ec in "${_extra_ssh[@]}"; do
        msg wizard.paseo.extra_ssh "$(ai_cli_display_name "$_ec")"
        paseo_ssh_fallback_text "$_ec" "$user" "$host"
    done

    prompt_confirm "$(msg wizard.confirm.continue)"

    phase_done "paseo_done"
    log "50-paseo: done (paired=${paired})"
}

if [[ "${BIB_PASEO_STEP_LIB:-0}" != "1" ]]; then
    paseo_step_main
fi
