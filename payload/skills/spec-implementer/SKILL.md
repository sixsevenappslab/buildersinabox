---
name: spec-implementer
description: Implements a validated FEAT-NNN spec wave by wave in a dedicated git worktree, runs quality gates, writes progress into the PR body, opens the PR with gh, and hands off to pr-review. Use when a FEAT has validated_by signed off and is ready to build.
---

# Spec Implementer

Implements one validated FEAT spec end-to-end and opens a verified pull request. Read `sdd-base` first for the v1 FEAT structure (Starter vs Full mode) and lifecycle (`draft/` → `active/` → `completed/`).

Copy this checklist and tick each step as you go:

```markdown
- [ ] 0. Confirm CWD matches the target project
- [ ] 1. Verify frontmatter (`status`, `validated_by`) and create a `git worktree` from `origin/main`
- [ ] 2. Implement tasks wave by wave (from §2 or Starter `## Tasks`), verifying each task
- [ ] 3. Run §2 quality gates (tests, lint, secret scan, scope check against §1 Boundaries)
- [ ] 4. Self-review the diff and fix any blocking (`🔴`) issues
- [ ] 5. Open the PR with `gh pr create` (progress table in the PR body) and run `pr-review`
- [ ] 6. Stop at the PR and report URL, branch and gate evidence to the owner
```

## Autonomy & Merge Switch (`~/.config/buildersinabox/sdd.json`)

By default, **this skill stops at the pull request** (`auto_merge: false`). Merging to `main` and deploying are the owner's decision.

- Read (never write, create or modify) `~/.config/buildersinabox/sdd.json`:
  ```bash
  jq -r '.auto_merge // false' ~/.config/buildersinabox/sdd.json 2>/dev/null
  ```
- When absent or not `true`, record `Auto-merge mode: stop-at-pr (default — owner merges)` in the PR body and stop after Step 5.
- Even when the owner sets `"auto_merge": true`, always stop and ask once at any of the **six hard stops**: (1) money/billing, (2) credentials, `.env` or security rules, (3) external actions on the owner's behalf, (4) irreversible deletions, (5) production deployments without an explicit request in the prompt, or (6) `sudo`.

## Step 0 — Confirm the working directory

Mixing projects in one session loads the wrong `CLAUDE.md` / `AGENTS.md` and can commit to the wrong repository:

1. Check `pwd` and `git rev-parse --show-toplevel`.
2. Confirm it matches the project in the FEAT's frontmatter (`project:`). If not, stop and ask the user to switch directories.

## Step 1 — Validate readiness and prepare the worktree

1. **Locate the FEAT** in `specs/active/` (or `specs/draft/`).
2. **Check sign-off (`validated_by`):** Read frontmatter (`status`, `validated_by`) in Full mode, or confirm owner sign-off in Starter mode:
   - If `validated_by` is `null`, empty or missing, **refuse to implement** and ask the owner to sign off Definition of Ready first (via `sdd-coordinator`).
   - If `validated_by` is set and the file is in `specs/draft/`, move it to `specs/active/` with `git mv` and set `status: active`.
3. **Read context:** Read the FEAT once, then the project's `CLAUDE.md` or `AGENTS.md`. Extract:
   - **§1 Boundaries** (`Always`, `Ask first`, `Never`) in Full mode, or `## Summary` in Starter mode.
   - **Tasks:** §2 `### Implementation plan (waves)` in Full mode, or `## Tasks` in Starter mode.
   - **QA & Gates:** §2 `### Quality gates` and §4 `## QA` (or Starter `## QA`).
4. **Create an isolated worktree from `origin/main`:**
   - Resolve `base_branch` from `~/.claude/projects.yaml` if present; otherwise use `origin/main`.
   - Create a sibling worktree so the main checkout stays untouched:
     ```bash
     git fetch origin main
     git worktree add "../<project>-<feat-id-lower>" -b "feat/<feat-id-lower>-<slug>" origin/main
     cd "../<project>-<feat-id-lower>"
     ```

## Step 2 — Implement wave by wave

Work inside the new worktree, following §2 waves (or Starter `## Tasks`):

1. **State assumptions** briefly before each wave.
2. **Minimal, surgical changes:** implement only what the spec asks for. Do not refactor adjacent files.
3. **Verify every task:** run the task's test or verification command before moving on.
4. **Retry cap (3 attempts):** on a failing test or verification, fix the root cause with the error output in context. After **3 failed attempts** on a task, stop and report the exact output, passing tasks, and branch path.
5. **Boundaries check:** follow **Always** and **Never** strictly. On an **Ask first** item touching a hard stop or product scope, pause and ask one clear question with options and a recommendation; for technical choices inside scope, pick the conservative option and note it in the PR body.

## Step 3 — Quality gates

Run every gate from §2 `### Quality gates` and the project's `CLAUDE.md` / `AGENTS.md`:

- **Tests:** run the project's test suite and the functional/edge cases in §4 QA.
- **Lint:** run `npm run lint`, `shellcheck`, or the project's linter if present.
- **Secrets check:** verify `git status` and `git diff origin/main...HEAD` contain no `.env`, keys, tokens or credentials.
- **Scope check:** verify `git diff --stat origin/main...HEAD` touches only files justified by §2 (plus the FEAT file).

When checking a local service, use a single bounded command (`timeout 30 bash -c 'until curl -fsS http://127.0.0.1:3000/health >/dev/null; do sleep 1; done'`) instead of polling across turns.

## Step 4 — Self-review

Review `git diff origin/main...HEAD` against §1 acceptance criteria, §1 Boundaries, and §4 QA:

- Fix any 🔴 blocking bug or spec gap before opening the PR (at most 2 fix cycles).
- In the v1 FEAT template, §5 is `Docs (post-merge checklist)`, so implementation progress belongs in the **PR body**, not in §5.

## Step 5 — Open the PR and hand off to `pr-review`

Push the branch and open the PR against `main` (or `base_branch`) with `gh pr create`:

```bash
git push -u origin "feat/<feat-id-lower>-<slug>"
gh pr create --base main --title "feat(FEAT-NNN): <short title>" --body "<structured body>"
```

The **PR body** must include:
1. **FEAT reference:** path to `specs/active/FEAT-NNN-<slug>.md` and summary.
2. **Task progress table:** each wave/task, status (`verified`), commit SHA, and verification evidence.
3. **Quality gates & QA results:** test counts, lint status, and any deviations from §2.
4. **Mode line:** `Auto-merge mode: stop-at-pr (default — owner merges)` (or `owner-enabled (~/.config/buildersinabox/sdd.json)` when `.auto_merge == true`).

Then run `pr-review` on the new PR and report the PR URL, branch, verification summary, and review verdict to the owner. The owner merges the PR, after which the FEAT moves to `specs/completed/`.
