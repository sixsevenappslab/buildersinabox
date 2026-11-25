#!/usr/bin/env bash
# Wizard step: confirm or pick the AI CLI. Persists the choice in state.json.
#
# Two cases (FEAT-046 H4):
#   - state.ai_cli is empty: show the menu and persist the pick. install.sh asks
#     before the stack install, so this is only a fallback for old state files.
#   - state.ai_cli is already set (install.sh asked, or a flag or the cloud
#     renderer fixed it): before the login, say which CLI that is and which
#     account it needs, and let the user continue or choose another. This is
#     only offered while no CLI login has happened, with a console attached,
#     and when the CLI was not forced with BIB_AI_CLI. Choosing another CLI
#     installs it now by re-running the stack steps that depend on the CLI;
#     the first CLI stays installed and is harmless.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"
# shellcheck source=../lib/oauth.sh
source "${SCRIPT_DIR}/../lib/oauth.sh"

# Install the pieces that depend on the CLI: the CLI itself, the Paseo daemon
# gate (46 installs or tears down by CLI) and the guard. Every one is
# idempotent and reads the CLI set from state.json. Detail goes to the log file.
# Optional $2="soft" returns non-zero instead of dying (used for secondary CLIs
# per FEAT-048 R10 so a failing secondary never blocks setup).
# Test seam, honoured ONLY with BIB_ONBOARDING_TEST=1 (this runs as root):
# BIB_CHOOSE_CLI_STEPS overrides the list of scripts (absolute paths).
choose_cli_install() {
    local cli="$1" mode="${2:-hard}" script rc=0
    local -a steps
    if [[ "${BIB_ONBOARDING_TEST:-0}" == "1" && -n "${BIB_CHOOSE_CLI_STEPS:-}" ]]; then
        read -ra steps <<<"$BIB_CHOOSE_CLI_STEPS"
    else
        steps=("$(ai_cli_install_script "$cli")" "install/46-paseo.sh" "install/47-cli-guard.sh")
    fi
    msg wizard.cli.installing "$(ai_cli_display_name "$cli")"
    for script in "${steps[@]}"; do
        [[ "$script" == /* ]] || script="${SCRIPT_DIR}/../${script}"
        [[ -x "$script" ]] || die "05-choose-cli: install step not executable: ${script}"  # i18n-ok: maintainer diagnostic
        log "05-choose-cli: running ${script} for ${cli}"
        rc=0
        "$script" >>"$BIB_LOG_FILE" 2>&1 || rc=$?
        if [[ "$rc" -ne 0 ]]; then
            if [[ "$mode" == "soft" ]]; then
                msg_warn wizard.cli.secondary_install_failed "$(ai_cli_display_name "$cli")" "$rc" "$BIB_LOG_FILE" "$cli"
                return "$rc"
            fi
            die "$(msg wizard.cli.install_failed "$script" "$cli" "$rc" "$BIB_LOG_FILE")"
        fi
    done
    msg_ok wizard.cli.installed "$(ai_cli_display_name "$cli")"
}

choose_cli_main() {
    local current pending current_csv
    current="$(state_get '.ai_cli')"

    # A switch that did not finish installing (an install step failed, or the
    # wizard was interrupted) is finished first. The new CLI is already the one
    # in state.json, so without this stamp a retry would take it for installed
    # and go on to a login with nothing there.
    pending="$(state_get '.cli_switch_pending')"
    if [[ -n "$pending" && "$pending" != "null" && "$pending" == "$current" ]]; then
        choose_cli_install "$current"
        state_set '.cli_switch_pending' 'null'
        return 0
    fi

    if [[ -z "$current" || "$current" == "null" ]]; then
        prompt_header "$(msg wizard.cli.menu_title)"
        msg wizard.cli.menu_intro
        ai_cli_menu_labels
        prompt_multi_choice "$(msg wizard.cli.multi_pick)" "${BIB_SUPPORTED_AI_CLIS[0]}" "${BIB_SUPPORTED_AI_CLIS[@]}" || die "05-choose-cli: aborted"  # i18n-ok: maintainer diagnostic
        ai_cli_persist_list "${BIB_PROMPT_VALUES[@]}"
        log "05-choose-cli: chose ${BIB_PROMPT_VALUES[*]}"
        return 0
    fi

    # Already chosen. Confirm / expand only when it can still change: nothing
    # logged in yet, somebody to answer, and no one forced it from outside.
    if phase_is_done "ai_cli_done" || oauth_is_mocked || [[ -n "${BIB_AI_CLI:-}" ]] \
        || ! _oauth_console_attached; then
        log "05-choose-cli: ai_cli already = $current, not asking"
        return 0
    fi
    ai_cli_validate "$current"

    local -a preset_clis=()
    local _c
    while IFS= read -r _c; do
        [[ -n "$_c" ]] && preset_clis+=("$_c")
    done < <(ai_cli_list)
    [[ ${#preset_clis[@]} -gt 0 ]] || preset_clis=("$current")
    current_csv="$(IFS=,; printf '%s' "${preset_clis[*]}")"

    wizard_clear
    wizard_step_header 4 6 "$(msg wizard.title.ai)" "$(msg wizard.eta.min3)"
    # Tell 38-ai-cli-login.sh this screen is already showing the step header, so
    # the login does not clear it and print "Step 4 of 6" a second time.
    : > "${BIB_STATE_DIR}/step4-header-shown"

    # The card below shows each CLI's account, so no single account is named
    # here before the owner has chosen (FEAT-048/049).
    local _names="" _pc
    for _pc in "${preset_clis[@]}"; do _names+="${_names:+, }$(ai_cli_display_name "$_pc")"; done
    msg wizard.cli.multi_intro "$_names"
    ai_cli_menu_labels
    prompt_multi_choice "$(msg wizard.cli.multi_pick)" "$current_csv" "${BIB_SUPPORTED_AI_CLIS[@]}" \
        || die "05-choose-cli: aborted"  # i18n-ok: maintainer diagnostic

    local -a picked=("${BIB_PROMPT_VALUES[@]}")
    local picked_csv
    picked_csv="$(IFS=,; printf '%s' "${picked[*]}")"

    if [[ "$picked_csv" == "$current_csv" ]]; then
        log "05-choose-cli: confirmed $current_csv"
        msg_ok wizard.cli.confirmed "$(ai_cli_display_name "${picked[0]}")"
        # Now that the choice is made, name the account its login needs.
        msg wizard.cli.need "$(ai_cli_account_hint "${picked[0]}")"
        return 0
    fi

    # Determine which CLIs are newly added (not already in preset_clis).
    # Install each new CLI binary before persisting it into .ai_clis so a failed
    # secondary never leaks into state.json or breaks an earlier CLI's 46-paseo
    # preflight (e.g. antigravity selected after codex).
    local -a kept=()
    local preset_set=" ${preset_clis[*]} "
    local idx=0
    state_set '.cli_switch_pending' "\"${picked[0]}\""
    for _c in "${picked[@]}"; do
        if [[ "$preset_set" == *" $_c "* ]]; then
            kept+=("$_c")
        else
            if [[ "${BIB_ONBOARDING_TEST:-0}" == "1" && -n "${BIB_CHOOSE_CLI_STEPS:-}" ]]; then
                if [[ "$idx" -eq 0 ]]; then
                    ai_cli_persist_list "$_c"
                    choose_cli_install "$_c" hard
                    kept+=("$_c")
                else
                    if choose_cli_install "$_c" soft; then
                        kept+=("$_c")
                    fi
                fi
            else
                local _bin_step rc_bin=0
                _bin_step="${SCRIPT_DIR}/../$(ai_cli_install_script "$_c")"
                [[ -x "$_bin_step" ]] || die "05-choose-cli: install step not executable: ${_bin_step}"  # i18n-ok: maintainer diagnostic
                msg wizard.cli.installing "$(ai_cli_display_name "$_c")"
                log "05-choose-cli: running ${_bin_step} for ${_c}"
                "$_bin_step" >>"$BIB_LOG_FILE" 2>&1 || rc_bin=$?
                if [[ "$rc_bin" -ne 0 ]]; then
                    if [[ "$idx" -eq 0 ]]; then
                        die "$(msg wizard.cli.install_failed "$_bin_step" "$_c" "$rc_bin" "$BIB_LOG_FILE")"
                    fi
                    msg_warn wizard.cli.secondary_install_failed "$(ai_cli_display_name "$_c")" "$rc_bin" "$BIB_LOG_FILE" "$_c"
                else
                    msg_ok wizard.cli.installed "$(ai_cli_display_name "$_c")"
                    kept+=("$_c")
                fi
            fi
        fi
        idx=$((idx + 1))
    done
    ai_cli_persist_list "${kept[@]}"
    if [[ ! ( "${BIB_ONBOARDING_TEST:-0}" == "1" && -n "${BIB_CHOOSE_CLI_STEPS:-}" ) ]]; then
        local _post rc_post=0
        for _post in "install/46-paseo.sh" "install/47-cli-guard.sh"; do
            local _post_path="${SCRIPT_DIR}/../${_post}"
            [[ -x "$_post_path" ]] || die "05-choose-cli: install step not executable: ${_post_path}"  # i18n-ok: maintainer diagnostic
            log "05-choose-cli: running ${_post_path} for ${kept[*]}"
            rc_post=0
            "$_post_path" >>"$BIB_LOG_FILE" 2>&1 || rc_post=$?
            if [[ "$rc_post" -ne 0 ]]; then
                die "$(msg wizard.cli.install_failed "$_post_path" "${kept[0]}" "$rc_post" "$BIB_LOG_FILE")"
            fi
        done
    fi
    state_set '.cli_switch_pending' 'null'
    msg wizard.cli.need "$(ai_cli_account_hint "${kept[0]}")"
    prompt_confirm "$(msg wizard.confirm.continue)"
}

if [[ "${BIB_CHOOSE_CLI_LIB:-0}" != "1" ]]; then
    choose_cli_main
fi
