---
name: docker-ops
description: Docker container management for development projects. Use when checking container status, viewing logs, rebuilding images, restarting services, or cleaning up Docker resources.
allowed-tools: Bash(docker*), Bash(docker-compose*), Read, Glob, Grep
disable-model-invocation: true
---

# Docker Operations

Manage Docker containers, images, and services across all projects.

## Common Operations

### Status Check
```bash
docker compose ps                    # Current project
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"  # All running
```

### Logs
```bash
docker logs --tail 100 <container>          # Last 100 lines
docker logs --tail 50 --follow <container>  # Follow live
docker logs --since 1h <container>          # Last hour
```

### Restart & Rebuild
```bash
# Restart without rebuild (config changes only)
docker compose restart <service>

# Full rebuild (code changes)
docker compose build <service> && docker compose up -d <service>

# Rebuild without cache (dependency changes)
docker compose build --no-cache <service> && docker compose up -d <service>
```

### Cleanup
```bash
docker system df                     # Check disk usage
docker image prune -f                # Remove dangling images
docker system prune -f               # Remove all unused (careful)
```

## Finding a Project's Compose File

Each project keeps its own `docker-compose.yml` (sometimes under a `docker/`
subdirectory). To locate them all:

```bash
find ~/ai-platform/projects -maxdepth 3 -name "docker-compose.y*ml" 2>/dev/null
```

Run `docker compose` commands from the directory containing the compose file,
or pass `-f <path>` explicitly.

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| Container keeps restarting | `docker logs <container>` | Fix error in code, rebuild |
| Port already in use | `docker ps` + `lsof -i :<port>` | Stop conflicting process |
| Out of disk space | `docker system df` | `docker system prune -f` |
| Build fails | Check Dockerfile and requirements | `docker compose build --no-cache` |
| Container can't reach network | `docker network ls` | Recreate: `docker compose down && up -d` |

## Rules

- ALWAYS use `docker compose` (not `docker-compose`) for modern Docker
- ALWAYS rebuild after code changes — containers use copied code, not live mounts
- Check `docker-compose.yml` for volume mounts before assuming files are copied
- Never remove volumes without confirming with user (data loss risk)
