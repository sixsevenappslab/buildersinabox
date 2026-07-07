---
id: FEAT-011
title: public-repo-publish
project: buildersinabox
status: completed
phase: requisitos
priority: high
complexity: medium
created: 2026-06-13
updated: 2026-06-13
validated_by: null
---

# FEAT-011: Public repo migration + publish.sh

## §0 — Strategy

> Owner: Product Lead

- **Why now:** everything else (FEAT-007 clone source, FEAT-009 README/CI, FEAT-010 install serving) assumes a public repo at `github.com/sixsevenapps/buildersinabox-installer` exists with clean history. It doesn't yet. This FEAT creates it and establishes the repeatable mechanism to push the shippable subset from the private dev repo to the public one — so future releases are one command, not a manual copy.
- **Hypothesis:** per Jesús's choice (2026-06-13), the public repo starts from a **fresh history** containing only the shippable subset (no `specs/`, no `flavors/gift/maintainer/`, no `BIZ-PLAN`, no `TODO-NEXT`). The dev repo (`jesusmartincalvo/buildersinabox`) stays the private workbench with full history including the Paco-era commits. A `tools/publish.sh` script does `git archive HEAD` (which honours export-ignore) into a clean tree and pushes it to the public repo as a new release commit. Clean public history, private dev history preserved.
- **Why this specific cut:** a fresh-history public repo eliminates any risk of a curious visitor running `git log`/`git show` and finding "paco"/"jesusmartincalvo" in old commits or messages. `git archive` already produces the exact clean tree (verified in FEAT-006: 97 files, 0 personal refs). The only new work is the push mechanism and the one-time repo creation.
- **Cost of not doing it:** no public repo = nothing to launch. Or, worse, a rushed manual publish that accidentally includes `specs/` or carries dirty history.
- **Strategic shift this enables:** establishes the dev-repo → public-repo publishing pipeline that all future releases (and eventually the sibling module repos: conerator, observio, pathtrip) reuse. It's the release valve for the whole umbrella.

## §1 — Product requirements

> Owner: Product Lead

### Problem

There is no public repository. The dev repo carries history and files that must never be public (personal references in old commits, `specs/`, gift maintainer materials). We need a clean public repo and a repeatable, safe way to publish to it.

### Intent (why)

Publishing is the actual launch act. It must be (a) clean — zero personal references in tree or history, (b) repeatable — releases are routine, not artisanal, and (c) safe — impossible to accidentally leak `specs/` or gift materials. Getting this right once gives a reusable pipeline for the umbrella's future module repos.

### Proposed solution

1. **Create `github.com/sixsevenapps/buildersinabox-installer`** (private initially, flipped public at launch).
2. **`tools/publish.sh`** in the dev repo: produces the shippable tree via `git archive HEAD` (honours `.gitattributes` export-ignore), runs `check-no-personal-refs.sh` against the extracted tree as a hard gate, then commits + pushes it to the public repo. Supports `--tag vX.Y.Z` to cut a release.
3. **Fresh public history**: the first publish is the public repo's initial commit. Each subsequent publish is a new commit (squashed snapshot of the current shippable tree) — the public repo is a *published-artifact* repo, not a mirror of dev history. Optionally tag releases.
4. **A guard in publish.sh** that aborts if the extracted tree contains `specs/`, `flavors/gift/maintainer/`, `BIZ-PLAN`, `TODO-NEXT`, or any `check-no-personal-refs.sh` hit — belt-and-suspenders over export-ignore.

### User stories

- As the maintainer, I want `tools/publish.sh --tag v0.1.0` to push a clean snapshot to the public repo, so releasing is one command I can't easily get wrong.
- As the maintainer, I want publish.sh to refuse if anything personal or internal sneaks into the tree, so I never leak by accident.
- As a public visitor, I want `git log` on the public repo to show only clean, English, project-relevant history, so there's no trace of the private development context.
- As a future maintainer publishing the Conerator module, I want the same publish pattern to reuse, so the umbrella's repos stay consistent.

### Functional requirements (EARS)

- [ ] **Event-driven:** When `tools/publish.sh` runs, it shall extract the shippable tree via `git archive HEAD` and run `check-no-personal-refs.sh` against the extracted tree before any push.
- [ ] **Unwanted:** If the extracted tree contains `specs/`, `flavors/gift/maintainer/`, `BIZ-PLAN-LIFESTYLE.md`, `TODO-NEXT-ISO.md`, or any personal-ref hit, then publish.sh shall abort with the offending path named and push nothing.
- [ ] **Event-driven:** When `--tag vX.Y.Z` is given, publish.sh shall create that tag on the public repo's new commit.
- [ ] **Ubiquitous:** The public repo shall contain only the shippable subset — no dev history, no internal docs.
- [ ] **State-driven:** While the public remote is not configured, publish.sh shall print the exact `git remote add` command and exit without pushing.
- [ ] **Ubiquitous:** publish.sh shall be idempotent-safe: re-running with no changes produces no spurious commit (or a clearly-empty one it refuses).

### Non-functional requirements

- [ ] publish.sh never force-pushes to the public repo's default branch without an explicit `--force` flag and a confirmation prompt.
- [ ] The public repo's default branch is `main`.
- [ ] No credentials in the script; relies on the maintainer's existing `gh`/git auth.

### Growth Notes

- **Channel:** the public repo URL is the canonical link for every post, the README, and the landing's GitHub button. The repo description + topics (from FEAT-009 MAINTAINING) get set here.

## §2 — Technical spec

> Owner: Tech Lead (`sdd-spec-writer`)

### Prior investigation

- **Export-ignore verified (FEAT-006):** `git archive HEAD | tar` yields 97 files, 0 `paco`/`Paco`/`PACO`, no `specs/`, no `flavors/gift/maintainer/`, no `BIZ-PLAN`/`TODO-NEXT`. So `git archive` already produces the correct tree — publish.sh wraps it with a verification gate + push.
- **Dev repo remote:** `origin` = `https://github.com/jesusmartincalvo/buildersinabox.git`. The public repo will be a *second* remote (e.g. `public` = `git@github.com:sixsevenapps/buildersinabox-installer.git`).
- **Org access:** `jesusmartincalvo` owns the `sixsevenapps` org (confirmed; private membership). `gh repo create sixsevenapps/buildersinabox-installer` works with current auth.
- **Publish mechanism options:** (a) `git archive` → extract → commit in a throwaway worktree pointed at the public remote; (b) a dedicated `public` orphan branch. Option (a) is cleaner: extract to a temp dir that is its own git repo tracking the public remote, commit the snapshot, push. Keeps the public repo history as a sequence of release snapshots.

### Scope

#### Includes

- `tools/publish.sh` — the extract + verify + push pipeline.
- A `--dry-run` mode that extracts + verifies + reports what would be pushed, without pushing.
- `--tag vX.Y.Z` release tagging.
- Documentation in `MAINTAINING.md` (the one-time repo creation + the publish workflow).
- The actual one-time creation of `sixsevenapps/buildersinabox-installer` (maintainer action, scripted via `gh` in the spec).

#### Does NOT include

- Mirroring dev history (deliberately fresh history).
- CI on the public repo (FEAT-009 ships the workflow file; it activates once the tree lands in the public repo).
- The sibling module repos (conerator/observio/pathtrip) — same pattern, future FEATs.
- Flipping the repo to public (a deliberate, separate launch-day action, gated on smoke tests passing).

### Affected files

| File | Action |
|------|--------|
| `tools/publish.sh` | CREATE |
| `MAINTAINING.md` | MODIFY — repo creation + publish workflow |

### Dependencies

- `git`, `gh`, `tar`. No new runtime dependency.

### Tasks

#### Wave 1

<task id="1">
  <name>publish.sh extract + verify gate</name>
  <files>tools/publish.sh</files>
  <action>
    set -euo pipefail. Steps: (1) parse --dry-run, --tag, --force; (2) TMP=$(mktemp -d);
    git archive HEAD | tar -x -C "$TMP"; (3) run tools/check-no-personal-refs.sh logic
    against "$TMP" (or copy the script in and run it there) — abort on any hit; (4)
    explicit deny-list check: fail if $TMP contains specs/, flavors/gift/maintainer/,
    BIZ-PLAN-LIFESTYLE.md, TODO-NEXT-ISO.md; (5) if --dry-run, print file count +
    tree summary and exit 0.
  </action>
  <verify>bash -n tools/publish.sh && shellcheck tools/publish.sh && bash tools/publish.sh --dry-run | grep -q "files"</verify>
  <done>--dry-run extracts, runs the gate, reports file count, pushes nothing. shellcheck clean.</done>
</task>

<task id="2">
  <name>publish.sh push to public remote</name>
  <files>tools/publish.sh</files>
  <action>
    After the gate: in $TMP, git init, set the public remote (from a PUBLIC_REMOTE
    env or a documented default git@github.com:sixsevenapps/buildersinabox-installer.git),
    fetch existing main if present, commit the snapshot ("release: <tag|date>"), and
    push to main. If the remote isn't reachable/configured, print the exact
    `git remote add` + `gh repo create` commands and exit without pushing. With
    --tag, create + push the tag. Refuse force-push to main without --force +
    interactive confirm.
  </action>
  <verify>bash tools/publish.sh --dry-run --tag v0.0.0-test | grep -q "v0.0.0-test"</verify>
  <done>Push path implemented; dry-run shows the intended tag/commit; force-push guarded.</done>
</task>

<task id="3">
  <name>Create the public repo (maintainer action, scripted)</name>
  <files>MAINTAINING.md</files>
  <action>
    Document + provide the command: `gh repo create sixsevenapps/buildersinabox-installer
    --private --description "<from FEAT-009 MAINTAINING>"`. Then first publish:
    `tools/publish.sh --tag v0.1.0`. Then (launch day, separate) `gh repo edit
    sixsevenapps/buildersinabox-installer --visibility public` + set topics. Document
    the whole sequence so it's repeatable.
  </action>
  <verify>grep -q "gh repo create sixsevenapps/buildersinabox-installer" MAINTAINING.md</verify>
  <done>MAINTAINING documents repo creation, first publish, and the public-flip as distinct gated steps.</done>
</task>

#### Wave 2 — verification

<task id="4">
  <name>Dry-run + real publish to a throwaway repo</name>
  <files>tools/publish.sh</files>
  <action>
    Verify against a throwaway private repo (e.g. sixsevenapps/biab-publish-test or a
    local bare repo): run publish.sh --dry-run (gate passes, nothing pushed), then a
    real publish to the throwaway, then clone it fresh and assert: no specs/, no
    maintainer/, no BIZ-PLAN, git log shows a single clean release commit, and
    check-no-personal-refs.sh passes on the clone. Delete the throwaway.
  </action>
  <verify>PUBLIC_REMOTE=file:///tmp/biab-public-test.git bash tools/publish.sh --tag v0.0.1-test && git clone /tmp/biab-public-test.git /tmp/biab-public-clone && ! test -d /tmp/biab-public-clone/specs && bash /tmp/biab-public-clone/tools/check-no-personal-refs.sh</verify>
  <done>Throwaway publish yields a clean single-commit repo with no internal paths; guard passes on the fresh clone.</done>
</task>

### Code pattern to follow

Reuse the FEAT-006 verification approach (extract via git archive, grep the extracted tree) as the publish gate — same commands, now as a release guard:

```bash
TMP="$(mktemp -d)"
git archive HEAD | tar -x -C "$TMP"
for forbidden in specs flavors/gift/maintainer BIZ-PLAN-LIFESTYLE.md TODO-NEXT-ISO.md; do
  [ -e "$TMP/$forbidden" ] && { echo "ABORT: $forbidden leaked into archive"; exit 1; }
done
( cd "$TMP" && bash tools/check-no-personal-refs.sh ) || exit 1
```

### Global acceptance criteria

- [ ] `tools/publish.sh --dry-run` extracts, runs the gate, reports, pushes nothing.
- [ ] Gate aborts on any personal ref or forbidden path in the extracted tree.
- [ ] Real publish to a throwaway repo yields a single clean release commit, no `specs/`/`maintainer/`/`BIZ-PLAN`.
- [ ] `--tag vX.Y.Z` tags the release on the public repo.
- [ ] Force-push to main is guarded by `--force` + confirmation.
- [ ] MAINTAINING documents repo creation, first publish, and the public-flip as separate gated steps.
- [ ] `shellcheck tools/publish.sh` clean.

## §3 — Boundaries

### Always

- The publish gate (`check-no-personal-refs.sh` + deny-list) runs before every push; a failure aborts with the offending path named.
- Public repo history is fresh (release snapshots), never a mirror of dev history.
- English; the script itself passes the guard.

### Ask First

- Flipping the public repo to `public` visibility (launch-day decision, gated on smoke tests).
- Any force-push to the public default branch.
- Changing the publish model from fresh-snapshot to full-history mirror.
- Publishing sibling module repos (separate FEATs, same pattern).

### Never

- Push `specs/`, `flavors/gift/maintainer/`, `BIZ-PLAN-LIFESTYLE.md`, `TODO-NEXT-ISO.md`, or any personal reference to the public repo.
- Mirror dev-repo history (it contains Paco-era commits + messages).
- Store credentials/tokens in publish.sh.
- Auto-flip visibility to public without explicit maintainer action.

## §4 — QA

> Owner: QA Lead (`sdd-qa`)

### Test cases (functional)

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| F1 | Dry-run gate passes on clean tree | `tools/publish.sh --dry-run` | Extracts, gate passes, reports file count, no push | pending |
| F2 | Real publish to throwaway | `PUBLIC_REMOTE=file:///tmp/x.git tools/publish.sh --tag v0.0.1-test` | Throwaway repo gets one clean release commit | pending |
| F3 | Clean clone audit | Clone the throwaway | No specs/, no maintainer/, no BIZ-PLAN; guard passes; single commit | pending |
| F4 | Tag created | After F2 | `git -C clone tag` shows v0.0.1-test | pending |

### Edge cases

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| E1 | Forbidden path leaks | Temporarily remove specs/ export-ignore, run publish | Gate aborts naming specs/, nothing pushed | pending |
| E2 | Personal ref leaks | Plant `paco` in a shippable file, run publish | Gate aborts naming the file, nothing pushed | pending |
| E3 | Remote not configured | Unset PUBLIC_REMOTE | Prints the gh repo create + git remote add commands, exits 0 without push | pending |
| E4 | Force-push guard | `publish.sh` without --force when main diverged | Refuses, instructs to use --force + confirm | pending |

### Regression

- [ ] `git archive HEAD` still yields the same 97-file clean tree (FEAT-006 invariant).
- [ ] Dev repo `origin` and history untouched by publish.sh.
- [ ] `.gitattributes` export-ignore rules still in force.

### Testing criteria

```bash
shellcheck tools/publish.sh
bash -n tools/publish.sh

# Throwaway end-to-end (no GitHub needed)
git init --bare /tmp/biab-public-test.git
PUBLIC_REMOTE=file:///tmp/biab-public-test.git bash tools/publish.sh --tag v0.0.1-test
git clone /tmp/biab-public-test.git /tmp/biab-public-clone
[ ! -d /tmp/biab-public-clone/specs ] && [ ! -d /tmp/biab-public-clone/payload/flavors/gift/maintainer ] && echo CLEAN
bash /tmp/biab-public-clone/tools/check-no-personal-refs.sh
git -C /tmp/biab-public-clone log --oneline | wc -l   # expect 1
rm -rf /tmp/biab-public-test.git /tmp/biab-public-clone
```

## §5 — Implementation

> To be filled during spec-implementer run. Branch `feat/FEAT-011`.

## §6 — Feedback

(none yet)
