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

## Landing page (Cloudflare Pages)

`site/` is a static landing + the served installer. One-time setup in the Cloudflare dashboard:

1. Pages → Create project → connect the public repo (`sixsevenapps/buildersinabox-installer`).
2. Build command: `bash site/build.sh`. Output directory: `site`.
3. Custom domain: bind `buildersinabox.com` (apex). DNS is already on Cloudflare.
4. Enable Web Analytics (cookieless) if you want install-attempt counts.

`site/build.sh` copies `installer/web/install.sh` → `site/install.sh` and fails the build if they drift, so `buildersinabox.com/install.sh` is always byte-identical to the repo. `site/_headers` forces `text/plain` + a 5-minute cache on `/install.sh`.

Post-deploy smoke: `curl -sI https://buildersinabox.com/install.sh` → `200` + `text/plain`; `curl -fsSL https://buildersinabox.com/install.sh | diff - installer/web/install.sh` → no diff.
