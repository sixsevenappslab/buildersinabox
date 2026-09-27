---
name: qa-testing
description: "QA testing skill. Test plan creation, PR validation against specs, structured bug reports, regression testing checklist."
---

# QA Testing

## Test Plan Template

```
### Test: [Feature Name]
**Spec:** FEAT-NNN | **Priority:** P0/P1/P2

#### Acceptance Criteria
- [ ] **AC-1:** Given [precondition], When [action], Then [expected result]
- [ ] **AC-2:** Given [precondition], When [action], Then [expected result]

#### Edge Cases
- [ ] Empty input / no data
- [ ] Network failure / timeout
- [ ] Unauthorized access
- [ ] Concurrent requests
```

## PR Validation Workflow

1. **Read spec** — open `specs/{draft|active}/FEAT-NNN.md`, extract acceptance criteria
2. **Read PR diff** — `gh pr diff <number>` or review changed files
3. **Verify each AC** — trace code changes to each criterion, mark ✅ or ❌
4. **Check boundaries** — confirm spec section 3 (out-of-scope) wasn't implemented
5. **Report** — structured verdict: APPROVED / CHANGES_REQUESTED with line refs

## Bug Report Format

```
🐛 Bug: [title]
Severity: 🔴 Critical / 🟠 Major / 🟡 Minor / ⚪ Cosmetic
Steps:
  1. ...
  2. ...
  3. ...
Expected: ...
Actual: ...
Evidence: [screenshot/log/curl output]
Spec ref: FEAT-NNN AC-X (if applicable)
```

## Regression Checklists

Keep one checklist per project and grow it as features ship — every regression
you catch (or miss) earns a line. A typical web app's list looks like:

### Example: a web app
- [ ] Auth flow (signup/login/refresh token)
- [ ] Core user flow end-to-end (the thing the app is *for*)
- [ ] Background jobs execute on schedule (cron, queues)
- [ ] Notifications deliver (email/push/webhook)
- [ ] External integrations sync (third-party APIs, OAuth refresh)
- [ ] API health (`/health` returns 200)

## Testing Commands

```bash
# Health checks
curl -s localhost:<port>/health | jq .

# Docker status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# DB connectivity
docker exec <pg-container> pg_isready -U postgres

# PM2 services
pm2 list

# Quick endpoint test
curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>/api/endpoint
```

## Smoke Tests (Critical Paths)

Define 3-4 requests per service that prove it's alive and doing its job — run
them after every deploy. The shape:

### Example: an API service (port <port>)
1. `GET /health` → 200
2. `POST /api/auth/login` → valid token
3. `GET /api/<core-resource>` (authed) → expected data
4. One request through the service's main side effect (a redirect, a queued
   job, a webhook) → observable result
