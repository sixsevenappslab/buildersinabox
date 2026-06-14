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

### SOFI
- [ ] Login/auth flow (Google OAuth)
- [ ] Cron jobs execute on schedule
- [ ] Google Classroom sync (import/refresh)
- [ ] AI chat responds correctly
- [ ] Reminders trigger and deliver

### Hezu
- [ ] Auth (signup/login/refresh token)
- [ ] Chat flow (send/receive/history)
- [ ] Subscription (create/cancel/webhook)
- [ ] i18n (ES/EN switch, fallback keys)
- [ ] SSE streaming (connect/reconnect/timeout)

### Ganga24
- [ ] Deal pipeline (scrape → score → publish)
- [ ] Notifications (Telegram/email delivery)
- [ ] Affiliate links (correct provider, params)
- [ ] Redirect service (301, tracking, fallback)

### Chordna
- [ ] Search (query, autocomplete, results)
- [ ] Song pages (render, metadata, lyrics)
- [ ] SEO meta tags (title, description, OG)
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

### SOFI (port 5000)
1. `GET /health` → 200
2. `POST /api/auth/login` → valid token
3. `GET /api/tasks` (authed) → task list
4. `GET /api/classroom/courses` (authed) → course data

### Hezu (check docker/pm2)
1. `GET /health` → 200
2. `POST /api/auth/register` → user created
3. `POST /api/chat` (authed) → AI response
4. `GET /api/subscription/status` → plan info

### Ganga24 (port 8000)
1. `GET /health` → 200
2. `GET /api/deals?limit=5` → deal list
3. `GET /r/<deal-id>` → 301 redirect
4. `GET /api/notifications/status` → queue info

### Chordna (port 3001)
1. `GET /health` → 200
2. `GET /api/search?q=test` → results
3. `GET /api/songs/<slug>` → song data
