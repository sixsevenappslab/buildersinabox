# skeleton/

The workspace that gets copied into the user's home directory on first boot. After the device finishes setup, the user lands at:

```
~/ai-platform/
├── CLAUDE.md            # workspace-level instructions
├── projects/            # empty — first project gets scaffolded here during pairing
└── stratops/            # strategy & ops "mesa" (OKRs, roadmap, notes)
```

The user lands in tmux with three windows:

| Window | cwd | Purpose |
|---|---|---|
| `platform` | `~/ai-platform/` | Cross-cutting changes to the workspace itself |
| `<project-name>` | `~/ai-platform/projects/<project-name>/` | Active development |
| `stratops` | `~/ai-platform/stratops/` | Personal strategy, OKRs, roadmap, decisions |

Each window has Claude Code already running.

## What's in `stratops/`

`stratops` (strategy + operations) is a workspace for the founder/operator-level thinking that doesn't belong inside a code project:

- `OKRs.md` — quarterly objectives
- `ROADMAP.md` — 6-12 month direction
- `PORTFOLIO.md` — snapshot of active projects + thesis
- `decisions/` — important decisions with rationale, dated
- `reviews/` — weekly / monthly reviews

You can ignore `stratops/` entirely if you're using your devbox just for code. It's there if you want it.

## What's intentionally NOT here

- No pre-installed code in `projects/`. The first project is scaffolded with the name you provide during pairing.
- No personal data, no credentials, no example projects from other people. This is your devbox.
