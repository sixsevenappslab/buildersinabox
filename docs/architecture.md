# Architecture

How Builders in a Box is put together, for contributors.

## Components

- **`payload/`** — everything that runs on the device. Bash + systemd + a console TUI wizard.
  - `payload/install.sh` — the entry point. Installs the stack, then runs the wizard. Flags: `--non-interactive`, `--update`, `--uninstall`, `--selftest`, `--flavor=<default|gift>`, `--skip-wizard`, `--ai-cli`.
  - `payload/install/*.sh` — per-tool install scripts (base packages, tmux, Tailscale, GitHub CLI, the AI CLI, SSH hardening). Idempotent.
  - `payload/wizard/*.sh` — the console wizard steps in run order, orchestrated by `wizard/run.sh`. Handles password, Tailscale login, the phone bridge, AI CLI login, workspace scaffold, and tmux launch.
  - `payload/lib/` — shared helpers. `common.sh` (logging, state machine, OS checks, `BIB_USER`/`BIB_NAME`/`BIB_FLAVOR` resolvers), `prompt.sh` (TUI), `oauth.sh`, `ai-cli.sh`.
  - `payload/skills/` — Claude Code skills installed into the user's `~/.claude/skills/`. `manifest.tsv` declares which are installed by default (`core`) vs opt-in (`optional`, installed on demand with `biab add <name>`). Includes the SDD workflow (`sdd-*`, core), the `quota` usage coach (core), and the optional `incident` log.
  - `payload/hooks/` — Claude Code hooks registered into `~/.claude/settings.json` by the scaffold (skipped on Antigravity boxes, which don't use this format). Registration is additive for every event — guardrails (`PreToolUse`/`PostToolUse`/`Stop`) and context injectors (`UserPromptSubmit` quota nudge, `SessionStart` pending-specs reminder) alike. A hook you already had is never removed or replaced: ours runs alongside it, and re-running the scaffold never adds a duplicate. Every hook is fail-open: it exits 0 on every path and degrades to a no-op without `jq`, so it can never block a session. `payload/statusline/` holds the optional weekly-spend status line, installed only when the user has none.
  - `payload/pack/` — heavyweight, opt-in capability packs (system packages, a dedicated user, a CLI on PATH — more than `biab add`'s skill-copy). Ships in the tarball but never auto-installs; `biab pack {list,add,remove} <name>` drives `payload/pack/<name>/{install,uninstall}.sh`. See "Browser pack" below.
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

## Browser pack (opt-in, FEAT-017)

`biab pack add browser` installs a headless-Chromium capability the agent can
use to read/click/fill/screenshot live web pages, without requiring a
desktop. Absent by default — not in `payload/skills/`, not in
`manifest.tsv`, not called from `payload/install.sh`. The pack lives at
`payload/pack/browser/` (installer, driver, CLI, skill, tests).

Security model: the engine runs as a dedicated system user (`biab-browser`,
`nologin`, no sudo, no access to the operator's `~/.ssh` or project files),
with a fresh ephemeral profile per run (no inherited logins) unless the
operator explicitly opts into a named persisted profile. Runs are
serialized (one browser at a time) to avoid OOM pressure on small boxes.

**Engine choice (sandbox):** the default engine is full Chromium (~646MB),
not `chromium-headless-shell` (~270MB) — the original spike choice.
Real testing on Ubuntu 24.04 found headless-shell does not ship Chromium's
setuid sandbox helper, and on stock Ubuntu 24.04
(`kernel.apparmor_restrict_unprivileged_userns=1`), the sandbox cannot
initialise without it, so the default path aborted on every real box.
Full Chromium ships its own setuid sandbox helper (`chrome_sandbox`,
`chown root; chmod 4755`, installed for both the default and
`--headful-xvfb` paths), so it works out-of-the-box with no escape hatch —
decided by Jesús 2026-07-12 (FEAT-017 §2.9 addendum), accepting the larger
footprint to keep the "never `--no-sandbox` by default" boundary. Full
Chromium also needs OS-level shared libraries a bare Ubuntu 24.04 server
doesn't have (GTK/ATK/X11/font packages) — `install.sh` runs
`playwright install-deps chromium` (as root, apt) to cover this; real VM
measurement puts peak RSS at ~1.0-1.2GB/run, up from the spike's ~700MB
(headless-shell). The driver (`driver/browse.mjs`) still deliberately does not use Playwright's
own `launch()`/`launchPersistentContext()` convenience API — real testing
found it silently appends `--no-sandbox` when the sandbox can't start, with
nothing in Playwright's source that a static grep would catch. Instead the
driver spawns Chromium itself with a fully self-authored, audited argument
list and **aborts (fail-closed, exit 3)** if the sandbox can't start for any
reason, rather than degrading silently. See the FEAT-017 implementation
notes and `payload/pack/browser/skill/browser/SKILL.md` for the full story.

## Conventions

- Bash with `set -euo pipefail`. Idempotent scripts. English-only user-facing strings.
- `shellcheck` clean. `tools/check-no-personal-refs.sh` clean (enforced in CI).
- Commit format: `feat:`, `fix:`, `docs:`, `refactor:`.
