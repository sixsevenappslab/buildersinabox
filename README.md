# Builders in a Box

> **Your own AI dev box. Plug in, code from your phone in 15 minutes.**

Turn any Ubuntu 24.04 machine — a mini PC, a homelab box, a VPS — into a personal development server you reach from your phone, with [Claude Code](https://claude.com/claude-code) (or another AI CLI) ready to ship. One command sets it up; [Tailscale](https://tailscale.com) makes it reachable from anywhere; `tmux` keeps your sessions alive.

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

**Status:** 🚧 early but real. The installer works on a fresh Ubuntu 24.04; the hosted one-liner and the landing page are landing as we go. Until then, the [git-clone install](#install) below works today.

---

## What you get

After ~15 minutes:

- **Claude Code reachable from your phone.** SSH in from [Termius](https://termius.com) (or any SSH client) over your private Tailscale network — no port forwarding, no public IP, end-to-end encrypted.
- **A `tmux` session that never dies.** Your work persists across disconnects. Pick up exactly where you left off, from the couch, a café, or a flight.
- **A scaffolded workspace** (`~/ai-platform/`) with sensible defaults and a guided `/tutorial` that walks you from "set up" to "building your first project" inside Claude Code itself.
- **Useful skills out of the box** — code review, simplification, UX review, and more. An opinionated spec-driven-development workflow is one `biab add sdd` away when you want it.

## What you need

- **A machine running Ubuntu Server 24.04 (x86-64).** A mini PC (Beelink, GEEKOM, Minisforum), a spare desktop, a homelab VM, or a cloud VPS all work. ~4 GB RAM is comfortable.
- **Ethernet for the first boot** (Wi-Fi provisioning is on the roadmap).
- **Accounts you already have or can make in 30 seconds:** Tailscale, and Claude (or Gemini). GitHub is optional but recommended.

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

## Roadmap

Builders in a Box is the first module of a small, opinionated toolkit for solo developers. Coming as separate opt-in modules:

- **Conerator** — a content engine that turns project data into posts across platforms.
- **Observio** — a cost + usage dashboard for your AI CLIs and your box.
- **Pathtrip** — natural-language web automation (scrape and act on any site).

Plus: Wi-Fi-first-boot, a richer module-install command (`biab install <module>`), and more hardware-tested images.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md). Be excellent to each other: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

MIT — see [LICENSE](LICENSE). Builders in a Box is published by SixSeven Apps.
