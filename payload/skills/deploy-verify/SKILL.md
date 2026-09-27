---
name: deploy-verify
description: Post-deployment verification checklist. Use after deploying code changes to verify the deployment succeeded — checks logs, endpoints, connectivity, and basic smoke tests.
allowed-tools: Bash(docker*), Bash(curl*), Bash(pm2*), Read, Grep
disable-model-invocation: true
---

# Deploy Verification

Verify deployments succeeded after any code change is deployed.
(For the deploy commands themselves and rollback criteria, see the
`deploy-ops` skill, an optional install.)

## Verification Checklist

### 1. Service Running
```bash
# Docker services
docker compose ps | grep -E "Up|running"

# PM2 services
pm2 list | grep online
```

### 2. No Crash Loops
```bash
# Check restart count (should be 0 or low)
docker ps --format "{{.Names}}\t{{.Status}}"

# Check recent logs for errors
docker logs --tail 30 <container> 2>&1 | grep -iE "error|exception|traceback|fatal"
```

### 3. Endpoint Health
```bash
# HTTP health check
curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>/health

# API endpoint test
curl -s http://localhost:<port>/api/status | python3 -m json.tool
```

### 4. Logs Clean
```bash
# Last 30 lines, look for startup confirmation
docker logs --tail 30 <container>

# Grep for specific error patterns
docker logs --since 2m <container> 2>&1 | grep -c "ERROR"
```

### 5. Connectivity
```bash
# Database accessible
docker exec <container> python -c "import sqlite3; sqlite3.connect('/app/data/db.sqlite3')"

# External APIs reachable
docker exec <container> python -c "import urllib.request; urllib.request.urlopen('https://api.github.com')"
```

## Quick Verify Script

Run all checks in sequence:
```bash
SERVICE="<container>"
echo "=== Status ===" && docker ps --filter name=$SERVICE --format "{{.Status}}" && \
echo "=== Recent Errors ===" && docker logs --tail 50 $SERVICE 2>&1 | grep -iE "error|exception|fatal" | tail -5 && \
echo "=== Last Log Lines ===" && docker logs --tail 10 $SERVICE
```

## Red Flags

- Container status shows "Restarting" — crash loop, check logs
- Log shows "ModuleNotFoundError" — missing dependency, rebuild with --no-cache
- Log shows "Permission denied" — file permissions issue in container
- Log shows "Connection refused" — dependent service not ready, check docker compose order
- No recent log output — process may have hung, restart

## Rules

- ALWAYS verify after deployment — never assume success
- Check logs FIRST before reporting success
- If errors found, investigate and fix before marking task complete
- For user-facing services, test from the user's perspective (web browser, phone) when possible
