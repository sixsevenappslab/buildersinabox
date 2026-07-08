# Maintaining

Maintainer-only notes. Not needed to *use* Builders in a Box.

## GitHub repo metadata

When the public repo (`sixsevenappslab/buildersinabox`) is set up, configure:

- **Description:** `Your own AI dev box. Plug in, code from your phone in 15 minutes. One-command install on any Ubuntu 24.04.`
- **Topics:** `homelab`, `tailscale`, `claude-code`, `ai`, `ubuntu`, `self-hosted`, `installer`, `developer-tools`, `mini-pc`, `tmux`
- **Website:** `https://buildersinabox.com`

## Publishing

The dev repo (`jesusmartincalvo/buildersinabox`) is the private workbench. The public repo gets a clean, fresh-history snapshot of the shippable tree — see FEAT-011's `tools/publish.sh` (extracts via `git archive HEAD`, runs the personal-refs guard, pushes a release snapshot). `specs/`, `payload/flavors/gift/maintainer/`, `BIZ-PLAN-LIFESTYLE.md`, and `TODO-NEXT-ISO.md` are `export-ignore`-d and never reach the public repo.

## CI

`.github/workflows/ci.yml` runs on every push/PR: `shellcheck`, `bash -n`, the personal-refs guard, and a `git archive` cleanliness check. The guard (`tools/check-no-personal-refs.sh`) is the durable protection against a personal-reference regression — keep its pattern list current.

## Landing page (Cloudflare Pages)

`site/` is a static landing + the served installer. One-time setup in the Cloudflare dashboard:

1. Pages → Create project → connect the public repo (`sixsevenappslab/buildersinabox`).
2. Build command: `bash site/build.sh`. Output directory: `site`.
3. Custom domain: bind `buildersinabox.com` (apex). DNS is already on Cloudflare.
4. Enable Web Analytics (cookieless) if you want install-attempt counts.

`site/build.sh` copies `installer/web/install.sh` → `site/install.sh` and fails the build if they drift, so `buildersinabox.com/install.sh` is always byte-identical to the repo. `site/_headers` forces `text/plain` + a 5-minute cache on `/install.sh`.

Post-deploy smoke: `curl -sI https://buildersinabox.com/install.sh` → `200` + `text/plain`; `curl -fsSL https://buildersinabox.com/install.sh | diff - installer/web/install.sh` → no diff.

## Email capture (Resend)

The landing form posts to `/subscribe`, served by the Pages Function
`functions/subscribe.js`, which adds the address to a Resend audience.
One-time setup (~10 min, no mailboxes involved):

1. **Resend account** — sign up at resend.com with any email (the account
   email does NOT need to be @buildersinabox.com). Free tier: 3k emails/month,
   1k audience contacts — plenty for the launch gate.
2. **Verify the domain** — Resend → Domains → Add `buildersinabox.com`. It
   gives you 3-4 DNS records (DKIM TXT + SPF/MX on a `send.` subdomain);
   add them in the Cloudflare DNS dashboard. This lets you SEND as
   `hello@buildersinabox.com` without any mailbox existing.
3. **Receive replies (optional but recommended)** — Cloudflare → Email →
   Email Routing: forward `hello@buildersinabox.com` to your real inbox.
   Pure forwarding, free, no mailbox. Routing's MX lives on the apex;
   Resend's MX lives on `send.` — they don't conflict.
4. **Audience + API key** — Resend → Audiences → note the default audience ID.
   API Keys → create one. Then Cloudflare → Pages project → Settings →
   Environment variables (Production, encrypted):
   `RESEND_API_KEY`, `RESEND_AUDIENCE_ID`. Redeploy.

Smoke test: `curl -s -X POST https://buildersinabox.com/subscribe -H 'accept: application/json' -H 'content-type: application/json' -d '{"email":"you@example.com"}'` → `{"ok":true}` and the contact appears in the Resend audience.
