# {{PROJECT_NAME}}

Project-level instructions for Claude Code.

## Overview

One-paragraph description of what this project is and who it's for.

## Tech stack

- Language: ...
- Framework: ...
- Key dependencies: ...

## Development workflow

This project follows the [Spec-Driven Development workflow](../../docs/sdd-workflow.md).

- **Specs root:** `specs/`
- **Lifecycle:** `draft/` → `active/` → `completed/`
- **FEAT template:** see `payload/templates/FEAT-TEMPLATE.md` (full) or `FEAT-STARTER.md` (lightweight)

| Mode | When | Process |
|------|------|---------|
| **Direct** | Hotfixes, simple bugs, changes < 2h | Fix → PR → CI → review → merge |
| **Spec-light** | Small features with business logic | Coordinator creates minimal FEAT → implement → PR → review |
| **Full SDD** | Medium/large features, architectural changes | Coordinator orchestrates Tech / QA / Growth → DoR → validate → spec-implementer → PR → review |

## Quality gates

- PR required for all changes — no direct pushes to `main`.
- CI must pass — tests + lint before merge.
- QA review required for changes to business logic.
- Owner approves and merges.

## Code conventions

- Logging: ...
- Async: ...
- Error handling: ...
- Imports: stdlib → third-party → local.

## Common commands

```bash
# Run dev server
...

# Run tests
...

# Lint
...
```

## Danger zones

Files/areas that require extra caution. Run existing tests as baseline before editing.

- `path/to/sensitive/file` — why it's sensitive

## Out of scope

Things this project explicitly does NOT do. Add boundaries here as you discover them.
