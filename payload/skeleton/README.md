# skeleton/

The workspace that gets copied into the user's home directory on first boot. After the device finishes setup, the user lands at:

```
~/ai-platform/
├── CLAUDE.md            # workspace-level instructions
├── projects/            # empty — your first project gets scaffolded here
└── stratops/            # strategy & ops "mesa" (OKRs, roadmap, notes)
```

The user lands in a single tmux session called `ai-platform` (cwd
`~/ai-platform/`) with Claude Code already running, which opens `/tutorial`.
The tutorial walks you through creating your first project; `/first-project`
then spins up its own tmux session per project, so each shows up as a separate
remote session in the Claude Code app.

## What's in `stratops/`

`stratops` (strategy + operations) is a workspace for the founder/operator-level thinking that doesn't belong inside a code project:

- `OKRs.md` — quarterly objectives
- `ROADMAP.md` — 6-12 month direction
- `PORTFOLIO.md` — snapshot of active projects + thesis
- `decisions/` — important decisions with rationale, dated
- `reviews/` — weekly / monthly reviews

You can ignore `stratops/` entirely if you're using your devbox just for code. It's there if you want it.

## What's intentionally NOT here

- No pre-installed code in `projects/`. Your first project is scaffolded with the name you choose in `/tutorial`.
- No personal data, no credentials, no example projects from other people. This is your devbox.
