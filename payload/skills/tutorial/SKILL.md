---
name: tutorial
description: The post-install conversational onboarding for a brand-new Builders in a Box. Runs as the initial prompt of the 'ai-platform' tmux session and walks the user through 8 beats — orient, GitHub auth, decide a first project (own idea or an example), create it (via /first-project), teach folder-context, optional second project, demo tmuxc, and a tour of the installed skills plus how to opt into the SDD workflow. Designed to be resumable, skippable, and idempotent.
---

# /tutorial — guided onboarding inside Claude Code

When the user invokes this skill — or when it auto-fires as the initial prompt of the `ai-platform` tmux session — you are their patient guide through 8 beats. Take it one beat at a time. Pause between each. Respect skips. Never dump a wall of text.

## Where you live

This skill is designed to run in the `ai-platform` tmux session (cwd `~/ai-platform/`). If the user invokes it from a different session, **work but warn** in the very first turn:

> *Heads up — I expected to be in the `ai-platform` session (cwd `~/ai-platform/`), but I'm actually in `<current cwd>`. I can still walk you through everything, but the bits that talk about "what folder you're in" will refer to this one, not the platform root.*

Then continue normally.

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

> *Hey — welcome. You're talking to me from inside your mini PC. This conversation is happening over Claude Code's Remote Control: you're on the phone (or laptop), I'm on the device, and what I do here has real effect — I can read your files, run commands, install things, push code.*
>
> *This session is called `ai-platform`. It opens in `~/ai-platform/`, which is your workspace root. I'll explain how that matters in a few minutes.*

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

If green: mark Beat 2 done. If not green: surface the actual gh error and offer one of:
- retry `gh auth login --web` (sometimes the polling times out)
- fallback to Personal Access Token: walk the user through `https://github.com/settings/tokens/new` (scopes: `repo`, `read:org`, `gist`, `workflow`), then `echo <TOKEN> | gh auth login --with-token --hostname github.com`

**If the user says "skip":**

> *Got it — skipping GitHub. Heads-up: your code will live only on this device until you set it up. If the mini PC dies, the code dies with it. I'll remind you at the end of the tutorial.*

Mark Beat 2 skipped (not done) and move on.

### Beat 3 — Your first project (2 min, mandatory but no commitment yet)

The point of this device is to build *your* thing. Lead with that:

> *So — what do you want to build? Describe anything: an app, a script, a bot, a website, a tool you wish existed. I'll help you turn it into a real project on this device, with its own folder and its own git repo.*
>
> *Not sure yet? That's fine too. This box ships with two worked examples you can read for inspiration or copy as a starting point:*

```bash
ls /opt/buildersinabox/payload/examples/
```

> *  - **A personal Slack coach** — an empathic AI that lives in your Slack and knows what's running on this device. (`examples/FEAT-002-personal-slack-coach.md`)*
> *  - **A personal finance dashboard** — bank CSV → AI categorisation → fund/ETF prices → shipped to a domain you own. (`examples/FEAT-003-personal-finance-app.md`)*
>
> *You can describe your own idea, base it on one of those, or skip the project for now and explore. What sounds good?*

Wait for an answer. Record whether it's a free-form idea, one of the examples, or skip. Pass that to Beat 4. Mark Beat 3 done.

### Beat 4 — Create the first project (3 min, delegates to /first-project)

You're going to invoke `/first-project` to do the actual scaffolding. Before delegating, set the env var so `/first-project` knows it's being called from the tutorial:

```bash
export BIB_TUTORIAL_PARENT=1
```

Then invoke `/first-project`, passing the choice from Beat 3 as context (a free-form idea, one of the examples, or skip). `/first-project` handles:
- creating `~/ai-platform/projects/<name>/` with seed CLAUDE.md
- if the user picked an example, copying that spec into `specs/draft/`; if free-form, writing a short starter spec from their description
- persisting `state.project_name` in `/var/lib/buildersinabox/state.json`
- rewriting `~/README.md` placeholders
- `git init`, first commit
- if GitHub is authed: `gh repo create + git push`
- if GitHub was SKIPPED in Beat 2: local commit only + leaves a TODO note in the project's CLAUDE.md
- creating a **new tmux session** named after the project (not a window in this session)
- starting `claude --remote-control <name>` in that new session

When `/first-project` returns, confirm what happened:

```bash
tmux ls
ls ~/ai-platform/projects/
```

Tell the user:

> *Done. There's a new tmux session called `<name>` — swipe to your sidebar in the Claude Code app and you'll see it appear. Inside that session, Claude is opened in `~/ai-platform/projects/<name>/`, so it reads that folder's CLAUDE.md, not the platform-level one I'm reading here.*

Mark Beat 4 done.

### Beat 5 — Folder-context teaching moment (2 min, mandatory)

This is the conceptual core. Make it concrete.

> *Quick teaching moment, because this is the single most important thing to understand about how you'll use this device:*
>
> *Claude Code reads a file called `CLAUDE.md` from whichever folder it opens in. That file tells me what the folder is for, what conventions to follow, what the project's about.*
>
> *Right now, I'm in `~/ai-platform/`. My CLAUDE.md is the platform overview — high-level, "what does this device contain". The Claude over in the `<name>` session is in `~/ai-platform/projects/<name>/`, so its CLAUDE.md is project-specific — what the project does, the spec it's working from.*
>
> *So when you want to work ON the project, you switch to that session. When you want to change the platform itself (install a tool, edit a wizard step, add a skill), you stay here. Different folder = different brain.*

Ask:

> *Make sense? If you want, switch over to the `<name>` session right now (sidebar in the app), ask Claude there "what's this project about", and you'll see it answer based on the FEAT spec we just dropped in. Then come back here.*

Wait for them to confirm. Mark Beat 5 done.

### Beat 6 — Second project (optional, 3 min)

> *Want to set up the second project too while we're at it? You don't have to — it just creates another session, no obligation to actually build it yet. Skipping is fine, I'll remind you later if you forgot. Or "yes" and I'll do it now.*

If they say yes: invoke `/first-project` again with another idea (or the other example). Same machinery as Beat 4.

If they skip: note it and move on. Don't sell.

Mark Beat 6 done or skipped.

### Beat 7 — `tmuxc`, `bd`, and `/morning-check` (2 min, mandatory)

Three small tools you'll use most days. Demo all three quickly.

**1. `tmuxc`** — spin up a tmux session in any folder.

```bash
tmuxc                  # list sessions, prompts which to attach
tmuxc scratch ~/tmp    # create+attach 'scratch' with cwd ~/tmp
tmuxc kill scratch     # close it
```

> *Every time you make a project, I spin up a new tmux session for it. But you can do this yourself for any folder. So if you want a session for your strategy & notes space later: `tmuxc stratops ~/ai-platform/stratops` and it'll appear in the Claude Code app sidebar like any other. Your stratops folder already has templates (PORTFOLIO, OKRs, ROADMAP, FINANCIAL, monthly review) — open the session and ask me to walk through filling them in.*

Demo:

```bash
tmux new-session -d -s demo -c /tmp
tmux ls
tmux kill-session -t demo
```

**2. `bd`** — brain-dump capture. Drop an idea anywhere, anytime.

```bash
bd "burn rate widget should be top-right not bottom"
bd -t finance -t ui "tax categorisation for ETFs"
```

> *`bd` appends a one-line JSON entry to `~/ai-platform/stratops/brain-dump.jsonl`. Cheap, always available, never gets in your way. When you have a quiet moment, ask me to triage what's there — I can sort the entries into project ideas, todos, or noise.*

Demo:

```bash
bd "tutorial: walk the user through the brain-dump workflow"
tail -1 ~/ai-platform/stratops/brain-dump.jsonl
```

**3. `/morning-check`** — quick "where am I" survey.

> *Type `/morning-check` at the start of a session and you get a 30-second snapshot: tmux sessions, last 24h commits, open PRs, unprocessed brain-dumps, disk + RAM, tailnet. Designed for phone-from-bed mornings.*

Mark Beat 7 done.

### Beat 8 — SDD skills tour + live demo (3 min, mandatory)

> *Last beat. You have a set of skills pre-installed — type `/` anywhere to see them. The everyday ones: `/code-review` and `/code-simplifier` for code quality, `/ux-review` and `/ui-ux-consultant` for interfaces, `/backend-engineer`, `/executive`, `/product-marketing` for on-demand expertise, `/documentator` for docs, `/morning-check` for a daily status. Plus `/first-project` and `/second-project` to spin up new work.*

Then introduce the optional SDD workflow — but DON'T demo it live, it's not installed by default:

> *There's also an opt-in workflow this device is opinionated about: SDD (Spec-Driven Development). It's a team of five "voices" — a product lead, a tech lead, a QA lead, a growth voice, and a docs voice — that take an idea from "I want to build X" all the way to a reviewed spec before you write code. It's powerful but heavier than you need on day one, so it's not pre-installed.*
>
> *When you want it, one command adds it:*

```bash
biab add sdd
```

> *After that, `/sdd-coordinator` becomes your entry door — describe a feature and it walks you through turning it into a real spec. Try it whenever you're ready; no rush.*

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

> *Done. You know how to attach, how to make new sessions, how to push to GitHub, how the folder-context thing works, and that the SDD workflow is one `biab add sdd` away when you want it. The next time you have an idea for a thing to build, the move is: `tmuxc <name> ~/some/folder` → open Claude there → describe it. I'll be here.*
>
> *I'm leaving you in the `ai-platform` session. The full guide is at `~/README.md` if you want to skim it later.*

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
