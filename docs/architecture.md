# Architecture

How Builders in a Box is put together, for contributors.

## Components

- **`payload/`** — everything that runs on the device. Bash + systemd + a console TUI wizard.
  - `payload/install.sh` — the entry point. Installs the stack, then runs the wizard. Flags: `--non-interactive`, `--update`, `--uninstall`, `--selftest`, `--flavor=<default|gift>`, `--skip-wizard`, `--ai-cli`.
  - `payload/install/*.sh` — per-tool install scripts (base packages, tmux, Tailscale, GitHub CLI, the AI CLI, SSH hardening). Idempotent.
  - `payload/wizard/*.sh` — the console wizard steps in run order, orchestrated by `wizard/run.sh`. Handles password, Tailscale login, the phone bridge, AI CLI login, workspace scaffold, and tmux launch.
  - `payload/lib/` — shared helpers. `common.sh` (logging, state machine, OS checks, `BIB_USER`/`BIB_NAME`/`BIB_FLAVOR` resolvers), `prompt.sh` (TUI), `oauth.sh`, `ai-cli.sh`.
  - `payload/skills/` — Claude Code skills installed into the user's `~/.claude/skills/`. `manifest.tsv` declares which are installed by default (`core`) vs opt-in (`optional`).
  - `payload/flavors/{default,gift}/` — copy + banner sets. `default` ships neutral copy; `gift` is the personalised welcome for handing someone a ready box.
  - `payload/examples/` — example FEAT specs the user can read or copy.
  - `payload/skeleton/` — the workspace skeleton copied to the user's home.
  - `payload/profile.d/biab-firstboot.sh` — login trigger that runs the wizard on first boot (used by the ISO autoinstall flow).

- **`iso-builder/`** — repackages an Ubuntu 24.04 Server ISO with cloud-init autoinstall + the payload, producing a self-installing USB image (the gift/USB edition).

- **`installer/web/`** — the hosted bootstrap served at `buildersinabox.com/install.sh` (clones the repo + runs `payload/install.sh`).

- **`tools/`** — maintainer scripts. `check-no-personal-refs.sh` is the guard that keeps personal references out of the shippable tree (also run in CI).

## State machine

The installer tracks progress in `/var/lib/buildersinabox/state.json` (schema v2): the resolved operator (`bib_user`), display name (`bib_name`), `flavor`, chosen `ai_cli`, and per-phase completion flags. Every step checks the state and skips if already done, so installs and `--update` are idempotent. Logs go to `/var/log/buildersinabox/bootstrap.log` (ISO-8601 UTC).

## Two install paths

- **`curl | bash` on existing Ubuntu** — the primary path. An interactive operator runs one command; the bootstrap clones the repo and runs `install.sh` inline.
- **USB autoinstall** — for the gift/USB edition. cloud-init installs Ubuntu unattended, drops the payload, and the first-boot trigger runs the wizard. No interactive operator at install time, which is why this path uses autologin + `firstboot.pending`.

## Conventions

- Bash with `set -euo pipefail`. Idempotent scripts. English-only user-facing strings.
- `shellcheck` clean. `tools/check-no-personal-refs.sh` clean (enforced in CI).
- Commit format: `feat:`, `fix:`, `docs:`, `refactor:`.
