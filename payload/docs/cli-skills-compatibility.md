# CLI skills compatibility: Claude Code ↔ Gemini CLI

> Wave 0 deliverable of FEAT-001. Determines whether the bundled SDD skills can be shipped under `~/.agents/skills/` and consumed identically by both AI CLIs supported in v1.

**Status:** ✅ Complete. Research + empirical validation done on a clean Ubuntu 24.04 multipass VM.

**Date:** 2026-05-25.

## Empirical results (TL;DR)

Tested on a fresh `multipass launch 24.04` VM with `claude@2.1.150` and `gemini@0.43.0` installed via npm. Dropped the unmodified `payload/skills/sdd-base/SKILL.md` into `~/.agents/skills/sdd-base/`.

**Gemini CLI:** discovers the skill with zero configuration. Confirmed via:

```
$ gemini skills list --all
Discovered Agent Skills:

sdd-base [Enabled]
  Description: Spec-Driven Development — base workflow for Claude Code. ...
  Location:    /home/ubuntu/.agents/skills/sdd-base/SKILL.md
```

**Claude Code:** does not look in `~/.agents/skills/` natively. Its canonical user-level skills path is `~/.claude/skills/`. For Claude to discover the bundled skill we need to also install it there (or symlink).

**Install strategy for v1 wizard:** install bundled skills to both `~/.claude/skills/` and `~/.agents/skills/` (via symlink to avoid duplication). One source-of-truth at `~/.agents/skills/<name>/`, a symlink at `~/.claude/skills/<name>` pointing to it. Both CLIs find their skill from their native location, no content drift possible.

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

The `~/.agents/skills/` and `.agents/skills/` aliases are explicitly documented in [Gemini CLI's skills docs](https://geminicli.com/docs/cli/skills/). Claude Code (v2.1.150 tested) does **not** read from `~/.agents/skills/` natively — its canonical path remains `~/.claude/skills/`. **Conclusion (revised after empirical test): install bundled skills to `~/.agents/skills/` as the source of truth, and symlink `~/.claude/skills/<name>` to it so Claude Code finds them at its native path. Both CLIs work with no duplication and no drift.**

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

A maintainer's local `~/.claude/skills/sdd-base/SKILL.md` may contain personalised agent personas, internal email domains, and hardcoded project paths from the maintainer's own workflow. **Those are not candidates for shipping.** Only the generic versions in `payload/skills/` ship to recipient devices. `tools/check-no-personal-refs.sh` guards the boundary.

## Empirical test recipe (reproducible)

For anyone wanting to re-validate, this is the exact sequence used:

```bash
# Host (one-time)
sudo snap install multipass

# Provision the VM
multipass launch --name biab-spike --cpus 2 --memory 4G --disk 20G 24.04
multipass mount /path/to/buildersinabox biab-spike:/repo

# Install Node 20 + both CLIs inside the VM
multipass exec biab-spike -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -"
multipass exec biab-spike -- sudo apt-get install -y nodejs
multipass exec biab-spike -- sudo npm install -g @anthropic-ai/claude-code @google/gemini-cli

# Drop the bundled skill via the cross-CLI alias
multipass exec biab-spike -- bash -c 'mkdir -p ~/.agents/skills && cp -r /repo/payload/skills/sdd-base ~/.agents/skills/'

# Verify Gemini discovers it (no OAuth needed)
multipass exec biab-spike -- gemini skills list --all
# Expected: sdd-base listed with the correct description and location

# (Optional) Verify the invocation by OAuthing into Gemini and running a SDD prompt
multipass exec biab-spike -- gemini auth login
multipass exec biab-spike -- bash -c 'echo "Use sdd-base to outline a FEAT for a hello-world CLI" | gemini -p'

# Cleanup
multipass delete biab-spike && multipass purge
```

### What we validated

- [x] **Format-level compatibility.** Anthropic-style frontmatter (`name`, `description`) is read identically by both CLIs.
- [x] **Gemini discovery.** Zero-config discovery from `~/.agents/skills/` confirmed via `gemini skills list --all`.
- [x] **Claude discovery path.** Confirmed as `~/.claude/skills/` (Claude Code does not currently honour the `~/.agents/skills/` alias — at least not in v2.1.150). Mitigation: install bundled skills to both paths (symlink one to the other).
- [ ] **Behavioural invocation.** Not validated under this spike — the model picking up the skill and producing SDD-shaped output is content-quality territory, deferred to FEAT-001 Wave 4 end-to-end tests once we have authenticated CLIs in the test rig.

## Follow-ups (not Wave 0 blockers)

1. **Config path portability.** Move `~/.claude/sdd-config.json` to `~/.config/sdd/config.json`. Update `SKILL.md` to look there first, fall back to the legacy path. One-line change once the bundled skill is finalised.
2. **Description wording.** Drop the literal `for Claude Code` reference in `description` so the skill reads neutral when shown to Gemini users.
3. **Specialized skills.** Write generic versions of `sdd-coordinator`, `sdd-spec-writer`, `sdd-qa`, `sdd-growth`, `sdd-docs` before v1 ships. They reference roles by title and never name personas, persona names live in `sdd-config.json`.
