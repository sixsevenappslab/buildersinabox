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

    # Run install.sh — it installs the stack (Tailscale, gh, the AI CLI,
    # the phone-app service, sshd hardening) if not already done, then runs the wizard.
    # Running wizard/run.sh directly here would skip the install phase
    # entirely and the OAuth steps would fail with "command not found".
    if [ -x /opt/buildersinabox/payload/install.sh ]; then
        # Propagate SSH_* env across sudo so wizard steps (e.g. 36-phone-bridge)
        # can reliably detect SSH context. Without --preserve-env, sudo strips
        # these and SSH detection falls back to the process tree walk.
        sudo --preserve-env=SSH_CONNECTION,SSH_CLIENT,SSH_TTY \
            /opt/buildersinabox/payload/install.sh
    else
        echo "WARN: /opt/buildersinabox/payload/install.sh not found." >&2  # i18n-ok: no payload, so no catalogs to read
        return 0
    fi

    # The wizard is done. How the user reaches the box now depends on the AI
    # CLI, and biab-workspace --mode is the one place that says so (it reads
    # the same gate the installer uses), so this file never tests a CLI name.
    if [ ! -f /var/lib/buildersinabox/firstboot.pending ]; then
        _bib_mode="$(/opt/buildersinabox/paseo/bin/biab-workspace --mode 2>/dev/null || echo ssh)"
        # The text is in the catalogs (FEAT-045), which are bash; this file is read by every login shell.
        if [ "$_bib_mode" = "paseo" ]; then
            bash -c 'source /opt/buildersinabox/payload/lib/i18n.sh && msg biab.firstboot.app'
        else
            bash -c 'source /opt/buildersinabox/payload/lib/i18n.sh && msg biab.firstboot.ssh'
        fi
    fi
}

_biab_firstboot
