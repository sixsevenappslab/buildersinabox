#!/usr/bin/env bash
# reset-for-gift — wipes all personal state from a BIAB device so it can
# be handed to someone else AS IF it just came out of the autoinstall.
#
# Run this on the mini PC AFTER you've tested the end-to-end flow with
# YOUR accounts (Tailscale, GitHub, Claude). It removes every trace of
# your accounts and personal data but leaves the BIAB installation
# itself intact, so the recipient can power on + complete the wizard
# WITHOUT needing to re-flash from USB.
#
# Usage (on the mini PC, after testing):
#   sudo /opt/buildersinabox/tools/reset-for-gift.sh
#
# After running, power off and you can deliver the device.
#
# TODO(2026-08-02, FEAT-020): this maintainer tool still hardcodes both CLIs'
# config paths (~/.config/claude*, ~/.gemini, ~/.cache/antigravity) instead of
# deriving them from payload/lib/ai-cli.sh. Deliberately left out of the
# FEAT-020 registry migration (maintainer-only, outside the user payload) —
# fold it in when a third CLI lands (Wave 3).

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (use sudo)" >&2
    exit 1
fi

# Resolve the target user (the one who's NOT root and whose home we'll clean).
TARGET_USER="${SUDO_USER:-builder}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || echo "/home/$TARGET_USER")"
[[ -d "$TARGET_HOME" ]] || { echo "ERROR: cannot find home for $TARGET_USER" >&2; exit 1; }

echo "======================================================================"
echo "  reset-for-gift — wiping personal state for clean delivery"
echo "  Target user: $TARGET_USER ($TARGET_HOME)"
echo "======================================================================"
echo
echo "This will DELETE all of the following:"
echo "  - Your GitHub, Claude, Antigravity (Google), Tailscale, gh, npm auth tokens"
echo "  - Your SSH keys and authorized_keys"
echo "  - The ai-platform workspace ($TARGET_HOME/ai-platform/)"
echo "  - Bundled skills under ~/.agents/skills + ~/.claude/skills"
echo "  - The bashrc.d snippets + the appended bashrc loader"
echo "  - The wizard state and bootstrap logs"
echo "  - All tmux sessions"
echo "  - The user's bash history"
echo
echo "It will KEEP:"
echo "  - Ubuntu itself + all installed packages (tmux, gh, claude, tailscale...)"
echo "  - /opt/buildersinabox/ (the BIAB payload)"
echo "  - /usr/local/bin/biab and /usr/local/bin/bd"
echo "  - System services (sshd, autologin, profile.d/biab-firstboot)"
echo "  - The user '$TARGET_USER' itself (with a temporary password)"
echo
read -r -p "Continue? [yes/N] " confirm
[[ "$confirm" == "yes" ]] || { echo "aborted."; exit 1; }

# ---- 1. Log out from every external service --------------------------------

echo
echo "==> Logging out of services"

# Tailscale: deregister the device from the tailnet.
if command -v tailscale >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" tailscale logout 2>/dev/null || true
    # Also reset locally so re-running setup behaves like first boot.
    tailscale down 2>/dev/null || true
fi

# gh: remove ~/.config/gh entirely (includes hosts.yml with the token).
rm -rf "$TARGET_HOME/.config/gh" 2>/dev/null || true

# Claude Code: remove its config dir(s). The exact path depends on version.
rm -rf "$TARGET_HOME/.config/claude" \
       "$TARGET_HOME/.config/claude-code" \
       "$TARGET_HOME/.cache/claude" 2>/dev/null || true

# Antigravity CLI (agy): its OAuth token is a plain 0600 file at
# ~/.gemini/antigravity-cli/antigravity-oauth-token (agy 1.1.0 uses the file
# fallback — there is NO system keyring to clear, verified in FEAT-013 spike
# T1). Settings, cached conversations and session state also live under
# ~/.gemini/, so remove that whole legacy tree to purge the Google account
# token completely. Also drop the official installer's staging cache.
rm -rf "$TARGET_HOME/.gemini" \
       "$TARGET_HOME/.cache/antigravity" 2>/dev/null || true

# npm / yarn login if any.
rm -f "$TARGET_HOME/.npmrc" 2>/dev/null || true

# ---- 2. Kill tmux + remote-control sessions -------------------------------

echo "==> Killing tmux sessions"
sudo -u "$TARGET_USER" tmux kill-server 2>/dev/null || true

# ---- 3. Workspace + skills + bashrc snippets ------------------------------

echo "==> Removing user-side workspace and dotfiles"
rm -rf "$TARGET_HOME/ai-platform" \
       "$TARGET_HOME/.agents" \
       "$TARGET_HOME/.claude" \
       "$TARGET_HOME/.bashrc.d" \
       "$TARGET_HOME/README.md" \
       "$TARGET_HOME/.config/biab-tutorial" \
       "$TARGET_HOME/.config/biab-coach" 2>/dev/null || true

# Strip the appended biab-bashrc-d-loader from .bashrc.
if [[ -f "$TARGET_HOME/.bashrc" ]] && grep -q "biab-bashrc-d-loader" "$TARGET_HOME/.bashrc"; then
    awk '
        BEGIN { skip=0 }
        /# biab-bashrc-d-loader/ { skip=1 }
        skip==0 { print }
        /^fi$/ && skip==1 { skip=0; next }
    ' "$TARGET_HOME/.bashrc" > "$TARGET_HOME/.bashrc.tmp"
    mv "$TARGET_HOME/.bashrc.tmp" "$TARGET_HOME/.bashrc"
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bashrc"
fi

# ---- 4. SSH keys -----------------------------------------------------------

echo "==> Removing user SSH authorized_keys + known_hosts"
rm -f "$TARGET_HOME/.ssh/authorized_keys" \
      "$TARGET_HOME/.ssh/known_hosts" \
      "$TARGET_HOME/.ssh/id_"* 2>/dev/null || true

# Regenerate host keys so the device's SSH identity is fresh (no fingerprint
# leak from your test).
echo "==> Regenerating sshd host keys"
rm -f /etc/ssh/ssh_host_* 2>/dev/null || true
ssh-keygen -A

# Drop the FEAT-014 SSH bind state: the Tailscale-only ListenAddress points at
# YOUR tailnet IP (useless — and a reboot lockout — for the new owner), the
# legacy public-hardening file, and the systemd ordering drop-in that waits for
# the tailnet at boot. The recipient's first boot re-runs 50-ssh (public
# password listener) and 35-ssh-finalize (re-binds to THEIR tailnet).
echo "==> Removing BIAB SSH bind drop-ins (Tailscale-only bind, boot ordering)"
rm -f /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf \
      /etc/ssh/sshd_config.d/02-buildersinabox-public-hardening.conf \
      /etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf 2>/dev/null || true
rmdir /etc/systemd/system/ssh.service.d 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

# ---- 5. BIAB wizard state + logs ------------------------------------------

echo "==> Resetting BIAB wizard state"
# Wipe state.json — wizard will start from scratch.
echo '{"version": 1, "phases": {}}' > /var/lib/buildersinabox/state.json
chmod 644 /var/lib/buildersinabox/state.json

# Recreate the first-boot trigger marker.
touch /var/lib/buildersinabox/firstboot.pending

# Clear the bootstrap log.
: > /var/log/buildersinabox/bootstrap.log 2>/dev/null || true

# ---- 6. Reset the user's password to a known temporary value --------------

# We set a temporary password that the wizard's 01-set-password step will
# replace on first boot. We do NOT expire it: some PAM stacks force a
# password change at the autologin tty before bash starts, which would
# block the wizard banner from ever appearing. The wizard's
# 01-set-password step is what actually sets the operator's real password.
TEMP_PASS="builders"
echo "$TARGET_USER:$TEMP_PASS" | chpasswd

# ---- 7. Clean shell history -----------------------------------------------

echo "==> Clearing bash history"
rm -f "$TARGET_HOME/.bash_history" \
      "$TARGET_HOME/.python_history" \
      "$TARGET_HOME/.lesshst" 2>/dev/null || true
# Also root's.
rm -f /root/.bash_history /root/.python_history /root/.lesshst 2>/dev/null || true

# ---- 8. Trim journald + apt logs to remove personal traces ----------------

echo "==> Trimming system logs"
journalctl --rotate 2>/dev/null || true
journalctl --vacuum-time=1s 2>/dev/null || true
: > /var/log/apt/history.log 2>/dev/null || true
: > /var/log/apt/term.log 2>/dev/null || true
: > /var/log/wtmp 2>/dev/null || true
: > /var/log/btmp 2>/dev/null || true
: > /var/log/lastlog 2>/dev/null || true
: > /var/log/syslog 2>/dev/null || true
: > /var/log/auth.log 2>/dev/null || true

# ---- 9. Tailscale residual state ------------------------------------------

# `tailscaled` writes a state file under /var/lib/tailscale/. Reset it so
# the device doesn't auto-rejoin your tailnet on boot.
if [[ -d /var/lib/tailscale ]]; then
    systemctl stop tailscaled 2>/dev/null || true
    rm -f /var/lib/tailscale/tailscaled.state \
          /var/lib/tailscale/tailscaled.log* 2>/dev/null || true
    systemctl start tailscaled 2>/dev/null || true
fi

# ---- Done -----------------------------------------------------------------

echo
echo "======================================================================"
echo "  DONE. The device is ready to be handed over."
echo
echo "  Next steps for you:"
echo "    1. Power off:           sudo poweroff"
echo "    2. Unplug monitor + keyboard + USB (no need to ship the USB"
echo "       inside the box unless you want to — it's the recovery media)."
echo "    3. Pack the mini PC and the welcome card."
echo
echo "  When the recipient powers it on, autologin fires, the wizard sees"
echo "  firstboot.pending, and the install starts from scratch — exactly"
echo "  as if it just came off the USB."
echo "======================================================================"
