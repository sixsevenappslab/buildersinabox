# Builders in a Box — Claude Code instructions

## Project overview

USB-based zero-touch provisioning for a personal dev server. Target user: a developer who buys a mini PC and a Builders in a Box USB and wants to be coding remotely from their phone within 15 minutes of plugging it in.

See `README.md` for the full vision.

## Current phase

**Phase 0 — pre-hardware.** The mini PC hasn't been bought yet. Until it arrives, work is limited to:
- Designing the architecture and contracts (pairing backend API, device state machine, USB token format).
- Drafting scripts that we'll execute manually on the mini PC once it arrives.
- Researching hardware candidates and Ubuntu Server 24.04 autoinstall specifics.

**Do not write code that requires a running mini PC to validate.** Anything device-side has to wait until we can test it on real hardware.

## Architecture summary

Three components, three repos-within-the-repo:

1. **`firmware/`** — runs on the mini PC after Ubuntu is installed. Bash + systemd. Handles Tailscale OAuth device flow, Claude Code OAuth device flow, tmux session setup, and posting state to the pairing backend.

2. **`pairing-backend/`** — small web service (likely Cloudflare Worker + KV/D1). Receives state updates from devices and serves a mobile-friendly setup page to users. Stateless except for short-lived pairing sessions.

3. **`installer/`** — generates the bootable USB image. Ubuntu Server 24.04 autoinstall with embedded device token, post-install hook that drops `firmware/` onto the system and enables the first-boot unit.

## Key design decisions (locked)

- **Ethernet first, WiFi later.** First boot assumes wired connection. WiFi provisioning (hotspot dance) is a v2 problem.
- **OAuth device flows, not embedded credentials.** The user logs into *their own* Tailscale and Claude Code accounts. We never see their credentials. The mini PC reports OAuth URLs to the pairing backend; the phone retrieves them and the user completes login there.
- **One unique token per USB.** Generated at flash time, printed as QR on the USB sticker. The token is the only secret the device knows about itself.
- **Open source.** AGPL for the pairing backend, MIT for firmware and installer. The commercial moat is hardware + hosted service, not code.

## Code conventions for this project

- **Bash** for firmware scripts. Keep them readable, `set -euo pipefail` always.
- **TypeScript** for the pairing backend (Cloudflare Workers).
- **Plain HTML + minimal JS** for the pairing web page. Mobile-first. No SPA framework.
- All user-facing strings in **English** by default — this is for an international audience.

## What to ask before building

- Hardware target: which mini PC are we testing on? Affects autoinstall config (UEFI vs BIOS, disk layout, NIC drivers).
- Pairing backend hosting: Cloudflare Workers vs self-hosted Node? Affects code style and dependencies.
- USB flashing process: do we mass-flash with unique tokens, or generate per-USB on demand?

## Out of scope (for now)

- WiFi-only setup
- Non-x86 hardware (Raspberry Pi etc.)
- Multi-user devices
- Web-based IDE (the whole point is mobile SSH into tmux + Claude Code)
- Anything that requires bundling Anthropic credentials
