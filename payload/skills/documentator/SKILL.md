---
name: documentator
description: Generates and updates technical documentation (CLAUDE.md/AGENTS.md, changelogs, API docs, architecture docs). Use when user explicitly asks to document code, generate a changelog, or update project documentation. NOT for writing code comments or docstrings.
allowed-tools: Read, Glob, Grep, Edit, Write
argument-hint: "[file|feature|changelog] [--update] [--full]"
disable-model-invocation: true
---

# Documentator

Generate and maintain documentation across the user's projects.

## Capabilities

1. **Feature Documentation**: Feature guides
2. **Changelog Updates**: CHANGELOG.md
3. **README Updates**: Keep README.md in sync
4. **API Documentation**: Endpoints and data flows
5. **Architecture Decisions**: ADRs

NOT in scope: inline comments, JSDoc, docstrings — unless explicitly requested.

## Documentation Standards

### Changelog Format
```markdown
## [Version] - YYYY-MM-DD

### Added
- New feature description

### Changed
- Modified behavior

### Fixed
- Bug fix description
```

## Workflow

1. Analyze `git diff` and recent commits
2. Identify undocumented changes
3. Write clear, concise documentation
4. Place in appropriate location
5. Update index files and cross-references

## Best Practices

- Be concise — documentation should be scannable
- Stay current — update docs with code changes
- Use examples — show, don't just tell
- Link related docs — cross-reference for context
- Follow project CLAUDE.md/AGENTS.md conventions
- No redundancy — don't repeat what's obvious from code
