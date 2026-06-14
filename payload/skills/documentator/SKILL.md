---
name: documentator
description: Generates and updates technical documentation (CLAUDE.md, changelogs, API docs, architecture docs). Use when user explicitly asks to document code, generate a changelog, or update project documentation. NOT for writing code comments or docstrings.
allowed-tools: Read, Glob, Grep, Edit, Write
argument-hint: [file|feature|changelog] [--update] [--full]
---

# Documentator

Generate and maintain documentation across SixSeven Apps projects.

## Capabilities

1. **Code Documentation**: Inline comments, JSDoc, Python docstrings
2. **Feature Documentation**: Feature guides
3. **Changelog Updates**: CHANGELOG.md
4. **README Updates**: Keep README.md in sync
5. **API Documentation**: Endpoints and data flows
6. **Architecture Decisions**: ADRs

## Documentation Standards

### JavaScript (ES6 Modules)
```javascript
/**
 * Brief description of function purpose.
 * @param {Object} params - Parameter description
 * @returns {Object} Return description
 */
function functionName(params) {
```

### Python
```python
def function_name(request: Request) -> Response:
    """
    Brief description.

    Args:
        request: Description with expected body fields

    Returns:
        Description of return value
    """
```

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
- Follow project CLAUDE.md conventions
- No redundancy — don't repeat what's obvious from code
