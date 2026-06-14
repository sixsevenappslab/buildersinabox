# payload/

Everything that gets installed on the mini PC **besides** Ubuntu itself.

This directory is the entry point for any DIY user: install Ubuntu Server 24.04 manually on any machine, clone this repo, and run `payload/install.sh`. The result is identical to what the USB installer produces — there's no magic.

## Contents

| Folder | What it contains |
|---|---|
| `install.sh` *(coming)* | Main first-boot script that orchestrates everything |
| `install/` *(coming)* | Sub-scripts: install Tailscale, Claude Code, gh CLI, tmux, etc. |
| `systemd/` *(coming)* | systemd unit files for first-boot one-shot execution |
| `tmux/` *(coming)* | tmux config + script that creates the 3 pre-configured windows |
| `skills/` | Claude Code skills bundled with the device (SDD workflow + utilities) |
| `templates/` | FEAT templates (starter + full), per-project CLAUDE.md template |
| `config/` | Example config files the user can copy and edit |
| `skeleton/` | The workspace skeleton (`ai-platform/` with empty `projects/`, `stratops/`) |
| `docs/` | Workflow documentation (SDD, specs lifecycle, adoption guide) |

## Applying the payload to an existing Ubuntu install (DIY path)

```bash
git clone https://github.com/buildersinabox/buildersinabox
cd buildersinabox/payload
sudo ./install.sh
```

The bootstrap script is idempotent — running it twice on the same machine is safe.

## Notes

The payload assumes Ubuntu Server 24.04 LTS. It may work on derivatives (Pop!_OS, Mint), but those are not tested.
