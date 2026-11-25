#!/usr/bin/env bash
# Wizard step: log into the chosen AI CLI (claude, antigravity, codex or opencode).
#
# This step runs AFTER 36-phone-bridge, which means we are guaranteed to
# be in an SSH session (the user moved to their phone's Termius) where
# copy-paste between the terminal and the mobile browser actually works.
#
#   - claude:      `claude auth login --claudeai` prints a URL + short code,
#                  then returns automatically once the user approves.
#   - antigravity: agy 1.1.0 has NO `agy auth login` subcommand. Login is
#                  the TUI itself: launch `agy`, pick "Google OAuth", it
#                  prints a long OAuth URL, the user signs in on their phone
#                  and pastes the authorization code back (spike T1).
#
#   - codex:       `codex login --device-auth` (device code).
#   - opencode:    `opencode auth login`, a TUI menu where the user pastes an
#                  API key from opencode.ai/auth (or picks another provider).
#                  It needs a real terminal: with none attached the adapter
#                  pauses (exit 78), and so does a cancelled login (R11).
#
# Skipped if the phase is already done. Mock mode short-circuits cleanly.

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

if phase_is_done "ai_cli_done"; then
    log "38-ai-cli-login: already done, skipping"
    exit 0
fi

mapfile -t clis < <(ai_cli_resolve_list "")
cli="${clis[0]}"
target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"

# Mock mode: short-circuit without launching the CLI.
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "38-ai-cli-login: mock mode, marking ai_cli_done"
    phase_done "ai_cli_done"
    exit 0
fi

# Primary CLI login (mandatory).
verify_cmd="$(ai_cli_login_verify_cmd "$cli" "$target_user")"

if bash -c "$verify_cmd"; then
    log "38-ai-cli-login: $cli already logged in for $target_user"
else
    # 05-choose-cli.sh may have shown this step's header a moment ago: then carry on
    # below it instead of clearing the screen and printing it again.
    if [[ -e "${BIB_STATE_DIR}/step4-header-shown" ]]; then
        rm -f "${BIB_STATE_DIR}/step4-header-shown"
    else
        wizard_clear
        wizard_step_header 4 6 "$(msg wizard.title.ai)" "$(msg wizard.eta.min3)"
    fi
    msg wizard.login.intro "$(ai_cli_display_name "$cli")" "$(ai_cli_account_hint "$cli")"

    # Intro copy + the CLI's interactive login flow, from the adapter.
    ai_cli_login_run "$cli" "$target_user"

    # Verify with a 3-second retry to account for token-flush delays. On repeat
    # failure, die with the CLI's own recovery hint (never hang waiting for an
    # impossible local browser — EARS Unwanted).
    if ! bash -c "$verify_cmd"; then
        log "38-ai-cli-login: $cli verification failed on first attempt, waiting 3s and retrying"
        sleep 3
        if ! bash -c "$verify_cmd"; then
            die "$(ai_cli_login_failure_hint "$cli" "$target_user")"
        fi
    fi

    log "38-ai-cli-login: $cli authenticated for $target_user"
    msg_ok wizard.login.done "$(ai_cli_display_name "$cli")"
fi

phase_done "ai_cli_done"

# Secondary CLIs (FEAT-048 R4, R10): run in order, skippable, non-fatal on failure.
_idx=1
while [[ "$_idx" -lt "${#clis[@]}" ]]; do
    scli="${clis[$_idx]}"
    _idx=$((_idx + 1))
    sverify="$(ai_cli_login_verify_cmd "$scli" "$target_user")"
    if bash -c "$sverify"; then
        log "38-ai-cli-login: secondary $scli already logged in for $target_user"
        msg wizard.login.already "$(ai_cli_display_name "$scli")"
        continue
    fi
    msg wizard.login.secondary_intro "$(ai_cli_display_name "$scli")" "$(ai_cli_account_hint "$scli")"
    msg wizard.login.secondary_ask
    _sans=""
    _bib_read_line _sans || _sans="s"
    _sans="${_sans//[[:space:]]/}"
    case "${_sans,,}" in
        s|skip|saltar)
            log "38-ai-cli-login: skipped secondary $scli"
            msg wizard.login.secondary_skipped "$(ai_cli_display_name "$scli")" "$scli"
            continue
            ;;
    esac
    ( ai_cli_login_run "$scli" "$target_user" ) || true
    if ! bash -c "$sverify"; then
        sleep 3
        if ! bash -c "$sverify"; then
            log "38-ai-cli-login: secondary $scli verification failed (continuing)"
            msg wizard.login.secondary_failed "$(ai_cli_display_name "$scli")" "$scli"
            continue
        fi
    fi
    log "38-ai-cli-login: secondary $scli authenticated for $target_user"
    msg_ok wizard.login.done "$(ai_cli_display_name "$scli")"
done
