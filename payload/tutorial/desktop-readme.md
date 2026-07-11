# Your Builders in a Box

<!-- BIB:claude:start -->
You made it. The device is configured. From now on, everything happens
through the **Claude Code mobile app** — no SSH client, no manual
`tmux attach`, no typing commands to reconnect. The sessions are
already running on this device and exposed via Claude Code's
**Remote Control** feature, so the mobile app sees them and lets
you jump straight in.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
You made it. The device is configured. From now on you reach it from
your phone (or laptop) over **SSH through Tailscale**, and pick up your
work by attaching to a persistent **tmux** session. The AI sessions are
already running on this device and survive disconnects — you attach,
you're back exactly where you left off.
<!-- BIB:end -->

## Start here

<!-- BIB:claude:start -->
Open the `ai-platform` session (in the Claude Code app sidebar, or via
`tmux attach -t ai-platform` from a terminal). Claude greets you on its
own — the `/tutorial` skill runs automatically the first time.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
SSH into the box and attach the `ai-platform` session:

    tmux attach -t ai-platform

Antigravity (`agy`) greets you on its own — the `/tutorial` skill runs
automatically the first time.
<!-- BIB:end -->

The tutorial is the guided onboarding: 8 short beats, ~10 minutes,
skippable. It covers GitHub auth, the two bundled project specs,
creating your first project, how your AI's context changes by folder,
spawning new tmux sessions per project, and the SDD skills with a
live demo of `/sdd-coordinator`.

If the tutorial is already done and you want to refresh the bigger
picture, type `/whats-ahead`. To set up additional projects later, use
`/first-project` and `/second-project`.

## How you connect from your phone (or laptop)

<!-- BIB:claude:start -->
The simple, default way:

1. Install **Claude Code** from the app store on your phone.
2. Sign in with the same Claude account you used during setup.
3. The app discovers your remote-controlled sessions and lists them.
   Right after install you'll see one: `ai-platform`. As you create
   projects via `/first-project`, each new project adds its own
   session to the sidebar.
4. Tap any of them to attach. You're inside, exactly where you left off.

No SSH key paste. No host configuration. No "did I attach to the right
session". The app does it for you because /remote-control was activated
in every window automatically during setup.

**Also works on your laptop.** Claude Code has a Mac/Windows/Linux app
too — install it, sign in with the same account, and you'll see the
exact same sessions there. Same conversation, same context, just
on a bigger screen with a real keyboard. Use the phone for quick
checks; switch to the laptop for deep work. The session doesn't care
where you are.

### Why no Termius / no SSH?

Because Claude Code app's remote control over your already-running
sessions is the smoothest interface for the way you'll actually use
this device — phone, coffee shop, sofa, in the car. SSH still works as a fallback
(see "Backup access" below), but you shouldn't need it day to day.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
The simple, default way is SSH over your private Tailscale network:

1. Install **Termius** (or any SSH client) on your phone — on a laptop
   the built-in terminal is enough.
2. Make sure **Tailscale** is connected on that device, signed in with
   the same account you used during setup. Your box shows up on your
   tailnet under the name from `tailscale status`.
3. Connect with Tailscale SSH (no key paste needed):

       ssh {{TARGET_USER}}@{{HOSTNAME}}

4. Attach your session:

       tmux attach -t ai-platform

You're inside, exactly where you left off. As you create projects via
`/first-project`, each one gets its own tmux session — attach any of
them by name with `tmux attach -t <name>` (or the `tmuxc` helper below).

**Works the same from your laptop** — same tailnet, same `ssh` + `tmux
attach`, just a bigger screen and a real keyboard. The session doesn't
care where you are; it keeps running on the box.

Detach any time with `Ctrl-b d` — the session and `agy` keep running,
ready for you to re-attach later.
<!-- BIB:end -->

## What's running right now

<!-- BIB:claude:start -->
A persistent tmux session called `ai-platform`, cwd `~/ai-platform/`,
running your AI CLI (claude) with Remote Control already enabled
via the `--remote-control` flag. As you create projects, each one gets
its own session — same shape, different folder, separate sidebar item
in the Claude Code app.

If Remote Control ever needs to be re-enabled (after a daemon restart,
for example), just rerun `/opt/buildersinabox/payload/tmux/launch-main.sh`.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
A persistent tmux session called `ai-platform`, cwd `~/ai-platform/`,
running Antigravity (`agy`) with the `/tutorial` skill. As you create
projects, each one gets its own tmux session — same shape, different
folder, attach by name.

If the session ever disappears (after a reboot without autostart, for
example), just rerun `/opt/buildersinabox/payload/tmux/launch-main.sh`.
<!-- BIB:end -->

## Talking to your AI

When you're inside any session, just type. Your AI listens.
Try:

> *"Help me sketch what a slack scheduler would look like"*

> *"Walk me through writing a small Python script that watches my
>  downloads folder and renames PDFs."*

> *"Review what I just changed and tell me if anything looks wrong."*

## Skills — your AI with specific expertise

This device ships with **19 pre-loaded skills**. Type `/` inside any
session and start typing the name. A few you might want:

### Guided onboarding
- `/tutorial` — the post-install onboarding (8 beats, ~10 min). Auto-fires
  the first time you attach `ai-platform`; can be re-invoked any time
  to pick up at the next un-done beat.
- `/first-project` — invoked from `/tutorial` Beat 4, also standalone.
  Picks a name, scaffolds the folder, copies the chosen FEAT spec, init
  + commit + GitHub push (if authed), spins up a new tmux session.
- `/second-project` — your second guided project walk-through: picking a
  cloud platform (Cloudflare, Firebase or GCP), buying a domain, and
  starting FEAT-003 (the personal finance app that ships to production).
- `/whats-ahead` — refresher tour of the system once the tutorial is done.
- `/extend-yourself` — when you want to teach the device a new trick
  (skill, shell helper, wizard step, bundled FEAT). Walks you through
  where to put what.

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
containing a `SKILL.md`. It's symlinked into your AI CLI's skills path
automatically (that's what `biab add` does).

## Switching contexts with tmuxc

Inside the device you also have a function called `tmuxc` available
everywhere:

```
tmuxc                 # list sessions, pick one
tmuxc <name>          # attach (or create) a session
tmuxc <name> <dir>    # create with a specific cwd
tmuxc kill <name>     # close one

tmuxa                 # shortcut: attach to 'ai-platform'
```

Use it when you want a side context — e.g. `tmuxc scratch ~/tmp` for a
throwaway poke at something, while your `ai-platform` session keeps running.

<!-- BIB:claude:start -->
## Hooks — automatic guardrails and polish

Your box ships four Claude Code hooks, on by default. They run automatically
around what the agent does — no prompting needed:

- **Guardrail** — before any shell command runs, it blocks the
  unambiguously destructive ones (`rm -rf /`, `mkfs`, `dd` to a disk, a
  fork bomb, `curl … | sudo bash`, a force-push to `main`/`master`) and asks
  you to confirm the risky-but-legit ones (a plain `curl … | bash`, a
  `--force-with-lease` push). Everyday commands pass straight through.
- **Formatter** — after the agent edits or writes a file, it runs your
  project's formatter (prettier / black / ruff / gofmt / rustfmt / shfmt) on
  that file. No formatter installed? It does nothing.
- **Lint feedback** — runs your project's linter on the edited file and hands
  any findings back to the agent so it can self-correct. It never blocks the
  edit.
- **Session log** — when a session ends, it appends one line to
  `~/.claude/logs/biab-sessions.log` (timestamp, session, folder, how many
  edits/commands, which files were touched). Metadata only — never your
  commands, file contents or secrets. Handy for auditing unattended work.

Everything degrades cleanly: if a formatter or linter isn't installed, the
hook simply does nothing.

**To turn them off**, pick one:

- Remove the `hooks` key from `~/.claude/settings.json` (or just the block
  you don't want).
- Set `BIAB_HOOKS_DISABLED=1` in your environment.
- Create the sentinel file: `touch ~/.claude/hooks-disabled`.

(Hooks are a Claude Code feature — Antigravity boxes don't get them yet.)

## Sharing a session live

You can also share any active session with someone else (a friend, a
teammate, the person who gave you this device). They get a link, they
see your screen live, they can take over to help. The remote-control
machinery is already on by default in your `ai-platform` session (and any
project sessions you create), so any of them is shareable — ask Claude
in-session and it'll generate the link.

## Backup access — Termius / SSH

If the Claude Code app ever can't reach a session (Anthropic outage,
your account locked, anything weird), there's a fallback:

1. Install Termius (or any SSH client) on your phone.
2. Add a host with the name shown by `tailscale status` on the device
   (it's the device's name on your tailnet).
3. Tailscale SSH handles auth — no key paste needed.
4. Once in, run `tmux attach -t ai-platform`.

Your GitHub SSH keys are also in `~/.ssh/authorized_keys` so a raw
`ssh <username>@<tailscale-ip>` works too. Both are belt-and-suspenders for
the rare day when the primary path is down.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
## Sharing a session live

tmux lets more than one client attach to the same session at once, so
you can pair with someone: they SSH into the box as you (or as another
user you've added), run `tmux attach -t ai-platform`, and you both see —
and drive — the same screen. Detach with `Ctrl-b d` when you're done.
Builders in a Box does not ship a hosted "share a link" service.

## If SSH ever fails

Your primary path IS SSH over Tailscale, so keep these handy:

- Check the box is on your tailnet: run `tailscale status` from another
  device. If the box is offline there, power-cycle it.
- Your GitHub SSH keys are in `~/.ssh/authorized_keys`, so a raw
  `ssh <username>@<tailscale-ip>` works even if Tailscale SSH is off.
- If `agy` says you're signed out, SSH in and run `agy` once
  interactively to redo the Google OAuth (choose "Google OAuth", paste
  the authorization code).

**Locked out after SSH was bound to Tailscale (VPS)?** Once Tailscale is up,
sshd is restricted to your private Tailscale address only. If the tailnet
isn't routing and you can't get back in, any one of these restores access
without reinstalling:

1. From your VPS provider's web/serial console, reopen the public listener:

       sudo rm -f /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf \
                  /etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf
       sudo systemctl daemon-reload && sudo systemctl reload ssh

2. Once you can reach the box over the tailnet again, re-apply the bind:

       sudo BIB_SSH_FORCE_TAILSCALE=1 \
           /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh

   (`BIB_SSH_FORCE_TAILSCALE=1` binds without re-checking tailnet routing —
   use it only with alternative access confirmed. sshd is reloaded, not
   restarted, so an active session survives.)

3. On a mini PC, plug in a keyboard + monitor and make the same edit as (1).
<!-- BIB:end -->

## Where things live

```
~/ai-platform/                   <- your workspace root
├── CLAUDE.md / AGENTS.md
├── projects/
│   └── {{PROJECT_NAME}}/
│       ├── CLAUDE.md / AGENTS.md
│       └── specs/
│           ├── draft/FEAT-002-personal-slack-coach.md   <- your first work
│           ├── draft/FEAT-003-personal-finance-app.md   <- your second
│           ├── active/      (when you start implementing)
│           └── completed/   (when you ship)
└── stratops/
    ├── CLAUDE.md / AGENTS.md
    └── README.md

~/.agents/skills/                <- bundled skills (and any you add)
~/.claude/skills/                <- same skills, symlinked from above
~/.bashrc.d/                     <- shell helpers like tmuxc
/var/lib/buildersinabox/         <- setup state (don't touch unless asked)
/var/log/buildersinabox/         <- bootstrap + wizard logs
```

<!-- BIB:claude:start -->
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
      sudo /opt/buildersinabox/payload/install.sh
  The wizard moves on without Claude. Authenticate later by SSH'ing in
  and running `claude` then `/login`.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
## The agy login URL is long — what to do

Antigravity signs in with Google OAuth. When you launch `agy` signed
out, choose "Google OAuth" and it prints a long sign-in URL that's
painful to type by hand and too long for your phone's text-recognition
to capture reliably from a monitor.

That's why the setup wizard pauses about halfway through and asks you
to SSH in from another device — phone OR laptop, your pick. In an SSH
session the URL appears in a real terminal where you can long-press to
copy (phone) or click-and-drag (laptop), then paste straight into your
browser, sign in, and paste the authorization code back into `agy`.

If `agy` ever says you're signed out, SSH in and just run `agy` once
interactively to redo it:

    ssh {{TARGET_USER}}@{{HOSTNAME}}
    agy        # choose "Google OAuth", paste the code
<!-- BIB:end -->

## When something feels off

<!-- BIB:claude:start -->
- **Claude Code app doesn't see your sessions:** confirm `/remote-control`
  is active in each window. The launcher script
  `/opt/buildersinabox/payload/tmux/launch-main.sh` re-applies it.
- **Claude says "please login" or refuses to start:** SSH in (fallback
  path above), run `claude` once interactively, do the login again.
- **Mobile app can't reach the device at all:** check `tailscale status`
  from another device on your tailnet. If the mini PC is offline there,
  power-cycle it.
- **Wizard didn't finish and you want to restart it:** as root, run
  `touch /var/lib/buildersinabox/firstboot.pending` and reboot.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
- **`tmux attach` says no such session:** rerun the launcher —
  `/opt/buildersinabox/payload/tmux/launch-main.sh` — to recreate the
  `ai-platform` session.
- **`agy` says "please sign in" or refuses to start:** run `agy` once
  interactively over SSH and redo the Google OAuth.
- **Can't reach the device at all:** check `tailscale status` from
  another device on your tailnet. If the mini PC is offline there,
  power-cycle it.
- **Wizard didn't finish and you want to restart it:** as root, run
  `touch /var/lib/buildersinabox/firstboot.pending` and reboot.
<!-- BIB:end -->

## Recovery — starting over from scratch

You own this machine. If you ever need to wipe everything and start
fresh, reinstall Ubuntu Server 24.04 (or re-provision the VPS, or
re-flash the USB stick if this box came as a gift) and run the
installer again:

    curl -fsSL https://buildersinabox.com/install.sh | sudo bash

Your code is safe — it lives on GitHub. Reinstalling only loses local
state (logs, the local AI session, anything you haven't pushed).

To remove Builders in a Box from this machine without reinstalling
the OS:

    sudo /opt/buildersinabox/payload/install.sh --uninstall

That removes everything BIAB-owned and leaves your home directory,
Tailscale, and your GitHub and AI CLI logins untouched.

## What this box is — and isn't

It's **yours**. You own the hardware, the data, the keys. Nothing here
phones home except the AI API calls *you* make on *your* own account.
<!-- BIB:claude:start -->
The one extra channel is the Claude Code app's remote-control link, which
*you* explicitly enabled during setup.
<!-- BIB:end -->

It's **not** a managed service. There's no support team. If an upstream
update changes a CLI flag and something breaks, you (or the person who
gave it to you) need to fix it. The whole thing is open code under
`/opt/buildersinabox/` (the full git repo) and `~/ai-platform/payload/`
(your live copy) — read it, change it, make it yours.

When you want to teach the device a new trick — a new skill, a shell
helper, a wizard step, a bundled FEAT — type `/extend-yourself` in any
session. It's an interactive guide for everything you can add. The whole
system is designed to be modified by its owner; nothing is meant to stay
frozen.
