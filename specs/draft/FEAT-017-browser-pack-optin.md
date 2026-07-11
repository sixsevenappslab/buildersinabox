# FEAT-017: Browser pack (opt-in, headless) — el agente actúa en la web sin escritorio

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** CHECKPOINT-GATED — NO construir antes de que BIAB pase su gate de 6 semanas (≥500 stars O ≥50 installs + ≥100 email subs + ≥3 testimonios) **Y** haya señal real de que usuarios piden acciones de navegador. Hasta entonces, esta carta se queda en la recámara.
- **Complejidad:** media
- **E2E mode:** none (spike de feasibility ya hecho, ver §2.0)
- **Reconciliation owner:** sdd-coordinator
- **Fase:** requisitos (draft)
- **Creado:** 2026-07-11
- **Validado por Jesus:** [ ]  (deliberadamente sin validar — decisión del strategy-council: lanzar headless primero; esto es hipótesis de checkpoint, no trabajo pre-launch)

## Origen (por qué existe este draft)

Jesús propuso (2026-07-11) migrar BIAB a Ubuntu Desktop para usar el MCP de Chrome de Claude y que el agente actúe en la web por el usuario. El strategy-council (5 voces) fue unánime: **lanzar la versión headless YA, no pivotar** — el navegador logueado + agente autónomo autodestruye el diferenciador de seguridad, rompe VPS/headless, compite con Operator/Cowork, y llega el día del último gate de código (patrón de "huir del grind de distribución"). PERO la idea en su forma FUERTE — **computer-use privado y self-hosted** (tu agente-navegador en TU caja, con TUS datos, lo contrario de Operator) — es genuinamente diferenciada y mira hacia donde va el mercado. Decisión de Jesús: lanzar headless + spike técnico timeboxed para tener esta carta lista. Este FEAT ES esa carta.

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

**Always:** opt-in (nunca en el bundle por defecto); headless por defecto; usuario dedicado con sandbox; perfil efímero sin logins ambientales por defecto; documentar el modelo de amenaza (prompt-injection en la web visitada).

**Ask First:** persistir un perfil logueado en un servicio; dar egress no revisado; cualquier cosa que toque credenciales del usuario.

**Never:** hacer del navegador el default (rompe seguridad/headless/VPS); requerir Ubuntu Desktop; heredar las sesiones logueadas del usuario por defecto; **construir esto antes del checkpoint de 6 semanas + señal de demanda**; competir de frente como "otro Operator" (el ángulo es privado/self-hosted).

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

## Notas

- Este FEAT NO se implementa hasta pasar el gate de 6 semanas + demanda real. Es la carta lista, no trabajo en curso.
- Relación: complementa el LAUNCH-PLAN (checkpoint de 6 semanas). Si se activa, revisar colisión con Hezu (regla del consejo: si compite con Hezu, Hezu gana).
