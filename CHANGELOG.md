# Changelog

All notable changes to Builders in a Box are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Opt-in night shift** (`biab pack add night-shift`): at 03:00 the box picks one spec you have already validated, implements it with your AI CLI, and stops at the pull request. Validated spec at night, pull request in the morning, on hardware you own.
  **It spends your subscription unattended, so it is switched off twice over.** Installing Builders in a Box schedules nothing; adding the pack installs a *disarmed* timer that only simulates — `biab-night-shift run` names the spec it would pick and spends nothing. Real passes need `sudo biab-night-shift arm`, which prints the per-pass cap ($2.00), the one-hour systemd timeout and your last seven days of spend **before** asking you to type a confirmation word. `disarm` stops the spending without uninstalling anything, and `BIAB_NIGHT_SHIFT_DISABLED=1` or a sentinel file skips a night.
  It never merges, releases or pushes to your main branch. That is not a line in a prompt: a `PreToolUse` hook, loaded from the command line so the agent cannot remove it by editing its own settings, inspects every shell command and blocks those outright. It also refuses to run on a dirty working tree, takes one spec per night with no retries, and will not re-attempt a spec for 14 days — the brake that stops an ambiguous spec becoming a recurring bill.
  Today only Claude Code can be armed (arming requires a headless mode, a spend cap and a mechanical tool guard); on Antigravity or Codex the pack installs and simulates, and tells you so when you add it rather than when you try to switch it on.
- The AI-CLI registry gained an `unattended` capability and an `ai_cli_unattended_cmd` verb, so what a box may do unsupervised is declared once in its adapter instead of inferred from the CLI's name.
- `payload/test/uninstall-contract.sh` grew eleven cases (`NS-1`…`NS-11`) covering everything the night shift leaves outside `/opt`: both systemd units, the runner, the file that authorises spending, the state tree and the guard directory — including that the timer is disabled before its unit file is deleted, that `daemon-reload` comes afterwards, and that a stranger's timer in the same directory survives byte-identical.

### Changed
- `extend-yourself` no longer claims linger is enabled at first boot. It only is on the USB/ISO path; after a `curl | sudo bash` install a user-level timer stops firing as soon as your last session ends, which is why the night shift ships a system unit instead.
- The starter spec template carries a `validated_by` field. Without it, a box in starter mode could never produce a spec the night shift was allowed to pick up — the feature would have been unusable out of the box.
- The scaffold never replaces a hook you already had. Registering our hooks into `~/.claude/settings.json` is now additive for every event: `PreToolUse`, `PostToolUse` and `Stop` used to be treated as ours to own and overwrote whatever you had configured there. Your hooks stay, ours run alongside them, and re-running the scaffold still adds no duplicates.

### Fixed
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
