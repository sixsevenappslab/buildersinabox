---
name: pm2-ops
description: PM2 process management for Node.js services. Use when checking PM2 status, restarting Node.js apps, viewing logs, or managing PM2 ecosystem configuration.
allowed-tools: Bash(pm2*), Bash(node*), Bash(npm*), Read, Glob, Grep
disable-model-invocation: true
---

# PM2 Operations

Manage Node.js processes running under PM2.

## Common Operations

### Status
```bash
pm2 list                        # All processes
pm2 show <app>                  # Detailed info for one app
pm2 monit                       # Real-time monitoring (interactive)
```

### Logs
```bash
pm2 logs <app> --lines 50       # Last 50 lines
pm2 logs <app> --err            # Error logs only
pm2 flush                       # Clear all log files
```

### Restart & Reload
```bash
pm2 restart <app>               # Hard restart (brief downtime)
pm2 reload <app>                # Graceful reload (zero downtime)
pm2 restart <app> --update-env  # Restart with updated env vars
```

### Start & Stop
```bash
pm2 start ecosystem.config.cjs  # Start from config file
pm2 start app.js --name myapp   # Start with name
pm2 stop <app>                  # Stop (keeps in list)
pm2 delete <app>                # Remove from list
```

### Save & Startup
```bash
pm2 save                        # Save current process list
pm2 startup                     # Generate startup script
```

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| App keeps restarting | `pm2 logs <app> --err` | Fix error, then `pm2 restart` |
| High memory usage | `pm2 show <app>` (memory) | Check for memory leaks, restart |
| App not responding | `pm2 show <app>` (status) | `pm2 restart <app>` |
| Env vars not loaded | `pm2 show <app>` (env) | `pm2 restart <app> --update-env` |
| Port conflict | `lsof -i :<port>` | Stop conflicting process |

## Rules

- Use `pm2 reload` over `pm2 restart` for zero-downtime when possible
- Always `pm2 save` after adding/removing processes to persist across reboots
- Check the project's `ecosystem.config.cjs` (or `.js`) for app configuration before manual starts
- Never use `pm2 kill` in production — it stops ALL PM2 processes
