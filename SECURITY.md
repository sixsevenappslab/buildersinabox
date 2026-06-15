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

## Good to know

- Builders in a Box bundles **no credentials**. Every login is the user's own OAuth flow.
- Run `curl -fsSL https://buildersinabox.com/install.sh` (without piping to bash) to read the bootstrap before executing it.
