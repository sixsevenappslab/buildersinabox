# CLI skills compatibility: Claude Code ↔ Antigravity CLI (`agy`)

> Determines whether the bundled SDD skills ship under `~/.agents/skills/`
> and are consumed identically by both AI CLIs Builders in a Box supports.

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

So Builders in a Box keeps a single source of truth at `~/.agents/skills/<name>/`
and symlinks it into each CLI's native location:

- `~/.claude/skills/<name>` → `~/.agents/skills/<name>`  (Claude Code)
- `~/.gemini/skills/<name>` → `~/.agents/skills/<name>`   (`agy`, antigravity boxes only)  <!-- agy's real config home -->

Symlinks are honoured by both CLIs (confirmed on the VM), so there is no
content duplication and no drift.

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
