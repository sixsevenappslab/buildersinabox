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

## §2b — Storyboard del vídeo (día PC, ~2026-08-08)

> La pieza viral según Distribución es el VÍDEO del móvil, no el asciinema.
> Target: 15–20 s, vertical 9:16 (móvil primero; recorte 16:9 para la landing
> si hace falta). Ángulo ownership: "an old PC + your phone", no seguridad.

| # | t | Plano | Contenido | Captura |
|---|---|-------|-----------|---------|
| 1 | 0–2s | Cámara, mano | El mini PC (o portátil viejo) en una estantería/cajón, LED encendido. Texto sobreimpreso: *"an old PC"* | Cámara del móvil de Sara u otro móvil, 60 fps |
| 2 | 2–5s | Screen-record móvil | Abrir la app de Claude Code → lista de sesiones remotas → tap en `ai-platform` | Grabación nativa de pantalla |
| 3 | 5–12s | Screen-record móvil | Escribir un prompt real y corto (*"add dark mode and open a PR"*) → el agente arranca y se ve trabajar. Texto: *"your agent, on your hardware"* | Misma grabación; prompt ensayado antes sobre un repo demo preparado |
| 4 | 12–16s | Cámara | Bloquear el móvil y guardarlo en el bolsillo. Corte → notificación de PR abierta / "done" en pantalla. Texto: *"it keeps working"* | Dos tomas: bolsillo + notificación |
| 5 | 16–20s | End card | Logo/nombre + `curl -fsSL https://buildersinabox.com/install.sh \| sudo bash` + *"one command, ~15 minutes"* | Estático, generado (misma estética que la landing) |

**Notas de captura (una sola sesión, día PC):**
- Grabar cada plano el doble de largo de lo necesario; recortar en edición.
- Hostname/tailnet neutros (`biab-box`) — nada del tailnet personal, ni repos
  privados, ni notificaciones personales en la barra del móvil (modo no
  molestar, batería decente, hora "bonita").
- Ensayar el prompt antes: repo demo pequeño con un cambio vistoso y rápido
  (dark mode, un README render, un test verde) para que el plano 3 tenga
  movimiento real en <7 s.
- Del mismo setup salen los otros dos assets en la misma sesión: el **hero
  screenshot** (plano 3 congelado: app Claude Code sobre la sesión
  `ai-platform`, prompt+respuesta visibles) y el **wizard GIF** (timelapse
  ~20 s del first boot, HDMI o cámara fija).
- Éxito del asset = alguien que ya usa Claude Code entiende en 20 s que puede
  tener esto con un comando. Si un plano no empuja a eso, fuera.

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
