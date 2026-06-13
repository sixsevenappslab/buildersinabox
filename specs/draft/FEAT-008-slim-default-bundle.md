---
id: FEAT-008
title: slim-default-bundle
project: buildersinabox
status: draft
phase: requisitos
priority: high
complexity: medium
created: 2026-06-13
updated: 2026-06-13
validated_by: null
---

# FEAT-008: Slim the default bundle + translate residuals

## §0 — Strategy

> Owner: Product Lead

- **Why now:** FEAT-006 made the *code* neutral, but the *bundle* still ships Jesús's personal workflow. `40-scaffold.sh` installs all 22 skills from `payload/skills/` — including 5 SDD skills written in Spanish (`sdd-coordinator`, `sdd-docs`, `sdd-growth`, `sdd-qa`, `sdd-spec-writer`) — plus two bundled starter specs (`FEAT-002` Slack coach, `FEAT-003` finance) that were written for one specific recipient. An English-speaking developer who runs the public installer and opens Claude Code will find a Spanish "sdd-coordinator" skill and a half-Spanish "implement my Slack coach" spec. That's confusing at best and signals "this wasn't really made for me".
- **Hypothesis:** the default install should ship only what's *universally useful and language-neutral*: the tutorial, the brain-dump CLI, tmux/shell helpers, and a small set of generic Claude Code skills. The opinionated SDD process and the personal starter specs become **opt-in** — surfaced later (FEAT post-launch via the `biab install <module>` contract) rather than forced on every user. A first-run experience that's clean and English beats one that's feature-rich and confusing.
- **Why this specific cut:** we don't delete the SDD skills or starter specs — they move to an opt-in location and the tutorial points to them as "want the full SDD workflow? run `biab add sdd`". This preserves the value for people who want it while keeping the default experience tight and trustworthy.
- **Cost of not doing it:** the first thing a new user sees inside Claude Code is foreign-language tooling and someone else's project specs. It reads as "I'm using someone's personal setup" not "I have my own AI dev box". Directly undercuts the launch.
- **Strategic shift this enables:** establishes the default-vs-opt-in distinction in the bundle, which is the seed of the module contract (FEAT future). It forces us to name "what is core BIAB" vs "what is Jesús's personal layer".

## §1 — Product requirements

> Owner: Product Lead

### Problem

The default install bundles language-specific (Spanish) and recipient-specific content that doesn't generalise: 5 Spanish SDD skills and 2 personal starter specs. A generic OSS user gets a confusing first-run experience full of artifacts that weren't made for them.

### Intent (why)

The launch positioning is "your own AI dev box". The default bundle has to feel like a clean, neutral, English starting point — not a copy of the maintainer's personal workflow. This is the difference between "this is mine" and "I'm borrowing someone's setup".

### Proposed solution

Split the bundled skills into **core** (always installed) and **optional** (available but not installed by default). Remove the two personal starter specs from the auto-install path. Translate any residual Spanish in core skills. Concretely:

1. **Core skills (stay in default install):** `tutorial`, `welcome`, `whats-ahead`, `first-project`, `second-project`, `morning-check`, `extend-yourself`, plus the generic engineering skills (`code-review`, `code-simplifier`, `qa-testing`, `documentator`, `ui-ux-consultant`, `ux-review`, `backend-engineer`, `executive`, `product-marketing`). All English.
2. **Optional skills (NOT installed by default):** the 5 SDD skills (`sdd-base`, `sdd-coordinator`, `sdd-docs`, `sdd-growth`, `sdd-qa`, `sdd-spec-writer`). They remain in the repo under `payload/skills/` but a manifest marks them optional. The tutorial mentions them and offers to install.
3. **Starter specs:** `payload/bundled-feats/FEAT-002` + `FEAT-003` are no longer auto-referenced by the default tutorial flow. The tutorial guides "describe your own first project" instead. The two specs move to `payload/examples/` as illustrative references the user can read or copy if they want.
4. **Translate residuals:** `morning-check`, `tutorial`, and any other core skill with Spanish gets translated to English.

### User stories

- As an English-speaking developer running the public installer, I want the default skills and first-run experience entirely in English, so it feels made for me.
- As a developer who doesn't care about formal spec-driven development, I want a clean Claude Code with a small set of useful skills, not someone's 6-role SDD process, so my `/` menu isn't cluttered.
- As a developer who DOES want the SDD workflow, I want the tutorial to tell me it exists and how to add it, so I don't lose access to it — it's just opt-in.
- As a curious user, I want the old starter specs available as readable examples, so I can learn from them without having them forced into my project.

### Functional requirements (EARS)

- [ ] **Ubiquitous:** The default install shall install only the skills marked `core` in the skills manifest; optional skills shall remain in the repo but not be copied to `~/.claude/skills/`.
- [ ] **Event-driven:** When the tutorial reaches the skills-tour beat, it shall mention the optional SDD bundle and how to add it (a single command), without installing it automatically.
- [ ] **Ubiquitous:** Every skill installed by default shall be in English (no Spanish diacritics, no Spanish-only sentences).
- [ ] **Ubiquitous:** The two personal starter specs shall NOT be auto-referenced by the default tutorial flow; they shall live under `payload/examples/` as optional references.
- [ ] **Optional:** Where the user opts in to the SDD bundle, the optional skills shall be copied into `~/.claude/skills/` and become available in Claude Code.
- [ ] **Unwanted:** If a skill in the manifest is marked `core` but contains Spanish, the build guard shall flag it (extend `check-no-personal-refs.sh` or a sibling check for core-skill language).

### Non-functional requirements

- [ ] No skill is deleted — only re-categorised (core vs optional) and relocated where needed. Reversible.
- [ ] The skills manifest is a simple declarative file (one line per skill: name + core|optional), human-editable.
- [ ] `40-scaffold.sh` reads the manifest instead of globbing `payload/skills/*`.

### Growth Notes

- **Channel:** N/A directly, but the first-run cleanliness materially affects retention/word-of-mouth after install. A confusing first run is a silent conversion killer.

## §2 — Technical spec

> Owner: Tech Lead (`sdd-spec-writer`)

### Prior investigation

- **Skill install logic:** `payload/wizard/40-scaffold.sh` lines ~86-115 loop over `payload/skills/*/`, copy each to `~/.agents/skills/<name>`, and symlink into `~/.claude/skills/<name>`. It installs *everything* via glob.
- **Skill inventory (22):** core-useful — `tutorial`, `welcome`, `whats-ahead`, `first-project`, `second-project`, `morning-check`, `extend-yourself`, `code-review`, `code-simplifier`, `qa-testing`, `documentator`, `ui-ux-consultant`, `ux-review`, `backend-engineer`, `executive`, `product-marketing`. SDD/optional — `sdd-base`, `sdd-coordinator`, `sdd-docs`, `sdd-growth`, `sdd-qa`, `sdd-spec-writer`.
- **Spanish skills (confirmed via diacritic + stopword grep):** `sdd-coordinator`, `sdd-docs`, `sdd-growth`, `sdd-qa`, `sdd-spec-writer`. These are all in the optional set — so removing them from default *also* removes the bulk of the Spanish problem. `sdd-base` to be checked.
- **bundled-feats:** `payload/bundled-feats/FEAT-002-personal-slack-coach.md` (Spanish coach persona) + `FEAT-003-personal-finance-app.md`. Referenced by `/first-project` and the tutorial Beat 3/4 (per FEAT-005).
- **Tutorial coupling:** `payload/skills/tutorial/SKILL.md` Beat 3 shows the two bundled FEATs and asks which to build; Beat 4 invokes `/first-project` with the chosen one. This flow must change to "describe your own project" when no bundled specs are present.
- **morning-check:** had Paco refs (fixed in FEAT-006); needs a Spanish-language pass to confirm it's clean English.

### Scope

#### Includes

- `payload/skills/manifest.tsv` (or `.txt`) — declares each skill `core` or `optional`.
- Modify `40-scaffold.sh` to install only `core` skills by default; respect `BIB_INSTALL_SKILLS=all` override for testing.
- Move `payload/bundled-feats/` → `payload/examples/` and update references.
- Rework `tutorial` Beat 3-4 + `first-project` to default to "describe your own project"; offer the examples as optional reading; offer to add the SDD bundle.
- Add a tiny `biab add sdd` (or `biab skills add sdd`) subcommand to `/usr/local/bin/biab` that copies the optional SDD skills in.
- Translate any residual Spanish in `core` skills (`morning-check`, `tutorial`, etc.).

#### Does NOT include

- Translating the optional SDD skills (they stay Spanish for now; opt-in users get a Spanish SDD process — acceptable since it's explicit opt-in. A future FEAT can translate them).
- The full `biab install <module>` contract (FEAT future) — this FEAT adds only the narrow `biab add sdd` shim.
- Deleting any skill or spec.

### Affected files

| File | Action |
|------|--------|
| `payload/skills/manifest.tsv` | CREATE — `<skill-name>\t<core\|optional>` |
| `payload/wizard/40-scaffold.sh` | MODIFY — read manifest, install core only |
| `payload/bundled-feats/` | MOVE → `payload/examples/` |
| `payload/skills/tutorial/SKILL.md` | MODIFY — Beat 3-4 default to own-project; mention examples + SDD opt-in |
| `payload/skills/first-project/SKILL.md` | MODIFY — handle "no bundled spec chosen" path |
| `payload/install/05-biab-command.sh` | MODIFY — add `biab add sdd` subcommand |
| `payload/skills/morning-check/SKILL.md` | MODIFY — translate residual Spanish if any |
| `payload/tutorial/desktop-readme.md` | MODIFY — update references to bundled-feats path |

### Dependencies

- None new. Bash + existing scaffold tooling.

### Tasks

#### Wave 1

<task id="1">
  <name>Create skills manifest + make scaffold read it</name>
  <files>payload/skills/manifest.tsv, payload/wizard/40-scaffold.sh</files>
  <action>
    Write manifest.tsv: one line per skill dir under payload/skills/, tab-separated
    name and core|optional. Mark the 6 sdd-* as optional, everything else core.
    Modify 40-scaffold.sh: instead of globbing payload/skills/*/, read manifest,
    install only rows tagged core (unless BIB_INSTALL_SKILLS=all). Skip rows whose
    dir is missing with a warn. Keep the agents/skills + claude/skills symlink
    pattern intact.
  </action>
  <verify>grep -c "optional" payload/skills/manifest.tsv | grep -q 6 && bash -n payload/wizard/40-scaffold.sh</verify>
  <done>Manifest lists every skill dir; 6 optional. 40-scaffold.sh parses and installs core-only.</done>
</task>

<task id="2">
  <name>Relocate bundled-feats to examples and repoint references</name>
  <files>payload/bundled-feats/ (move), payload/examples/, payload/skills/first-project/SKILL.md, payload/tutorial/desktop-readme.md</files>
  <action>
    git mv payload/bundled-feats payload/examples. Grep the tree for "bundled-feats"
    and repoint to "examples". The examples remain readable specs but are no longer
    the default project source.
  </action>
  <verify>! test -d payload/bundled-feats && test -d payload/examples && ! grep -rIn "bundled-feats" payload/ --include="*.sh" --include="*.md"</verify>
  <done>bundled-feats gone, examples present, no stale references.</done>
</task>

<task id="3">
  <name>Rework tutorial to own-project-first + opt-in mentions</name>
  <files>payload/skills/tutorial/SKILL.md, payload/skills/first-project/SKILL.md</files>
  <action>
    Beat 3: instead of "pick one of these two specs", say "tell me what you want to
    build — or browse the examples in payload/examples/ for inspiration". Beat 4:
    /first-project handles a free-form project description (create the dir + a
    starter CLAUDE.md + git init), with the examples as optional copy-from. Skills
    tour beat: add one line — "Want a full spec-driven workflow (multi-role SDD)?
    Run `biab add sdd` and I'll install those skills." No auto-install.
  </action>
  <verify>! grep -qIE "(¿|¡|á|é|í|ó|ú|ñ)" payload/skills/tutorial/SKILL.md && grep -q "biab add sdd" payload/skills/tutorial/SKILL.md</verify>
  <done>Tutorial is English, defaults to own-project, mentions the SDD opt-in.</done>
</task>

<task id="4">
  <name>Add `biab add sdd` subcommand</name>
  <files>payload/install/05-biab-command.sh</files>
  <action>
    Extend the biab wrapper with an `add` subcommand. `biab add sdd` copies the
    optional sdd-* skills from /opt/buildersinabox/payload/skills/ into
    ~/.claude/skills/ (and ~/.agents/skills/) using the same install routine as
    40-scaffold. Idempotent. Print which skills were added.
  </action>
  <verify>bash -n payload/install/05-biab-command.sh && grep -q "add sdd\|add)" payload/install/05-biab-command.sh</verify>
  <done>`biab add sdd` exists and installs the optional SDD skills.</done>
</task>

<task id="5">
  <name>Translate residual Spanish in core skills</name>
  <files>payload/skills/morning-check/SKILL.md, any core skill flagged</files>
  <action>
    Grep every core skill for Spanish (diacritics + stopwords). Translate to
    English preserving structure and examples. Do not touch optional sdd-* skills.
  </action>
  <verify>for s in $(awk -F'\t' '$2=="core"{print $1}' payload/skills/manifest.tsv); do grep -lIE "(¿|¡|á|é|í|ó|ú|ñ)" payload/skills/$s/SKILL.md && exit 1; done; echo CLEAN</verify>
  <done>No Spanish diacritics in any core skill.</done>
</task>

#### Wave 2 — verification

<task id="6">
  <name>Fresh-install bundle check</name>
  <files>payload/wizard/40-scaffold.sh</files>
  <action>
    On a VM (or with BIB_TARGET_USER override), run scaffold and assert
    ~/.claude/skills/ contains the core skills and NOT the sdd-* skills. Then run
    `biab add sdd` and assert they appear. Confirm payload/examples/ is present and
    bundled-feats/ is gone.
  </action>
  <verify>ls ~/.claude/skills/ | grep -q tutorial && ! ls ~/.claude/skills/ | grep -q sdd-coordinator</verify>
  <done>Default skills present, SDD skills absent until opt-in. Examples present.</done>
</task>

### Code pattern to follow

The existing skill-install loop in `40-scaffold.sh` (copy to `~/.agents/skills` + symlink to `~/.claude/skills`) is the routine to factor into a reusable function `install_skill <name>` that both scaffold and `biab add` call.

### Global acceptance criteria

- [ ] Default install: `~/.claude/skills/` has the core set, none of the 6 sdd-*.
- [ ] `biab add sdd` installs the optional SDD skills idempotently.
- [ ] No Spanish diacritics in any `core` skill (`awk` core list + grep).
- [ ] `payload/bundled-feats/` removed; `payload/examples/` present; no stale references.
- [ ] Tutorial defaults to "describe your own project" and mentions the SDD opt-in.
- [ ] `git archive` shippable tree still passes `check-no-personal-refs.sh`.

## §3 — Boundaries

### Always

- Re-categorise, never delete. Every skill/spec stays in the repo.
- Manifest is the single source of truth for core-vs-optional.
- Core skills are English-only; optional skills may stay Spanish (explicit opt-in).

### Ask First

- Translating the optional SDD skills (separate effort/decision).
- Promoting `biab add sdd` into a general `biab install <module>` contract (that's the FEAT-008-adjacent module-contract FEAT).
- Changing which skills count as `core` vs `optional` beyond the proposed split.

### Never

- Delete a skill or a starter spec.
- Auto-install optional content without explicit user action.
- Ship a `core` skill containing Spanish or personal references.

## §4 — QA

> Owner: QA Lead (`sdd-qa`)

### Test cases (functional)

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| F1 | Default bundle excludes SDD | Fresh scaffold | `~/.claude/skills/` has tutorial/first-project/etc, no sdd-* | pending |
| F2 | Opt-in adds SDD | `biab add sdd` | sdd-coordinator etc. appear in `~/.claude/skills/`; idempotent on re-run | pending |
| F3 | Examples readable, not forced | Inspect `payload/examples/` | FEAT-002 + FEAT-003 present; tutorial does not auto-load them | pending |
| F4 | Own-project tutorial path | Run `/tutorial` Beat 4 with a free-form description | `/first-project` scaffolds a project dir + CLAUDE.md + git init from the description | pending |

### Edge cases

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| E1 | Manifest lists a missing skill dir | Add a bogus row | scaffold warns and skips, doesn't abort | pending |
| E2 | `biab add sdd` when already added | Run twice | Second run is a no-op with "already installed" | pending |
| E3 | BIB_INSTALL_SKILLS=all override | Scaffold with the override | All skills install (for maintainer/testing) | pending |

### Regression

- [ ] `/tutorial` still completes end-to-end (now via own-project path).
- [ ] `/first-project` and `/second-project` still work.
- [ ] morning-check, brain-dump (`bd`), tmuxc still installed and functional.
- [ ] `check-no-personal-refs.sh` clean.

### Testing criteria

```bash
# Manifest + core-only install
awk -F'\t' '$2=="optional"{print $1}' payload/skills/manifest.tsv   # expect the 6 sdd-*
bash -n payload/wizard/40-scaffold.sh payload/install/05-biab-command.sh

# No Spanish in core skills
for s in $(awk -F'\t' '$2=="core"{print $1}' payload/skills/manifest.tsv); do
  grep -lIE '(¿|¡|á|é|í|ó|ú|ñ)' "payload/skills/$s/SKILL.md" && echo "SPANISH IN $s" || true
done

# Structure
! test -d payload/bundled-feats && test -d payload/examples
bash tools/check-no-personal-refs.sh
```

## §5 — Implementation

> To be filled during spec-implementer run. Branch `feat/FEAT-008`.

## §6 — Feedback

(none yet)
