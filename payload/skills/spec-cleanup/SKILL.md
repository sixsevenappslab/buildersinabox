---
name: spec-cleanup
description: Interactive cleanup of a project's accumulated spec drafts. Lists each draft with its age, asks one binary question per draft (archive / keep / promote), applies the decisions, and writes a local HTML report. Use when the user wants to triage the drafts of one specific project.
---

# Spec Cleanup

Triage accumulated drafts of ONE project at a time. This skill focuses on
**live drafts** in `specs/draft/` that need a decision: archive, keep, or
promote to active.

## When to invoke

- The user says things like "clean up the drafts of my-app", "review the specs
  in my-app", "what do I do with the drafts of X".
- The user passes the project name as an argument, or you detect it from the
  current working directory.

## Flow

### 1. Detect the project

If the user didn't name a project:
- If the cwd is inside `~/ai-platform/projects/<X>/`, use `<X>`.
- Otherwise, ask the user which project (list the candidates: any folder under
  `~/ai-platform/projects/` that contains a `specs/` subdirectory).

### 2. List drafts with metadata

```bash
ls -lt ~/ai-platform/projects/<project>/specs/draft/ 2>/dev/null
```

For each draft compute:
- File name
- Days since last mtime (today - mtime)
- Size in lines
- Zombie flag: >45 days old
- Warning flag: 30-45 days old

### 3. Initial summary

Before asking any questions, show:
- How many drafts there are
- How many zombies / warnings / fresh
- A short list with tags

### 4. Binary decisions, one at a time

For each draft, **read its opening sections** (roughly `head -50`: problem
statement, goal) and ask the user one question with 3 options:

- **Archive** — `mv` to `_archive/` (create it if missing). Frees the slot.
- **Keep in draft** — don't touch. Useful if the user hasn't decided yet.
- **Promote to active** — `mv` to `active/`. Implies implementation starts soon.

If the user says "you decide" or asks for your opinion, **read the spec more
deeply** and evaluate against:
- Is there a project roadmap in its context file (CLAUDE.md / AGENTS.md)? Respect it.
- Is it blocked by another FEAT? If the dependency doesn't exist, archive or keep.
- Is it bloat (another spec already covers the case)? Archive.
- Older than 45 days with no clear reason → archive.
- Freshly edited + active roadmap → keep or promote.

Give a reasoned decision (3-5 lines) and apply it unless the user disagrees.

### 5. Apply decisions

- **Archive**: `mkdir -p .../specs/_archive/ && mv .../specs/draft/<file> .../specs/_archive/`
- **Keep**: nothing. Optionally add a dated review note to the spec (helps future-you).
- **Promote**: `mv .../specs/draft/<file> .../specs/active/`

Do NOT commit automatically. At the end, show `git status` and propose a batch commit.

### 6. Generate the report

At the end of the cleanup, write a **self-contained HTML file** to
`~/spec-cleanup-<project>-<YYYY-MM-DD>.html` with:

- Before/after summary: draft counts, net changes.
- Table of decisions taken, with the reason for each.
- List of the resulting active specs.
- Suggested next actions (pending implementation, dependencies, etc.).
- No complex SVG — tables and badges with inline CSS.

HTML style: monospace or sans-serif, dark dashboard theme. Semantic colors
(red archived, green active, yellow kept in draft). If the user prefers plain
text, offer a markdown file instead.

## Conventions

- Do NOT create extra documentation (README, etc.) beyond the report file.
- Do NOT refactor specs — only move them; never edit content except an explicit review note.
- Do NOT commit automatically. Always show the batch to the user for approval.
- If you find keys/secrets in a spec while reading, alert the user immediately
  and do NOT continue with that draft until resolved.

## Example output (final chat summary)

```
Cleanup my-app done:
- Before: 9 drafts
- After: 5 drafts, 1 promoted to active, 3 archived
- Report: ~/spec-cleanup-my-app-2026-05-10.html

Suggested next actions:
1. Proposed batch commit (show the command)
2. Start implementing FEAT-XXX (just promoted)
```
