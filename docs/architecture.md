# Architecture

How Builders in a Box is put together, for contributors.

## Components

- **`payload/`** — everything that runs on the device. Bash + systemd + a console TUI wizard.
  - `payload/install.sh` — the entry point. Installs the stack, then runs the wizard. Flags: `--non-interactive`, `--update`, `--uninstall`, `--selftest`, `--flavor=<default|gift>`, `--skip-wizard`, `--ai-cli`.
  - `payload/install/*.sh` — per-tool install scripts (base packages, Tailscale, GitHub CLI, the AI CLI, SSH hardening, the Paseo daemon). Idempotent.
  - `payload/wizard/*.sh` — the guided, resumable console/SSH wizard, orchestrated by `wizard/run.sh`. Its six visible milestones are password, private connection, remote handoff, AI login, workspace, and the first agent in Paseo; SSH hardening remains an internal safety step.
  - `payload/lib/` — shared helpers. `common.sh` (logging, state machine, OS checks, `BIB_USER`/`BIB_NAME`/`BIB_FLAVOR` resolvers), `prompt.sh` (TUI), `oauth.sh`, `ai-cli.sh`.
  - `payload/skills/` — Claude Code skills installed into the user's `~/.claude/skills/`. `manifest.tsv` declares which are installed by default (`core`) vs optional (`optional`, installed on demand with `biab add <name>`). Includes the SDD workflow (`sdd-*`, core), the `quota` usage coach (core), and the optional `incident` log.
  - `payload/hooks/` — Claude Code hooks registered into `~/.claude/settings.json` by the scaffold (skipped on the other boxes, which don't use this format; their shell-command guard, where they have one, is registered by the stack step `install/47-cli-guard.sh` in the CLI's own config: see "What each AI CLI gets" in the README). Registration is additive for every event — guardrails (`PreToolUse`/`PostToolUse`/`Stop`) and context injectors (`UserPromptSubmit` quota nudge, `SessionStart` pending-specs reminder) alike. A hook you already had is never removed or replaced: ours runs alongside it, and re-running the scaffold never adds a duplicate. Every hook is fail-open: it exits 0 on every path and degrades to a no-op without `jq`, so it can never block a session. `payload/statusline/` holds the optional weekly-spend status line, installed only when the user has none.
  - `payload/pack/` — heavyweight, optional capability packs (system packages, a dedicated user, a CLI on PATH — more than `biab add`'s skill-copy). Ships in the tarball but never auto-installs; `biab pack {list,add,remove} <name>` drives `payload/pack/<name>/{install,uninstall}.sh`. See "Browser pack" below.
  - `payload/flavors/{default,gift}/` — copy + banner sets. `default` ships neutral copy; `gift` is the personalised welcome for handing someone a ready box.
  - `payload/examples/` — example FEAT specs the user can read or copy.
  - `payload/skeleton/` — the workspace skeleton copied to the user's home.
  - `payload/profile.d/biab-firstboot.sh` — login trigger that runs the wizard on first boot (used by the ISO autoinstall flow).

- **`iso-builder/`** — repackages an Ubuntu 24.04 Server ISO with cloud-init autoinstall + the payload, producing a self-installing USB image (the gift/USB edition).

- **`installer/web/`** — the hosted bootstrap served at `buildersinabox.com/install.sh` (clones the repo + runs `payload/install.sh`).

- **`tools/`** — maintainer scripts. `check-no-personal-refs.sh` is the guard that keeps personal references out of the shippable tree (also run in CI).

## State machine

The installer tracks progress in `/var/lib/buildersinabox/state.json` (schema v2): the resolved operator (`bib_user`), display name (`bib_name`), `flavor`, chosen `ai_cli`, and per-phase completion flags. Every step checks the state and skips if already done, so installs and `--update` are idempotent. Logs go to `/var/log/buildersinabox/bootstrap.log` (ISO-8601 UTC).

## Three install paths

- **`curl | bash` on existing Ubuntu** — the primary path. An interactive operator runs one command; the bootstrap clones the repo and runs `install.sh` inline.
- **USB autoinstall** — for the gift/USB edition. cloud-init installs Ubuntu unattended, drops the payload, and the first-boot trigger runs the wizard. No interactive operator at install time, which is why this path uses autologin + `firstboot.pending`.
- **Cloud bootstrap (FEAT-029)** — for a VPS in the user's own cloud account. `installer/cloud/render.sh` emits cloud-init user-data offline; `installer/cloud/bootstrap.sh`, embedded in it, verifies the platform, the target user and an exact commit before running `install.sh --non-interactive --skip-wizard --profile=cloud`. It stops at `awaiting-owner-setup` — no login, no agent — because the alternative is baking credentials into instance metadata. See [`cloud.md`](cloud.md).

## Install profiles (FEAT-029)

`install_profile` in `state.json` decides who owns sshd, and is read from state first so it survives `biab update` re-running the installer with no arguments.

- **`dedicated`** (default, unchanged) — BIAB owns SSH end to end: `install/50-ssh.sh` writes `00-buildersinabox.conf` with password auth and swaps `ssh.socket` for `ssh.service`; `wizard/35-ssh-finalize.sh` later binds sshd to the tailnet.
- **`cloud`** — both of those scripts return before mutating anything. The invariant is that no file is ever written under `/etc/ssh/sshd_config.d/` or `/etc/systemd/system/ssh.service.d/`. That one property is what makes install, update and uninstall safe together: the uninstall teardown is already gated on BIAB having written a drop-in, so a profile that writes none needs no profile-aware teardown. `35-ssh-finalize.sh` stamps `ssh_provider_managed`, never `ssh_finalized`, because the provider's listener is still reachable.

Switching an existing box between profiles is refused rather than applied, and `BIB_SSH_FORCE_TAILSCALE` cannot route around the profile. Covered by `payload/test/cloud-profile.sh`.

## Paseo daemon (FEAT-035)

Paseo is the default interface on a box whose AI CLI declares the
`paseo-permissioned` capability, which is all three today: Claude Code, Codex
and Antigravity (below). It is a third-party
Apache-2.0 daemon that runs shells for the box user and listens on the network,
so everything that decides what it may do lives in root-owned places the agents
it launches cannot edit.

- **Install** (`payload/install/46-paseo.sh`): `npm ci --omit=dev --ignore-scripts`
  from the committed `payload/paseo/package-lock.json` into
  `/opt/buildersinabox/paseo/<PASEO_PIN>/`, never `npm install -g` and never
  `latest`. `PASEO_PIN` in `payload/lib/paseo.sh`, `package.json` and the
  lockfile are bumped together; `payload/test/paseo.sh` fails if they disagree.
  Trees of other versions are pruned once the new one runs.
- **Units** (root-owned, `/etc/systemd/system/`): `biab-paseo.service` (User=
  the box user; bind address, `PASEO_RELAY_ENABLED=false` and the password in
  the unit environment, which beat the user-writable `~/.paseo/config.json`),
  `biab-paseo-failed.service` (records a give-up), and
  `biab-paseo-health.{service,timer}` (the watchdog: restarts with a cap of
  three per hour, then `GIVEN_UP` until `biab paseo restart`). `MemoryHigh` is
  set, never `MemoryMax`, because the cgroup holds the user's agents.
- **Network:** one listener on the tailnet address, port 6767. The launcher
  (`biab-paseo-run`) refuses `0.0.0.0`; on a cloud-profile box with no tailnet
  address yet the unit waits without burning its restart budget
  (`WAITING_TAILNET`). `tailscale serve` is not used.
- **Credential:** `/etc/buildersinabox/paseo.env`, `root:root 0600`, created once
  and never in state, logs or the repo; `printf` only, because `log()` writes to
  a world-writable file. It is in the environment of the Paseo processes, so any
  process running as the box user can read it from `/proc/<pid>/environ`:
  it keeps other devices out, not the user's own agents.
- **State and ownership:** the daemon home is `~/.biab/paseo` with an ownership
  marker; a user's own `~/.paseo` is never adopted, overwritten or deleted, and
  `--uninstall` removes our home only when the marker is present.
- **Workspaces:** `biab-workspace <path> <name>` is the only thing skills call.
  `bib_paseo_migrate` (run by `biab update`) registers one workspace per existing
  project on a box installed before Paseo became the default and removes nothing.
- **Fallback:** `biab status` prints the SSH command when the daemon is not
  healthy.
- **Antigravity (FEAT-041):** Paseo's own Antigravity plugin starts `agy` with
  `--dangerously-skip-permissions` and cannot be configured, so BIAB disables it
  (`agents.providers.antigravity.enabled=false`, on every box) and, when the
  state's AI CLI is Antigravity, declares its own ACP provider `antigravity-acp`
  whose command is exactly `["/usr/local/bin/agy","acp"]`. In that mode each
  permission request reaches the app. The adapter declares
  `paseo-permissioned`; there is no consent step and no state key.
  The pinned `agy` must have the `acp` subcommand: `46-paseo.sh` checks
  `agy acp --help` before it writes a unit or a config, and stops with a clear
  message otherwise (the SSH way in still works).
- **Provider settings:** they live in `~/.biab/paseo/config.json`, a file of the
  box user, because Paseo rewrites it in place. `biab-paseo-run providers sync`
  (run as the box user right before `exec paseo daemon run`) writes the managed
  block from a heredoc in the root-owned launcher, keeps the user's other
  providers and keys, removes user providers that run Antigravity, and aborts
  the start on a symlink, invalid or oversized file. `providers verify` is
  read-only; the health timer runs it and records `provider_file` in
  `health.json` so `biab status` can say the file changed since the start. It
  repairs, restarts and stops nothing. This is parity with Claude Code and
  Codex, whose permission settings are also user files: a brake, not a lock.
- **Auto Accept:** Paseo's per-agent switch, on by default for unattended runs,
  cannot be removed in the pinned version. BIAB sets none of it. See SECURITY.md.
- **Conversion:** `biab update` re-runs `46-paseo.sh`, which registers an old
  box's projects as workspaces and calls `bib_paseo_antigravity_convert` to drop
  the retired consent key and print the notice once. The old Antigravity switch
  under `biab paseo` only prints that notice until 2027-04-30.

Tests: `payload/test/paseo.sh` (pin, units, launcher, credential, watchdog state
machine, wizard, migration) and the Paseo block of `payload/test/uninstall-contract.sh`.
Hardware-only checks are listed in `HARDWARE-PASS.md`.

## Night shift reach ladder (optional, FEAT-025 + FEAT-039)

The night-shift pack (`payload/pack/night-shift/`) runs one validated spec per
night from a system timer, as the box user, under a root-owned guard
directory. FEAT-039 adds a reach: `pr` (stop at the pull request), `dev`
(default for a new `arm`) or `main`. Reach and the choice of `main` are root-owned
literal files beside `mode`; no `reach` file means `pr`, so boxes armed before
the ladder behave exactly as before.

At `dev`/`main` the runner (`bin/biab-night-shift`, `night_pass`) does, in
order: free prechecks before the attempt stamp (review budget, summary
write-probe, GitHub reachable, `dev` protected and not behind, base fetched and
cross-checked with the API, a baseline run of `.biab/dev-check.sh`; undeclared
or red lowers the pass to `pr`); the agent in its own session under
`timeout 2200`, whose leftovers are killed (and, under systemd, the unit's
cgroup swept) before any gate; then PR identity, danger list and size caps
(files API), CI (check runs + statuses), an independent review
(`ai_cli_review_cmd`: no tools, no MCP, JSON schema, prompt on stdin), a second
write-probe, a re-read of the PR, `gh pr merge --squash --match-head-commit`,
and the base's dev check on the merge commit. Every step checks a T0+3500 s
deadline; every stop is a value of a closed `stopped_at` list in
`last-run.json` (schema 2), read back by `payload/hooks/biab-specs.sh`.
Operator-only commands (`dev-setup`, `dev-sync`, `promote`) use the box user's
own `gh` and refuse root.

Tests: `payload/pack/night-shift/tests/test-pack.sh` (gates against a mock `gh`
and `claude` and a local bare origin), `tests/mutations.sh` (M-30..M-52) and the
night-shift block of `payload/test/uninstall-contract.sh`.

## Browser pack (optional, FEAT-017 + FEAT-030)

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

**Mode ladder (FEAT-030).** A desktop headless Chromium is refused outright by
some sites. A pilot on this stack measured Reddit and Sephora serving a 403
interstitial to desktop headless while the same Chromium, emulating an iPhone,
got a 200 — repeated in both orders, with fresh profiles each time. So the
default is now `--mode auto`, which tries desktop headless, then iPhone
emulation, then headful under a lazily-installed Xvfb, and reports on stderr
which rung worked. `--mode desktop|iphone|headful` pins one rung and disables
the ladder; `--headful-xvfb` remains an alias for `--mode headful`.

Two constraints make this a fallback and not a retry loop:

- **The ladder only moves before the first action.** The driver returns the
  reserved exit code 6 exclusively for a block detected on the initial
  navigation; the wrapper is the only thing that decides to try the next rung,
  and by then nothing has been clicked or submitted. A failed action is never
  replayed against another mode — re-running "fill, click, submit" against a
  page that may have already ordered something is not a safe default.
- **The block detector is deliberately narrow.** A CAPTCHA does not trigger it
  (no other rung solves a challenge, and re-requesting it is exactly the
  hammer-until-it-works behaviour this pack must not have), and neither do DNS
  failures, TLS errors, timeouts, 401/404/429/5xx or login walls — those are
  real answers from the site and are reported as themselves. The title test is
  anchored precisely so an article *about* access denial is not mistaken for
  being denied access. `driver/lib.mjs` holds that decision as a pure function
  so the test suite can pin every one of those cases without a browser.

None of this is evasion: no stealth patches, no proxy rotation, no CAPTCHA
solving. iPhone mode is Chromium emulation applied over CDP before the first
navigation — viewport, touch, user agent — and is documented as such, not as
Safari or iOS.

**Workflows (FEAT-030).** `biab-browse run <url> < workflow.json` runs up to 20
`fill`/`click`/`select`/`wait_for`/`read_text` actions in one browser, on one
page, in order, stopping at the first failure. Before this, a multi-step task
meant one `biab-browse open` per step, and each call closed the browser — so
filling a field and then submitting it submitted an empty form. The workflow
arrives on **stdin, never argv**, so its values stay out of process listings;
the wrapper stages it in a root-owned file and deletes it on exit.

That staging directory is deliberately **not** under `$BROWSER_HOME`, which is
where everything else the pack creates lives. The difference is direction. For
the profiles and the screenshot handoff, the browser user writes and root only
ever reads back, with an explicit recheck immediately before the privileged
copy — so biab-browser owning those paths is fine. A workflow inverts it: root
writes. Write permission on a *directory* is what governs rename and unlink,
whoever owns the entry, so a workflow staged under `$BROWSER_HOME` could be
swapped for a symlink by biab-browser between root's `mktemp` and root's
`chmod`/write. `chmod`, a `>` redirect and `chown` all follow symlinks, which
would turn a Chromium sandbox escape into "root truncates a file of the
attacker's choosing" and, via the `chown`, into ownership of it — straight
through the dedicated user that exists to contain exactly that escape.
`BROWSER_RUNTIME_DIR` (`/run/biab-browser`, root-owned, mode 0711) leaves the
race nowhere to happen: the file stays owned by root and is only
group-readable by biab-browser, which is all the driver needs. The full schema is validated before the browser
starts, and mutating actions confirm themselves without echoing the value they
carried.

## Conventions

- Bash with `set -euo pipefail`. Idempotent scripts. English-only user-facing strings.
- `shellcheck` clean. `tools/check-no-personal-refs.sh` clean (enforced in CI).
- Commit format: `feat:`, `fix:`, `docs:`, `refactor:`.
