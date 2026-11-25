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

If you touch the installer or the uninstaller, run the ownership-contract driver
before opening the PR — it asserts that we only remove what is ours and put back
what we changed:

```bash
bash payload/test/uninstall-contract.sh
```

No root, no network, no VM: it sources `install.sh` as a library and points the
whole teardown at a temporary directory. **Never run it with `sudo`** — it
refuses to start as root, because under root a missed path prefix would delete
from your real `/etc`.

## Conventions

- `set -euo pipefail` at the top of every script.
- Scripts must be **idempotent** — safe to run twice.
- **English and Spanish** in user-facing strings (FEAT-045). No personal names, employer references, or real tokens — the guard enforces this. Maintainer docs (this file, `docs/`, `CHANGELOG.md`) stay English.

### Adding or changing a message

Text the owner reads while setting up or using the box lives in the message
catalogs, not in the scripts: `payload/i18n/en/<area>.sh` and
`payload/i18n/es/<area>.sh`, one line `BIB_MSG[area.topic.detail]='printf format'`
per message, printed with `msg area.topic.detail [args]`.

1. Add the same key to both files, with the same `%s` placeholders in the same
   order and the same commands, flags and paths (those stay literal; so do skill
   names, the Paseo workspace and agent titles and the labels of third-party apps).
2. Spanish is neutral, tuteo, with no regionalisms; wrap it to the same 60 columns
   as the English and never pad it with `printf '%-Ns'`. Glossary: header of
   `payload/i18n/es/wizard.sh`.
3. A new section or per-CLI sentence of the box README goes in
   `payload/tutorial/desktop-readme.md` and `desktop-readme.es.md` in the same PR.
4. Run `bash payload/test/i18n.sh` (add `BIB_I18N_NO_MUTANTS=1` for a fast pass). It
   fails on a key in one language only, a different placeholder or literal, a
   Spanish value left in English, a screen over the width limit, and a raw English
   sentence in a migrated script (escape: `# i18n-ok: <reason>` for logs and
   maintainer diagnostics). If English changes on purpose, regenerate the golden
   transcripts as `payload/README.md` says and say so in the PR.
- Commit messages: `feat:`, `fix:`, `docs:`, `refactor:`.

## Add your AI CLI (~1 hour)

The payload never branches on a CLI name — every supported CLI is one
self-contained adapter block in [`payload/lib/ai-cli.sh`](payload/lib/ai-cli.sh).
Adding one is three steps:

1. Add its identifier to `BIB_SUPPORTED_AI_CLIS`.
2. Write the adapter block: a props function (`AI_CLI_DISPLAY_NAME`,
   `AI_CLI_COMMAND`, `AI_CLI_INSTALL_SCRIPT`, `AI_CLI_SKILLS_DIRS`, `AI_CLI_CAPABILITIES`),
   the owner-facing text of the CLI as catalog keys in `payload/i18n/<en|es>/cli.sh`
   (`cli.hint.<id>`, the line the chooser shows, which must say what its guard and night shift are;
   `cli.account.<id>`, what the user needs in order to sign in; `cli.night.<id>` when it has no night shift),
   plus the behaviour functions:
   `paseo_provider`, `initial_prompt`, `login_verify_cmd`, `login_run`,
   `login_failure_hint`, `seed_settings`.
3. Write one install script under `payload/install/`.

To run under the Paseo daemon an adapter also adds a `_ai_cli_paseo_provider__<id>`
function (the id Paseo uses) and declares the `paseo-permissioned` capability,
which means Paseo can run it with its normal permission prompts. Without the
capability the CLI is reached over SSH and no daemon runs for it; never declare it
for a provider that forces `--dangerously-skip-permissions`. If Paseo's built-in
provider for a CLI does that, declare your own ACP provider as `antigravity-acp`
does (see `biab-paseo-run providers sync`).

Everything else — the installer's CLI chooser, the wizard's login step, the
launcher (the Paseo agent run), the workspace scaffold, the wiring smoke and its CI job —
derives from the registry automatically. The four shipped adapters are the
reference, each exercising a different corner of the contract: `claude`
(hooks, statusline, remote-control capability), `antigravity` (multiple
skills dirs), `codex` (native `~/.agents/skills`, headless device auth), `opencode` (native `~/.agents/skills`, a pinned release binary, login by pasted key, permissions seeded and re-checked: see `_ai_cli_seed_settings__opencode`).
`payload/test/wiring-smoke.sh` will catch a hole in a new adapter.

## What goes where

See [`docs/architecture.md`](docs/architecture.md). In short: device code in `payload/`, the USB image in `iso-builder/`, the hosted bootstrap in `installer/web/`, maintainer tools in `tools/`.

By contributing you agree your work is licensed under the project's [MIT License](LICENSE).
