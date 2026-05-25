# pairing/

Web service that bridges a headless devbox and a user's phone during the OAuth-heavy first-boot setup (Tailscale, Claude Code, GitHub).

## Why it exists

A fresh devbox is headless and has no UI. The user has a phone but can't directly interact with the device until SSH is available. OAuth device flows require a browser interaction.

The pairing service is the bridge:

1. The devbox boots, hits `POST /devices/:token/state` with its current state and any pending OAuth URLs.
2. The user scans the QR on the USB → opens `https://pair.buildersinabox.com/p/:token` on their phone.
3. The phone polls device state and shows the user:
   - OAuth links to open (for Tailscale, GitHub, Claude Code).
   - A field to enter the project name they want to scaffold.
   - The final Tailscale hostname + deep link to Termius once the device is ready.

The pairing service never sees credentials — only the OAuth handoff URLs, which are short-lived and tied to the user's own accounts.

## Status

⏸ **Deferred to v2.** In v1, the user connects monitor + keyboard to the mini PC for a ~15 min on-console setup wizard. OAuth URLs appear on the screen; the user opens them on their phone or laptop manually. This eliminates the need for any hosted service in v1.

The pairing service becomes relevant in v2, when we want the device to be fully headless from boot — useful for the commercial hardware tier, where the customer never touches the mini PC's I/O.

**Do not implement before v1 ships.**

## Stack (planned)

- Cloudflare Worker (TypeScript) — backend
- Cloudflare KV or D1 — short-lived pairing state (auto-expires after 24h)
- Mobile-first HTML/CSS/JS — no SPA framework

## Self-hosting

The pairing backend is AGPL-3.0. If you want to run your own (instead of using the hosted `pair.buildersinabox.com`), you can deploy the Worker to your own Cloudflare account and point the devbox at it via `PAIRING_HOST` in the firmware config.
