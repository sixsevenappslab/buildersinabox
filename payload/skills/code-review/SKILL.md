---
name: code-review
description: "Structured PR code review process. Checklists, GitHub CLI commands, review criteria by severity (🔴 bugs, 🟡 nits, 🔵 suggestions)."
---

# Code Review

## Workflow

1. **Fetch** — `gh pr view <number> --json title,body,additions,deletions,files`
2. **Diff** — `gh pr diff <number>`
3. **Checks** — `gh pr checks <number>`
4. **Analyze** — Apply checklist below to every changed file
5. **Comment** — Leave structured review via `gh pr review`
6. **Verdict** — Approve or request changes

## Severity Scale

| Icon | Level | Action Required |
|------|-------|-----------------|
| 🔴 | **Bug** | Must fix before merge |
| 🟡 | **Nit** | Optional, nice to have |
| 🔵 | **Suggestion** | Consider for future |
| 🟣 | **Pre-existing** | Not introduced by this PR, track separately |

## Review Checklist

- [ ] **Security** — No hardcoded secrets, API keys, tokens in diff
- [ ] **Error handling** — Try/catch where needed, meaningful error messages
- [ ] **Tests** — New logic has tests, existing tests still pass
- [ ] **Backwards compatibility** — No breaking changes to APIs or DB schemas
- [ ] **Naming** — Variables, functions, files follow project conventions
- [ ] **Docs** — README/comments updated if behavior changed
- [ ] **No debug artifacts** — No `console.log`, `print()`, `debugger` left behind
- [ ] **TODOs** — Any new TODO references a GitHub issue number

## Auto-Checks (grep the diff)

```bash
# Hardcoded secrets
gh pr diff <number> | grep -inE '(password|secret|api_key|token)\s*[:=]'

# Debug statements
gh pr diff <number> | grep -nE '^\+.*(console\.log|print\(|debugger)'

# TODOs without issue reference
gh pr diff <number> | grep -nE '^\+.*TODO' | grep -v '#[0-9]'
```

## Leaving a Review

```bash
# Approve
gh pr review <number> --approve --body "✅ LGTM — clean implementation, tests pass."

# Request changes (body supports markdown)
gh pr review <number> --request-changes --body "$(cat <<'EOF'
## Review — PR #<number>

🔴 **Bug:** `handlePayment()` doesn't catch network errors (src/pay.ts:42)
🟡 **Nit:** Rename `data` → `userProfile` for clarity (src/api.ts:15)
🔵 **Suggestion:** Consider extracting validation into a shared util

**Verdict:** Requesting changes for the 🔴 bug.
EOF
)"

# Comment only (no verdict)
gh pr review <number> --comment --body "🔵 Minor suggestions, non-blocking."
```

## Review Comment Format

Structure every review body as:

```
## Review — PR #<number>

<severity emoji> **<Level>:** <description> (<file>:<line>)
...

**Verdict:** <summary of blocking vs non-blocking items>
```
