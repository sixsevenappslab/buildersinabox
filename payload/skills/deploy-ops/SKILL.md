---
name: deploy-ops
description: "Deployment reference card for your projects. Docker, Firebase, PM2 commands. Health checks, rollbacks, monitoring."
disable-model-invocation: true
---

# Deploy Ops

## Deployment Matrix

Keep a matrix like this for your own projects in a project doc or the
project's agent context file (CLAUDE.md / AGENTS.md) — one row per deploy
target, with the exact commands. Example:

| Project | Directory | Deploy | Verify | Rollback |
|---------|-----------|--------|--------|----------|
| **my-api** (Docker) | `projects/my-api/` | `docker compose build && docker compose up -d` | `curl -s localhost:8080/health` | `docker compose down && git checkout HEAD~1 && docker compose up -d` |
| **my-site** (Firebase) | `projects/my-site/` | `npm run build && firebase deploy --only hosting` | Load the site, check Firebase console | `firebase hosting:rollback` |
| **my-worker** (PM2) | `projects/my-worker/` | `git pull && npm ci && pm2 reload my-worker` | `pm2 show my-worker` | `git checkout HEAD~1 && npm ci && pm2 reload my-worker` |

If a project isn't in the matrix yet, work out the commands once and add the row.

## Health Checks

```bash
# Single service
curl -sf localhost:<port>/health && echo "OK" || echo "DOWN"

# All your services at a glance (adapt the list to your stack)
for svc in "my-api:8080" "my-frontend:3000"; do
  name="${svc%%:*}"; port="${svc##*:}"
  curl -sf "localhost:$port/health" > /dev/null 2>&1 \
    && echo "OK   $name ($port)" \
    || echo "FAIL $name ($port)"
done

# All listening ports
netstat -tlnp 2>/dev/null | grep LISTEN
```

## Docker Monitoring

```bash
# Running containers with ports
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Logs (last hour)
docker logs --tail 100 --since 1h <container>

# Resource usage
docker stats --no-stream

# Restart a crashed container
docker compose -f <project>/docker-compose.yml restart <service>
```

## Firebase Commands

```bash
firebase use <project-alias>            # Select target project first
firebase deploy --only hosting          # Deploy hosting only
firebase deploy --only functions        # Deploy functions only
firebase hosting:rollback               # Roll back the last hosting release
firebase login --reauth                 # When deploy fails with auth errors
```

## PM2 Commands

```bash
pm2 list                        # All processes
pm2 logs <app>                  # Live logs
pm2 logs <app> --lines 100      # Last 100 lines
pm2 reload <app>                # Graceful restart (zero downtime)
pm2 monit                       # Real-time monitor
```

## Post-Deploy Verification

Run the `deploy-verify` skill after every deploy — it's the full checklist
(service running, no crash loops, endpoint health, clean logs, connectivity).
Minimum bar if you skip it: run the project's health check, tail the logs for
errors, and confirm no restart loop.

## Rollback Decision

| Signal | Action |
|--------|--------|
| Health check fails immediately | Rollback now |
| Error rate > 5% in first 5 min | Rollback now |
| Restart loop detected | Rollback + investigate |
| Minor non-blocking errors | Monitor, fix forward |
