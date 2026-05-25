# Builders in a Box

> Plug a USB. Boot a mini PC. Code from your phone.

Builders in a Box turns any x86 mini PC into a personal, remote-accessible development server in a single boot. From bare metal to coding with Claude Code on your phone — no manual configuration.

**Status:** 🚧 Early development. Targeting first working USB → mobile flow in the coming weeks.

---

## What it does

You buy a mini PC and a Builders in a Box USB. You plug the USB, connect Ethernet, power it on, and walk away. ~10 minutes later you scan the QR code on the USB with your phone and:

1. The mini PC has Ubuntu Server installed.
2. You log into **your** Tailscale account from the phone — the mini PC joins your tailnet.
3. You log into **your** Claude Code account.
4. You log into **your** GitHub account (so the device can clone, commit, and push on your behalf).
5. You pick a name for your first project. The device scaffolds the workspace.
6. You open Termius on your phone, tap the pre-configured host, and you land in a `tmux` session with **three windows already running Claude Code**:
   - `platform` — at `~/ai-platform/`, for changes to the platform itself.
   - `<your-project-name>` — at `~/ai-platform/projects/<your-project-name>/`, ready to start building.
   - `stratops` — at `~/ai-platform/stratops/`, your personal strategy & ops mesa (OKRs, roadmap, notes).

That's it. You have a personal cloud dev environment, on hardware you own, with Claude Code running on three contexts simultaneously, accessible from anywhere.

## Why

- **Own your dev environment.** No vendor lock-in, no monthly fees scaling with usage, no data leaving hardware you control.
- **Mobile-first development.** With Claude Code, "coding from your phone" stops being a joke. A mini PC + Tailscale + Termius makes it real.
- **Zero-config onboarding.** The hardest part of self-hosting is the first boot. We solve that with a USB and a QR.

## How it works (high level)

```
┌─────────────┐    Ethernet    ┌──────────────┐    OAuth flows    ┌────────────┐
│   USB stick │──────────────▶│   Mini PC    │◀─────────────────▶│   Phone    │
│  (autoinstall│              │ (Ubuntu+stack)│   (via pairing    │ (Tailscale,│
│   + QR code) │              │              │    web service)   │   Termius) │
└─────────────┘                └──────────────┘                    └────────────┘
                                      │
                                      ▼
                              ┌───────────────┐
                              │  Tailscale    │
                              │  Claude Code  │
                              │  tmux ready   │
                              └───────────────┘
```

The USB carries:
- An Ubuntu Server 24.04 autoinstall image.
- A unique device token (also printed as a QR code).
- A post-install script that sets up Tailscale, Claude Code, tmux, and a clean development workspace.

A small pairing web service (hosted, but also open source for self-hosters) bridges the headless mini PC and the user's phone during the OAuth flows for Tailscale and Claude Code login.

## Tiers

| Tier | What you get | Who flashes the USB |
|---|---|---|
| **Hardware bundle** (planned) | Mini PC + pre-made USB + access to hosted pairing service | We do |
| **USB only** (planned) | Pre-made USB + access to hosted pairing service | We do |
| **DIY / self-hosted** | This repo. Build your own image, run your own pairing service | You do |

## Roadmap

- [ ] Manual bootstrap script working on a real mini PC
- [ ] Tailscale + Claude Code + GitHub OAuth device flows validated from mobile
- [ ] Three-window tmux + Claude Code UX from Termius on phone validated
- [ ] Workspace skeleton (ai-platform, projects/, stratops) scaffolding
- [ ] Pairing backend MVP (including project-name capture and GitHub login bridge)
- [ ] USB autoinstall image generator
- [ ] First end-to-end: fresh USB → working remote dev environment from phone
- [ ] Hardware recommendations and tested configurations
- [ ] Public release

## Repo layout

```
buildersinabox/
├── payload/             # Everything that goes on the device BESIDES Ubuntu
│   ├── bootstrap.sh        # (coming) main first-boot script
│   ├── install/            # (coming) per-tool install sub-scripts
│   ├── systemd/            # (coming) systemd units
│   ├── tmux/               # (coming) tmux config + session bootstrap
│   ├── skills/             # Claude Code skills (SDD workflow + utilities)
│   ├── templates/          # FEAT templates (starter + full), CLAUDE.md template
│   ├── config/             # Example configs (personas, project matrix)
│   ├── skeleton/           # Workspace skeleton copied to user's home
│   └── docs/               # SDD workflow, lifecycle, adoption guide
├── iso-builder/         # Tool: Ubuntu ISO + payload → bootable USB image
├── pairing/             # Web service bridging device ↔ phone OAuth (later)
└── README.md
```

A DIY user only needs `payload/` — install Ubuntu manually, clone the repo, run `payload/bootstrap.sh`. `iso-builder/` and `pairing/` are convenience layers for the USB and hosted-service tiers.

## License

TBD. Likely **AGPL-3.0** for the pairing backend and **MIT** for everything else, so anyone can build and ship a derived device freely, while improvements to the hosted service flow back to the community.

## Contact

This project is currently a solo effort by [@hezumartin](https://github.com/hezumartin). Reach out if you want to follow progress, contribute, or pilot the first hardware.
