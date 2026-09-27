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
    wizard_step_header 3 6 "Continue remotely" "4 minutes"
    cat <<EOF
Use your laptop for the rest of setup.

1. Install Tailscale.
   Sign in with the same account:

https://tailscale.com/download

2. Open its terminal and connect:

ssh ${target_user}@${hostname_val}

If that name does not work, use:

ssh ${target_user}@${ts_ip}

3. In the SSH session, run:

biab
EOF
}

render_phone_bridge() {
    local target_user="$1" hostname_val="$2" ts_ip="$3"

    wizard_clear
    wizard_step_header 3 6 "Continue remotely" "4 minutes"
    cat <<'EOF'
On your phone, install Tailscale.
Sign in with the same account:

https://tailscale.com/download
EOF
    prompt_confirm "Press Enter when it says Connected."

    wizard_clear
    wizard_step_header 3 6 "Continue remotely" "4 minutes"
    cat <<'EOF'
Install an SSH app, such as Termius:

https://termius.com/download
EOF
    prompt_confirm "Press Enter when your SSH app is ready."

    wizard_clear
    wizard_step_header 3 6 "Continue remotely" "4 minutes"
    cat <<EOF
Create a new SSH connection with:

Host
${hostname_val}

Username
${target_user}

Password
The password you set in step 1.

If the host name does not work, use:

${ts_ip}

After connecting, run:

biab
EOF
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
    ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || echo 'your Tailscale IP')"

    wizard_clear
    wizard_step_header 3 6 "Continue remotely" "4 minutes"
    cat <<'EOF'
The next login is easier with copy and paste.
Choose your device. You will only see its instructions.
EOF
    prompt_choice "Where will you continue?" "Laptop (recommended)" "Phone" \
        || die "36-phone-bridge: no device selected"

    case "$BIB_PROMPT_VALUE" in
        "Laptop (recommended)") render_laptop_bridge "$target_user" "$hostname_val" "$ts_ip" ;;
        Phone) render_phone_bridge "$target_user" "$hostname_val" "$ts_ip" ;;
        *) die "36-phone-bridge: unexpected device choice" ;;
    esac

    printf '\nThe monitor is finished. Continue with the SSH session.\n'
    return 78
}

if [[ "${BIB_BRIDGE_LIB:-0}" != "1" ]]; then
    bridge_main
fi
