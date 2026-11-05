---
name: second-project
description: Interactive guide for the user's second suggested project — a personal finance app (FEAT-003) that ingests CSVs, scrapes a bank, auto-categorises with AI, and ships to a real domain in production. Walks through choosing a cloud platform (Cloudflare recommended; GCP / Firebase as alternatives), opening the relevant accounts, buying a domain, and starting Wave 1 of the implementation. Assumes the user has already completed /first-project and shipped FEAT-002.
---

# /second-project — your second guided project: a personal finance app

When the user invokes this skill, you guide them through a bigger arc than `/first-project`. This is the "graduation project" — they go from spec to live URL on a domain they own.

## Pre-flight

Run these:

```bash
BP=/opt/buildersinabox/payload/scripts/biab-project
FIRST=$(jq -r '.project_name // empty' /var/lib/buildersinabox/state.json)
[ -n "$FIRST" ] && "$BP" status "$FIRST"
```

Check whether the first walk is finished: `status` says `complete` once its pull request is merged. If it's not — politely suggest they finish the first project first (`/first-project` to resume). They *can* do the finance app first if they want, but the first project is faster and teaches the loop before they add cloud accounts on top.

If they insist on doing the finance app first, proceed.

## Step 1 — Frame what they're about to build (90 seconds)

Tell them, in your own words, roughly:

> *FEAT-003 is a personal finance app. You drop your bank CSV at a webpage (or in a Slack channel), an AI categorises every transaction, a dashboard shows you where your money went, and you can ask it questions in plain language. There's also a Playwright scraper for the bank that doesn't give you a nice CSV.*
>
> *Unlike the coach, this one will live on a domain you own, in production, on infrastructure you control. That means we need to open one cloud account (where the app runs) and pick a domain.*
>
> *The full spec will land in your project folder in step 5, once you've picked a platform and a domain. Does that sound like the project you want?*

Wait for a yes before moving on.

## Step 2 — Choose a cloud platform

Lay out the three real options. Don't be exhaustive — opinions help here. Use roughly these words:

> *Three reasonable choices. I'll tell you which I'd pick and why.*
>
> **Cloudflare (my recommendation).** One account gives you: Workers (the API), Pages (the dashboard hosting), D1 (the database), R2 (file storage for CSVs and scraper screenshots), Workers AI (for categorisation), and a domain registrar with no markup. Free tier covers personal use easily. Deploy with one `wrangler` command. If you've never set up cloud infra before, this is the gentlest path.
>
> **Firebase (Google).** Hosting + Cloud Functions + Firestore + Auth. Excellent dev experience, but you'll be on two vendors (Firebase for infra, somewhere else for the domain). Good choice if you already know it.
>
> **GCP (Google Cloud Platform).** Cloud Run + Cloud SQL + Cloud Storage. Most powerful and flexible, also the most setup. Pick this if you specifically want to learn GCP, or if you might outgrow the simpler stacks later.

Ask: *"Which one do you want to use?"*

Wait for an answer. Don't push them off Cloudflare if they pick another — they have reasons.

## Step 3 — Open the chosen cloud account

### If they picked **Cloudflare**:

1. *"Go to https://dash.cloudflare.com/sign-up on your phone or laptop. Sign up with the email you want to use. Verify your email."*
2. *"Once you're in, you'll land on a dashboard with options like Workers, Pages, R2, D1 in the left sidebar. Don't click anything yet — just confirm you see them."*
3. Once they confirm: *"Now we install the Cloudflare CLI on the device. Run:"*
   ```bash
   npm install -g wrangler
   wrangler login
   ```
4. `wrangler login` opens a browser-flow URL. They open it on their phone, click "Allow", come back, see "logged in" in the terminal.

### If they picked **Firebase**:

1. *"Go to https://console.firebase.google.com on your phone or laptop. Sign in with a Google account you want to use (creating one if needed)."*
2. *"Create a new project — name it whatever, e.g. `<project_name>-finance`. Skip Google Analytics for now (you can add later)."*
3. Install the Firebase CLI:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```
4. `firebase login` opens a browser-flow URL. Same drill.

### If they picked **GCP**:

1. *"Go to https://console.cloud.google.com on your phone or laptop. Sign in with a Google account."*
2. *"GCP requires you to enable billing even for the free tier. They give you $300 credit to start. Add a card, accept terms, then create a new project named e.g. `<project_name>-finance`."*
3. Install the gcloud CLI:
   ```bash
   curl https://sdk.cloud.google.com | bash
   exec -l "$SHELL"
   gcloud init
   ```
4. `gcloud init` walks an interactive flow. Help them through it: pick the project they just made, pick a region (`europe-west1` is a fine default).

In every case: do not move on until the relevant CLI runs `<cli> whoami` (or equivalent) successfully.

## Step 4 — Pick and buy a domain

> *Your app needs a place to live. A domain costs roughly 10€/year and is yours forever as long as you renew it.*

Two paths:

**A. Buy via Cloudflare Registrar (cheapest, even if you're not deploying to Cloudflare):**

1. Go to https://dash.cloudflare.com → Domain Registration → Register Domains.
2. Search for what they want. Suggest combinations of `<their first name>finance.com`, `<project_name>.app`, etc.
3. Buy it. They'll pay the wholesale price + ~0.18€ ICANN fee.
4. The domain auto-attaches to their Cloudflare account.

**B. They already own a domain:**

1. Transfer it into Cloudflare (free, takes ~5 days) OR just change its nameservers to point to Cloudflare's.
2. The DNS panel on dash.cloudflare.com is where they'll add the records later.

Either way, confirm: *"What's the domain? I want to remember it for the rest of the walkthrough."* Save it mentally (the wizard doesn't persist this — you do).

## Step 5 — Create the project and build it

Now they have:
- A cloud account (their choice).
- The CLI for it, logged in.
- A domain (or one in the pipeline).

Create the finance app as its own project, with its spec waiting in `specs/draft/`. The `status` check makes this safe to run again: it only scaffolds a project that is not scaffolded yet, and the same word (`spec`, `confirm`, `build`, `publish`, `review`, `complete`) tells you which step of `/first-project` to continue at.

```bash
PROJECT=finance-dashboard
PDIR=~/ai-platform/projects/$PROJECT
[ "$(/opt/buildersinabox/payload/scripts/biab-project status "$PROJECT")" != scaffold ] || /opt/buildersinabox/payload/scripts/biab-project scaffold finance-dashboard finance-dashboard
cd "$PDIR"
[ -d .git ] || git init -b main
git rev-parse -q --verify HEAD >/dev/null 2>&1 || { git add -A && git commit -m "Initial commit from Builders in a Box"; }
/opt/buildersinabox/paseo/bin/biab-workspace "$PDIR" "$PROJECT"
```

If `scaffold` stops (exit 6 means a folder with that name already exists that is not this walk's), show its one-line message as it is and ask what they want. Then say roughly:

> *That's the setup done. The actual building is the spec in `specs/draft/`. We'll go wave by wave. Wave 1 is "schema + CSV import" — about an evening of work. By the end of it, you'll have a CSV you drop on a webpage and see rows in a database.*
>
> *Want to start now, or save it for tomorrow?*

If they say go: follow the build and publish steps of `/first-project` (spec in `specs/draft/`, the user confirms it, a branch, a pull request).

If they say later: stop here. The project and its spec are saved; next time they say `/second-project` and `status` says where you are.

## Tone

- This walkthrough has more setup than `/first-project`. Be patient.
- The cloud platform choice is a big-feeling decision for new users. Hold space for that — don't rush them.
- When something fails (and on cloud signups, it will — billing forms, verification emails, browser auth flows), debug calmly. The boss is not technical-by-default; treat this like sitting next to him at his laptop.
- Concrete commands. Always.
- No "best practices" lectures. The spec already has them.

## When NOT to use this skill

- The user hasn't done `/first-project` AND hasn't shipped FEAT-002. Suggest they do that first — the coach is a much smaller project to learn the rhythm.
- The user is far along on a different project. This skill is for the specific arc of "build the finance app from FEAT-003".
