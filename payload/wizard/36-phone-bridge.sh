#!/usr/bin/env bash
# Wizard step: pause the console flow so the user moves to their phone.
#
# Rationale: Claude Code's interactive /login generates a 500+ char OAuth
# URL that's impractical to copy from a console screen (too long to type,
# phone OCR struggles with TV-style monitors, no clipboard on tty1). The
# clean path is to SSH from the user's phone via Termius + Tailscale and
# complete Claude's OAuth there, where the mobile clipboard makes
# copy-paste between Termius and the mobile browser trivial.
#
# Behavior depends on the controlling TTY:
#   - /dev/tty1 (console autologin)  -> print a rich guide and exit 78.
#                                       Exit code 78 tells run.sh to stop
#                                       the wizard chain cleanly.
#   - /dev/pts/N (SSH session)       -> log + exit 0, continue to Claude
#                                       login (which now works because
#                                       the SSH terminal supports copy).
#
# Skipped entirely if Claude is already authenticated (resumption case).

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

# Test/mock mode: don't pause, the rest of the wizard is mocked anyway.
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

# We're on console. Print the guide and pause the wizard chain.
target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"
hostname_val="$(hostname)"
ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || true)"

prompt_header "Continue from your phone"

cat <<EOF
The next step is Claude Code's first OAuth login. Its sign-in URL is
much too long to type from a phone or scan from this screen, so we
finish setup from your phone instead — over SSH, where copy-paste works.

Three things to do, in order. Take your phone now.

EOF

# ---- Step 1: Tailscale on phone -------------------------------------------
printf '%s[1/3]%s  %sInstall Tailscale on your phone%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}"
cat <<'EOF'
       App Store / Google Play: search "Tailscale"
       Sign in with the SAME account you used earlier in this wizard
       (when we set up Tailscale on the device). Approve the phone
       joining your tailnet.
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n       %s...or scan to install Tailscale:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://tailscale.com/download" 2>/dev/null | sed 's/^/         /'
fi

# ---- Step 2: Termius on phone, host configured ---------------------------
printf '\n%s[2/3]%s  %sInstall Termius and add this device as a host%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}"
cat <<EOF
       App Store / Google Play: search "Termius"
       Open Termius. Tap "+" -> "New Host". Fill in:
EOF
printf '         %sAlias%s    : biab\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
printf '         %sHostname%s : %s\n' "${BIB_DIM:-}" "${BIB_RESET:-}" "$hostname_val"
if [[ -n "$ts_ip" ]]; then
    printf '                    %s(or %s if the hostname does not resolve)%s\n' \
        "${BIB_DIM:-}" "$ts_ip" "${BIB_RESET:-}"
fi
printf '         %sUsername%s : %s\n' "${BIB_DIM:-}" "${BIB_RESET:-}" "$target_user"
printf '         %sPassword%s : (leave blank — Tailscale SSH handles auth)\n' \
    "${BIB_DIM:-}" "${BIB_RESET:-}"
cat <<'EOF'
       Save the host. Tap it. You should land in a shell prompt.
EOF
if command -v qrencode >/dev/null 2>&1; then
    printf '\n       %s...or scan to install Termius:%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"
    qrencode -t UTF8 -m 1 "https://termius.com/download" 2>/dev/null | sed 's/^/         /'
fi

# ---- Step 3: Resume the wizard from inside Termius -----------------------
printf '\n%s[3/3]%s  %sResume this wizard from Termius%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}"
cat <<'EOF'
       In the Termius SSH session, run exactly this:

           sudo /opt/buildersinabox/payload/bootstrap.sh

       The wizard picks up from where we paused. The next prompt is the
       Claude OAuth: a long URL appears in Termius. Long-press to copy,
       paste into your phone's browser, complete the login, copy the
       short auth code Claude shows, paste it back into Termius.

       After that the wizard scaffolds your project, launches tmux, and
       prints the final 'All set' message — all inside Termius. That's
       when you install the Claude Code app and connect from it.

       You can leave this monitor as it is, or unplug it now.
EOF
printf '\n'

exit 78
