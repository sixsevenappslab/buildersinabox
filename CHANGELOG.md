# Changelog

All notable changes to Builders in a Box are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Demo/visual launch plan for the README and landing page (asciinema of the install, phone screenshot of Claude Code over Tailscale).
- `CHANGELOG.md`.

### Changed
- The bundled GitHub login now also imports your GitHub SSH keys into `~/.ssh/authorized_keys`, so a raw `ssh <user>@<host>` works as a fallback when Tailscale SSH or the Claude Code app is unreachable.
- The optional Spec-Driven Development skills (`biab add sdd`) are now in English and rewritten for the single-session model: roles are invoked as in-session skills (`/sdd-spec-writer`, `/sdd-qa`, `/sdd-growth`, `/sdd-docs`) instead of background agents, with no chat-app integration. References now point only to bundled skills.
- The bundled coach example (`FEAT-002`) is now in English.

### Removed
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
