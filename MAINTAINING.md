# Maintaining

Maintainer-only notes. Not needed to *use* Builders in a Box.

## GitHub repo metadata

When the public repo (`sixsevenapps/buildersinabox-installer`) is set up, configure:

- **Description:** `Your own AI dev box. Plug in, code from your phone in 15 minutes. One-command install on any Ubuntu 24.04.`
- **Topics:** `homelab`, `tailscale`, `claude-code`, `ai`, `ubuntu`, `self-hosted`, `installer`, `developer-tools`, `mini-pc`, `tmux`
- **Website:** `https://buildersinabox.com`

## Publishing

The dev repo (`jesusmartincalvo/buildersinabox`) is the private workbench. The public repo gets a clean, fresh-history snapshot of the shippable tree — see FEAT-011's `tools/publish.sh` (extracts via `git archive HEAD`, runs the personal-refs guard, pushes a release snapshot). `specs/`, `payload/flavors/gift/maintainer/`, `BIZ-PLAN-LIFESTYLE.md`, and `TODO-NEXT-ISO.md` are `export-ignore`-d and never reach the public repo.

## CI

`.github/workflows/ci.yml` runs on every push/PR: `shellcheck`, `bash -n`, the personal-refs guard, and a `git archive` cleanliness check. The guard (`tools/check-no-personal-refs.sh`) is the durable protection against a personal-reference regression — keep its pattern list current.
