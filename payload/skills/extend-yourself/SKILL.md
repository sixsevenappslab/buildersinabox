---
name: extend-yourself
description: Interactive guide for extending the Builders in a Box device itself. Use when the user wants to add a new skill, a new shell helper, a new wizard step, bundle a new FEAT spec, modify an existing payload script, or pull updates from the upstream BIAB repo. Maps the user's intent to the right files and patterns. Assumes the user is on a provisioned BIAB device with /opt/buildersinabox/payload/ available.
---

# /extend-yourself — make this device do something it doesn't do yet

When the user invokes this skill, your job is to figure out **what kind of extension** they want, point them at the right place in the payload, show the existing example, and help them make their version.

Everything on this device is open code. Nothing is hidden. The whole payload lives at `/opt/buildersinabox/payload/` and the workspace at `~/ai-platform/`. The user can modify any of it.

## Pre-flight

Run these to ground yourself in the device's state:

```bash
ls /opt/buildersinabox/payload/
cat /var/lib/buildersinabox/state.json
```

If `/opt/buildersinabox/payload/` is missing, the user is on a device that was set up before the iso-builder started shipping the full repo. Point them at the GitHub source and continue using the in-home `~/.agents/skills/` and `~/.bashrc.d/` for whatever they're adding.

## Ask what they want to add

Use roughly these categories. Don't read them aloud as a list — ask "what are you trying to add?" and infer.

| Intent | Right place | Existing example |
|---|---|---|
| A new assistant persona / expertise / voice | `~/.agents/skills/<name>/SKILL.md` | `~/.agents/skills/backend-engineer/` |
| A new shell helper / alias | `~/.bashrc.d/<name>.sh` | `~/.bashrc.d/biab-tmuxc.sh` |
| A new step in the first-boot wizard | `/opt/buildersinabox/payload/wizard/NN-name.sh` | any of the existing `wizard/*.sh` |
| A new bundled FEAT spec waiting in your project | `~/ai-platform/projects/<project>/specs/draft/FEAT-NNN-<slug>.md` | `FEAT-002-personal-slack-coach.md` |
| A new system service (daemon) | `~/.config/systemd/user/<name>.service` | the opt-in night-shift pack ships one (`biab pack add night-shift`) |
| A new cron-like scheduled task | `~/.config/systemd/user/<name>.timer` + matching `.service` | the night-shift timer, installed only if you ask for the pack |
| Modify an existing wizard step | edit `/opt/buildersinabox/payload/wizard/NN-*.sh` in place | n/a, just edit |
| Pull upstream updates from the BIAB project itself | `cd /opt/buildersinabox && git pull` | n/a |

## Walkthroughs by category

### A new skill

1. *"What's the skill called and what does it do in one sentence?"*
2. Create the folder + SKILL.md:
   ```bash
   mkdir -p ~/.agents/skills/<name>
   ```
3. Write the SKILL.md with the standard frontmatter. **Show the user** an existing one as the template:
   ```bash
   cat ~/.agents/skills/backend-engineer/SKILL.md | head -10
   ```
4. Frontmatter shape:
   ```yaml
   ---
   name: <name>
   description: <one or two sentences. This is what shows up when the user types /. Make it specific — Claude uses this to decide if the skill matches their request.>
   ---
   ```
5. Body is markdown. Anything goes — instructions, tone, examples, when-to-use, when-not-to-use sections. Read a couple of the bundled skills to absorb the house style.
6. Symlink it into `~/.claude/skills/` so Claude Code finds it at its native path:
   ```bash
   ln -s ~/.agents/skills/<name> ~/.claude/skills/<name>
   ```
7. Type `/` in any Claude Code window and it should be there.

### A new shell helper

1. Create a file under `~/.bashrc.d/<name>.sh`. The loader (`~/.bashrc`) sources every `*.sh` in that folder on shell startup.
2. **Must** start with `# shellcheck shell=bash` if you want shellcheck to lint it.
3. Define functions or aliases. Don't `set -e` here — `.bashrc` is shared.
4. Test in a new shell:
   ```bash
   bash -i -c 'type <function-name>'
   ```
5. Existing example to copy from: `~/.bashrc.d/biab-tmuxc.sh`.

### A new wizard step

This is for changes you want to run on every fresh install (rare for personal use). If you're just adding something to your existing device, prefer a one-off script.

1. Drop the script into `/opt/buildersinabox/payload/wizard/NN-name.sh` (pick `NN` so it sorts between existing steps).
2. Make it executable: `chmod +x` it.
3. Source `common.sh` and `prompt.sh` like the existing steps do.
4. Add a `phase_is_done` check + `phase_done` call so it's idempotent.
5. Wire it into `/opt/buildersinabox/payload/wizard/run.sh` (a single `run_step "NN-name.sh"` line in the right position).
6. Test with the dryrun rig:
   ```bash
   sudo rm /var/lib/buildersinabox/state.json
   sudo BIB_OAUTH_MOCK=1 BIB_PROMPT_INPUT=/dev/stdin /opt/buildersinabox/payload/install.sh
   ```

If you only want to RUN the step on this device (not bake it into a future ISO), just `sudo bash /opt/buildersinabox/payload/wizard/NN-name.sh` once.

### A new bundled FEAT spec

These are pre-written specs you (or someone) put in your draft folder as a starter project.

1. Copy the template from `/opt/buildersinabox/payload/templates/FEAT-TEMPLATE.md` or one of the existing bundled FEATs.
2. Save as `~/ai-platform/projects/<your-project>/specs/draft/FEAT-NNN-<slug>.md` (next free number).
3. Fill in §0 through §5.
4. When ready to start, move from `draft/` to `active/` and ask `/sdd-spec-writer` or `/sdd-coordinator` to refine before implementation.

### A new background daemon

User-level systemd unit, so it runs without root.

1. Write `~/.config/systemd/user/<name>.service`. Use `Type=simple`, `ExecStart=/path/to/your/binary`, `Restart=on-failure`.
2. `systemctl --user daemon-reload`
3. `systemctl --user enable --now <name>.service`
4. Make sure linger is enabled so the unit survives logout: `loginctl enable-linger "$USER"`. **Check it rather than assume it** — only the USB/ISO install turns linger on; after a `curl | sudo bash` install it is off, so a user unit stops firing as soon as your last session ends. For anything that has to run whether or not you are logged in (an overnight job, say), write a *system* unit in `/etc/systemd/system/` with `User=<you>` instead — that is what the night-shift pack does.
5. Logs via `journalctl --user -u <name>.service`.

### Pulling upstream updates

The whole payload is a git repo, so:

```bash
cd /opt/buildersinabox
sudo git pull
```

This brings in any improvements the maintainers (or you yourself, via a fork) have shipped. Then re-run any wizard step that changed if you want it applied:

```bash
sudo BIB_OAUTH_MOCK=0 /opt/buildersinabox/payload/wizard/NN-name.sh
```

Or just `--force` the whole wizard to reapply settings without reinstalling the stack:

```bash
sudo /opt/buildersinabox/payload/install.sh --force
```

## Contributing back

If something you built is useful beyond your device, fork the GitHub repo, commit your change, send a pull request. The maintainers love it. The folks who gave you this device love it even more.

```bash
cd /opt/buildersinabox
sudo git remote add my-fork git@github.com:<your-user>/buildersinabox.git
# make changes
sudo git checkout -b your-improvement
sudo git commit -am "what you did"
sudo git push -u my-fork your-improvement
gh pr create
```

## Tone

- This is the user starting to make the device their own. Celebrate that — but don't be sappy about it. Just be useful.
- Show the existing example, then ask what they want to change.
- Patient. Some of these patterns are new (systemd user units, slash command frontmatter). Explain when asked, skip when not.
- Concrete commands always. Never abstractions like "edit the appropriate file".

## When NOT to use this skill

- The user is asking how to use an existing feature (not extend the system). Direct them at `/whats-ahead` or the relevant skill.
- The user is implementing a regular project FEAT (their own code, not the device). They want `/sdd-spec-writer` and friends, not this skill.
