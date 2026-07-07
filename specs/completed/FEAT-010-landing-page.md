---
id: FEAT-010
title: landing-page
project: buildersinabox
status: completed
phase: requisitos
priority: medium
created: 2026-06-13
updated: 2026-06-13
validated_by: null
---

# FEAT-010: buildersinabox.com landing + install.sh serving

## §0 — Strategy

> Owner: Product Lead

- **Why now:** `curl -fsSL https://buildersinabox.com/install.sh | sudo bash` (FEAT-007) only works if `buildersinabox.com/install.sh` actually serves the bootstrap. And the domain is the second thing people hit after the GitHub repo — a tweet might link the domain, not the repo. Today `buildersinabox.com` returns Cloudflare's default (nothing). Two jobs: serve the install script at a stable path, and give the root a minimal but credible landing.
- **Hypothesis:** a single static site on Cloudflare Pages (the domain is already on Cloudflare) covers both: the root path renders a one-screen landing (hook, the install command, a GitHub button, a "what you get" line), and `/install.sh` serves the FEAT-007 bootstrap as `text/plain`. No backend, no framework — plain HTML + the script file. This is the cheapest possible thing that makes the one-liner real.
- **Why this specific cut:** keeping it static (no SPA, no build step beyond copying files) means it's trivial to maintain and impossible to break in interesting ways. The landing is deliberately minimal for v1 — the demo gif and richer copy can iterate without re-architecting.
- **Cost of not doing it:** the launch one-liner 404s, or the domain shows a parking page. Either kills trust instantly.
- **Strategic shift this enables:** the domain becomes the canonical entry point that the install command, README, and posts all reference. Future analytics (install attempts) and richer marketing live here without changing the contract.

## §1 — Product requirements

> Owner: Product Lead

### Problem

`buildersinabox.com` serves nothing. The FEAT-007 install one-liner has no host to resolve against, and the domain (which posts will link) has no landing.

### Intent (why)

The one-liner is the launch CTA; it must resolve to a real, stable, `text/plain` script over HTTPS. The domain root must present a credible one-screen pitch. Both are prerequisites to any public link going out.

### Proposed solution

A static site deployed to Cloudflare Pages, bound to `buildersinabox.com`:

1. **`/install.sh`** — serves the FEAT-007 bootstrap verbatim as `text/plain; charset=utf-8`, no redirects, valid HTTPS. This is the single most important route.
2. **`/` (root)** — one-screen landing: hook headline, the copy-paste install command (with a copy button), a primary "View on GitHub" button, a 3-bullet "what you get", a one-line honest "bring your own Ubuntu box" note, and a footer with the OSS/MIT + roadmap mention. Mobile-first, no framework.
3. **`/install.sh` integrity** — the served script is the exact file from `installer/web/install.sh` in the repo (single source of truth; the Pages deploy copies it).

### User stories

- As a developer who copied the install command from a tweet, I want `curl https://buildersinabox.com/install.sh` to return the script over HTTPS with no surprises, so the one-liner just works.
- As someone who clicked the domain from a post, I want a one-screen page that tells me what BIAB is and links me to GitHub, so I can decide in 10 seconds.
- As a cautious user, I want to open `buildersinabox.com/install.sh` in a browser and read it, so I trust it before piping to bash.

### Functional requirements (EARS)

- [ ] **Ubiquitous:** The site shall serve `installer/web/install.sh` at `https://buildersinabox.com/install.sh` with `Content-Type: text/plain; charset=utf-8` and HTTP 200 (no redirect).
- [ ] **Ubiquitous:** The root path shall render a one-screen landing with the install command, a GitHub link, and a "what you get" summary.
- [ ] **Event-driven:** When the repo's `installer/web/install.sh` changes and the site redeploys, the served script shall match the repo file byte-for-byte.
- [ ] **Unwanted:** If a visitor requests an unknown path, then the site shall return a simple 404 (no framework error page).
- [ ] **Ubiquitous:** All landing copy shall be English and free of personal references.

### Non-functional requirements

- [ ] Static only — no server runtime, no build step beyond file copy. Cloudflare Pages free tier.
- [ ] HTTPS via Cloudflare edge cert (already terminated for the domain).
- [ ] Landing < 50 KB total (no heavy JS); loads instantly on mobile.
- [ ] `/install.sh` served with a short cache TTL (e.g. 5 min) so script updates propagate quickly.

### Growth Notes

- **Channel:** the domain is a primary funnel entry. The copy-button on the install command reduces friction. Optional: Cloudflare Web Analytics (cookieless) to count landing views + `/install.sh` fetches as a proxy for install attempts — no PII.
- **Tracking:** `/install.sh` request count is the closest thing to an "install attempts" metric. Wire Cloudflare Analytics on that route.

## §2 — Technical spec

> Owner: Tech Lead (`sdd-spec-writer`)

### Prior investigation

- **DNS/host:** `buildersinabox.com` nameservers are Cloudflare (`pat`/`rex.ns.cloudflare.com`), Email Routing active. Cloudflare Pages can bind the apex via the dashboard.
- **Script source:** `installer/web/install.sh` is produced by FEAT-007. The Pages deploy must publish that exact file at `/install.sh`. Simplest: the Pages project's output dir contains `index.html`, `install.sh`, `404.html`, and assets. A tiny build step (`cp installer/web/install.sh site/install.sh`) keeps the source single.
- **Content-Type:** Pages serves `.sh` as `text/plain` by default; confirm and, if needed, add a `_headers` file to force `Content-Type` + cache TTL on `/install.sh`.
- **Repo location:** the landing lives in `site/` (or `landing/`) in the installer repo, OR in a separate repo. Decision: keep it in the same repo under `site/` so the install script and its host stay version-locked. `site/` is shippable-tree-neutral (docs/marketing, not part of the device payload) — exclude from `git archive` payload if needed, but it can stay.

### Scope

#### Includes

- `site/index.html` — the landing (inline CSS, minimal JS for the copy button).
- `site/404.html` — minimal 404.
- `site/_headers` — force `Content-Type: text/plain` + `Cache-Control` on `/install.sh`.
- `site/install.sh` — copied from `installer/web/install.sh` at deploy time (build step or a committed symlink/copy with a check that they match).
- `site/build.sh` — trivial: copies `installer/web/install.sh` → `site/install.sh`, validates they're identical.
- A `MAINTAINING.md` note (or extend FEAT-009's) documenting the Cloudflare Pages project setup (which is done once via dashboard/UI by the maintainer).

#### Does NOT include

- The bootstrap script itself (FEAT-007).
- Rich marketing (demo video, blog, multi-page site) — v1 is one screen.
- Analytics dashboards (just enabling Cloudflare Web Analytics, a checkbox).
- A CMS or framework.

### Affected files

| File | Action |
|------|--------|
| `site/index.html` | CREATE |
| `site/404.html` | CREATE |
| `site/_headers` | CREATE |
| `site/install.sh` | CREATE (generated copy of installer/web/install.sh) |
| `site/build.sh` | CREATE |
| `MAINTAINING.md` | MODIFY (Pages setup steps) |

### Dependencies

- Cloudflare Pages (free tier). No code dependency.

### Tasks

#### Wave 1

<task id="1">
  <name>Landing HTML</name>
  <files>site/index.html, site/404.html</files>
  <action>
    Single-screen responsive HTML, inline CSS, system font stack. Sections: hook
    headline ("Plug in. Code from your phone in 15 minutes."); a <code> block with
    the install one-liner + a copy button (minimal vanilla JS); primary "View on
    GitHub" button → the public repo; 3 bullets "what you get"; one line "Bring your
    own Ubuntu 24.04 box (mini PC, VPS, homelab)."; footer MIT + "modules coming:
    Conerator, Observio, Pathtrip". 404.html minimal with a link home.
  </action>
  <verify>python3 -c "import html.parser,sys; html.parser.HTMLParser().feed(open('site/index.html').read())" && grep -q "install.sh | sudo bash" site/index.html</verify>
  <done>Valid HTML, contains the install one-liner + GitHub link.</done>
</task>

<task id="2">
  <name>Headers + build step</name>
  <files>site/_headers, site/build.sh, site/install.sh</files>
  <action>
    _headers: for /install.sh set Content-Type: text/plain; charset=utf-8 and
    Cache-Control: public, max-age=300. build.sh: cp installer/web/install.sh
    site/install.sh; diff them and exit non-zero if they differ (guards against a
    stale committed copy). Run build.sh so site/install.sh exists.
  </action>
  <verify>bash site/build.sh && diff installer/web/install.sh site/install.sh && grep -q "text/plain" site/_headers</verify>
  <done>site/install.sh matches the FEAT-007 source; _headers forces text/plain + TTL.</done>
</task>

<task id="3">
  <name>Document Cloudflare Pages setup</name>
  <files>MAINTAINING.md</files>
  <action>
    Steps the maintainer does once in the Cloudflare dashboard: create Pages project
    from the repo, set build command `bash site/build.sh`, output dir `site`, bind
    custom domain buildersinabox.com (apex), enable Web Analytics. Note that
    /install.sh updates on each deploy.
  </action>
  <verify>grep -q "Cloudflare Pages" MAINTAINING.md && grep -q "site/build.sh" MAINTAINING.md</verify>
  <done>MAINTAINING documents the one-time Pages setup.</done>
</task>

#### Wave 2 — verification

<task id="4">
  <name>Post-deploy smoke (maintainer, on live domain)</name>
  <files>site/install.sh</files>
  <action>
    After the maintainer wires Pages: curl -sI https://buildersinabox.com/install.sh
    shows 200 + text/plain; curl -fsSL https://buildersinabox.com/install.sh matches
    the repo file; the root renders the landing; an unknown path 404s. Then the full
    FEAT-007 one-liner works end-to-end on a fresh VM against the live URL.
  </action>
  <verify>curl -fsSL https://buildersinabox.com/install.sh | diff - installer/web/install.sh && curl -sI https://buildersinabox.com/install.sh | grep -i "content-type: text/plain"</verify>
  <done>Live /install.sh is byte-identical, text/plain, 200; landing renders; one-liner works against the live domain.</done>
</task>

### Code pattern to follow

Keep the landing dependency-free. The copy button is the only JS:

```html
<button onclick="navigator.clipboard.writeText('curl -fsSL https://buildersinabox.com/install.sh | sudo bash')">copy</button>
```

### Global acceptance criteria

- [ ] `https://buildersinabox.com/install.sh` → 200, `text/plain`, byte-identical to `installer/web/install.sh`.
- [ ] Root renders a one-screen landing with the install command + GitHub link.
- [ ] `site/build.sh` fails if `site/install.sh` drifts from the source.
- [ ] Unknown path → simple 404.
- [ ] All copy English; guard clean.
- [ ] The FEAT-007 one-liner works against the live domain on a fresh VM.

## §3 — Boundaries

### Always

- Static only; no backend; no framework.
- `/install.sh` is byte-identical to the repo source (build step enforces).
- English; guard clean.

### Ask First

- Enabling any analytics beyond Cloudflare's cookieless Web Analytics.
- Adding a waitlist/email-capture form (data handling + GDPR per the maintainer's own rules).
- Pointing the domain at anything other than the Pages project.

### Never

- Serve `/install.sh` from a source other than the repo file.
- Add tracking that sets cookies or collects PII.
- Inline secrets or tokens in the site.

## §4 — QA

> Owner: QA Lead (`sdd-qa`)

### Test cases (functional)

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| F1 | Script served correctly | `curl -sI https://buildersinabox.com/install.sh` | 200, `Content-Type: text/plain; charset=utf-8` | pending |
| F2 | Script integrity | `curl -fsSL .../install.sh \| diff - installer/web/install.sh` | No diff | pending |
| F3 | Landing renders | Open `https://buildersinabox.com/` | One-screen page, install command, GitHub button visible | pending |
| F4 | One-liner end-to-end | On fresh VM: run the live one-liner | Clones + installs (with mock OAuth / --skip-wizard) | pending |

### Edge cases

| # | Case | Steps | Expected | Status |
|---|------|-------|----------|--------|
| E1 | Drift guard | Edit site/install.sh by hand, run build.sh | Exit non-zero (mismatch detected) | pending |
| E2 | Unknown path | `curl -sI .../nope` | 404, minimal page | pending |
| E3 | Copy button | Click copy on the landing | Clipboard holds the exact one-liner | pending |

### Regression

- [ ] Email Routing for the domain still works (DNS unaffected by Pages binding).
- [ ] `installer/web/install.sh` remains the single source of truth.

### Testing criteria

```bash
# Local
bash site/build.sh && diff installer/web/install.sh site/install.sh
python3 -c "import html.parser; html.parser.HTMLParser().feed(open('site/index.html').read())"
grep -q "text/plain" site/_headers

# Live (post-deploy)
curl -sI https://buildersinabox.com/install.sh | grep -i 'content-type: text/plain'
curl -fsSL https://buildersinabox.com/install.sh | diff - installer/web/install.sh
```

## §5 — Implementation

> To be filled during spec-implementer run. Branch `feat/FEAT-010`.

## §6 — Feedback

(none yet)
