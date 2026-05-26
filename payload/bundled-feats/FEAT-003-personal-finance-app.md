---
id: FEAT-003
title: personal-finance-app
status: draft
priority: medium
complexity: high
created: 2026-05-26
validated_by: null
---

# FEAT-003: Personal finance app — CSV / Slack / scraper ingestion + AI categorisation + live dashboard

> Pre-bundled by Builders in a Box. Suggested as your second project after FEAT-002. Designed to walk you end-to-end through: building a real product, ingesting data from multiple sources, using AI for the boring parts, and shipping it to a real domain in production.

## §0 — Strategy

> Owner: Product Lead

- **Why now:** the boss already has a working devbox, a coach in Slack (FEAT-002), and an understanding of SDD. The next leap is "I can build a real product that runs in production on a domain I own." Personal finance is the perfect candidate — the boss already knows the domain, the data shapes are well-understood, and the value of the app is immediate (one screen with where my money went last month).
- **Hypothesis:** a self-hosted finance dashboard that ingests bank CSVs, scrapes one tricky bank, and auto-categorises transactions with AI will be useful enough that the boss actually keeps using it. Useful → he iterates → he learns the production loop in production.
- **OKR / goal alignment:** this is the "graduation project". After this FEAT, the boss has run the full BIAB loop end-to-end at least once with a real deploy.
- **Cost of not doing it:** the device sits at "could build something" instead of "did build something". Without a second real project, the value of the coach (FEAT-002) is also harder to see.

## §1 — Product requirements

> Owner: Product Lead

### What it does

A small web app you (the boss) host on a domain you own. From your phone or laptop you can:

1. **Upload a CSV** (bank statement) via a web form, or drop one in a dedicated Slack channel.
2. **Trigger a scraper** for at least one bank/card the boss uses (Playwright-driven) so transactions arrive without manual export.
3. **See the data** in a dashboard:
   - Monthly spending by category (bar chart).
   - Top 10 merchants this month.
   - Cashflow over the last 6 months (line chart).
   - Drill-down: tap a category → see the transactions in it.
4. **AI auto-categorises** new transactions on import. Manual override is one tap.
5. **Search** the full transaction history in plain language ("how much did I spend on coffee last quarter?") — answered by an LLM with the database as context.

### Boundaries

- **Always:**
  - Self-hosted on infrastructure the boss controls (his Cloudflare/GCP/Firebase account).
  - Free tier sufficient for personal use. If the boss outgrows it, that's a good problem.
  - The data never leaves the boss's account. Anthropic sees only the prompts the boss explicitly sends.
  - All secrets in environment variables / KV / Secret Manager — never in code.
  - One-command deploy. `wrangler deploy` (Cloudflare) or `firebase deploy` (Firebase) or `gcloud run deploy` (GCP).
  - Mobile-first UI. The boss will mostly look at this from his phone.

- **Ask first:**
  - Which cloud platform? (Recommendation: Cloudflare. Cheaper, simpler, includes domain registration. Alternatives discussed in `/second-project`.)
  - One bank scraper or two? (One is enough for v1.)
  - How aggressively to anonymise/redact merchants in AI prompts? Default: strip account numbers, keep merchant names.

- **Never:**
  - Connect to a real bank via plaid/open-banking APIs in v1. Too much KYC for a personal project.
  - Sell or share any data, ever. Not part of the product.
  - Store CSVs in a third-party service the boss doesn't control.
  - Build a "multi-tenant SaaS finance app". This is one user (the boss), forever.

### Product acceptance criteria

- [ ] Boss can drop a CSV (e.g. an N26 export) at the upload page, see the parsed rows preview, confirm, and watch the dashboard update.
- [ ] Boss can drop the same CSV in a Slack channel (`#finance`?) and have it auto-imported with a thread reply confirming the row count.
- [ ] At least one Playwright scraper successfully imports last month's transactions on demand.
- [ ] >85% of imported transactions get a sensible AI category on first pass.
- [ ] The dashboard loads in under 2s on a 4G phone connection.
- [ ] Plain-language search returns a correct number for a deterministic test query ("how much did I spend at <known merchant> in <known month>?").
- [ ] App deployed at a domain the boss owns. HTTPS via the platform's automatic certs.
- [ ] One-command redeploy from the project folder reaches production in <2 min.

## §2 — Technical spec

> Owner: Tech Lead

### Research

**Recommended stack (Cloudflare path):**

- **Frontend:** Astro or plain HTML + HTMX + Chart.js. No SPA framework needed for a 3-page mobile dashboard. Hosted on Cloudflare Pages.
- **Backend / API:** TypeScript + Hono on Cloudflare Workers.
- **Database:** Cloudflare D1 (sqlite-compatible, serverless). Tables: `transactions`, `categories`, `imports`, `scraper_runs`.
- **Object storage:** Cloudflare R2 for raw CSV archives and scraper screenshots (debug artifacts).
- **AI:** Cloudflare Workers AI (Llama or similar) for categorisation; Claude API directly for plain-language search (better quality).
- **Slack ingest:** Slack Events API webhook → Cloudflare Worker route.
- **Scraper:** Playwright running on a small VPS (cheapest droplet, ~5€/mo) OR Cloudflare Browser Rendering (still beta, watch costs). For v1 a tiny VPS is simpler.
- **Domain:** Cloudflare Registrar (cheapest, no markup, one account).
- **Auth:** single-user. Cloudflare Access (free for 1 user) protects the dashboard behind your Google/GitHub login. Slack ingest uses signing secret to validate.

**Alternative stacks:**

| Stack | Pros | Cons |
|---|---|---|
| Firebase (Hosting + Functions + Firestore) | Excellent dev experience, generous free tier | Cold starts on Functions, no built-in scraper host |
| GCP (Cloud Run + Cloud SQL + Cloud Storage) | Production-grade primitives, very flexible | More setup; needs billing enabled even on free tier |
| Vercel + Supabase | Great DX, free tier ok | Two vendors, no domain registrar |

The `/second-project` skill walks through choosing one. **Default recommendation: Cloudflare** for cost + single-vendor + included domain registrar.

### Implementation plan (waves)

**Wave 0 — Cloud accounts (the boss does this with the `/second-project` skill).**
0. Cloudflare account created. Optional: also GCP and Firebase accounts for comparison.
1. Domain bought via Cloudflare Registrar (or transferred in). DNS pointed to Cloudflare.

**Wave 1 — Schema + CSV import.**
2. D1 database created. Schema migration applied (`transactions`, `categories`, `imports`).
3. Hono worker with `POST /api/import/csv` that takes a file, parses (papaparse), stores rows.
4. Minimal HTML upload page on Pages that calls the worker.
5. Smoke test: real CSV from the boss's bank goes in, rows visible via `wrangler d1 execute ... 'SELECT * FROM transactions'`.

**Wave 2 — AI categorisation.**
6. On import, run each row through Workers AI (or Claude API) with a prompt that maps `(merchant, amount, description)` to one of ~12 categories.
7. Cache merchant→category mappings in `categories` table so repeat merchants are instant + free.
8. Manual override endpoint `PATCH /api/transactions/:id` for fixing wrong categories.

**Wave 3 — Dashboard.**
9. Dashboard page with three charts (monthly by category, top merchants, 6-month cashflow). Chart.js, server-rendered HTML with HTMX partial reloads for the time-range picker.
10. Category drill-down route.
11. Plain-language search bar: input → calls Claude with the DB schema + recent transactions → Claude returns a SQL query → backend runs the SQL (sandboxed, read-only) → answer rendered.

**Wave 4 — Slack ingestion.**
12. Slack app (separate from the coach app, or reuse — the boss decides). Add `files:read` and `channels:history` scopes.
13. Slack Events API webhook subscribed to `file_shared` and `message` in the `#finance` channel.
14. Worker route receives the event, fetches the file content from Slack, runs the same import pipeline as Wave 1.
15. Posts back to the channel: "imported 47 rows, here's the link to the dashboard".

**Wave 5 — Playwright scraper.**
16. Small VPS (Hetzner or Digital Ocean) provisioned. Tailscale-joined so the boss can SSH in via the existing tailnet.
17. Playwright script for the boss's chosen bank/card. Headless, runs daily via cron.
18. On run, posts the new rows to `POST /api/import/scraper` on the worker (signed with a shared secret).
19. Screenshots of each run archived to R2 for debugging.

**Wave 6 — Deploy + harden.**
20. `wrangler deploy` to a production environment. Cloudflare Access in front of the dashboard (only the boss's Google account allowed).
21. Custom domain attached. HTTPS automatic.
22. README and runbook for "this broke, what do I do" written.

### Quality gates

- [ ] All TypeScript code passes `tsc --noEmit`.
- [ ] `wrangler dev` runs cleanly with no errors at startup.
- [ ] No secrets in any committed file (`xoxb-`, `sk-ant-`, etc.).
- [ ] D1 schema is captured in a migration file under `migrations/`.
- [ ] Manual smoke run of every wave's acceptance criterion before merging to main.

## §3 — Growth notes

> Owner: Growth Lead

Personal tool. No growth surface in v1. If the boss ever shares it as a template (which would be fun), that's a separate FEAT.

The interesting growth angle is meta: this app becomes the boss's reference for "I built this from spec to production in N evenings on my BIAB". That story is the marketing for BIAB itself.

## §4 — QA

> Owner: QA Lead

### Functional cases

- [ ] Upload a 300-row CSV. All 300 rows appear in the DB and on the dashboard within 5s.
- [ ] Upload the same CSV twice. Duplicates detected and skipped.
- [ ] AI categorises a known merchant (e.g. "Mercadona") correctly on first import.
- [ ] Manual override of a category sticks (page reload reflects it).
- [ ] Slack drop of the same CSV produces the same result as the web upload.
- [ ] Scraper run posts new rows and acks in Slack.
- [ ] Plain-language search returns a correct number for a deterministic query.
- [ ] Dashboard loads in <2s on a throttled 4G connection (Chrome DevTools profile).

### Edge cases

- [ ] Garbage CSV (no header, wrong columns): friendly error, no crash.
- [ ] Slack drop with a non-CSV file: bot replies "I only handle CSV, sorry".
- [ ] Scraper run fails (bank changed their UI): row count = 0, error captured in R2 + Slack DM.
- [ ] AI categoriser times out: row imported with `category=uncategorised`, dashboard shows it.
- [ ] User uploads a CSV in a different currency: rows imported with currency field, dashboard shows mixed-currency view honestly.
- [ ] Plain-language search asks for data the schema can't answer: model says so, doesn't hallucinate.

### Regression plan

- [ ] CI on the project's GitHub repo runs `tsc`, eslint, and an integration test that imports a fixture CSV and asserts the row count.
- [ ] One real-world import per week is the heartbeat.

### Smoke tests post-deploy

- [ ] Hit the domain, see the dashboard.
- [ ] Cloudflare Access prompts for login.
- [ ] Drop a known CSV into Slack, see ack within 30s.

## §5 — Docs

- [ ] `README.md` in the project repo: what this is, how to deploy, how to add a new scraper.
- [ ] `RUNBOOK.md`: common failure modes and how to fix them.
- [ ] `CLAUDE.md` updated with project conventions (Hono routing, D1 patterns, AI categorisation prompt).
- [ ] One short blog post / Twitter thread (optional) for the meta-marketing angle.

## §6 — Feedback (post-completed)

*Filled in after the FEAT ships.*
