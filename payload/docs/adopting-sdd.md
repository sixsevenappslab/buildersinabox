# Adopting SDD on your devbox

First-time setup for the Spec-Driven Development workflow.

## 1. Pick your mode

| Mode | Use if... |
|---|---|
| **Starter** | This is your first project, you're solo, you want to learn the rhythm without ceremony |
| **Full** | You're working on multiple projects, you want Claude Code to play distinct roles, you care about long-term coherence |

You can switch later — same workflow, same skills, different template depth.

## 2. Configure (optional)

If you want to customize persona names or add projects to the spec-implementer matrix, copy the example configs:

```bash
cp ~/buildersinabox/payload/config/sdd-config.example.json ~/.claude/sdd-config.json
cp ~/buildersinabox/payload/config/projects.example.yaml ~/.claude/projects.yaml
$EDITOR ~/.claude/sdd-config.json
```

If you skip this step, the skills run with sensible defaults.

## 3. Create your first project

```bash
cd ~/ai-platform/projects
mkdir my-first-project
cd my-first-project
mkdir -p specs/{draft,active,completed,feedback}
cp ~/buildersinabox/payload/templates/PROJECT-CLAUDE.md CLAUDE.md
$EDITOR CLAUDE.md      # personalize project description, stack, danger zones
```

## 4. Write your first FEAT

From inside Claude Code:

```
/sdd-coordinator I want to add user authentication to my project
```

The coordinator will create `specs/draft/FEAT-001-user-authentication.md` and walk you through §0 and §1.

In **starter mode**, the template is three short sections (Summary / Tasks / QA).
In **full mode**, the template has six sections and the coordinator hands off to the other roles as needed.

## 5. Move from draft to active

Once §0, §1, §2, and §4 have enough content, the coordinator validates DoR and moves the FEAT to `specs/active/`. Now you (or `spec-implementer`) can build it.

## 6. Ship and reflect

When the FEAT merges:

1. The file moves to `specs/completed/`.
2. The owner fills in §6 Feedback (in full mode) — what surprised us, what we'd do differently.
3. The §5 Docs checklist gets ticked off.

## When to graduate from starter to full

You'll know when:
- You start wanting separate sections for "what" vs "how" vs "test plan".
- You need Claude Code to think differently when reviewing requirements vs. designing the implementation.
- You have multiple projects and want consistency across them.

Switching is just: change `mode: starter` to `mode: full` in `sdd-config.json` and start using the full template for new FEATs. Old FEATs stay in starter format — no migration needed.

## Common pitfalls

- **Over-using full mode for trivial fixes.** A typo fix doesn't need a FEAT. Use the Direct mode in your project's `CLAUDE.md`.
- **Drafts that never become active.** If you have >5 drafts and zero active, that's a smell. Run `spec-cleanup`.
- **Treating sections as mandatory.** §3 Growth is optional. §5 Docs can be empty if the FEAT has no public surface. Don't fill sections to "look complete".
