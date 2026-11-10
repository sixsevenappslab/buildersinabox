# Builders in a Box — contributor guide

Guidance for coding agents (and humans) working in this repository.

## What this is

Builders in a Box turns any Ubuntu 24.04 machine (mini PC, homelab box, VPS) into
a personal dev server you reach from your phone — Claude Code (or another AI CLI)
running under a Paseo daemon, reachable over Tailscale, set up by one command:

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

Start with [`README.md`](README.md) for the product overview and
[`docs/architecture.md`](docs/architecture.md) for how the pieces fit together.

## Repository layout

- **`payload/`** — everything that ends up on the device. Bash + systemd + a
  console wizard. `install/*.sh` install the stack once (`48-user-content.sh`
  syncs missing core skills and additive hooks on `biab update`); `wizard/*.sh` run the
  guided first-boot setup (password, AI-CLI choice, Tailscale, SSH, scaffold,
  Paseo); `paseo/` is the pinned Paseo daemon (lockfile, units, launcher,
  watchdog, `biab-workspace`); `skills/<name>/SKILL.md` are the bundled skills
  (`manifest.tsv` defines `core`, `optional`, and optional `group` columns such
  as `handover` and `marketing`); `hooks/` are the local guard and session hooks;
  `docs/operating-rules.md` documents the six hard stops, git worktrees, and
  hooks-as-brakes vs. branch-protection-as-lock; `skeleton/` is the workspace
  copied into the user's home; `tutorial/` and the `/tutorial` skill own
  post-install onboarding.
- **`installer/`** — the bootstrap path. `installer/web/install.sh` is the
  `curl|bash` entrypoint that clones the repo and runs `payload/install.sh`.
- **`iso-builder/`** — repackages the Ubuntu 24.04 server ISO into a
  self-installing USB image (the optional "gift" edition).
- **`site/`** — the Cloudflare Pages landing page; `site/build.sh` also serves
  `install.sh` byte-identical to the bootstrap script.
- **`tools/`** — maintenance scripts (publishing, the personal-refs guard).

## How the device ends up (the model to keep accurate)

**Interface model (FEAT-035): Paseo is the default, SSH is the fallback.**

For a CLI that declares the `paseo-permissioned` capability (Claude Code,
Codex and Antigravity today) the box runs one pinned Paseo daemon as the root-owned system unit
`biab-paseo.service`, as the box user, bound to the tailnet address only, relay
off, with a per-box password in `/etc/buildersinabox/paseo.env`. The last wizard
step (`50-paseo.sh`) starts the user's first agent in the workspace
"BIAB · ai-platform" (cwd `~/ai-platform/`), opening `/tutorial`, and guides
pairing the Paseo app. `/tutorial` then walks them through GitHub auth and
creating their first project; `/first-project` registers a Paseo workspace named
"BIAB · <project>" through `biab-workspace` (idempotent by path). Nothing in a
skill tests a CLI name: they ask `biab-workspace --mode` (`paseo` for all three today), and
`paseo_supports_cli` in `payload/lib/paseo.sh` is the one place that decides.

Antigravity runs under Paseo through a provider BIAB declares itself (FEAT-041).
Paseo's own Antigravity plugin starts `agy` with `--dangerously-skip-permissions`
(BIAB never passes that flag), so `biab-paseo-run providers sync` disables it on
every box and, on an Antigravity box, writes the `antigravity-acp` provider whose
command is exactly `/usr/local/bin/agy acp`; each permission request reaches the
app. There is no opt-in, no `paseo-optin` capability and no consent state key
(`sudo biab paseo antigravity` is only a notice until 2027-04-30). The provider
settings are a file of the box user, as Claude Code's and Codex's permission
settings are: BIAB makes them safe at every daemon start (or the service refuses
to start) and `biab status` says when they changed since; it does not watch them
while the service runs. A CLI without the `paseo-permissioned` capability is
reached over SSH and runs no daemon: there is no tmux layer, and tmux is not
installed or mentioned by a new box (old boxes keep theirs, with a dated sunset in
`bib_paseo_migrate`). `install/46-paseo.sh` is gated on `paseo_supports_cli`.
Root never writes through a path the box user controls: `46-paseo.sh` refuses symlinks in `~/.biab` / `~/.bashrc.d` and writes there as the user (`paseo_prepare_user_state`). The SSH
fallback into the AI CLI also works on a Paseo box when the daemon is down, and
`biab status` prints the command. A watchdog (`biab-paseo-health.timer`)
restarts the daemon with a retry cap; `biab paseo pair|restart` are the user
verbs. There is no multi-window layout and no separate pairing service. Any
user-visible text on the Paseo path names BIAB as the origin and never uses
Paseo's name or icon as branding. If you touch onboarding copy, keep it
consistent with this.

**Shell & secret-read guard (FEAT-042, FEAT-044).** A CLI whose adapter declares `guard` gets a hook that
denies destructive shell commands, all built on one decision function
(`payload/hooks/guardrail-rules.sh`), plus the shared secret-read rules
(`payload/hooks/secret-guard-rules.sh`, pinned by `payload/hooks/tests/secret-guard-corpus.tsv`).
The tokens are `guard`, `guard-ask` and
`guard-exact`, never `hooks` (that one means Claude-format settings hooks).
`install/47-cli-guard.sh` is a stack step after 46, so `biab update` re-runs it; it
registers the guard as the box user, adding to the CLI's own config and never
removing the user's entries. On Antigravity (`guard guard-ask guard-exact`), that is
the `biab-guard` plugin in `~/.gemini/config/plugins/biab-guard` wiring
`biab-guardrail-agy.sh` (`run_command`), `biab-secret-guard-agy.sh`
(`run_command|read_file|view_file`), `biab-format-agy.sh` (`PostToolUse`), and
`biab-specs-agy.sh` (`SessionStart`). On Codex that is one entry in
`~/.codex/hooks.json` (`biab-guardrail-codex.sh`, calling both `biab_guard_decide`
and `biab_secret_decide "$cmd" "deny"`):
Codex runs it only after the owner approves it once (`codex`, then `/hooks`), BIAB
never approves it for them, and `biab status` says PENDING APPROVAL until then. The
entry's bytes are frozen (Codex trusts by hash). No root-owned lock, no `sudo`.
On OpenCode the guard is not a hook but `permission.bash` keys, generated from
`payload/hooks/guard-glob-templates.tsv` by `payload/hooks/opencode-guard.sh` and
appended (ask keys first, then deny keys: the last match wins) to the seed FEAT-040
writes in `~/.config/opencode/opencode.json`. It is declared `guard` only: a glob
cannot see a pipe or a quote, so it is PARTIAL and `biab status` lists what it does
not cover (pipes, quotes, `/*`, `bash -c`, any command that does not start with the
tool's own name; subagents are not confirmed; the `OPENCODE_CONFIG_CONTENT` and
`OPENCODE_PERMISSION` environment variables and a project `opencode.json` override it;
a few false positives are listed as `over` rows). Change the table, not the keys; `payload/test/cli-guard.sh` compares it
with the golden corpus, and `BIAB_GUARD_REAL=1` runs the same corpus through the real
`opencode` binary.

**Copy per CLI (FEAT-042 wave 5).** No user-facing sentence may promise a protection an
adapter does not declare. The README's "What each AI CLI gets" table sits between
`<!-- BIB:matrix:start -->` and `<!-- BIB:matrix:end -->` and is GENERATED: paste the output of
`bash payload/scripts/biab-guard matrix` when an adapter's capabilities change (the drift test,
CF-60 in `payload/test/cli-guard.sh`, is red until you do). The box's own README
(`payload/tutorial/desktop-readme.md`) keeps a `guard-<cli>` block per CLI, shown only while that
CLI declares `guard`, and a `no-guard` block for the rest, so declaring a guard for a CLI means
writing its `guard-<cli>` block in the same PR. `biab status` takes the night-shift reason from
`_ai_cli_night_shift_text__<cli>`. Do not write "the same on every CLI" about guards, confirm
prompts or the night shift: CF-62 and CF-63 look for it in the README, the site and SECURITY.md.

## Code conventions

- **Bash** for device scripts. `set -euo pipefail` always. Keep them readable
  and idempotent — install/wizard steps can re-run.
- All user-facing strings in **English** by default — this is for an
  international audience. (The bundled `sdd-*` skills are in English too.)
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
