---
id: FEAT-005
title: claude-tutorial-onboarding
project: buildersinabox
status: completed
priority: high
complexity: high
created: 2026-05-29
validated_by: null
---

# FEAT-005: Onboarding tutorial inside Claude Code (post-wizard)

## §0 — Strategy

> Owner: Product Lead

- **Why now:** the test on 2026-05-28 / 29 made it obvious that the moment after the console wizard ends — when Paco opens the Claude Code app for the first time — is wide open and unguided. He attaches to a window where Claude is running, and… nothing tells him what to do. The previous version dumped him at a `/welcome` skill that summarised everything in 4 turns and waved him off. That works as a brochure, not as a doing experience.
- **Hypothesis:** the right place to teach Paco *how to use this device* is inside Claude Code itself, not on a console he'll never see again. If the first 10 minutes inside the app are a guided `/tutorial` skill that walks him through (a) connecting GitHub from inside Claude, (b) creating the two bundled projects each as its own tmux session, (c) showing what changes when you open Claude in a different folder, and (d) introducing the SDD skills as a team — he ends those 10 minutes already productive, not just "set up".
- **Why not the wizard:** the console wizard is fine for the unmovable plumbing (password, network, SSH, Claude login). Anything that benefits from copy-paste, a real text area, or a conversation belongs inside Claude. GitHub OAuth especially: the OAuth URL is short enough for any terminal, but doing it inside Claude lets Claude *react* to success/failure and adapt the next step.
- **Cost of not doing it:** Paco lands in an empty Claude TUI on his phone, gets no concrete next action, and either (a) explores randomly and bounces, or (b) goes back to the README on the desktop, which defeats the "mobile-first" thesis of the box.
- **Strategic shift this enables:** the wizard becomes thinner (and rebuilds faster), and the tutorial becomes a living artefact we can iterate without re-flashing the USB — `/tutorial` is just a markdown file in `~/.agents/skills/tutorial/`, editable by Paco himself once he's familiar.

## §1 — Product requirements

> Owner: Product Lead

### What Paco experiences

1. **Wizard ends earlier.** After Claude login, scaffold, and tmux setup, the wizard prints "All set, Paco — open the Claude Code app". No project picker, no GitHub login in the wizard.
2. **Opens Claude Code app** (mobile or desktop). Sees one session in the sidebar: **`root`**, cwd `~/ai-platform/`. Attaches.
3. **Claude greets with `/tutorial` already running** (sent as the initial prompt at launch). Conversational, 5–8 short turns.
4. The tutorial covers, in order, with pauses between sections:
   - **Beat 1 — orient.** "You're inside Claude Code, talking to me over Remote Control. This session is called `root` and lives in `~/ai-platform/`. Everything I do here happens on your mini PC."
   - **Beat 2 — connect GitHub.** "Let's put your code on GitHub. I'll run `gh auth login --web` here in the terminal; you'll see a short URL and a one-time code. Open the URL on your phone browser, paste the code, approve, come back." When `gh auth status` is green, move on. (No fallbacks for "I don't have a GitHub account" — the tutorial pauses and points him at signing up at github.com first, then resumes.)
   - **Beat 3 — bundled specs.** "Your device shipped with two pre-written specs. We can build either, both, or you can describe your own thing." Show the two FEATs (FEAT-002 coach, FEAT-003 finance) with one-paragraph hooks. Ask which to set up first.
   - **Beat 4 — create the first project.** Invoke the existing `/first-project` skill internally, passing the chosen FEAT. After `/first-project` returns, the user sees a NEW tmux session appear in the Claude Code app sidebar — the project, in its own session, with Claude already running there.
   - **Beat 5 — context teaching moment.** "Notice that new session opened in `~/ai-platform/projects/<name>/`? Claude reads the CLAUDE.md from whichever folder it starts in, so the Claude inside that session knows everything about your project, while the Claude here in `root` only sees the platform-level overview. That's how you 'load context' on this device: by which folder you open Claude in."
   - **Beat 6 — second project.** Offer to set up the second bundled FEAT as a second tmux session right now (parallel to the first), or save it for later.
   - **Beat 7 — `tmuxc` for any folder.** "If you ever want to spin up a session in some random folder — a scratch dir, your stratops/, anywhere — use `tmuxc <name> <folder>` from any terminal. It creates the session and Claude can attach to it through the app."
   - **Beat 8 — SDD skills team.** Quick intro to the SDD voices: sdd-coordinator (product), sdd-spec-writer (tech), sdd-qa (QA), sdd-growth (growth), sdd-docs (docs). Plus the consultancy on demand: backend-engineer, ui-ux-consultant, executive, product-marketing. Plus the code-level tools: code-review, code-simplifier, ux-review. Wrap with "type `/` anytime to see the menu — these aren't features to memorize, they're voices to call when you need them."
5. **End-state after the tutorial:**
   - GitHub is authenticated.
   - At least one project is scaffolded, committed, and pushed to GitHub.
   - At least one extra tmux session exists for the project.
   - Paco knows how to spin up more sessions and which skills to reach for.
   - Wall-clock time from "attached the app" to "tutorial done" is **≤ 12 minutes** on a normal pace.

### Boundaries

- **Always:**
  - Tutorial runs in a real Claude conversation — never block waiting for input the way a wizard does, but always wait for the user before moving to the next beat.
  - All commands the tutorial runs (`gh`, `git`, `tmux`, scaffolding) execute via Claude's Bash tool, not via prose instructions for the user to copy.
  - Idempotent: if any beat has already happened (gh already authed, project already exists, second session already there), skip with a one-line acknowledgement and move on.
  - English copy, matches existing wizard tone (warm, brief, no hype).
- **Never:**
  - Re-implement what `/first-project` already does — the tutorial calls it as a subroutine, doesn't duplicate the logic.
  - Hide errors. If `gh auth login` fails or the GitHub repo creation fails, surface the actual error to Paco and offer to retry.
  - Force the second project. Beat 6 is optional and skippable.
  - Pretend the SDD team are humans named Elena/Laura/Pablo/Andrea. We use the skill slugs (`sdd-coordinator` etc.) — those personas live in the maintainer's other project, not in BIAB.

### Product acceptance criteria

- [ ] On a freshly-installed device, attaching to the `root` session shows Claude already greeting with the tutorial's first beat (no `/tutorial` typed by the user).
- [ ] After Beat 2, `gh auth status` returns green.
- [ ] After Beat 4, `~/ai-platform/projects/<chosen>/` exists with a copy of the chosen FEAT spec, an initial git commit, a GitHub repo, and a new tmux session named `<chosen>` running `claude --remote-control <chosen>`.
- [ ] After Beat 5, Paco can articulate (when asked) "Claude in this window knows the project; Claude in root knows the platform". Test it: tutorial asks him at the end.
- [ ] If Paco quits halfway and re-attaches later, the tutorial picks up at the next un-done beat — never repeats one that's already complete.
- [ ] The Claude Code app sidebar shows ≥ 2 tmux sessions after the tutorial: `root` plus whatever projects were created.

## §2 — Technical spec

> Owner: Tech Lead

### What changes in the wizard (Phase B)

- **Remove `20-gh-login` from the wizard chain.** Move the gh package install + `gh auth login` invocation entirely into `/tutorial` Beat 2. Keep the `payload/install/30-gh.sh` script (the binary needs to be on PATH for the tutorial to invoke `gh`).
- **Modify `50-tmux.sh` and `payload/tmux/launch-main.sh`:**
  - Change the default session name from `main` to `root` (matches the user's mental model).
  - The `root` session opens with one window only, cwd `~/ai-platform/`, running `claude --remote-control root '/tutorial'` (note: `/tutorial` is the initial prompt that auto-fires Beat 1).
  - **Do not create a `stratops` window.** The tutorial mentions stratops as something the user can create later via `tmuxc stratops ~/ai-platform/stratops`.
  - Remove all conditional logic about `project_name` being set — the project comes from `/first-project`, which creates its own tmux session via `tmux new-session`.
- **Update `payload/wizard/run.sh` final message** to drop the "GitHub will be configured" line, drop "platform/project/stratops" 3-window listing, and instead say "you'll see one session called `root` — attach to it and the tutorial begins."
- **Update `36-phone-bridge.sh`** to drop the "Once SSH'd in: GitHub login, Claude login, tmux..." preview (less stuff now, just Claude login + tmux). Update the "what's left" message.

### What changes in `/first-project`

- It's already written to scaffold + GitHub + create a new tmux window. **Change the window step to a session step**:
  - Replace `tmux new-window -t main: -n <name> -c ...` with `tmux new-session -d -s <name> -c ...`.
  - Then `tmux send-keys -t <name>: "claude --remote-control <name>" Enter`.
- Idempotency: if a session named `<name>` already exists, skip the create and just confirm.
- Add a hook at the end: when `/first-project` is invoked *from inside `/tutorial`*, return cleanly so the tutorial can continue Beat 5. When invoked standalone, end with the existing hand-off prose. (Implementation: check for `BIB_TUTORIAL_PARENT=1` env var the tutorial sets before delegating.)

### New skill: `/tutorial`

Located at `payload/skills/tutorial/SKILL.md`. Same shape as the existing `/welcome` skill, but longer and more structured. The skill:
- Reads `/var/lib/buildersinabox/state.json` to know what's already done.
- Maintains its own "current beat" in a small state file at `~/.config/biab-tutorial/state.json` (jq-managed). Beat numbers 1–8 + `done`.
- At the start of every invocation, jumps to the first non-done beat. Says one line to acknowledge skipping done beats.
- Uses Claude's Bash tool for every command: `gh auth login`, `gh auth status`, scaffold commands (via `/first-project`), `tmux new-session`, `tmux ls`.
- Pauses between beats by ending the turn with a single concrete question (no walls of bullet points).

### Existing skills to retire or rewrite

- **`/welcome` skill becomes redundant.** Replace its file with a stub that just says "type `/tutorial` to start" and forwards. Don't delete entirely — keep it for muscle memory if Paco types the old keyword.
- **`/first-project` stays** (called as subroutine by `/tutorial`, also usable standalone).
- **`/second-project` stays** (now becomes optional — Beat 6 of tutorial can offer to do it, or Paco can invoke later).
- **`/whats-ahead` stays** — it's the "I already did the tutorial, show me a refresher" exit.
- **All SDD skills (`sdd-*`)** unchanged.

### Bundled-feats location

- The two FEATs (FEAT-002, FEAT-003) keep living at `/opt/buildersinabox/payload/bundled-feats/` (read-only). `/first-project` copies the chosen one into the project's `specs/draft/`.

### tmux model after this FEAT

The Claude Code app sidebar after a full first-day run:

```
root              <- always there, opened by the wizard's 50-tmux
finance-dashboard <- created by /first-project after Beat 4
personal-coach    <- created by /first-project after Beat 6 (optional)
```

Each session has a single window with Claude running in `--remote-control` mode, cwd set to the relevant folder. No multi-window inside any session — that's the model the tutorial teaches.

### `tmuxc` is the public API for new sessions

Already shipped in `payload/bashrc.d/tmuxc.sh`. The tutorial (Beat 7) demos it. `/first-project` and `/tutorial` internally use `tmux new-session` directly (lower level) — `tmuxc` is for Paco from any shell.

### Implementation plan (waves)

**Wave 1 — Wizard slim-down (this commit).**
1. `payload/wizard/run.sh`: remove `20-gh-login.sh` line from chain. Update intro + final message.
2. `payload/tmux/launch-main.sh`: rename session `main` → `root`, single window in `~/ai-platform/`, initial prompt `/tutorial`. Strip the project-window conditional (it lives in `/first-project` now).
3. `payload/wizard/36-phone-bridge.sh`: drop GitHub from the "what's left" preview.
4. `payload/skills/welcome/SKILL.md`: replace body with "type `/tutorial`" stub.
5. Manual verify: dryrun in mhserver still passes.

**Wave 2 — `/tutorial` skill (this commit).**
1. Create `payload/skills/tutorial/SKILL.md` with all 8 beats.
2. Create the state tracker convention (file path, jq commands inline in the skill instructions).
3. Document idempotency rules.

**Wave 3 — `/first-project` adjustments (this commit).**
1. Switch `tmux new-window` → `tmux new-session`.
2. Add the `BIB_TUTORIAL_PARENT` exit branch.
3. Tighten idempotency on the session check.

**Wave 4 — Polish (this commit).**
1. Update `payload/tutorial/desktop-readme.md` to reflect the new flow (1 root session, projects spawn new sessions, `/tutorial` is the entry).
2. Bump bundled-feats README references in `/welcome` stub.

**Wave 5 — Done.** Rebuild ISO, reflash, retest. No staged rollout — gift edition, single user.

### Risks

- **Tutorial gets stuck if Claude's Bash tool times out.** Mitigation: every long-running command (`apt install`, `gh auth login`) wrapped with a timeout note in the skill; if it returns non-zero, the skill surfaces the error and offers retry.
- **Paco quits mid-tutorial and the state tracker drifts from reality.** Mitigation: the skill re-detects reality at every entry (e.g. checks `gh auth status` before declaring Beat 2 done, regardless of state file).
- **App doesn't refresh sidebar when a new tmux session is created mid-conversation.** Mitigation: tutorial explicitly tells the user to swipe-to-refresh / reopen the session list after Beat 4 and 6. If we find Claude Code app does refresh automatically, drop the instruction.
- **`claude --remote-control root '/tutorial'` quoting.** Bash escaping for the initial prompt has to survive `tmux send-keys`. Test with both single and double quotes.

### Quality gates

- [ ] `shellcheck --severity=warning` clean on all touched .sh files.
- [ ] `tools/check-no-personal-refs.sh` still clean.
- [ ] `bash payload/test/dryrun.sh` (if it survives the chain change) — run after Wave 1.
- [ ] Manual on real mini PC: attach root, see Beat 1, walk through to Beat 8 without errors. Time the run.

## §3 — Growth notes

Skipped — personal gift, no public surface, no acquisition funnel.

## §4 — QA

> Owner: QA Lead

### Test plan

**T1 — Wizard ends correctly with new chain.**
- Fresh install. Boot, complete wizard. Verify `/var/lib/buildersinabox/state.json` shows: password_set, ssh_finalize_done, tailscale_done, ai_cli_done, scaffold_done, tmux_done. **No** `gh_done`.
- `tmux ls` shows exactly one session: `root`. No `main`, no `platform`, no `stratops`.

**T2 — Initial Claude attach fires tutorial.**
- Open the Claude Code app, attach to `root`. Within ~3 seconds, see Claude's first turn (Beat 1 text). Confirm `/tutorial` did not need to be typed.

**T3 — Beat 2 (GitHub) happy path.**
- Follow Claude's instructions. Complete `gh auth login --web` from phone browser.
- Verify `gh auth status` is green inside the same Claude conversation.
- Tutorial moves to Beat 3.

**T4 — Beat 4 + tutorial-to-`/first-project` handoff.**
- Pick FEAT-003 (finance). Claude scaffolds `~/ai-platform/projects/finance-dashboard/`, copies the spec, init+commit+push.
- A new tmux session `finance-dashboard` appears.
- The Claude Code app sidebar shows it (may need refresh).
- Tutorial returns to its own conversation (in `root`) and moves to Beat 5.

**T5 — Beat 5 context teaching.**
- Tutorial asks "what does Claude see in the new window vs. here?". Verify the question is concrete enough that Paco can answer (not a vague "what did you learn?").

**T6 — Beat 6 second project (optional).**
- Paco picks "yes, do FEAT-002 too". A second session `personal-coach` is created.
- Paco picks "no, skip". Tutorial moves to Beat 7 without error.

**T7 — Beat 7 demo of `tmuxc`.**
- Tutorial demos `tmuxc scratch ~/tmp` (or similar safe path). Verifies the new session shows up in `tmux ls`.

**T8 — Beat 8 SDD intro.**
- Tutorial lists the SDD skills. Asks Paco to type `/` and confirm he can see the menu in the Claude Code app. Marks tutorial done.

**T9 — Idempotency.**
- Restart Claude from any session. Re-invoke `/tutorial`. It should one-line acknowledge what's already done and either end or pick up at the next pending beat.

**T10 — Interrupted tutorial.**
- Halfway through Beat 4 (after `gh repo create` but before the new session check), kill the conversation. Reopen, invoke `/tutorial`. It should detect the partial state and recover (e.g. session exists but state file says Beat 4 not done → re-confirm with Paco that the project looks right, then mark done).

### Regression to watch

- The bridge step (Phase A) must still pause cleanly on console and resume on SSH. Phase A code is untouched but the run.sh wizard chain changes, so dryrun the whole flow once.
- `/welcome` invocation by old-Paco-muscle-memory must still work (it now forwards to `/tutorial`).

## §5 — Docs

> Owner: Docs

- Update `payload/tutorial/desktop-readme.md` to reflect:
  - 1 default session (`root`) instead of 3
  - `/tutorial` is the entry point, not `/welcome`
  - Projects each get their own tmux session
- Add a small "Skills overview" appendix in the same README mirroring Beat 8 of the tutorial, for users who skipped the tutorial.
- Update top-level `payload/CLAUDE.md` (if it exists in the shipped tree — verify) to mention `/tutorial` as the canonical entry.
- No public docs (still no public surface).
- Changelog entry inside this repo: "FEAT-005 — onboarding moved into Claude Code, wizard slimmed to plumbing only."

---

## Resolved decisions (2026-05-29 iteration with maintainer)

1. **`/tutorial` invoked from a non-default session: work but warn.** The skill runs anywhere, but the first turn says "you're not in `ai-platform`, which is where I expected. I can still do the work, but the explanations about context will refer to the cwd Claude is in right now, not the platform root."
2. **Beat 8 (SDD skills): demo one inline.** List the SDD voices briefly, then *actually invoke* `/sdd-coordinator` mid-tutorial with a real prompt ("imagine you want to build X — let me show you what this voice does"). +3–5 min, lasting impression. Other skills stay as one-line callouts.
3. **Skipping is allowed.** If Paco says "skip" at any beat, the skill records what's missing, summarises the consequences in one sentence ("you're skipping GitHub — your code stays local and you'll lose it if the device dies"), and continues. At the end of the tutorial it offers to come back to the skipped beats. State file tracks `skipped` separately from `done`.
4. **Default session name: `ai-platform`.** Matches the folder name (`~/ai-platform/`), no collision with the unix `root` user, mentally one-to-one with what's in the filesystem.

These decisions are now baked into the spec above (replace any earlier mention of `root` with `ai-platform`, etc. during implementation).
