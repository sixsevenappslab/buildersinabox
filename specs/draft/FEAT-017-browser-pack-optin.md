# FEAT-017: Browser pack (opt-in, headless) — el agente actúa en la web sin escritorio

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** CHECKPOINT-GATED — NO construir antes de que BIAB pase su gate de 6 semanas (≥500 stars O ≥50 installs + ≥100 email subs + ≥3 testimonios) **Y** haya señal real de que usuarios piden acciones de navegador. Hasta entonces, esta carta se queda en la recámara.
- **Complejidad:** media
- **E2E mode:** none (spike de feasibility ya hecho, ver §2.0)
- **Reconciliation owner:** sdd-coordinator
- **Fase:** tecnica (draft)
- **Creado:** 2026-07-11
- **Actualizado:** 2026-07-11
- **Validado por Jesus:** [x] (2026-07-11 — valida que la spec es correcta y DoR-completa; NO autoriza build, sigue CHECKPOINT-GATED, ver arriba)

## Origen (por qué existe este draft)

Jesús propuso (2026-07-11) migrar BIAB a Ubuntu Desktop para usar el MCP de Chrome de Claude y que el agente actúe en la web por el usuario. El strategy-council (5 voces) fue unánime: **lanzar la versión headless YA, no pivotar** — el navegador logueado + agente autónomo autodestruye el diferenciador de seguridad, rompe VPS/headless, compite con Operator/Cowork, y llega el día del último gate de código (patrón de "huir del grind de distribución"). PERO la idea en su forma FUERTE — **computer-use privado y self-hosted** (tu agente-navegador en TU caja, con TUS datos, lo contrario de Operator) — es genuinamente diferenciada y mira hacia donde va el mercado. Decisión de Jesús: lanzar headless + spike técnico timeboxed para tener esta carta lista. Este FEAT ES esa carta.

## Definition of Ready (DoR) — COMPLETA 2026-07-11

> **Ojo:** DoR completa = la spec está lista para construir *cuando se abra el gate de checkpoint*. El `[x]` de Jesús aquí valida **que la spec es correcta**, NO autoriza el build (sigue CHECKPOINT-GATED, ver Metadata).

### Producto (§1) — Elena
- [x] Problema explícito
- [x] Intent (why) separado del problema
- [x] ≥1 historia de usuario (2)
- [x] ≥3 requisitos funcionales EARS (4)
- [x] Boundaries Always/Ask First/Never

### Spec Técnica (§2) — Laura
- [x] Investigación con rutas verificadas (file:line, §2.2) + spike (§2.0)
- [x] Tabla archivos afectados (§2.4)
- [x] ≥1 task con verify ejecutable + done observable (6 tasks, §2.6)
- [x] Patrón de código real (§2.7)
- [x] Criterios globales verificables (§2.8)
- [x] Gaps de QA reconciliados (§2.9)

### QA (§4) — Pablo
- [x] ≥1 funcional + ≥1 edge + ≥1 regresión + casos de seguridad
- [x] Criterios de testing ejecutables (§4.11)

### Growth (§1.Growth) — N/A
- [x] Sin canal/SEO directo; el ángulo de posicionamiento ("computer-use privado self-hosted") ya vive en Intent/Origen. Métrica directa N/A.

## 1. Requisitos

### Problema

Hoy BIAB da al agente un hogar para trabajar con CÓDIGO. Muchas tareas de valor son web (rellenar, investigar en vivo, actuar en apps web), no código. Sin capacidad de navegador, el agente no puede hacerlas.

### Intent (why)

Extender lo que el agente puede hacer POR el usuario, **sin traicionar el diferenciador de seguridad ni el modelo headless/VPS**. La forma fuerte no es "otro Operator", es *computer-use privado y self-hosted*: la privacidad como ventaja, no como coste. Solo se construye si el dato (checkpoint) dice que a los usuarios les importa — no por entusiasmo de creador.

### Solución propuesta

Un **"browser pack" OPT-IN** (`biab pack add browser`), **headless**, que NO requiere Ubuntu Desktop:
- **Playwright headless** (Chromium) como motor — corre en Ubuntu Server sin display. Fallback `--headful-xvfb` (solo Xvfb, ~2 MB, NO un escritorio) para las webs que bloquean headless.
- Se expone al agente como MCP/CLI (`biab-browse <task>`) con herramientas `open/read_text/click/fill/screenshot`.
- Corre como usuario dedicado **`biab-browser`** (sandbox de chromium activo, sin acceso a los ficheros del proyecto ni a `~/.ssh`/credenciales).
- **Seguridad por defecto:** perfil de navegador **efímero y aislado, SIN sesiones logueadas ambientales** — el agente NO hereda tus cookies de banco/correo. Login por tarea es explícito y opt-in (perfil persistente nombrado, decisión consciente por servicio).

### Historias de usuario

- Como usuario, quiero que mi agente pueda leer/rellenar/actuar en webs por mí, desde mi caja, sin mandar mis datos a la nube de un tercero.
- Como usuario preocupado por la seguridad, quiero que por defecto el agente NO tenga acceso a mis sesiones logueadas — que cada login sea una decisión mía explícita.

### Requisitos funcionales (EARS)

- [ ] **Optional:** Where el usuario instala el browser pack, el sistema shall darle al agente herramientas de navegador (open/read/click/fill/screenshot) en una caja headless SIN instalar un escritorio.
- [ ] **Ubicuo:** El browser pack shall correr como un usuario dedicado sin acceso a los ficheros/credenciales del usuario.
- [ ] **Unwanted:** Si el usuario no autoriza explícitamente un login, el agente shall usar un perfil efímero sin sesiones logueadas (nunca heredar cookies ambientales).
- [ ] **Event-driven:** Cuando una web bloquea headless, el sistema shall poder reintentar en modo headful bajo Xvfb (flag), sin instalar un entorno gráfico.

### Boundaries

**Always:** opt-in (nunca en el bundle por defecto ni en el manifest core de skills); headless por defecto; usuario dedicado `biab-browser` (nologin, sin sudo) con sandbox de Chromium ACTIVO (nunca `--no-sandbox` en el path por defecto); perfil efímero sin logins ambientales por defecto; documentar el modelo de amenaza (prompt-injection en la web visitada) en la skill; el pack shipea pero no se auto-instala (patrón de `payload/hooks/`).

**Ask First (refinado por Laura — seguridad):** persistir un perfil logueado en un servicio; dar egress no revisado; cualquier cosa que toque credenciales del usuario; **exponer el navegador como servidor MCP** (v1 es CLI plano `biab-browse`; MCP añade proceso de larga vida + config por-CLI, decisión consciente); relajar el sandbox / usar `--no-sandbox` o abrir userns vía AppArmor global (debe ser acotado SOLO al binario del navegador).

**Never:** hacer del navegador el default (rompe seguridad/headless/VPS); requerir Ubuntu Desktop o instalar un entorno gráfico (solo Xvfb en el fallback); heredar las sesiones logueadas del usuario por defecto; correr el motor como root o como el usuario operador; que `biab-browser` tenga acceso a `~operador/.ssh`, a los ficheros del proyecto o a `-G sudo`; **construir esto antes del checkpoint de 6 semanas + señal de demanda**; competir de frente como "otro Operator" (el ángulo es privado/self-hosted).

## 2. Spec Técnica

### 2.0 Investigación previa — SPIKE de feasibility (2026-07-11, VM Ubuntu 24.04 limpia, 2 vCPU/4 GB, sin escritorio). Veredicto: **GO**.

- **Desktop NO hace falta** (probado, no asumido): la VM no tenía binarios de escritorio/X en ningún momento. Playwright headless no necesita display alguno; Xvfb (fallback) es un framebuffer falso de ~2 MB, no un escritorio.
- **A) Playwright headless — FUNCIONA.** Navegó example.com + news.ycombinator.com (JS), extrajo texto, click→página 2, rellenó búsqueda. Disco: **~262 MB** (chromium-headless-shell) o 646 MB si instalas el chromium completo; `node_modules` 18 MB. RAM pico **~688 MB**, run ~2 s. **← path recomendado.**
- **B) Chromium headful bajo Xvfb — FUNCIONA** como fallback. Chrome real (UA `X11; Linux x86_64`), driven por CDP. Coste extra: ~2× RAM (~1.3 GB) + gestionar el ciclo de Xvfb. Usar el chromium bundled de Playwright, **NO el snap** (confinamiento AppArmor = dolor headless).
- **claude-in-chrome (MCP de Chrome) NO sirve aquí:** es una extensión + MCP para el Chrome REAL e interactivo del usuario (permisos por UI, sesión logueada, humano en el bucle). No encaja en un server headless autónomo. En la caja BIAB el camino es **Playwright/CDP**, no la extensión. (claude-in-chrome sigue siendo la herramienta correcta en el portátil/Mac del propio usuario — otra superficie.)
- **Concurrencia:** ~700 MB/run → en 4 GB caben ~2-3 navegadores headless a la vez antes de presión.

### 2.1 Límites del spike (a cerrar cuando/si se construye)

- El path sandbox no-root no se validó end-to-end (se corrió como root con `--no-sandbox`). El modelo de seguridad de §1 es un sketch, no implementación verificada.
- Solo se probaron webs públicas simples. Sin probar: anti-bot (Cloudflare/CAPTCHA), login walls, descargas, sesiones concurrentes/largas — ahí está la fricción real.
- Cifras de RAM aproximadas (±10-15%, RSS sampleado).

### 2.2 Investigación previa — puntos de integración REALES en el repo (verificados 2026-07-11)

> Rutas verificadas con `ls`/`sed` sobre el checkout. "EXISTE" = ya está en el árbol; "CREAR" = hay que construirlo. Esto convierte el spike (que dice *si se puede*) en un plan de *cómo engancha*.

**El comando `biab` y el patrón de subcomandos**
- `payload/install/05-biab-command.sh:19-105` instala `/usr/local/bin/biab`, un wrapper heredoc. El `case` (`:85-104`) enruta subcomandos: `""`, `status`, `logs`, `update`, `add`, `help`.
- **`biab pack` NO existe.** Lo que existe es `biab add <group>` (`do_add`, `:37-55`), pensado para *grupos de skills* y hoy un no-op amistoso (SDD se volvió core en v0.2). El §1 de este FEAT pide `biab pack add browser`.
- **Decisión: CREAR un subcomando `pack` nuevo** (`do_pack`), separado de `add`. Justificación: `add` copia directorios de skills (SKILL.md) sin trabajo de root; un *pack* es más pesado — instala paquetes apt/npm, crea un usuario de sistema, deja un binario en PATH y configura sandbox. Semánticamente son cosas distintas; mezclarlas ensucia el modelo mental y el `case`. `pack` delega en scripts del pack (`/opt/buildersinabox/payload/pack/<name>/{install,uninstall}.sh`), quedando el wrapper como dispatcher fino. Mantener `add` intacto (compat).

**Cómo se instalan y empaquetan skills/capacidades**
- `payload/wizard/40-scaffold.sh:112-159` instala skills: `install_skill()` copia `payload/skills/<name>` a `~/.agents/skills/<name>` (fuente de verdad) y **symlinka** en `~/.claude/skills/<name>` y, si `ai_cli=antigravity`, en `~/.gemini/skills/<name>`. Es idempotente. Guiado por `payload/skills/manifest.tsv` (tiers `core`/`optional`; hoy todo `core`).
- El pack reutilizará ESTE mismo patrón para su skill `browser`, pero la skill vive **dentro del pack** (`payload/pack/browser/skill/`), NO en `payload/skills/` — así el barrido del manifest de `40-scaffold.sh` no la instala nunca por defecto (garantiza opt-in). El `install.sh` del pack replica la lógica de copy+symlink de `install_skill`.

**Cómo se le expone tooling al agente hoy → decisión MCP vs CLI**
- El repo expone capacidades al agente por DOS vías, ninguna MCP: (1) **CLIs planos en PATH** — `biab` (`05-biab-command.sh`) y `bd` (`06-bd-cli.sh` → `payload/scripts/bd`); (2) **skills** (`SKILL.md`) que enseñan al agente a invocarlos.
- `40-scaffold.sh:196-222` siembra `~/.claude/settings.json` con **hooks** (guardrail/format/lint/session-log) y `:174-188` mergea el `settings.json` de agy. **No hay NINGÚN wiring de servidores MCP en toda la caja.** La única mención MCP es frontmatter aspiracional en `payload/skills/ui-ux-consultant/SKILL.md:4` (`allowed-tools` con tools playwright-mcp), pero nada instala ni registra ese servidor.
- **Decisión: v1 expone el navegador como CLI plano `biab-browse` + una skill `browser` (SKILL.md), NO como servidor MCP.** Justificación: (a) calca el patrón vivo `bd`/`biab` + skill; (b) es **CLI-agnóstico** — funciona idéntico para `claude` y `agy` sin sembrar config por-CLI (Claude Code y agy usan formatos/ubicaciones MCP distintos, y el repo no tiene infra para ninguno); (c) MCP exigiría un proceso servidor de larga vida + dos formatos de config nuevos, superficie que el spike NO validó. MCP queda anotado como mejora futura (§3 Ask First), no v1.

**Node / motor**
- `payload/install/00-base.sh:30-44` instala **Node.js 20 (NodeSource)** en toda caja. Playwright lo necesita y ya está. El pack instala `playwright-core` + el shell headless de Chromium bajo el usuario dedicado (no toca el Node global salvo el `npm` para bootstrapping).

**Usuario dedicado `biab-browser` (modelo de seguridad)**
- El repo crea el usuario HUMANO operador con `useradd -m -s /bin/bash -G sudo` (`payload/install.sh:279`) — un usuario de login, no de servicio. **No existe patrón de usuario `--system`/service en el repo.** Hay que CREARLO: `useradd --system --home-dir /var/lib/biab-browser --shell /usr/sbin/nologin biab-browser`, y ejecutar el motor vía `sudo -u biab-browser` / `systemd-run --uid`. Este usuario NO va en `-G sudo` y no tiene acceso a `~operador/.ssh` ni a los ficheros del proyecto.
- **Gotcha Ubuntu 24.04 (a resolver en implementación):** userns no privilegiado está restringido por AppArmor (`kernel.apparmor_restrict_unprivileged_userns=1`), por lo que el sandbox de Chromium como no-root falla salvo config extra. El spike lo esquivó corriendo como root con `--no-sandbox` (ver §2.1). El pack debe usar el `chrome-sandbox` setuid del bundle de Playwright **o** instalar un perfil AppArmor que permita userns SOLO al binario del navegador. Este es el punto duro y tiene tarea propia con `<verify>`.

**Qué SHIPEA (opt-in) y qué no**
- `.gitattributes` marca `export-ignore` para docs de mantenedor y `specs/`. `payload/hooks/` **NO** está export-ignored → shipea. El pack (`payload/pack/`) debe seguir el mismo patrón: **SHIPEA en el tarball** (para poder `biab pack add` offline) pero **NO se instala** por defecto (no está en el manifest core; `install.sh` no lo llama). Opt-in = "presente en disco, ausente del sistema hasta que lo pidas".

**Uninstall**
- `payload/install.sh:122-196` (`do_uninstall`) borra rutas BIAB-owned de una lista fija. El pack añade su propio teardown modular (`biab pack remove browser` → `payload/pack/browser/uninstall.sh`): borra el usuario `biab-browser`, su home, el binario `biab-browse`, la skill y los perfiles. `do_uninstall` puede invocar el teardown del pack si está instalado (best-effort), pero la fuente de verdad del borrado vive en el pack.

### 2.3 Alcance

#### Incluye

- Subcomando `biab pack {add,remove,list}` en el wrapper `biab` (dispatcher fino a scripts del pack).
- Directorio del pack `payload/pack/browser/` que SHIPEA pero no se auto-instala: `install.sh`, `uninstall.sh`, el CLI `biab-browse`, el driver Node sobre Playwright, la skill `browser/`.
- Motor **Playwright headless-shell (Chromium)** pinneado, instalado bajo el usuario dedicado; footprint dentro de las cifras del spike (~262 MB disco, ~700 MB RAM/run).
- Usuario de sistema `biab-browser` (nologin, sin sudo, sin acceso a credenciales del operador) + sandbox de Chromium activo como no-root.
- Interfaz agente-facing: CLI `biab-browse` con verbos `open/read_text/click/fill/screenshot` + skill `browser` (SKILL.md) que enseña a usarlo.
- Seguridad por defecto: **perfil efímero y aislado** (`--user-data-dir` en `mktemp -d`, limpiado al salir), sin heredar cookies/sesiones ambientales.
- Fallback `--headful-xvfb` (solo Xvfb, sin escritorio) para webs que bloquean headless.
- Opt-in real: ausente del install por defecto y del manifest core.
- Uninstall del pack (`biab pack remove browser`) que revierte usuario + ficheros + skill.

#### NO incluye (OBLIGATORIO)

- **NO** servidor MCP (v1 es CLI plano; MCP es mejora futura, Ask First).
- **NO** perfiles persistentes/logueados por defecto (login por servicio es opt-in explícito, fuera del alcance v1 salvo el mecanismo mínimo de "perfil nombrado" si sobra tiempo — por defecto NO).
- **NO** hacer del navegador el default ni tocar el bundle de skills core / el flujo del wizard.
- **NO** requerir Ubuntu Desktop ni instalar entorno gráfico (solo Xvfb en el fallback).
- **NO** resolver anti-bot/CAPTCHA/Cloudflare ni descargas (fuera de alcance; documentar como límite conocido).
- **NO** modificar `05-biab-command.sh` más allá de añadir el case `pack` (no refactor del wrapper).

### 2.4 Archivos afectados

| Archivo | Acción | Propósito |
|---------|--------|-----------|
| `payload/install/05-biab-command.sh` | MODIFICAR | Añadir `do_pack()` + case `pack)` al `case` del wrapper heredoc. Sin refactor del resto. |
| `payload/pack/browser/install.sh` | CREAR | Instalador idempotente del pack: crea usuario `biab-browser`, instala Playwright + headless-shell pinneado bajo su home, configura sandbox, instala `biab-browse` en PATH, copia+symlinka la skill. |
| `payload/pack/browser/uninstall.sh` | CREAR | Teardown: borra `biab-browse`, la skill, los perfiles, el home del usuario y el usuario. Idempotente. |
| `payload/pack/browser/bin/biab-browse` | CREAR | CLI agente-facing (dispatcher). Re-ejecuta como `biab-browser`, monta perfil efímero, invoca el driver Node. Verbos `open/read_text/click/fill/screenshot`; flag `--headful-xvfb`. |
| `payload/pack/browser/driver/browse.mjs` | CREAR | Driver Node sobre `playwright-core`: abre Chromium headless, ejecuta el verbo, imprime resultado (texto/JSON/ruta screenshot). |
| `payload/pack/browser/driver/package.json` | CREAR | Pin exacto de `playwright-core` (versión fija) para el proyecto Node del pack. |
| `payload/pack/browser/skill/browser/SKILL.md` | CREAR | Skill que enseña al agente a llamar `biab-browse` (verbos, ejemplos, modelo de amenaza: prompt-injection en la web visitada). Strings en inglés. |
| `payload/pack/browser/lib.sh` | CREAR | Helpers del pack (resolución de usuario objetivo, rutas, sandbox check). Puede `source` `../../lib/common.sh` si se ejecuta desde el árbol. |
| `payload/install.sh` | MODIFICAR | `do_uninstall`: invocar best-effort el teardown del pack si `payload/pack/browser/uninstall.sh` existe y el pack está instalado. |
| `payload/pack/browser/tests/test-pack.bats` (o `.sh`) | CREAR | Tests: opt-in (ausente sin instalar), headless sin display, usuario dedicado, perfil efímero, footprint, uninstall limpio. |
| `.gitattributes` | VERIFICAR (probable no-op) | Confirmar que `payload/pack/` NO queda export-ignored (debe shipear como opt-in, igual que `payload/hooks/`). |
| `docs/architecture.md` (y/o `CLAUDE.md`) | MODIFICAR | Documentar el pack como capacidad opt-in headless, el modelo de seguridad y el ángulo self-hosted. |

> Todas las rutas `payload/pack/**` son NUEVAS (el dir no existe hoy). `05-biab-command.sh`, `install.sh`, `.gitattributes`, `docs/architecture.md` EXISTEN.

### 2.5 Dependencias

- **Nuevas (aisladas en el usuario del pack, no globales):** `playwright-core` (versión pinneada exacta) + Chromium **headless-shell** vía `npx playwright install chromium-headless-shell` (NO el snap; NO el chromium completo salvo que se justifique).
- **Sistema (fallback):** `xvfb` (apt, ~2 MB) — instalado SOLO si el usuario usa `--headful-xvfb`, no en el install base del pack.
- **Ya disponibles:** Node 20 (`00-base.sh`), `jq`, `curl`, `git` (`00-base.sh`). Sin cambios en el stack base.

### 2.6 Tareas (máx. 6, en waves)

#### Wave 1 — Subcomando + motor

<task id="1">
  <name>Subcomando `biab pack` (dispatcher) + esqueleto del pack</name>
  <files>payload/install/05-biab-command.sh, payload/pack/browser/lib.sh</files>
  <action>
    En el heredoc de `05-biab-command.sh` añadir `do_pack()` siguiendo el estilo de `do_add()`/`do_update()`: sub-verbos `list` (lista packs disponibles + estado instalado/no), `add <name>` (exec `/opt/buildersinabox/payload/pack/<name>/install.sh`), `remove <name>` (exec `.../uninstall.sh`). Añadir `pack) shift; do_pack "$@" ;;` al `case`. Actualizar el heredoc de `help`. NO refactorizar el resto del wrapper. Crear `payload/pack/browser/lib.sh` con helpers (resolver usuario operador vía state.json, rutas del pack, `pack_is_installed`). `set -euo pipefail`, idempotente, strings en inglés.
  </action>
  <verify>bash -n payload/install/05-biab-command.sh &amp;&amp; shellcheck payload/install/05-biab-command.sh payload/pack/browser/lib.sh</verify>
  <done>`bash -n` y `shellcheck` limpios; el heredoc contiene un case `pack)` que enruta `list/add/remove`; `biab pack list` (tras instalar el wrapper) imprime `browser  not installed`.</done>
</task>

<task id="2">
  <name>Instalador del pack: Playwright headless-shell pinneado bajo usuario dedicado</name>
  <files>payload/pack/browser/install.sh, payload/pack/browser/driver/package.json, payload/pack/browser/driver/browse.mjs</files>
  <action>
    `install.sh` idempotente (`set -euo pipefail`, `require_root`): (1) crea el proyecto Node del pack en `/var/lib/biab-browser/driver` con `package.json` pinneando `playwright-core` a una versión exacta; (2) `npm ci`/`npm install` + `npx playwright install chromium-headless-shell` con `PLAYWRIGHT_BROWSERS_PATH` bajo el home del usuario dedicado; (3) instala `bin/biab-browse` en `/usr/local/bin/biab-browse` (0755). `browse.mjs` implementa el arranque headless de Chromium y un verbo `open`+`read_text` mínimo. Verificar footprint contra el spike. NO instalar el chromium completo ni el snap.
  </action>
  <verify>sudo /opt/buildersinabox/payload/pack/browser/install.sh &amp;&amp; du -sh /var/lib/biab-browser/.cache/ms-playwright 2>/dev/null; biab-browse open https://example.com read_text | head</verify>
  <done>Instalación sin error; caché de navegadores ≈250-300 MB (headless-shell, no el full ~646 MB); `biab-browse open example.com read_text` imprime texto de la página SIN display (sin `$DISPLAY`).</done>
</task>

#### Wave 2 — Seguridad + interfaz (dependen de Wave 1)

<task id="3">
  <name>Usuario de sistema `biab-browser` + sandbox no-root + perfil efímero por defecto</name>
  <files>payload/pack/browser/install.sh, payload/pack/browser/bin/biab-browse</files>
  <action>
    En `install.sh`: crear `useradd --system --home-dir /var/lib/biab-browser --shell /usr/sbin/nologin biab-browser` (idempotente: `getent passwd` guard); chown del driver/caché al usuario. En `biab-browse`: re-ejecutar el driver como `biab-browser` (`sudo -u biab-browser` o `systemd-run --uid`), montar SIEMPRE por defecto un `--user-data-dir="$(mktemp -d)"` borrado con `trap` al salir (perfil efímero, sin cookies ambientales). Resolver el sandbox de Chromium como no-root (chrome-sandbox setuid del bundle Playwright o perfil AppArmor que permita userns solo al binario del navegador). Cerrar el límite del spike §2.1: NO usar `--no-sandbox` en el path por defecto.
  </action>
  <verify>ps -o user= -C chrome_crashpad_handler 2>/dev/null; sudo -u biab-browser test ! -r /home/*/.ssh/id_ed25519 &amp;&amp; echo "no ssh access"; biab-browse open https://example.com read_text >/dev/null &amp;&amp; echo ok</verify>
  <done>El proceso del navegador corre como `biab-browser` (no root, no el operador); `biab-browser` NO puede leer `~operador/.ssh`; el navegador arranca con sandbox activo (verificable en `chrome://sandbox` o logs, sin `--no-sandbox`); tras la tarea el `user-data-dir` efímero ya no existe.</done>
</task>

<task id="4">
  <name>CLI agente-facing completa (`open/read_text/click/fill/screenshot`) + skill `browser`</name>
  <files>payload/pack/browser/bin/biab-browse, payload/pack/browser/driver/browse.mjs, payload/pack/browser/skill/browser/SKILL.md</files>
  <action>
    Completar los verbos en `browse.mjs` y su parseo en `biab-browse` (`open <url>`, `read_text`, `click <selector>`, `fill <selector> <value>`, `screenshot <path>`). Salidas deterministas (texto/JSON/ruta). Crear la skill `browser/SKILL.md` (frontmatter `name`/`description`, en inglés) que enseña al agente a llamar `biab-browse`, con ejemplos y una sección de **modelo de amenaza** (prompt-injection desde la web visitada; el navegador no tiene acceso a credenciales). `install.sh` copia la skill a `~/.agents/skills/browser` y la symlinka en `~/.claude/skills/` (y `~/.gemini/skills/` si `ai_cli=antigravity`), replicando `install_skill` de `40-scaffold.sh`.
  </action>
  <verify>biab-browse open https://news.ycombinator.com read_text | grep -qi 'hacker news' &amp;&amp; echo textok; test -L "$HOME/.claude/skills/browser" &amp;&amp; echo skillok</verify>
  <done>`read_text` sobre HN devuelve texto con "Hacker News"; `click`/`fill`/`screenshot` ejecutan sin error sobre una página de prueba; la skill `browser` está symlinkada en `~/.claude/skills/browser` y aparece al escribir `/` en el CLI.</done>
</task>

<task id="5">
  <name>Fallback `--headful-xvfb` (sin escritorio)</name>
  <files>payload/pack/browser/bin/biab-browse, payload/pack/browser/install.sh</files>
  <action>
    Añadir flag `--headful-xvfb` que lance Chromium headful bajo `xvfb-run` (framebuffer, NO escritorio). Instalar `xvfb` (apt) de forma perezosa la primera vez que se use el flag (o documentar que `biab pack add browser --with-xvfb` lo pre-instala). Usar el Chromium bundled de Playwright (NO snap). Gestionar el ciclo de vida de Xvfb (arranque/parada) dentro del wrapper.
  </action>
  <verify>biab-browse --headful-xvfb open https://example.com read_text >/dev/null &amp;&amp; echo xvfbok; dpkg -l | grep -q xvfb &amp;&amp; echo xvfbpkg</verify>
  <done>La tarea corre en modo headful bajo Xvfb (UA `X11; Linux x86_64`) sin ningún entorno gráfico instalado; `xvfb` presente solo tras usar el flag; sin display real requerido.</done>
</task>

#### Wave 3 — Opt-in, uninstall, verificación global (depende de Waves 1-2)

<task id="6">
  <name>Opt-in real + uninstall + verificación global</name>
  <files>payload/install.sh, .gitattributes, payload/pack/browser/uninstall.sh, payload/pack/browser/tests/test-pack.sh, docs/architecture.md</files>
  <action>
    Confirmar que `payload/pack/` NO está en `.gitattributes` export-ignore (shipea) y que NADA en `install.sh`/manifest lo instala por defecto. `uninstall.sh`: borrar `biab-browse`, la skill (+symlinks), perfiles, caché, home y el usuario `biab-browser` (idempotente). En `install.sh do_uninstall`: llamar best-effort al teardown del pack si está instalado. Tests en `tests/test-pack.sh`: opt-in (fresh install sin `biab-browse`), headless sin display, usuario dedicado, perfil efímero, footprint, uninstall limpio. Documentar en `docs/architecture.md`. `shellcheck` de todo el pack.
  </action>
  <verify>shellcheck payload/pack/browser/*.sh payload/pack/browser/bin/biab-browse; git archive HEAD | tar -t | grep -q '^payload/pack/browser/' &amp;&amp; echo ships; bash payload/pack/browser/tests/test-pack.sh</verify>
  <done>`shellcheck` limpio en todo el pack; `git archive` incluye `payload/pack/browser/` (shipea) pero un install por defecto NO deja `biab-browse` en PATH; `biab pack remove browser` borra usuario+ficheros (verificable con `getent passwd biab-browser` vacío); todos los tests pasan.</done>
</task>

### 2.7 Patrón de código a seguir

Estilo del wrapper `biab` (heredoc en `05-biab-command.sh`) — el nuevo `do_pack` calca `do_add`/`do_update`:

```bash
do_pack() {
    # `biab pack add|remove|list <name>` manages heavyweight opt-in packs
    # (system packages, a dedicated user, a CLI on PATH). Skill-only groups
    # still go through `biab add`. Packs live in the shipped-but-not-installed
    # payload/pack/<name>/ tree; add/remove just exec their scripts.
    local action="${1:-}"; shift || true
    local name="${1:-}"
    local packroot=/opt/buildersinabox/payload/pack
    case "$action" in
        list)
            for d in "$packroot"/*/; do
                [[ -d "$d" ]] || continue
                local n; n="$(basename "$d")"
                if command -v "biab-${n%/}" >/dev/null 2>&1; then
                    printf '%s\tinstalled\n' "$n"
                else
                    printf '%s\tnot installed\n' "$n"
                fi
            done ;;
        add)
            [[ -n "$name" ]] || { echo "usage: biab pack add <name>" >&2; exit 1; }
            exec sudo "$packroot/$name/install.sh" "$@" ;;
        remove)
            [[ -n "$name" ]] || { echo "usage: biab pack remove <name>" >&2; exit 1; }
            exec sudo "$packroot/$name/uninstall.sh" ;;
        *)
            echo "usage: biab pack {list|add|remove} <name>" >&2; exit 1 ;;
    esac
}
```

Estilo de instalador de pack (idempotente, guardas `getent`, siguiendo `05-biab-command.sh`/`06-bd-cli.sh` y el `install_skill` de `40-scaffold.sh`):

```bash
# Create the dedicated, unprivileged browser user (idempotent).
if ! getent passwd biab-browser >/dev/null; then
    useradd --system --home-dir /var/lib/biab-browser \
        --shell /usr/sbin/nologin biab-browser
    log "browser-pack: created system user biab-browser"
fi
install -d -o biab-browser -g biab-browser -m 0750 /var/lib/biab-browser
```

### 2.8 Criterios de aceptación (VERIFICABLES)

- [ ] **Opt-in real:** un install por defecto (`payload/install.sh` sin `biab pack add`) NO deja `biab-browse` en PATH ni el usuario `biab-browser` en `getent passwd`. La capacidad aparece SOLO tras `biab pack add browser`.
- [ ] **Shipea en el tarball:** `git archive HEAD | tar -t | grep '^payload/pack/browser/'` devuelve ficheros (no está export-ignored).
- [ ] **Headless sin escritorio:** `biab-browse open https://example.com read_text` imprime texto con `$DISPLAY` vacío y sin ningún paquete de entorno gráfico instalado.
- [ ] **Usuario dedicado + sandbox:** el proceso del navegador corre como `biab-browser` (no root, no operador), con sandbox de Chromium ACTIVO (sin `--no-sandbox` en el path por defecto), y `biab-browser` no puede leer `~operador/.ssh`.
- [ ] **Perfil efímero por defecto:** cada `biab-browse` usa un `--user-data-dir` temporal borrado al salir; no hay estado de sesión persistente entre invocaciones sin opt-in explícito.
- [ ] **Footprint dentro del spike:** caché de navegadores ≈250-300 MB (headless-shell), RAM pico por run ≲ ~700 MB.
- [ ] **Fallback:** `biab-browse --headful-xvfb ...` funciona bajo Xvfb sin escritorio.
- [ ] **Uninstall limpio:** `biab pack remove browser` deja `getent passwd biab-browser` vacío, sin `biab-browse` en PATH y sin la skill.
- [ ] `shellcheck` limpio en todo `payload/pack/browser/**` y en `05-biab-command.sh`.

### 2.9 Reconciliación de gaps de QA (decisiones de coordinador, 2026-07-11)

QA (§4.12) señaló 6 gaps de testabilidad. Decisiones para el momento del build (no cambian el gate de checkpoint):

1. **Sandbox FAIL-CLOSED (crítico).** El driver (`browse.mjs`) shall abortar con error si el sandbox de Chromium no arranca — NUNCA degradar silenciosamente a `--no-sandbox` (un fallback silencioso pasaría B2/B3 violando el modelo). Se añade a §1 Always y a Task 3 un `<verify>` explícito de estado de sandbox (readout verificable, no solo grep estático). Grep estático (S4) es necesario pero NO suficiente.
2. **Ruta de sandbox = [DANGER ZONE si AppArmor].** Task 3 deja dos rutas (chrome-sandbox setuid del bundle Playwright vs perfil AppArmor acotado al binario). **Preferencia: la setuid del bundle** (no toca `/etc/apparmor.d/`). Si en el build resulta imprescindible un drop-in AppArmor → es config de seguridad global → **requiere OK explícito de Jesús** (regla danger-zone de CLAUDE.md). Se pinea en el build, no antes.
3. **Límite de concurrencia (v1 = serializar).** El spike da ~2-3 navegadores/4 GB antes de presión, y §2 no implementaba límite. Decisión v1: `biab-browse` shall serializar (límite por defecto = 1 run activo, vía lockfile/flock), configurable. Evita que llamadas paralelas del agente disparen el OOM-killer contra procesos del operador. Semáforo N>1 = v0.2.
4. **Handoff de screenshot (cross-user).** El motor corre como `biab-browser`, el agente como operador → los ficheros de salida (screenshots) deben caer en un dir de handoff con ownership definido y legible por el operador (p.ej. `/var/lib/biab-browser/out`, group-readable al operador, o copia con `install -o operador`). Se añade AC a §4 y contrato de salida a Task 4.
5. **Fixtures locales, no webs vivas.** Los casos de contrato del CLI usan un `python3 -m http.server` local (determinista); example.com/HN/httpbin quedan solo para el E2E manual (`[sesión]`). Evita flakiness en CI.
6. **Assert permanente de opt-in en CI.** Añadir a CI una aserción permanente (patrón AC-LOG1 de FEAT-015) de que `browser` NUNCA aparece en `payload/skills/` ni en `manifest.tsv` — el opt-in no puede depender solo de una convención de ubicación. Se folda en Task 6.

## 4. QA (Pablo)

### 4.0 Estrategia

El pack es un instalador bash + un CLI Node sobre Playwright + un usuario de sistema + una skill. El riesgo NO está en "¿navega?" (el spike §2.0 ya dijo GO): está en **(a) el opt-in real** (que un install por defecto no traiga nada de esto) y **(b) el modelo de seguridad** (usuario aislado, sandbox activo, perfil efímero) — que es exactamente lo que el spike §2.1 dejó SIN validar. Por eso el peso de esta §4 recae en regresión de ausencia y en las pruebas de seguridad, no en el happy path.

Verificación en tres planos:

1. **Contrato del CLI (aislado, reproducible sobre una caja con el pack instalado):** `biab-browse <verbo> ...` es una caja `args → stdout determinista + exit code`. Se dispara y se inspecciona `$?` + stdout. Determinista, no necesita sesión del agente.
2. **Invariantes de sistema (sobre la caja):** presencia/ausencia de usuario (`getent passwd`), de binario (`command -v`), de skill (symlink), footprint (`du`/RSS), identidad del proceso navegador (`ps -o user=`), sandbox activo. Son asserts de estado, no de output.
3. **Efecto E2E de cara al agente (`[sesión]`):** en una sesión `claude`/`agy` sobre la caja con el pack, pedir una tarea web y observar que el agente la ejecuta vía la skill `browser`. Cubre el wiring skill→CLI.

**Convención:** los ejemplos asumen una VM Ubuntu 24.04 Server **sin escritorio** (misma clase que el spike: 2 vCPU / 4 GB), `set -uo pipefail`. `FRESH` = caja recién instalada por `payload/install.sh` **sin** `biab pack add browser`. `PACKED` = la misma caja tras `biab pack add browser`. `OP` = el usuario operador humano.

Cada caso cita el/los EARS de §1 y la/s tarea/s de §2.6 que cubre.

---

### 4.1 Casos funcionales — instalación + navegación headless

**AC-B1 — `biab pack add browser` instala el pack completo.** (EARS-1 · Tasks 1,2,3)
Sobre `FRESH`, un solo comando deja el sistema en estado `PACKED`: usuario dedicado creado, motor pinneado bajo su home, CLI en PATH, skill symlinkada.
- *pasos:*
  1. `biab pack list` → imprime `browser⇥not installed`.
  2. `sudo /opt/buildersinabox/payload/pack/browser/install.sh` (o `biab pack add browser`).
  3. `getent passwd biab-browser` → devuelve una línea (usuario existe).
  4. `command -v biab-browse` → `/usr/local/bin/biab-browse`.
  5. `test -L "$HOME/.claude/skills/browser"` (o `~/.gemini/skills/browser` si `ai_cli=antigravity`) → symlink presente.
  6. `biab pack list` → ahora `browser⇥installed`.
- *criterio:* los pasos 3-6 pasan; instalación idempotente (segunda corrida de `install.sh` → `exit 0`, sin duplicar usuario ni error de `useradd`).

**AC-B2 — Navegación headless sin display: `open` + `read_text`.** (EARS-1 · Task 2)
Sobre `PACKED`, en una caja **sin `$DISPLAY` y sin ningún paquete de entorno gráfico**, el CLI devuelve el texto de la página.
- *test:*
  ```bash
  DISPLAY= biab-browse open https://example.com read_text | grep -qi 'example domain' \
    && echo PASS || echo FAIL
  ```
- *criterio:* stdout contiene el texto de la página con `$DISPLAY` vacío; `exit 0`. Confirmar que NO hay escritorio: `dpkg -l | grep -Ei 'xserver-xorg|gnome-shell|ubuntu-desktop'` → **vacío** (solo Xvfb aparecería, y solo si ya se usó el fallback — ver AC-B7).

**AC-B3 — Página con JS pesado (contrato realista del spike).** (EARS-1 · Task 4)
`read_text` sobre una SPA/página con JS (el spike usó Hacker News) devuelve texto renderizado, no el HTML crudo pre-JS.
- *test:* `biab-browse open https://news.ycombinator.com read_text | grep -qi 'hacker news' && echo textok`.
- *criterio:* aparece contenido dependiente de JS; `exit 0`. Mapea al `<verify>` de Task 4.

---

### 4.2 Casos funcionales — verbos completos + skill

**AC-B4 — Los cinco verbos ejecutan con salida determinista.** (EARS-1 · Task 4)
`open / read_text / click / fill / screenshot` funcionan sobre una página de prueba controlada (servir un HTML local con `python3 -m http.server` para no depender de la red externa: un `<input>`, un `<a>` y texto).
- *pasos (contra `http://127.0.0.1:PORT/form.html`):*
  1. `biab-browse open <url> read_text` → texto esperado.
  2. `biab-browse open <url> fill '#q' 'hola'` → `exit 0`.
  3. `biab-browse open <url> click 'a#next'` → `exit 0`, navega.
  4. `biab-browse open <url> screenshot /tmp/shot.png` → fichero PNG creado (`file /tmp/shot.png` = PNG), `exit 0`.
- *criterio:* los 4 verbos `exit 0`; el screenshot es un PNG válido; salidas deterministas (texto/JSON/ruta) — no volcados de stack. El screenshot debe escribirse a una ruta legible por `OP` (el proceso corre como `biab-browser`; verificar permiso de lectura del artefacto de salida — ver hueco §4.12.4).

**AC-B5 — La skill `browser` está instalada y expone el modelo de amenaza.** (Task 4)
- *test:*
  ```bash
  test -L "$HOME/.claude/skills/browser" && \
  grep -qiE 'prompt.?inject|threat model|no access to (credentials|secrets)' \
    "$HOME/.agents/skills/browser/SKILL.md" && echo skillok
  ```
- *criterio:* symlink presente apuntando a `~/.agents/skills/browser` (fuente de verdad, réplica de `install_skill` de `40-scaffold.sh`); el `SKILL.md` contiene una sección de modelo de amenaza (prompt-injection desde la web visitada) y strings en inglés (`grep -P '[áéíóúñ¿¡]' SKILL.md` → vacío, salvo nombres propios).

**AC-B6 [sesión] — El agente usa el pack de punta a punta.** (EARS-1 · Tasks 4)
En `claude`/`agy` sobre `PACKED`: pedir "lee el titular de example.com". El agente descubre la skill `browser`, invoca `biab-browse`, y devuelve el texto.
- *criterio:* el agente ejecuta el CLI (no lo alucina) y responde con contenido real de la página. Verificación manual obligatoria en el PR (no automatizable barato).

---

### 4.3 Edge — fallback headful bajo Xvfb

**AC-E1 — Web que bloquea headless → `--headful-xvfb` la recupera.** (EARS-4 · Task 5)
Ante un sitio que rechaza el UA headless, el flag reintenta headful bajo Xvfb (framebuffer, NO escritorio).
- *test:*
  ```bash
  biab-browse --headful-xvfb open https://example.com read_text >/dev/null && echo xvfbok
  dpkg -l | grep -q '^ii.*xvfb' && echo xvfbpkg   # xvfb presente SOLO tras usar el flag
  ```
- *criterio:* la tarea corre en headful (UA `X11; Linux x86_64`, comprobable con un endpoint eco de UA) sin ningún entorno gráfico instalado; `xvfb` aparece en `dpkg` solo tras el primer uso del flag (instalación perezosa de §2.6 Task 5); Xvfb se arranca y se **para** al terminar (`pgrep Xvfb` → vacío tras la tarea; sin fuga de proceso). Mapea al `<verify>` de Task 5.
- *nota QA:* el spike §2.1 NO probó anti-bot real (Cloudflare/CAPTCHA); este AC verifica el **mecanismo** del fallback, no que derrote un anti-bot concreto. La derrota de anti-bot está fuera de alcance (§2.3 NO incluye) — documentar como límite conocido, no como fallo.

---

### 4.4 Edge — concurrencia, red, URL inválida (degradación limpia)

**AC-E2 — URL mala / DNS fallido / timeout degradan con error claro, no cuelgan.** (Task 2/4)
- *test:*
  ```bash
  biab-browse open https://no-such-host.invalid read_text; echo "rc=$?"   # rc != 0, mensaje claro
  biab-browse open not-a-url read_text; echo "rc=$?"                       # rc != 0, valida el arg
  ```
- *criterio:* exit code ≠ 0 con un mensaje legible en stderr (no un stack trace de Node crudo); el proceso navegador **no queda huérfano** (`pgrep -u biab-browser chrome` → vacío tras el fallo — el `trap` de limpieza corre igual en error); hay un timeout acotado por defecto (no cuelga indefinido). El `--user-data-dir` efímero se borra también en el camino de error.

**AC-E3 — Presión de concurrencia en 4 GB.** (§2.0/§2.1 · Task 2)
Lanzar N tareas `biab-browse` en paralelo y observar el techo del spike (~700 MB/run → ~2-3 en 4 GB).
- *test:* lanzar 3 y luego 6 invocaciones concurrentes de `open …read_text`, muestrear RSS (`ps -o rss= -u biab-browser | awk '{s+=$1} END{print s/1024" MB"}'`).
- *criterio:* con 2-3 concurrentes la caja no entra en OOM/swap severo; con 6 se degrada de forma tolerable (tareas encoladas/fallando con error claro, **no** OOM-killer matando procesos del `OP` ni la sesión del agente). Documentar el número seguro observado. Hueco: si el pack NO limita concurrencia, anotarlo (§4.12.3) — el spike sugiere que hace falta un semáforo, pero §2.6 no le da tarea. **Testability**: medir en la clase de hardware objetivo (mini PC), no en el server de dev.

---

### 4.5 Seguridad — usuario dedicado aislado (el crux del FEAT)

**AC-S1 — `biab-browser` NO tiene sudo ni pertenece a grupos privilegiados.** (EARS-2 · Task 3)
- *test:*
  ```bash
  id biab-browser | grep -qv '\bsudo\b' && echo "no sudo group"
  sudo -u biab-browser sudo -n true 2>&1 | grep -qi 'not\|require\|password' && echo "no sudo rights"
  getent passwd biab-browser | cut -d: -f7 | grep -q 'nologin' && echo "nologin shell"
  ```
- *criterio:* `biab-browser` no está en `-G sudo`, no puede `sudo`, y su shell es `/usr/sbin/nologin`. Cubre Boundary "Never: `-G sudo`".

**AC-S2 — `biab-browser` NO puede leer las claves SSH ni los ficheros del proyecto del operador.** (EARS-2 · Task 3)
- *test:*
  ```bash
  sudo -u biab-browser cat /home/*/.ssh/id_ed25519 2>&1 | grep -qi 'permission denied\|no such' && echo "ssh blocked"
  sudo -u biab-browser bash -c 'ls ~OP/ai-platform 2>&1' | grep -qi 'permission denied\|no such' && echo "project blocked"
  ```
  (sustituir `~OP` por el home real del operador).
- *criterio:* lectura de `~OP/.ssh/*` y de los ficheros de proyecto → **denegada** (no por ausencia accidental, sino por permisos: el home del operador es `0750`/`0700` y `biab-browser` no está en su grupo). Mapea al `<verify>` de Task 3. Este es el gate duro de EARS-2.

**AC-S3 — El proceso del navegador corre como `biab-browser`, nunca como root ni como el operador.** (EARS-2 · Task 3)
- *test:* durante un `biab-browse open …` en curso: `ps -o user=,comm= -C chrome_crashpad_handler` (o el proceso del headless-shell) → usuario `biab-browser`.
- *criterio:* ni `root` ni `OP` aparecen como dueños del proceso del motor. Cubre Boundary "Never: correr el motor como root o como el usuario operador".

---

### 4.6 Seguridad — sandbox de Chromium ACTIVO

**AC-S4 — El path por defecto NUNCA pasa `--no-sandbox`.** (Boundary "Always" · Task 3)
Cierra el límite del spike §2.1 (que corrió como root con `--no-sandbox`).
- *test (estático):*
  ```bash
  grep -RIn -- '--no-sandbox' payload/pack/browser/ && echo "FAIL: no-sandbox present" || echo "PASS: no no-sandbox"
  ```
  Si aparece, debe estar **exclusivamente** bajo un flag opt-in explícito y comentado (nunca en el flujo por defecto de `biab-browse`), y el test se ajusta para verificar que el default no lo alcanza.
- *test (runtime):* lanzar una tarea y comprobar en `chrome://sandbox` (vía el propio driver) o en los flags de arranque logueados que el sandbox está `enabled`/`yes`.
- *criterio:* `grep` de `--no-sandbox` en el árbol del pack → vacío (o acotado y probado como inalcanzable por defecto); el navegador arranca con sandbox activo como **no-root**. Este AC es el diferenciador de seguridad del FEAT.

**AC-S5 — El sandbox no-root funciona pese al AppArmor de Ubuntu 24.04.** (§2.2 gotcha · Task 3)
La caja objetivo trae `kernel.apparmor_restrict_unprivileged_userns=1`, que rompe el sandbox no-root salvo config extra (chrome-sandbox setuid del bundle Playwright **o** perfil AppArmor acotado SOLO al binario del navegador).
- *test:*
  ```bash
  sysctl kernel.apparmor_restrict_unprivileged_userns   # confirmar =1 en la caja de test (no relajado global)
  DISPLAY= biab-browse open https://example.com read_text >/dev/null && echo "sandbox+launch ok"
  ```
- *criterio:* el navegador arranca **con** el sysctl en `1` (el pack NO lo pone a `0` globalmente — eso violaría Boundary "Ask First: abrir userns vía AppArmor global"); si el pack instala un perfil AppArmor, `aa-status` lo muestra acotado al binario del navegador, no global. **Hueco de testabilidad crítico** (§4.12.1): cómo probar de forma barata que el sandbox está *realmente* activo y no silenciosamente caído a `--no-sandbox` — ver §4.12.

---

### 4.7 Seguridad — perfil efímero sin sesiones ambientales

**AC-S6 — Por defecto, perfil efímero: sin cookies/sesiones heredadas.** (EARS-3 · Task 3)
- *pasos:*
  1. `biab-browse open https://httpbin.org/cookies/set/foo/bar read_text` (setea una cookie).
  2. `biab-browse open https://httpbin.org/cookies read_text` (segunda invocación) → **no** contiene `foo=bar`.
- *criterio:* la cookie NO persiste entre invocaciones (cada run usa un `--user-data-dir` de `mktemp -d` distinto). Verificar además que ese dir temporal se **borra** al salir: capturar la ruta usada (log/debug) y `test ! -d <dir>` tras la tarea. Cubre EARS-3 y Boundary "Unwanted".

**AC-S7 — El perfil efímero no ve credenciales del `OP`.** (EARS-3 · Task 3)
El `--user-data-dir` vive bajo el home de `biab-browser` (o `/tmp` con dueño `biab-browser`), NO bajo `~OP`. No hay ruta por la que herede cookies del navegador personal del operador (que ni existe en la caja headless).
- *criterio:* el `user-data-dir` no está bajo `~OP`; no se monta ni symlinka ningún perfil del operador. Ausencia de "ambient login" por construcción.

**AC-S8 — Persistir un perfil logueado es opt-in explícito, NUNCA el default.** (Boundary "Ask First"/"Never" · §2.3)
- *criterio:* NO existe forma de invocar `biab-browse` sin flag/argumento explícito que reutilice un perfil nombrado persistente. Si §2.3 implementa el "perfil nombrado" mínimo, requiere un flag consciente (p.ej. `--profile <name>`); sin él, siempre efímero. Test: `biab-browse open …` dos veces sin flags → cero estado compartido (ya cubierto por AC-S6); con el flag → estado compartido SOLO entre runs que lo pasen. Si el mecanismo de perfil nombrado NO se implementa en v1 (§2.3 lo deja opcional), este AC se reduce a "no hay persistencia por ninguna vía".

---

### 4.8 Footprint (dentro de las cifras del spike)

**AC-FP1 — Disco del motor ≈ headless-shell, no el chromium completo.** (§2.0 · Task 2)
- *test:* `du -sh /var/lib/biab-browser/.cache/ms-playwright` (o `PLAYWRIGHT_BROWSERS_PATH` real).
- *criterio:* caché ≈ **250-300 MB** (headless-shell del spike: ~262 MB), **NO** ~646 MB (chromium full). Si supera 400 MB, es señal de que se instaló el chromium completo — FAIL (viola §2.3/§2.5).

**AC-FP2 — RAM por run dentro del techo del spike.** (§2.0/§2.1 · Task 2)
- *test:* muestrear RSS del árbol de procesos `biab-browser` durante un `open …read_text` (`ps -o rss= --ppid <pid>` sumado, o `/usr/bin/time -v`).
- *criterio:* pico ≲ **~700 MB/run** (spike: ~688 MB, ±10-15%). Reportar el número medido en la clase de hardware objetivo. Es el input de la regla de concurrencia (AC-E3).

---

### 4.9 Regresión — OPT-IN REAL (el gate más crítico)

**AC-R1 — Un install por defecto NO trae NADA del pack.** (Boundary "Always: opt-in" · Task 6) — **CRÍTICO.**
Sobre `FRESH` (install por defecto, sin `biab pack add browser`):
- *test:*
  ```bash
  getent passwd biab-browser && echo "FAIL: user exists" || echo "PASS: no user"
  command -v biab-browse && echo "FAIL: cli in PATH" || echo "PASS: no cli"
  test -e "$HOME/.claude/skills/browser" && echo "FAIL: skill installed" || echo "PASS: no skill"
  find / -path '*/ms-playwright/*' -name 'chrome*' 2>/dev/null | grep -q . && echo "FAIL: playwright present" || echo "PASS: no playwright"
  ```
- *criterio:* los cuatro → PASS. **Ni usuario, ni CLI, ni skill, ni Playwright** en una caja que no pidió el pack. Este es el corazón del FEAT (Boundary "Never: hacer del navegador el default").

**AC-R2 — El barrido del manifest de `40-scaffold.sh` NO instala la skill `browser`.** (§2.2 · Task 6) — **CRÍTICO.**
La skill vive en `payload/pack/browser/skill/`, NO en `payload/skills/`, precisamente para que `install_skill()` guiado por `payload/skills/manifest.tsv` no la barra.
- *test:*
  ```bash
  grep -q 'browser' payload/skills/manifest.tsv && echo "FAIL: browser in core manifest" || echo "PASS: not in manifest"
  test ! -e payload/skills/browser && echo "PASS: skill not in core skills dir"
  ```
- *criterio:* `browser` ausente de `manifest.tsv` y de `payload/skills/`; tras un scaffold `FRESH`, `~/.claude/skills/browser` NO existe (ya cubierto por AC-R1, aquí se ataca la causa raíz: la ubicación del fichero fuente).

**AC-R3 — El pack SHIPEA en el tarball (opt-in = presente en disco, ausente del sistema).** (§2.2 · Task 6)
- *test:* `git archive HEAD | tar -t | grep -q '^payload/pack/browser/' && echo ships`.
- *criterio:* `payload/pack/browser/**` aparece en `git archive` (NO está en `.gitattributes` export-ignore, igual que `payload/hooks/`). Verificar `.gitattributes` no lista `payload/pack`. Mapea a §2.8 y al `<verify>` de Task 6.

**AC-R4 — Añadir el pack NO rompe los subcomandos `biab` existentes.** (Task 1) — **regresión del wrapper.**
El nuevo `do_pack` + case `pack)` no puede tocar el resto del `case` de `05-biab-command.sh`.
- *test:* tras `biab pack add browser`, ejercitar los subcomandos previos: `biab status`, `biab logs`, `biab update` (dry/help), `biab add <group>` (el no-op amistoso), `biab help`.
- *criterio:* todos siguen respondiendo como antes; `biab help` ahora menciona `pack` pero no cambió el resto; `biab add` sigue siendo el no-op de skills (no se fusionó con `pack`). Diff de §2.4 confirma que `05-biab-command.sh` solo añade, no refactoriza.

**AC-R5 — El pack NO toca los hooks/SDD que fueron a core (v0.2), ni el Node global, ni el flujo del wizard.** (Boundary "Never" · §2.5)
- *test:* tras instalar el pack, verificar: (a) `~/.claude/settings.json` (hooks de FEAT-015) intacto (`jq -S '.hooks' | md5sum` igual antes/después); (b) las skills core (`sdd-*`) siguen symlinkeadas; (c) `node --version` global sin cambios (el pack usa `playwright-core` bajo el home del usuario dedicado, no toca el Node global salvo `npm` de bootstrap); (d) el wizard (`40-scaffold.sh`) no se ejecuta ni se modifica al añadir el pack.
- *criterio:* hooks, skills core, Node global y wizard sin regresión.

**AC-R6 — CI verde con el árbol nuevo.** (Task 1,6 · §2.8)
- *criterio:* `shellcheck -S warning` sobre `payload/pack/browser/*.sh`, `payload/pack/browser/bin/biab-browse` y `05-biab-command.sh` → limpio; `bash -n` sobre cada script → OK; guard de refs personales (`tools/`) y el check de archive-cleanliness (CI existente) siguen pasando con los ficheros nuevos.

---

### 4.10 Uninstall limpio

**AC-U1 — `biab pack remove browser` revierte todo.** (Task 6 · §2.2 uninstall)
- *test:*
  ```bash
  biab pack remove browser
  getent passwd biab-browser && echo FAIL || echo "user gone"
  command -v biab-browse && echo FAIL || echo "cli gone"
  test -e "$HOME/.claude/skills/browser" && echo FAIL || echo "skill gone"
  test -d /var/lib/biab-browser && echo FAIL || echo "home gone"
  ```
- *criterio:* usuario, home, caché, binario, skill (+symlink) y perfiles borrados; idempotente (segunda corrida `exit 0`, sin error). `biab pack list` → `browser⇥not installed`.

**AC-U2 — `do_uninstall` global invoca el teardown del pack best-effort.** (§2.2 · Task 6)
- *criterio:* `payload/install.sh do_uninstall` sobre una caja `PACKED` llama a `payload/pack/browser/uninstall.sh` si el pack está instalado, y no falla si NO lo está (guard de existencia + `pack_is_installed`). Sobre `FRESH`, `do_uninstall` no intenta borrar nada del pack.

---

### 4.11 Criterios de testing (resumen ejecutable)

- **Opt-in (gate crítico):** sobre `FRESH` → `getent passwd biab-browser` vacío + `command -v biab-browse` vacío + `~/.claude/skills/browser` ausente + sin Playwright (AC-R1); `grep browser payload/skills/manifest.tsv` vacío (AC-R2).
- **Shipea:** `git archive HEAD | tar -t | grep '^payload/pack/browser/'` no vacío (AC-R3).
- **Headless sin display:** `DISPLAY= biab-browse open https://example.com read_text` imprime texto, con `dpkg -l | grep -Ei 'xserver-xorg|ubuntu-desktop'` vacío (AC-B2).
- **Contrato del CLI:** matriz de los 5 verbos contra un HTML local servido con `python3 -m http.server`; screenshot = PNG válido (AC-B4).
- **Seguridad — usuario:** `id biab-browser` sin `sudo`; `sudo -u biab-browser cat ~OP/.ssh/id_*` → permission denied; `ps -o user= -C <motor>` = `biab-browser` (AC-S1/S2/S3).
- **Seguridad — sandbox:** `grep -RIn -- '--no-sandbox' payload/pack/browser/` **vacío** en el path por defecto (AC-S4); arranque OK con `kernel.apparmor_restrict_unprivileged_userns=1` (AC-S5).
- **Seguridad — perfil efímero:** set-cookie en run 1, ausente en run 2; `--user-data-dir` temporal borrado tras salir (AC-S6).
- **Footprint:** `du -sh …/ms-playwright` ≈ 250-300 MB (AC-FP1); RSS pico ≲ ~700 MB/run (AC-FP2).
- **Fallback:** `biab-browse --headful-xvfb …` OK; `xvfb` en `dpkg` solo tras usarlo; `pgrep Xvfb` vacío tras la tarea (AC-E1).
- **Uninstall:** `biab pack remove browser` → `getent passwd biab-browser` vacío, sin CLI ni skill (AC-U1).
- **Regresión wrapper:** `biab status/logs/update/add/help` OK tras instalar el pack (AC-R4); hooks `settings.json` intactos (AC-R5).
- **CI:** `shellcheck -S warning` + `bash -n` sobre el pack y `05-biab-command.sh`; guards de refs/archive verdes (AC-R6).

---

### 4.12 Huecos de testabilidad detectados en §2 (para Laura/Elena)

1. **Sandbox no-root "realmente activo" es difícil de probar de forma barata (AC-S5) — el hueco #1 del FEAT.** §2.1 admite que el path sandbox no-root NO se validó (el spike corrió como root con `--no-sandbox`). El riesgo real es una implementación que *falle abierto*: si el `chrome-sandbox` setuid o el perfil AppArmor no aplican, es fácil que el driver caiga silenciosamente a `--no-sandbox` "para que funcione" y el navegador siga navegando — pasando AC-B2/B3 mientras viola el modelo de seguridad. `grep` estático (AC-S4) atrapa el `--no-sandbox` literal, pero NO atrapa un fallo runtime del sandbox. **Recomendación QA:** el driver debe (a) tener un modo que **falle cerrado** si el sandbox no arranca (abortar, no degradar a `--no-sandbox`), y (b) exponer el estado del sandbox de forma verificable (leer `chrome://sandbox`, o parsear el arranque del navegador, o un test que confirme que un proceso hijo del render NO puede hacer `clone(CLONE_NEWUSER)` fuera del namespace). Sin (b), AC-S5 no es automatizable con confianza — pedir a Laura que dé al driver una tarea `<verify>` explícita de "sandbox status = enabled" y que el default aborte si no.

2. **`kernel.apparmor_restrict_unprivileged_userns=1` puede requerir escritura de sistema que el pack no debería hacer global.** La resolución (perfil AppArmor acotado al binario) toca `/etc/apparmor.d/` — territorio de root y de "danger zone" (security config). Hueco: §2.6 Task 3 le da un `<verify>` pero no fija CUÁL de las dos vías (setuid vs AppArmor) se elige, y las dos tienen perfiles de test distintos. **Recomendación:** que Laura fije la vía ANTES de implementar; la vía AppArmor necesita además un test de que el perfil NO es global (AC-S5) — Boundary "Ask First" lo exige y hoy no hay caso que lo blinde salvo mi AC-S5, que es parcial. Si se elige AppArmor, esto probablemente merece OK explícito de Jesús (danger zone / security config per CLAUDE.md).

3. **No hay límite de concurrencia en §2.6 pese a que §2.0 dice que hace falta (~2-3 en 4 GB).** AC-E3 prueba el comportamiento bajo presión, pero ninguna tarea de §2 implementa un semáforo/cola. Sin él, N invocaciones paralelas del agente pueden disparar el OOM-killer y matar procesos del operador o la propia sesión del agente — peor que fallar la tarea de navegador. **Recomendación:** añadir a §2 una tarea (o ampliar Task 2/4) con un límite de concurrencia configurable (flock/semáforo) y un fallo claro al superarlo, y que AC-E3 pase a ser gate, no solo observación. Decisión de Elena: ¿scope v1 o límite documentado + v0.2?

4. **El artefacto de `screenshot` cruza la frontera de usuarios (AC-B4).** El motor corre como `biab-browser` pero el agente (que corre como `OP`) necesita leer el PNG. Si el screenshot se escribe con dueño `biab-browser` y permisos restrictivos, `OP` no lo lee → la feature "screenshot" es inútil de facto. §2 no especifica el contrato de propiedad/permиso del fichero de salida ni un dir de intercambio. **Recomendación:** definir un directorio de handoff con permisos acordados (p.ej. salida a una ruta pasada por `OP`, escrita `0644` o con `OP` como grupo), y un AC que verifique `sudo -u OP test -r <screenshot>`. Aplica también a cualquier output-a-fichero futuro.

5. **`example.com` / `news.ycombinator.com` / `httpbin.org` como fixtures acoplan los tests a la red externa.** Varios ACs (B2, B3, S6) dependen de sitios públicos vivos → tests frágiles/flaky en CI sin red o si el sitio cambia. **Recomendación:** para el contrato del CLI (AC-B4, S6) usar un HTML local servido por `python3 -m http.server` (cookies vía un endpoint local trivial) y reservar los sitios reales SOLO para el smoke E2E manual (AC-B3/B6). httpbin en particular es un servicio de terceros que ha tenido caídas — sustituir por un handler local para AC-S6.

6. **El opt-in depende de una convención de ubicación de fichero, no de un mecanismo forzado.** AC-R2 verifica que la skill está en `payload/pack/browser/skill/` y no en `payload/skills/`, pero nada IMPIDE que un futuro contribuidor mueva o copie la skill a `payload/skills/` y rompa el opt-in silenciosamente. **Recomendación:** un test de CI permanente (no one-off) que afirme la ausencia de `browser` en `payload/skills/` y en `manifest.tsv` — que AC-R1/R2 queden como regresión perpetua, igual que se hizo con AC-LOG1 en FEAT-015. Es la única garantía estructural del invariante central del FEAT.

## Notas

- Este FEAT NO se implementa hasta pasar el gate de 6 semanas + demanda real. Es la carta lista, no trabajo en curso.
- Relación: complementa el LAUNCH-PLAN (checkpoint de 6 semanas). Si se activa, revisar colisión con Hezu (regla del consejo: si compite con Hezu, Hezu gana).
