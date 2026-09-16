# Changelog

All notable changes to Builders in a Box are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Opt-in night shift** (`biab pack add night-shift`): at 03:00 the box picks one spec you have already validated, implements it with your AI CLI, and stops at the pull request. Validated spec at night, pull request in the morning, on hardware you own.
  **It spends your subscription unattended, so it is switched off twice over.** Installing Builders in a Box schedules nothing; adding the pack installs a *disarmed* timer that only simulates — `biab-night-shift run` names the spec it would pick and spends nothing. Real passes need `sudo biab-night-shift arm`, which prints the per-pass cap ($2.00), the one-hour systemd timeout and your last seven days of spend **before** asking you to type a confirmation word. `disarm` stops the spending without uninstalling anything, and `BIAB_NIGHT_SHIFT_DISABLED=1` or a sentinel file skips a night.
  It stops at the pull request. A `PreToolUse` hook, loaded from the command line so the agent cannot remove it by editing its own settings, allows only `git push [-u] origin <feature-branch>` and a handful of `gh` verbs, and blocks merges, releases, pushes to main, the GitHub API, CI edits, root and eval — from the shell and from the file-editing tools, with MCP switched off for the pass. That is a brake; the lock is branch protection on your repository, which a real pass checks for before spending anything (see *Security* below). It also refuses to run on a dirty working tree, takes one spec per night with no retries, and will not re-attempt a spec for 14 days — the brake that stops an ambiguous spec becoming a recurring bill.
  Today only Claude Code can be armed (arming requires a headless mode, a spend cap and a mechanical tool guard); on Antigravity or Codex the pack installs and simulates, and tells you so when you add it rather than when you try to switch it on.
- **The browser pack can finish a form, and gets past sites that refuse a headless desktop browser.** `biab-browse run <url> < workflow.json` runs up to 20 `fill`/`click`/`select`/`wait_for`/`read_text` actions in one browser, on one page, in order, stopping at the first failure. Until now a multi-step task meant one `biab-browse open` per step and each call closed the browser, so filling a field and then submitting it submitted an empty form. The workflow arrives on stdin rather than as an argument, so a password inside one is not visible to anyone who can list processes, and is staged in a root-owned directory the browser engine can read from but not write to.
  It also picks how to open the page. A pilot on this stack measured Reddit and Sephora serving a 403 to desktop headless while the same Chromium, told it was an iPhone, got a 200 — so the default `--mode auto` tries desktop headless, then iPhone emulation, then a headful browser on a temporary virtual display, and says on stderr which one worked. `--mode desktop|iphone|headful` pins one.
  **It is a fallback, not a retry loop, and not evasion.** Modes only ever switch *before* the first action, so a click or a form submission is never replayed against another mode. A CAPTCHA does not trigger a fallback (nothing up the ladder solves a challenge), and neither do timeouts, 404s, 429s, 5xxs or login walls — those are real answers from the site and are reported as themselves. There are no stealth patches, no proxy rotation and no CAPTCHA solving, and iPhone mode is documented as Chromium emulation, not Safari.
- The AI-CLI registry gained an `unattended` capability and an `ai_cli_unattended_cmd` verb, so what a box may do unsupervised is declared once in its adapter instead of inferred from the CLI's name.
- The browser pack's test suite grew 44 cases for the above (25 to 69): the mode ladder and its exit codes, a local fixture server that serves a 403 interstitial to a desktop user agent and the real page to an iPhone (so the claim is pinned deterministically instead of depending on a third party's mood), a multi-step workflow proving page state survives across actions, a failing action proving the ones after it do not run, and the full workflow schema — including that an article containing the words "access denied" is not mistaken for being denied access.
- `payload/test/uninstall-contract.sh` grew eleven cases (`NS-1`…`NS-11`) covering everything the night shift leaves outside `/opt`: both systemd units, the runner, the file that authorises spending, the state tree and the guard directory — including that the timer is disabled before its unit file is deleted, that `daemon-reload` comes afterwards, and that a stranger's timer in the same directory survives byte-identical.

### Security
- **A workflow is staged where the browser user cannot reach it.** Caught in review before release: the first version of `biab-browse run` wrote the workflow into a directory under `/var/lib/biab-browser`, which the browser user owns. Write permission on a directory is what governs rename and unlink — whoever owns the entry — so the browser user could have replaced the path with a symlink in the window between root creating the file and root writing to it. `chmod`, a `>` redirect and `chown` all follow symlinks, so that would have let a Chromium sandbox escape truncate a root-owned file of its choosing and then be handed ownership of it, defeating the dedicated unprivileged user that exists to contain exactly that. The workflow now lives in `/run/biab-browser` (root-owned, mode 0711, cleared on reboot and on uninstall), stays owned by root, and is only group-readable by the browser user, which is all the driver needs. The pack's other directories keep their existing ownership: there the browser user writes and root only reads back, with the recheck that has guarded the screenshot handoff since 0.2.0.
- **Night shift: the no-merge guard is a whitelist now, and branch protection is the lock.** The first guard was a blacklist of seven spellings; a battery of 27 ways to merge, push to main or deploy walked past 22 of them (`git push` with no refspec while on main, `git push origin "main"`, `gh api -X PUT …/merge`, `gh workflow run deploy.yml`, `curl` with `gh auth token`, a workflow file edited with the Write tool…). The guard now allows only `git push [-u] origin <feature-branch>`, `gh pr create` and a few read-only `gh` verbs; blocks the GitHub API, HTTP clients against github.com, credential reads, `git remote`/`git config`/`git tag` tampering, edits to `.git/` and `.github/workflows/` (shell and file tools), `sudo` and `eval`; and the pass runs with `--strict-mcp-config --disallowedTools mcp__*` so a GitHub MCP server cannot hand the agent a merge tool the hook never sees. A security review of the rewrite added what a lexical guard also has to see: quoted verbs (`git "push"`), git/gh environment overrides (`GIT_CONFIG_KEY_0=remote.origin.url…`, `GH_REPO=`), shell functions and aliases, writes to `~/.gitconfig` and `~/.config/git/`, reads of credential stores through the Read/Grep tools, the repository's real default branch (not just `main`), and rulesets with bypass actors. What it still cannot catch — a script written to disk and then executed, or a variable holding the word `git` — is why a hook is a brake and not a lock; and the lock covers merging into *your* repository, not pushing the code somewhere else, which only the hook guards. The lock is a required review on the default branch, which the agent, acting as the owner, cannot give itself: a real pass now asks GitHub (classic protection or rulesets) before spending anything and aborts with `default-branch-not-protected` if it is missing; `sudo biab-night-shift arm --unprotected-ok` accepts running without it, root-owned like the mode file, and the morning summary flags every pass that ran that way. README, landing page, installer and `arm` copy no longer claim "can't merge without you" on the strength of the hook alone.

### Changed
- `extend-yourself` no longer claims linger is enabled at first boot. It only is on the USB/ISO path; after a `curl | sudo bash` install a user-level timer stops firing as soon as your last session ends, which is why the night shift ships a system unit instead.
- The starter spec template carries a `validated_by` field. Without it, a box in starter mode could never produce a spec the night shift was allowed to pick up — the feature would have been unusable out of the box.
- The scaffold never replaces a hook you already had. Registering our hooks into `~/.claude/settings.json` is now additive for every event: `PreToolUse`, `PostToolUse` and `Stop` used to be treated as ours to own and overwrote whatever you had configured there. Your hooks stay, ours run alongside them, and re-running the scaffold still adds no duplicates.

### Fixed
- A workflow piped into `biab-browse run` is no longer silently truncated. The wrapper slurped stdin with `dd bs=65537 count=1`, which issues a single `read(2)` — and a read from a pipe returns only what happens to be buffered right then. Measured: a payload written in two chunks 300ms apart arrived 36 bytes short with no error at all, leaving the caller to puzzle over "invalid workflow JSON"; a cut that happened to stay valid JSON would have *run*, short.
- An unknown `--mode` reported the wrong exit code. `mapfile -t attempts < <(browser_mode_attempts "$mode")` reports `mapfile`'s status and never the process substitution's, so the `|| exit $?` guarding it was dead code: the run ended up exiting 6, the code reserved for "the site blocked us", instead of 2 for a usage error.
- A failed merge can no longer cost you your `~/.claude/settings.json`. The scaffold read and rewrote the file in one step, so if the merge errored the file was truncated to a blank line — taking unrelated settings (`env`, `apiKeyHelper`, and the rest) with it. It now leaves the file untouched and warns instead.
- The hooks + scaffold-seed test suite (`payload/hooks/tests/run-tests.sh`) now runs in CI and actually exercises the scaffold. It had been aborting partway through for some time, skipping roughly 40 later assertions — red, with nothing running it to notice.

## [0.2.0] - 2026-07-12

### Added
- **Usage coach** (`quota` skill, core): reconstructs Claude plan spend from the box's own session transcripts (by model and project), a `UserPromptSubmit` nudge that suggests a cheaper model for routine work when you're on an expensive one, and an optional status-line segment showing the running weekly total (installed only when you don't already have a status line). No new account or API — it reads what's already on the box.
- **Opt-in browser pack** (`biab pack add browser`): gives the agent a sandboxed headless Chromium it can read/click/fill/screenshot live pages with, without a desktop. Off by default; runs as a dedicated locked-down `biab-browser` user (no sudo, no access to the operator's `~/.ssh` or project files), with the setuid sandbox enabled and a fail-closed default (never `--no-sandbox`). `biab pack {list,add,remove}` manages it; `--uninstall`-clean.
- **Session-start spec reminder**: a `SessionStart` hook surfaces any unfinished specs (`specs/draft`/`specs/active`) when you open a session, so long-running work doesn't rot unseen. Silent when there's nothing pending; fail-open (never blocks a session).
- **Optional `incident` skill** (`biab add incident`): keeps a running `INCIDENTS.md` log (symptom, root cause, fix, rule learned) with auto-numbered `ERR-NNN` entries.
- Email capture on the landing page: a release-notes signup form backed by a Cloudflare Pages Function (`/subscribe`) and a Resend audience.
- Lockout guard: if someone is connected over SSH from outside the tailnet (typical on a VPS), the wizard now warns and asks before restricting sshd to the Tailscale address, and prints the exact command (`BIB_SSH_FORCE_TAILSCALE=1`) to apply the restriction later.
- Root-only hosts (fresh VPS images): the installer now offers to create the target user account instead of failing with an error.
- Releases pin the published bootstrap: `tools/publish.sh --tag vX.Y.Z` rewrites the served `install.sh` to clone that tag by default, so the script you audit fetches exactly the code it runs.
- README section "What it changes on your system" documenting every path the installer touches and the `--uninstall` flag; linked from the landing page.
- README "Security model" section (zero public ports, tailnet-only auth, lockout-safe hardening, release-pinned bootstrap); landing repositioned security-first.
- Demo/visual launch plan for the README and landing page (asciinema of the install, phone screenshot of Claude Code over Tailscale).
- `CHANGELOG.md`.

### Fixed
- `biab update` and re-running the bootstrap over an existing checkout now hard-sync to the published ref. Previously a tag-pinned clone kept a tag-only fetch refspec (making every update a silent no-op) and the snapshot-based release history could never fast-forward.

### Changed
- Public docs (landing + README) now lead with spec-driven development's value and are tool-agnostic — no `tmux`/Tailscale brand names in the user-facing copy — with explicit dual-CLI framing (works the same with Claude Code or Antigravity).
- The Spec-Driven Development skills (`sdd-*`) now install by default on every box instead of being opt-in behind `biab add sdd`. `/sdd-coordinator` is the entry door; the tutorial mentions the workflow softly without imposing it. `biab add sdd` is now a friendly no-op (the `biab add` framework stays for future skill groups).
- Interactive installs now ask which AI CLI to run (claude or gemini) instead of silently persisting the default — which made the wizard's choice step always skip.
- README and landing state the account requirements plainly (paid Claude subscription or Google account for Gemini; Tailscale's free plan is plenty), and the "~15 minutes" claim now refers to time-to-first-SSH.
- Interactive prompts in `install.sh` read from `/dev/tty`, so they work under `curl | sudo bash`.
- Trimmed tutorial Beat 7 to `tmuxc` + `/morning-check`, with the brain-dump `bd` reduced to a one-line mention.
- Genericized USB-gift copy that had leaked into the generic install path (re-flash instructions, "unplug the monitor", the Windows-recovery section of the device README).
- The bundled GitHub login now also imports your GitHub SSH keys into `~/.ssh/authorized_keys`, so `ssh <user>@<host>` can authenticate with your key instead of your account password.
- The optional Spec-Driven Development skills (`biab add sdd`) are now in English and rewritten for the single-session model: roles are invoked as in-session skills (`/sdd-spec-writer`, `/sdd-qa`, `/sdd-growth`, `/sdd-docs`) instead of background agents, with no chat-app integration. References now point only to bundled skills.
- The bundled coach example (`FEAT-002`) is now in English.

### Removed
- "Modules coming: Conerator, Observio, Pathtrip" from the landing footer and the README roadmap.
- Orphaned stale `payload/tutorial/welcome-card.md` (pre-single-session copy).
- Orphaned first-boot scripts that were no longer wired into the wizard (`20-gh-login.sh`, `60-slack-bootstrap.sh`) and their stale references.

## [0.1.3] - 2026-06-15

### Changed
- Pre-launch content polish: rewrote the top-level `CLAUDE.md` as a public contributor guide and removed stale pre-single-session copy ("three tmux windows") across the wizard, tutorial, and skills.

### Fixed
- First-login auto-attach and the `tmuxa` shortcut now target the real `ai-platform` tmux session (they pointed at a non-existent `main` session).

### Removed
- The deferred `pairing/` service is no longer shipped in the release tarball.

## [0.1.2] - 2026-06-14

### Changed
- Normalized user-facing copy ("café" → "coffee shop").

## [0.1.1] - 2026-06-13

### Fixed
- The installer now actually installs the `biab` and `bd` commands.
- A failed `ssh.service` restart no longer aborts the whole install.

## [0.1.0] - 2026-06-13

### Added
- Initial public release: one-command install on Ubuntu 24.04, OAuth device flows (Tailscale, Claude Code / Gemini, GitHub), a scaffolded `~/ai-platform/` workspace, a guided `/tutorial`, bundled skills, and an optional self-installing USB image.
- `curl | bash` bootstrap and the `buildersinabox.com` landing page.
- OSS hygiene: README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, CI, issue/PR templates.

[Unreleased]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.4...v0.2.0
[0.1.3]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/sixsevenappslab/buildersinabox/releases/tag/v0.1.0
