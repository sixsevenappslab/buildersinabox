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

1. **`payload/`** — runs on the mini PC after Ubuntu is installed (or applied manually on any Ubuntu by DIY users). Bash + systemd + a console TUI wizard. Handles three OAuth device flows (Tailscale, Claude Code, GitHub via `gh auth login`) by printing URLs to the console for the user to open on their phone, prompts for project name on the console, scaffolds the workspace skeleton (`ai-platform/{projects,stratops}/`), sets up three tmux windows each running Claude Code, and configures SSH for remote access.

2. **`pairing/`** — DEFERRED to v2. Small web service (Cloudflare Worker) that would relay OAuth URLs from a headless device to the user's phone. In v1, we skip this entirely: the user connects monitor+keyboard for the ~15 min wizard. Keep the folder with a README pointing at v2 scope; do not implement.

3. **`installer/`** — generates the bootable USB image. Ubuntu Server 24.04 autoinstall with embedded device token, post-install hook that drops `firmware/` onto the system and enables the first-boot unit.

## Key design decisions (locked)

- **Ethernet first, WiFi later.** First boot assumes wired connection. WiFi provisioning is a v2 problem.
- **v1 = monitor + keyboard for first boot.** The user connects HDMI + USB keyboard to the mini PC for the ~15 min setup wizard (a TUI shell script). Tailscale, GitHub and Claude Code OAuth device flows run on the console — the user reads URLs from the screen and completes login on their phone or laptop. **No pairing backend in v1.** This eliminates Cloudflare Worker, domain, QR-with-token, mobile polling page, deep linking — all deferred to v2.
- **OAuth device flows, not embedded credentials.** The user logs into *their own* Tailscale, Claude Code, and GitHub accounts. We never see credentials. v1: URLs shown on the mini PC's screen. v2: relayed via pairing backend to phone.
- **Final state = three tmux windows with Claude Code.** After setup, the user lands (via Termius SSH from phone) inside a tmux session with three windows: `platform` (cwd `~/ai-platform/`), `<project-name>` (cwd `~/ai-platform/projects/<project-name>/`), and `stratops` (cwd `~/ai-platform/stratops/`). Each window has Claude Code running. The project name is captured from the user during the setup wizard.
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
