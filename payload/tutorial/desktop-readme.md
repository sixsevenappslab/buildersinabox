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

## How you connect from your phone

The simple, default way:

1. Install **Claude Code** from the app store on your phone.
2. Sign in with the same Claude account you used during setup.
3. The app discovers your three remote-controlled sessions
   (`platform`, `{{PROJECT_NAME}}`, `stratops`) and lists them.
4. Tap any of them to attach. You're inside, exactly where you left off.

No SSH key paste. No host configuration. No "did I attach to the right
session". The app does it for you because /remote-control was activated
in every window automatically during setup.

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

This device ships with **18 pre-loaded skills**. Type `/` inside any
Claude Code window and start typing the name. A few you might want:

### Guided onboarding
- `/first-project` — your guided first-day walkthrough (Git, GitHub, your
  first commit, hand-off to FEAT-002, the bundled coach spec).
- `/second-project` — your second guided project: walks you through
  picking a cloud platform (Cloudflare, Firebase or GCP), buying a
  domain, and starting FEAT-003 (a personal finance app that ships to
  production).
- `/whats-ahead` — 5-minute narrative tour of the system.

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

## What this box is — and isn't

It's **yours**. You own the hardware, the data, the keys. Nothing here
phones home except the Claude/Gemini API calls *you* make on *your*
account, plus the Claude Code app's remote-control channel that *you*
explicitly enabled.

It's **not** a managed service. There's no support team. If a Claude
update changes a CLI flag and something breaks, you (or the person who
gave it to you) need to fix it. The whole thing is open code under
`~/ai-platform/payload/` — read it, change it, make it yours.
