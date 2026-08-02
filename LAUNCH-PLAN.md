# BIAB — Launch Plan (post strategy-council)

> 2026-07-08. Output de: 5 consejeros strategy-council + market delta (jun 1–jul 8) + revisión fría del repo.
> Export-ignored (no ship al repo público). Sustituye el GTM del BIZ-PLAN-LIFESTYLE.md §6 donde choquen.

---

## 0. La decisión y el veredicto del consejo

**Decisión sobre la mesa:** ¿flip a público ya, con qué plan?

| Consejero | Veredicto en una frase |
|---|---|
| Contrarian | El lanzamiento es teatro: gate imposible por diseño, hook que mata la diferencia (el hardware), canal (X a cero) que garantiza abandono. Vende 10 cajas a 50€ vía LinkedIn ANTES del flip. |
| Esencialista | Flip esta semana con lo que hay; toda la ambición en UNA cosa: el momento móvil→tu-máquina→Claude perfecto. El "plan ambicioso" es el que sobra. |
| Bootstrapper | Flip sí, ambición no: lanzamiento diseñado para NO generar obligaciones recurrentes. Un solo acto de push (Show HN un sábado libre). Cero Discord, cero X diario. |
| Inversor | Lanza con plan pequeño y aburrido; el camino al fracaso nº1 es el tuyo conocido (abandonar el grind en semana 3). Corrige el gate ANTES de lanzar. Hezu primero. |
| Distribución | Canal correcto (Show HN + r/selfhosted + Tailscale DevRel), vehículo equivocado (X a cero). La pieza viral es el VÍDEO del móvil, no el asciinema. Pide la excepción LinkedIn tipo Juntale: UN post. |
| Market delta | **LAUNCH NOW (semana, no mes).** Ventana intacta pero estrechándose (OpenHands Agent Canvas 16-jun). Tres tailwinds en pico: refugiados Gemini CLI, Sonnet 5, Cowork mobile en prensa. |
| Revisor frío | "Not ready as-is" — pero los 4 blockers son 1-2 días de trabajo. El instalador es launch-quality; el paquete alrededor no. |

**Dónde coinciden (los 5 + los 2 técnicos):**
- El gate del checkpoint está ROTO: pide "≥10 paying betas" en un proyecto donde decidimos no cobrar. Hay que reescribirlo antes de lanzar o es una coartada para archivar.
- El "plan ambicioso" con X + build-in-public diario contradice el Operating Model ("si una pieza de distribución requiere disciplina manual recurrente, está mal diseñada") y el patrón conocido del operador.
- LinkedIn (8k) es el único canal propio real; la regla EXEC-004 merece la misma excepción puntual que ya se aprobó para Juntale: UN post el día del launch.
- Nadie externo ha instalado BIAB end-to-end sin Jesús cerca. Riesgo real de "me bricked el VPS" en el hilo de HN.

**Dónde chocan (el desacuerdo valioso):** el Contrarian quiere retrasar el flip y vender primero 10-15 cajas/instalaciones a 50€ para medir COMPRA real; los otros cuatro dicen flip ya y que las 6 semanas midan. Elegir al Contrarian = 3-4 semanas más y logística; elegir al resto = lanzar con validación de adopción, no de compra. Punto medio adoptado: 2-3 instalaciones beta externas SIN dinero antes del flip (1 semana, no 4).

---

## 0b. Posicionamiento (delta 2026-07-08, post market-research sesión personal)

> Reconciliado desde el strategy-council sobre hardware (2026-07-07, veredicto unánime: NO
> comprar stock) + investigación de mercado fresca. NO reabre decisiones: es un cambio de
> ángulo del copy, mismo plan, mismo timeline.

**El pivote:** de "plug in, code from your phone" a **seguridad-primero**. El hueco real es
"el appliance de agentes SEGURO POR DEFECTO", no "instalador zero-touch": escaneo feb 2026
encontró 42.665 instancias OpenClaw expuestas, 93,4% con auth bypass; los OEMs (PowerMining,
ACEMAGIC, Minisforum) venden "preinstalado" y velocidad, nadie vende seguridad. BIAB ya ERA
Tailscale-only/cero puertos públicos — solo lo contaba como conveniencia.

- **Hook del Show HN y de r/selfhosted:** el dato 42.665 / 93,4%. Título candidato:
  "Show HN: Builders in a Box — a personal AI agent box that isn't one of the 42,665 exposed
  ones" (refinar; el actual "phone-first one command" pasa a subtítulo/primer párrafo).
- **Tagline:** "secure by default: Tailscale-only, zero public ports". OJO: NO usar
  "keys not passwords" — choca con FEAT-001/50-ssh.sh: password auth dentro del tailnet es
  INTENCIONAL (la credencial es el sudo password; el listener es tailnet-only). Gana el repo.
- **Cowork, nombrado con honestidad** (credibilidad HN): "if you just want Claude in the
  background, Anthropic's Cowork does that; this is for when the agent needs YOUR machine —
  your files, your LAN, your credentials, your cron jobs". Ya añadido a la landing.
- **El rival del dev puro es el VPS de 5-10$/mes** (Hostinger vende "Claude Code VPS hosting"
  como categoría), no otro appliance. BIAB corre en VPS: es feature — el fix-pack B3/B4 hace
  ese path seguro (lockout guard) y posible (root-only). Mencionarlo en el hilo.
- **B3 y B5 suben de "fixes" a features de seguridad** y se venden como tales: README tiene
  ya sección "Security model" (zero public ports, auth solo tailnet, lockout-safe hardening,
  bootstrap pineado a release); la landing la enlaza. Hecho en PR #14.
- **Validación de timing:** Mac mini M4 agotados en Asia (ene-feb) como appliance no-oficial
  de agentes; el patrón Tailscale+tmux+Claude Code ya es "setup canónico" documentado.
  Ventana abierta pero rodeada.

---

## 1. Pre-flip fix pack (del revisor frío) — ~6-8 h

Verificado: el issue #1 del revisor (docs internos visibles) es FALSA ALARMA — publish.sh usa git archive + export-ignore y el repo público v0.1.4 está limpio (verificado por tar -t).

Los reales, por prioridad:

| # | Fix | Esfuerzo | Nota |
|---|---|---|---|
| B1 | **Demo assets** (FEAT-012): asciinema del install (VM) + screenshot real del móvil con Claude Code sobre el mini PC + idealmente vídeo 15-20s | M | El único gap M. El vídeo del móvil es LA pieza viral según Distribución. Jesús tiene mini PC + móvil. |
| B2 | **Disclosure del coste Claude**: línea honesta en README + landing: "a Claude subscription (Pro or above) or Gemini account; Tailscale is free" | S | Evita el bait-and-switch en `claude auth login`. |
| B3 | **sshd rebind warning**: si `SSH_CONNECTION` viene de IP no-tailnet, avisar + confirmar antes de bindear sshd a Tailscale-only (35-ssh-finalize.sh). Idealmente verificar que un 2º dispositivo tailnet responde antes | M | El fix que evita "this script bricked my VPS" en HN. |
| B4 | **Root-only VPS**: detectar root sin SUDO_USER → ofrecer crear usuario (adduser + sudo group) o imprimir los 2 comandos exactos | S/M | DigitalOcean/Hetzner default = root. Primera impresión del público VPS. |
| B5 | **Pin de release**: bootstrap clona tag estable por defecto (`BIB_REF=v0.x.y`), no main HEAD | S | "El código que auditaste es el que ejecutas." |
| B6 | **"What it changes / how to uninstall"** en landing + README (sshd, tty1 autologin, /opt, /usr/local/bin, profile.d) + anunciar `--uninstall` | S | Trust feature ya construida y escondida. |
| B7 | **CLI choice bug**: install.sh persiste claude en state.json ANTES del wizard → 05-choose-cli siempre se salta. Preguntar en install o suavizar el claim "or another AI CLI" | S | Bug real, no copy. |
| B8 | **README status line** contradictoria ("hosted one-liner landing as we go" con el one-liner ya arriba) | S | 5 min. |
| B9 | **Copy USB filtrada al path genérico**: "Ethernet for first boot" (VPS?), "re-flash the USB" (curl|bash?), "unplug the monitor" | S | Condicionar por flavor o genericizar. |
| B10 | **Trim Beat 7 del tutorial**: quitar pitch de stratops/PORTFOLIO/bd-triage; dejar tmuxc + /morning-check + 1 frase. Headline "~15 min to first SSH" (no "15 min" total) | S | Donde el extraño abandona (min 25-30). |
| B11 | **Quitar "Modules coming: Conerator, Observio, Pathtrip"** del footer landing + README hook (1 línea de roadmap máx.) | S | 3 nombres vaporware en una página que pide sudo. Esencialista + Distribución + revisor coinciden. |

## 2. Beta externa mínima (el punto medio con el Contrarian) — 1 semana en paralelo

- 2-3 personas de la red (LinkedIn DM personal, no post público) que instalen SIN ayuda: una en VPS, una en mini PC/homelab, idealmente una con Gemini.
- Éxito = completan hasta "Claude responde desde el móvil" sin WhatsApp de rescate. Cada fricción → issue.
- Si 0/3 completan → NO flip; arreglar y repetir. Esto sustituye a las "10 cajas a 50€".

## 3. Gate reescrito (obligatorio antes del flip)

Fuera "paying betas" (imposible en OSS-only). Nuevo gate a 6 semanas del launch:
- ≥500 stars **o** ≥50 instalaciones completadas reportadas (issues/`biab diagnostic` opt-in/testimonios)
- ≥100 suscriptores email (añadir capture en landing ANTES del launch — audiencia POSEÍDA, no stars)
- ≥3 testimonios externos espontáneos ("it worked")
- Presupuesto post-launch: **4 h/semana cap**, 3 meses. Si al final del trimestre el interés no justifica ni eso → modo mantenimiento pasivo (no archivo dramático).

## 4. El launch (UN día, no una campaña)

**Preparación (la semana del launch):**
- Email capture en landing (Buttondown/Resend, S)
- Show HN draft — ~~ángulo seguridad (§0b)~~ **SUPERSEDED 2026-07-13**: tras un segundo strategy-council + research de audiencias, el ángulo elegido es **ownership / old-PC revive** (el dato de las 42.665 cajas baja al cuerpo, no al título, para que el hilo no arranque como debate de seguridad). Draft final abajo ⬇.
- Post LinkedIn draft (excepción puntual EXEC-004, misma figura que Juntale — anotar en EXEC): "Construí mi propio servidor de IA y se lo regalé a mi jefe; hoy lo libero" + una línea del ángulo seguridad (42k cajas expuestas; la mía no escucha en internet). Encaja con autoridad data/IA, no con crianza.
- Posts r/selfhosted + r/homelab (angle seguridad-primero: "42,665 exposed agent boxes; here's one with zero public ports" + "your laptop shouldn't be the always-on server")
- Email corto a Tailscale DevRel (viven de estos casos; Aperture demuestra que cortejan el use case de agentes)
- Mención dirigida a refugiados Gemini CLI (la cuota 1000→20/día es rabia fresca; BIAB ofrece elección de CLI)

### Draft final del Show HN — ángulo ownership (elegido 2026-07-13)

> Gancho = ahorro/propiedad; el dato de seguridad (42.665) va en el cuerpo, no en el título. Esquiva las landmines del §1.4 del BIZ-PLAN (nada de "sovereignty/privacy", "keys not passwords", ni "anti-Anthropic").

**Título:**

`Show HN: Builders in a Box — turn an old PC into a secure, always-on home for your coding agent`

**Primer comentario (autor, al publicar):**

> Anthropic shipped the phone client. I shipped the server.
>
> I already coded with Claude Code every day, but it lived on my laptop — it died when I closed the lid, I couldn't reach it from my phone, and doing it "properly" (a private network, a session that survives a dropped connection, SSH that isn't a liability) was the yak-shave I kept postponing. So I automated the whole thing into one command, and to prove it worked end-to-end I set up a spare mini PC and gave it to my boss as a gift — he was coding from his phone 15 minutes later.
>
> `curl -fsSL https://buildersinabox.com/install.sh | sudo bash` takes any Ubuntu 24.04 box — a mini PC, a homelab VM, or that old laptop in a drawer — and turns it into a persistent dev server you reach from your phone: your chosen AI CLI (Claude Code or Google's Antigravity) in a tmux session that never dies, over a Tailscale private network, with SSH hardened and GitHub wired up.
>
> The part I care about most: the end state has **nothing listening on the open internet**. Early-2026 scans found ~42,665 self-hosted agent boxes exposed publicly, most with auth bypass — this is designed so it's structurally not one of them (Tailscale-only, zero public ports; on a VPS it hardens to key-only first so it can't lock you out mid-session).
>
> It's not a hosted service — if you just want an agent running in the background, Anthropic's Cowork does that. This is for when the agent needs *your* machine: your files, your LAN, your credentials, your cron jobs. MIT, everything it touches is listed in the README, `--uninstall` reverses all of it.
>
> Happy to answer anything about the security model or the setup — I'll be around all day.

**Día L (un sábado con hueco):**
- 09:00 ET Show HN → responder comentarios ese día (es UN día de compromiso, no una cadencia)
- Mismo día: LinkedIn post + r/selfhosted + r/homelab
- La cuenta @buildersinabox X: crearla, biografía + el vídeo pinneado + link. NO compromiso diario — es escaparate, no canal. Posts futuros solo automatizables (releases).

**Post-launch (cap 4 h/semana):**
- Issue templates con expectativas claras ("Ubuntu 24.04 only; otro hardware = best-effort")
- Sin Discord. GitHub Discussions basta.
- Releases via publish.sh cuando toque; Pages auto-deploya.
- Contenido: SOLO si sale de trabajo ya hecho (un fix interesante → post corto), nunca calendario editorial.

## 5. Qué NO hacemos (matado por el consejo)

- ❌ Build-in-public diario en X (viola operating model; morirá en semana 3)
- ❌ Discord / soporte en tiempo real
- ❌ Vender cajas físicas ahora (Contrarian outvoted; queda como opción post-tracción)
- ❌ Prometer módulos umbrella en el hook (Conerator/Observio/Pathtrip fuera del copy de launch)
- ❌ Product Hunt el mismo día (concentrar en HN; PH opcional semanas después con el "1 month in")
- ❌ Traducir las skills SDD antes del launch (siguen opt-in)
- ❌ Stock de hardware (council 2026-07-07, unánime): cero cajas compradas por adelantado.
  Si el OSS tracciona post-gate §3, caja tipo Umbrel (~500-600€, bajo pedido) — el modelo
  validado es OS gratis → comunidad → caja (Umbrel 3,7M$ con 5 empleados); lo que muere es
  hardware de bajo volumen sin comunidad previa (HA Yellow EOL).
- ❌ Soporte OpenClaw como CLI/app opcional del payload en v1: evaluar POST-launch (el mercado
  "agente en casa" se consolida sobre OpenClaw como runtime; mismo trato que Gemini CLI si
  llega — pero no ahora).

## 6. Timeline

| Semana | Qué |
|---|---|
| Sem 1 (jul 8-14) | Fix pack B1-B11 (~6-8h) + reclutar 2-3 betas + email capture en landing |
| Sem 2 (jul 15-21) | Betas instalan; arreglar lo que rompan; grabar vídeo móvil definitivo; republish v0.2.0 |
| Sem 2-3 | **Flip público + Día L** (primer sábado disponible tras betas OK) |
| Sem 3-9 | Cap 4h/semana; medir contra el gate nuevo |
| Sem 9 (~sep) | Checkpoint contra gate §3 → seguir / mantenimiento pasivo |

## 7. Riesgo de agenda que el consejo señaló unánime

Hezu (core 40%) tiene el pipeline Conerator parado desde el 17-jun y el evento purchase sin medir. **Este plan de BIAB cabe en ~12-16 h totales en 2 semanas + 4 h/semana después. Si en algún momento compite con desatascar Hezu, Hezu gana** — es la condición de la decisión OSS-only de mayo y de la tesis barbell.
