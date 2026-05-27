# Builders in a Box — first-boot trigger.
# Installed into /etc/profile.d/ so it runs for every interactive shell of
# every user. We only act when:
#   - the shell is on /dev/tty1 (the physical console attached to the mini PC),
#   - and /var/lib/buildersinabox/firstboot.pending exists.
#
# When both are true we hand control to the setup wizard. The wizard removes
# firstboot.pending when it completes successfully, so we don't keep
# re-launching it on every boot.

# shellcheck shell=sh

_biab_firstboot() {
    [ -f /var/lib/buildersinabox/firstboot.pending ] || return 0
    case "$(tty 2>/dev/null)" in
        /dev/tty1) ;;
        *) return 0 ;;
    esac

    # Run bootstrap.sh — it installs the stack (Tailscale, gh, Claude Code,
    # tmux, sshd hardening) if not already done, then runs the wizard.
    # Running wizard/run.sh directly here would skip the install phase
    # entirely and the OAuth steps would fail with "command not found".
    if [ -x /opt/buildersinabox/payload/bootstrap.sh ]; then
        sudo /opt/buildersinabox/payload/bootstrap.sh
    else
        echo "WARN: /opt/buildersinabox/payload/bootstrap.sh not found." >&2
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
