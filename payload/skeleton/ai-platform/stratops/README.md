# stratops/

Strategy & operations workspace — the "founder's desk" of your devbox.

This folder is for thinking that lives above any single code project: long-term direction, portfolio decisions, quarterly objectives, monthly reviews. Claude Code opens a dedicated tmux window here so you can step out of code and into strategy without losing context.

Pre-loaded templates (open them, fill the placeholders, customise):

| File | Purpose |
|---|---|
| `PORTFOLIO.md` | Live snapshot of your projects + 12-month time-distribution thesis |
| `OKRs.md` | Current quarter's objectives + measurable key results |
| `ROADMAP.md` | 12-month outlook + Now/Next/Later for the current quarter |
| `FINANCIAL.md` | Revenue + cost per project, monthly headline |
| `monthly-review-template.md` | Copy to `reviews/YYYY-MM-review.md` at start of every month |
| `reviews/` | Archive of past monthly reviews. One file per month, never deleted |

All templates use `<placeholder>` style — open in Claude in the `stratops` session and ask Claude to walk through filling them with your real data. The tutorial's Beat 7 mentions this folder explicitly.

## Why a dedicated folder?

When code and strategy share the same window, strategy loses. A tmux window pinned to `stratops/` keeps the founder-brain accessible at all times without competing with implementation work.

If you don't need this, delete the folder. The tmux window will just open empty and you can repurpose it.
