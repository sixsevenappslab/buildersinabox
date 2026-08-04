---
id: FEAT-022
title: harness-consumer-reconciliation
project: buildersinabox
status: active
priority: medium
complexity: small
created: 2026-08-04
validated_by: Jesus (scope dictated verbatim, Spec Ligero)
---

# FEAT-022: Reconcile BIAB as consumer of core/harness/ (Spec Ligero)

## §0 — Why

BIAB is the external "in a box" edition of the personal harness at
`~/ai-platform/core/harness/` (canonical source). FEAT-034 Wave B did the
initial reconciliation source→bundle; this closes the consumer side.

**Scope decided, do not reopen:** BIAB base = the "way of working" layer
(SDD skills, review, roles). Personal services from ai-platform/core
(Slack daemon, observio, conerator) do NOT enter the base — at most future
opt-in bring-your-own-token packs.

## §1 — Tasks

1. **Reconcile `payload/skills/`** with source for the 8 lineage pairs
   (code-simplifier, documentator, incident, code-review←code-review-checklist,
   morning-check←project-health, executive←elena-vp-product,
   ui-ux-consultant←lucas-uxui, quota←`core/harness/claude/skills/quota`):
   port pending improvements from the FEAT-034 Wave B reconciliation,
   genericizing (no mhserver paths, no portfolio project names;
   `tools/check-no-personal-refs.sh` must pass).
2. **Evaluate promoting** shared/ skills marked "export candidate" in the
   lineage table (`core/harness/shared/README.md`, after updating it with
   the marks): propose core vs optional (incident/`biab add` pattern).
   **Gate: Jesús decides before implementing.**
   **DECIDED 2026-08-04 (Jesús, AskUserQuestion): 2 core + 5 optional** —
   core: deploy-verify, no-ai-slop; optional (`biab add`): debugging,
   docker-ops, pm2-ops, spec-cleanup, wireframe-generator. Not exportable:
   strategy-council, laura-legal, sl-management, linkedin-strategy,
   content-ganga24, code-review-checklist (dup of bundled code-review).
   **Addendum 2026-08-05 (Jesús):** +deploy-ops as 6th optional (the
   initial proposal wrongly assumed it was already bundled); laura-legal
   confirmed out — deferred to a post-launch generic legal-advisor rewrite
   (FEAT-036 table annotated accordingly, ai-platform PR #328).
3. **`docs/` design note "future packs"**: what a BYO-token slack-bridge
   pack and an observability pack would need. Design doc only, no
   implementation.
4. **README positioning line**: BIAB is the installable edition of the
   system SixSeven Apps is built with (link
   sixsevenapps.com/es/apps/harness). No full-parity promise.

## §3 — Boundaries

- **Always:** genericize on port; personal-refs guard green; PR + CI.
- **Never:** implement packs (task 3 is a doc); promote skills before
  Jesús's decision (task 2); touch payload structural skills
  (tutorial, first-project, whats-ahead, extend-yourself).

## §4 — Done criteria

- [ ] 8 pairs compared; pending improvements ported or "no delta" noted.
- [ ] Lineage table updated with export-candidate marks (ai-platform side).
- [ ] Promotion proposal presented; Jesús's decision recorded here.
- [ ] `docs/future-packs.md` merged.
- [ ] README positioning line merged.
