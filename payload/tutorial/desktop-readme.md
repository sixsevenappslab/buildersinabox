# Your Builders in a Box

You made it. The device is configured. From now on, everything happens
from your phone via SSH + tmux + Claude Code.

## Start here

Open any of the three tmux windows and type:

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

## What's running right now

A persistent tmux session called `main` with three windows, each running
your AI CLI ({{AI_CLI}}):

- **`platform`** — for changes to your dev environment itself
  (`~/ai-platform/`).
- **`{{PROJECT_NAME}}`** — your first project
  (`~/ai-platform/projects/{{PROJECT_NAME}}/`).
- **`stratops`** — your personal strategy & ops space — OKRs, roadmap,
  notes (`~/ai-platform/stratops/`).

If you ever close the session by accident:

```
tmux attach -t main          # reattach to the existing session
~/ai-platform/payload/tmux/launch-main.sh   # rebuild it from scratch
```

## Connecting from your phone

You should already have Termius installed. Two ways to log in:

**Easy (Tailscale SSH):** in Termius, add a new host using the name shown
by `tailscale status`. No SSH key needed — Tailscale handles auth.

**Backup (raw SSH):** if Tailscale SSH ever fails, your GitHub SSH keys
are also in `~/.ssh/authorized_keys`. So `ssh biab@<tailscale-ip>` from
any machine with your GitHub key works too.

Once connected, run `tmux attach -t main`.

## Talking to Claude

When you're inside any of the three tmux windows, just type. Claude
listens. Try:

> *"Help me sketch what a slack scheduler would look like"*

> *"Walk me through writing a small Python script that watches my
>  downloads folder and renames PDFs."*

> *"Review what I just changed and tell me if anything looks wrong."*

## Skills — Claude with specific expertise

This device ships with **15 pre-loaded skills**. Type `/` inside any
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

## Sharing a session — `/remote-control`

If you want someone else (a friend, a teammate, the person who gave you
this device) to see your Claude Code session live and even take over,
type:

```
/remote-control
```

inside any Claude Code window. It generates a link you can share. The
other person can read along, jump in, hand control back. Use it for pair
programming, demos, or when you want help and "here's my screen" beats
explaining.

## Switching contexts with tmuxc

You have a function called `tmuxc` available everywhere:

```
tmuxc                 # list sessions, pick one
tmuxc <name>          # attach (or create) a session
tmuxc <name> <dir>    # create with a specific cwd
tmuxc kill <name>     # close one

tmuxa                 # shortcut: attach to 'main'
```

Use it when you want a side context — e.g. `tmuxc scratch ~/tmp` for a
throwaway poke at something, while your `main` session keeps running.

## Where things live

```
~/ai-platform/                   <- your workspace root
├── CLAUDE.md / GEMINI.md / AGENTS.md
├── projects/
│   └── {{PROJECT_NAME}}/
│       ├── CLAUDE.md / GEMINI.md / AGENTS.md
│       └── specs/
│           ├── draft/FEAT-002-personal-slack-coach.md   <- your first work
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

- **Claude says "please login" or refuses to start:** SSH in, run
  `claude` once interactively, do the login again. It happens when the
  device-flow token expires.
- **Termius can't connect:** check `tailscale status` from another
  device on your tailnet. If the mini PC is offline there, power-cycle
  it.
- **Wizard didn't finish and you want to restart it:** as root, run
  `touch /var/lib/buildersinabox/firstboot.pending` and reboot.

## What this box is — and isn't

It's **yours**. You own the hardware, the data, the keys. Nothing here
phones home except the Claude/Gemini API calls *you* make on *your*
account.

It's **not** a managed service. There's no support team. If a Claude
update changes a CLI flag and something breaks, you (or the person who
gave it to you) need to fix it. The whole thing is open code under
`~/ai-platform/payload/` — read it, change it, make it yours.
