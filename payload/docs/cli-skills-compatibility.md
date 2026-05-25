# CLI skills compatibility: Claude Code ↔ Gemini CLI

> Wave 0 deliverable of FEAT-001. Determines whether the bundled SDD skills can be shipped under `~/.agents/skills/` and consumed identically by both AI CLIs supported in v1.

**Status:** Research complete. Empirical validation pending (see [Empirical test](#empirical-test) below).

**Date:** 2026-05-25.

## TL;DR

The skill format **is drop-in compatible** between Claude Code and Gemini CLI at the file/directory level. Both look in `~/.agents/skills/` (the documented cross-CLI alias), both expect a `SKILL.md` with `name` and `description` frontmatter, both add the body to the conversation when the skill activates.

The bundled `payload/skills/sdd-base/SKILL.md` is generic (roles by title, persona names configurable, no hardcoded project paths) and ships safely to both CLIs.

**One caveat** (non-blocking, but worth fixing in a follow-up): the bundled SKILL.md references `~/.claude/sdd-config.json` as the optional config location. For Gemini users that path doesn't exist. The skill correctly falls back to defaults if the file is missing, so Gemini users get a usable workflow but lose configurability. Recommendation: move the config to `~/.config/sdd/config.json` (XDG-compliant, CLI-agnostic). Tracked as follow-up, not a Wave 0 blocker.

## Research findings (paper)

### Discovery locations

| CLI | Searched paths (precedence high → low) |
|-----|----------------------------------------|
| Claude Code | `.claude/skills/` (workspace) → `~/.claude/skills/` (user) → built-in |
| Gemini CLI | `.gemini/skills/` or `.agents/skills/` (workspace) → `~/.gemini/skills/` or `~/.agents/skills/` (user) → extension skills → built-in |

The `~/.agents/skills/` and `.agents/skills/` aliases are explicitly documented in [Gemini CLI's skills docs](https://geminicli.com/docs/cli/skills/) and are also recognised by Claude Code via the same alias convention. **Conclusion: install bundled skills to `~/.agents/skills/` for cross-CLI access.**

### Required file layout

Both CLIs require:

```
<skills-root>/<skill-name>/
└── SKILL.md          # frontmatter + body
   (+ any supporting assets, scripts, templates)
```

### Frontmatter

Both CLIs read `name` and `description` from YAML frontmatter at the top of `SKILL.md`. The bundled skill already conforms:

```yaml
---
name: sdd-base
description: Spec-Driven Development — base workflow for Claude Code. ...
---
```

The text `for Claude Code` in the description is misleading once we ship to Gemini too. Consider rewording to `for AI coding CLIs` or simply omitting the CLI reference. Minor wording fix, not a compatibility blocker.

### Activation behavior

Per Gemini's docs: *"When a skill activates, the `SKILL.md` body and folder structure is added to the conversation history."*

Claude Code behaves the same way (the skill body is injected into the system prompt when the model decides the user's request matches the skill description).

**Implication for content writing:** the SKILL.md body should be **self-contained**. It cannot assume access to other skills, external services, or files outside its own folder unless those references are themselves portable.

## What we ship in v1

| File | Status |
|------|--------|
| `payload/skills/sdd-base/SKILL.md` | ✅ Generic — roles by title, no Elena/Laura/Pablo hardcoded, no specific project paths. Ships as-is. |
| `payload/templates/FEAT-TEMPLATE.md` | ✅ Generic — `Owner: Product Lead`, etc. Ships as-is. |
| `payload/templates/FEAT-STARTER.md` | ✅ Generic. Ships as-is. |
| `payload/skills/sdd-coordinator/` | 🚧 Not yet written. Generic version needed before v1 ships. |
| `payload/skills/sdd-spec-writer/` | 🚧 Same. |
| `payload/skills/sdd-qa/` | 🚧 Same. |
| `payload/skills/sdd-growth/` | 🚧 Same. |
| `payload/skills/sdd-docs/` | 🚧 Same. |

The bundled `~/.claude/skills/sdd-base/SKILL.md` on the developer host (Jesus's personal Claude install) is **not** a candidate for shipping — it references his personal agent personas (Elena/Laura/Pablo/Andrea), virtualdev.company email domain, hardcoded project paths (Sofi/Ganga24/Chordna/Hezu). Treat it as developer scaffolding only.

## Empirical test

Pending. To be run on a clean Ubuntu 24.04 VM (multipass) with both CLIs installed and the bundled skill dropped into `~/.agents/skills/`.

### Recipe

```bash
# Host
multipass launch --name biab-spike --cpus 2 --memory 4G --disk 20G 24.04
multipass mount $(pwd) biab-spike:/repo
multipass shell biab-spike

# Inside the VM
sudo apt-get update && sudo apt-get install -y nodejs npm
sudo npm install -g @anthropic-ai/claude-code @google/gemini-cli   # exact package names TBD
mkdir -p ~/.agents/skills/
cp -r /repo/payload/skills/sdd-base ~/.agents/skills/

# Authenticate each CLI (interactive, one-time)
claude login
gemini auth login

# Probe Claude Code: does it list the skill?
claude --help     # look for skill listing flag, or invoke a SDD prompt
echo "Create a FEAT spec for a hello-world CLI" | claude -p

# Probe Gemini CLI: same prompt
echo "Create a FEAT spec for a hello-world CLI" | gemini -p
```

### Acceptance criteria for the empirical test

- [ ] Claude Code loads `sdd-base` and the response visibly follows the SDD template (sections §0–§6 or starter mode).
- [ ] Gemini CLI loads `sdd-base` from `~/.agents/skills/` (no extra config needed) and the response is similarly SDD-shaped.
- [ ] If both pass: v1 ships SDD skills for both CLIs.
- [ ] If only Claude passes: v1 ships SDD skills only when Claude is chosen; document Gemini as "no SDD skills yet, planned for v1.x".

## Follow-ups (not Wave 0 blockers)

1. **Config path portability.** Move `~/.claude/sdd-config.json` to `~/.config/sdd/config.json`. Update `SKILL.md` to look there first, fall back to the legacy path. One-line change once the bundled skill is finalised.
2. **Description wording.** Drop the literal `for Claude Code` reference in `description` so the skill reads neutral when shown to Gemini users.
3. **Specialized skills.** Write generic versions of `sdd-coordinator`, `sdd-spec-writer`, `sdd-qa`, `sdd-growth`, `sdd-docs` before v1 ships. They reference roles by title and never name personas, persona names live in `sdd-config.json`.
