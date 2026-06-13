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
#     `ssh <username>@biab`. Done.
#
#   Path B — Phone
#     install Tailscale + Termius/ConnectBot apps, configure host,
#     connect.
#
# Both paths end with the same command:
#     sudo /opt/buildersinabox/payload/install.sh
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

# Decide whether we're running inside an SSH session.
#
# We can't just look at the TTY because `sudo` allocates its own pty
# (/dev/pts/N) even on the console — so a check like /dev/pts/* would
# misclassify the console autologin->profile.d->sudo bootstrap chain
# as SSH. See test-2026-05-28: bridge skipped on console, user was
# stuck OCR'ing Claude's 500-char OAuth URL from the monitor.
#
# Two robust signals:
#   1. SSH_CONNECTION env var is set by sshd. The wrapper in
#      profile.d/biab-firstboot.sh uses `sudo --preserve-env=...` to
#      keep it across the sudo boundary.
#   2. Walk up the process tree looking for sshd as an ancestor.
#      Works regardless of env propagation.
current_tty="$(tty 2>/dev/null || echo unknown)"
log "36-phone-bridge: tty=$current_tty ssh_conn=${SSH_CONNECTION:-unset}"

is_via_ssh() {
    [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]] && return 0
    local pid=$$
    local depth=0
    while [[ "$pid" -gt 1 && "$depth" -lt 20 ]]; do
        local comm
        comm="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
        [[ "$comm" == sshd* ]] && return 0
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
        [[ -z "$pid" ]] && break
        depth=$((depth + 1))
    done
    return 1
}

if is_via_ssh; then
    log "36-phone-bridge: SSH ancestor or SSH_* env detected, skipping bridge"
    exit 0
fi

# --- We're on the console. Show the SSH bridge instructions. --------------

target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"
hostname_val="$(hostname)"
ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || echo '')"

# Narrative header — make explicit what's about to happen and why.
clear
prompt_header "Time to move from this monitor to your phone (or laptop)"
cat <<'EOF'
We're going to keep going, but from another device.

Why: the next login (Claude) opens a URL that's too long to type or
scan from this monitor. From a real terminal — on your phone or your
laptop — copy/paste just works, so we use that.

How: we'll connect from your phone or laptop to this device over SSH
(the standard, secure remote-terminal protocol). Tailscale is already
set up, so SSH'ing in is just one short command on the other end.

Two paths below. Pick whichever you have handy. The phone path takes
a couple more taps; the laptop path is one ssh command.

EOF

prompt_confirm "Press Enter when you're ready to see the steps."

# =========================================================================
# PATH A — Phone (Termius)
# =========================================================================
clear
printf '%s+============================================================+%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sPath A — From your phone (Termius)%s                       %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+============================================================+%s\n\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"

cat <<'EOF'
Three short steps. You'll install two apps on your phone (Tailscale
+ Termius) and then connect.

If you have a laptop handy and prefer to use that, skip to Path B
further below — your laptop already has a terminal built in, so it
needs only ONE app install (Tailscale) and one ssh command. Faster.

----------------------------------------------------------------------

Step 1 — Install the Tailscale app on your phone.

   You signed into Tailscale's website a moment ago (that authorised
   the mini PC). Now you need the actual phone APP, so your phone
   joins the same private network and can reach the device.
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n   %sScan to open the Tailscale download page:%s\n\n' \
        "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t ANSI256 -l L -m 2 "https://tailscale.com/download" 2>/dev/null \
        | sed 's/^/     /'
    printf '\n'
fi
cat <<'EOF'
   (or search "Tailscale" in the App Store / Google Play)

   Open the app and sign in with the SAME account you used on the
   Tailscale website a moment ago. When the app shows "Connected"
   you're done.
EOF
echo
prompt_confirm "Press Enter once the Tailscale app is connected on your phone."

cat <<'EOF'

Step 2 — Install Termius on your phone.

   Termius is the SSH client — it's the app you'll actually type
   commands into. Tailscale handled the networking; Termius handles
   the terminal.
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n   %sScan to open the Termius download page:%s\n\n' \
        "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t ANSI256 -l L -m 2 "https://termius.com/download" 2>/dev/null \
        | sed 's/^/     /'
    printf '\n'
fi
cat <<'EOF'
   (or search "Termius" in the App Store / Google Play)

   Open it, create a free account (or sign in if you have one),
   and come back here.
EOF
echo
prompt_confirm "Press Enter once Termius is installed and you're signed in."

cat <<EOF

Step 3 — In Termius, tap "New Host" and fill in these three fields:

EOF
printf '       %sHostname%s : %s%s%s   %s(or %s if the name does not resolve)%s\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}" \
    "${BIB_BOLD:-}${BIB_BRIGHT_YELLOW:-}" "$hostname_val" "${BIB_RESET:-}" \
    "${BIB_DIM:-}" "${ts_ip:-100.x.x.x}" "${BIB_RESET:-}"
printf '       %sUsername%s : %s%s%s\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}" \
    "${BIB_BOLD:-}${BIB_BRIGHT_YELLOW:-}" "$target_user" "${BIB_RESET:-}"
printf '       %sPassword%s : the sudo password you just set\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}"
cat <<EOF

  Save → tap the host → accept the fingerprint.
  You should land at:  ${target_user}@${hostname_val}:~\$

EOF

# =========================================================================
# PATH B — Laptop
# =========================================================================
printf '%s+============================================================+%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sPath B — From your laptop (the faster path)%s              %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+============================================================+%s\n\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF
Mac, Windows or Linux laptop — all three have a built-in terminal,
which means you don't need Termius. One app install (Tailscale) and
one short command.

Step 1 — Install Tailscale on your laptop.
   Download from https://tailscale.com/download for your OS, install
   it, and sign in with the SAME account you used a moment ago on the
   Tailscale website. When the menu bar / system tray shows
   "Connected" you're done.

Step 2 — Open your laptop's terminal.
   - Mac      : Spotlight (Cmd-Space) → type "Terminal" → Enter
   - Windows  : Start menu → type "PowerShell" or "Windows Terminal"
   - Linux    : your usual one (gnome-terminal, konsole, etc.)

Step 3 — In that terminal, run:

EOF
printf '       %sssh %s@%s%s\n\n' \
    "${BIB_BOLD:-}${BIB_BRIGHT_YELLOW:-}" "$target_user" "$hostname_val" "${BIB_RESET:-}"
cat <<EOF
     (If "$hostname_val" doesn't resolve, replace with: $ts_ip)
     Password = the sudo password you just set.

EOF

# =========================================================================
# Resume command — same for both paths
# =========================================================================
printf '%s+============================================================+%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sOnce you are connected (either path)%s                     %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+============================================================+%s\n\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
cat <<EOF
  In the SSH session, type:

EOF
printf '       %sbiab%s\n\n' "${BIB_BOLD:-}${BIB_BRIGHT_YELLOW:-}" "${BIB_RESET:-}"
cat <<'EOF'
  That resumes the installer from where we paused: Claude login
  and tmux session. ~3 minutes.

  When you see the "All set!" message you're done. You can unplug the
  monitor and keyboard from this device and forget they exist.

  GitHub login happens later, inside the Claude Code app — the
  tutorial walks you through it.
EOF

echo
exit 78
