# Security Policy

Builders in a Box installs and configures software **as root** on the machine it runs on, and sets up remote access (SSH over Tailscale, and a Paseo daemon on the same private network). We take security reports seriously.

## Reporting a vulnerability

Email **hello@buildersinabox.com** with:

- a description of the issue and its impact,
- steps to reproduce (or a proof of concept),
- the version / commit you tested.

Please **do not** open a public issue for security problems. We'll acknowledge your report within a few days and keep you posted on the fix.

## Scope

Things we especially care about:

- The `curl | bash` bootstrap and `payload/install.sh` — they run as root.
- The OAuth flows (Tailscale, GitHub, the AI CLI) — credentials must stay on the user's machine; we never transmit them anywhere.
- The SSH hardening step and the autologin/first-boot machinery.
- The Paseo daemon (`biab-paseo.service`): its bind address, relay switch, credential handling and the way `--uninstall` removes it.
- Anything that could let a third party reach a user's box or read their tokens.

## Out of scope

- Vulnerabilities in upstream dependencies (Tailscale, GitHub CLI, the AI CLIs, Paseo, Ubuntu) — report those to their projects, though we're happy to know about them.
- The maintainer-only `gift` materials, which never ship to a device.

## SSH end state and recovery

Once Tailscale is up, `sshd` is bound to your private Tailscale address only, so it does not listen on the public internet. Reaching that safe state never locks out the only admin:

- **Home box / behind NAT:** nothing is exposed to begin with, so the bind is applied straight away.
- **VPS with a public IP:** if you're driving the box over its public IP while it's set up, SSH is *not* silently locked to the tailnet (that could cut you off). Instead it's hardened to **key-only** if a key is present, or **held open with a clear warning** if the only credential is your password. It moves to Tailscale-only automatically once you finish `/tutorial` (which imports your GitHub key) or when you re-run the finalize step from a tailnet session.

If you ever get locked out, any one of these restores access without reinstalling:

1. **VPS provider web/serial console** — undo the Tailscale bind and reopen the public listener:

   ```bash
   sudo rm -f /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf \
              /etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf
   sudo systemctl daemon-reload && sudo systemctl reload ssh
   ```

2. **Re-apply the bind once Tailscale routes** (from a session that can reach the box over the tailnet):

   ```bash
   sudo BIB_SSH_FORCE_TAILSCALE=1 /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh
   ```

   Note: `BIB_SSH_FORCE_TAILSCALE=1` binds to the tailnet **without** first checking that the tailnet actually routes — only use it when you have confirmed alternative access. sshd is `reload`ed, not restarted, so an active session survives the bind and you can revert if the tailnet turns out not to route.

3. **Physical console (mini PC)** — keyboard + monitor, same edit as (1).

## The Paseo daemon and its password

On every box, Builders in a Box runs a pinned version of the third-party Paseo daemon as the system service `biab-paseo.service`, under your user. It lets the Paseo app on your phone drive your agents, and it can run shells for you, so what it exposes matters:

- **Network:** it listens on port 6767 on your Tailscale address only — never on the LAN or `0.0.0.0` — and Paseo's relay is switched off. The bind address, the relay switch and the password are set in a root-owned unit and a root-only file, so the agents it launches cannot loosen them by editing `~/.paseo/config.json`.
- **The password is not a defence against your own agents.** The phone password is generated per box, stored in `/etc/buildersinabox/paseo.env` (`root:root`, `0600`) and never written to the repo, state file or logs. But it must be in the environment of the Paseo processes, so **any agent or program running as your box user can read it from `/proc/<pid>/environ`.** That is how Paseo works: your agents already run under that daemon with your permissions. The password keeps other devices on your private network from pairing; it does not, and cannot, protect the box from the agents you run on it. Treat anything that can run commands as you as already trusted with it. Rotate it with `sudo biab paseo pair --rotate`. `sudo biab paseo pair` prints the password only to a terminal, which prevents accidental leaks into a transcript or a log; it is not a boundary against agents, because processes of the box user can read the password from `/proc/<pid>/environ` regardless.
- **Your own Paseo is left alone.** BIAB keeps its state in `~/.biab/paseo` and never adopts, overwrites or deletes an existing `~/.paseo`.
- **Removal:** `sudo /opt/buildersinabox/payload/install.sh --uninstall` stops and deletes the daemon, its units, its pinned binaries, its credential and `~/.biab/paseo` (the last only if it carries our ownership marker).
- **If Paseo is down,** SSH over Tailscale straight into your AI CLI keeps working; `biab status` prints the command.

**Antigravity under Paseo asks before it runs commands, writes files and reads outside your project.** Paseo's own Antigravity plugin starts `agy` with `--dangerously-skip-permissions` and offers no way to change that, so Builders in a Box never uses it: on every box it sets that plugin to disabled, and on an Antigravity box it declares its own provider, `antigravity-acp`, which runs the pinned `agy` as `agy acp --disable-telemetry --add-dir <your home>/.agents/skills` (the absolute path `/usr/local/bin/agy`; those two flags and no other). That mode sends each permission request to the Paseo app, where you allow it once or reject it.

What was measured, with `agy` 1.4.11 in that mode on a test box. It **asks** before it runs a shell command, before it writes a file in the project, your home folder, `~/.biab` or `/var/tmp` (each was tried), and before it reads a file outside the project. It **does not ask** before it reads a file inside the project, before it searches the web or fetches a page, or before it writes in `/tmp`. Your skills folder (`~/.agents/skills`, which the tutorial and the other skills are read from) is the one place outside the project it reads without asking: that is what `--add-dir` is for. A rejection is respected: nothing runs and nothing is written. When it asks, the prompt offers only allow once or reject, with no always-allow; the Auto Accept switch (below) is separate and turns the asking off for that agent. What this means: an agent can read anything inside the project and search or fetch web pages without asking, so what it reads in the project it can also put in a web request; and it can write in `/tmp` without asking. The list describes `agy` 1.4.11; a different `agy` has to be measured again. If you start `agy` yourself over SSH (the emergency path) it is not given `--add-dir`, so it may ask once when it reads a skill; that was not measured.

Reads outside the project ask because Builders in a Box sets `allowNonWorkspaceAccess` to `false` in `~/.gemini/antigravity-cli/settings.json` (with `true`, those reads do not ask). On a box installed before this change, the first `biab update` changes a `true` to `false` there, as your user, once, and tells you; it then writes a mark in the box state and never touches the setting again, so a `true` you set later is yours. If the file is a symbolic link or is not a JSON object, `biab update` leaves it alone, warns you with the file name and the line to set by hand, and tries again next time.

**The rule for the settings behind that is parity, not surveillance.** The permission settings of Claude Code and Codex live in files owned by your user, and so do Antigravity's provider settings (`config.json` in `~/.biab/paseo`). Builders in a Box makes them safe at every start of the daemon: the built-in full-access provider is disabled, `antigravity-acp` is the only Antigravity entry, and any provider you or an agent added that runs Antigravity is removed. If the file cannot be read or written (a symbolic link, invalid content, too large), the service refuses to start rather than start unsafe. While the service runs, nothing watches or undoes changes. `biab status` compares the file with what the last start set and says when it differs; `sudo biab paseo restart` puts the safe settings back. An agent you let edit its own settings can change them, the same way it can switch Claude Code to Bypass or Codex to Full Access. This is a brake, not a lock. Builders in a Box guards the two ids it manages (`antigravity` and `antigravity-acp`); any other provider you add is yours.

**OpenCode under Paseo asks only because Builders in a Box seeds its rules, and only while they hold.** OpenCode's own defaults allow every file edit and shell command, so on its own it would not ask. Builders in a Box writes rules in `~/.config/opencode/opencode.json` that make edits, web fetches and shell commands ask (apart from three exact read-only commands, with no wildcard; `git status` and `git diff` are left out because they run configuration that comes with a repository), as your user and never through a link, adding only keys you do not already have. It then treats OpenCode as running with permission prompts only while that file still says so, and re-checks it at every `biab update`; a `permission` that allows edits or commands without asking, a wildcard that allows more, an `agent` or `mode` block or an agent file that allows anything, a link, a `opencode.jsonc` beside it or invalid JSON means OpenCode is not offered in the app and stays reachable over SSH. The check reads the global file and the other places OpenCode applies from your home folder and the `~/ai-platform` workspace after it (`~/.opencode/`, `~/ai-platform/.opencode/`, `~/ai-platform/opencode.json`, and agent files in those and in `~/.config/opencode/`; measured with `opencode debug agent build`): a link, a JSONC file, invalid JSON or anything that allows actions without asking there means OpenCode is not offered in the app. Limits: it does not see the `opencode.json` of a repository under `~/ai-platform/projects` (which OpenCode lets override the rules) or an `OPENCODE_PERMISSION` or `OPENCODE_CONFIG_CONTENT` environment setting; "Always allow" in the app lasts for the session; and the file is owned by your user, so an agent you let edit its own settings can change it, the same as for Claude Code and Codex. Whether the app really shows the prompt is still to be confirmed on hardware (HARDWARE-PASS.md). OpenCode is installed from a pinned release whose sha256 is checked before anything is written, at `/usr/local/bin/opencode`, owned by root.

**The shell-command guard differs per AI CLI, and it is a brake, not a lock.** Claude Code and Codex get a guard that refuses a list of clearly destructive shell commands before they run (`rm -rf /`, `mkfs`, `dd` to a disk, a fork bomb, `curl … | sudo bash`, a force-push to `main`/`master`); Claude Code's also asks about the risky-but-legitimate ones, while Codex's only refuses and leaves those to Codex's own approval rules. OpenCode gets a partial guard: deny keys appended to `permission.bash` in its `opencode.json` that cover a smaller set, cannot see a pipe or a quoted target, and are overridden by a project's own `opencode.json` that allows everything and by the `OPENCODE_PERMISSION` and `OPENCODE_CONFIG_CONTENT` settings; whether a subagent obeys them is not confirmed. Antigravity gets none from Builders in a Box: only its own prompts protect it. The README's table is generated from what each adapter declares, and `biab status` says what your box has. Limits that apply wherever there is a guard: it is a list of patterns, not a sandbox, so a destructive command written in a way no pattern lists gets through; it does not protect reads, so a secret in `.env` or `~/.ssh` is not covered; it lives in a file in your home folder, so an agent you let edit its own settings can remove it (`biab status` notices a changed Codex entry or missing OpenCode keys, but cannot prevent it); and no root-owned lock is installed on purpose, because that would need `sudo` and bind you to rules you could not loosen. Codex runs its guard only after you approve it once (`codex`, then `/hooks`) and skips it, `codex exec` included, until then. All of this is checked by tests in the repository; watching each guard refuse a command in a real, logged-in session on a real box is a hardware pass still to be done, so none of it is a claim about a live session yet.

**Auto Accept is a switch you control, per agent.** The Paseo app has an "Auto Accept" switch on each agent. Turned on, that agent stops asking, exactly like Bypass for Claude Code and Full Access for Codex. Builders in a Box never turns it on and has no setting for it. Paseo's unattended runs (schedules, and agents started by another agent without a person present) turn it on by default, so an Antigravity agent started that way will not ask. In the pinned Paseo version nothing removes that switch.

**Antigravity's own configuration is outside the guard.** `agy` has its own files that can change what it asks: `~/.gemini/antigravity-cli/settings.json`, `hooks.json`, `~/.gemini/config/projects/` and the `.agents/` folder of a workspace. Changing a rule, a hook or a trusted project there can change the questions you see in the app; setting `allowNonWorkspaceAccess` back to `true`, for example, makes reads outside the project silent again (measured). Builders in a Box does not read, guard or reset them, in the app or over SSH; the one exception is the single `allowNonWorkspaceAccess` conversion on update described above.

As with Claude Code and Codex in the app, the night shift's guard, gates and branch protection are properties of the night shift's own runner (`biab pack add night-shift`), not of an interactive session.

A box installed before this change is converted by `biab update`: the provider is switched and your projects stay workspaces in the app. Anyone who had switched on the older mode that ran every tool without asking is told once what Antigravity asks about now. The command `sudo biab paseo antigravity` remains until 2027-04-30 only to print that notice, because there is nothing to switch.

**The night shift's `dev` merge is a brake, not a lock.** At `dev` reach (the default when you arm it), the night-shift runner merges the agent's pull request into a `dev` branch after CI, an independent model review and your `.biab/dev-check.sh` pass. The agent and the runner run as the same user with the same GitHub token, so what keeps the agent from merging into `dev` on its own is the `PreToolUse` hook and the runner's order of operations (it merges only after the agent process has exited, pinned to the commit the gates saw, and kills anything the agent left running first) — not a permission GitHub enforces. What *is* a lock is branch protection on your default branch: nothing reaches `main` without your approving review unless you chose `main` reach and typed `UNLOCK MAIN`. The independent review is a model and can be talked round by text inside the diff; that is why the danger-zone list, the CI gate and the dev check sit around it. Gate state (reach, review budget, danger list) is root-owned; the runner itself runs as you. Details in the README, "Optional: the night shift".

**Where the root-owned boundary starts.** The protections above (root-owned unit, root-only credential) assume the box user cannot become root. On a box built from the ISO, the `builder` user has passwordless sudo (`NOPASSWD`) until the wizard sets a password, so the boundary is only real after that step. Until then, treat the agents on the box as able to change anything. Even afterwards, the installer refuses to write through a symbolic link in your home folder (`~/.biab`, `~/.bashrc.d`) and does those writes as your user, so an agent cannot use `biab update` to make root overwrite a file of its choice.

## Good to know

- Builders in a Box bundles **no credentials**. Every login is the user's own OAuth flow.
- Run `curl -fsSL https://buildersinabox.com/install.sh` (without piping to bash) to read the bootstrap before executing it.
