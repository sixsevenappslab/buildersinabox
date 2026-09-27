# Builders in a Box — contributor guide

Guidance for coding agents (and humans) working in this repository.

## What this is

Builders in a Box turns any Ubuntu 24.04 machine (mini PC, homelab box, VPS) into
a personal dev server you reach from your phone — Claude Code (or another AI CLI)
running in `tmux`, reachable over Tailscale, set up by one command:

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

Start with [`README.md`](README.md) for the product overview and
[`docs/architecture.md`](docs/architecture.md) for how the pieces fit together.

## Repository layout

- **`payload/`** — everything that ends up on the device. Bash + systemd + a
  console wizard. `install/*.sh` install the stack once; `wizard/*.sh` run the
  guided first-boot setup (password, AI-CLI choice, Tailscale, SSH, scaffold,
  tmux); `skills/<name>/SKILL.md` are the bundled Claude Code / Antigravity skills;
  `skeleton/` is the workspace copied into the user's home; `tutorial/` and the
  `/tutorial` skill own post-install onboarding.
- **`installer/`** — the bootstrap path. `installer/web/install.sh` is the
  `curl|bash` entrypoint that clones the repo and runs `payload/install.sh`.
- **`iso-builder/`** — repackages the Ubuntu 24.04 server ISO into a
  self-installing USB image (the optional "gift" edition).
- **`site/`** — the Cloudflare Pages landing page; `site/build.sh` also serves
  `install.sh` byte-identical to the bootstrap script.
- **`tools/`** — maintenance scripts (publishing, the personal-refs guard).

## How the device ends up (the model to keep accurate)

After setup the user lands in **one** tmux session named `ai-platform`
(cwd `~/ai-platform/`) running their chosen AI CLI, which opens `/tutorial`.
`/tutorial` walks them through GitHub auth and creating their first project;
`/first-project` then creates an **independent** tmux session per project, so
each shows up as its own remote session in the Claude Code app. There is no
multi-window layout and no separate pairing service — both were earlier designs
that were dropped. If you touch onboarding copy, keep it consistent with this.

## Code conventions

- **Bash** for device scripts. `set -euo pipefail` always. Keep them readable
  and idempotent — install/wizard steps can re-run.
- All user-facing strings in **English** by default — this is for an
  international audience. (The bundled `sdd-*` skills are still Spanish; that
  translation is deliberately deferred.)
- Commit format: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`.

## Working in this repo

- Quality gate: PR always, CI green before merge. CI runs shellcheck, a
  personal-refs guard, `bash -n`, and an archive-cleanliness check.
- SDD (spec-driven development) skills ship **by default** on a user's box
  (core since v0.2); using them is still optional here too — small fixes
  don't need a spec.
- Anything in `.gitattributes` marked `export-ignore` (maintainer docs, specs)
  never ships in the published tree; don't put user-facing content there.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a PR.
