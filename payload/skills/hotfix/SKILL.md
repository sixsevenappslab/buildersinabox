---
name: hotfix
description: Emergency hotfix workflow for production bugs that need a minimal, verified fix without a full FEAT spec. Runs from the affected project directory, verifies the fix, and stops after opening a hotfix pull request for the owner to merge.
---

# Emergency Hotfix Workflow

## When to Use

- Production bug: service down, broken functionality, or data corruption risk
- Time-sensitive — goal is a minimal, verified fix in under 30 minutes
- **NOT** for features, improvements, or refactors — use `sdd-coordinator` and `spec-implementer` for those

## Workflow

### 1. Assess and Reproduce
Confirm the bug is real and capture baseline evidence before touching code:
```bash
curl -fsS http://localhost:<port>/health   # service health check
docker ps                                  # container status (if containerised)
docker logs <container> --tail 50          # recent error logs
```

### 2. Create a Hotfix Branch or Worktree
Work from the project directory (`~/ai-platform/projects/<project>`) so its `CLAUDE.md` / `AGENTS.md` and project skills load automatically:
```bash
cd ~/ai-platform/projects/<project>
git fetch origin
git worktree add "../<project>-hotfix-<slug>" -b "hotfix/<slug>" origin/main
cd "../<project>-hotfix-<slug>"
```

### 3. Apply the Minimal Fix
Keep the scope strictly bounded:
- Read `CLAUDE.md` / `AGENTS.md` for project conventions and commands.
- Fix **only** the reported bug — no drive-by refactors, formatting sweeps, or unrelated edits.
- Add or update a regression test that fails without the fix and passes with it.
- Keep the diff as small and reviewable as possible.

### 4. Verify Locally
Run the project's test suite, linter, and health check before opening a PR:
```bash
npm test          # or pytest / cargo test / bash test suite
npm run lint      # if configured
```
If the fix touches a running local service, restart or rebuild it and verify the affected endpoint or UI path directly.

### 5. Open the Hotfix Pull Request (Stop at the PR)
Push the branch and open the pull request against the project's base branch (`main`):
```bash
git push -u origin "hotfix/<slug>"
gh pr create --base main \
  --title "hotfix(<project>): <short description>" \
  --body "## Bug
<symptoms, logs, affected endpoint>

## Root Cause & Fix
<minimal change made and why>

## Verification
<commands run and output>

## Rollback
\`git revert <merge-commit>\` and redeploy."
```

### 6. Hand Off to the Owner
**Stop at the PR — the owner merges and deploys.** Share the PR URL, the verification results, and the exact deploy command from the project's `CLAUDE.md` / `AGENTS.md` (or `deploy-ops`) so the owner can review, merge, and deploy immediately. If the fix touches data migrations, credentials, or security rules, flag that explicitly at the top of your message.

## Rollback

If a deployed hotfix causes a regression, revert the commit cleanly and redeploy:
```bash
git revert HEAD
git push origin HEAD
```
Then run the project's deploy command and `deploy-verify` checklist.

## Anti-patterns

- ❌ Fixing + refactoring in the same PR (scope creep delays emergency review)
- ❌ Skipping regression tests or verification before opening the PR
- ❌ Running from the wrong directory and missing project instructions (`CLAUDE.md` / `AGENTS.md`)
- ❌ Self-merging or deploying to production without the owner's confirmation
