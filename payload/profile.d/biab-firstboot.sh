# Builders in a Box — first-boot trigger.
# Installed into /etc/profile.d/ so it runs for every interactive shell of
# every user. We act when:
#   - /var/lib/buildersinabox/firstboot.pending exists, AND
#   - either we're on the physical console (/dev/tty1), or
#     we're inside an SSH session (so the user resuming Phase B from
#     their phone/laptop lands straight into the wizard with zero
#     copy/paste — fixes the test-2026-05-28 friction).
#
# The wizard removes firstboot.pending when it completes, so we don't
# keep re-launching it on every login.

# shellcheck shell=sh

_biab_firstboot() {
    [ -f /var/lib/buildersinabox/firstboot.pending ] || return 0

    _bib_tty="$(tty 2>/dev/null || echo unknown)"
    _bib_in_ssh=0
    if [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]; then
        _bib_in_ssh=1
    fi

    case "$_bib_tty" in
        /dev/tty1) ;;
        *)
            if [ "$_bib_in_ssh" = "0" ]; then
                return 0
            fi
            ;;
    esac

    # Run install.sh — it installs the stack (Tailscale, gh, Claude Code,
    # tmux, sshd hardening) if not already done, then runs the wizard.
    # Running wizard/run.sh directly here would skip the install phase
    # entirely and the OAuth steps would fail with "command not found".
    if [ -x /opt/buildersinabox/payload/install.sh ]; then
        # Propagate SSH_* env across sudo so wizard steps (e.g. 36-phone-bridge)
        # can reliably detect SSH context. Without --preserve-env, sudo strips
        # these and SSH detection falls back to the process tree walk.
        sudo --preserve-env=SSH_CONNECTION,SSH_CLIENT,SSH_TTY \
            /opt/buildersinabox/payload/install.sh
    else
        echo "WARN: /opt/buildersinabox/payload/install.sh not found." >&2
        return 0
    fi

    # If the wizard finished and tmux is up, attach to it so the user lands
    # straight inside their session.
    if [ ! -f /var/lib/buildersinabox/firstboot.pending ] \
        && command -v tmux >/dev/null 2>&1 \
        && tmux has-session -t main 2>/dev/null; then
        exec tmux attach -t main
    fi
}

_biab_firstboot
