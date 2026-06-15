---
name: sdd-base
description: Spec-Driven Development — base workflow for Claude Code. One FEAT-NNN document per feature, lifecycle draft → active → completed. Two modes (starter / full). Invoked directly or through the specialized skills sdd-coordinator / sdd-spec-writer / sdd-qa / sdd-growth / sdd-docs.
---

# Spec-Driven Development (SDD) — Base

A lightweight framework for going from idea → spec → implementation → ship, using a single Markdown file per feature as the source of truth.

This skill describes the **base workflow** that every other SDD skill builds on. Read this first when in doubt.

## Two modes

SDD ships in two flavors. Pick the one that matches the size of the work and the user's preference.

| Mode | Sections | Template | Use it when |
|------|----------|----------|-------------|
| **Starter** | 3 (Summary / Tasks / QA) | `templates/FEAT-STARTER.md` | Solo work, side projects, learning the rhythm |
| **Full** | 6 (§0 Strategy → §6 Feedback) | `templates/FEAT-TEMPLATE.md` | Multiple projects, role-based work, sustained development |

The mode is set in `~/.claude/sdd-config.json` (`"mode": "starter"` or `"mode": "full"`). If the config file is missing, default to **starter** — the gentler entry point for first-time users. The example config in `config/sdd-config.example.json` ships with `"mode": "full"` to illustrate the full schema; that's a starting point for customization, not the implicit default.

## Configuration

Two optional config files drive this workflow. Read them before doing anything project-specific.

### `~/.claude/sdd-config.json`

Defines the mode, persona names, and lifecycle folder names. Example schema lives at `config/sdd-config.example.json` in this payload. The relevant fields:

- `mode` — `starter` or `full`.
- `personas` — names + titles + tones for the four roles (product / tech / qa / growth). Renaming them changes how the specialized skills introduce themselves and sign sections. Defaults are Elena (Product Lead), Laura (Tech Lead), Pablo (QA Lead), Andrea (Growth Lead) — but every project is free to rename them. Refer to roles by their *title* in user-facing prose, and only use the configured `name` when speaking in voice.
- `specs_root` — folder name inside each project that holds the specs tree. Default: `specs`.
- `feat_prefix` — file prefix. Default: `FEAT`.
- `lifecycle_folders` — canonical list: `["draft", "active", "completed", "feedback"]`.
- `optional_folders` — e.g. `["planned"]`.

If the file is missing, fall back to all defaults.

### `~/.claude/projects.yaml`

Lists the projects that SDD-aware skills should know about. Schema example at `config/projects.example.yaml`. Each entry can specify `path`, `type`, `base_branch`, `deploy_cmd`, `specs_root`, and `quality_gates`.

If the file is missing, **auto-discover** projects by scanning `$BUILDERSINABOX_ROOT/projects/*/` (default root: `~/ai-platform`) and treating any folder that contains a `specs/` subdirectory as a project. Override the root via the `BUILDERSINABOX_ROOT` environment variable.

Never hardcode project names in skill logic. Always resolve them through `projects.yaml` or auto-discovery.

## The unified FEAT document

One file replaces every previous PRD / SPEC / QA / STATE / FEEDBACK split. It lives at:

```
<project>/<specs_root>/<lifecycle>/<feat_prefix>-NNN-<slug>.md
```

For example: `~/ai-platform/projects/my-app/specs/draft/FEAT-012-pdf-export.md`.

### Full-mode structure

| Section | Owner role | Contents |
|---------|-----------|----------|
| §0 Strategy | Product Lead | Why now, hypothesis, OKR alignment, cost of inaction |
| §1 Product requirements | Product Lead | What it does, user stories, Boundaries (Always / Ask first / Never), acceptance criteria |
| §2 Technical spec | Tech Lead | Research, files touched, dependencies, risks, implementation plan in waves, quality gates |
| §3 Growth notes | Growth Lead *(optional)* | KPIs, channels, UTMs, experiments, SEO, analytics |
| §4 QA | QA Lead | Functional cases, edge cases, regression plan, smoke tests post-deploy |
| §5 Docs | Tech Lead | Post-merge documentation checklist (CLAUDE.md, changelog, runbooks, etc.) |
| §6 Feedback | Product Lead | Filled after shipping — surprises, follow-ups, links to incidents |

### Starter-mode structure

```
## Summary
## Tasks
## QA
```

Same lifecycle, same file naming, same numbering — just fewer sections.

### Boundaries (always part of §1 in full mode)

Every full FEAT lists explicit Boundaries:

- **Always** — behaviors that must happen.
- **Ask first** — ambiguous decisions that need user confirmation before being made.
- **Never** — things explicitly out of scope. Useful to stop scope creep mid-implementation.

## Lifecycle

```
draft/ ──DoR pass──▶ active/ ──merged + deployed──▶ completed/
   │                     │
   └── stale (>45d) ─────┴─▶ manual cleanup (archive / drop / promote)
```

| Folder | What lives here |
|--------|------------------|
| `draft/` | FEATs in requirements / spec / QA, before DoR validation |
| `active/` | FEATs that passed DoR and are being implemented |
| `completed/` | Shipped FEATs, kept for history and §6 feedback |
| `feedback/` | Standalone retrospectives spanning multiple FEATs |
| `planned/` *(optional)* | Roadmap-level future ideas, not yet ready to spec |

### Definition of Ready (DoR)

A FEAT can move from `draft/` to `active/` when:

- §0 Strategy is filled (or, in starter mode, Summary is non-trivial).
- §1 Product requirements has at least one acceptance criterion and explicit Boundaries.
- §2 Technical spec exists, even if rough.
- §4 QA lists at least the functional acceptance criteria.
- The owner has signed off via the `validated_by` field in the FEAT's frontmatter.

§3 Growth and §5 Docs can be empty if they don't apply.

## Numbering

Before creating a new FEAT, look up the highest existing number across both `draft/` and `completed/`:

```bash
ls "$PROJECT_PATH/$SPECS_ROOT/draft/$FEAT_PREFIX-"* \
   "$PROJECT_PATH/$SPECS_ROOT/active/$FEAT_PREFIX-"* \
   "$PROJECT_PATH/$SPECS_ROOT/completed/$FEAT_PREFIX-"* 2>/dev/null
```

Use the next available zero-padded three-digit number. If no FEATs exist yet, start at `001`.

Numbering is **per project** — `FEAT-012` in project A is unrelated to `FEAT-012` in project B.

## Naming convention

```
<FEAT_PREFIX>-NNN-<slug>.md
```

- `NNN` — zero-padded, three digits.
- `slug` — lowercase, kebab-case, 2–5 words, descriptive.
- Examples: `FEAT-012-pdf-export.md`, `FEAT-047-multi-tenant-billing.md`.

Avoid dates in filenames, author initials, or emoji — metadata holds that.

Standalone growth analyses (rare, only when the work isn't a single FEAT) can use a separate `GROWTH-NNN-<slug>.md` prefix.

## Three tiers of work

Not every change needs a full FEAT. Pick the right tier up front.

| Tier | When | Process |
|------|------|---------|
| **Direct** | Hotfixes, simple bugs, < 2h changes | Fix → PR with clear description → CI → `/code-review` → merge |
| **Spec-light** | Small features with business logic | `sdd-coordinator` creates a minimal FEAT → implement → PR → review |
| **Full SDD** | Medium/large features, architectural changes | `sdd-coordinator` orchestrates `sdd-spec-writer` + `sdd-qa` (+ `sdd-growth` if applicable) → DoR → validation → implement → PR → `/code-review` |

When unsure, ask the user which tier applies before writing anything.

## Specialized skills

This skill is the foundation. Specialized skills handle individual sections:

- `sdd-coordinator` — Product Lead voice. Creates FEATs, fills §0 + §1, validates DoR, manages lifecycle transitions.
- `sdd-spec-writer` — Tech Lead voice. Researches the codebase and fills §2.
- `sdd-qa` — QA Lead voice. Fills §4.
- `sdd-growth` — Growth Lead voice. Fills §3 when the feature has a growth/marketing surface.
- `sdd-docs` — Plans §5 post-merge documentation actions.

You don't need all of them. A minimal flow is `sdd-coordinator` → you implement against the spec → `/code-review` → done. Implementation, PR review, and stale-draft cleanup are done by you in-session here (with `/code-review` for reviews); there's no background automation in this bundle.

## Implementation plan: waves

In §2 of full-mode FEATs, the Tech Lead breaks the work into **waves** — ordered groups of tasks where each wave is independently reviewable.

```
Wave 1 — foundations (data model, contracts)
Wave 2 — happy-path logic
Wave 3 — edge cases + error handling
Wave 4 — observability + tests
```

Waves let you checkpoint progress and intervene between waves if something looks off.

## Quality gates

Every full FEAT lists explicit quality gates inside §2. Common ones:

- [ ] Tests pass
- [ ] Lint / static analysis passes
- [ ] No secrets in commits
- [ ] Scope stays inside the §1 Boundaries
- [ ] Project-specific gates from `projects.yaml` (`quality_gates` field)

Quality gates run **before opening the PR**, not after.

## Rules

- The Product Lead role coordinates the FEAT end-to-end but **never writes technical specs or production code**.
- The Tech Lead role owns §2 and implementation but **never writes business requirements**.
- The QA Lead role owns §4 and can read code / PRs to design tests.
- The Growth Lead role only participates when the FEAT has a growth, SEO, or marketing surface.
- Each role only modifies its own section + the `status` and `validated_by` fields in frontmatter.
- Implementation does **not** start until DoR is signed off (`validated_by` set, all required sections filled).
- A FEAT only moves to `completed/` after the PR is merged **and** the change is verified in the target environment.
- Never commit `.env`, credentials, tokens, or API keys.
- Persona names are configurable — refer to roles by their **title** in cross-role prose, and use the configured **name** only when speaking in that role's voice.
