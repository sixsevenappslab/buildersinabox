# skills/

AI CLI skills bundled with a Builders in a Box devbox. Installed to
`~/.agents/skills/<name>/` on first boot (the source of truth), with a
symlink into each CLI's native skills dir — `~/.claude/skills/<name>` for
Claude Code, `~/.gemini/skills/<name>` for Antigravity CLI — so both find them.

## What's in this v1 bundle

### Spec-Driven Development workflow
- `sdd-base` — foundational workflow doc and entry point. Defines what a FEAT is,
  the lifecycle (draft → active → completed), and the four roles.
- `sdd-coordinator` — Product Lead voice. Creates FEATs, fills §1 Requirements + §3
  Boundaries, validates Definition of Ready, manages lifecycle transitions.
- `sdd-spec-writer` — Tech Lead voice. Researches the codebase and fills §2 Technical spec.
- `sdd-qa` — QA Lead voice. Fills §4 QA: functional cases, edge cases, regression plan.
- `sdd-growth` — Growth Lead voice. Fills §3 Growth Notes when the FEAT has growth surface.
- `sdd-docs` — Plans §5 post-merge documentation actions (CLAUDE.md, runbooks, changelog).

### Consultants (expert advice on demand)
- `backend-engineer` — Senior Backend Engineer consultant. Architecture, performance,
  API design, security.
- `ui-ux-consultant` — UI/UX Consultant. Usability, accessibility, design systems.
- `executive` — Executive / CPO. Strategy, prioritization, cross-functional alignment.
- `product-marketing` — Product Marketing Manager. Growth, conversion, positioning.

### Code quality & process
- `code-review` — Structured review of the current diff at a chosen effort level.
- `code-simplifier` — Refines recently modified code for clarity and consistency.
- `qa-testing` — Test plan creation, structured bug reports, regression checklist.
- `documentator` — Generates/updates technical docs (CLAUDE.md, changelogs, API docs).
- `ux-review` — Mobile-first UX/UI evaluation criteria.

## Coming in a later update

The following skills exist in the maintainer's setup but still need work to
strip personalization before shipping: `spec-implementer`, `pr-review`,
`debugging`, and `spec-cleanup`. They will arrive in a follow-up release.

## How to invoke a skill

Type `/skill-name` inside any tmux window running Claude Code or Antigravity CLI.
Example: `/sdd-coordinator I want to add bulk export to my app`.

To see what's available at any time, type `/skills` (Antigravity) or
just `/` and start typing (Claude Code shows matches).

## Adding your own

Drop a folder under `~/.agents/skills/<your-skill>/` containing a `SKILL.md`
with frontmatter (`name`, `description`). Both CLIs pick it up immediately.
See `sdd-base/SKILL.md` for a working example.
