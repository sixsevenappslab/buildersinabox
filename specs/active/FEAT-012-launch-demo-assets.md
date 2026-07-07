---
id: FEAT-012
title: launch-demo-assets
project: buildersinabox
status: active
priority: high
complexity: medium
created: 2026-06-15
validated_by: null
---

# FEAT-012: Launch demo assets (README + landing visuals)

## §0 — Why

The README and `site/index.html` are text-only. The entire pitch is "code from
your phone in 15 minutes", and there is currently nothing that *shows* it. A
demo is the single highest-conversion asset on an OSS repo and the most-missed
on the landing page. This is the last high-priority gap before the public flip.

Blocking dependency: some assets need the real mini PC (the phone experience
can't be faked convincingly). The asciinema can be produced now from a VM.

## §1 — What we want

Three assets, in priority order:

1. **Hero: phone screenshot of Claude Code over Tailscale.** A real phone
   showing the Claude Code app attached to the `ai-platform` session on the
   box. This is the money shot — it proves the core promise. **Needs hardware.**
2. **Install cast (asciinema).** `curl -fsSL https://buildersinabox.com/install.sh | sudo bash`
   → stack install → wizard intro. Embeddable in the README "From source" /
   quickstart and on the landing. **Can be produced on a VM now**, with the
   caveat below.
3. **Wizard GIF (optional, nice-to-have).** The ~15-min first-boot wizard
   compressed to ~20s. **Needs hardware** (or a scripted clean run).

### Placement
- README: hero image immediately under the title/tagline, above the `curl`
  one-liner. asciinema (as an SVG or a link) near the install section.
- `site/index.html`: hero asset above the fold; today the page is text-only.

### Boundaries
- **Always:** assets must be real (no faked terminals/mockups); host them in
  the repo (`site/` or a `docs/assets/` dir) so they survive the publish
  snapshot — not hotlinked from a third party.
- **Ask first:** whether to record the phone screenshot with personal
  accounts visible (blur/relogin with a throwaway GitHub/Tailscale if needed).
- **Never:** leak personal tailnet names, real tokens, or private repo names in
  any frame.

## §2 — How (technical notes)

- **asciinema (now, VM):** `asciinema rec install.cast` inside a fresh multipass
  Ubuntu 24.04, running the bootstrap. Render to SVG with `svg-term` (or
  `agg` → GIF) for static hosting without the asciinema player JS.
  - **Caveat:** in multipass, `50-ssh.sh` severs multipass's own SSH to the VM
    (known artifact — see the verification notes), so a `--skip-wizard` stack
    cast ends cleanly at "stack installed" but a full-wizard cast can't complete
    in multipass. For the hero install cast, record up to "stack installed";
    record the wizard separately on hardware.
- **phone screenshot / wizard GIF (hardware):** capture on the real mini PC
  once it's set up. Native screen recording on the phone for the app; a camera
  or HDMI capture for the wizard.
- Store assets under `site/` (so the landing can use them and they're in the
  published tree). Keep them small (optimize PNG, prefer SVG cast).

## §4 — QA / done criteria

- [ ] Hero asset present in both README and `site/index.html`.
- [ ] Install cast embedded and renders without external JS dependency.
- [ ] No personal data (tailnet, tokens, private repos) visible in any asset.
- [ ] Assets live in the repo and survive `git archive HEAD` (in `site/` or
      `docs/assets/`, not export-ignored).
- [ ] Total added asset weight is reasonable (< ~1.5 MB).

## Owner split

- **Claude (now):** the asciinema install cast from a VM (if Jesús wants it
  before hardware), and wiring asset placeholders into README + landing.
- **Jesús (hardware):** phone screenshot + wizard GIF on the real mini PC.
