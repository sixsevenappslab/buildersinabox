---
name: pr-review
description: Coordinates a size-matched review of an open pull request — checking tests, scope, security and QA criteria — and reports a structured verdict before the owner merges. Use after spec-implementer opens a PR or when asked to review a PR.
---

# PR Review

Reviews an open pull request with depth proportional to the change. Over-delegating on a two-line doc edit wastes quota; under-checking business logic or auth changes misses real bugs.

## Step 1 — Size the review to the change

Pick the row matching `gh pr diff <n>` (when spanning multiple rows, use the highest-risk row):

| Change type | Review depth |
|---|---|
| Docs, specs, comments only | Read the diff yourself. No subagents needed. |
| Config, scripts or ops under 100 lines | Single code-review pass (inline or one generic subagent). |
| Business logic or feature code | Code review pass + `sdd-qa` acceptance/edge-case verification. |
| Feature touching acquisition, SEO, copy or analytics | Above + `sdd-growth` check against §3 Growth notes. |
| Auth, permissions, payments, secrets or shell hooks | Above + dedicated security audit of trust boundaries, input handling and privileges. |
| Database schema or migrations | Verify reversibility, lock impact and data-loss risk; state findings in the verdict. |

> **Note on `/code-review`:** `/code-review` is an interactive user command (`disable-model-invocation: true`), so agents cannot invoke it directly. Run the code-review pass yourself (or via generic subagents), and remind the owner they can run `/code-review` interactively.

## Step 2 — Gather the PR context (`gh --repo` caveat)

```bash
gh pr view <n> --json title,body,url,baseRefName,headRefName,changedFiles,additions,deletions
gh pr diff <n>
gh pr checks <n>
```

**Caveat on `gh`:** `gh` resolves the repository from the current working directory, **not** the PR number. In `~/ai-platform/projects/*` or across git worktrees, `cd` into the project/worktree first or pass `--repo <owner/repo>` explicitly.

Identify the contract:
- With a `FEAT-NNN` spec in `specs/active/`, read **§1 Product requirements & Boundaries**, **§2 Technical spec**, and **§4 QA** (or Starter `## Summary`, `## Tasks`, `## QA`).
- Without a FEAT, the PR description and `CLAUDE.md` / `AGENTS.md` are the contract.

## Step 3 — Verification, not opinion

A review that says "looks good to me" without executing anything has reviewed nothing:

1. **Run the tests:** execute the test suite and verification commands cited in the PR body or FEAT §4.
2. **Check cited paths and scope:** confirm every file in `gh pr diff <n> --name-only` belongs to the task and no `.env`, credential, or unrelated file leaked in.
3. **Mutate new tests on a `/tmp` copy:** when a PR adds or updates a test, copy the files to `mktemp -d`, break the behaviour under test on the copy, and confirm the test goes red (never mutate the working tree).
4. **Re-check subagent claims:** verify concrete counts, file paths and exit codes before repeating them.

Severity levels:
- 🔴 **Blocking:** bugs, broken tests, security flaws, boundary violations, or unmet acceptance criteria. Fix before merge.
- 🟡 **Should fix:** edge cases, maintainability issues, or missing non-critical test coverage.
- 🟢 **Nit:** optional style or wording suggestions.

## Step 4 — Synthesise the verdict

```markdown
PR #<n> — <title>
<url>

- Code review: <N 🔴 / N 🟡 / N 🟢>
- QA (`sdd-qa`): <approved | changes required | N/A>
- Growth (`sdd-growth`): <approved | changes required | N/A>
- Security: <approved | changes required | N/A>
- CI checks: <passing | pending | failing>

Verdict: <ready for owner merge | changes required>
```

## Step 5 — Hand off to the owner (the owner merges)

- **With 🔴 blocking findings:** fix them on the PR branch, push, and re-run affected checks (max 2 review-fix cycles before escalating to the owner).
- **When clean (`0 🔴` and CI green):** **the owner merges.** Stop and present the verdict block and PR URL so the owner can review and merge on GitHub.
- **Owner auto-merge switch (`~/.config/buildersinabox/sdd.json`):** only if the owner manually set `"auto_merge": true` in `~/.config/buildersinabox/sdd.json` (read-only — never create or edit that file) AND the PR touches none of the six hard stops (money, credentials/security configs, external actions, irreversible deletes, production without request, `sudo`), may the agent merge after a clean verdict.
