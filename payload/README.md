# payload/

Everything that gets installed on the mini PC **besides** Ubuntu itself.

This directory is the entry point for any DIY user: install Ubuntu Server 24.04 manually on any machine, clone this repo, and run `payload/install.sh`. The result is identical to what the USB installer produces — there's no magic.

## Contents

| Folder | What it contains |
|---|---|
| `install.sh` *(coming)* | Main first-boot script that orchestrates everything |
| `install/` *(coming)* | Sub-scripts: install Tailscale, Claude Code, gh CLI, etc. |
| `systemd/` *(coming)* | systemd unit files for first-boot one-shot execution |
| `skills/` | Claude Code skills bundled with the device (SDD workflow + utilities) |
| `templates/` | FEAT templates (starter + full), per-project CLAUDE.md template, and `templates/projects/` — the project template catalogue (`manifest.tsv`, the brief for "describe your own idea") that `/first-project` offers |
| `scripts/` | `biab-project` — lists the catalogue, scaffolds a project without overwriting anything, reports which step of the first-project walk the disk says a project is at, and remembers the walk's progress (`~/.config/biab-first-project/`) |
| `config/` | Example config files the user can copy and edit |
| `skeleton/` | The workspace skeleton (`ai-platform/` with empty `projects/`, `stratops/`) |
| `docs/` | Workflow documentation (SDD, specs lifecycle, adoption guide) |
| `i18n/` | Message catalogs, one directory per language (`en`, `es`) and one file per area (FEAT-045); see below |

## Message catalogs (FEAT-045)

`lib/i18n.sh` loads `i18n/<lang>/<area>.sh`: single-line `BIB_MSG[area.topic.detail]='printf format'` assignments (the value carries its own `\n`; keys are never the English sentence). Print with `msg KEY [args]` (or `msg_str VAR KEY [args]`); a key missing in the active language prints the English text and logs the key to `bootstrap.log`.

To add a message, add the same key to `i18n/en/<area>.sh` and `i18n/es/<area>.sh` with the same `%s` sequence (bash `printf` has no `%1$s`) and the same commands, flags and paths. `bash payload/test/i18n.sh` fails when they differ. A language is offered at install only once it is listed in `BIB_LANGS_AVAILABLE` (`lib/i18n.sh`, now `"en es"`), so a catalog can merge before it is complete: a new language goes in that constant in the last PR, when its catalogs, box README and skills directive are done. The `en` transcripts that `i18n.sh` compares with the goldens are printed with the gate closed (a build that offers only English, what `origin/main` printed); `BIB_SCREENS_OPEN=1 i18n-screens.sh ...` prints the shipped build, which differs from the golden by the one-line language confirmation of the first wizard run and nothing else (`i18n.sh` checks that).

The first-run path (the wizard, `lib/prompt.sh`, `lib/oauth.sh`, the installer's prompts, the login copy and the pairing screens) is migrated, and `payload/test/i18n.sh` keeps it that way: a printf, a `cat <<EOF` of text, or a `warn`/`die`/`prompt_*` call with a literal English sentence in a migrated file fails it, unless the line carries `# i18n-ok: <why>` (a log line, a machine marker, a maintainer diagnostic). Spanish is rewrapped, not padded, to the same 60 columns as English (40 for the closing guard note and the welcome copy). `payload/test/i18n-screens.sh <payload> <en|es> <new work dir>` prints the first-run screens for one language; the leakage check and a diff between two trees use it.

`payload/test/fixtures/first-run-en.golden.txt` is that transcript in English as `origin/main` printed it before the catalogs, and `i18n.sh` compares the live one with it byte for byte (R12: English does not change when text moves). When English copy changes ON PURPOSE, say so in the PR and regenerate it from the reviewed tree: `d=$(mktemp -d) && bash payload/test/i18n-screens.sh "$PWD/payload" en "$d/w" > payload/test/fixtures/first-run-en.golden.txt`; the diff of the golden is then the list of English screens the PR changes. Adding a skill does not change it (the count is masked).

What the box shows after setup is migrated too (FEAT-045 T3): the `biab` command and every verb (the wrapper `install/05-biab-command.sh` writes), `biab status` with the phone-app block of `paseo/bin/biab-paseo-health`, `scripts/biab-project`, the per-CLI text of `lib/ai-cli.sh` (choice hints, night-shift reasons, OpenCode permission reasons, guard-state text), the `Safety net` block of `lib/guard.sh`, the Antigravity notices of `lib/paseo.sh` and the first-boot lines. In `biab status` the first two columns of the safety-net table (`base`, `guard`, `night shift` and `yes`, `no`, `off`, `none`, `?`) and the service states (`OK`, `FAILED`...) are fixed words in every language; only the sentence beside them is translated. `payload/test/i18n-biab.sh <payload> <en|es> </tmp/new work dir>` prints that transcript; `payload/test/fixtures/biab-en.golden.txt` is the English one as it was before the catalogs, compared byte for byte (regenerate it the same way as the first-run golden, with `i18n-biab.sh`). `payload/test/cli-guard.sh` holds the Spanish counterparts of CF-61d, CF-62 and CF-63: phrase tables per language, and a sentence-level check with injected false claims, so a Spanish sentence cannot promise a protection an adapter does not declare.

`scripts/biab-worktrees` (`biab worktrees clean`, FEAT-047) is a migrated file as well: its messages are the `biab.wt.*` keys of `i18n/{en,es}/biab.sh` and it is in the `RATCHET` list of `i18n.sh`, so a hard-coded English sentence in it fails the suite. The word `retirable` is the same in both languages; only the reasons are translated.

The agent and the files the owner reads follow the language too (FEAT-045 T4), without translated copies of the skills (decision D1):

- **Box README**: `tutorial/desktop-readme.es.md` is the twin of `tutorial/desktop-readme.md`, with the same `<!-- BIB:... -->` markers, headings, commands, flags and paths, so the CLI, Paseo and `guard-<cli>` / `no-guard` gating is the same in both. `ai_cli_render_readme <cli> <src> [lang]` reads the twin next to `<src>` for a language other than `en` (English plus a log line when there is none), and `40-scaffold.sh` passes the language of the box. A new section or sentence goes in both files in the same PR; `i18n.sh` compares markers, headings and literals, and CF-62-es / CF-63-es read the Spanish file. The section titled "If SSH ever fails" / "Si SSH falla alguna vez" is quoted by `wizard.ssh.*`: keep both titles.
- **Context files**: `templates/PROJECT-CLAUDE.md` and `skeleton/ai-platform/CLAUDE.md` carry a `<!-- biab-lang:start -->` ... `<!-- biab-lang:end -->` block (`## Language`) with `{{LANG_NAME}}` and `{{LANG_CODE}}`. The two copies must be identical (`i18n.sh` checks); `uc_lang_apply` (`lib/user-content.sh`) fills it in from the template for the language of the box, in the workspace, stratops and every project, and a file without the block is never given one.
- **Onboarding skills**: `tutorial`, `first-project`, `second-project`, `whats-ahead`, `extend-yourself` and `welcome` start with a `## Language` directive that reads `.lang` from `/var/lib/buildersinabox/state.json` (en when missing). No other bundled skill has it, and the vendored marketing skills are not touched. `morning-check` also gives the Spanish form of the OFF-PIN line.
- **`biab lang [en|es]`** (`scripts/biab-lang`): prints the language, or switches it. It rewrites `~/README.md` only while it is untouched (it equals `.readme_sha256` in the state, which `40-scaffold.sh` stores, or a fresh render of the old language with the project name `/first-project` filled in); an edited README stays and the new version goes to `~/README.<code>.md`. It then rewrites the Language block of the context files, writes `.lang` (and `phases.lang_confirmed`) with sudo, and answers in the new language. Re-running changes nothing. On a build that offers only English it says so and changes nothing.
- **Project templates**: `templates/projects/manifest.es.tsv` (`name TAB description`) holds the Spanish descriptions `biab-project list` shows in a Spanish box; a template without a row there is shown in English. Add a row for every row of `manifest.tsv`.
- `payload/test/i18n-lang.sh <payload> <work dir>` runs all of that on a copy (scaffold, `biab lang`, `biab-project`); `i18n.sh` turns its lines into results and leak-checks the Spanish output. English changes of the `biab help` text are made by hand in `biab-en.golden.txt`.

The hooks and the night-shift pack are in the catalogs too (FEAT-045 T5), each with its own area:

- **Hook reasons** (`i18n/<lang>/hook.sh`, keys `hook.*`): the text of a permission prompt or a refusal from the guard hooks (Claude's guardrail and secret guard, Codex's, Antigravity's two). The decision, the rule id and the corpora (`hooks/tests/*.tsv`) never depend on the language. English is the literal at the call site (`biab_hook_text <key> "<english>"`, in `hooks/lib.sh`, and the `_biab_guard_set` / `_biab_secret_reason` helpers of the rules files); `i18n.sh` compares every literal and every rule's reason with the en catalog, so they cannot drift. The lookup runs only when a hook is about to ask or deny, never on the pass-through path, and in a separate process with a hard limit (`hooks/text-lookup.sh` under `timeout -s KILL 0.7`): whatever fails in it (a missing, broken, hanging or process-killing catalog or library, a bad state file, a language the build does not offer) returns the English text and the decision stands. A new reason is a new key in both files and a `biab_hook_text` call; the Codex `hooks.json` entry is hashed by Codex and does not change. Hooks that put text in the agent's context (`biab-specs.sh`, `biab-quota-*.sh`, `biab-lint.sh`) and the night-shift guard `pack/night-shift/hooks/no-merge-guard.sh` write for the agent, not the owner, and stay English (D1).
- **Night shift** (`i18n/<lang>/nightshift.sh`, keys `nightshift.*`): everything `biab-night-shift`, its gates (`pack/night-shift/lib.sh`), `install.sh` (the notice, now `night_install_notice` in `lib.sh`) and `uninstall.sh` print for the owner. `say_msg` / `err_msg` print `night-shift: ` and a catalog message; the `verdict=... reason=...` lines, the fixed first column of `status`, the words the owner types (`ARM`, `IUNDERSTAND`, `UNLOCK MAIN`), the prompts handed to the agent and the text written to the owner's GitHub repository (PR title and body, merge message) stay as they are. `payload/test/i18n-hooks.sh` and `payload/test/i18n-nightshift.sh <payload> <en|es> <new work dir>` print the transcripts that `i18n.sh` compares with `fixtures/hooks-en.golden.txt` and `fixtures/nightshift-en.golden.txt` (English as `origin/main` printed it before the catalogs; regenerate them like the other goldens when English changes on purpose) and leak-checks in Spanish.

## Applying the payload to an existing Ubuntu install (DIY path)

```bash
git clone https://github.com/buildersinabox/buildersinabox
cd buildersinabox/payload
sudo ./install.sh
```

The bootstrap script is idempotent — running it twice on the same machine is safe.

## Notes

The payload assumes Ubuntu Server 24.04 LTS. It may work on derivatives (Pop!_OS, Mint), but those are not tested.
