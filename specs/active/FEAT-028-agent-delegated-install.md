# FEAT-028: Install via an agent you already have (semi-delegado)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** media — no bloquea el flip, es un canal de distribución adicional
- **Complejidad:** baja — spec ligera
- **E2E mode:** una pasada real end-to-end contra una VM o VPS, dirigida por un agente
- **Depende de:** FEAT-027 (`check_ssh_install_preflight`, ya en main); reutiliza el
  patrón de pausa `exit 78` de `payload/wizard/run.sh` / `36-phone-bridge.sh`
- **Fase:** requisitos
- **Creado:** 2026-08-20
- **Actualizado:** 2026-08-20
- **Validado por Jesus:** [ ] <!-- decisión de alcance tomada el 2026-08-20 vía strategy-council modo ligero -->

## Contexto y por qué ahora

Idea de Jesús: la audiencia de BIAB (gente que ya vive en Claude Code / Codex) podría
pedirle a su propio agente remoto "instálame BIAB en esta máquina nueva" en vez de
copiar el `curl | sudo bash` a mano. Nota honesta sobre el origen de esta spec: no
viene de una petición de un usuario real (Paco no la ha pedido) — es una hipótesis de
Jesús. El consejo (modo ligero, Esencialista + Distribución) recomendó aparcarla hasta
tener demanda confirmada; Jesús decidió priorizarla igualmente. Por eso el timebox es
corto y el alcance deliberadamente recortado — si en la implementación aparece fricción
extra, se para y se documenta, no se sigue empujando.

Investigación previa (verificado contra `main` 2026-08-20) — **tres puntos, no uno**,
exigen hoy un humano con navegador:

1. **Tailscale** (`payload/wizard/10-tailscale-up.sh`) — device-flow OAuth puro, sin
   soporte de auth-key headless en ningún sitio del repo (`grep -rn authkey` → nada).
2. **Login del AI CLI** (`payload/wizard/38-ai-cli-login.sh`) — Claude Code y Codex
   también son device-flow OAuth (URL + código aprobado desde el móvil). Irónico: para
   que un agente instale "un AI CLI nuevo", ese CLI nuevo necesita que un humano
   apruebe su propio login.
   **Hallazgo de implementación (2026-08-21):** este paso NO usa `oauth_step` — cada
   adaptador (`payload/lib/ai-cli.sh`) tiene su propio `_ai_cli_login_run__<cli>`.
   `claude`/`codex` ejecutan un subcomando headless que imprime URL+código y hace
   polling por su cuenta hasta completar o expirar — no hace falta tocar código, un
   agente solo necesita mantener la sesión SSH abierta y relayar la URL mientras el
   comando sigue corriendo. `antigravity` (agy) es distinto: su login es la propia
   TUI (`_ai_cli_login_run__antigravity`, comentario explícito "no remote-control
   equivalent") — necesita una terminal real, no funciona sin pty. Por tanto: la
   instalación delegada a un agente **no soporta `antigravity`** en esta FEAT.
3. **Password sudo** (`payload/wizard/01-set-password.sh`) — el menos problemático, ya
   tiene ruta de mock/skip.

Por decisión de Jesús (ver pregunta cerrada), esta FEAT NO intenta eliminar esos tres
puntos (eso sería "totalmente headless": auth-key de Tailscale + login del AI CLI por
API key, un timebox mucho mayor con decisiones de seguridad propias — rotación de
auth-keys, alcance del API key — que no se ha tomado). Esta FEAT construye la versión
**semi-delegada**: el agente orquesta el SSH, el curl, y el wizard no interactivo de
punta a punta, y solo se detiene a pasarle al humano los 2 links de login (Tailscale,
AI CLI) — igual que hoy hace un humano leyendo la consola, pero relayado por chat en
vez de leído en pantalla.

Hallazgo clave que abarata el alcance: la mecánica de pausa YA EXISTE. `run.sh` usa
`exit 78` como señal limpia de "pausa aquí, se retoma en otro contexto"
(`36-phone-bridge.sh` es el único caso hoy). Y `oauth_step` (`payload/lib/oauth.sh`),
cuando `/dev/tty` no es legible (sesión sin pty, que es exactamente cómo correría un
agente), ya degrada con gracia: `prompt_confirm` no cuelga — `_bib_read_line` cae a un
`read` sobre stdin cerrado, EOF inmediato, sigue adelante sin esperar. El problema no es
que cuelgue: es que hoy, tras eso, intenta `verify_cmd` de inmediato (el login aún no
se ha completado), falla, y `die()` con un mensaje genérico — indistinguible de un bug
real para un agente que esté parseando la salida.

## 1. Requisitos

- [x] R1 — WHEN `oauth_step` corre y `BIB_PROMPT_INPUT` (default `/dev/tty`) no es
      legible (sin pty — el caso de un agente driving por SSH sin `-t`), THE SYSTEM
      SHALL, tras capturar e imprimir la URL, saltarse el intento de verificación
      inmediata y salir con `exit 78` imprimiendo una línea greppable de una sola
      pieza (`BIB_AGENT_PAUSE: step=<label> url=<url>`), en vez del `die()`
      genérico actual. `run.sh` ya interpreta `78` como "pausa limpia, exit 0,
      retómalo relanzando el comando" — reutilizado tal cual.
      → `payload/lib/oauth.sh:oauth_step`. **Ajuste sobre el plan original:**
      no depende de `NON_INTERACTIVE` (nunca se exporta a los subprocesos del
      wizard — habría sido una condición muerta); depende de si `BIB_PROMPT_INPUT`
      se puede abrir de verdad, no de su legibilidad.
      **Bug encontrado en code-review y corregido (2026-08-21):** la primera
      versión usaba `[[ -r "$BIB_PROMPT_INPUT" ]]`, pero `/dev/tty` tiene bits
      de permiso "legible" incluso sin terminal de control — el fallo real es
      `ENXIO` al abrir, no un error de permisos. Con eso, la pausa nunca se
      disparaba en el caso real (SSH sin pty) y el proceso se quedaba colgado
      en el `wait "$cmd_pid"` posterior — peor que el `die()` que sustituía.
      Corregido con `_oauth_console_attached()`, que intenta un open real
      (`{ : < "$BIB_PROMPT_INPUT"; } 2>/dev/null`). Reproducido y verificado
      con un test bajo `setsid` (sesión sin terminal de control real).
- [x] R2 — WHEN el paso pausado se relanza, THE SYSTEM SHALL detectar que el
      login ya se completó y continuar sin repetir pasos anteriores.
      **Ajuste sobre el plan original:** esto no vive dentro de `oauth_step`
      (que ahora pausa incondicionalmente sin mirar `verify_cmd` cuando no hay
      consola — la responsabilidad de "¿ya está hecho?" es del *caller*). Para
      Tailscale ya lo hace `10-tailscale-up.sh` con su propio pre-check
      (`tailscale status` antes de llamar a `oauth_step`) — código preexistente,
      sin cambios. Documentado como contrato explícito en el comentario de
      cabecera de `oauth.sh` para que un futuro segundo caller no lo pase por alto.
- [x] R3 — WHEN un usuario con Claude Code/Codex remoto quiere delegar la
      instalación, THE SYSTEM SHALL documentar la receta exacta: dar al agente
      acceso SSH al target, el comando, qué significa cada pausa, y que el ack de
      SSH de FEAT-027 (`BIB_SSH_INSTALL_ACK=1`) hay que pasarlo también.
      → `README.md` sección "Install via an agent you already have".
      **Ajuste sobre el plan original, encontrado al leer `payload/wizard/
      38-ai-cli-login.sh`:** el login del AI CLI NO usa `oauth_step` — cada
      adaptador (`payload/lib/ai-cli.sh`) tiene su propio
      `_ai_cli_login_run__<cli>`. `claude`/`codex` corren un subcomando headless
      que imprime URL+código y hace polling por su cuenta (no necesita R1, ya
      funciona sin consola: la sesión SSH del agente simplemente se queda
      corriendo hasta que el humano aprueba). `antigravity` es una TUI sin
      variante headless — **no soportado** en la receta documentada.
- [ ] R4 — pasada real: un agente (esta sesión de Claude Code, o Jesús con Codex)
      dirige la instalación completa contra una VM o VPS de verdad, relayando los
      2 links de login, hasta ver `/tutorial` arrancar. Lo observado sustituye a
      cualquier suposición de este documento. **Pendiente — requiere target real,
      no ejecutable en dry-run.**

## 2. Spec técnica (esbozo — spec ligera)

| Fichero | Cambio |
|---|---|
| `payload/lib/oauth.sh` | En `oauth_step`: si `NON_INTERACTIVE=1` y `/dev/tty` no legible, tras capturar la URL, imprimir `BIB_AGENT_PAUSE: step=<label> url=<url>` y `exit 78` — saltarse `prompt_confirm` + el intento de `verify_cmd` que hoy termina en `die()` |
| `payload/wizard/run.sh` | Ninguno — `run_step` ya trata `78` como pausa limpia (`exit 0`, log "paused, will resume") |
| `payload/wizard/10-tailscale-up.sh`, `38-ai-cli-login.sh` | Ninguno — llaman a `oauth_step`, heredan el comportamiento nuevo sin tocarlos |
| `payload/test/oauth-agent-pause.sh` (nuevo) | Mock de `oauth_step` con `BIB_PROMPT_INPUT` apuntando a algo no legible + `NON_INTERACTIVE=1`: asserta `exit 78` y la línea `BIB_AGENT_PAUSE:` en stdout, sin colgarse ni hacer `die()` |
| `README.md` | Sección nueva "Install via an agent you already have" (R3): receta + qué son las pausas |

**Fuera de alcance (Never):** auth-key headless de Tailscale; login por API key para
el AI CLI en vez de OAuth; cualquier orquestación automática del *relay* humano→agente
(quién copia el link a quién sigue siendo manual, por chat); soportar el caso de la
Fase B corriendo sobre una conexión distinta a la que abrió Fase A (el agente
reconectando por tailnet) — se documenta como paso manual en R3, no se automatiza.

**Timebox:** 1-2 días incluida la pasada real (R4). Si la pasada real descubre que la
reconexión Fase A → Fase B (LAN/VPS → tailnet) es más fricción de la documentable en
una frase, se para ahí y se anota como hallazgo — no se convierte en trabajo nuevo sin
pasar otra vez por decisión de Jesús.

## 3. Boundaries

- **Always:** el `exit 78` nuevo sigue el mismo contrato que ya usa
  `36-phone-bridge.sh` — no inventar semántica de exit code nueva.
- **Ask first:** cualquier cambio en `payload/wizard/10-tailscale-up.sh` o
  `38-ai-cli-login.sh` más allá de heredar el comportamiento de `oauth_step` sin
  tocarlos directamente.
- **Never:** tocar `payload/wizard/35-ssh-finalize.sh` o el preflight de FEAT-027;
  construir auth-key/API-key headless (eso es la opción "totalmente headless" que
  Jesús explícitamente no eligió); prometer en el README que la instalación es
  "cero clics" — sigue exigiendo 2 clics humanos, y hay que decirlo así de claro.

## 4. QA (mínimo)

1. [x] `oauth_step` con `BIB_PROMPT_INPUT` apuntando a una ruta no legible, URL
   capturada del `url-cmd` → `exit 78`, línea `BIB_AGENT_PAUSE: step=... url=...`
   presente, ni cuelgue ni `die()`.
   → `payload/test/oauth-agent-pause.sh` escenario 1.
2. [x] Edge case: mismo caso pero el `url-cmd` no imprime ninguna URL → sigue
   pausando limpio (`url=none`), no crashea.
   → escenario 2.
3. [x] Regresión: `BIB_PROMPT_INPUT` legible (consola real) + verify OK → completa
   normal, sin línea de pausa. Y con verify KO → `die()` de siempre, no `exit 78`.
   → escenarios 3 y 4.
4. [x] Regresión: `ssh-install-preflight.sh` (6/6), `ssh-finalize-decision.sh`
   (53/53), `uninstall-contract.sh` (89/89), `wiring-smoke.sh` × 3 CLIs — todos en
   verde. `shellcheck -S warning` y `tools/check-no-personal-refs.sh` limpios.
5. [x] Caso real (no simulado): sesión sin terminal de control (`setsid`, sin
   override de `BIB_PROMPT_INPUT`) → `exit 78`. Regresión encontrada por
   code-review: el check original (`-r`) no cubría este caso — ver Decisiones.
   → escenario 5.
6. [ ] Pasada viva (R4): agente real dirigiendo la instalación contra VM/VPS,
   relay manual de 2 links, hasta `/tutorial`. **Pendiente, requiere target real.**

## 5. Docs

README (R3, nueva sección). Sin cambios en `site/index.html` — audiencia técnica,
no la landing de lanzamiento. Sin cambios en `LAUNCH-PLAN.md` — esto no es parte del
titular del flip.

## 6. Implementación

### Branch

`feat/028-agent-delegated-install`

### Progreso

| Task | Estado | Notas |
|------|--------|-------|
| R1 — pausa agent-friendly en `oauth_step` | hecho | `payload/lib/oauth.sh` |
| R2 — resume sin repetir pasos | hecho (sin código nuevo) | pre-check existente en `10-tailscale-up.sh` |
| R3 — receta documentada | hecho | `README.md` §"Install via an agent you already have" |
| Test `oauth-agent-pause.sh` | hecho | 5 escenarios (incl. repro `setsid` del bug de review), wireado en CI |
| R4 — pasada real | pendiente | requiere VM/VPS real, fuera de este entorno |

### Decisiones tomadas

- [2026-08-21] Se descartó `NON_INTERACTIVE` como condición de disparo (nunca se
  exporta del `install.sh` a los subprocesos del wizard) en favor de la
  legibilidad de `BIB_PROMPT_INPUT`, que es el mecanismo real que ya usa
  `prompt.sh` para detectar ausencia de consola.
- [2026-08-21] `antigravity` queda fuera de la receta de instalación delegada: su
  login es una TUI sin variante headless (`_ai_cli_login_run__antigravity`,
  comentario explícito en el código: "no remote-control equivalent"). La receta
  del README solo recomienda `claude`/`codex`.
- [2026-08-21] No se tocó `payload/wizard/38-ai-cli-login.sh` ni los adaptadores de
  `lib/ai-cli.sh`: `claude`/`codex` ya bloquean-y-hacen-polling por su cuenta sin
  consola, así que no necesitan el mecanismo de pausa `exit 78` — solo se
  documentó el comportamiento existente en R3.

### Blockers

Ninguno. R4 depende de que Jesús (o un agente con acceso) dirija una instalación
real contra una VM o VPS — no ejecutable desde este entorno.

### Verificación post-implementación

- [x] `payload/test/oauth-agent-pause.sh`: 4/4 en verde.
- [x] Regresión: `ssh-install-preflight.sh`, `ssh-finalize-decision.sh`,
  `uninstall-contract.sh`, `wiring-smoke.sh` (claude/antigravity/codex).
- [x] `shellcheck -S warning` en todos los ficheros bash tocados/nuevos.
- [x] `bash tools/check-no-personal-refs.sh` limpio.
- [x] Sin secrets en el diff, sin cambios fuera de alcance.
- [ ] CI de GitHub — pendiente de abrir el PR.
