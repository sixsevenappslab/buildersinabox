# skills/

Claude Code skills bundled with a Builders in a Box devbox. Installed to `~/.claude/skills/` on first boot.

## What's in here (planned)

### Spec-Driven Development workflow
- `sdd-base` — foundational workflow doc, no commands of its own
- `sdd-coordinator` — Product Lead voice; creates FEATs, validates DoR, manages lifecycle
- `sdd-spec-writer` — Tech Lead voice; fills §2 Technical spec
- `sdd-qa` — QA Lead voice; fills §4 QA
- `sdd-growth` — Growth Lead voice; fills §3 Growth notes (when applicable)
- `sdd-docs` — Plans §5 post-merge documentation
- `spec-implementer` — End-to-end pipeline: reads active FEAT, implements, opens PR
- `spec-cleanup` — Interactive triage of stale drafts
- `spec-triage` — Cross-project audit of FEAT health

### Code quality & review
- `code-review` — Reviews current diff for bugs, posts inline PR comments
- `pr-review` — Multi-role PR review coordination
- `code-simplifier` — Refines recently modified code for clarity
- `qa-testing` — Test plan creation, structured bug reports
- `documentator` — Generates/updates technical docs (CLAUDE.md, changelogs, API docs)

### Claude Code utilities
- `update-config` — Manages Claude Code settings.json
- `keybindings-help` — Customizes keyboard shortcuts
- `fewer-permission-prompts` — Adds common read-only commands to allowlist

## Status

🚧 **All skills are pending refactor for public release.** The originals live in the maintainer's `~/.claude/skills/` but contain hardcoded references to specific projects, deploy targets, and Slack integrations. The public versions will:

- Read project lists from `~/.claude/projects.yaml` instead of hardcoded arrays
- Use `~/.claude/sdd-config.json` for persona names (with sensible defaults)
- Strip references to private services (specific Firebase projects, Slack workspaces, etc.)

Track refactor progress in the repo's issues.
