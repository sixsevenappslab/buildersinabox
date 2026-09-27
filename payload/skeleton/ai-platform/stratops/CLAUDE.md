# stratops/

The founder's desk of this devbox. Strategy and operations live here — the thinking that sits above any single code project.

## What lives here

- **`PORTFOLIO.md`** — live snapshot of active projects + 12-month time-distribution thesis
- **`OKRs.md`** — current quarter's objectives + measurable key results
- **`ROADMAP.md`** — 12-month outlook + Now/Next/Later for the current quarter
- **`FINANCIAL.md`** — revenue + cost per project, monthly headline
- **`monthly-review-template.md`** — copy to `reviews/YYYY-MM-review.md` at the start of each month
- **`reviews/`** — archive of past monthly reviews, one file per month, never deleted
- **`brain-dump.jsonl`** — append-only ideas captured via the `bd` CLI from any terminal

## How Claude should help here

When the user opens a Claude session in this folder, the context is **strategic, not tactical**. Default behaviour:

- Help fill in the templates with the user's real data when asked. Ask clarifying questions before writing — these documents reflect the user's actual situation, not generic best-practice.
- When the user shares an idea, propose where it belongs: a project's `specs/draft/` (if it's a buildable thing), this folder's `ROADMAP.md` Later section (if it's a direction), or a one-line `bd` entry (if it's still vague).
- When asked to triage `brain-dump.jsonl`, sort each unprocessed entry into one of: project-idea (with a suggested target project), todo (date-tagged action), or noise (delete). Mark `processed: true` and add a one-line `triage_notes`.
- Avoid jumping into code. If a strategic question shades into a coding question, suggest the user switch to the relevant project's tmux session (CLAUDE.md context is different there).

## Conventions

- Markdown only. No JSON / YAML config files in this folder — they live in projects/.
- Decisions worth keeping go in `reviews/<YYYY-MM-DD>-<slug>.md`. One decision per file. Never edit historical decisions; supersede with a new one and link both ways.
- Filenames in kebab-case-or-underscore-no-spaces.
- Dates in ISO format (`2026-05-29`), never `29/05/2026`.

## What does NOT live here

- Code (any of it). If you find yourself writing code in stratops, you're in the wrong session — open `tmuxc <project> ~/ai-platform/projects/<project>`.
- Project-specific specs. Those go in `~/ai-platform/projects/<name>/specs/`.
- Secrets / `.env` files. Ever.
