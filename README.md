# Builders in a Box

[![CI](https://github.com/sixsevenappslab/buildersinabox/actions/workflows/ci.yml/badge.svg)](https://github.com/sixsevenappslab/buildersinabox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Ubuntu 24.04 LTS](https://img.shields.io/badge/Ubuntu-24.04%20LTS-e95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/download/server)

> **An AI agent that codes overnight on your own mini PC — and can't merge without you. One command turns any old PC into a secure, always-on home for Claude Code or Antigravity, reachable from your phone. ~15 minutes.**

<!-- HERO: phone screenshot — pending hardware capture (Jesús), FEAT-012 §1.1.
     Drop the PNG here (under the tagline, above the curl one-liner) as:
     <p align="center"><img src="site/assets/hero.png" alt="A coding agent on a phone over a private network" width="360"></p> -->

Turn any Ubuntu 24.04 machine — a mini PC, a homelab box, a VPS, even that old laptop gathering dust in a drawer — into a personal development server you reach from your phone, with [Claude Code](https://claude.com/claude-code) or [Google's Antigravity](https://antigravity.google) ready to ship. One command sets it up, makes it reachable from anywhere over your own private network, and keeps your sessions alive across disconnects.

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

**Status:** 🚧 early but real. The hosted one-liner above and the [git-clone install](#install) below both work on a fresh Ubuntu 24.04.

> This isn't a demo workflow: Builders in a Box is the installable edition of the same harness [SixSeven Apps builds its own products with](https://sixsevenapps.com/es/apps/harness) — the box gets the way of working, not a copy of anyone's infrastructure.

---

## What you get

About 15 minutes gets you to your first SSH session from your phone; the guided tutorial after that is ~12 more. At the end:

- **Reachable from your phone or laptop.** SSH in from [Termius](https://termius.com) (or any SSH client) over your own private network — no port forwarding, no public IP, end-to-end encrypted.
- **Sessions that never die.** Your work persists across disconnects and closed laptops. Pick up exactly where you left off, from the couch, a coffee shop, or a flight.
- **A scaffolded workspace** (`~/ai-platform/`) with sensible defaults and a guided `/tutorial` that walks you from "set up" to "building your first project" inside your agent itself.
- **A senior workflow, baked in — spec-driven development.** The standout skill: instead of diving straight into code, the agent writes a short spec you approve *first* — the problem, the plan, the edge cases — so you catch a misunderstanding in a paragraph instead of a 400-line diff, which is what keeps a bigger feature on the rails when you're steering from your phone. It ships with a cast of review skills (code review, simplification, UX review, QA) that critique the work before you merge, GitHub wired up, and a real pull-request flow — a way of working teams take years to build, on your box from minute one (the `sdd-*` skills, `/sdd-coordinator` to start). A session-start reminder resurfaces any unfinished specs so long-running work doesn't rot, and an optional `incident` skill logs what broke and the rule you learned.
- **Work happens while you sleep — a guard, not a promise.** The optional night shift picks a spec you already approved, implements it unattended, and stops dead at the pull request. That's enforced at the tool layer: a `PreToolUse` hook blocks every merge and push attempt outright, loaded from the command line so the agent can't edit it out of its own settings. See [Optional: the night shift](#optional-the-night-shift).
- **A built-in usage coach.** Know what your agent burns before you hit a rate limit: the `quota` skill reconstructs your spend from your own session transcripts (by model, by project), a status-line segment shows the running weekly total, and a gentle nudge suggests dropping to a cheaper model for routine work. No new account — it reads what's already on your box.
- **Optional capability packs.** Heavier add-ons stay off until you ask for them. `biab pack add browser` gives the agent a sandboxed headless browser it can read, click, fill and screenshot with — running as its own locked-down user, never with access to your keys or code. `biab pack list` shows what's available.

## What you need

- **A machine running Ubuntu Server 24.04 (x86-64).** A mini PC (Beelink, GEEKOM, Minisforum), a spare desktop, a homelab VM, or a cloud VPS all work. ~4 GB RAM is comfortable.
- **A network connection.** An already-running machine or VPS uses whatever it has; the USB/gift image needs wired Ethernet for its first boot (Wi-Fi provisioning is on the roadmap).
- **The agent you already use:** a **paid Claude subscription** (Pro or above — Claude Code is included in paid plans, not the free tier) or a **Google account** for [Antigravity CLI](https://antigravity.google) (`agy`). The installer also sets you up on a private mesh network that's free for personal use. GitHub is optional but recommended.

### No spare hardware? Try it in a VM first

Same script, same wizard, same result — just disposable. Any hypervisor with
a real console window works: **VirtualBox** (Windows/Linux/Intel Mac, free),
**UTM** (Apple Silicon Mac, free, native virtualization), or
**virt-manager/Proxmox** (Linux). Install Ubuntu Server 24.04 LTS as the
guest (2 vCPU / 4 GB RAM / 20 GB disk is plenty), then run the one-liner
inside it exactly as you would on real hardware. Expect ~15-20 minutes,
console included.

**Not supported: Multipass.** Its `shell` is itself an SSH session with no
console behind it — partway through setup the installer restricts SSH to the
private network, and a console-less VM gets locked out of its own shell.
Use a hypervisor with a real console window instead.

No VM software handy? **A €4-5/month VPS also works** — same install, real
always-on hardware, no laptop fan spinning.

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

**What the install looks like** — a real recording on a fresh Ubuntu 24.04 box, from the command to “stack installed” (the guided wizard runs right after):

<p align="center"><a href="site/assets/install.svg"><img src="site/assets/install.svg" alt="Terminal recording: running the installer on a fresh Ubuntu 24.04 box, from the command to 'stack installed'." width="720"></a></p>

### Gift / USB edition

Builders in a Box can also be flashed to a USB stick as a self-installing Ubuntu image — plug it into a mini PC and it provisions hands-free, ending at a personalised welcome wizard. See [`iso-builder/`](iso-builder/). This is how you'd hand a ready-to-go box to someone as a gift.

## How it works

```
Your phone ──private network──▶ your box ──▶ your AI CLI + workspace
 (any SSH client)               (Ubuntu 24.04)  (a session that persists)
```

1. `install.sh` installs the stack (private networking, the GitHub CLI, your chosen AI CLI, persistent sessions, SSH hardening).
2. A short wizard handles the OAuth logins (you read a URL, approve on your phone) and scaffolds your workspace.
3. You SSH in from your phone or laptop and land inside your agent, in a session that survives disconnects, ready to build.

More detail in [`docs/architecture.md`](docs/architecture.md).

## Optional: the night shift

> **This one spends money. Read the whole section before you switch it on.**

`biab pack add night-shift` installs a scheduled job that, at 03:00, picks
**one** spec you have already validated, implements it with your AI CLI, and
**stops at the pull request**. You approve a spec on Sunday evening and find a
PR waiting on Monday morning, on hardware you own.

It is **opt-in and installed switched off**. Installing Builders in a Box never
schedules anything, and adding the pack does not either: a freshly added pack
*simulates*. Run `biab-night-shift run` and it will tell you which spec it would
have picked and what it would have done, having spent nothing and written
nothing. Turning that into real work takes a second, deliberate step:

```bash
biab pack add night-shift      # installs it, switched off
biab-night-shift run           # simulate: what would it do tonight?
biab-night-shift status        # installed? armed? how did last night go?
sudo biab-night-shift arm      # shows the cost, then asks you to type ARM
sudo biab-night-shift disarm   # back to simulating, nothing uninstalled
```

**What it costs.** A real pass runs your AI CLI unattended, on your own
subscription, while you are asleep and nobody is watching the meter. One spec
per night, no retries, capped at **$2.00 per pass** (`--max-budget-usd`) and
**one hour** of wall clock, enforced by systemd. `arm` prints those numbers —
plus your last seven days of spend, if the `quota` skill has a cache — *before*
it asks you anything.

Two honest caveats. The dollar cap is the CLI's own flag; on a subscription
account the binding limit in practice is the one-hour timeout and the
one-spec-per-night rule, not the dollar figure. And a spec that turns out to be
ambiguous can still burn a pass — which is why a spec that has been attempted
is not retried for 14 days.

**What it will not do.** It never merges, never releases, never pushes to your
main branch. That is not a request in a prompt: a `PreToolUse` hook inspects
every shell command the agent tries to run and blocks those outright, and the
hook is loaded from the command line, so the agent cannot remove it by editing
its own settings. It also refuses to start at all if your working tree is
dirty, and it only ever picks specs whose frontmatter carries a
`validated_by` — your approval is what authorises the spending.

**Switching it off.** `sudo biab-night-shift disarm` (keeps the pack, stops the
spending), `touch /var/lib/buildersinabox/night-shift/state/night-shift-disabled`
or `BIAB_NIGHT_SHIFT_DISABLED=1` (skip passes without disarming), or
`sudo biab pack remove night-shift` (removes the timer, the service, the runner
and all its state).

**One CLI only, for now.** Arming requires a headless mode, a per-run spend cap
*and* a mechanical tool guard. Today only Claude Code has all three, so on an
Antigravity or Codex box the pack installs and simulates but cannot be armed —
and it tells you that when you add it, not when you try to turn it on.

## What it changes on your system

Everything the installer touches, so you can audit it and undo it:

- **Packages:** a terminal multiplexer, a mesh-VPN client, jq, the GitHub CLI, and your chosen AI CLI (Claude Code or Antigravity).
- **Files:** the repo at `/opt/buildersinabox`; the `biab` and `bd` commands in `/usr/local/bin`; state in `/var/lib/buildersinabox`; logs in `/var/log/buildersinabox`; an autologin drop-in for `tty1` and a first-boot trigger in `/etc/profile.d/`; small shell helpers in `~/.bashrc.d/`.
- **SSH:** two drop-ins in `/etc/ssh/sshd_config.d/`. One enables password and key auth — your sudo password is the SSH credential — and because sshd takes the first value it finds for a setting and ours sorts first, it takes precedence over your own drop-ins for as long as it is installed. The other binds sshd to your private-network address only, once that network is up; if you're connected over SSH from outside it — typical on a VPS — the wizard warns you and asks first. The installer also moves sshd off Ubuntu's socket activation onto a long-running service, which is what makes that binding possible.
- **Workspace:** `~/ai-platform/` scaffolded in the target user's home, plus Claude Code skills in `~/.claude/skills/` and a few fail-open hooks in `~/.claude/settings.json`.
- **Opt-in packs only when you ask:** the base install adds nothing heavyweight and schedules nothing. `biab pack add browser` installs Chromium, a dedicated `biab-browser` system user, and a tightly-scoped `sudoers` rule (NOPASSWD for exactly `/usr/local/bin/biab-browse`). `biab pack add night-shift` installs `/usr/local/bin/biab-night-shift`, a `biab-night-shift` systemd service and timer in `/etc/systemd/system/` (root-owned, so the agent cannot rewrite its own schedule or drop its own guard), and a state tree under `/var/lib/buildersinabox/night-shift/` — enabled but disarmed, spending nothing until you run `biab-night-shift arm`. `biab pack remove <name>` reverses either of them.

To remove all of it:

```bash
sudo /opt/buildersinabox/payload/install.sh --uninstall
```

That removes both SSH drop-ins and puts socket activation back (on the next
boot — it deliberately won't drop the listener under you if you're uninstalling
over SSH), so sshd returns to your distribution's defaults.

What it deliberately does **not** undo: your home directory, your private-network
membership, your GitHub and agent logins, your account password, and the packages
it installed (tmux, jq, gh, Node, the mesh-VPN client, your AI CLI).

## Security model

Early-2026 scans found tens of thousands of self-hosted AI agent boxes exposed to the public internet, most with authentication bypasses. Builders in a Box is designed so the end state is nothing exposed:

- **sshd binds to your private network, not the internet.** Once the private network is up, sshd is restricted to your private-network address only — and Ubuntu's `ssh.socket` activation is disabled so that bind actually holds. On a home box or homelab behind NAT, nothing ever listens on the open internet: no port forwarding, no public IP, no reverse proxy. On a VPS with a public IP, the box reaches that same private-only end state — see the next point for how it gets there without locking you out.
- **Lockout-safe on a VPS.** If you set the box up over its public IP, it never silently locks SSH to the private network mid-session (that could cut you off). Instead: if one of your SSH keys is present, the public listener is hardened to **key-only** (no password, not brute-forceable); if only a password exists, SSH is held open with a loud warning and is **not** reported as secured until you acknowledge it. It moves to private-network-only automatically when you finish `/tutorial` (which imports your GitHub key) or when you re-run the finalize step from a session on that network. Recovery routes are documented in [SECURITY.md](SECURITY.md).
- **Auth stays inside your private network.** In the end state, SSH (your private-network SSH, your GitHub public keys, or your sudo password) is reachable only from devices on that private network. Root login over SSH is key-only (`prohibit-password`).
- **Auditable install.** The script served at `buildersinabox.com/install.sh` is pinned to the release tag it shipped with, so the code you read is the code it fetches. [What it changes](#what-it-changes-on-your-system) lists every path it touches; `--uninstall` reverses it.

## Roadmap

Wi-Fi first boot, more hardware-tested images, and more optional capability packs (`biab pack`) beyond the browser.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md). Be excellent to each other: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

MIT — see [LICENSE](LICENSE). Builders in a Box is published by SixSeven Apps.
