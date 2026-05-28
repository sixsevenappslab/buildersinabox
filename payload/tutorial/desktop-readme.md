# Your Builders in a Box

You made it. The device is configured. From now on, everything happens
through the **Claude Code mobile app** — no SSH client, no manual
`tmux attach`, no typing commands to reconnect. The sessions are
already running on this device and exposed via Claude Code's
**Remote Control** feature, so the mobile app sees them and lets
you jump straight in.

## Start here

Open any of the three tmux windows on screen (or jump in from the
Claude Code app, same thing) and type:

```
/first-project
```

That's an interactive walkthrough. It will explain GitHub, put your
project on GitHub for the first time, and hand you off to FEAT-002 —
the spec for your AI Slack coach that ships pre-written in your project.
You build the coach as your first real piece of work, with Claude helping.

When the coach is shipped, type `/second-project` for the next arc — a
personal finance app (FEAT-003) that you ship to a real domain. That
walkthrough also helps you open cloud accounts (Cloudflare, Firebase or
GCP) if you don't have one yet.

If you want the bigger picture first, type `/whats-ahead` instead — it's a
5-minute narrative tour of the system.

## How you connect from your phone (or laptop)

The simple, default way:

1. Install **Claude Code** from the app store on your phone.
2. Sign in with the same Claude account you used during setup.
3. The app discovers your three remote-controlled sessions
   (`platform`, `{{PROJECT_NAME}}`, `stratops`) and lists them.
4. Tap any of them to attach. You're inside, exactly where you left off.

No SSH key paste. No host configuration. No "did I attach to the right
session". The app does it for you because /remote-control was activated
in every window automatically during setup.

**Also works on your laptop.** Claude Code has a Mac/Windows/Linux app
too — install it, sign in with the same account, and you'll see the
exact same three sessions there. Same conversation, same context, just
on a bigger screen with a real keyboard. Use the phone for quick
checks; switch to the laptop for deep work. The session doesn't care
where you are.

### Why no Termius / no SSH?

Because Claude Code app's remote control over your already-running
sessions is the smoothest interface for the way you'll actually use
this device — phone, café, sofa, in the car. SSH still works as a fallback
(see "Backup access" below), but you shouldn't need it day to day.

## What's running right now

A persistent tmux session called `main` with three windows, each running
your AI CLI ({{AI_CLI}}) with `/remote-control` already enabled:

- **`platform`** — for changes to your dev environment itself
  (`~/ai-platform/`).
- **`{{PROJECT_NAME}}`** — your first project
  (`~/ai-platform/projects/{{PROJECT_NAME}}/`).
- **`stratops`** — your personal strategy & ops space — OKRs, roadmap,
  notes (`~/ai-platform/stratops/`).

If `/remote-control` ever needs to be re-enabled (after a daemon restart,
for example), open a fresh session via Termius and type `/remote-control`
in each window — or just rerun `~/ai-platform/payload/tmux/launch-main.sh`
which does it for you.

## Talking to Claude

When you're inside any of the three sessions, just type. Claude listens.
Try:

> *"Help me sketch what a slack scheduler would look like"*

> *"Walk me through writing a small Python script that watches my
>  downloads folder and renames PDFs."*

> *"Review what I just changed and tell me if anything looks wrong."*

## Skills — Claude with specific expertise

This device ships with **19 pre-loaded skills**. Type `/` inside any
Claude Code window and start typing the name. A few you might want:

### Guided onboarding
- `/first-project` — your guided first-day walkthrough (Git, GitHub, your
  first commit, hand-off to FEAT-002, the bundled coach spec).
- `/second-project` — your second guided project: walks you through
  picking a cloud platform (Cloudflare, Firebase or GCP), buying a
  domain, and starting FEAT-003 (a personal finance app that ships to
  production).
- `/whats-ahead` — 5-minute narrative tour of the system.
- `/extend-yourself` — when you want to teach the device a new trick
  (a new skill, a new shell helper, a new wizard step, a new bundled
  FEAT). Walks you through where to put what.

### Building digital products end-to-end
- `/sdd-base` — read this first to understand the workflow this device
  is opinionated about (spec-driven development).
- `/sdd-coordinator` — talk to it like a Product Lead. "I want to
  build X, help me write a spec."
- `/sdd-spec-writer` — Tech Lead voice. Researches your codebase and
  drafts the technical spec.
- `/sdd-qa` — QA Lead voice. Writes test plans.
- `/sdd-growth` — Growth voice. Useful when a feature touches
  marketing or onboarding.
- `/sdd-docs` — Plans the docs work after a feature ships.

### Expert consultancy on demand
- `/backend-engineer` — senior backend perspective.
- `/ui-ux-consultant` — UI/UX advice.
- `/executive` — strategy and prioritization.
- `/product-marketing` — positioning, conversion, growth.

### Code-level tools
- `/code-review` — pass it a diff or branch, get a structured review.
- `/code-simplifier` — refactors recent code for clarity.
- `/qa-testing` — generates a test plan from a spec.
- `/documentator` — generates technical docs (CLAUDE.md, changelogs).
- `/ux-review` — UX heuristic evaluation.

Want more skills later? Drop a folder under `~/.agents/skills/<name>/`
containing a `SKILL.md`. Both Claude Code and Gemini CLI find it
automatically.

## Switching contexts with tmuxc

Inside the device you also have a function called `tmuxc` available
everywhere:

```
tmuxc                 # list sessions, pick one
tmuxc <name>          # attach (or create) a session
tmuxc <name> <dir>    # create with a specific cwd
tmuxc kill <name>     # close one

tmuxa                 # shortcut: attach to 'main'
```

Use it when you want a side context — e.g. `tmuxc scratch ~/tmp` for a
throwaway poke at something, while your `main` session keeps running.

## Sharing a session live

You can also share any active session with someone else (a friend, a
teammate, the person who gave you this device). They get a link, they
see your screen live, they can take over to help. The remote-control
machinery is already on by default in your three windows, so any of them
is shareable — ask Claude in-session and it'll generate the link.

## Backup access — Termius / SSH

If the Claude Code app ever can't reach a session (Anthropic outage,
your account locked, anything weird), there's a fallback:

1. Install Termius (or any SSH client) on your phone.
2. Add a host with the name shown by `tailscale status` on the device
   (it's the device's name on your tailnet).
3. Tailscale SSH handles auth — no key paste needed.
4. Once in, run `tmux attach -t main`.

Your GitHub SSH keys are also in `~/.ssh/authorized_keys` so a raw
`ssh paco@<tailscale-ip>` works too. Both are belt-and-suspenders for
the rare day when the primary path is down.

## Where things live

```
~/ai-platform/                   <- your workspace root
├── CLAUDE.md / GEMINI.md / AGENTS.md
├── projects/
│   └── {{PROJECT_NAME}}/
│       ├── CLAUDE.md / GEMINI.md / AGENTS.md
│       └── specs/
│           ├── draft/FEAT-002-personal-slack-coach.md   <- your first work
│           ├── draft/FEAT-003-personal-finance-app.md   <- your second
│           ├── active/      (when you start implementing)
│           └── completed/   (when you ship)
└── stratops/
    ├── CLAUDE.md / GEMINI.md / AGENTS.md
    └── README.md

~/.agents/skills/                <- bundled skills (and any you add)
~/.claude/skills/                <- same skills, symlinked from above
~/.bashrc.d/                     <- shell helpers like tmuxc
~/.config/biab-coach/secrets.env <- Slack tokens (if you ran 60-slack-bootstrap)
/var/lib/buildersinabox/         <- setup state (don't touch unless asked)
/var/log/buildersinabox/         <- bootstrap + wizard logs
```

## The Claude login URL is too long for OCR — what to do

The wizard's third login is Claude Code itself. Inside Claude's UI you
type `/login` and it prints a very long OAuth URL that's painful to
type by hand and too long for your phone's text-recognition to capture
reliably from a monitor.

That's why the setup wizard pauses about halfway through and asks you
to SSH in from another device — phone OR laptop, your pick. In an SSH
session the URL appears in a real terminal where you can long-press to
copy (phone) or click-and-drag (laptop), then paste straight into your
browser.

If you somehow ended up trying to do the Claude login on the device's
own monitor and you're stuck, SSH in from your phone or laptop:

- **From your phone**: open ConnectBot or Termius (configure host with
  your sudo password as the credential), connect, then `claude` and
  `/login`. Long-press the URL to copy.

- **From your laptop**: from any computer on your tailnet:
      ssh {{TARGET_USER}}@{{HOSTNAME}}
  Run `claude` and `/login`. Copy-paste in the terminal.

- **Skip Claude here, come back later**:
      sudo jq '.phases.ai_cli_done = true' \
        /var/lib/buildersinabox/state.json > /tmp/s.json && \
      sudo mv /tmp/s.json /var/lib/buildersinabox/state.json && \
      sudo chmod 644 /var/lib/buildersinabox/state.json && \
      sudo /opt/buildersinabox/payload/bootstrap.sh
  The wizard moves on without Claude. Authenticate later by SSH'ing in
  and running `claude` then `/login`.

## When something feels off

- **Claude Code app doesn't see your sessions:** confirm `/remote-control`
  is active in each window. The launcher script
  `~/ai-platform/payload/tmux/launch-main.sh` re-applies it.
- **Claude says "please login" or refuses to start:** SSH in (fallback
  path above), run `claude` once interactively, do the login again.
- **Mobile app can't reach the device at all:** check `tailscale status`
  from another device on your tailnet. If the mini PC is offline there,
  power-cycle it.
- **Wizard didn't finish and you want to restart it:** as root, run
  `touch /var/lib/buildersinabox/firstboot.pending` and reboot.

## Recovery — starting over from scratch

You own this hardware. If you ever need to wipe everything and start
fresh — either back to a clean Builders in a Box, or all the way back
to Windows — both paths are open.

### Option A: clean reinstall of Builders in a Box

This is the easy path. The USB stick that came with this gift is also
the recovery image — it always does the same thing:

1. Plug the USB stick into this device.
2. Power off the device. Power on again.
3. Press F7 (or F11/F12 depending on the mini PC brand) at the boot
   logo, pick "UEFI: Flash, Partition 2".
4. GRUB auto-selects "Builders in a Box — Autoinstall" after 3 seconds.
5. The disk gets wiped and Ubuntu reinstalls in ~10 minutes.
6. The wizard fires on first boot. You walk through it again.

Your code is safe — it lives on GitHub. Reinstalling only loses local
state (logs, the local Claude session, anything you haven't pushed).

### Option B: go back to Windows

The mini PC came with Windows 11 OEM. **That licence is permanently
baked into the UEFI firmware** — you didn't lose it when we wiped the
disk for Builders in a Box. To get Windows back:

1. On any other computer, download the Windows 11 installer ISO from:
       https://www.microsoft.com/software-download/windows11
   (Microsoft offers it free as a direct download.)

2. Flash that ISO onto a USB stick (at least 8 GB):
   - On Windows: use Microsoft's "Media Creation Tool" from the same page.
   - On Mac / Linux: use Balena Etcher (https://etcher.balena.io/) or Rufus.

3. Plug that Windows USB into the mini PC. Power on, press F7, pick the
   Windows installer USB.

4. Run through the Windows installer. Pick "Custom Install" and delete
   all partitions, then install onto the unallocated space.

5. When Windows boots and connects to the internet, the OEM licence
   activates itself. No product key to type, no purchase.

Whole process: ~30 minutes. You can come back to Builders in a Box any
time — just plug in the original USB stick and reinstall.

## What this box is — and isn't

It's **yours**. You own the hardware, the data, the keys. Nothing here
phones home except the Claude/Gemini API calls *you* make on *your*
account, plus the Claude Code app's remote-control channel that *you*
explicitly enabled.

It's **not** a managed service. There's no support team. If a Claude
update changes a CLI flag and something breaks, you (or the person who
gave it to you) need to fix it. The whole thing is open code under
`/opt/buildersinabox/` (the full git repo) and `~/ai-platform/payload/`
(your live copy) — read it, change it, make it yours.

When you want to teach the device a new trick — a new skill, a shell
helper, a wizard step, a bundled FEAT — type `/extend-yourself` in any
Claude Code window. It's an interactive guide for everything you can
add. The whole system is designed to be modified by its owner; nothing
is meant to stay frozen.
