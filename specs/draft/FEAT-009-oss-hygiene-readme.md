---
id: FEAT-009
title: oss-hygiene-readme
project: buildersinabox
status: draft
phase: requisitos
priority: high
complexity: low
created: 2026-06-13
updated: 2026-06-13
validated_by: null
---

# FEAT-009: OSS hygiene + public README

## §0 — Strategy

> Owner: Product Lead

- **Why now:** the first pageview on a public GitHub repo is the README, and the first signals a developer scans for are LICENSE, CONTRIBUTING, an active CI badge, and a SECURITY policy. Without them the repo reads as "someone's dump", not "a project I can trust and contribute to". For a tool that asks users to pipe a script to `sudo bash`, the trust bar is higher than usual — a visible CI that lints every change and a clear SECURITY contact are not optional.
- **Hypothesis:** a tight README that delivers the hierarchical pitch (installer-on-Ubuntu primary, USB/ISO alt, umbrella roadmap), plus the standard OSS hygiene files, plus a CI workflow that runs the checks we already have (`shellcheck`, `check-no-personal-refs.sh`, `bash -n`) on every push, is enough to make the repo look credible and defensible on day one.
- **Why this specific cut:** these are mostly additive files; the only judgement-heavy piece is the README copy, which carries the positioning. The CI is the highest-leverage item — it permanently prevents a personal-reference regression (a future commit reintroducing "paco") from reaching `main`.
- **Cost of not doing it:** a README written for maintainers, no contribution guidance, no CI badge, and no security contact. Contributors bounce, a bad PR can merge without lint, and a personal-ref regression could leak silently.
- **Strategic shift this enables:** the repo becomes contribution-ready and the CI gate becomes the durable guarantee behind every future "the tree is clean" claim. The README becomes the canonical pitch that the landing page (FEAT-010) and launch posts echo.

## §1 — Product requirements

> Owner: Product Lead

### Problem

The repo has no public-facing README, no contribution guide, no security policy, no CI, and no issue/PR templates. It cannot be published as a credible OSS project in this state.

### Intent (why)

Launch readiness requires the repo to meet baseline OSS expectations. The README is the conversion surface; CI is the trust-and-safety gate; the hygiene files are the contribution on-ramp. All three are prerequisites to making the repo public.

### Proposed solution

1. **Public README** with: one-line hook, the `curl | bash` quickstart, a "what you get" section, hardware guidance (any Ubuntu 24.04 box + 2-3 recommended mini PCs), the USB/ISO alt path, an honest "roadmap / coming modules" section (Conerator, Observio, Pathtrip), and links to deeper docs.
2. **CONTRIBUTING.md** — how to propose changes, run the tests locally (`shellcheck`, `bash -n`, `check-no-personal-refs.sh`, `payload/test/dryrun.sh` on a VM), commit style.
3. **SECURITY.md** — report vulnerabilities to `hello@buildersinabox.com`; scope (it's an installer that runs as root); response expectations.
4. **CODE_OF_CONDUCT.md** — Contributor Covenant boilerplate.
5. **`.github/workflows/ci.yml`** — on push/PR: `shellcheck` all `.sh`, `bash -n` the entry points, run `check-no-personal-refs.sh`, optionally a `git archive` cleanliness check.
6. **Issue templates** (`.github/ISSUE_TEMPLATE/{bug_report,feature_request}.yml`) + **PR template** (`.github/PULL_REQUEST_TEMPLATE.md`).
7. **Repo metadata**: description + topics (documented for the maintainer to set on the public repo).

### User stories

- As a developer evaluating BIAB, I want a README that tells me in 10 seconds what it is, how to install it, and what I get, so I decide to try it.
- As a would-be contributor, I want a CONTRIBUTING guide and a green CI badge, so I know how to help and that my PR will be checked.
- As a security researcher, I want a SECURITY.md with a contact, so I can responsibly disclose.
- As a maintainer, I want CI to block any PR that reintroduces a personal reference or breaks shellcheck, so the tree stays clean without manual vigilance.

### Functional requirements (EARS)

- [ ] **Ubiquitous:** The README shall present the `curl | bash` one-liner as the primary install path within the first screen.
- [ ] **Ubiquitous:** The README shall state hardware expectations (Ubuntu 24.04, x86-64, ethernet for first boot) and name 2-3 recommended mini PCs.
- [ ] **Event-driven:** When a PR or push touches any `.sh` file, CI shall run `shellcheck` and fail the check on any error-level finding.
- [ ] **Event-driven:** When a PR or push occurs, CI shall run `tools/check-no-personal-refs.sh` and fail if it returns non-zero.
- [ ] **Ubiquitous:** SECURITY.md shall name `hello@buildersinabox.com` as the disclosure contact and state that the installer runs as root.
- [ ] **Ubiquitous:** All hygiene files and the README shall be English and pass `check-no-personal-refs.sh`.
- [ ] **Unwanted:** If CI's `check-no-personal-refs.sh` finds a forbidden pattern, then the workflow shall fail with the matching file and pattern in the log.

### Non-functional requirements

- [ ] README ≤ ~200 lines; scannable, not a wall of text. Demo gif slot reserved (asset produced separately).
- [ ] CI runs in < 2 minutes (lint-only, no VM).
- [ ] Hygiene files use recognised standards (Contributor Covenant, GitHub template schema).

### Growth Notes

- **Channel:** the README is the top of the GitHub funnel; the CI badge is a trust signal. The "roadmap / coming modules" section seeds expectations for the umbrella story without overpromising.

## §2 — Technical spec

> Owner: Tech Lead (`sdd-spec-writer`)

### Prior investigation

- **Current README:** `README.md` is maintainer-oriented (directory map, dev notes). It references `payload/install.sh`, the repo layout, DIY install. Needs a rewrite for a public audience, keeping a "repo layout" section lower down for contributors.
- **Existing checks to wire into CI:** `tools/check-no-personal-refs.sh` (returns 0/1), `shellcheck` (available), `bash -n`. `payload/test/dryrun.sh` needs a VM so it's NOT in CI (documented in CONTRIBUTING as a manual step).
- **No `.github/` dir yet** — all templates/workflows are new.
- **LICENSE:** MIT, present.
- **Email:** `hello@buildersinabox.com` routes to the maintainer (Cloudflare Email Routing, done).

### Scope

#### Includes

- Rewrite `README.md` (public).
- Create `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`.
- Create `.github/workflows/ci.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `.github/PULL_REQUEST_TEMPLATE.md`.
- A `docs/` landing for contributor-facing deep docs (architecture, the wizard flow) — move existing maintainer notes from README here.
- A short `MAINTAINING.md` note documenting the repo description + topics to set on GitHub.

#### Does NOT include

- The marketing landing page (FEAT-010).
- The social preview image (asset task, can be tracked separately).
- Any code change to the installer (hygiene/docs only).
- Translating SDD skills or examples (FEAT-008).

### Affected files

| File | Action |
|------|--------|
| `README.md` | REWRITE (public) |
| `CONTRIBUTING.md` | CREATE |
| `SECURITY.md` | CREATE |
| `CODE_OF_CONDUCT.md` | CREATE |
| `.github/workflows/ci.yml` | CREATE |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | CREATE |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | CREATE |
| `.github/PULL_REQUEST_TEMPLATE.md` | CREATE |
| `docs/architecture.md` | CREATE (absorbs maintainer detail from old README) |
| `MAINTAINING.md` | CREATE (repo description + topics + release notes) |

### Dependencies

- None new. CI uses `ubuntu-latest` GitHub runner + apt `shellcheck`.

### Tasks

#### Wave 1

<task id="1">
  <name>CI workflow</name>
  <files>.github/workflows/ci.yml</files>
  <action>
    On push + pull_request: checkout, apt-get install shellcheck, run shellcheck on
    all tracked .sh (find . -name '*.sh' -not -path './.git/*'), run `bash -n` on
    payload/install.sh + installer/web/install.sh, run bash tools/check-no-personal-refs.sh,
    and a `git archive HEAD | tar -t | grep -q maintainer && exit 1 || true`
    cleanliness assertion. Fail the job on any non-zero.
  </action>
  <verify>yamllint .github/workflows/ci.yml 2>/dev/null || python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"</verify>
  <done>Valid YAML; job defines shellcheck + bash -n + guard steps.</done>
</task>

<task id="2">
  <name>Public README rewrite</name>
  <files>README.md, docs/architecture.md</files>
  <action>
    New README: hook line; `curl -fsSL https://buildersinabox.com/install.sh | sudo bash`
    quickstart; "What you get" (phone-accessible Claude Code over Tailscale + tmux in
    ~15 min); "What you need" (Ubuntu 24.04 x86-64, ethernet, a Claude/Tailscale
    account; 2-3 recommended mini PCs); "Alt: USB/ISO" pointer to iso-builder/;
    "Roadmap" honest list (Conerator, Observio, Pathtrip as coming modules); "How it
    works" 3-bullet summary; links. Reserve a demo-gif slot near the top. Move the
    repo-layout/dev detail to docs/architecture.md.
  </action>
  <verify>grep -q "curl -fsSL https://buildersinabox.com/install.sh" README.md && [ "$(wc -l < README.md)" -le 220 ]</verify>
  <done>README leads with the one-liner, ≤220 lines, architecture detail moved to docs/.</done>
</task>

<task id="3">
  <name>CONTRIBUTING + SECURITY + CODE_OF_CONDUCT</name>
  <files>CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md</files>
  <action>
    CONTRIBUTING: local test commands (shellcheck, bash -n, check-no-personal-refs.sh,
    VM dryrun as manual step), commit style (feat:/fix:/docs:), PR expectations.
    SECURITY: contact hello@buildersinabox.com, note root-level install scope,
    disclosure window. CODE_OF_CONDUCT: Contributor Covenant 2.1 with the contact
    email filled in.
  </action>
  <verify>grep -q "hello@buildersinabox.com" SECURITY.md && grep -q "check-no-personal-refs" CONTRIBUTING.md</verify>
  <done>Three files present with the right contact + local-test guidance.</done>
</task>

<task id="4">
  <name>Issue + PR templates + MAINTAINING</name>
  <files>.github/ISSUE_TEMPLATE/bug_report.yml, .github/ISSUE_TEMPLATE/feature_request.yml, .github/PULL_REQUEST_TEMPLATE.md, MAINTAINING.md</files>
  <action>
    GitHub form-schema YAML for bug (env: which Ubuntu, which mini PC, install path)
    and feature templates. PR template with a checklist (shellcheck pass, guard pass,
    tested on VM?). MAINTAINING.md: the repo description string, the topics list
    (homelab, tailscale, claude-code, ubuntu, ai, self-hosted, installer), and the
    release/publish note pointing at FEAT-011's publish.sh.
  </action>
  <verify>python3 -c "import yaml; yaml.safe_load(open('.github/ISSUE_TEMPLATE/bug_report.yml'))" && test -f .github/PULL_REQUEST_TEMPLATE.md</verify>
  <done>Templates are valid; MAINTAINING documents description + topics.</done>
</task>

#### Wave 2 — verification

<task id="5">
  <name>Run CI steps locally + guard</name>
  <files>.github/workflows/ci.yml</files>
  <action>
    Execute each CI step locally to confirm they pass on the current tree:
    shellcheck, bash -n, check-no-personal-refs.sh, archive cleanliness.
  </action>
  <verify>bash tools/check-no-personal-refs.sh && shellcheck $(find . -name '*.sh' -not -path './.git/*' -not -path './payload/flavors/gift/maintainer/*')</verify>
  <done>All CI steps pass locally on the current tree.</done>
</task>

### Code pattern to follow

Reuse the existing check invocations verbatim in CI so local and CI behaviour are identical:

```yaml
- run: bash tools/check-no-personal-refs.sh
- run: find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck
```

### Global acceptance criteria

- [ ] README leads with the `curl | bash` one-liner and covers hardware + alt path + roadmap.
- [ ] CI workflow is valid YAML and its steps pass on the current tree.
- [ ] SECURITY.md names `hello@buildersinabox.com`.
- [ ] CONTRIBUTING documents the local test commands.
- [ ] Issue + PR templates valid; MAINTAINING lists description + topics.
- [ ] Everything English; `check-no-personal-refs.sh` clean.

## §3 — Boundaries

### Always

- English; passes the personal-refs guard.
- CI reuses the existing check scripts (no divergent logic).
- README stays honest about what's shipped vs roadmap.

### Ask First

- Adding a paid/sponsor CTA (FUNDING.yml) — brand/monetisation decision tied to EXEC-005 (OSS-only, no monetisation 12 months).
- Enabling GitHub Discussions / Wiki (community-surface decision).
- Any CI step that uploads artifacts or talks to external services.

### Never

- Put personal references, real tokens, or internal URLs in any public doc.
- Claim modules (Conerator/Observio/Pathtrip) are available when they're roadmap.
- Reference the maintainer's employer or personal brand (EXEC-004 separation).

## §4 — QA

> Owner: QA Lead (`sdd-qa`)

### Test cases (functional)

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| F1 | README quickstart visible | Open README | One-liner in first screen; hardware + alt path + roadmap sections present | pending |
| F2 | CI passes on clean tree | Trigger workflow (or act/local) | All steps green | pending |
| F3 | CI fails on planted leak | Add `paco` to a file, push to a test branch | check-no-personal-refs step fails, workflow red | pending |
| F4 | Templates render | Open a new issue / PR on GitHub | Bug/feature forms + PR checklist appear | pending |

### Edge cases

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| E1 | shellcheck warning vs error | Introduce an info-level shellcheck note | CI still passes (only error-level fails) | pending |
| E2 | Non-.sh change | Edit only a .md | CI runs guard but skips shellcheck gracefully (no .sh changed still lints all, passes) | pending |

### Regression

- [ ] Existing maintainer info still discoverable (moved to docs/architecture.md, linked from README).
- [ ] `check-no-personal-refs.sh` clean after all new files added.

### Testing criteria

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
grep -q "curl -fsSL https://buildersinabox.com/install.sh" README.md
grep -q "hello@buildersinabox.com" SECURITY.md
bash tools/check-no-personal-refs.sh
shellcheck $(find . -name '*.sh' -not -path './.git/*' -not -path './payload/flavors/gift/maintainer/*')
```

## §5 — Implementation

> To be filled during spec-implementer run. Branch `feat/FEAT-009`.

## §6 — Feedback

(none yet)
