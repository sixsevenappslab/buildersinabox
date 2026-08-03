# CLI skills compatibility: Claude Code ↔ Antigravity CLI (`agy`) ↔ Codex

> Determines whether the bundled SDD skills ship under `~/.agents/skills/`
> and are consumed identically by every AI CLI Builders in a Box supports.

**Status:** ✅ Validated empirically for both CLIs.

The original v1 validation (2026-05-25) targeted Builders in a Box's *first*
second-CLI option, which Google retired for consumers on 2026-06-18. That CLI
has been replaced by its successor, the **Antigravity CLI (`agy`)**, and the
findings below reflect the FEAT-013 spike on `agy` 1.1.0 (2026-07-09).

## TL;DR

The Anthropic-style `SKILL.md` format is drop-in compatible between Claude
Code and `agy`: a folder with a `SKILL.md` (YAML frontmatter `name` +
`description`, then a body) is discovered and invocable by both. The
difference is *where* each CLI looks:

- **Claude Code** reads `~/.claude/skills/<name>/`.
- **`agy`** does **not** scan `~/.agents/skills/` in `$HOME` — it only reads
  `.agents/skills/` at the *workspace* level. Its global ("Shared") skills
  directory is `~/.gemini/skills/`.  <!-- ~/.gemini is agy's real config home -->
- **Codex** reads `~/.agents/skills/<name>/` in `$HOME` **natively** — that is
  its standard global skills path, the very directory Builders in a Box uses as
  its source of truth. Codex invokes skills as `$name` (not `/name`).

So Builders in a Box keeps a single source of truth at `~/.agents/skills/<name>/`
and symlinks it into each CLI's native location:

| CLI | Native skills dir | Symlink Builders in a Box creates |
|-----|-------------------|-----------------------------------|
| Claude Code | `~/.claude/skills/<name>` | `~/.claude/skills/<name>` → `~/.agents/skills/<name>` |
| `agy` (antigravity boxes) | `~/.gemini/skills/<name>` | `~/.gemini/skills/<name>` → `~/.agents/skills/<name>`  <!-- agy's real config home --> |
| Codex | `~/.agents/skills/<name>` | none — the source of truth **is** codex's native dir |

Symlinks are honoured by every CLI (confirmed on the VM), so there is no
content duplication and no drift. Codex needs **no** new symlink: its native
dir already is the source of truth, so the scaffold's skills loop is a no-op
for it (the `[[ -e || -L ]]` guard skips the self-referential link).

## FEAT-013 spike addendum — `agy` 1.1.0 on headless Ubuntu 24.04

Ran on a clean multipass VM (Ubuntu 24.04, no `gnome-keyring`/`libsecret`/
`dbus-x11` at any point). `agy` installed pinned from a GitHub release
(`agy_cli_linux_x64.tar.gz`, sha256-verified), authenticated with a real
Google consumer account.

### Skills — discovery + invocation

- A rig of marker skills in each candidate directory showed `/skills` lists,
  by category:
  - **Workspace:** `<workspace>/.agents/skills/`
  - **Global:** `~/.gemini/antigravity-cli/skills/`  <!-- agy app-data dir -->
  - **Shared:** `~/.gemini/skills/`  <!-- agy's stable global dir -->
  - plus product-builtin and a registered `~/.gemini/config/skills/`.  <!-- agy config dir -->
- `~/.agents/skills/` in `$HOME` was **not** scanned — the home-level marker
  skill never appeared. Only workspace `.agents/skills/` is read.
- **Symlinks work:** a skill symlinked into a scanned global dir showed up and
  was invocable. Builders in a Box symlinks into `~/.gemini/skills/` (the
  stable "Shared" dir; the `antigravity-cli/` tree is regenerable app-data).  <!-- agy's config home -->
- `agy -i '/tutorial'` boots the TUI and fires the skill (verified). On the
  first run, because the real `SKILL.md` sits outside the workspace (reached
  via symlink), `agy` asks for file-access — neutralised by pre-seeding
  `allowNonWorkspaceAccess: true` in its settings (see below).

### Login + token persistence

- `agy` 1.1.0 has **no** `agy auth login` subcommand. Login is the TUI itself:
  launch `agy`, choose "Google OAuth", it prints a long sign-in URL, the user
  signs in and pastes the authorization code back.
- The OAuth token is written to a plain `0600` file at
  `~/.gemini/antigravity-cli/antigravity-oauth-token`  <!-- agy token file -->
  (JSON `{token, auth_method}`). **No system keyring is used or required** —
  the earlier "keyring-only" concern (issue #57) does not reproduce on 1.1.0,
  which falls back to a file. The token survived two reboots with `agy`
  staying authenticated (verified with `agy models`).
- Health check (non-interactive, no quota, no OAuth trigger):
  `agy models </dev/null` — exit 0 + model list when authed, exit 1 when not.

### Zero-touch settings pre-seed

Written by the scaffold step to
`~/.gemini/antigravity-cli/settings.json`:  <!-- agy settings file -->

```json
{
  "allowNonWorkspaceAccess": true,
  "enableTelemetry": false,
  "trustedWorkspaces": ["/home/<user>/ai-platform"]
}
```

Plus `AGY_CLI_DISABLE_AUTO_UPDATE=1` exported in the launcher/login so the
pinned version can't silently drift.

### Workspace context files

Asked `agy` which context markers it saw in a workspace containing
`GEMINI.md`, `AGENTS.md` and `.antigravity.md`:  <!-- agy legacy context file -->

- It reads **`AGENTS.md`** and the legacy **`GEMINI.md`**.  <!-- agy legacy context file -->
- It does **not** read `.antigravity.md`.

Decision for the scaffold: generate **`CLAUDE.md`** (Claude Code) and
**`AGENTS.md`** (the open standard `agy` reads). Builders in a Box stops
generating the legacy per-folder context file the retired CLI used.

### reset-for-gift purge targets

To de-authenticate a box before gifting, remove `~/.gemini/` wholesale (token
+ settings + cached conversations) and `~/.cache/antigravity/`. There is no
keyring secret to clear.  <!-- ~/.gemini is agy's real config home -->

## Required file layout (both CLIs)

```
<skills-root>/<skill-name>/
└── SKILL.md          # YAML frontmatter (name, description) + body
   (+ any supporting assets, scripts, templates)
```

## Activation behavior

When a skill activates, its `SKILL.md` body is injected into the model's
context. Bodies should therefore be **self-contained** — no assumptions about
other skills or files outside the skill's own folder unless those references
are themselves portable.

## Skill-specific notes

- **`quota`** — **Claude Code only.** It reconstructs usage from Claude Code
  transcripts (`~/.claude/projects/**/*.jsonl`); neither Antigravity nor Codex
  writes that format, so on an `agy`/codex box the skill still installs but its
  report prints "no Claude Code transcripts found yet". The companion
  quota-nudge hook and statusline are Claude-format too, so the scaffold skips
  them on non-Claude boxes (same guard as the other hooks).

## Codex — context files + skills invocation

Codex reads **`AGENTS.md`** in the chain global → git-root → cwd — the same
open-standard context file Builders in a Box already scaffolds for `agy`, so no
new context file is generated. Skills are invoked as `$name` (or implicitly);
`/name` only maps to deprecated custom prompts. Codex has no hooks, statusline,
or remote-control companion app, so it is treated like `agy`: reached over
SSH + tmux, no companion app.
