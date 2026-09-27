---
name: first-project
description: Interactive first-project walkthrough for someone using a fresh Builders in a Box devbox. Helps the user pick (or invent) their first project, scaffolds the folder, copies the bundled FEAT spec, sets up Git + GitHub for it, and adds a tmux window with Claude --remote-control so the project becomes a first-class working surface in the Claude Code app.
---

# /first-project — your guided first-day walkthrough

When the user invokes this skill, you are their guide through THREE arcs, in order. Pause between each. Don't barrel through.

## Before you start — orient yourself

Read the current state and the bundled specs:

```bash
cat /var/lib/buildersinabox/state.json
ls /opt/buildersinabox/payload/examples/
ls ~/ai-platform/projects/ 2>/dev/null || true
```

If `state.project_name` is already set AND `~/ai-platform/projects/<name>/` exists, the user has already done this. Switch to `/whats-ahead` instead.

If `gh auth status` returns non-zero, stop. Tell the user to run `gh auth login` first. Don't proceed without GitHub auth.

## Arc 1 — Pick the project (5 min, conversational)

Don't just dump a menu. Have a brief chat first, then offer the choices.

Open warm:

> *Time to give your first project a name. You can either pick one of the two specs we shipped with — both are fully written, ready to build — or you can describe something else you'd rather make, and I'll help you scope it.*

Show the two bundled options with one-paragraph summaries. They live at `/opt/buildersinabox/payload/examples/`. Open and skim them yourself if you need detail.

> *Option 1 — `FEAT-002` Personal Slack coach. Empathic AI that lives in your Slack and chats with you about how your work is going. Knows what's happening on this device. ~2 evenings to ship. Folder name we'd use: `personal-coach`.*
>
> *Option 2 — `FEAT-003` Personal finance dashboard. Upload your bank CSV, scrape fund/ETF prices, AI auto-categorises every transaction, ship to a real domain you own. ~4–8 evenings. Folder name we'd use: `finance-dashboard`.*
>
> *Or — option 3 — describe something else you'd rather build. I can help write the spec, no spec required upfront.*

Wait for an answer. If they pick option 3, ask:

- "What would you call it?" → use the slug as the folder name (kebab-case, no spaces).
- "One line — what does it do?" → store this for the seed CLAUDE.md.

If they pick option 1 or 2, the folder name is fixed (`personal-coach` or `finance-dashboard`).

## Arc 2 — Scaffold the project (3 min, mostly automatic)

You're going to:
1. Create the project folder under `~/ai-platform/projects/<name>/`.
2. Drop in seed `CLAUDE.md` / `AGENTS.md` (from `/opt/buildersinabox/payload/templates/PROJECT-CLAUDE.md`). `CLAUDE.md` is Claude Code's context file; `AGENTS.md` is the open standard that both Antigravity (`agy`) and Codex read.
3. Copy the chosen bundled spec into `specs/draft/` if option 1 or 2.
4. Persist the name into state.json.
5. Patch `~/README.md` so the `{{PROJECT_NAME}}` placeholder gets replaced with the real name.
6. Add a tmux window so the project becomes a first-class session.

Concrete commands (run them yourself with Bash; don't dictate to the user):

```bash
PROJECT=<name>                                  # e.g. personal-coach
PDIR=~/ai-platform/projects/$PROJECT
mkdir -p "$PDIR/specs/draft" "$PDIR/specs/active" "$PDIR/specs/completed"

# Seed context files for this project.
TPL=/opt/buildersinabox/payload/templates/PROJECT-CLAUDE.md
for name in CLAUDE.md AGENTS.md; do
    sed "s|{{PROJECT_NAME}}|$PROJECT|g" "$TPL" > "$PDIR/$name"
done

# Copy the chosen bundled FEAT spec (skip if option 3 / custom).
if [[ "$PROJECT" == "personal-coach" ]]; then
    cp /opt/buildersinabox/payload/examples/FEAT-002-personal-slack-coach.md \
       "$PDIR/specs/draft/"
elif [[ "$PROJECT" == "finance-dashboard" ]]; then
    cp /opt/buildersinabox/payload/examples/FEAT-003-personal-finance-app.md \
       "$PDIR/specs/draft/"
fi

# Persist the project name in state.json.
sudo jq --arg n "$PROJECT" '.project_name = $n' \
    /var/lib/buildersinabox/state.json > /tmp/s.json && \
sudo mv /tmp/s.json /var/lib/buildersinabox/state.json && \
sudo chmod 644 /var/lib/buildersinabox/state.json

# Replace {{PROJECT_NAME}} in ~/README.md (still has the placeholder).
sed -i "s|{{PROJECT_NAME}}|$PROJECT|g" ~/README.md

# Create a NEW tmux session for the project (not a window inside another
# session). Each project is its own remote session in the Claude Code app
# sidebar — this is how FEAT-005 wants the model to work.
if tmux has-session -t "$PROJECT" 2>/dev/null; then
    echo "tmux session $PROJECT already exists, leaving it"
else
    tmux new-session -d -s "$PROJECT" -c "$PDIR"
    tmux send-keys -t "$PROJECT" "claude --remote-control $PROJECT" Enter
fi
```

The `claude --remote-control` line above is for a Claude Code box. On an
`agy` or codex box there is no Remote Control — start the box's own CLI
instead (no companion app; the session is reached over SSH + tmux):

```bash
# agy box:    tmux send-keys -t "$PROJECT" "AGY_CLI_DISABLE_AUTO_UPDATE=1 agy" Enter
# codex box:  tmux send-keys -t "$PROJECT" "codex" Enter
```

Pick the line matching this box's CLI
(`jq -r '.ai_cli // "claude"' /var/lib/buildersinabox/state.json`).

Confirm with the user: "Done. There's a new tmux session called `<name>` in the Claude Code app sidebar — if it doesn't appear right away, swipe down to refresh the session list (the app polls every few seconds, swipe forces it)." Wait for them to spot it before continuing.

## Arc 3 — Git init + (if GitHub authed) push (3 min)

Always do the git init + first commit locally. Only push to GitHub if `gh auth status` succeeds.

```bash
cd ~/ai-platform/projects/$PROJECT

# git identity if not set
git config --global user.name >/dev/null 2>&1 || \
    git config --global user.name "$(gh api user --jq .name 2>/dev/null || echo 'BIAB User')"
git config --global user.email >/dev/null 2>&1 || \
    git config --global user.email "$(gh api user --jq .email 2>/dev/null || echo "${USER}@local")"

git init -b main
git add -A
git commit -m "Initial commit from Builders in a Box"
```

Then check GitHub:

```bash
if gh auth status >/dev/null 2>&1; then
    # GitHub is authed — push for real.
    GH_AUTHED=1
else
    GH_AUTHED=0
fi
```

**If `GH_AUTHED=1`:**

Ask the user: **public or private?** Default to private — they can flip it later. Then:

```bash
gh repo create "$PROJECT" --private --source=. --push   # or --public
gh repo view --web   # prints URL; user opens on their phone
```

> *Your project is live on GitHub. Open the URL on your phone to see it.*

**If `GH_AUTHED=0`:** (the user skipped GitHub during `/tutorial` Beat 2)

Don't try to push. Drop a TODO at the bottom of the project's CLAUDE.md:

```bash
cat >> $PDIR/CLAUDE.md <<'TODO_EOF'

## TODO — Connect this project to GitHub

GitHub was skipped during /tutorial Beat 2 — this project lives only on
the device for now. To push it later:

    /tutorial            # re-runs from the next pending beat (GitHub)
    # ...or do it manually:
    gh auth login --hostname github.com --git-protocol https --web
    cd ~/ai-platform/projects/<this-folder>
    gh repo create $(basename $PWD) --private --source=. --push
TODO_EOF
```

Tell the user:

> *Local commit done. GitHub push skipped because you haven't connected your account yet — there's a TODO note in this project's CLAUDE.md with the exact command for later. Or run `/tutorial` again and it'll pick up at the GitHub beat.*

If any step fails (including the GitHub-authed path), surface the actual error and offer to retry. Don't move on with broken state.

## Arc 4 — Hand off

**If invoked from `/tutorial`** (`BIB_TUTORIAL_PARENT=1` env var present):

End cleanly with a one-line confirmation and return — the tutorial picks up at the next beat. Do NOT do the long hand-off prose; the tutorial owns that voice.

> *Project ready: folder, commit, GitHub (if authed), tmux session. Returning to the tutorial.*

**If invoked standalone** (no parent env var):

Long hand-off as before. Tailor by spec choice:

If the project is one of the bundled FEATs:

> *The spec is in `~/ai-platform/projects/<name>/specs/draft/`. When you're ready to actually build, switch to the `<name>` tmux session and say "let's start the spec" — I'll walk you through it section by section.*
>
> *When you finish this one, there's a second spec already waiting. Invoke `/second-project` then.*

If the project is custom (option 3):

> *The spec is empty — that's expected. When you're ready to start, switch to the `<name>` session and either say "let's write the spec" (I'll use `/sdd-coordinator` to walk you through it), or just start describing what you want and I'll improvise from there.*

End the skill here. Don't push further.

## Tone

- Patient. The user might be new to terminals, Git, or both.
- Concrete. Show actual commands, not abstractions.
- Honest. If something fails, say so and debug together.
- Brief. Each explanation is one short paragraph, not three.
- No hype.

## When NOT to use this skill

- `state.project_name` is already set and the folder exists → use `/whats-ahead` instead.
- The user is on a device that isn't a fresh Builders in a Box install. This skill assumes the state file, payload, and tmux session are present.
