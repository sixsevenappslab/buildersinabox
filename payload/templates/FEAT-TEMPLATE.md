---
id: FEAT-NNN
title: <slug-kebab-case>
project: <project-name>
status: draft               # draft | active | completed
priority: medium            # low | medium | high
complexity: medium          # low (haiku) | medium (sonnet) | high (opus)
created: YYYY-MM-DD
validated_by: null          # set to the user/owner who signs off DoR
---

# FEAT-NNN: <title>

## §0 — Strategy

> Owner: Product Lead

- **Why now:** ...
- **Hypothesis:** ...
- **OKR / goal alignment:** ...
- **Cost of not doing it:** ...

## §1 — Product requirements

> Owner: Product Lead

### What it does
- ...

### Boundaries
- **Always:** behaviors that must happen.
- **Ask first:** ambiguous decisions that need user confirmation.
- **Never:** things explicitly out of scope.

### Product acceptance criteria
- [ ] ...
- [ ] ...

## §2 — Technical spec

> Owner: Tech Lead

### Research
- Files / modules to touch
- External dependencies
- Technical risks and mitigations

### Implementation plan (waves)
1. Wave 1 — ...
2. Wave 2 — ...
3. Wave 3 — ...

### Quality gates
- [ ] Tests pass
- [ ] Lint passes
- [ ] No secrets in commits
- [ ] Scope stays inside §1 boundaries

## §3 — Growth notes

> Owner: Growth Lead — *skip this section if the FEAT has no growth/marketing surface*

- **KPIs affected:** ...
- **Channels:** ...
- **UTMs / tracking:** ...
- **Experiments:** ...
- **SEO impact:** ...

## §4 — QA

> Owner: QA Lead

### Functional cases
- [ ] ...

### Edge cases
- [ ] ...

### Regression plan
- [ ] ...

### Smoke tests post-deploy
- [ ] ...

## §5 — Docs (post-merge checklist)

- [ ] Update project `CLAUDE.md` if conventions changed
- [ ] Add entry to `CHANGELOG.md`
- [ ] Public README updated (if user-facing)
- [ ] API docs / runbooks updated (if applicable)
- [ ] Onboarding docs touched (if applicable)

## §6 — Feedback (post-completed)

*Filled in after the FEAT ships. Capture what surprised us, what we'd do differently, links to incidents or follow-ups.*
