# Your Builders in a Box

<!-- BIB:paseo:start -->
You made it. The device is configured. From now on you open your box
from the **Paseo app** on your phone (or laptop), over your private
Tailscale network. Your agent and your projects are workspaces in the
app; they keep running on the box when you close it, and you pick up
exactly where you left off. No SSH client needed day to day.
<!-- BIB:end -->

## Start here

<!-- BIB:paseo:start -->
Open the Paseo app and look for the workspace **"BIAB · ai-platform"**
with the agent **"BIAB · Start here"**. It is already running and
greets you on its own: it opens the tutorial for you.
<!-- BIB:end -->
<!-- BIB:codex:start -->
(In Codex you invoke skills as `$tutorial`, not `/tutorial`.)
<!-- BIB:end -->
<!-- BIB:opencode:start -->
(OpenCode loads skills through its own `skill` tool: you do not type
`/tutorial`, you ask for it, for example "run the tutorial skill".)
<!-- BIB:end -->
<!-- BIB:paseo:start -->

Not paired yet? Run this on the box and follow the steps it prints:

    sudo biab paseo pair
<!-- BIB:end -->

The tutorial is the guided onboarding: 8 short beats, ~10 minutes,
skippable. It covers GitHub auth, the two bundled project specs,
creating your first project, how your AI's context changes by folder,
giving each project its own place to work, and the SDD skills with a
live demo of `/sdd-coordinator`.

If the tutorial is already done and you want to refresh the bigger
picture, type `/whats-ahead`. To set up additional projects later, use
`/first-project` and `/second-project`.

## How you connect from your phone (or laptop)

During setup, the wizard asks whether you are continuing from a laptop or
phone, then shows only the steps for that device. This page keeps the
route as a reference for later.

<!-- BIB:paseo:start -->
The simple, default way is the Paseo app over your private Tailscale
network:

1. Install the **Paseo** app from your phone's app store.
2. Make sure **Tailscale** is connected on that device, signed in with
   the same account you used during setup.
3. In the app, open Settings, then Add host, then choose **Direct
   connection**. Enter the host, port and password that
   `sudo biab paseo pair` prints on the box. Leave "Use SSL" off.
4. The app lists your workspaces. Right after setup you'll see one:
   "BIAB · ai-platform". As you create projects via `/first-project`,
   each one adds its own workspace.

Tap a workspace to open it, then start a new agent there or open one
that is already running.
<!-- BIB:end -->

## What's running right now

<!-- BIB:paseo:start -->
A small background service, `biab-paseo`, that the app talks to. It
listens only on your Tailscale network (never on your home network or
the internet), asks for the password, and has its relay switched off. A
watchdog restarts it if it stops; `biab status` shows how it is doing.

Your first agent runs in the workspace `~/ai-platform/` with the
`/tutorial` skill. As you create projects, each one becomes its own
workspace with its own agents.
<!-- BIB:end -->
<!-- BIB:opencode:start -->

OpenCode runs in the app with permission rules that BIAB wrote in
`~/.config/opencode/opencode.json`: it asks you before it edits a file,
fetches a web page or runs a shell command, except for a few read-only ones
(`git log`, `ls`, `pwd`). OpenCode itself allows
everything unless told otherwise, so BIAB only offers it in the app while that
file still asks. If you change it so that edits or commands no longer ask,
the next `biab update` says so and OpenCode stays reachable
over SSH. Two limits: a project that has its own `opencode.json` can override
these rules, and "Always allow" in the app lasts for the session. OpenCode does
not get the night shift.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->

Antigravity runs in the app through its `agy acp` mode. It asks you before
it runs a shell command, writes a file in the project, your home folder,
`~/.biab` or `/var/tmp`, or reads a file outside your project: the request
shows up in the app and waits for your answer. It does not ask before it reads
inside the project, searches the web, opens a web page or writes in `/tmp`. The
prompt offers only allow once or reject, with no always-allow; the Auto Accept
switch is separate.
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
- `/tutorial` — the post-install onboarding (8 beats, ~10 min). Starts
  by itself the first time you open your first agent; can be re-invoked
  any time to pick up at the next un-done beat.
- `/first-project` — invoked from `/tutorial` Beat 4, also standalone.
  Picks a name, scaffolds the folder, copies the chosen FEAT spec, init
  + commit + GitHub push (if authed), makes it a workspace of its own.
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

## Switching contexts

<!-- BIB:paseo:start -->
Every project is its own workspace in the app, with its own agents and
its own folder. Open another workspace to switch context. For a side
folder that is not a project, run
`/opt/buildersinabox/paseo/bin/biab-workspace <folder>` and it shows up
in the app too.
<!-- BIB:end -->

<!-- BIB:guard-claude:start -->
## Shell-command guard

On Claude Code the shell-command guard is the **Guardrail** hook described just
below: before a shell command runs, it blocks the clearly destructive ones and
asks you about the risky-but-legit ones. It is a brake, not a lock: a list of
patterns that catches the common ways to destroy a box, not a sandbox, and it
lives in a file in your home folder, so an agent you let edit its own settings
can change it. `biab status` shows whether it is registered.

<!-- BIB:end -->
<!-- BIB:guard-codex:start -->
## Shell-command guard

Builders in a Box registers one guard for Codex. Before a shell command runs, it
refuses the clearly destructive ones (`rm -rf /`, `mkfs`, `dd` to a disk, a
fork bomb, `curl … | sudo bash`, a force-push to `main`/`master`).

**It needs your approval once.** Codex runs a hook only after you approve it:
SSH in, run `codex`, type `/hooks` and approve the Builders in a Box entry.
Until then `biab status` says PENDING APPROVAL and Codex skips the guard
(`codex exec` too). If the entry is edited later, Codex asks again and
`biab status` tells you.

What it does not do. It never asks you to confirm anything: a plain
`curl … | bash` or a `--force-with-lease` push is left to Codex's own approval
rules. It is a list of patterns, not a sandbox, so a destructive command written
in a way no pattern lists gets through. And it is a brake, not a lock: it lives
in `~/.codex/hooks.json`, in your home folder, so an agent you let edit its own
settings can remove it (`biab status` notices). The guard has been checked
against Codex's own hook list in tests; watching it refuse a command in a real
logged-in session is still to be done.
<!-- TODO(2026-11-05): drop the last sentence once the hardware pass (FEAT-042 T6) has seen it block. -->

To turn it off: `touch ~/.biab/hooks-disabled`, or set `BIAB_HOOKS_DISABLED=1`,
or switch the entry off in `/hooks`.

<!-- BIB:end -->
<!-- BIB:guard-opencode:start -->
## Shell-command guard

OpenCode already asks before it runs a shell command (above). On top of that,
Builders in a Box adds deny rules to `permission.bash` in
`~/.config/opencode/opencode.json`, after your own keys and never changing one of
yours. They refuse the plain forms of `mkfs`, `wipefs`, `dd` to a disk, a
redirect onto a disk, `parted` and `sgdisk` writes, a recursive `rm`, `chmod` or
`chown` of `/` or your home folder, and a force-push to `main`/`master`.

**This guard covers a smaller set than the one Claude Code and Codex get, and
`biab status` says PARTIAL.** OpenCode matches each command against fixed text
patterns, not regular expressions, so some forms get through: a pipe into a
shell (`curl … | bash`), a quoted target (`rm -rf "/"`), `rm -rf /*`, commands
inside `bash -c`, a command that starts with something else (`sudo` before a
force-push, `env`, `VAR=1 rm`), and a command split over two lines. A few harmless
commands can be refused too, such as `git push -f` to a branch whose name
contains `main`.

Two more limits. Whether a subagent obeys these rules is not confirmed. And a
project's own `opencode.json` that allows everything, or the
`OPENCODE_PERMISSION` and `OPENCODE_CONFIG_CONTENT` settings, override them.
It is a brake, not a lock: the file is yours.

To turn it off: `touch ~/.biab/hooks-disabled` stops Builders in a Box from
adding rules. The ones already in the file stay; to remove them, delete the keys
printed by `bash /opt/buildersinabox/payload/hooks/opencode-guard.sh keys`.

<!-- BIB:end -->
<!-- BIB:no-guard:start -->
## No shell-command guard here

Builders in a Box adds no shell-command guard of its own to this AI CLI. What
protects the box here is the CLI's own permission prompts (described above), and
they are only as good as your answers: read a command before you allow it.
`biab status` shows this as `guard none`.

<!-- BIB:end -->
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

(These hooks are in Claude Code's own settings format. The other AI CLIs have their own guard, or none: see "Shell-command guard" above.)

<!-- BIB:end -->
<!-- BIB:paseo:start -->
## Backup access — SSH

If the Paseo app ever can't reach your box, there's a fallback that
needs no app at all:

1. Install Termius (or any SSH client) on your phone.
2. Add a host with the name shown by `tailscale status` on the device
   (it's the device's name on your tailnet).
3. Auth is your account password, or your GitHub key if you imported one.
4. Once in, start your AI CLI by hand (`claude`, `codex` or `agy`).

Your GitHub SSH keys are also in `~/.ssh/authorized_keys` so a raw
`ssh <username>@<tailscale-ip>` works too. `biab status` prints this
command whenever the app service is not healthy.
<!-- BIB:end -->

## If SSH ever fails

<!-- BIB:paseo:start -->
SSH over Tailscale is your fallback when the app can't reach the box, so
keep these handy:
<!-- BIB:end -->

- Check the box is on your tailnet: run `tailscale status` from another
  device. If the box is offline there, power-cycle it.
- Your GitHub SSH keys are in `~/.ssh/authorized_keys`, so `ssh
  <username>@<tailscale-ip>` works with your key instead of the password.
<!-- BIB:antigravity:start -->
- If `agy` says you're signed out, SSH in and run `agy` once
  interactively to redo the Google OAuth (choose "Google OAuth", paste
  the authorization code).
<!-- BIB:end -->
<!-- BIB:opencode:start -->
- If `opencode` says you're signed out, SSH in and run `opencode auth login`
  (choose OpenCode Go or Zen and paste your key from https://opencode.ai/auth,
  or pick another provider you pay for).
<!-- BIB:end -->
<!-- BIB:codex:start -->
- If `codex` says you're signed out, SSH in and run `codex login
  --device-auth` (make sure "device code login" is enabled in ChatGPT →
  Settings → Security first), or forward the login port and log in
  normally: `ssh -L 1455:localhost:1455 <username>@<tailscale-ip>` then
  `codex login`.
<!-- BIB:end -->

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
<!-- BIB:claude:start -->
~/.claude/skills/                <- same skills, symlinked from above
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
~/.claude/skills/                <- same skills, symlinked from above
<!-- BIB:end -->
~/.bashrc.d/                     <- shell helpers (e.g. git-helpers.sh)
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
      t="$(sudo mktemp /var/lib/buildersinabox/state.XXXXXX)" && \
      sudo jq '.phases.ai_cli_done = true' \
        /var/lib/buildersinabox/state.json | sudo tee "$t" >/dev/null && \
      sudo mv "$t" /var/lib/buildersinabox/state.json && \
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
<!-- BIB:codex:start -->
## The Codex login uses a device code — what to do

Codex signs in with your ChatGPT account using a device code. First,
from any browser, turn ON "device code login" in ChatGPT → Settings →
Security (without it the code login is refused). Then, in an SSH session,
run the login — the URL + short code appear in a real terminal where you
can long-press to copy (phone) or click-and-drag (laptop):

    ssh {{TARGET_USER}}@{{HOSTNAME}}
    codex login --device-auth   # open the URL, enter the code, approve

If the code login won't work at all, forward Codex's local login port and
log in the normal way instead:

    ssh -L 1455:localhost:1455 {{TARGET_USER}}@{{HOSTNAME}}
    codex login
<!-- BIB:end -->

## When something feels off

<!-- BIB:paseo:start -->
- **The app can't connect:** run `biab status` on the box (or over SSH). It
  says whether the app service is healthy and, if not, prints the SSH
  command that still works. Also check that Tailscale is on in your phone.
- **The app asks for the password again, or you changed phones:** run
  `sudo biab paseo pair` to see the values, or `sudo biab paseo pair
  --rotate` for a new password.
- **`biab status` says the service gave up:** run `sudo biab paseo restart`.
<!-- BIB:end -->
<!-- BIB:claude:start -->
- **Claude says "please login" or refuses to start:** SSH in (fallback
  path above), run `claude` once interactively, do the login again.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
- **`agy` says "please sign in" or refuses to start:** run `agy` once
  interactively over SSH and redo the Google OAuth.
<!-- BIB:end -->
<!-- BIB:opencode:start -->
- **`opencode` says it has no credentials or refuses to start:** run
  `opencode auth login` over SSH and paste your key again.
<!-- BIB:end -->
<!-- BIB:codex:start -->
- **`codex` says "please sign in" or refuses to start:** run `codex login
  --device-auth` over SSH (enable "device code login" in ChatGPT →
  Settings → Security first), or forward the port and run `codex login`.
<!-- BIB:end -->
- **Can't reach the device at all:** check `tailscale status` from
  another device on your tailnet. If the mini PC is offline there,
  power-cycle it.
- **Wizard didn't finish and you want to restart it:** as root, run
  `touch /var/lib/buildersinabox/firstboot.pending` and reboot.

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
<!-- BIB:paseo:start -->
The one extra thing running is the phone-app service: it listens only on
your private Tailscale network, asks for a password, and has its relay
switched off. `sudo /opt/buildersinabox/payload/install.sh --uninstall`
removes it.
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
