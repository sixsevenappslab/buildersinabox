# Security Policy

Builders in a Box installs and configures software **as root** on the machine it runs on, and sets up remote access (SSH over Tailscale). We take security reports seriously.

## Reporting a vulnerability

Email **hello@buildersinabox.com** with:

- a description of the issue and its impact,
- steps to reproduce (or a proof of concept),
- the version / commit you tested.

Please **do not** open a public issue for security problems. We'll acknowledge your report within a few days and keep you posted on the fix.

## Scope

Things we especially care about:

- The `curl | bash` bootstrap and `payload/install.sh` — they run as root.
- The OAuth flows (Tailscale, GitHub, the AI CLI) — credentials must stay on the user's machine; we never transmit them anywhere.
- The SSH hardening step and the autologin/first-boot machinery.
- Anything that could let a third party reach a user's box or read their tokens.

## Out of scope

- Vulnerabilities in upstream dependencies (Tailscale, GitHub CLI, the AI CLIs, Ubuntu) — report those to their projects, though we're happy to know about them.
- The maintainer-only `gift` materials, which never ship to a device.

## SSH end state and recovery

Once Tailscale is up, `sshd` is bound to your private Tailscale address only, so it does not listen on the public internet. Reaching that safe state never locks out the only admin:

- **Home box / behind NAT:** nothing is exposed to begin with, so the bind is applied straight away.
- **VPS with a public IP:** if you're driving the box over its public IP while it's set up, SSH is *not* silently locked to the tailnet (that could cut you off). Instead it's hardened to **key-only** if a key is present, or **held open with a clear warning** if the only credential is your password. It moves to Tailscale-only automatically once you finish `/tutorial` (which imports your GitHub key) or when you re-run the finalize step from a tailnet session.

If you ever get locked out, any one of these restores access without reinstalling:

1. **VPS provider web/serial console** — undo the Tailscale bind and reopen the public listener:

   ```bash
   sudo rm -f /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf \
              /etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf
   sudo systemctl daemon-reload && sudo systemctl reload ssh
   ```

2. **Re-apply the bind once Tailscale routes** (from a session that can reach the box over the tailnet):

   ```bash
   sudo BIB_SSH_FORCE_TAILSCALE=1 /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh
   ```

   Note: `BIB_SSH_FORCE_TAILSCALE=1` binds to the tailnet **without** first checking that the tailnet actually routes — only use it when you have confirmed alternative access. sshd is `reload`ed, not restarted, so an active session survives the bind and you can revert if the tailnet turns out not to route.

3. **Physical console (mini PC)** — keyboard + monitor, same edit as (1).

## Good to know

- Builders in a Box bundles **no credentials**. Every login is the user's own OAuth flow.
- Run `curl -fsSL https://buildersinabox.com/install.sh` (without piping to bash) to read the bootstrap before executing it.
