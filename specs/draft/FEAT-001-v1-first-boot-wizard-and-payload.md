---
id: FEAT-001
title: v1-first-boot-wizard-and-payload
project: buildersinabox
status: draft
priority: high
complexity: high
created: 2026-05-25
validated_by: null
---

# FEAT-001: v1 first-boot wizard and payload

## §0 — Strategy

> Owner: Product Lead

- **Why now:** v1 needs a working DIY path (clone repo on any Ubuntu 24.04 → run `bootstrap.sh` → land in tmux+Claude Code) **before** the mini PC arrives. The payload is the part we can build, test in a VM, and validate without hardware. Locking it down early de-risks every later phase (iso-builder, autoinstall, USB flashing, eventual pairing v2).
- **Hypothesis:** if a developer with a fresh Ubuntu 24.04 install can go from `git clone` to "three tmux windows with Claude Code, accessible from Termius on my phone via Tailscale" in under 15 minutes, the v1 promise is technically proven. The USB just automates step 0 (installing Ubuntu).
- **OKR / goal alignment:** ships the open-source MVP that the commercial hardware tier is built on. Without the payload, there is no product.
- **Cost of not doing it:** every other piece of the project (ISO builder, USB flashing, pairing v2, marketing) is blocked. We can't even test what we'd ship.

## §1 — Product requirements

> Owner: Product Lead

### What it does

A user with a fresh Ubuntu Server 24.04 install (mini PC or VM) clones this repo, runs `sudo payload/bootstrap.sh`, and within ~15 minutes ends up with:

1. **System stack installed:** Tailscale, GitHub CLI (`gh`), **the chosen AI CLI** (Claude Code *or* Gemini CLI — see step 2), tmux, git, build essentials. Idempotent — re-running is safe.
2. **TUI setup wizard executed** (on first run only) that walks the user through:
   - **AI CLI choice:** Claude Code (default) or Gemini CLI. One only in v1 — the chosen CLI becomes the one running in all tmux windows and the one invoked by the coach (FEAT-002). The choice is stored in `/var/lib/buildersinabox/state.json` (`ai_cli: "claude" | "gemini"`).
   - Tailscale `up` with device flow — URL printed to console, user opens it on their phone, Tailscale joins their tailnet.
   - GitHub `gh auth login` device flow — same pattern.
   - **AI CLI login** — `claude login` or `gemini auth login`, both have OAuth device flows. Same URL-on-console-then-phone pattern.
   - Prompt for a **project name** (free text, validated as a safe slug).
3. **Workspace scaffolded** from `payload/skeleton/` to `~/ai-platform/`. Each folder gets the bundled context files applied: `CLAUDE.md`, `GEMINI.md` and `AGENTS.md` are all written with the same content (rendered from a single source template). This way the user can switch CLIs later without re-scaffolding. Skills (SDD bundle) install to `~/.agents/skills/` (cross-CLI alias supported by both Claude Code and Gemini CLI).
4. **tmux session named `main` created**, with three windows pre-named and pre-launched:
   - `platform` — cwd `~/ai-platform/`, runs the chosen AI CLI on entry.
   - `<project-name>` — cwd `~/ai-platform/projects/<project-name>/`, runs the chosen AI CLI.
   - `stratops` — cwd `~/ai-platform/stratops/`, runs the chosen AI CLI.
   The session persists across SSH disconnects (the user attaches via `tmux attach -t main` from Termius).
5. **SSH configured for phone access** — sshd enabled, password auth disabled (key-only), and a one-time helper prints instructions for adding the user's phone public key (or, if Tailscale SSH is enabled, this step is no-op).
6. **First-boot artifact written** at `/var/lib/buildersinabox/state.json` so the wizard does not re-prompt on reboot. A `--force` flag re-runs it.

### Boundaries

- **Always:**
  - Run as root via `sudo`. Refuse to run as a non-root user.
  - Be idempotent: re-running on an already-provisioned machine must not break state. Detect "already done" steps and skip.
  - Print every URL the user needs to open clearly to the terminal, with surrounding whitespace and a short label. Never hide them behind a TUI redraw.
  - Use Bash with `set -euo pipefail` for all scripts. POSIX where possible, Bash where readability wins.
  - Log everything to `/var/log/buildersinabox/bootstrap.log` with timestamps in addition to stdout.
  - Validate project name as `^[a-z][a-z0-9-]{1,30}$` and reject reserved names (`platform`, `stratops`, `projects`).
  - Use OAuth device flows for Tailscale, GitHub and the chosen AI CLI. **Never** bundle credentials, tokens, or API keys.

- **Ask first:** *(all resolved 2026-05-25 — see Locked decisions below)*

- **Locked decisions:**
  - **sshd binds to Tailscale interface only** once Tailscale is up. Password auth disabled. Public LAN cannot reach port 22.
  - **No Docker in the base stack.** Per-project install. Keeps the base small (~250 MB lighter, no idle daemons). `sudo apt install docker.io` is a 30s task if a project needs it.
  - **AI CLI runs directly** in each tmux window, no wrapper. If the user exits the CLI they land in bash and can rerun it manually. Honest UX, easier to debug.
  - **v1 ships with Claude Code and Gemini CLI as supported choices.** Codex CLI is deferred to v1.x because it currently lacks an OAuth device flow (requires API key paste) which breaks wizard simplicity.
  - **Skills install to `~/.agents/skills/` as source-of-truth, with a symlink at `~/.claude/skills/<name>`.** Validated empirically on a clean Ubuntu 24.04 VM (Wave 0, see `payload/docs/cli-skills-compatibility.md`): Gemini CLI 0.43 discovers `~/.agents/skills/` natively; Claude Code 2.1.150 still uses `~/.claude/skills/` as canonical, so we symlink. No content drift, no duplication, both CLIs find their skill at their native path.

- **Never:**
  - Do anything that requires a running mini PC to validate (project rule — see CLAUDE.md). Everything in this FEAT must be testable in a VM or container.
  - Implement the `pairing/` backend. v1 is on-console only (locked design decision).
  - Write to `iso-builder/`. That's a separate FEAT once the payload is stable.
  - Install or configure the Slack coach daemon. That is FEAT-002, optional, post-bootstrap.
  - Hardcode any user identity, token, hostname, or path that should come from the running system or user input.
  - Touch WiFi configuration. Ethernet only in v1.
  - Add a web UI or browser-launching code. The console is the only interface.
  - Install Docker. Per-project decision, not baseline.

### Product acceptance criteria

- [ ] On a fresh Ubuntu Server 24.04 VM, `git clone … && sudo payload/bootstrap.sh` finishes successfully in under 15 minutes (excluding human time on OAuth screens) and exits 0.
- [ ] After bootstrap, `tmux ls` shows a session `main` with exactly three windows named `platform`, `<project-name>`, `stratops`.
- [ ] Attaching to that session (`tmux attach -t main`) shows the chosen AI CLI running in each window at the correct cwd.
- [ ] `tailscale status` confirms the device is on the user's tailnet.
- [ ] `gh auth status` confirms login.
- [ ] The chosen AI CLI returns successfully on `--version` and the user is logged in (Claude Code → `claude` status; Gemini CLI → `gemini auth status` or equivalent).
- [ ] `~/.agents/skills/` exists and contains the bundled SDD skills (if Claude was chosen, or if Gemini-compatibility was verified for the skills).
- [ ] Re-running `sudo payload/bootstrap.sh` on the same machine completes in under 30 seconds, makes no destructive changes, and exits 0.
- [ ] Running `sudo payload/bootstrap.sh --force` re-runs the wizard portion while skipping stack reinstall.
- [ ] The user can SSH into the device from a phone (Termius) over Tailscale and immediately run `tmux attach -t main`.

## §2 — Technical spec

> Owner: Tech Lead

### Research

**Files / modules to touch (all new):**

```
payload/
├── bootstrap.sh                    # Top-level orchestrator
├── lib/
│   ├── common.sh                   # log(), die(), is_root(), state_get/set
│   ├── prompt.sh                   # TUI prompt helpers (project name, confirm, choice)
│   ├── oauth.sh                    # Generic "print URL, wait for ready" wrapper
│   └── ai-cli.sh                   # Abstraction: get_ai_cli, ai_cli_login_cmd, ai_cli_binary
├── install/
│   ├── 00-base.sh                  # apt update, build-essential, curl, git, jq, nodejs
│   ├── 10-tmux.sh                  # tmux + ~/.tmux.conf for the target user
│   ├── 20-tailscale.sh             # Tailscale apt repo + install
│   ├── 30-gh.sh                    # GitHub CLI apt repo + install
│   ├── 40-claude-code.sh           # Claude Code CLI install (only if ai_cli=claude)
│   ├── 41-gemini-cli.sh            # Gemini CLI install (only if ai_cli=gemini)
│   └── 50-ssh.sh                   # sshd hardening + Tailscale-only bind
├── wizard/
│   ├── run.sh                      # Orchestrates the wizard steps
│   ├── 05-choose-cli.sh            # Prompt: Claude Code (default) or Gemini CLI
│   ├── 10-tailscale-up.sh          # tailscale up with device flow URL surfaced
│   ├── 20-gh-login.sh              # gh auth login --web (device flow)
│   ├── 30-ai-cli-login.sh          # dispatches to claude login OR gemini auth login
│   └── 40-scaffold.sh              # Prompt project name, copy skeleton, launch tmux
├── systemd/
│   └── buildersinabox-firstboot.service  # one-shot, runs bootstrap.sh on first boot
└── tmux/
    ├── tmux.conf                   # Sensible defaults for mobile SSH
    └── launch-main.sh              # Creates the 3-window session (reads $BIB_AI_CLI)
```

State file: `/var/lib/buildersinabox/state.json` — tracks `ai_cli` (`"claude"|"gemini"`) and completed phases (`stack_installed`, `tailscale_done`, `gh_done`, `ai_cli_done`, `scaffold_done`, `tmux_done`) so each is skippable on rerun.

**External dependencies:**
- Tailscale apt repo (`pkgs.tailscale.com`).
- GitHub CLI apt repo (`cli.github.com/packages`).
- Claude Code installer (npm `@anthropic-ai/claude-code` or official installer — pick whichever Anthropic recommends in their published docs at implementation time). Only installed if user chose Claude.
- Gemini CLI installer (npm `@google/gemini-cli` or official path — confirm at implementation time). Only installed if user chose Gemini.
- Node.js 20+ from NodeSource (required by both CLIs and by the FEAT-002 coach daemon).
- `jq` for state file manipulation.
- All other tools are in Ubuntu 24.04 main.

**Technical risks and mitigations:**

| Risk | Mitigation |
|---|---|
| Claude Code or Gemini CLI install method changes between now and implementation | Each install wrapped in its own script (`install/40-*.sh`, `install/41-*.sh`); if one breaks, swap method without touching the other. Pin versions in constants. |
| Gemini CLI lacks an OAuth device flow on Ubuntu (turns out to need a desktop browser) | Pre-flight check in `wizard/30-ai-cli-login.sh`: if `gemini auth login` returns a URL the user can open on their phone, proceed. If it tries to launch a local browser, abort with clear "Gemini path needs a local browser; choose Claude or use the workaround". |
| SDD skills in `~/.claude/skills/` don't work drop-in under Gemini's `~/.agents/skills/` reader | Investigated as **first action** of Wave 1 (see open item in Locked decisions). If incompatible: v1 ships skills only when Claude is chosen; Gemini works but with a doc note "SDD skills support coming". |
| Tailscale device-flow URL is printed by `tailscale up` to stderr in a way that's hard to surface in a TUI | Run `tailscale up --auth-key=""` is wrong; correct path is `tailscale up` which prints the URL. Capture stderr and re-print with banner. Tested manually in §4 smoke. |
| OAuth flows block forever if user abandons | Each wizard step has a timeout (default 10 min) with a clear "press Enter when done" confirmation step after the URL is shown. |
| `gh auth login` interactive prompts vs scripted use | Use `gh auth login --web --hostname github.com --git-protocol https` and capture the URL it prints. |
| User runs bootstrap on something that isn't Ubuntu 24.04 | Detect via `/etc/os-release`; refuse with a clear error unless `--i-know-what-im-doing` is passed. |
| Re-running wizard mangles scaffold | scaffold step only runs if `state.json.scaffold_done` is false. `--force` resets the flag. |
| systemd unit fires bootstrap before network is up | `After=network-online.target` + `Wants=network-online.target`. |
| Bootstrap killed mid-flight leaves half-installed state | Each phase is small and idempotent; state file is updated only after a phase fully succeeds. |

### Implementation plan (waves)

**Wave 0 — Compatibility spike.** ✅ Complete (2026-05-25). Result: format drop-in compatible; install path is `~/.agents/skills/` with a symlink at `~/.claude/skills/`. See `payload/docs/cli-skills-compatibility.md`.

**Wave 1 — Skeleton + library + base install (testable in VM, no OAuth).**
1. Write `payload/bootstrap.sh` with arg parsing (`--force`, `--skip-wizard`, `--i-know-what-im-doing`, `--ai-cli=claude|gemini`), root check, OS check, state init.
2. Write `payload/lib/common.sh` (logging, state file, error handlers) and `payload/lib/ai-cli.sh` (abstraction).
3. Write `install/00-base.sh`, `install/10-tmux.sh`, `install/20-tailscale.sh` (install only, no `tailscale up`), `install/30-gh.sh`, `install/40-claude-code.sh`, `install/41-gemini-cli.sh`, `install/50-ssh.sh`. Bootstrap picks 40 or 41 based on `$BIB_AI_CLI`.
4. Test on a fresh Ubuntu 24.04 VM that `bootstrap.sh --skip-wizard --ai-cli=claude` and `--ai-cli=gemini` both install everything cleanly and are idempotent on rerun.

**Wave 2 — Wizard with OAuth flows.**
5. Write `payload/lib/oauth.sh` — generic helper: takes a label, an URL-producing command, a "press Enter when done" confirmation, and a verification command (e.g. `tailscale status` returns 0).
6. Write `payload/lib/prompt.sh` with project-name validation and `prompt_choice` helper.
7. Write `wizard/05-choose-cli.sh` — single-choice prompt, persists to state.
8. Write `wizard/10-tailscale-up.sh`, `wizard/20-gh-login.sh`, `wizard/30-ai-cli-login.sh` (dispatches based on `$BIB_AI_CLI`). Each surfaces its URL clearly and waits for confirmation.
9. Write `wizard/40-scaffold.sh` — prompt project name, copy `skeleton/ai-platform/` to `$HOME/ai-platform/`, render `CLAUDE.md` + `GEMINI.md` + `AGENTS.md` from a single source template with the project name substituted. Install skills bundle to `~/.agents/skills/` (subject to Wave 0 outcome).
10. Write `wizard/run.sh` to chain the steps with per-step state.

**Wave 3 — tmux + SSH + systemd one-shot.**
11. Write `tmux/tmux.conf` (mouse on, history-limit 50k, sane defaults for narrow mobile screens).
12. Write `tmux/launch-main.sh` — creates the three-window session, each `cd`ing and running `$BIB_AI_CLI_BIN` (reads from state, fallback to `claude`). Idempotent: if session exists, skip.
13. Harden `install/50-ssh.sh` — disable password auth, ensure Tailscale-only listen post-Tailscale-up.
14. Write `systemd/buildersinabox-firstboot.service` and an installer step that enables it.

**Wave 4 — End-to-end VM dry run + docs.**
15. Document the DIY path in `payload/README.md` (replace the "coming" placeholders).
16. Document a "VM test recipe" in `payload/docs/testing-in-vm.md` (Multipass or libvirt instructions).
17. Run the full bootstrap on a clean VM **for each CLI choice** (claude and gemini). Capture timing, screenshots/asciinema. Iterate until the QA criteria in §4 pass for both paths.

### Quality gates

- [ ] All Bash scripts pass `shellcheck` with no errors.
- [ ] All scripts use `set -euo pipefail`.
- [ ] No secrets, tokens, or hardcoded user identity anywhere in the repo.
- [ ] State file is written atomically (temp file + `mv`) so a SIGKILL never corrupts it.
- [ ] Re-running `bootstrap.sh` produces zero diff in `/etc` or `$HOME` after the first successful run.
- [ ] Scope stays inside §1 boundaries — no pairing/, no iso-builder/, no WiFi.

## §3 — Growth notes

> Owner: Growth Lead

Not applicable in §1 sense. v1 is a developer tool with no marketing surface yet — no signups, no UTMs, no funnels. The "growth lever" is **the DIY path works flawlessly**, which is what makes the project shareable on Twitter/HN/Reddit. Treat the README rendering after this FEAT as the launch artifact.

Post-FEAT actions for marketing (separate work):
- Record a ≤90s asciinema of the full DIY flow for the README.
- Tagline test: "Plug a USB. Boot a mini PC. Code from your phone." vs alternatives.

## §4 — QA

> Owner: QA Lead

### Functional cases

- [ ] **Happy path, DIY, Claude.** Fresh Ubuntu Server 24.04 VM, `sudo payload/bootstrap.sh`, choose Claude in wizard. Completes, OAuth flows succeed, scaffold created, tmux session running, `claude` alive in all three windows.
- [ ] **Happy path, DIY, Gemini.** Same as above but choose Gemini. `gemini` alive in all three windows.
- [ ] **`--ai-cli=claude` and `--ai-cli=gemini` flags** skip the wizard CLI-choice step and behave consistently with interactive selection.
- [ ] **Happy path, rerun.** Same VM, `sudo payload/bootstrap.sh` again. Exits 0 in under 30s, no changes.
- [ ] **Force rerun wizard.** `sudo payload/bootstrap.sh --force`. Re-runs wizard, allows user to re-enter project name (or confirm existing), does not reinstall the stack.
- [ ] **Skip wizard.** `sudo payload/bootstrap.sh --skip-wizard` installs stack but exits before any OAuth — useful for CI / image baking.
- [ ] **Project name validation.** Names with spaces, uppercase, special chars, reserved words → rejected with clear error and re-prompt.
- [ ] **tmux session shape.** After bootstrap, `tmux list-windows -t main` shows exactly 3 windows in the right order with the right names and cwds.

### Edge cases

- [ ] **Non-Ubuntu OS** (e.g. Debian 12): bootstrap aborts with a clear message pointing at `--i-know-what-im-doing` for power users.
- [ ] **Non-root invocation:** aborts immediately with a clear "run me with sudo" message.
- [ ] **No network at start:** clear error referencing the Ethernet-only assumption, exit non-zero.
- [ ] **Tailscale already up** before bootstrap: detect and skip the `tailscale up` step.
- [ ] **`gh` already authed** for a different account: prompt the user "keep current account or re-auth?" — default keep.
- [ ] **Claude Code already installed but not logged in:** skip install, run wizard step.
- [ ] **User aborts an OAuth step (Ctrl+C):** state file not updated, exit non-zero, helpful message: "rerun bootstrap.sh to resume".
- [ ] **`/var/lib/buildersinabox/state.json` corrupted:** detect on read; bootstrap prints how to reset (`rm` the file and rerun).
- [ ] **Disk near full:** pre-flight check warns if `/` has <2 GB free.

### Regression plan

- [ ] Shellcheck runs in CI on every PR touching `payload/**`.
- [ ] A `make test-vm` (or equivalent script in `payload/docs/testing-in-vm.md`) brings up a Multipass VM, runs bootstrap end-to-end with mocked OAuth steps (env var `BIB_OAUTH_MOCK=1` short-circuits the device flows), and asserts the acceptance criteria.

### Smoke tests post-deploy

(There is no "deploy" — this ships as a repo. "Post-merge" = on `main`.)

- [ ] Pull a fresh clone on a freshly-installed Ubuntu 24.04 VM; run bootstrap; assert all §1 acceptance criteria pass manually once before tagging a release.

## §5 — Docs (post-merge checklist)

- [ ] Update `payload/README.md` — replace every "coming" placeholder with the real script location.
- [ ] Update top-level `README.md` — if anything in the user journey shifted (it shouldn't).
- [ ] Add `payload/docs/testing-in-vm.md` with the Multipass recipe.
- [ ] Add `payload/docs/troubleshooting.md` covering the top 5 failure modes we hit during VM testing.
- [ ] Update project `CLAUDE.md` if any conventions emerged (logging path, state file location, mock env var).
- [ ] No public API to document yet (pairing v2 will add one).
- [ ] Capture an asciinema of the full DIY flow and link it from the top-level README.

## §6 — Feedback (post-completed)

*Filled in after the FEAT ships.*
