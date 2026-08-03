# Contributing to Builders in a Box

Thanks for wanting to help. This is a Bash-first project that provisions Ubuntu machines, so most changes are shell scripts, wizard copy, or docs.

## Before you start

- Open an issue describing the change if it's non-trivial, so we can agree on the approach.
- Keep changes focused. One concern per PR.

## Local checks

Run these before opening a PR — they're exactly what CI runs:

```bash
# Lint every shell script (warning level)
find . -name '*.sh' -not -path './.git/*' -not -path './payload/flavors/gift/maintainer/*' -print0 \
  | xargs -0 shellcheck -S warning

# Syntax-check the entry points
bash -n payload/install.sh payload/lib/common.sh

# Guard: no personal references in the shippable tree
bash tools/check-no-personal-refs.sh
```

## Testing on a real machine

The installer touches systemd, apt, and the network, so it needs a real Ubuntu 24.04 (a fresh VM via [Multipass](https://multipass.run) or LXD is ideal — not a plain container). A safe smoke run that installs the stack without the OAuth wizard:

```bash
BIB_USER=ubuntu BIB_NAME='' BIB_FLAVOR=default BIB_AI_CLI=claude BIB_OAUTH_MOCK=1 \
  sudo -E /opt/buildersinabox/payload/install.sh --non-interactive --skip-wizard
```

`payload/install.sh --uninstall` cleanly removes everything BIAB-owned (and leaves your home, Tailscale, GitHub, and Claude auth untouched), so you can iterate.

## Conventions

- `set -euo pipefail` at the top of every script.
- Scripts must be **idempotent** — safe to run twice.
- **English only** in user-facing strings. No personal names, employer references, or real tokens — the guard enforces this.
- Commit messages: `feat:`, `fix:`, `docs:`, `refactor:`.

## Add your AI CLI (~1 hour)

The payload never branches on a CLI name — every supported CLI is one
self-contained adapter block in [`payload/lib/ai-cli.sh`](payload/lib/ai-cli.sh).
Adding one is three steps:

1. Add its identifier to `BIB_SUPPORTED_AI_CLIS`.
2. Write the adapter block: a props function (`AI_CLI_DISPLAY_NAME`,
   `AI_CLI_CHOICE_HINT`, `AI_CLI_COMMAND`, `AI_CLI_INSTALL_SCRIPT`,
   `AI_CLI_SKILLS_DIRS`, `AI_CLI_CAPABILITIES`) plus five behaviour functions:
   `launch_cmd`, `login_verify_cmd`, `login_run`, `login_failure_hint`,
   `seed_settings`.
3. Write one install script under `payload/install/`.

Everything else — the installer's CLI chooser, the wizard's login step, the
tmux launcher, the workspace scaffold, the wiring smoke and the CI matrix —
derives from the registry automatically. The three shipped adapters are the
reference, each exercising a different corner of the contract: `claude`
(hooks, statusline, remote-control capability), `antigravity` (multiple
skills dirs), `codex` (native `~/.agents/skills`, headless device auth).
`payload/test/wiring-smoke.sh` will catch a hole in a new adapter.

## What goes where

See [`docs/architecture.md`](docs/architecture.md). In short: device code in `payload/`, the USB image in `iso-builder/`, the hosted bootstrap in `installer/web/`, maintainer tools in `tools/`.

By contributing you agree your work is licensed under the project's [MIT License](LICENSE).
