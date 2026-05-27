#!/usr/bin/env bash
# Wizard step: pause the console flow so the user moves to their phone.
#
# This is the BIG MOMENT where Paco switches from the mini PC console
# to his phone. Done well, it's the moment the gift starts feeling real
# ("oh, I can use this from my pocket"). Done poorly, it's where setup
# stalls. So this step is patient: it walks through each phone-side
# task and waits for confirmation before moving to the next.
#
# Behavior depends on the controlling TTY:
#   - /dev/tty1 (console autologin)  -> walk through the 3-step phone
#                                       setup with confirmations,
#                                       then exit 78 to pause the chain.
#   - /dev/pts/N (SSH session)       -> log + exit 0, continue.
#   - BIB_OAUTH_MOCK=1               -> skip entirely (tests).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root

if phase_is_done "ai_cli_done"; then
    log "36-phone-bridge: ai_cli_done already set, skipping bridge"
    exit 0
fi

if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "36-phone-bridge: mock mode, skipping bridge"
    exit 0
fi

current_tty="$(tty 2>/dev/null || echo unknown)"
case "$current_tty" in
    /dev/pts/*)
        log "36-phone-bridge: running via SSH ($current_tty), continuing"
        exit 0
        ;;
esac

# --- We're on console. Walk through the 3 phone setup steps. ---------------

target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"
hostname_val="$(hostname)"
ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || echo '')"

prompt_header "Switch to your phone"
cat <<'EOF'
Now the fun part. We're going to move you to your phone, where the
rest of setup is easier (copy-paste actually works on a phone keyboard).

Two apps to install, then you SSH back into this device from your phone.
Five minutes, give or take. Take your phone now — we'll go step by step.
EOF

# ---- Step 1 of 3: Tailscale -----------------------------------------------
printf '\n%s+---------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sStep 1 of 3 — Install Tailscale on your phone%s    %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+---------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<'EOF'

  What it is: a small free app that puts your phone on a private
  network with this device. Like a Wi-Fi just for your gadgets.

  Do this on your phone:
    1. Open the App Store / Google Play
    2. Search "Tailscale" — by Tailscale Inc.
    3. Install. Open the app.
    4. Tap "Get started", sign in with the SAME account you used
       earlier in this wizard (when you authorised this device).
       (If you signed in with Google, use Google. If GitHub, GitHub. Same one.)
    5. The app shows your devices. You should see one called "biab"
       — that's this mini PC.

EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '  %s...or scan to open the Tailscale download page:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://tailscale.com/download" 2>/dev/null | sed 's/^/    /'
fi
printf '\n'
prompt_confirm "Press Enter once Tailscale is installed AND you see 'biab' in your tailnet."

# ---- Step 2 of 3: Termius + host config -----------------------------------
printf '\n%s+---------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sStep 2 of 3 — Install Termius and connect%s        %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+---------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF

  What it is: an SSH terminal app for your phone. We'll use it to log
  into this device's command line from your phone.

  Do this on your phone:
    1. Open the App Store / Google Play
    2. Search "Termius" — by Termius Corporation
    3. Install. Open it. (You can skip "Create a Termius account" — tap "Skip".)
    4. Tap the "+" button, then "New Host". Fill in:

         Alias     : biab
         Hostname  : ${hostname_val}
EOF
if [[ -n "$ts_ip" ]]; then
    printf '                     %s(if "biab" does not connect, try: %s)%s\n' \
        "${BIB_DIM:-}" "$ts_ip" "${BIB_RESET:-}"
fi
cat <<EOF
         Username  : ${target_user}
         Password  : (leave blank)
         SSH Key   : (leave blank)

    5. Save the host. Tap it. After a 2-3 second pause you should see:

         ${BIB_BOLD:-}${target_user}@${hostname_val}:~\$${BIB_RESET:-}

  If you see a "host key fingerprint" prompt, tap "Accept" / "Yes".
  If the connection times out, the most common cause is Tailscale on
  the phone is still connecting — wait 30s and try again.

EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '  %s...or scan to open the Termius download page:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://termius.com/download" 2>/dev/null | sed 's/^/    /'
fi
printf '\n'
prompt_confirm "Press Enter when you see the ${target_user}@${hostname_val}:~\$ prompt in Termius."

# ---- Step 3 of 3: Resume from SSH -----------------------------------------
printf '\n%s+---------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sStep 3 of 3 — Resume this wizard from Termius%s    %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+---------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF

  You're now in Termius, looking at ${target_user}@${hostname_val}:~\$ on your phone.

  In that Termius prompt, type this command (long-press to paste also works):
EOF
printf '\n       %ssudo /opt/buildersinabox/payload/bootstrap.sh%s\n\n' \
    "${BIB_BOLD:-}${BIB_BRIGHT_YELLOW:-}" "${BIB_RESET:-}"
cat <<'EOF'
  The wizard picks up from where we paused. The remaining steps:
    - GitHub login  (short URL + 8-char code, easy in Termius)
    - Claude login  (long URL — long-press to copy into your browser)
    - Workspace setup + tmux session (no input needed)
    - Final 'All set' message with the Claude Code app QR

  When that's done, you install the Claude Code app from the QR, sign
  in with the same Claude account, and your three sessions appear.
  Tap any of them — you're inside Claude, talking to it from your phone.

  You can unplug the monitor and keyboard from this device now,
  or leave them as they are. We're done with the console.
EOF

echo
exit 78
