# skills/

AI CLI skills bundled with a Builders in a Box devbox. Installed to
`~/.agents/skills/<name>/` on first boot (the source of truth), with a
symlink into each CLI's native skills dir — `~/.claude/skills/<name>` for
Claude Code, and `~/.gemini/skills/<name>`, `~/.gemini/antigravity-cli/skills/<name>`
and `~/.gemini/config/skills/<name>` for Antigravity CLI — so each CLI finds them.

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
- `spec-implementer` — Implements a validated FEAT wave by wave in a dedicated git
  worktree, runs quality gates, writes progress into the PR body, opens the PR with
  `gh`, and hands off to `pr-review` (stops at the PR by default).
- `pr-review` — Coordinates a size-matched review of an open PR (code, QA, growth,
  security) and reports a structured verdict before the owner merges.

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
- `deploy-verify` — Post-deployment verification checklist: logs, endpoints, smoke tests.
- `no-ai-slop` — Edits a draft to sound human without flattening the author's voice,
  or detects AI-writing patterns without rewriting.

### Onboarding & box operations (core)
- `welcome` — First-session greeting and quick tour of the devbox.
- `tutorial` — Guided post-install walkthrough (GitHub auth, workspace tour, next steps).
- `first-project` — End-to-end guide from project template or custom idea to spec, branch, and first PR.
- `second-project` — Scaffolds a second project (including cloud-backed templates).
- `whats-ahead` — Suggests the next milestone based on your current project progress.
- `morning-check` — Quick health and status check across your projects and services.
- `quota` — Reconstructs subscription usage (`quota_report.py`) and rolling 5-hour window pace (`quota_watchdog.py`) from local transcripts.
- `extend-yourself` — Guides you through adding custom skills, hooks, or systemd timers on the box.

### Optional skills (install with `biab add`)
Shipped in the repo but not installed by default:
- `incident` — Logs operational incidents as ERR-NNN entries with a fixed template.
- `debugging` — Production debugging guide: logs, Docker diagnostics, DB queries.
- `deploy-ops` — Deployment reference card: Docker, Firebase, PM2, rollbacks
  (pairs with the core `deploy-verify`).
- `docker-ops` — Docker container management: status, logs, rebuilds, cleanup.
- `pm2-ops` — PM2 process management for Node.js services.
- `spec-cleanup` — Interactive triage of a project's accumulated spec drafts.
- `wireframe-generator` — Wireframes/mockups via the Gemini image API
  (bring your own `GEMINI_API_KEY`).
- `hotfix` — Emergency hotfix workflow for production bugs without a full FEAT spec
  (stops at the PR; rollback with `git revert`).
- `fact-checker` — Claim-by-claim verification of a draft against primary sources,
  returning a structured verdict table.
- `verify-frontend-change` — End-to-end browser verification of UI changes using
  `biab-browse` (when the browser pack is installed) or a connected browser tool.
- **Group `handover` (`biab add handover`)** — Cross-session and cross-CLI task
  continuity:
  - `agent-handover` — Shared repository-aware handover backend (`scripts/handover.py`)
    with automatic carry-forward of unresolved Blockers/Pending and claim/commit locking.
  - `wrapup` — Saves a structured handover before pausing or switching coding agents.
  - `unwrap` — Resumes work by reconciling saved handovers and active workspace sessions.
- **Group `marketing` (`biab add marketing`)** — 19 vendored MIT marketing skills from
  `coreyhaines31/marketingskills` (pinned in `marketingskills.lock.json`, MIT notice in
  `LICENSE.marketingskills` and inside each skill directory; opt-in so their ~13.5k
  characters of frontmatter descriptions do not weigh down default sessions; ~25 prose
  pointers to unshipped upstream siblings such as `emails` or `competitors` are skipped
  by the agent):
  - `marketing-context` (renamed from upstream `product-marketing` to avoid colliding
    with BIAB's core `product-marketing` advisor persona; maintains `.agents/product-marketing.md`),
    `customer-research`, `analytics`, `attribution`, `cro`, `programmatic-seo`, `schema`,
    `marketing-loops`, `ab-testing`, `ads`, `ai-seo`, `content-strategy`, `copywriting`,
    `marketing-ideas`, `onboarding`, `popups`, `revops`, `seo-audit`, `signup`.

## The first project

`/first-project` takes one idea from a template (or the user's own) to a written
spec, an implementation on a branch and a pull request, using the `sdd-*` skills
above. The catalogue it offers is `payload/templates/projects/manifest.tsv`; the
script behind it is `payload/scripts/biab-project`. Add a template by adding a
directory and one manifest line. `/second-project` reaches the templates that
need a cloud account by name.

## How to invoke a skill

Type `/skill-name` in any agent session running Claude Code or Antigravity CLI (Codex: `$skill-name`).
Example: `/sdd-coordinator I want to add bulk export to my app`.

To see what's available at any time, type `/skills` (Antigravity) or
just `/` and start typing (Claude Code shows matches).

## Adding your own

Drop a folder under `~/.agents/skills/<your-skill>/` containing a `SKILL.md`
with frontmatter (`name`, `description`). Both CLIs pick it up immediately.
See `sdd-base/SKILL.md` for a working example.
