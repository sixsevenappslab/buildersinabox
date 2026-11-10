# Builders in a Box

[![CI](https://github.com/sixsevenappslab/buildersinabox/actions/workflows/ci.yml/badge.svg)](https://github.com/sixsevenappslab/buildersinabox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Ubuntu 24.04 LTS](https://img.shields.io/badge/Ubuntu-24.04%20LTS-e95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/download/server)

> **You just describe it and push to prod. An AI agent builds it overnight on your own mini PC, and by morning it is on your `dev` branch — CI green, independently reviewed, your own check passing. Promoting it to `main` is the one step that stays yours. One command turns any old PC into a secure, always-on home for Claude Code, Codex, Antigravity or OpenCode, reachable from your phone. ~15 minutes.**

<!-- HERO: phone screenshot — pending hardware capture (the maintainer), FEAT-012 §1.1.
     Drop the PNG here (under the tagline, above the curl one-liner) as:
     <p align="center"><img src="site/assets/hero.png" alt="A coding agent on a phone over a private network" width="360"></p> -->

Turn any Ubuntu 24.04 machine — a mini PC, a homelab box, a VPS, even that old laptop gathering dust in a drawer — into a personal development server you reach from your phone, with [Claude Code](https://claude.com/claude-code), Codex, [Google's Antigravity](https://antigravity.google) or [OpenCode](https://opencode.ai) ready to ship. One command sets it up, makes it reachable from anywhere over your own private network, and keeps your sessions alive across disconnects.

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

**Status:** 🚧 early but real. The hosted one-liner above and the [git-clone install](#install) below both work on a fresh Ubuntu 24.04.

> This isn't a demo workflow: Builders in a Box is the installable edition of the same harness [SixSeven Apps builds its own products with](https://sixsevenapps.com/es/apps/harness) — the box gets the way of working, not a copy of anyone's infrastructure.

---

## What you get

About 15 minutes gets you to your first SSH session from your phone; the guided tutorial after that is ~12 more. At the end:

- **Reachable from your phone or laptop.** On every box — Claude Code, Codex, Antigravity or OpenCode (OpenCode while its permission rules hold, see below) — you open the [Paseo](https://github.com/getpaseo/paseo) app and find your agent and your projects as workspaces named "BIAB · …", over your own private network — no port forwarding, no public IP. Claude Code and Codex keep their permission prompts in the app, and Antigravity asks before it runs commands, writes files and reads outside your project. SSH from [Termius](https://termius.com) (or any SSH client) into the same CLI always works too, with or without the app.
- **Sessions that never die.** The agent runs on the box, not on your phone, so closing the app, a dropped connection or a closed laptop does not stop it. Pick up exactly where you left off, from the couch, a coffee shop, or a flight. A watchdog restarts the Paseo daemon if it dies and `biab status` tells you when it could not.
- **A scaffolded workspace** (`~/ai-platform/`) with sensible defaults and a guided `/tutorial` that walks you from "set up" to "building your first project" inside your agent itself.
- **A senior workflow, baked in — spec-driven development.** The standout skill: instead of diving straight into code, the agent writes a short spec you approve *first* — the problem, the plan, the edge cases — so you catch a misunderstanding in a paragraph instead of a 400-line diff, which is what keeps a bigger feature on the rails when you're steering from your phone. It ships with a cast of review skills (code review, simplification, UX review, QA) that critique the work before you merge, GitHub wired up, and a real pull-request flow — a way of working teams take years to build, on your box from minute one (the `sdd-*` skills, `/sdd-coordinator` to start). A session-start reminder resurfaces any unfinished specs so long-running work doesn't rot, and an optional `incident` skill logs what broke and the rule you learned.
- **Work happens while you sleep — gates you can read, not a promise.** The optional night shift (Claude Code only today, see [what each AI CLI gets](#what-each-ai-cli-gets)) picks a spec you already approved and implements it unattended, then goes only as far as you allowed: it stops at the pull request, or — the default when you arm it now — merges into a `dev` branch once CI, an independent review and your own dev check all pass. Promoting `dev` to `main` stays yours. A `PreToolUse` hook, loaded from the command line so the agent can't edit it out of its own settings, keeps the agent itself from merging or pushing to `main` or `dev`; branch protection on your default branch is the lock. The merge to `dev` is a brake, not a lock — the runner and the agent share your account — and we say so. See [Optional: the night shift](#optional-the-night-shift).
- **A built-in usage coach.** Know what your agent burns before you hit a rate limit: the `quota` skill reconstructs your spend from your own session transcripts (by model, by project), a status-line segment shows the running weekly total, and a gentle nudge suggests dropping to a cheaper model for routine work. No new account — it reads what's already on your box.
- **Optional capability packs.** Heavier add-ons stay off until you ask for them. `biab pack add browser` gives the agent a sandboxed headless browser it can read, click, fill and screenshot with — running as its own locked-down user, never with access to your keys or code. It can work through a form in one go rather than a click at a time, and when a site refuses a headless desktop browser it retries as a phone before giving up. It will not solve a CAPTCHA or pretend not to be automation, and it says so instead of trying. `biab pack list` shows what's available.

## What each AI CLI gets

The four AI CLIs are not equal on a box, and Builders in a Box does not pretend they are. The table below is generated from what each CLI's adapter declares in the installer (`biab-guard matrix`), a test fails if it ever differs from them, and `biab status` prints the same facts for your own box.

<!-- BIB:matrix:start -->
| AI CLI | Phone app | Guard | Confirm prompts | Same refuse list as Claude Code | Night shift |
|---|---|---|---|---|---|
| Claude Code | yes | yes | yes | yes | yes |
| Antigravity (agy) | yes | yes | yes | yes | no |
| Codex CLI | yes | yes | no | yes | no |
| OpenCode | yes, while its rules hold | partial | no | no | no |
<!-- BIB:matrix:end -->

- **Phone app:** the CLI runs in the Paseo app with its permission prompts on. OpenCode counts only while the permission rules Builders in a Box wrote for it still ask.
- **Guard:** a shell-command guard registered in the CLI's own hook or rule system, refusing the clearly destructive commands (`rm -rf /`, `mkfs`, `dd` to a disk, a fork bomb, `curl … | sudo bash`, a force-push to `main`; OpenCode's covers only part of this, see below). A brake, not a lock: a list of patterns, not a sandbox, kept in a file in your home folder that an agent you let edit its own settings can change.
- **Confirm prompts:** the guard also asks, instead of refusing, for the risky-but-legitimate ones (a plain `curl … | bash`, a `--force-with-lease` push).
- **Same refuse list as Claude Code:** whether the guard refuses the same commands Claude Code's guard does (the confirm-class ones aside, see the previous column).
- **Night shift:** the optional unattended run needs a headless mode, a spend cap and a mechanical tool guard; see [the night shift](#optional-the-night-shift).

What that means for each CLI, in plain words:

- **Claude Code** is the reference: guard, confirm prompts, a status line and the night shift.
- **Codex** has the guard, with Claude Code's patterns but no confirm prompts of ours (its own approval rules decide those). You approve it once, with `/hooks` inside `codex`; until you do, `biab status` says PENDING APPROVAL and Codex skips it, `codex exec` included. No night shift yet: it is not wired for Codex.
- **Antigravity** has the guard and confirm prompts, installed as the `biab-guard` plugin in `~/.gemini/config/plugins/biab-guard` with the same rules as Claude Code's guard, on top of its own permission prompts (it asks before it runs commands, writes files and reads outside your project). No night shift: its command-line mode waits for a terminal that an unattended run does not have, and it cannot log in without a person at a screen.
- **OpenCode** has a partial guard: deny rules in its own `opencode.json`, covering a smaller set than Claude Code's, Antigravity's or Codex's, which is why the table says "partial" and `biab status` says PARTIAL and lists what is not covered (pipes into a shell, quoted targets, subagents are not confirmed, a project's own `opencode.json` can override it). No night shift.

Where the guards stand: they are checked by tests in this repository and against each CLI's own commands for listing hooks or reading configuration. Watching each one refuse a command in a real, logged-in session on a real box is a hardware pass still to be done, and until it is, none of this is a claim about what happens in a live session.

## What you need

- **A machine running Ubuntu Server 24.04 (x86-64).** A mini PC (Beelink, GEEKOM, Minisforum), a spare desktop, a homelab VM, or a cloud VPS all work. ~4 GB RAM is comfortable.
- **A network connection.** An already-running machine or VPS uses whatever it has; the USB/gift image needs wired Ethernet for its first boot (Wi-Fi provisioning is on the roadmap).
- **The agent you already use:** a **paid Claude subscription** (Pro or above — Claude Code is included in paid plans, not the free tier), a **ChatGPT account** for Codex, a **Google account** for [Antigravity CLI](https://antigravity.google) (`agy`), or an [OpenCode](https://opencode.ai) login (an OpenCode Go or Zen key, or another provider you already pay for). The installer also sets you up on a private mesh network that's free for personal use. GitHub is optional but recommended.

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

No VM software handy? **A cloud VPS also works** — same install, real
always-on hardware, no laptop fan spinning. A VPS reached over a public IP
installs under a separate profile that never touches your provider's SSH:
see [`docs/cloud.md`](docs/cloud.md) for the Google Cloud recipe, the costs
and how to close the door afterwards.

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

### Install via an agent you already have

If you already have Claude Code or Codex running somewhere, you can tell it to install Builders in a Box on a target box for you instead of running the one-liner yourself — as long as that agent already has SSH access to the target (a VPS you control, or a box on your LAN):

```bash
curl -fsSL https://buildersinabox.com/install.sh | \
  sudo env BIB_USER=you BIB_FLAVOR=default BIB_AI_CLI=claude BIB_SSH_INSTALL_ACK=1 \
  bash -s -- --non-interactive
```

- `BIB_AI_CLI=claude` or `BIB_AI_CLI=codex` — **not `antigravity` or `opencode`**. Their logins are full-screen TUIs that need a real terminal (OpenCode asks you to paste a key); the other two run a one-shot command that prints a URL and polls on its own, which is what makes this workable without a real terminal attached.
- `BIB_SSH_INSTALL_ACK=1` acknowledges the SSH-lockout warning this installer already prints when it detects it's running over SSH with no private network up yet (see [Security model](#security-model)) — without it, the install aborts before touching anything.

Two points in the run need a human, and the agent should surface both as plain messages, not swallow them:

1. **Tailscale login.** The install pauses — prints a line like `BIB_AGENT_PAUSE: step=Tailscale url=https://login.tailscale.com/...` and stops (exit code 78) rather than hanging on a keypress nobody will send. Open that URL, sign in, then have the agent re-run the exact same command — the install is idempotent and picks up where it left off.
2. **AI CLI login.** The command keeps running and prints its own URL + short code. Open it, approve, and the install continues by itself — no rerun needed here.

This is still two clicks from a phone, not zero-touch — the agent is doing the typing, you're still doing the login.

## How it works

```
Your phone ──private network──▶ your box ──▶ your AI CLI + workspace
 (Paseo app, or any SSH client)  (Ubuntu 24.04)  (an agent that keeps running)
```

1. `install.sh` installs the stack (private networking, the GitHub CLI, your chosen AI CLI, SSH hardening) and a pinned [Paseo](https://github.com/getpaseo/paseo) daemon that runs as a systemd service.
2. A short, resumable six-step wizard handles the private connection, remote handoff, AI login and workspace setup. It asks whether you have a phone or laptop before showing its instructions. Its last step starts your first agent in Paseo, in the `~/ai-platform` workspace, and walks you through pairing the app with the box.
3. You open the Paseo app and the agent is already running, opening the tutorial. Every project you create afterwards appears as its own workspace named "BIAB · <project>". If you skip pairing, `sudo biab paseo pair` shows the three values later.
4. If Paseo is ever down, SSH over the private network straight into your AI CLI still works, and `biab status` prints the exact command.

Paseo is an independent open-source project (Apache-2.0) by its own authors. Builders in a Box installs a pinned version of it, names itself in everything you see in the app, and does not use Paseo's name or icon as its own branding.

### Antigravity in the Paseo app

Antigravity runs in the app like the other two. It asks before it runs a shell command, before it writes a file in the project, your home folder, `~/.biab` or `/var/tmp`, and before it reads a file outside your project. It does not ask before it reads inside the project, searches the web, opens a web page or writes in `/tmp`. The prompt offers only allow once or reject, with no always-allow; the Auto Accept switch (below) is separate. That is what we measured with `agy` 1.4.11. Paseo ships its own Antigravity plugin, but that one starts `agy` with `--dangerously-skip-permissions`, so every tool call would run without asking. Builders in a Box never uses it: it switches that plugin off and declares its own Antigravity provider instead, which runs the pinned `agy` as `agy acp` (Antigravity's Agent Client Protocol mode). There is nothing to switch on and nothing to type: the wizard starts your first agent in the app, opening the tutorial, as it does for Claude Code and Codex.

### OpenCode in the Paseo app

OpenCode allows every file edit and shell command unless its settings say otherwise, so Builders in a Box writes permission rules in `~/.config/opencode/opencode.json` (as you, never through a link, and only adding keys you do not already have): it asks before it edits a file, fetches a web page or runs a shell command, apart from three exact read-only commands (`git log`, `ls`, `pwd`). OpenCode is offered in the app **only while that file still asks**: if you change it so that edits or commands run unasked, the next `biab update` stops offering it there and says why, and you can still use it over SSH. It also checks the other places OpenCode reads from your home folder and the `~/ai-platform` workspace (`~/.opencode/`, `~/ai-platform/.opencode/`, `~/ai-platform/opencode.json`, and agent files in them or in `~/.config/opencode/`): a link, a JSONC file, invalid JSON or anything that allows actions without asking there stops it too. Limits: the `opencode.json` of a repository under `~/ai-platform/projects` and an `OPENCODE_PERMISSION` or `OPENCODE_CONFIG_CONTENT` environment setting can still override these rules and are not seen, "Always allow" in the app lasts for the session, and the file is yours, so an agent you let edit its own settings can change it. OpenCode does **not** get the night shift. Sign in with `opencode auth login` (an OpenCode Go or Zen key from opencode.ai/auth, or another provider); a login cancelled halfway leaves the setup paused and `biab` resumes it.

Two things to know:

- Paseo's app has a per-agent **Auto Accept** switch. Turned on, that agent stops asking. It is the same kind of switch as Bypass for Claude Code and Full Access for Codex, and Builders in a Box never turns any of them on. Be aware that Paseo's unattended runs (schedules) turn Auto Accept on by default.
- Antigravity's provider settings live in a file in your home, like the permission settings of Claude Code and Codex do. Every time the daemon starts, Builders in a Box puts the safe ones back; while it runs it does not watch them. [SECURITY.md](SECURITY.md) has the details and the limits.

An Antigravity box installed before this change is moved over by `biab update`: your projects show up as workspaces in the app, and your existing SSH sessions keep running. If you had switched on the older mode that ran every tool without asking, `biab update` tells you once what Antigravity now asks about. An older Antigravity box also gets one agy setting changed (`allowNonWorkspaceAccess` from `true` to `false`), which is what makes reads outside the project ask.

More detail in [`docs/architecture.md`](docs/architecture.md).

## Optional: the night shift

> **This one spends money, and at `dev` reach it merges code. Read the whole section before you switch it on.**

`biab pack add night-shift` installs a scheduled job that, at 03:00, picks
**one** spec you have already validated, implements it with your AI CLI, and
then goes only as far as you allowed it — its **reach**:

- **`pr`** — it stops at the pull request. You approve a spec on Sunday evening
  and find a PR waiting on Monday morning.
- **`dev`** (the default when you arm it) — after the agent has finished, the
  runner merges its pull request into a `dev` branch, but only if CI is green,
  an independent review finds nothing blocking and your own dev check passes on
  the result. You find the change already on `dev` in the morning, and promote
  `dev` to `main` yourself.
- **`main`** — the same gates, merging into your default branch. You have to
  type `UNLOCK MAIN` to choose it, because at this level nothing is a lock any
  more.

It is **optional and installed switched off**. Installing Builders in a Box never
schedules anything, and adding the pack does not either: a freshly added pack
*simulates*. Run `biab-night-shift run` and it will tell you which spec it would
have picked and what it would have done, having spent nothing and written
nothing. Turning that into real work takes a second, deliberate step:

```bash
biab pack add night-shift              # installs it, switched off
biab-night-shift run                   # simulate: what would it do tonight?
biab-night-shift status                # installed? armed? which reach? how did last night go?
sudo biab-night-shift arm              # shows the cost, asks you to type ARM (reach: dev)
sudo biab-night-shift arm --reach pr   # the same, stopping at the pull request
biab-night-shift dev-setup <project>   # as you, not root: create and protect the project's dev branch
biab-night-shift promote <project>     # as you: open (or reuse) the dev -> main PR
sudo biab-night-shift disarm           # back to simulating, nothing uninstalled
```

A box armed before the reach ladder existed keeps stopping at the pull request
until you arm it again.

**What it costs.** A real pass runs your AI CLI unattended, on your own
subscription, while you are asleep and nobody is watching the meter. One spec
per night, no retries, **one hour** of wall clock enforced by systemd, and a cap
of **$2.00 per pass** (`--max-budget-usd`) at `pr` — **$2.50** at `dev` or
`main`, because the independent review is a second call with its own $0.50 cap.
`arm` prints those numbers — plus your last seven days of spend, if the `quota`
skill has a cache — *before* it asks you anything.

Two honest caveats. The dollar cap is the CLI's own flag; on a subscription
account the binding limit in practice is the one-hour timeout and the
one-spec-per-night rule, not the dollar figure. And a spec that turns out to be
ambiguous can still burn a pass — which is why a spec that has been attempted
is not retried for 14 days.

**What each level can and cannot do.**

| Reach | Mechanical, and true | Only a brake (we say so) |
|---|---|---|
| `pr` | It cannot merge without you: a required review on your default branch, checked before a pass spends anything. | The hook. |
| `dev` | It cannot reach `main` without you: the same lock. It merges into `dev` only through the runner's gates, after the agent has exited, pinned to the exact commit those gates saw. It never touches a danger zone, a project with no dev check, or a repo with no CI. | That the agent cannot merge into `dev` by itself (the hook, same account and token). That the independent review cannot be talked round (it is a model). |
| `main` | Nothing is a lock any more; you accepted that in writing. The same gates run. | Everything. |

**The agent itself always stops at the pull request.** A `PreToolUse` hook,
loaded from the command line so the agent cannot edit it out of its own
settings, is a whitelist, not a list of forbidden spellings: the only push it
allows is `git push [-u] origin <feature-branch>` (never `main` or `dev`), the
only `gh` verbs are `pr create` and a few read-only ones, and it blocks merges,
releases, the GitHub API, `curl` against GitHub, credential reads, edits to
`.git/` and `.github/workflows/`, `sudo` and `eval` — from the shell and from the
file-editing tools alike. MCP servers are switched off for the pass. It writes
its own audit line every time it blocks something. Call it a brake: an agent
that writes files and runs programs can always find one more spelling (a script
written to disk and then executed is the obvious one), and we would rather say
that than promise otherwise.

**The lock is branch protection on your repository**, requiring at least one
approving review with administrators included. The agent runs as you, and you
cannot approve your own pull request, so with that in place nothing merges into
your default branch no matter what it types. A real pass checks GitHub for it
before spending anything and aborts if it is missing; if you knowingly want to
run without it — say, a private repo on a plan without branch protection —
`sudo biab-night-shift arm --unprotected-ok` says so explicitly, and every
morning's summary will remind you the hook was the only brake.

**At `dev` reach, the runner merges — after the agent has exited.** It finds the
pull request on GitHub instead of trusting what the agent printed (exactly one,
opened by you, from this repository, during this pass), and then, in order:

1. **Danger zones** stop it at the pull request: anything under `.github/` or
   `.biab/`, secrets and keys, infrastructure files, migrations, auth, payment
   and billing code, dependency manifests, agent instruction files
   (`CLAUDE.md`, `AGENTS.md`, `.claude/`), deleted or renamed files, more than
   60 files or 2,000 changed lines, and added lines that mention payment or
   cloud platforms. Your repo can add patterns in `.biab/danger-paths`; it can
   never remove one. A lexical list: a false positive costs you one PR to merge
   by hand.
2. **CI** must exist and be green (a repo with no checks stays at `pr`).
3. **An independent review** — a second, separate call to your CLI with no
   tools, that sees only the diff and the spec and must answer in a fixed
   format — must approve with nothing blocking.
4. The **merge** is pinned to the commit every gate looked at.
5. **Your dev check** runs on the merged result, and the morning summary quotes
   its last line.

Anything missing, late, malformed or unclear stops it at the pull request, and
the summary names the step. A failed dev check after the merge is reported,
never reverted.

**Your dev check** is one file in your repo, `.biab/dev-check.sh`: exit `0`
means the change works, any other exit means it does not, and exit `3` means
"not configured yet" (that is what `/first-project` writes, and it counts as
missing). It is whatever shows *you* the project works — run the tests, start
the app and curl it, deploy to a staging URL. The version that runs is always
the one already on `dev`, never the one the pull request brings, and it runs
with a clean environment and a five-minute limit. A project with no dev check,
or whose `dev` is red, runs at `pr` that night, and the morning summary says
why.

**Promoting `dev` to `main`** is yours: `biab-night-shift promote <project>`
opens (or reuses) the pull request and prints the one command that finishes
it — a merge commit, never a squash, so `dev` and `main` stay in line.

It also refuses to start at all if your working tree is dirty, and it only
ever picks specs whose frontmatter carries a `validated_by` — your approval
is what authorises the spending.

**Switching it off.** `sudo biab-night-shift disarm` (keeps the pack, stops the
spending), `touch /var/lib/buildersinabox/night-shift/state/night-shift-disabled`
or `BIAB_NIGHT_SHIFT_DISABLED=1` (skip passes without disarming), or
`sudo biab pack remove night-shift` (removes the timer, the service, the runner
and all its state). Your `dev` branch on GitHub and the `.biab/` files in your
projects are yours and are left alone.

**One CLI only, for now.** Arming requires a headless mode, a per-run spend cap
*and* a mechanical tool guard. Today only Claude Code has all three, so on an
Antigravity, Codex or OpenCode box the pack installs and simulates but cannot be armed —
and it tells you that when you add it, not when you try to turn it on. Codex is not wired yet;
Antigravity's command-line mode waits for a terminal that an unattended run does not have, and
it cannot log in without a person at a screen; OpenCode has no unattended mode we can verify.

## What it changes on your system

Everything the installer touches, so you can audit it and undo it:

- **Packages:** a mesh-VPN client, jq, the GitHub CLI, and your chosen AI CLI (Claude Code, Codex, Antigravity or OpenCode, the last as a pinned, checksum-verified release binary in `/usr/local/bin`). The Paseo daemon is not an apt package: it is a pinned version installed from the npm registry through a committed lockfile into `/opt/buildersinabox/paseo` (about 800 MB on disk), never with `npm install -g`.
- **Files:** the repo at `/opt/buildersinabox`; the `biab` and `bd` commands in `/usr/local/bin`; state in `/var/lib/buildersinabox`; logs in `/var/log/buildersinabox`; an autologin drop-in for `tty1` and a first-boot trigger in `/etc/profile.d/`; small shell helpers in `~/.bashrc.d/`.
- **SSH:** two drop-ins in `/etc/ssh/sshd_config.d/`. One enables password and key auth — your sudo password is the SSH credential — and because sshd takes the first value it finds for a setting and ours sorts first, it takes precedence over your own drop-ins for as long as it is installed. The other binds sshd to your private-network address only, once that network is up; if you're connected over SSH from outside it — typical on a VPS — the wizard warns you and asks first. The installer also moves sshd off Ubuntu's socket activation onto a long-running service, which is what makes that binding possible.
- **The Paseo daemon (every box, whichever AI CLI you chose):** a system service `biab-paseo.service`, run as your user, plus a watchdog timer and two small helper units, all in `/etc/systemd/system/` and root-owned. It listens on port 6767 **on your private-network address only** — not on the LAN, not on `0.0.0.0` — with Paseo's relay switched off. Its phone password is generated per box into `/etc/buildersinabox/paseo.env` (root-only, mode 0600). Its own state lives in `~/.biab/paseo`, never in an existing `~/.paseo`, which is left alone. On a cloud-profile box with no private network yet, the daemon waits for it instead of starting early.
- **Workspace:** `~/ai-platform/` scaffolded in the target user's home, plus Claude Code skills in `~/.claude/skills/` and a few fail-open hooks in `~/.claude/settings.json`.
- **The shell-command guard (see [what each AI CLI gets](#what-each-ai-cli-gets)):** added to your own files only, as your user, never through a link, and only adding entries you do not already have. On an Antigravity box, the `biab-guard` plugin in `~/.gemini/config/plugins/biab-guard`; on a Codex box, an entry in `~/.codex/hooks.json` that Codex runs only after you approve it with `/hooks`; on an OpenCode box, deny keys at the end of `permission.bash` in `~/.config/opencode/opencode.json`. Nothing under `/etc`, no `sudo` at run time, no network. `touch ~/.biab/hooks-disabled` (or `BIAB_HOOKS_DISABLED=1`) stops Builders in a Box from adding it and silences the script guards.
- **Optional packs only when you ask:** the base install adds nothing heavyweight and schedules nothing. `biab pack add browser` installs Chromium, a dedicated `biab-browser` system user, and a tightly-scoped `sudoers` rule (NOPASSWD for exactly `/usr/local/bin/biab-browse`). `biab pack add night-shift` installs `/usr/local/bin/biab-night-shift`, a `biab-night-shift` systemd service and timer in `/etc/systemd/system/` (root-owned, so the agent cannot rewrite its own schedule or drop its own guard), and a state tree under `/var/lib/buildersinabox/night-shift/` — enabled but disarmed, spending nothing until you run `biab-night-shift arm`. `biab pack remove <name>` reverses either of them.

To remove all of it:

```bash
sudo /opt/buildersinabox/payload/install.sh --uninstall
```

That stops and removes the Paseo daemon, its watchdog, its units, its pinned
tree, its credential and `~/.biab/paseo` (only if it carries our ownership
marker — a Paseo home it did not create is never touched), and removes both SSH drop-ins and puts socket activation back (on the next
boot — it deliberately won't drop the listener under you if you're uninstalling
over SSH), so sshd returns to your distribution's defaults.

What it deliberately does **not** undo: your home directory, your private-network
membership, your GitHub and agent logins, your account password, and the packages
it installed (jq, gh, Node, the mesh-VPN client, your AI CLI) and the Paseo app on your phone.

## Security model

Early-2026 scans found tens of thousands of self-hosted AI agent boxes exposed to the public internet, most with authentication bypasses. Builders in a Box is designed so the end state is nothing exposed:

- **sshd binds to your private network, not the internet.** Once the private network is up, sshd is restricted to your private-network address only — and Ubuntu's `ssh.socket` activation is disabled so that bind actually holds. On a home box or homelab behind NAT, nothing ever listens on the open internet: no port forwarding, no public IP, no reverse proxy. On a VPS with a public IP, the box reaches that same private-only end state — see the next point for how it gets there without locking you out.
- **On a cloud VPS, SSH stays your provider's.** Installing with
`--profile=cloud` means Builders in a Box writes no sshd drop-in, never enables
password authentication, never switches socket activation and never binds sshd
to your private network. The profile is persisted, so `biab update` cannot
revert it. In exchange, the provider's listener stays reachable until *you*
close inbound TCP/22 in your own console — the box reports that honestly rather
than claiming it is private. Full walkthrough in [`docs/cloud.md`](docs/cloud.md).
- **Lockout-safe on a dedicated box or self-managed VPS.** If you set the box up over its public IP, it never silently locks SSH to the private network mid-session (that could cut you off). Instead: if one of your SSH keys is present, the public listener is hardened to **key-only** (no password, not brute-forceable); if only a password exists, SSH is held open with a loud warning and is **not** reported as secured until you acknowledge it. It moves to private-network-only automatically when you finish `/tutorial` (which imports your GitHub key) or when you re-run the finalize step from a session on that network. Recovery routes are documented in [SECURITY.md](SECURITY.md).
- **Auth stays inside your private network.** In the end state, SSH (your private-network SSH, your GitHub public keys, or your sudo password) is reachable only from devices on that private network. Root login over SSH is key-only (`prohibit-password`).
- **The Paseo daemon is private-network only, and its password is not a wall against your own agents.** The daemon binds to your private-network address and nothing else, with the relay off; the bind, the relay switch and the password sit in a root-owned unit, so the agents it launches cannot loosen them through their own config. The phone password is a per-box secret that keeps other devices on your private network from pairing. It lives in the environment of the Paseo processes, and **any agent running as the box user can read it from `/proc/<pid>/environ`**. That matches how Paseo works — your agents already run under that daemon with your permissions — so treat the password as protection for the app connection, never as protection against the agents on your box. See [SECURITY.md](SECURITY.md).
- **Auditable install.** The script served at `buildersinabox.com/install.sh` is pinned to the release tag it shipped with, so the code you read is the code it fetches. [What it changes](#what-it-changes-on-your-system) lists every path it touches; `--uninstall` reverses it.

## Roadmap

Wi-Fi first boot, more hardware-tested images, and more optional capability packs (`biab pack`) beyond the browser.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md). Be excellent to each other: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

MIT — see [LICENSE](LICENSE). Builders in a Box is published by SixSeven Apps.
