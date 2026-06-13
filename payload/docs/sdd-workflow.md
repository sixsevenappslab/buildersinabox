# Spec-Driven Development (SDD) workflow

A lightweight framework for going from idea → spec → implementation → ship, while keeping enough structure to scale across multiple projects.

SDD ships with Builders in a Box in **two modes**:

- **Starter** — minimal. Three sections per spec. Good for solo work and side projects.
- **Full** — six sections, optional role-based ownership (Product / Tech / QA / Growth). Good for sustained work on multiple projects, especially when you want Claude Code to play different roles.

You can start in starter mode and graduate to full mode any time — same workflow, more depth.

## The basic loop

```
idea → FEAT spec (draft) → DoR validated → active → implementation → PR → completed
```

A **FEAT** (feature spec) is a single Markdown file living at `<project>/specs/draft/FEAT-NNN-slug.md`. As work progresses, the file moves between `draft/`, `active/`, and `completed/` folders. The file itself is the source of truth — there's no separate tracking system.

## Starter mode

Three sections, no roles, no overhead. See `payload/templates/FEAT-STARTER.md`.

```markdown
## Summary
## Tasks
## QA
```

That's it. Good for: side projects, solo work, learning the workflow.

## Full mode

Six sections plus metadata. See `payload/templates/FEAT-TEMPLATE.md`.

| Section | Purpose | Role |
|---|---|---|
| §0 Strategy | Why now, hypothesis, OKR alignment | Product Lead |
| §1 Product requirements | What it does, boundaries, acceptance | Product Lead |
| §2 Technical spec | Files, plan, risks, quality gates | Tech Lead |
| §3 Growth notes | KPIs, channels, tracking (optional) | Growth Lead |
| §4 QA | Functional + edge cases, regression, smoke | QA Lead |
| §5 Docs | Post-merge documentation checklist | Tech Lead |
| §6 Feedback | Retrospective, filled after shipping | Product Lead |

### Optional: personas

Builders in a Box ships with default persona names (Elena/Laura/Pablo/Andrea for Product/Tech/QA/Growth). You can:

1. **Use them as-is** — Claude Code will adopt the persona's name and tone when filling that section.
2. **Rename them** — edit `~/.claude/sdd-config.json` to use whatever names you want.
3. **Disable them** — set `mode: starter` and the skills use plain role names.

See `payload/config/sdd-config.example.json` for the schema.

## Lifecycle: draft → active → completed

| Folder | What lives here |
|---|---|
| `specs/draft/` | FEAT proposals not yet validated. Coordinator can iterate here freely. |
| `specs/active/` | FEATs that passed Definition of Ready (DoR) and are being implemented. |
| `specs/completed/` | Shipped FEATs, kept for history and §6 feedback. |
| `specs/feedback/` | (Optional) standalone retrospectives that cross multiple FEATs. |
| `specs/planned/` | (Optional) roadmap-future FEATs, not yet ready to spec. |

**Definition of Ready (DoR):** for a FEAT to move from `draft/` to `active/`, the owner confirms that §0, §1, and §2 are filled in (and §4 has at least functional cases). §3 and §5 can be empty if not applicable.

## Tooling: the SDD skills

Builders in a Box bundles these skills (see `payload/skills/`):

- `sdd-coordinator` — Product Lead. Creates new FEATs, fills §0/§1, validates DoR, moves files between lifecycle folders.
- `sdd-spec-writer` — Tech Lead. Researches the codebase and fills §2.
- `sdd-qa` — QA Lead. Fills §4.
- `sdd-growth` — Growth Lead. Fills §3 when applicable.
- `sdd-docs` — Tech Lead voice. Plans §5 post-merge actions.
- `spec-implementer` — End-to-end pipeline: reads a FEAT in `active/`, implements it, opens a PR, optionally deploys.
- `spec-cleanup` — Interactive triage of stale drafts.
- `spec-triage` — Cross-project audit of FEAT health.

You don't need to use all of them. A minimal flow is `sdd-coordinator` → human implements → done.

## Three modes of work

Not every change needs a full FEAT. Pick the right tier:

| Mode | When | Process |
|---|---|---|
| **Direct** | Hotfixes, simple bugs, < 2h changes | Fix → PR → review → merge |
| **Spec-light** | Small features with business logic | `sdd-coordinator` writes a minimal FEAT → implement → PR |
| **Full SDD** | Medium/large features, architectural changes | Coordinator + spec-writer + QA + (Growth) → DoR → spec-implementer → PR → review |

## Adopting SDD on your devbox

See [`adopting-sdd.md`](adopting-sdd.md) for the first-time setup guide.
