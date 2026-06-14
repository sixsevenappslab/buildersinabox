# Specs lifecycle

Each project on a Builders in a Box devbox follows the same folder convention for specs. This document is the canon — bend it only when you have a specific reason.

## Canonical structure

```
<project-name>/
├── specs/
│   ├── draft/         # FEATs not yet ready to implement
│   ├── active/        # FEATs being implemented now
│   ├── completed/     # Shipped FEATs
│   └── feedback/      # (Optional) cross-FEAT retrospectives
└── ...
```

## Optional folders

| Folder | When to use |
|---|---|
| `planned/` | Future ideas that aren't ready to spec yet. Roadmap-level. |
| `assets/` | Diagrams, mockups, screenshots referenced by FEATs. |
| `tests/` | Test plans that span multiple FEATs. |

If you don't need them, don't create them. Empty folders are clutter.

## What we explicitly avoid

- `discarded/`, `archived/`, `pending/`, `rejected/` — these overlap with `completed/` (treat dead FEATs as completed-but-not-shipped) or `draft/` (still in flux). One folder per state, no synonyms.
- Numbered subfolders (`v1/`, `v2/`). Use FEAT IDs and git history.
- Per-author subfolders. The FEAT metadata says who owns it.

## Naming convention

```
FEAT-NNN-short-slug.md
```

- `NNN` — zero-padded three-digit number, increments globally per project.
- `slug` — lowercase, kebab-case, 2-5 words, descriptive.
- Examples: `FEAT-012-pdf-export.md`, `FEAT-047-multi-tenant-billing.md`

Avoid: dates in filenames (metadata holds those), author initials, emoji.

## Lifecycle transitions

```
draft/ ──DoR pass──▶ active/ ──merged──▶ completed/
   │                     │
   └── too stale ────────┴─▶ deleted (or kept in completed/ with status: dropped)
```

**DoR (Definition of Ready)** — the FEAT can move from draft to active when:
- §0 Strategy is filled (you can articulate *why*).
- §1 Product requirements is filled with boundaries.
- §2 Technical spec exists (even if rough).
- §4 QA has at least functional acceptance criteria.
- Owner has signed off (`validated_by` field).

**Going stale** — if a draft sits untouched for >45 days, run `spec-cleanup` to triage it (archive, delete, or promote).

## Multi-project view

If you keep several projects under one workspace (the typical Builders in a Box setup), you can run `spec-triage` to get a cross-project view of FEAT health: drafts per project, average age, stalled work.
