#!/usr/bin/env bash
# Wizard step: pause on the console and move the user to an SSH terminal.
# The next AI login has a long URL, so it belongs on a device with copy/paste.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

render_laptop_bridge() {
    local target_user="$1" hostname_val="$2" ts_ip="$3"
    wizard_clear
    wizard_step_header 3 6 "$(msg wizard.title.remote)" "$(msg wizard.eta.min4)"
    msg wizard.bridge.laptop "$target_user" "$hostname_val" "$target_user" "$ts_ip"
}

render_phone_bridge() {
    local target_user="$1" hostname_val="$2" ts_ip="$3"

    wizard_clear
    wizard_step_header 3 6 "$(msg wizard.title.remote)" "$(msg wizard.eta.min4)"
    msg wizard.bridge.phone1
    prompt_confirm "$(msg wizard.confirm.bridge_connected)"

    wizard_clear
    wizard_step_header 3 6 "$(msg wizard.title.remote)" "$(msg wizard.eta.min4)"
    msg wizard.bridge.phone2
    prompt_confirm "$(msg wizard.confirm.bridge_sshapp)"

    wizard_clear
    wizard_step_header 3 6 "$(msg wizard.title.remote)" "$(msg wizard.eta.min4)"
    msg wizard.bridge.phone3 "$hostname_val" "$target_user" "$ts_ip"
}

bridge_main() {
    require_root

    if phase_is_done "ai_cli_done"; then
        log "36-phone-bridge: ai_cli_done already set, skipping bridge"
        return 0
    fi
    if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
        log "36-phone-bridge: mock mode, skipping bridge"
        return 0
    fi

    local current_tty
    current_tty="$(tty 2>/dev/null || echo unknown)"
    log "36-phone-bridge: tty=$current_tty ssh_conn=${SSH_CONNECTION:-unset}"
    if wizard_is_ssh; then
        log "36-phone-bridge: SSH context detected, skipping bridge"
        return 0
    fi

    local target_user hostname_val ts_ip
    target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"
    hostname_val="$(hostname)"
    ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || msg wizard.bridge.ts_ip_fallback)"

    wizard_clear
    wizard_step_header 3 6 "$(msg wizard.title.remote)" "$(msg wizard.eta.min4)"
    msg wizard.bridge.pick
    local bridge_q bridge_laptop bridge_phone
    msg_str bridge_q wizard.bridge.question
    msg_str bridge_laptop wizard.bridge.opt_laptop
    msg_str bridge_phone wizard.bridge.opt_phone
    prompt_choice "$bridge_q" "$bridge_laptop" "$bridge_phone" \
        || die "36-phone-bridge: no device selected"  # i18n-ok: maintainer diagnostic

    case "$BIB_PROMPT_VALUE" in
        "$bridge_laptop") render_laptop_bridge "$target_user" "$hostname_val" "$ts_ip" ;;
        "$bridge_phone") render_phone_bridge "$target_user" "$hostname_val" "$ts_ip" ;;
        *) die "36-phone-bridge: unexpected device choice" ;;  # i18n-ok: maintainer diagnostic
    esac

    msg wizard.bridge.finished
    return 78
}

if [[ "${BIB_BRIDGE_LIB:-0}" != "1" ]]; then
    bridge_main
fi
