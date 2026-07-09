# Builders in a Box

> **Your own AI dev box. One command, ~15 minutes to coding from your phone.**

Turn any Ubuntu 24.04 machine — a mini PC, a homelab box, a VPS — into a personal development server you reach from your phone, with [Claude Code](https://claude.com/claude-code) (or another AI CLI) ready to ship. One command sets it up; [Tailscale](https://tailscale.com) makes it reachable from anywhere; `tmux` keeps your sessions alive.

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

**Status:** 🚧 early but real. The hosted one-liner above and the [git-clone install](#install) below both work on a fresh Ubuntu 24.04.

---

## What you get

About 15 minutes gets you to your first SSH session from your phone; the guided tutorial after that is ~12 more. At the end:

- **Claude Code reachable from your phone.** SSH in from [Termius](https://termius.com) (or any SSH client) over your private Tailscale network — no port forwarding, no public IP, end-to-end encrypted.
- **A `tmux` session that never dies.** Your work persists across disconnects. Pick up exactly where you left off, from the couch, a coffee shop, or a flight.
- **A scaffolded workspace** (`~/ai-platform/`) with sensible defaults and a guided `/tutorial` that walks you from "set up" to "building your first project" inside Claude Code itself.
- **Useful skills out of the box** — code review, simplification, UX review, and more. An opinionated spec-driven-development workflow is one `biab add sdd` away when you want it.

## What you need

- **A machine running Ubuntu Server 24.04 (x86-64).** A mini PC (Beelink, GEEKOM, Minisforum), a spare desktop, a homelab VM, or a cloud VPS all work. ~4 GB RAM is comfortable.
- **A network connection.** An already-running machine or VPS uses whatever it has; the USB/gift image needs wired Ethernet for its first boot (Wi-Fi provisioning is on the roadmap).
- **Accounts:** [Tailscale](https://tailscale.com) (the free plan is plenty) and either a **paid Claude subscription** (Pro or above — Claude Code is included in paid plans, not the free tier) or a **Google account** for [Antigravity CLI](https://antigravity.google) (`agy`). GitHub is optional but recommended.

## Install

**Hosted one-liner** (recommended once live):

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

**From source** (works today):

```bash
git clone https://github.com/sixsevenappslab/buildersinabox /opt/buildersinabox
sudo /opt/buildersinabox/payload/install.sh
```

The installer is interactive by default (it asks your name for the welcome screen). For unattended installs, see `payload/install.sh --help` (`--non-interactive`, `--update`, `--uninstall`, `--flavor`).

### Gift / USB edition

Builders in a Box can also be flashed to a USB stick as a self-installing Ubuntu image — plug it into a mini PC and it provisions hands-free, ending at a personalised welcome wizard. See [`iso-builder/`](iso-builder/). This is how you'd hand a ready-to-go box to someone as a gift.

## How it works

```
Your phone ──Tailscale──▶ your mini PC ──▶ tmux + Claude Code
 (Termius / SSH)          (Ubuntu 24.04)     (your workspace)
```

1. `install.sh` installs the stack (Tailscale, GitHub CLI, your chosen AI CLI, tmux, SSH hardening).
2. A short wizard handles the OAuth logins (you read a URL, approve on your phone) and scaffolds your workspace.
3. You SSH in from your phone and land inside Claude Code, in `tmux`, ready to build.

More detail in [`docs/architecture.md`](docs/architecture.md).

## What it changes on your system

Everything the installer touches, so you can audit it and undo it:

- **Packages:** tmux, jq, the GitHub CLI, Tailscale, and your chosen AI CLI (Claude Code or Antigravity CLI).
- **Files:** the repo at `/opt/buildersinabox`; the `biab` and `bd` commands in `/usr/local/bin`; state in `/var/lib/buildersinabox`; logs in `/var/log/buildersinabox`; an autologin drop-in for `tty1` and a first-boot trigger in `/etc/profile.d/`; small shell helpers in `~/.bashrc.d/`.
- **SSH:** once Tailscale is up, sshd is bound to your Tailscale address only (a drop-in in `/etc/ssh/sshd_config.d/`). If you're connected over SSH from outside your tailnet — typical on a VPS — the wizard warns you and asks before doing this.
- **Workspace:** `~/ai-platform/` scaffolded in the target user's home.

To remove all of it:

```bash
sudo /opt/buildersinabox/payload/install.sh --uninstall
```

It leaves your home directory, Tailscale, and your GitHub and Claude logins untouched.

## Security model

Early-2026 scans found tens of thousands of self-hosted AI agent boxes exposed to the public internet, most with authentication bypasses. Builders in a Box is designed so there is nothing to expose:

- **Zero public ports.** Nothing listens on the open internet. Once Tailscale is up, sshd binds to your private Tailscale address only — and Ubuntu's `ssh.socket` activation is disabled so that bind actually holds. No port forwarding, no public IP, no reverse proxy.
- **Auth stays inside your tailnet.** SSH (Tailscale SSH, your GitHub public keys, or your sudo password) is only reachable from devices on your private Tailscale network. Root login over SSH is key-only (`prohibit-password`).
- **Lockout-safe hardening.** If you're connected from outside the tailnet — typical on a VPS — the wizard warns and asks before restricting sshd, instead of cutting you off mid-session.
- **Auditable install.** The script served at `buildersinabox.com/install.sh` is pinned to the release tag it shipped with, so the code you read is the code it fetches. [What it changes](#what-it-changes-on-your-system) lists every path it touches; `--uninstall` reverses it.

## Roadmap

Wi-Fi first boot, more hardware-tested images, and a `biab install <module>` command for optional add-ons.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md). Be excellent to each other: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

MIT — see [LICENSE](LICENSE). Builders in a Box is published by SixSeven Apps.
