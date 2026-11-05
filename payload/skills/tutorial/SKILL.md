---
name: tutorial
description: The post-install conversational onboarding for a brand-new Builders in a Box. Runs as the first message of the agent the setup starts in the 'ai-platform' workspace and walks the user through 8 beats — orient, GitHub auth, decide a first project (own idea or an example), create it (via /first-project), teach folder-context, optional second project, show how to move between workspaces, and a tour of the installed skills including the built-in SDD workflow. Designed to be resumable, skippable, and idempotent.
---

# /tutorial — guided onboarding inside Claude Code

When the user invokes this skill — or when it auto-fires as the first message of the agent the setup started in the `ai-platform` workspace — you are their patient guide through 8 beats. Take it one beat at a time. Pause between each. Respect skips. Never dump a wall of text.

## Where you live

This skill is designed to run in the `ai-platform` workspace (cwd `~/ai-platform/`). If the user invokes it from a different folder, **work but warn** in the very first turn:

> *Heads up — I expected to be in the `ai-platform` workspace (cwd `~/ai-platform/`), but I'm actually in `<current cwd>`. I can still walk you through everything, but the bits that talk about "what folder you're in" will refer to this one, not the platform root.*

Then continue normally.

## Which AI CLI is this box running?

The user talks to you through the Paseo app on their phone (or laptop), whichever CLI the box runs. Every project is a workspace in that app. Read the CLI once at the start (`jq -r '.ai_cli // "claude"' /var/lib/buildersinabox/state.json`). Only the way you name skills and the context file differ:

- **claude** — skills are invoked with `/name`; context file is `CLAUDE.md`.
- **antigravity (`agy`)** — skills `/name`; context file `AGENTS.md`.
- **codex** — skills are invoked with `$name` (not `/name`); context file is
  `AGENTS.md`. When you mention a skill to a Codex user, write it `$tutorial`,
  `$first-project`, etc.
- **opencode** — skills are loaded through OpenCode's own `skill` tool, so the
  user does not type `/name` or `$name`; context file is `AGENTS.md`. When you
  mention a skill to an OpenCode user, name it ("the `first-project` skill") and
  offer to load it for them.

## State tracker

You keep your own state file at `~/.config/biab-tutorial/state.json`. Create the directory if needed (no sudo — it's the user's own config).

State schema:

```json
{
  "version": 1,
  "current_beat": 1,
  "done": [1, 2, 3],
  "skipped": [2]
}
```

- `current_beat`: the next un-done beat to attempt (1–8). `null` when the tutorial finished.
- `done`: beats that succeeded.
- `skipped`: beats the user explicitly skipped. These get a recap at the very end.

Read the file at every invocation. If `current_beat` is `null`, the tutorial is finished — switch to `/whats-ahead` mode (refresher of the system) instead of repeating.

If a beat is in both `done` and `skipped`, treat `done` as truth.

**Reality always wins over the state file.** Before declaring Beat 2 done because the state file says so, run `gh auth status` to confirm. If reality contradicts the state file, fix the state file silently and proceed.

Commands you'll use a lot:

```bash
# Read current state (creates default if missing)
STATE=~/.config/biab-tutorial/state.json
mkdir -p ~/.config/biab-tutorial
[ -f "$STATE" ] || echo '{"version":1,"current_beat":1,"done":[],"skipped":[]}' > "$STATE"
jq . "$STATE"

# Mark a beat done
jq --argjson n 2 '.done += [$n] | .done |= unique | .current_beat = ($n + 1)' "$STATE" > /tmp/s.json && mv /tmp/s.json "$STATE"

# Mark a beat skipped
jq --argjson n 2 '.skipped += [$n] | .skipped |= unique | .current_beat = ($n + 1)' "$STATE" > /tmp/s.json && mv /tmp/s.json "$STATE"

# Mark tutorial done
jq '.current_beat = null' "$STATE" > /tmp/s.json && mv /tmp/s.json "$STATE"
```

## Skipping

At every beat, after explaining what we're about to do, give the user an out:

> *Say "skip" to move past this — I'll remember and remind you at the end.*

When they skip, write to `.skipped`, give a ONE-line consequence summary ("you're skipping GitHub — your code stays local; we'll come back to this"), then advance to the next beat. Do not lecture.

The single beat that CAN be skipped but has the heaviest consequence is Beat 2 (GitHub). Make the consequence summary land.

## The 8 beats

### Beat 1 — Orient (1 min, mandatory)

Open warm. One short paragraph. No formatting.

> *Hey — welcome. You're talking to me from inside your mini PC. You're on the phone (or laptop) in the Paseo app, I'm on the device, and what I do here has real effect — I can read your files, run commands, install things, push code.*
>
> *This workspace is called `ai-platform`. It opens in `~/ai-platform/`, which is your workspace root. I'll explain how that matters in a few minutes.*

End with one question:

> *Ready to go? (Type anything; "skip" works for any beat from now on.)*

When they reply, mark Beat 1 done and move to Beat 2.

### Beat 2 — Connect GitHub (3 min, skippable with warning)

> *First real piece of plumbing: GitHub. So your code is backed up off this device, and so you can share it (or keep it private — your choice) later.*

The `gh auth login --web` command is interactive — it prompts "Press Enter to open browser…" and waits. Inside this Claude conversation, that prompt has no keyboard to listen to, so feed it an empty stdin and let gh print the URL + code right away:

```bash
echo "" | gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key 2>&1 &
GH_PID=$!
# Give gh ~2 seconds to print the URL + code, then surface what it said:
sleep 2
# At this point the URL is already in the user's screen via the bash output.
echo "→ Open the URL above on your phone browser, enter the 8-char code, approve."
wait "$GH_PID" || true
```

Tell the user:

> *gh just printed a URL (`https://github.com/login/device`) and an 8-character code. Open the URL on your phone browser, type that exact code, sign in to GitHub if you aren't already, click Authorize. Come back and tell me when you've done it.*

After they confirm, verify (this is the only signal that actually matters):

```bash
gh auth status 2>&1
```

If green, import the user's GitHub SSH keys into `~/.ssh/authorized_keys`. SSH into the box authenticates with the account password by default; importing their key means `ssh <user>@<tailscale-host>` from any machine holding it gets them in without typing a password on a phone keyboard.

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
if keys="$(gh api /user/keys --jq '.[].key' 2>/dev/null)"; then
  added=0
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    grep -Fqx "$k" ~/.ssh/authorized_keys || { printf '%s\n' "$k" >> ~/.ssh/authorized_keys; added=$((added+1)); }
  done <<< "$keys"
  echo "Imported $added GitHub SSH key(s) into ~/.ssh/authorized_keys."
else
  echo "No GitHub SSH keys fetched (you may have none uploaded) — you can still SSH in with your account password."
fi
```

Now close the SSH loop. On a VPS the box may still be on a public listener
(it held SSH open during the console wizard because there was no key yet).
Now that a key is in place — and the user is reaching the box over the
tailnet through the app — bind sshd to the Tailscale address if
it isn't secured yet. `BIB_SSH_FORCE_TAILSCALE=1` applies the bind directly;
because sshd is `reload`ed (never restarted), the current session survives.

```bash
STATE_JSON=/var/lib/buildersinabox/state.json
if [ -f "$STATE_JSON" ] && [ "$(jq -r '.phases.ssh_finalized // false' "$STATE_JSON")" != "true" ]; then
  echo "Securing SSH: binding it to your private Tailscale address now that a key is in place…"
  sudo BIB_SSH_FORCE_TAILSCALE=1 /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh \
    && echo "SSH is now Tailscale-only." \
    || echo "(Couldn't finalize SSH automatically — see ~/README.md 'If SSH ever fails' to bind it manually.)"
else
  echo "SSH is already bound to your Tailscale network — nothing to do."
fi
```

Tell the user plainly: on a home box behind NAT this was already done during
setup; on a VPS this is the moment SSH stops listening on the public internet
and moves to your tailnet only.

Then mark Beat 2 done. If `gh auth status` is not green: surface the actual gh error and offer one of:
- retry `gh auth login --web` (sometimes the polling times out)
- fallback to Personal Access Token: walk the user through `https://github.com/settings/tokens/new` (scopes: `repo`, `read:org`, `gist`, `workflow`), then `echo <TOKEN> | gh auth login --with-token --hostname github.com`

**If the user says "skip":**

> *Got it — skipping GitHub. Heads-up: your code will live only on this device until you set it up. If the mini PC dies, the code dies with it. I'll remind you at the end of the tutorial.*

Mark Beat 2 skipped (not done) and move on.

### Beat 3 — Your first project (2 min, mandatory but no commitment yet)

The point of this device is to build *your* thing. Lead with that:

> *So — what do you want to build? Describe anything: an app, a script, a bot, a website, a tool you wish existed. I'll help you turn it into a real project on this device, with its own folder and its own git repo.*
>
> *Not sure yet? That's fine too. This box ships with ready-made starting points you can pick from:*

```bash
/opt/buildersinabox/payload/scripts/biab-project list
```

Each line is `name`, `time`, `description`. Show them as a short numbered list (name, time, one line each), and end with:

> *You can pick one of those, describe your own idea, or skip the project for now and explore. What sounds good?*

Wait for an answer. Record whether it's a free-form idea, one of the templates, or skip. Pass that to Beat 4. Mark Beat 3 done.

### Beat 4 — Create the first project (3 min, delegates to /first-project)

You're going to invoke `/first-project` to do the actual scaffolding. Before delegating, set the env var so `/first-project` knows it's being called from the tutorial:

```bash
export BIB_TUTORIAL_PARENT=1
```

Then invoke `/first-project`, passing the choice from Beat 3 as context (a free-form idea, one of the templates, or skip). Called from the tutorial it does the setup and returns; the spec and the pull request come later, when the user says `/first-project` again. It handles:
- creating `~/ai-platform/projects/<name>/` from the chosen template (the seed CLAUDE.md, the template's spec in `specs/draft/` if it has one), without ever overwriting a file
- persisting `state.project_name` in `/var/lib/buildersinabox/state.json`
- rewriting `~/README.md` placeholders
- `git init`, first commit
- making the project its own **workspace** (via `biab-workspace`, which also tells you how this box is reached)

GitHub is not needed for any of that: the push happens at the end of the walk, and if it was skipped in Beat 2 the walk keeps everything local and says what is waiting.

When `/first-project` returns, confirm what happened:

```bash
ls ~/ai-platform/projects/
```

Tell the user:

> *Done. There's a new workspace called `BIAB · <name>` in the Paseo app — pull down to refresh the list if you don't see it yet. An agent started there opens in `~/ai-platform/projects/<name>/`, so it reads that folder's context file, not the platform-level one I'm reading here.*

Mark Beat 4 done.

### Beat 5 — Folder-context teaching moment (2 min, mandatory)

This is the conceptual core. Make it concrete.

> *Quick teaching moment, because this is the single most important thing to understand about how you'll use this device:*
>
> *Claude Code reads a file called `CLAUDE.md` from whichever folder it opens in. That file tells me what the folder is for, what conventions to follow, what the project's about.*
>
> *Right now, I'm in `~/ai-platform/`. My CLAUDE.md is the platform overview — high-level, "what does this device contain". The agent over in the `<name>` workspace is in `~/ai-platform/projects/<name>/`, so its context file is project-specific — what the project does, the spec it's working from.*
>
> *So when you want to work ON the project, you switch to that workspace. When you want to change the platform itself (install a tool, edit a wizard step, add a skill), you stay here. Different folder = different brain.*

Ask:

> *Make sense? If you want, switch over to the `<name>` workspace right now (the list in the app), ask the agent there "what's this project about", and you'll see it answer based on the FEAT spec we just dropped in. Then come back here.*

Wait for them to confirm. Mark Beat 5 done.

### Beat 6 — Second project (optional, 3 min)

> *Want to set up the second project too while we're at it? You don't have to — it just creates another workspace, no obligation to actually build it yet. Skipping is fine, I'll remind you later if you forgot. Or "yes" and I'll do it now.*

If they say yes: invoke `/first-project` again with another idea (or the other example). Same machinery as Beat 4.

If they skip: note it and move on. Don't sell.

Mark Beat 6 done or skipped.

### Beat 7 — Moving around and `/morning-check` (1 min, mandatory)

Two small things you'll use most days. Keep this beat SHORT — the user is ~25 minutes in.

**1. Moving between workspaces.**

> *Each project is its own workspace in the Paseo app, with its own agents and its own folder. To work on something, open its workspace; to start a fresh conversation, start a new agent inside it. Your agents keep running on the box when you close the app.*

If they want a workspace for a side folder (not a project), you can make one:

```bash
/opt/buildersinabox/paseo/bin/biab-workspace ~/some/folder "scratch"
```

**2. `/morning-check`** — quick "where am I" survey.

> *Type `/morning-check` at the start of a session and you get a 30-second snapshot: whether the app service is healthy, last 24h commits, open PRs, disk + RAM, tailnet. Designed for phone-from-bed mornings.*

One closing sentence, no demo:

> *There's also `bd "some idea"` — a one-line brain-dump capture you can fire from any terminal; ask me about it whenever an idea strikes.*

Mark Beat 7 done.

### Beat 8 — SDD skills tour + live demo (3 min, mandatory)

> *Last beat. You have a set of skills pre-installed — type `/` anywhere to see them. The everyday ones: `/code-review` and `/code-simplifier` for code quality, `/ux-review` and `/ui-ux-consultant` for interfaces, `/backend-engineer`, `/executive`, `/product-marketing` for on-demand expertise, `/documentator` for docs, `/morning-check` for a daily status. Plus `/first-project` and `/second-project` to spin up new work.*

Then point at the SDD workflow — it's already installed, but keep it a soft mention, not a lesson:

> *One of those skills is the heart of how this box likes to work: SDD (Spec-Driven Development). It's a team of five "voices" — a product lead, a tech lead, a QA lead, a growth voice, and a docs voice — that take an idea from "I want to build X" all the way to a reviewed spec before you write a line of code. It's already installed; `/sdd-coordinator` is the entry door. You don't have to work this way — plenty gets built by just describing what you want — but it's there the day you want a real spec behind a feature. No rush.*

Mark Beat 8 done.

### Finish — Wrap and recap (1 min)

Read state, summarise:

```bash
jq . ~/.config/biab-tutorial/state.json
```

If `skipped` is non-empty, offer to go back:

> *That's the tutorial. You skipped: <beat names>. Want to go back to any of them now? "Beat 2" for GitHub, "Beat 6" for the second project, etc. Or "no, I'm good" and I'll mark the tutorial complete.*

If they go back: re-enter that beat, run it, mark done. Loop until nothing skipped or user says no more.

If `skipped` is empty (or they're done revisiting):

```bash
jq '.current_beat = null' ~/.config/biab-tutorial/state.json > /tmp/s.json && mv /tmp/s.json ~/.config/biab-tutorial/state.json
```

> *Done. You know how to get back in, how to make a workspace for a project, how to push to GitHub, how the folder-context thing works, and that the SDD workflow is built in (`/sdd-coordinator`) for whenever you want a spec behind a feature. The next time you have an idea for a thing to build, the move is: ask me to make a workspace for the folder (`/first-project` does it for projects) → open it → describe what you want. I'll be here.*
>
> *I'm leaving you in the `ai-platform` workspace. The full guide is at `~/README.md` if you want to skim it later.*

End the skill.

## Tone

- Warm, brief, concrete. No marketing language. No "the future of dev" / "it just works" / etc.
- Each beat: at most one short paragraph of setup, then the action, then one question.
- When something fails, surface the actual error verbatim and offer to retry. Do not pretend.
- Use the user's first name (read from `${BIB_NAME}` or `whoami` if BIB_NAME is empty).

## When NOT to use this skill

- State file `current_beat` is `null` → tutorial finished. Forward to `/whats-ahead` instead.
- The user invokes a different skill mid-tutorial (e.g. `/sdd-coordinator` directly). Don't try to recapture — they know what they want.

## Idempotency contract

- Reality always wins over state. Verify before claiming "already done".
- A re-invoked beat must be safe to run again. Specifically: Beat 4 / Beat 6 delegating to `/first-project` — that skill must be idempotent (it is).
- The state file is the user's; never delete it. Never reset to beat 1 without the user explicitly asking.
