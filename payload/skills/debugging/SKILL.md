---
name: debugging
description: "Production debugging guide. Log access, Docker diagnostics, service health, database queries for troubleshooting."
disable-model-invocation: true
---

# Debugging

## Quick Triage (run first)

```bash
# What's running?
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
pm2 list
netstat -tlnp 2>/dev/null | grep LISTEN

# Recent errors (Docker)
docker logs --tail 50 --since 1h <container> 2>&1 | grep -iE 'error|critical|exception|traceback'

# Recent errors (PM2)
pm2 logs --lines 50 --nostream | grep -iE 'error|critical|exception|traceback'
```

## Know Your Ports

Keep a ports table for your own services in a project doc or the project's
agent context file (CLAUDE.md / AGENTS.md), e.g.:

| Service | Port | Health Endpoint | Container/Process |
|---------|------|-----------------|-------------------|
| my-api | 8080 | `localhost:8080/health` | docker: my-api |
| my-worker | — | (no HTTP; check logs) | pm2: my-worker |
| PostgreSQL | 5432 | `docker exec <pg-container> pg_isready` | docker: postgres |

If you don't have one, build it now from `docker ps` + `pm2 list` output —
it pays for itself the first time something breaks at 2am.

## Log Patterns to Grep

```bash
# General error scan
docker logs <container> 2>&1 | grep -iE 'error|critical|fatal|traceback|exception|panic'

# Specific patterns
grep -n 'ECONNREFUSED'    # Service can't reach dependency
grep -n 'ENOMEM'          # Out of memory
grep -n '502\|503\|504'   # Upstream failures
grep -n 'SIGTERM\|SIGKILL' # Process killed
```

## Database Debugging

```bash
# Connect to PostgreSQL (read the password from the project's .env, never hardcode)
PGPASSWORD=$(grep DB_PASSWORD <project>/.env | cut -d= -f2) \
  psql -h localhost -U <user> -d <database>

# Common diagnostic queries
SELECT count(*) FROM pg_stat_activity;              -- Active connections
SELECT * FROM pg_stat_activity WHERE state = 'active'; -- Running queries
SELECT pg_database_size('<database>');               -- DB size
SELECT relname, n_dead_tup FROM pg_stat_user_tables
  ORDER BY n_dead_tup DESC LIMIT 5;                 -- Tables needing VACUUM
```

## Network Diagnostics

```bash
# Check if port is listening
netstat -tlnp 2>/dev/null | grep :<PORT>

# Test endpoint verbosely
curl -v localhost:<PORT>/health

# DNS resolution inside Docker
docker exec <container> nslookup <hostname>

# Container-to-container connectivity
docker exec <container> curl -sf http://<other-container>:<port>/health
```

## Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Container restart loop | Crash on startup, bad config | `docker logs <c>`, check env vars |
| Port not listening | Service didn't start | `docker ps -a` for exited containers, check logs |
| 502 Bad Gateway | Upstream service down | Check dependent service health |
| DB connection refused | Database down or max connections | `docker restart <pg-container>`, check `pg_stat_activity` |
| Out of disk | Docker images/logs filling disk | `docker system prune -f`, rotate logs |
| PM2 high restarts | Unhandled exception in loop | `pm2 logs`, fix error, `pm2 restart` |
| Slow API response | DB query performance | Check `pg_stat_activity` for long queries |

## Health Check Script (all services)

Adapt the service:port list to your own stack:

```bash
for svc in "my-api:8080" "my-frontend:3000"; do
  name="${svc%%:*}"; port="${svc##*:}"
  curl -sf "localhost:$port/health" > /dev/null 2>&1 \
    && echo "OK   $name ($port)" \
    || echo "FAIL $name ($port)"
done
docker ps --format '{{.Names}}' | grep -q postgres \
  && echo "OK   PostgreSQL" || echo "FAIL PostgreSQL"
```
