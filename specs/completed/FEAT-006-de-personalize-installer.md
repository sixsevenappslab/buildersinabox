---
id: FEAT-006
title: de-personalize-installer
project: buildersinabox
status: completed
phase: completada
priority: high
complexity: medium
created: 2026-06-09
updated: 2026-06-09
validated_by: jesus 2026-06-09
---

# FEAT-006: De-personalize installer for first public OSS release

## §0 — Strategy

> Owner: Product Lead

- **Why now:** EXEC-005 (revision 2026-06-01) locked BIAB as an OSS umbrella under `github.com/sixsevenapps`, with `buildersinabox-installer` as the first module to ship publicly. Domain `buildersinabox.com` is live, email routing is wired, `@buildersinabox` is on its way. The remaining bloqueante is the code itself: today the `payload/` tree is full of `paco` / `Paco` / Spanish copy / gift-specific defaults. That's fine for a personal gift, fatal for a public repo — pushing it as-is would leak the recipient's name into a brand-separated product and break the EXEC-004 brand discipline. This FEAT is the one piece of work standing between "private repo" and "first public commit".
- **Hypothesis:** the de-personalization is mostly mechanical (renames + translations + a tiny generalization layer for who-is-this-user). A flag-driven `install.sh` with `--non-interactive` for CI/preview installs, `--update` for repeat runs, and `--uninstall` for clean teardown is enough to make the script usable on a freshly-autoinstalled Ubuntu by *anyone*, not just Paco. The bigger pieces (`curl | bash` over an already-installed Ubuntu, the module contract for `biab install <name>`) are deliberately scoped out into FEAT-007 / FEAT-008 — this one stays atomic so it ships in days, not weeks.
- **Why this specific cut:** keeping the autoinstall flow as the primary path means we don't have to redesign the wizard's assumptions about firstboot. The `install.sh` rename + flags is **additive surface area** (the wizard chain stays largely intact under the hood); the renames + translation are **find-and-replace surface area**. Splitting "shippable for new installs" from "installable on existing Ubuntu" lets us validate the rename refactor on its own.
- **Cost of not doing it:** without this FEAT, the OSS launch cannot start. Every other FEAT-007+ depends on a public repo existing with neutral code in it. Build-in-public posts also depend on it (we can't tweet about "Paco's wizard" — that wasn't the point of the brand separation).
- **Strategic shift this enables:** with FEAT-006 merged, the next public-facing decisions (first commit visible, first README crawled by Google, first GitHub star) can happen on a clean slate. The `flavors/gift/` directory becomes opt-in for future gift bundles (including potential second-gift, third-gift) without polluting default installs.

## §1 — Product requirements

> Owner: Product Lead

### Problem

The current installer is hardcoded for one recipient. User names, paths, console copy, and the entire `gift/` story assume "Paco on his mini PC". The autoinstall ISO, the wizard banner, the bashrc snippets, the welcome card — all of it embeds personal references that cannot ship publicly without breaking brand separation and leaking a private name into the product.

### Intent (why)

EXEC-005 sequenced naming → de-personalize → first public commit. The first two are done. This FEAT is the only thing between "domain + email + handle ready" and "repo public, first build-in-public tweet". Every day we delay is a day where the squat-able handle decays in value (`@buildersinabox` exists but with zero content) and the momentum from v0.1's ship-to-Paco fades. We resolve it now while the context is fresh.

### Proposed solution

A `BIB_USER` and `BIB_NAME` indirection wherever Paco/paco appears, with sensible runtime defaults so the script Just Works on any Ubuntu install. A flag-driven entry point `install.sh` (renamed from `bootstrap.sh`) accepting `--non-interactive`, `--uninstall`, `--update`. Wizard copy translated end-to-end to English. The gift-edition copy moved behind a `--flavor=gift` opt-in so default installs see neutral copy.

Concretely, after this FEAT:
1. **Any developer can clone the repo** and read every file without seeing a personal name.
2. **Running `install.sh` on a fresh autoinstall Ubuntu 24.04** prompts for `BIB_USER` (defaults to the current `$USER` of whoever's running the wizard) and `BIB_NAME` (optional — defaults to empty, which makes the banner say "BUILDERS IN A BOX" without a personal "PACO" line above it).
3. **`install.sh --non-interactive`** runs end-to-end using env vars `BIB_USER` / `BIB_NAME` / `BIB_FLAVOR` (= "default" or "gift"), no prompts. For CI smoke tests and unattended re-installs.
4. **`install.sh --update`** re-runs idempotently on a box that already went through install once (skips completed phases, doesn't reset password, doesn't re-OAuth).
5. **`install.sh --uninstall`** removes `/opt/buildersinabox`, `/usr/local/bin/biab`, `/usr/local/bin/bd`, `/var/lib/buildersinabox/`, `/var/log/buildersinabox/`, and `/etc/profile.d/biab-firstboot.sh`. Leaves the user's home, Tailscale auth, GitHub auth, and project workspaces intact (those are *their* data, not ours).
6. **`flavors/gift/` exists as an opt-in directory** containing the Paco-style welcome banner, the gift copy, the block-letter name handling. Selected via `--flavor=gift` flag or `BIB_FLAVOR=gift` env var. Default is `--flavor=default` (neutral copy).

### User stories

- As a developer who just plugged in a new mini PC with autoinstalled Ubuntu, I want `install.sh` to detect my user account and walk me through a neutral, English wizard, so I can land in tmux + Claude Code without anyone else's name on my screen.
- As a maintainer testing the installer on a VPS or VM, I want `install.sh --non-interactive` with env vars to install end-to-end without prompts, so I can run smoke tests in CI before each release.
- As a developer who already ran `install.sh` once and wants to pull a newer payload, I want `install.sh --update` to re-run only the phases that changed, so I don't have to nuke my box.
- As a developer who decides BIAB isn't for them, I want `install.sh --uninstall` to cleanly remove everything BIAB-owned without touching my OAuth tokens, repos, or shell history.
- As a future maintainer preparing a gift edition for a specific person, I want to drop the Paco-style copy into `flavors/gift/` and invoke `install.sh --flavor=gift BIB_NAME="Maria"` to get the personalized experience without polluting the default install.

### Functional requirements (EARS)

- [ ] **Ubiquitous:** The installer shall reference the operating user via `${BIB_USER}` and the display name via `${BIB_NAME}` in every script, copy file, and banner — never via the hardcoded literal `paco` / `Paco`.
- [ ] **Event-driven:** When `install.sh` is invoked without `--non-interactive`, the installer shall prompt for `BIB_USER` (default: current `$USER`) and `BIB_NAME` (default: empty), and persist both to `/var/lib/buildersinabox/state.json` before any phase runs.
- [ ] **Event-driven:** When `install.sh --non-interactive` is invoked, the installer shall read `BIB_USER`, `BIB_NAME`, and `BIB_FLAVOR` from the environment, fail with a clear error message if any required var is missing, and run all phases without any TTY prompt.
- [ ] **Event-driven:** When `install.sh --update` is invoked on a box where `/var/lib/buildersinabox/state.json` already records completed phases, the installer shall skip those phases with a one-line log entry and re-run only the remaining ones.
- [ ] **Event-driven:** When `install.sh --uninstall` is invoked, the installer shall remove `/opt/buildersinabox`, `/usr/local/bin/biab`, `/usr/local/bin/bd`, `/var/lib/buildersinabox/`, `/var/log/buildersinabox/`, `/etc/profile.d/biab-firstboot.sh`, and shell snippets installed under the user's `~/.bashrc.d/` — and **shall not** touch the user's home dir contents, Tailscale state, GitHub auth, Claude auth, or any directory the user created themselves.
- [ ] **State-driven:** While the wizard runs in non-interactive mode and a required env var is unset, the installer shall fail fast with a precise message naming the missing var (no silent defaults that would hide config errors in CI).
- [ ] **Optional:** Where `--flavor=gift` (or `BIB_FLAVOR=gift`) is set, the installer shall source console copy and banner art from `payload/flavors/gift/` instead of `payload/flavors/default/`.
- [ ] **Ubiquitous:** All wizard scripts, install scripts, banner copy, bashrc snippets, and the welcome readme shall be in English. (Existing tutorial/skill copy already in English stays.)
- [ ] **Ubiquitous:** The `gift/` top-level directory (welcome card source, PDF explainer, delivery notes) shall move to `flavors/gift/maintainer/` so it travels with the gift flavor instead of being a top-level repo concern.
- [ ] **Unwanted:** If the installer detects that a phase's `<verify>` was already satisfied (state.json phase = done AND the verify check still passes), the installer shall skip the phase silently rather than re-run it — and shall not attempt to re-create files that already exist.
- [ ] **Unwanted:** If the user runs `install.sh` without sudo when sudo is required (writing to `/opt`, `/usr/local/bin`), the installer shall fail with a clear message naming the exact privilege needed — never with a Python-style traceback or a `permission denied` cascade.

### Non-functional requirements

- [ ] No new dependencies introduced by this FEAT. The script keeps the existing bash + systemd + tmux + cloud-init dependency surface — only renames, translations, and flag additions.
- [ ] Backward compatibility with Paco's v0.1 box is **not a requirement** (per Jesus's scope decision 2026-06-09). His v0.1 stays as a frozen tarball install. No migration path is designed in this FEAT.
- [ ] No telemetry, no analytics, no phone-home of any kind added in this FEAT.
- [ ] The renamed `install.sh` shall still be invocable from cloud-init `runcmd` exactly like `bootstrap.sh` was — the cloud-init template gets updated to call the new name, ISO autoinstall flow continues working end-to-end.
- [ ] Pre-commit guard `tools/check-no-personal-refs.sh` shall be extended to also block `paco`, `Paco`, `jesusmartincalvo`, `hezumartin`, `virtualdev`, and any project-specific Spanish word lists. The guard runs as part of `install.sh --selftest` and on CI for the repo.
- [ ] Total LOC delta budget: ≤500 lines net. If the FEAT exceeds this, split into FEAT-006a/b before implementing.

### Visual references

- **Wireframes / mockups:** N/A (no UI changes). The wizard is a TUI; layout doesn't change. Only the words and the name placeholders do.
- **Banner reference:** existing `wizard_banner` in `payload/wizard/` shows the block-letter PACO + BUILDERS IN A BOX. Default flavor drops the personal line; gift flavor preserves it. Side-by-side comparison goes in the spec implementation notes.

### Growth Notes

- **Channel:** N/A for FEAT-006 itself (this is plumbing, not a growth surface). The growth play depends on this FEAT shipping so FEAT-007/008 + first public post can happen, but the metrics live in those follow-ups.

## §2 — Technical spec

> Owner: Tech Lead (`sdd-spec-writer`)

### Prior investigation

- **Existing entry point:** `payload/bootstrap.sh` orchestrates the install. Uses helpers from `payload/lib/common.sh` (`require_root`, `require_supported_os`, `state_init`, `phase_done`, `phase_is_done`, `phase_reset`, `log`, `die`, `apt_install`) and `payload/lib/ai-cli.sh` (`ai_cli_resolve`, `ai_cli_persist`, `ai_cli_install_script`). Phase tracker writes to `/var/lib/buildersinabox/state.json` with schema version `1`. Phases recorded: `stack_installed`, `password_set`, `tailscale_done`, `gh_done`, `ai_cli_done`, `scaffold_done`, `tmux_done`.
- **Wizard chain:** `payload/wizard/run.sh` orchestrates `01-set-password.sh` → `10-tailscale-up.sh` → `35-ssh-finalize.sh` → `36-phone-bridge.sh` (pauses with exit 78) → `05-choose-cli.sh` → `38-ai-cli-login.sh` → `40-scaffold.sh` → `50-tmux.sh`. Pattern: each step is a standalone script that calls `phase_is_done` to skip if already complete, then `phase_done` at the end.
- **Firstboot trigger:** `payload/profile.d/biab-firstboot.sh` (installed to `/etc/profile.d/`) checks for `/var/lib/buildersinabox/firstboot.pending` and re-runs the wizard on login (console or SSH). Marker is removed at end of `wizard/run.sh`.
- **Existing guard:** `tools/check-no-personal-refs.sh` already filters `jesusmartincalvo`, `hezumartin`, `virtualdev\.company`, `@virtualdev`, `\bJesus\b`. Currently excludes `gift/` and `tools/`. **Does NOT catch `paco`/`Paco`** — that's the gap this FEAT closes.
- **`paco`/`Paco` surface (17 files, ~30 hits):** `payload/install/00-base.sh` (1), `payload/wizard/*.sh` (15 across 9 files), `payload/skills/*/SKILL.md` (12 across 4 files), `payload/tutorial/desktop-readme.md` (1), `payload/lib/prompt.sh` (1). Verified via `grep -rIl --include="*.sh" --include="*.md" -e "paco" -e "Paco" payload/`.
- **`bootstrap.sh` references to update on rename:** `payload/wizard/run.sh` (l.9, l.79), `payload/tutorial/desktop-readme.md` (l.222), `payload/README.md` (l.5, l.11, l.26), `payload/bootstrap.sh` self-reference (l.27), `payload/test/dryrun.sh` (l.28), `payload/lib/oauth.sh` (l.94). ISO autoinstall flow does NOT call `bootstrap.sh` directly — it relies on `profile.d/biab-firstboot.sh` to trigger first login. No `iso-builder/user-data` change needed for the rename itself, though the cloud-init `runcmd` block copies the profile.d trigger.
- **Existing flags in `bootstrap.sh`:** `--force` (resets wizard phases), `--skip-wizard` (install stack + exit, used in CI), `--i-know-what-im-doing` (OS override), `--ai-cli=<claude|gemini>`. The new flags piggyback on the same `getopts`-style loop.
- **Existing test scaffold:** `payload/test/dryrun.sh` runs the install end-to-end against `--ai-cli=claude --skip-wizard`. Provides a baseline for `--non-interactive` smoke test.
- **Dependencies available:** `bash`, `jq` (already required by `state_init`), `apt`, `systemd`, `tmux`, `awk`, `sed`. **No new runtime dependency introduced.** Only `envsubst` (gettext-base) is borderline new — used for safe template substitution; check whether already pulled in by an apt-installed package.
- **Risks identified:**
  - **`state.json` schema bump** from `1` to `2` (adding `bib_user`, `bib_name`, `flavor` fields) is technically a breaking change. Existing test boxes with schema 1 hit `state_init`'s version check on next run. Mitigation: write a migration that detects v1 and upgrades in place (read existing phases, write back as v2 with defaulted new fields). Migration is small (~15 LOC) and non-destructive.
  - **`gift/` relocation** changes the top-level repo shape. The `.gitattributes` `export-ignore` rule needs updating (`gift/` → `payload/flavors/gift/maintainer/`). Existing CI / `git archive` flows depend on this path.
  - **OAuth helpers in `lib/oauth.sh`** are user-facing prompts; translation Spanish → English must preserve identical logical flow (exit codes, retry semantics) — translations that accidentally change behaviour break Phase B.
  - **`getty@tty1.service.d/autologin.conf`** hardcodes `User=paco`. ISO cloud-init copies this file in `runcmd`. Templating it requires either (a) generating it at install time with envsubst, or (b) leaving as-is and accepting that ISO autoinstall always autologins to a user literally named after `${BIB_USER}` (which for an OSS user might not be `paco`). Decision: parameterize via envsubst at install time, generating the systemd drop-in dynamically.
  - **Wizard banner block letters** (`PACO` ASCII art generated by figlet-like rendering): the rendering is computed at wizard runtime from `${BIB_NAME}`. If `BIB_NAME` is empty (default), the banner shows only "BUILDERS IN A BOX". If gift flavor selected, the banner uses `${BIB_NAME}` (uppercased) above the main name.

### Scope

#### Includes

- Rename `payload/bootstrap.sh` → `payload/install.sh`, update every reference across the repo and ISO cloud-init.
- Add flags `--non-interactive`, `--uninstall`, `--update`, `--flavor=<default|gift>`, `--selftest` to `install.sh`.
- Add `bib_user_resolve` / `bib_name_resolve` / `bib_flavor_resolve` helpers in `payload/lib/common.sh`.
- Replace every `paco` / `Paco` literal across `payload/**/*.{sh,md,yaml}` with `${BIB_USER}` / `${BIB_NAME}` (or runtime substitution where files are static).
- Bump `state.json` schema from `1` to `2` with non-destructive migration.
- Move top-level `gift/` → `payload/flavors/gift/maintainer/`. Create `payload/flavors/default/copy/` and `payload/flavors/gift/copy/` for wizard banner + welcome copy.
- Translate Spanish wizard copy to English in `payload/wizard/*.sh` and `payload/lib/oauth.sh`, `payload/lib/prompt.sh`.
- Extend `tools/check-no-personal-refs.sh` PATTERNS array with `\bpaco\b` and `\bPaco\b`. Hook into `install.sh --selftest`.
- Update `.gitattributes` export-ignore rule from `gift/` → `payload/flavors/gift/maintainer/`.
- Generate `getty@tty1.service.d/autologin.conf` dynamically at install time using `envsubst` so `User=` matches `${BIB_USER}`.
- Update `payload/test/dryrun.sh` to exercise `install.sh --non-interactive` smoke path.

#### Does NOT include (explicit exclusions)

- `curl https://buildersinabox.com/install.sh | bash` over already-installed Ubuntu — that's **FEAT-007**.
- Module contract for `biab install <name>` — that's **FEAT-008**.
- Migration path for Paco's v0.1 tarball box — scope decision 2026-06-09: his box is frozen, no upgrade flow built here.
- WiFi-only setup, ARM/Raspberry Pi support, multi-user devices — all explicitly out of scope per CLAUDE.md.
- Refactor of `lib/common.sh` beyond adding the three new resolver helpers + the state migration function. Existing API surface stays.
- New translations beyond English (i18n framework). Spanish copy moves to `flavors/gift/maintainer/` because it's gift-personal, not because we support i18n.
- Removing any existing wizard step or install script. De-personalize ≠ delete.

### Affected files

| File | Action |
|------|--------|
| `payload/bootstrap.sh` | RENAME → `payload/install.sh` + extend with new flags |
| `payload/lib/common.sh` | MODIFY — add `bib_user_resolve`, `bib_name_resolve`, `bib_flavor_resolve`, `state_migrate_v1_to_v2`. Bump `BIB_STATE_SCHEMA_VERSION` to `2`. |
| `payload/lib/oauth.sh` | MODIFY — translate Spanish strings; update self-reference from `bootstrap.sh` to `install.sh` |
| `payload/lib/prompt.sh` | MODIFY — translate banner/header copy; replace `Paco` with `${BIB_NAME}` indirection |
| `payload/install/00-base.sh` | MODIFY — translate Spanish comment about Paco's local time; honour `${BIB_USER}` |
| `payload/wizard/run.sh` | MODIFY — replace `Paco` literals with `${BIB_NAME}`; update bootstrap.sh→install.sh ref |
| `payload/wizard/01-set-password.sh` | MODIFY — translate prompts; replace `paco` references |
| `payload/wizard/10-tailscale-up.sh` | MODIFY — same pattern |
| `payload/wizard/20-gh-login.sh` | MODIFY — same pattern |
| `payload/wizard/35-ssh-finalize.sh` | MODIFY — same pattern |
| `payload/wizard/36-phone-bridge.sh` | MODIFY — same pattern (3 hits) |
| `payload/wizard/38-ai-cli-login.sh` | MODIFY — same pattern |
| `payload/wizard/40-scaffold.sh` | MODIFY — same pattern |
| `payload/wizard/50-tmux.sh` | MODIFY — same pattern |
| `payload/wizard/60-slack-bootstrap.sh` | MODIFY — same pattern |
| `payload/skills/tutorial/SKILL.md` | MODIFY — replace `Paco` placeholders with `${BIB_NAME}` (rendered at runtime via skill prompt template) |
| `payload/skills/morning-check/SKILL.md` | MODIFY — same pattern |
| `payload/skills/first-project/SKILL.md` | MODIFY — same pattern |
| `payload/skills/extend-yourself/SKILL.md` | MODIFY — same pattern |
| `payload/tutorial/desktop-readme.md` | MODIFY — replace `Paco`; update bootstrap.sh→install.sh ref |
| `payload/README.md` | MODIFY — update bootstrap.sh→install.sh ref + DIY install copy |
| `payload/systemd/getty@tty1.service.d/autologin.conf` | CONVERT to template: rename to `autologin.conf.in`; install.sh renders it via `envsubst < autologin.conf.in > /etc/systemd/...` |
| `payload/test/dryrun.sh` | MODIFY — exercise `install.sh --non-interactive` with env vars |
| `tools/check-no-personal-refs.sh` | MODIFY — extend PATTERNS with `\bpaco\b`, `\bPaco\b` |
| `iso-builder/user-data` | MODIFY — only the path of the copied profile.d trigger if needed; verify no direct bootstrap.sh reference |
| `gift/` (top-level) | MOVE → `payload/flavors/gift/maintainer/` |
| `payload/flavors/default/copy/welcome.txt` | CREATE — neutral welcome copy used by default flavor banner |
| `payload/flavors/gift/copy/welcome.txt` | CREATE — gift welcome copy (moved from current wizard/run.sh inline heredocs) |
| `payload/flavors/default/manifest.sh` | CREATE — flavor declaration (sourced by install.sh, exports `BIB_FLAVOR_COPY_DIR`) |
| `payload/flavors/gift/manifest.sh` | CREATE — same for gift |
| `.gitattributes` | MODIFY — `gift/ export-ignore` → `payload/flavors/gift/maintainer/ export-ignore` |

### Dependencies

- **No new runtime dependency.** Bash + jq + apt + systemd + tmux + envsubst (gettext-base). `envsubst` is the only borderline — verified available via `apt list --installed gettext-base` on a fresh Ubuntu 24.04. If missing, add to `install/00-base.sh` apt list.

### Tasks

#### Wave 1 — Indirection + flag scaffolding (independent file edits)

<task id="1">
  <name>Add BIB_USER/BIB_NAME/BIB_FLAVOR resolvers + state schema v2 migration in lib/common.sh</name>
  <files>payload/lib/common.sh</files>
  <action>
    Add three helpers and the schema migration:
    - `bib_user_resolve()`: echo "${BIB_USER:-${SUDO_USER:-${USER}}}". Validates the result is a non-empty string and a real user (getent passwd "$result").
    - `bib_name_resolve()`: echo "${BIB_NAME:-}" (empty default is fine; banner handles empty case).
    - `bib_flavor_resolve()`: echo "${BIB_FLAVOR:-default}". Validates value is in {default, gift}, dies on invalid.
    - `state_migrate_v1_to_v2()`: if state.json version == 1, read existing phases, write back with version=2 + bib_user (resolved) + bib_name (empty) + flavor=default. Atomic write via temp file + mv. Idempotent (no-op if already v2).
    - Bump `BIB_STATE_SCHEMA_VERSION` constant from `1` to `2`.
    - `state_init()`: call `state_migrate_v1_to_v2()` after loading existing file (before checking version).
    Keep all existing functions unchanged. Add at end of relevant sections.
  </action>
  <verify>bash -n payload/lib/common.sh && grep -E "^(bib_user_resolve|bib_name_resolve|bib_flavor_resolve|state_migrate_v1_to_v2)\(\)" payload/lib/common.sh | wc -l</verify>
  <done>Returns 4. shellcheck passes on common.sh without new warnings.</done>
</task>

<task id="2">
  <name>Rename bootstrap.sh → install.sh and extend with new flags</name>
  <files>payload/bootstrap.sh, payload/install.sh, payload/wizard/run.sh, payload/tutorial/desktop-readme.md, payload/README.md, payload/test/dryrun.sh, payload/lib/oauth.sh</files>
  <action>
    1. `git mv payload/bootstrap.sh payload/install.sh`.
    2. Update self-references in usage text from `bootstrap.sh` to `install.sh`.
    3. Add new flag parsing in the existing while-case loop:
       - `--non-interactive` sets NON_INTERACTIVE=1, requires BIB_USER + BIB_NAME + BIB_FLAVOR + BIB_AI_CLI env vars; die with named-var error if missing.
       - `--update` sets UPDATE_MODE=1; re-runs `<verify>` on each phase before skipping (today `--force` resets all, this only re-checks).
       - `--uninstall` sets UNINSTALL_MODE=1; runs new `do_uninstall()` function and exits.
       - `--flavor=<default|gift>` sets BIB_FLAVOR; validates via bib_flavor_resolve.
       - `--selftest` runs tools/check-no-personal-refs.sh against the install tree + verifies state.json schema; exits.
    4. Implement `do_uninstall()`: removes `/opt/buildersinabox`, `/usr/local/bin/biab`, `/usr/local/bin/bd`, `/var/lib/buildersinabox/`, `/var/log/buildersinabox/`, `/etc/profile.d/biab-firstboot.sh`, `~${BIB_USER}/.bashrc.d/biab-*` shell snippets. Leaves user home, Tailscale state, gh auth, claude auth alone.
    5. Update `payload/wizard/run.sh` lines 9 and 79 + `payload/tutorial/desktop-readme.md` line 222 + `payload/README.md` lines 5/11/26 + `payload/test/dryrun.sh` line 28 + `payload/lib/oauth.sh` line 94: `bootstrap.sh` → `install.sh`.
    6. Source flavors/<resolved>/manifest.sh after state_init so the rest of the run sees BIB_FLAVOR_COPY_DIR.
    Keep existing flags (--force, --skip-wizard, --i-know-what-im-doing, --ai-cli) unchanged.
  </action>
  <verify>bash -n payload/install.sh && ! [ -e payload/bootstrap.sh ] && grep -c "install\.sh" payload/wizard/run.sh payload/tutorial/desktop-readme.md payload/README.md payload/test/dryrun.sh payload/lib/oauth.sh</verify>
  <done>install.sh parses. bootstrap.sh no longer exists. All five files reference install.sh (count ≥ 5).</done>
</task>

<task id="3">
  <name>Replace all paco/Paco literals with ${BIB_USER}/${BIB_NAME} across payload tree</name>
  <files>payload/wizard/*.sh, payload/install/00-base.sh, payload/skills/*/SKILL.md, payload/tutorial/desktop-readme.md, payload/lib/prompt.sh</files>
  <action>
    For every file flagged by `grep -rIl --include="*.sh" --include="*.md" -e "paco" -e "Paco" payload/`:
    - Replace bash-script `paco` (literal username, in path strings, in chown, in heredocs sourced by user wizard) with `"${BIB_USER}"`. Watch quoting: single-quoted heredocs need `EOF`→`"EOF"` to allow expansion, OR refactor to assemble lines.
    - Replace `Paco` (display name in greetings, banners, headers) with `"${BIB_NAME}"`. If `${BIB_NAME}` is empty, the line must read naturally (e.g., `"Hi ${BIB_NAME:+${BIB_NAME} — }let's set up your Builders in a Box"` collapses cleanly).
    - In SKILL.md files: replace `Paco` with template placeholder `{{BIB_NAME}}` (the skill prompt template engine substitutes at runtime — verify the engine supports this token; if not, fall back to direct env-var substitution in the SKILL.md loader).
    - Run `grep -rE "\bpaco\b|\bPaco\b" payload/` after — expect zero hits outside `payload/flavors/gift/`.
  </action>
  <verify>! grep -rIE --include="*.sh" --include="*.md" "\bpaco\b|\bPaco\b" payload/ --exclude-dir=flavors</verify>
  <done>grep returns no hits outside payload/flavors/. Wizard scripts still bash -n pass.</done>
</task>

#### Wave 2 — Flavors + translations (depends on Wave 1 file shape)

<task id="4">
  <name>Create flavors/ structure and move gift/ into it</name>
  <files>payload/flavors/default/, payload/flavors/gift/, gift/ (move), .gitattributes</files>
  <action>
    1. `mkdir -p payload/flavors/default/copy payload/flavors/gift/{copy,maintainer}`.
    2. `git mv gift/ payload/flavors/gift/maintainer/`.
    3. Create `payload/flavors/default/manifest.sh`:
       ```
       export BIB_FLAVOR_COPY_DIR="${BIB_INSTALL_ROOT}/payload/flavors/default/copy"
       export BIB_FLAVOR_NAME="default"
       ```
    4. Create `payload/flavors/gift/manifest.sh` (parallel).
    5. Create `payload/flavors/default/copy/welcome.txt` — neutral 6-line welcome shown after wizard ends. No personal references.
    6. Create `payload/flavors/gift/copy/welcome.txt` — moved from current heredoc in `wizard/run.sh` (the long "This isn't just a mini PC" copy). Add `${BIB_NAME}` substitution markers.
    7. Refactor `wizard/run.sh`: replace the inline heredocs with `cat "${BIB_FLAVOR_COPY_DIR}/welcome.txt" | envsubst`.
    8. Update `.gitattributes`: replace `gift/ export-ignore` and `gift/* export-ignore` rules with `payload/flavors/gift/maintainer/ export-ignore`.
    9. Update `payload/lib/common.sh` so `wizard_banner()` and `apply_wizard_font()` consult `${BIB_FLAVOR_NAME}` and source banner art from the resolved flavor dir.
  </action>
  <verify>test -d payload/flavors/default/copy && test -d payload/flavors/gift/copy && test -d payload/flavors/gift/maintainer && ! test -d gift && grep -q "payload/flavors/gift/maintainer/ export-ignore" .gitattributes</verify>
  <done>flavors/ tree exists. gift/ top-level removed. .gitattributes export-ignore points to new path. wizard/run.sh sources welcome.txt via envsubst.</done>
</task>

<task id="5">
  <name>Translate Spanish wizard copy to English</name>
  <files>payload/wizard/*.sh, payload/lib/oauth.sh, payload/lib/prompt.sh, payload/install/00-base.sh</files>
  <action>
    Translate every Spanish user-facing string to English. Preserve:
    - Identical logical control flow (no behavior changes from translation).
    - Existing exit codes (especially exit 78 in 36-phone-bridge.sh).
    - Variable substitutions and quoting.
    - Tone: warm, brief, no hype (matches FEAT-005 style).
    Skip anything inside `payload/flavors/gift/` — gift copy stays bilingual (it's maintainer-only).
    Use shellcheck after each file: any new warnings means the translation introduced a quoting bug.
    Add `payload/install/00-base.sh` translation of the Paco-local-time comment → "Set timezone to match the operator's local time (configurable via TZ env var on next install)".
  </action>
  <verify>! grep -rIE --include="*.sh" "(¿|¡|á|é|í|ó|ú|ñ)" payload/wizard payload/lib payload/install 2>/dev/null | grep -v "^payload/flavors/"</verify>
  <done>grep finds no Spanish diacritics in wizard/lib/install scripts (excluding flavors/gift/). All scripts still bash -n + shellcheck pass.</done>
</task>

#### Wave 3 — Guard, autologin templating, verification

<task id="6">
  <name>Extend personal-refs guard, template autologin, end-to-end verification</name>
  <files>tools/check-no-personal-refs.sh, payload/systemd/getty@tty1.service.d/autologin.conf, payload/install.sh, iso-builder/user-data</files>
  <action>
    1. `tools/check-no-personal-refs.sh`: append `"\bpaco\b"` and `"\bPaco\b"` to PATTERNS array. The existing `EXCLUDES` already covers `gift/` — extend to also exclude `payload/flavors/gift/maintainer/`. Update header comment to list the new patterns.
    2. Rename `payload/systemd/getty@tty1.service.d/autologin.conf` → `autologin.conf.in`. Replace the hardcoded `User=paco` with `User=${BIB_USER}`. In `install.sh`, add a step early in the install phase (before phase `stack_installed`) that renders the file:
       ```
       envsubst < /opt/buildersinabox/payload/systemd/getty@tty1.service.d/autologin.conf.in \
         > /etc/systemd/system/getty@tty1.service.d/autologin.conf
       ```
    3. Update `iso-builder/user-data` `runcmd` block: instead of copying `autologin.conf` directly, copy `autologin.conf.in` and rely on `install.sh` (triggered by first-boot) to render it.
    4. Update `payload/install.sh --selftest`: runs `tools/check-no-personal-refs.sh` against `/opt/buildersinabox/` and verifies `state.json` schema version is 2.
    5. Update `payload/test/dryrun.sh`: add a smoke test path `install.sh --non-interactive` with BIB_USER=testuser, BIB_NAME="Test User", BIB_FLAVOR=default, BIB_AI_CLI=claude.
    6. End-to-end run on a fresh Ubuntu 24.04 cloud-init VM (or LXC container) — exercises install → wizard (Phase A only, skip OAuth interactive bits) → verifies `state.json` v2 → runs `--selftest` → runs `--uninstall` → checks `/opt/buildersinabox` is gone and user home untouched.
  </action>
  <verify>bash tools/check-no-personal-refs.sh && payload/test/dryrun.sh && payload/install.sh --selftest</verify>
  <done>check-no-personal-refs.sh returns 0 (clean). dryrun.sh smoke completes. --selftest returns 0. End-to-end VM run is clean (manual observation; transcript logged to /tmp/feat-006-e2e.log).</done>
</task>

### Code pattern to follow

Existing phase guard + state pattern from `payload/wizard/01-set-password.sh` (representative of how every wizard step is structured — re-use this exact shape when adding new code paths):

```bash
#!/usr/bin/env bash
# Wizard step 01: set the operator's password.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root

if phase_is_done "password_set"; then
    log "wizard/01: password already set, skipping"
    exit 0
fi

# ... actual logic that prompts and updates passwd ...

phase_done "password_set"
```

New flag-handling block to add to `install.sh` follows the existing `while [[ $# -gt 0 ]]; case "$1"` pattern (see `payload/bootstrap.sh:30-50`). New `do_uninstall()` follows the existing `run_install()` helper shape (declared near other top-level helpers, called at most once).

### Global acceptance criteria

- [ ] `tools/check-no-personal-refs.sh` returns 0 on the shippable tree (`gift/` exempt → now `payload/flavors/gift/maintainer/` exempt).
- [ ] `grep -rIE --include='*.sh' --include='*.md' '\bpaco\b|\bPaco\b' payload/ --exclude-dir=flavors` returns no hits.
- [ ] `grep -rIE --include='*.sh' '(¿|¡|á|é|í|ó|ú|ñ)' payload/wizard payload/lib payload/install` returns no hits (excluding flavors/gift/).
- [ ] `payload/install.sh --help` shows the new flags (`--non-interactive`, `--uninstall`, `--update`, `--flavor`, `--selftest`) in addition to existing.
- [ ] `payload/install.sh --non-interactive` with required env vars (BIB_USER, BIB_NAME, BIB_FLAVOR, BIB_AI_CLI) runs end-to-end without prompting on a fresh Ubuntu 24.04 VM. Exits 0.
- [ ] `payload/install.sh --update` on an already-installed box re-checks each phase's verify and skips done ones. No phase is destructively reset.
- [ ] `payload/install.sh --uninstall` removes BIB-owned dirs (`/opt/buildersinabox`, `/usr/local/bin/biab`, `/usr/local/bin/bd`, `/var/lib/buildersinabox`, `/var/log/buildersinabox`, `/etc/profile.d/biab-firstboot.sh`) and leaves user `${HOME}`, Tailscale, gh, claude auth untouched (verified post-uninstall).
- [ ] `payload/install.sh --selftest` returns 0 on a clean install.
- [ ] `state.json` schema upgraded from `1` to `2` non-destructively on an existing v1 box (verified by manual test with a stubbed v1 file).
- [ ] `getty@tty1.service.d/autologin.conf` is generated at install time with `User=${BIB_USER}` (verified by inspecting the rendered file after install).
- [ ] `git archive HEAD` produces a tarball with no top-level `gift/` and no Paco/paco occurrences (`tar -tvf` listing for the first; `grep` on extracted contents for the second).
- [ ] `shellcheck` passes (no new warnings) on every modified `.sh` file.
- [ ] LOC budget: `git diff --stat` shows net `< 500` LOC added. If exceeded, FEAT splits into FEAT-006a/b before merge.

## §3 — Boundaries

> Owner: Product Lead, refined by Tech Lead and (if applicable) Security.

### Always

- English in every user-facing string. Spanish only allowed in maintainer-only files in `flavors/gift/maintainer/` (gift copy is bilingual but never shipped in default).
- Every rename `paco` → `${BIB_USER}` must go through a variable indirection — never inline string templating that could break under shell quoting edge cases. Use single-quoted heredocs with envsubst where needed.
- Idempotency: every script must be safe to re-run. Use the `state.json` phase tracker. If a phase has no `state.json` entry yet, the script defines one with `pending` → `done` transitions.
- Pre-commit guard `tools/check-no-personal-refs.sh` runs as part of CI and as part of `install.sh --selftest`. If it fails, the build fails.
- Commit format follows existing convention: `feat:`, `fix:`, `refactor:`, `docs:`. Commit messages in English.
- New scripts get `set -euo pipefail` at the top — no exceptions.

### Ask First

- Any **change to the autoinstall ISO build** (`iso-builder/`). The ISO is shipped to Paco already; we can rebuild for new flavors but Jesús reviews the diff before touching it.
- Any change to **default Tailscale, GitHub, or Claude OAuth scopes**. The user's auth flows are sensitive and any prompt change in those steps deserves a human review.
- **Translation of `payload/lib/oauth.sh`** — this script holds OAuth retry / exit-code semantics. Translation must preserve the existing exit codes and error-handling paths. Any change in observable behavior here gets flagged to Jesús before merge.
- **`state.json` schema bump from v1 to v2.** Existing test boxes carrying schema v1 hit `state_init` migration on next run. Migration is non-destructive (read v1 + write v2 with defaults) — but it's a one-way change. Sign-off needed before merging.
- Adding **any new top-level directory** in the repo. The shape (payload/, iso-builder/, pairing/, specs/, tools/, gift/ → flavors/gift/) is intentional; new dirs need scope review.
- **Removing any existing script or skill from the payload.** De-personalize ≠ delete. If a script feels redundant after rename, it goes through a separate FEAT for removal.
- **Adding `envsubst` (gettext-base) to `install/00-base.sh` apt list.** Verified available in default Ubuntu 24.04 server, but if testing reveals it's missing on minimal installs, the spec must add it explicitly — confirm before bumping apt deps.

### Never

- Touch `.env`, `state.json` examples with real Tailscale/Claude/GitHub credentials. The example file `state.json.example` ships with placeholder values only.
- Modify `firestore.rules` or any security configuration (the project has none of those, but the rule stands as a guardrail for future modules).
- Add WiFi-only setup or non-x86 hardware support (those are explicitly out of scope per existing CLAUDE.md — that's a separate FEAT when the time comes).
- Bundle Anthropic / OpenAI / Tailscale credentials in the repo or in the ISO. Every auth flow must remain user-driven OAuth.
- Add telemetry, analytics, phone-home, or any network call to a non-user-controlled endpoint.
- Re-introduce Spanish copy anywhere in the default install path. Spanish belongs to maintainer-only files inside `flavors/gift/maintainer/`.
- Break Paco's v0.1 install (he runs a frozen tarball, so as long as we don't push to his box, we're safe — but if any FEAT-006 work somehow affects his box, stop and re-scope).

## §4 — QA

> Owner: QA Lead (`sdd-qa`)

### Test cases (functional)

| # | Case | Steps | Expected result | Status |
|---|------|-------|-----------------|--------|
| F1 | Default flavor non-interactive install on fresh Ubuntu 24.04 VM | 1. Provision fresh Ubuntu 24.04 cloud-init VM as user `ubuntu`. 2. `git clone` repo to `/repo`. 3. `BIB_USER=ubuntu BIB_NAME="" BIB_FLAVOR=default BIB_AI_CLI=claude BIB_OAUTH_MOCK=1 sudo -E /repo/payload/install.sh --non-interactive --skip-wizard`. 4. Read `/var/lib/buildersinabox/state.json`. | Exit 0. `state.json` exists with `version: 2`, `phases.stack_installed: true`, `bib_user: "ubuntu"`, `bib_name: ""`, `flavor: "default"`. `/usr/local/bin/biab` and `/usr/local/bin/bd` are executable. No prompt was shown. No `paco`/`Paco` strings in `/var/log/buildersinabox/bootstrap.log`. | pending |
| F2 | Gift flavor with BIB_NAME renders personalized banner | 1. Provision fresh VM. 2. `git clone` + ensure `payload/flavors/gift/maintainer/` is present in working tree (export-ignore strips it from `git archive` but local clone retains it). 3. `BIB_USER=maria BIB_NAME="Maria" BIB_FLAVOR=gift BIB_AI_CLI=claude BIB_OAUTH_MOCK=1 sudo -E /repo/payload/install.sh --non-interactive`. 4. Inspect rendered banner output captured to log. | Exit 0. Bootstrap log contains "MARIA" block-letter banner above "BUILDERS IN A BOX". Welcome text reads from `payload/flavors/gift/copy/welcome.txt` with `${BIB_NAME}` substituted to "Maria". `state.json` records `flavor: "gift"`, `bib_name: "Maria"`. | pending |
| F3 | install.sh --update on already-installed box skips done phases idempotently | 1. After F1, capture timestamp of `/var/lib/buildersinabox/state.json`. 2. Re-run `sudo /repo/payload/install.sh --update --skip-wizard`. 3. Compare state.json before/after, inspect bootstrap.log for phase decisions. | Exit 0. `state.json` mtime updated (state_init touches it) but `phases.stack_installed` stays `true` and no install script re-ran (log shows "stack already installed, skipping" for each phase). User `${BIB_USER}` password not reset. `/etc/systemd/system/getty@tty1.service.d/autologin.conf` unchanged. | pending |
| F4 | install.sh --uninstall removes BIB state and nothing else | 1. After F1, create proof-of-life files: `touch /home/ubuntu/MY_FILE` and `mkdir -p /home/ubuntu/.config/{tailscale,gh}` with `touch /home/ubuntu/.config/tailscale/state.fake /home/ubuntu/.config/gh/hosts.yml /home/ubuntu/.claude/credentials.json`. 2. `sudo /repo/payload/install.sh --uninstall`. 3. Walk filesystem. | Exit 0. Removed: `/opt/buildersinabox`, `/usr/local/bin/biab`, `/usr/local/bin/bd`, `/var/lib/buildersinabox/`, `/var/log/buildersinabox/`, `/etc/profile.d/biab-firstboot.sh`, `/etc/systemd/system/getty@tty1.service.d/autologin.conf`. Preserved: `/home/ubuntu/MY_FILE`, `/home/ubuntu/.config/tailscale/`, `/home/ubuntu/.config/gh/`, `/home/ubuntu/.claude/`, user's `${HOME}` overall. `getent passwd ubuntu` still returns the user (uninstall does not delete the operator). | pending |
| F5 | install.sh --selftest catches reintroduced personal references | 1. On a clean install (post F1), inject a personal ref: `sudo bash -c 'echo "hello Paco" > /opt/buildersinabox/payload/wizard/leak.sh'`. 2. `sudo /repo/payload/install.sh --selftest`. 3. Clean up by removing the injected file. 4. Re-run `--selftest`. | Step 2: exit ≥1 with stderr line naming `/opt/buildersinabox/payload/wizard/leak.sh` and the pattern `\bPaco\b`. Step 4: exit 0 with "Clean. No personal references found." | pending |

### Edge cases

| # | Case | Steps | Expected result | Status |
|---|------|-------|-----------------|--------|
| E1 | --non-interactive missing required env var fails fast with named-var error | 1. `sudo BIB_NAME="" BIB_FLAVOR=default BIB_AI_CLI=claude /repo/payload/install.sh --non-interactive` (BIB_USER omitted). 2. Capture stderr. | Exit ≠ 0 (≤ 64). Stderr contains exactly one error line naming `BIB_USER` as the missing variable. No phase scripts ran (no entries in `/var/log/buildersinabox/bootstrap.log` beyond the preflight failure). No `state.json` written. | pending |
| E2 | --flavor=invalid rejects with named error | 1. `sudo BIB_USER=ubuntu BIB_NAME="" BIB_FLAVOR=bogus BIB_AI_CLI=claude /repo/payload/install.sh --non-interactive`. 2. Capture stderr. | Exit ≠ 0. Stderr names `BIB_FLAVOR=bogus` as invalid and lists allowed values (`default`, `gift`). No phases run. | pending |
| E3 | state.json schema v1 → v2 migration is non-destructive on a partially-completed install | 1. Manually stub a v1 state file with mixed phases done/pending: `sudo tee /var/lib/buildersinabox/state.json <<EOF { "version": 1, "ai_cli": "claude", "phases": { "stack_installed": true, "password_set": true, "tailscale_done": false, ... } } EOF`. 2. Run `sudo /repo/payload/install.sh --update --skip-wizard`. 3. Read state.json after. | `state.json` is now `version: 2`, with `bib_user` populated from `${SUDO_USER}` resolution, `bib_name: ""`, `flavor: "default"`. All previously-done phases still `true`. All previously-pending phases still `false`. No phase that was `true` got re-executed (log shows skip lines). Original file backed up to `/var/lib/buildersinabox/state.json.v1.bak` (migration safety). | pending |
| E4 | install.sh without sudo fails with clear privilege error | 1. As non-root user: `/repo/payload/install.sh --non-interactive` (no sudo, valid env vars). 2. Capture stderr. | Exit ≠ 0. Stderr contains a single line stating root is required (no Python-style traceback, no permission-denied cascade from a downstream apt or systemd call). The `require_root` preflight catches it before any phase runs. | pending |
| E5 | BIB_NAME with shell metacharacters renders safely in banner | 1. Run install with `BIB_NAME="O'Brien; rm -rf /"`. 2. Inspect rendered banner and welcome.txt substitution. | Banner shows literal characters (proper escaping in envsubst). No shell command executed. `state.json` records the raw string verbatim. `/home/ubuntu/` not deleted. | pending |
| E6 | --uninstall on a box that was never installed exits cleanly | 1. On a fresh VM with no BIB artefacts: `sudo /repo/payload/install.sh --uninstall`. 2. Capture stdout/stderr. | Exit 0. Stderr (or stdout) reports "Nothing to uninstall — no BIB state found" (or equivalent). No errors, no missing-file traceback. | pending |

### Regression

- [ ] **Paco's v0.1 box (still on `bootstrap.sh` tarball, frozen):** verify out-of-scope per Jesús's 2026-06-09 decision. Confirmation step: do NOT push any of these changes to Paco's box. Test by inspecting `/opt/buildersinabox/payload/bootstrap.sh` on his box (if accessible via Tailscale) — it must still exist and not have been renamed. If the repo gets pushed there accidentally, his wizard breaks because the new `install.sh` doesn't exist on his tarball and his profile.d trigger would log a "not found" error.
- [ ] **Gift flavor equivalence with Paco's v0.1 UX (semantic regression):** after F2 passes, manually compare the rendered banner + welcome text against the v0.1 reference (saved as a maintainer artefact in `payload/flavors/gift/maintainer/reference-banner.txt`) for visual equivalence. Block-letter `${BIB_NAME}` (e.g., "MARIA") renders with same kerning rules as v0.1's "PACO". Tone, line breaks, paragraph order all match.
- [ ] **ISO autoinstall path:** rebuild the ISO (`bash iso-builder/build.sh`) and boot it in a VM. Confirm: autologin still works (autologin.conf rendered at first boot from .in template), `firstboot.pending` triggers `install.sh`, Phase A reaches `36-phone-bridge.sh` and pauses cleanly. Phase B (SSH resume) finishes and removes the pending marker.
- [ ] **Wizard chain order unchanged:** `payload/wizard/run.sh` still calls the steps in the same sequence (`01-set-password` → `10-tailscale-up` → `35-ssh-finalize` → `36-phone-bridge` → `05-choose-cli` → `38-ai-cli-login` → `40-scaffold` → `50-tmux`). De-personalize does not reorder or skip any step.
- [ ] **Skill SKILL.md placeholders render correctly:** open `/tutorial`, `/morning-check`, `/first-project`, `/extend-yourself` in Claude Code after install. Where copy previously said "Paco", it now says the `${BIB_NAME}` value (or no name at all if empty) without leaving raw `{{BIB_NAME}}` template syntax visible.
- [ ] **`getty@tty1.service.d/autologin.conf` correctness:** after install, `systemctl cat getty@tty1.service` shows the drop-in with `User=${BIB_USER}` resolved to the actual operator. Reboot and verify autologin lands in the operator's shell, not in the gdm prompt.
- [ ] **`tools/check-no-personal-refs.sh` still catches the original 5 patterns:** existing PATTERNS (`jesusmartincalvo`, `hezumartin`, `virtualdev`, `@virtualdev`, `\bJesus\b`) still trigger detection on planted strings. Test by adding a temp file with each pattern, running guard, removing files.
- [ ] **`git archive HEAD | tar -tvf -` clean:** the tarball produced by `git archive` does not contain `payload/flavors/gift/maintainer/` (export-ignore working with new path) and does not contain top-level `gift/` (since it moved). It DOES contain `payload/flavors/default/`, `payload/flavors/gift/copy/`, and `payload/flavors/gift/manifest.sh`.

### Testing criteria

```bash
# 1) Static checks — run from repo root
shellcheck payload/install.sh payload/lib/*.sh payload/wizard/*.sh payload/install/*.sh tools/check-no-personal-refs.sh
bash -n payload/install.sh payload/lib/common.sh
[ ! -e payload/bootstrap.sh ]  # rename completed
[ -x payload/install.sh ]

# 2) Personal-refs guard — must return 0
bash tools/check-no-personal-refs.sh

# 3) No paco/Paco outside flavors/
! grep -rIE --include='*.sh' --include='*.md' '\bpaco\b|\bPaco\b' payload/ --exclude-dir=flavors

# 4) No Spanish diacritics in default-flavor scripts (excluding flavors/gift/)
! grep -rIE --include='*.sh' '(¿|¡|á|é|í|ó|ú|ñ)' payload/wizard payload/lib payload/install

# 5) git archive is clean
git archive HEAD | tar -tvf - | grep -E '(^|/)gift/|payload/flavors/gift/maintainer/' && echo FAIL || echo OK

# 6) End-to-end smoke tests inside fresh Ubuntu 24.04 VM (one VM per case)
#    F1 — default flavor
sudo rm -f /var/lib/buildersinabox/state.json
BIB_USER=ubuntu BIB_NAME="" BIB_FLAVOR=default BIB_AI_CLI=claude BIB_OAUTH_MOCK=1 \
  sudo -E /repo/payload/install.sh --non-interactive --skip-wizard
jq -e '.version == 2 and .bib_user == "ubuntu" and .flavor == "default"' \
  /var/lib/buildersinabox/state.json

#    F2 — gift flavor
sudo rm -f /var/lib/buildersinabox/state.json
BIB_USER=maria BIB_NAME="Maria" BIB_FLAVOR=gift BIB_AI_CLI=claude BIB_OAUTH_MOCK=1 \
  sudo -E /repo/payload/install.sh --non-interactive --skip-wizard
grep -q "MARIA" /var/log/buildersinabox/bootstrap.log

#    F4 — uninstall preserves user data
touch /home/ubuntu/MY_FILE
mkdir -p /home/ubuntu/.config/{tailscale,gh} /home/ubuntu/.claude
touch /home/ubuntu/.config/tailscale/state.fake /home/ubuntu/.claude/credentials.json
sudo /repo/payload/install.sh --uninstall
[ ! -e /opt/buildersinabox ] && [ ! -e /usr/local/bin/biab ] && [ ! -e /var/lib/buildersinabox ]
[ -e /home/ubuntu/MY_FILE ] && [ -e /home/ubuntu/.config/tailscale/state.fake ] && [ -e /home/ubuntu/.claude/credentials.json ]

#    F5 — selftest catches injected leak
sudo bash -c 'echo "hello Paco" > /opt/buildersinabox/payload/wizard/leak.sh'
sudo /repo/payload/install.sh --selftest && echo "FAIL: should have caught Paco" || echo "OK"
sudo rm /opt/buildersinabox/payload/wizard/leak.sh
sudo /repo/payload/install.sh --selftest && echo "OK: clean"

#    E1 — missing env var fails clean
sudo BIB_NAME="" BIB_FLAVOR=default BIB_AI_CLI=claude /repo/payload/install.sh --non-interactive 2>&1 | grep -qE "BIB_USER.*(missing|required|unset)"

#    E3 — v1→v2 migration
sudo tee /var/lib/buildersinabox/state.json <<'EOF'
{ "version": 1, "ai_cli": "claude", "phases": { "stack_installed": true, "password_set": true } }
EOF
sudo /repo/payload/install.sh --update --skip-wizard
jq -e '.version == 2 and .phases.stack_installed == true and .phases.password_set == true' \
  /var/lib/buildersinabox/state.json
[ -e /var/lib/buildersinabox/state.json.v1.bak ]

# 7) Existing dryrun.sh (updated for install.sh) still passes
bash payload/test/dryrun.sh
```

### Notes on observability

- Bootstrap log at `/var/log/buildersinabox/bootstrap.log` retains the same ISO-8601 UTC format. Each phase logs `phase=X status=skip|run|done`. Translation must preserve these log keys (they're parsed by FEAT-005 tutorial state checks and by Observio adapter when it lands as a BIAB module).
- Sentinel files for visual inspection during VM testing: `/var/lib/buildersinabox/state.json` (phase tracker), `/var/lib/buildersinabox/firstboot.pending` (presence triggers wizard on next login), `/var/lib/buildersinabox/state.json.v1.bak` (migration backup).
- For F2 gift-flavor visual diff: capture stdout of the wizard banner section to a file and `diff` against the maintainer reference. Acceptable diff = only the substituted name (`MARIA` vs `PACO`). Any other diff is a regression.

## §5 — Implementation

> Owner: Tech Lead. To be filled during spec-implementer run.

### Branch

`feat/FEAT-006`

### Progress

| Task | Status | Commit | Notes |
|------|--------|--------|-------|
| — | pending | — | — |

### Decisions taken during implementation

- [YYYY-MM-DD] —

### Blockers

- [ ] —

### Post-implementation verification

- [ ] All `<verify>` checks from §2 pass on a fresh Ubuntu 24.04 VM
- [ ] `install.sh --non-interactive` completes end-to-end with env vars
- [ ] `install.sh --update` re-runs idempotently on an already-installed box (no errors, no destructive ops)
- [ ] `install.sh --uninstall` cleanly removes BIAB state and leaves user data intact
- [ ] `tools/check-no-personal-refs.sh` returns clean on the entire shippable tree
- [ ] No secrets in the diff
- [ ] No scope creep outside §1
- [ ] Shellcheck passes on every modified `.sh`

## §6 — Feedback

> Jesus fills this in after reviewing the PR or running the installer on a fresh VM.

### Bugs found

(none yet)

### Suggested improvements

(none yet)
