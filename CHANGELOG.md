# Changelog

All notable changes to Builders in a Box are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
- The Spec-Driven Development skills (`sdd-*`) now install by default on every box instead of being opt-in behind `biab add sdd`. `/sdd-coordinator` is the entry door; the tutorial mentions the workflow softly without imposing it. `biab add sdd` is now a friendly no-op (the `biab add` framework stays for future skill groups).
- Interactive installs now ask which AI CLI to run (claude or gemini) instead of silently persisting the default — which made the wizard's choice step always skip.
- README and landing state the account requirements plainly (paid Claude subscription or Google account for Gemini; Tailscale's free plan is plenty), and the "~15 minutes" claim now refers to time-to-first-SSH.
- Interactive prompts in `install.sh` read from `/dev/tty`, so they work under `curl | sudo bash`.
- Trimmed tutorial Beat 7 to `tmuxc` + `/morning-check`, with the brain-dump `bd` reduced to a one-line mention.
- Genericized USB-gift copy that had leaked into the generic install path (re-flash instructions, "unplug the monitor", the Windows-recovery section of the device README).
- The bundled GitHub login now also imports your GitHub SSH keys into `~/.ssh/authorized_keys`, so a raw `ssh <user>@<host>` works as a fallback when Tailscale SSH or the Claude Code app is unreachable.
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

[Unreleased]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/sixsevenappslab/buildersinabox/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/sixsevenappslab/buildersinabox/releases/tag/v0.1.0
