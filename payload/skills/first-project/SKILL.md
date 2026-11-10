---
name: first-project
description: Guided first project for someone on a fresh Builders in a Box devbox. Walks one idea from a template (or the user's own idea) to a written spec, an implementation on a branch, and a pull request on GitHub, one short step at a time. Resumes where it stopped, never overwrites the user's files, and never merges for them.
---

# /first-project — from idea to a pull request

You guide the user through ONE walk: pick a template or describe an idea, write a spec together, build it on a branch, open a pull request. Five steps, one short message and one decision at a time (the user is probably on a phone). Never barrel through.

The deterministic work (the catalogue, scaffolding without overwriting, what step the disk says the project is at, remembering progress) is done by one script. Call it, do not redo its job by hand:

```bash
BP=/opt/buildersinabox/payload/scripts/biab-project
```

## Before you start: where is the user?

Progress comes first, before anything else. Resuming is the normal case, not an error.

```bash
"$BP" progress get; echo "exit=$?"
jq -r '.project_name // empty' /var/lib/buildersinabox/state.json
```

- **exit 0** prints `<template><TAB><project>`: the walk was started. Run `"$BP" status "$PROJECT"` and continue at the step in the table below. Do not ask again for answers already given: they are in the spec the project already holds. The disk wins over your memory of the conversation.
- **exit 1** (no progress yet): a fresh start, go to step 1. Only if `state.project_name` is set and that folder exists under `~/ai-platform/projects/`, the user did this walk some other way: point them to `/whats-ahead` instead.
- **exit 3** (the progress file is damaged): say so, name the file, and ask whether to start fresh. It holds no answers, only a template and a project name.

| `status` says | Continue at |
|---|---|
| `scaffold`, `init`, `register` | step 2 (every part of it is safe to repeat) |
| `spec` | step 3, asking the brief questions |
| `confirm` | step 3, reviewing the spec in `specs/draft/` with the user |
| `build` | step 4. If the `feat/*` branch has uncommitted edits, read them and carry on from there |
| `publish` | step 5 only: the work exists, it still has to reach GitHub |
| `review` | check whether the pull request exists (`gh pr list --head <branch>`), create it if not, then tell the user it is waiting for their review |
| `complete` | say "Walk complete", point to `/whats-ahead` and `/second-project`, and stop. Do not start over and do not write progress again |

If the user says they want a different template or a different idea instead of resuming, go back to step 1: `progress set` replaces the progress, and the folder already created is left exactly as it is.

Resuming never throws work away. Run no command that discards uncommitted changes or rewrites history; if there are edits you did not expect, look at them and ask.

## Step 1 — Pick (one decision)

Show what the catalogue offers. Do not use a list of your own:

```bash
"$BP" list
```

Each line is `name<TAB>time<TAB>description`. Show them as a numbered short list (name, time, one line), plus the last option: **describe your own idea**. Ask which one. Nothing else in this message.

- A template: the project folder is the template name.
- Their own idea: ask "What would you call it?" (lowercase letters, digits and dashes) and then "One line: what does it do?". The template is then `idea`.

If a later command rejects the name (exit 3 or 6), show its message as it is and ask once for another name. Never rename it yourself.

## Step 2 — Scaffold (automatic, about 3 minutes)

```bash
PROJECT=<name>                     # the folder name
TEMPLATE=<template or idea>
PDIR=~/ai-platform/projects/$PROJECT

"$BP" progress set "$TEMPLATE" "$PROJECT"
"$BP" scaffold "$TEMPLATE" "$PROJECT"
```

`scaffold` creates the project from the template and never overwrites a file the user has. If it stops, relay its one-line message as it is and ask what they want: exit 2 names the files that would be overwritten (nothing was written), exit 6 means the name is already a project of theirs. Do not retry with another name on your own.

When it succeeds, finish the setup. Every line is safe to run again:

```bash
cd "$PDIR"

# git identity if not set
git config --global user.name >/dev/null 2>&1 || \
    git config --global user.name "$(gh api user --jq .name 2>/dev/null || echo 'BIAB User')"
git config --global user.email >/dev/null 2>&1 || \
    git config --global user.email "$(gh api user --jq .email 2>/dev/null || echo "${USER}@local")"

[ -d .git ] || git init -b main
if ! git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    git add -A
    git commit -m "Initial commit from Builders in a Box"
fi

# Replace {{PROJECT_NAME}} in ~/README.md if it still has the placeholder.
sed -i "s|{{PROJECT_NAME}}|$PROJECT|g" ~/README.md

# Make the project its own workspace. The helper is idempotent and is the ONLY
# thing that knows how this box is reached (the Paseo app):
# never hand-write interface commands here.
/opt/buildersinabox/paseo/bin/biab-workspace "$PDIR" "$PROJECT"

# Last, so a cut before this line is seen as "register" and the lines above run again.
# Persist the project name once, for the first project only.
# The temp file is made by root inside the root-owned state dir, never in /tmp.
if [ -z "$(jq -r '.project_name // empty' /var/lib/buildersinabox/state.json)" ]; then
    state_tmp="$(sudo mktemp /var/lib/buildersinabox/state.XXXXXX)" && \
    sudo jq --arg n "$PROJECT" '.project_name = $n' \
        /var/lib/buildersinabox/state.json | sudo tee "$state_tmp" >/dev/null && \
    sudo mv "$state_tmp" /var/lib/buildersinabox/state.json && \
    sudo chmod 644 /var/lib/buildersinabox/state.json
fi
```

The helper prints one or two lines saying where the project now lives. Relay them in your own words, then:

> *Done. There's a new workspace called `BIAB · <name>` in the Paseo app. If it doesn't appear right away, pull down to refresh the list.*

**If invoked from `/tutorial`** (`BIB_TUTORIAL_PARENT=1` is set): stop here with one line and return, the tutorial owns the next beats. The walk resumes later from step 3 by itself.

> *Project ready: folder, first commit, workspace. Say `/first-project` any time to write its first spec. Returning to the tutorial.*

## Step 3 — Write the spec (no code yet)

Write nothing but the spec until the user says the spec is right.

- **Their own idea:** read `/opt/buildersinabox/payload/templates/projects/IDEA-BRIEF.md`, ask its questions one at a time (every question has a default: "ok" is a valid answer), then run `/sdd-coordinator` in starter mode to write the spec in `specs/draft/` from the answers.
- **A template:** the spec is already in `specs/draft/`. Give a short summary, ask what to change, and edit it with them. Keep it short enough to read on a phone.

When they say it is right, the coordinator records `validated_by` and moves it to `specs/active/`. Commit that on `main` (still local, before the first push):

```bash
cd "$PDIR" && git add -A && git commit -m "Add the first spec"
```

## Step 4 — Build it on a branch

Cut the branch from `main`, not from whatever is checked out:

```bash
cd "$PDIR" && git switch -c feat/<short-slug> main
```

Implement the active spec yourself, in waves, following the implementation phase of `/sdd-coordinator`: stay inside the spec's Boundaries, write the tests the spec asks for, run them, commit as you go with clear messages. Run the quality gates before moving on. If the tests cannot pass, do not open a pull request with red tests: say what is missing and what you tried. `status` stays at `build` and the user can resume.

Ask one question when the build is done: **"How do you run this project to see that it works?"** If they answer, put that command in `.biab/dev-check.sh` (exit 0 when it works, exit 1 when it does not, a one-line summary as the last line) and commit it. If they do not know yet, leave the placeholder: the night shift then stops at the pull request for this project.

## Step 5 — Publish and open the pull request

All work is committed on the branch. Check that GitHub is within reach before touching anything:

```bash
command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; echo "gh ready: $?"
```

If it is not ready, or a command below fails, **do not fail the walk**: the spec, the code and the branch stay on the device. Say plainly which step is waiting and how to unblock it, then stop. Never retry on your own and never push in a way that overwrites remote history.

- `gh` is missing or not logged in: *"The code is done and safe here. Run `gh auth login --web`, then say `/first-project` and I'll pick up at the publish step."*
- No network, or `gh` fails with a network error: *"The code is done and safe here. Reconnect and say `/first-project`."*
- The repository name is taken on their account: the project folder keeps its name. Ask once for another **repository** name, and do not run the create command again until they answer.
- A push is rejected: show git's message as it is and wait for the user.

When GitHub is ready, publish. The first push is the one place `main` is pushed: it creates the user's repository, and without it there is no base to open a pull request against. The repository is always private; the user can change that on GitHub afterwards.

```bash
cd "$PDIR"
BRANCH=$(git branch --show-current)          # feat/<short-slug>
REPO=$PROJECT                                # or the new name the user chose
if ! git remote get-url origin >/dev/null 2>&1; then
    git switch main
    gh repo create "$REPO" --private --source=. --push
    git switch "$BRANCH"
fi
git show-ref --verify -q refs/remotes/origin/main || git push -u origin main
git push -u origin "$BRANCH"
gh pr create --base main --head "$BRANCH" --title "<title from the spec>" --body "<what it does, how it was tested>"
```

If creating the repository worked and a push failed, `origin` exists: on resume, skip the create and only push.

Then tell the user, short and warm: the pull request URL, that it is waiting for **their** review and the merge is theirs, and that `/code-review <number>` reviews it for them (you cannot run that command yourself, they type it). After they merge it, `/first-project` says the walk is complete.

If invoked standalone, finish with:

> *Your first project is on GitHub. Review the pull request, merge it when you like it, then say `/first-project` once more. For what to do next there is `/whats-ahead`.*

## Tone

- Patient. The user might be new to terminals, Git, or both.
- Concrete. Show actual commands only when they need to run something; run yours yourself.
- Honest. If something fails, say so and debug together.
- Brief. One short paragraph per message, one decision at a time.
- No hype.

## When NOT to use this skill

- The user already has a project and no walk in progress (`progress get` says exit 1 and `state.project_name` points at an existing folder): use `/whats-ahead`.
- The device is not a fresh Builders in a Box install: this skill assumes the state file and the payload are present.
