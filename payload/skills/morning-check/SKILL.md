---
name: morning-check
description: Quick "what's the state of my device this morning" survey. Run at the start of a session to see what's running, what shipped overnight, what brain-dumps you left for yourself, and what's pending. Designed to be fast (under 30 seconds) and read like a daily standup with yourself.
---

# /morning-check — the 30-second device status

When the user invokes this skill, run a small battery of probes and report the result as a single tight markdown summary. No prose, no hedging — bullets and counts.

## What to gather

Run each of these (with Bash tool). All of them must tolerate missing data — if a command fails or returns empty, the corresponding section just says "—" or is omitted.

### Sessions

```bash
tmux ls 2>/dev/null || echo "(no tmux running)"
```

### Recent commits (last 24h, across all projects)

```bash
find ~/ai-platform/projects -maxdepth 2 -name .git -type d 2>/dev/null \
  | while read -r g; do
      repo="$(dirname "$g")"
      cnt="$(git -C "$repo" log --since='24 hours ago' --oneline 2>/dev/null | wc -l)"
      if [[ "$cnt" -gt 0 ]]; then
          printf '  %s: %s commit(s) in last 24h\n' "$(basename "$repo")" "$cnt"
      fi
  done
```

### Pending PRs (across your GitHub)

```bash
gh pr list --author "@me" --state open --limit 10 --json title,url,repository \
  --jq '.[] | "  - " + .repository.name + " · " + .title + " · " + .url' 2>/dev/null || echo "  (gh not authed or no PRs)"
```

### Brain-dump pending (bd entries not yet triaged)

```bash
bd_file="$HOME/ai-platform/stratops/brain-dump.jsonl"
if [[ -f "$bd_file" ]]; then
    pending="$(jq -s 'map(select(.processed == false)) | length' "$bd_file" 2>/dev/null || echo 0)"
    echo "  $pending unprocessed entries in brain-dump.jsonl"
    # Show the 3 most recent unprocessed for a nudge
    jq -s 'map(select(.processed == false)) | .[-3:] | reverse | .[] | "    - " + .text' \
        "$bd_file" 2>/dev/null
else
    echo "  (no brain-dump file yet — try: bd \"your first idea\")"
fi
```

### Disk + memory pulse

```bash
df -h / | awk 'NR==2 {printf "  root: %s used (%s available)\n", $5, $4}'
free -h | awk 'NR==2 {printf "  RAM: %s used / %s total\n", $3, $2}'
uptime | awk '{print "  uptime: " $3 " " $4 " load:" $(NF-2) " " $(NF-1) " " $NF}'
```

### Tailscale + SSH reachability

```bash
tailscale status 2>/dev/null | head -5
```

### Today's date in local time

```bash
date '+%A %d %b %Y, %H:%M (%Z)'
```

## Output format

Render as a single markdown block — terse, scannable, mobile-friendly. Example shape:

```
## ☀️ Good morning — Thursday 29 May 2026, 09:14 (CEST)

### Sessions
- ai-platform  (created Mon)
- finance-dashboard  (created yesterday, 2 windows)

### Last 24h activity
  finance-dashboard: 3 commits

### Open PRs
  - finance-dashboard · "Add Cloudflare worker" · https://github.com/<user>/finance-dashboard/pull/4

### Brain dump
  4 unprocessed entries:
    - "burn rate widget should be top-right not bottom"
    - "look up how the cron daemon is wired up"
    - "tax categorisation for ETFs — separate from stocks?"

### System
  root: 27% used (45G available)
  RAM: 5.2G used / 32G total
  uptime: 3 days  load: 0.21 0.32 0.18

### Tailnet
  biab           user@   active
  pixel-9        user@   offline 4h ago
```

End with one nudge — pick whichever applies:
- if there are unprocessed brain-dump entries: "→ triage your inbox first?"
- if there are open PRs: "→ resolve PR(s) first?"
- if neither: "→ ready to build."

## Tone

- Single greeting line at the top, then sections. No paragraph prose.
- Always include the date and weekday — The user may use this from the phone in transit and want orientation.
- If something is broken (e.g. tailscale is down), say so plainly without alarm.

## When NOT to use this skill

- The user is mid-task. Don't volunteer it unless they ask.
- More than 5 sections would be empty. The skill should be useful — if the device is brand-new (no projects, no PRs, no brain-dumps), suggest `/tutorial` instead.
