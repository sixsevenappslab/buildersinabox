# {{WORKSPACE_NAME}}

Workspace-level instructions for Claude Code on this Builders in a Box devbox.

## Layout

- `projects/` — one folder per project. Each has its own `CLAUDE.md`.
- `stratops/` — strategy & operations workspace (OKRs, roadmap, decisions, reviews).

## Conventions

- **Specs:** Every project uses the [Spec-Driven Development workflow](../../buildersinabox/payload/docs/sdd-workflow.md). See `payload/docs/specs-lifecycle.md` for the canonical folder structure.
- **Quality gates:** PR required for non-trivial changes. CI green before merge.
- **Code style:** Each project's `CLAUDE.md` defines its own conventions.

## Aliases (edit to your taste)

When you create projects, you can register short aliases here so Claude Code knows where to look:

```
- "myapp" = ~/ai-platform/projects/myapp
```

## Global preferences

Examples — edit, remove, or expand:

- Language: write code comments in English, conversation in your preferred language.
- Git: prefer small, frequent commits.
- Never commit `.env`, credentials, tokens, or API keys.
