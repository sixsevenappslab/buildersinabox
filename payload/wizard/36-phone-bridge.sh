#!/usr/bin/env bash
# Wizard step: pause the console flow so the user moves to a second
# device (phone OR laptop) and SSHs into this mini PC. Claude Code's
# /login generates a 500+ char OAuth URL that's impractical to copy
# from a console screen — but trivial from a real terminal where
# copy-paste works.
#
# This step offers TWO paths and lets the user pick whichever they
# have handy:
#
#   Path A — Laptop (easier if you have one)
#     install Tailscale app for Mac/Windows/Linux, open Terminal,
#     `ssh paco@biab`. Done.
#
#   Path B — Phone
#     install Tailscale + Termius/ConnectBot apps, configure host,
#     connect.
#
# Both paths end with the same command:
#     sudo /opt/buildersinabox/payload/bootstrap.sh
# …and the wizard resumes from where it paused.
#
# Behavior depends on the controlling TTY:
#   - /dev/tty1 (console autologin)  -> walk through both paths, exit 78
#   - /dev/pts/N (SSH session)       -> log + exit 0 (continue chain)
#   - BIB_OAUTH_MOCK=1               -> skip entirely (tests)

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

# Log the TTY we resolved for post-mortem debugging.
current_tty="$(tty 2>/dev/null || echo unknown)"
log "36-phone-bridge: tty=$current_tty"
case "$current_tty" in
    /dev/pts/*)
        log "36-phone-bridge: running via SSH ($current_tty), continuing"
        exit 0
        ;;
esac

# --- We're on the console. Walk through both bridge paths. ----------------

target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"
hostname_val="$(hostname)"
ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || echo '')"

prompt_header "Continue from your phone or your laptop"
cat <<'EOF'
The remaining steps (Claude login, project setup, tmux) are easier on a
device where copy-paste actually works — Claude's OAuth URL is too long
to type or scan from this monitor.

Both paths below work equally well. Phone is what this device is built
for day-to-day; laptop is just as valid here. Pick whichever you have
handy right now.

EOF

# ---- PATH A — Laptop -----------------------------------------------------
printf '%s+----- Path A — From your laptop -----+%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF

  Works on Mac, Windows 10+, or any Linux.

  Do this on your laptop:
    1. Open https://tailscale.com/download in any browser
       Install the Tailscale app for your OS. Sign in with the SAME
       Tailscale account you used in this wizard.

    2. Open a terminal:
         - Mac      : Terminal.app  (Cmd-Space, type "terminal")
         - Windows  : PowerShell or Windows Terminal
         - Linux    : your usual terminal

    3. In that terminal run:

EOF
printf '         %sssh %s@%s%s\n\n' "${BIB_BOLD:-}${BIB_BRIGHT_YELLOW:-}" "$target_user" "$hostname_val" "${BIB_RESET:-}"
cat <<EOF
       (If "$hostname_val" doesn't resolve, use the IP: $ts_ip)

       It asks for a password — that's the sudo password you just set.
       Once in, you'll see: ${target_user}@${hostname_val}:~\$
EOF

# ---- PATH B — Phone ------------------------------------------------------
printf '\n%s+----- Path B — From your phone -----+%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF

  Works on iOS or Android. Take your phone now.

  Step B.1 — Install Tailscale on your phone:
    - App Store / Google Play: search "Tailscale"
    - Sign in with the SAME account you used earlier
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n    %s...or scan to install Tailscale:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t ANSI256 -l L -m 2 "https://tailscale.com/download" 2>/dev/null | sed 's/^/      /'
fi

cat <<EOF

  Step B.2 — Install an SSH app on your phone:
    - We recommend ConnectBot (Android) or Termius (iOS/Android).
    - ConnectBot is free, no account needed.
    - Termius needs a free account but has a nicer UI.

  Step B.3 — Configure the host inside the SSH app:
EOF
printf '       %sHostname%s : %s   %s(or %s if hostname does not resolve)%s\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}" "$hostname_val" "${BIB_DIM:-}" "${ts_ip:-100.x.x.x}" "${BIB_RESET:-}"
printf '       %sUsername%s : %s\n' "${BIB_DIM:-}" "${BIB_RESET:-}" "$target_user"
printf '       %sPassword%s : your sudo password (just set)\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
cat <<EOF

  Connect, accept the host key fingerprint when prompted.
  You should land at: ${target_user}@${hostname_val}:~\$
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n    %s...QR for Termius:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t ANSI256 -l L -m 2 "https://termius.com/download" 2>/dev/null | sed 's/^/      /'
fi

# ---- BOTH PATHS — Resume the wizard --------------------------------------
printf '\n%s+----- Once you are SSH'\''d in (either path) -----+%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<'EOF'

  In your SSH session, run exactly:
EOF
printf '\n       %ssudo /opt/buildersinabox/payload/bootstrap.sh%s\n\n' \
    "${BIB_BOLD:-}${BIB_BRIGHT_YELLOW:-}" "${BIB_RESET:-}"
cat <<'EOF'
  The wizard picks up from where we paused: GitHub login (short URL in
  your terminal, easy), Claude login (long URL — paste from terminal to
  browser, works fine), workspace scaffold, tmux session. ~5 minutes.

  When the wizard says "All set, Paco!" you're done. You can unplug the
  monitor and keyboard from this device and forget they exist.
EOF

echo
exit 78
