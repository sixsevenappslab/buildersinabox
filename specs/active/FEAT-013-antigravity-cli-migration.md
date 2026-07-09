# FEAT-013: Migración del segundo CLI: Gemini CLI → Antigravity CLI (`agy`)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (bloquea el flip a público — decisión de Jesus 2026-07-09)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts de dispositivo (bash). La verificación automatizada es el dryrun harness; la validación real exige una pasada E2E en box headless física/VM (ver §4).
- **Reconciliation owner:** sdd-coordinator
- **Fase:** implementacion
- **Creado:** 2026-07-09
- **Actualizado:** 2026-07-09
- **Validado por Jesus:** [x] (2026-07-09)

> Complejidad determina el modelo de implementacion: alta=Opus, media/baja=Sonnet.

---

## Definition of Ready (DoR)

### Producto (§1) — owner Elena
- [x] Problema explicito (no solucionismo: el "por que", no solo el "que")
- [x] **Intent (why) rellenado** — motivación estratégica/usuario separada del problema
- [x] Minimo 1 historia de usuario verificable
- [x] Minimo 3 requisitos funcionales con checkbox
- [x] **Requisitos funcionales en sintaxis EARS** (o marcados `[free-form]` con justificación inline)
- [x] Boundaries §3 con al menos 1 item en cada bloque (Always / Ask First / Never)

### Spec Tecnica (§2) — owner Laura
- [x] Investigacion previa rellenada con rutas reales verificadas (`ls`)
- [x] Tabla "Archivos afectados" completa con accion (CREAR/MODIFICAR/ELIMINAR)
- [x] Minimo 1 `<task>` con `<verify>` ejecutable y `<done>` observable (no "funciona bien")
- [x] Patron de codigo con fragmento real del proyecto (10-20 lineas)
- [x] Criterios de aceptacion globales verificables (no genericos)

### QA (§4) — owner Pablo
- [x] Minimo 1 caso funcional en la tabla con pasos numerados y resultado verificable
- [x] Minimo 1 edge case (input vacio/invalido/limite)
- [x] Minimo 1 item de regresion (feature existente que NO debe romperse)
- [x] Bloque `Criterios de testing` con comandos ejecutables (no pseudocodigo)

### Growth (§1.Growth Notes) — owner Andrea (solo si aplica)
- [x] Canal + metrica + target, o marcado N/A explicito

---

## 1. Requisitos (Elena)

### Problema

La opción "gemini" del wizard instala `@google/gemini-cli`, un CLI que Google dejó de servir a consumidores (free tier + AI Pro/Ultra) el 2026-06-18 — su sustituto oficial es Antigravity CLI (`agy`). Además, la ruta Gemini nunca se probó E2E y está rota en puntos críticos: el finale del wizard manda a TODOS los usuarios a instalar la app de Claude Code (dead end para quien no eligió Claude), el flujo de auth es contradictorio en el código y nunca se validó en box headless, y el README + la landing prometen públicamente "a Google account for Gemini CLI" — una promesa falsa desde el 18 de junio.

### Intent (why)

Jesus decidió (2026-07-09, tras consejo de estrategia) que BIAB no lanza públicamente con una segunda opción de CLI muerta o rota: la promesa multi-CLI es parte del posicionamiento del producto y el hook del launch es "los demás lo hacen mal; esto está bien hecho". Lanzar con una ruta que cuelga el wizard o acaba en un dead end destruiría exactamente esa credibilidad en el thread de HN. Coste aceptado conscientemente: 2-4 semanas de retraso del launch. Restricción upstream conocida: `agy` NO acepta Gemini API key (issue google-antigravity/antigravity-cli#78, sin planes) — el auth real es OAuth de cuenta Google (`agy auth login`) o proyecto GCP; la suposición inicial "el usuario mete su API key" queda descartada.

### Solucion propuesta

El wizard ofrece `claude` o `antigravity`. Quien elige Antigravity obtiene: instalación del binario `agy` (versión pineada), login OAuth guiado que funciona en box headless (URL copiable desde el móvil), sesión tmux `ai-platform` arrancando `agy` con `/tutorial`, y un finale + README de escritorio específicos (historia de móvil = SSH/Termius + tmux attach, con ccgram documentado como opción avanzada — NO un bridge propio). README y landing dejan de mencionar Gemini CLI y pasan a describir la opción Antigravity con honestidad. CI ejercita ambas rutas.

### Historias de usuario

- Como builder sin suscripción de pago a Claude, quiero elegir Antigravity CLI en el wizard y autenticarme con mi cuenta de Google, para tener mi dev server con IA sin coste de suscripción adicional.
- Como usuario que eligió Antigravity, quiero que la pantalla final y el README de mi box me expliquen cómo conectar desde el móvil con SSH/Termius (y no que me manden a instalar la app de Claude Code), para no quedarme tirado en el último paso del setup.
- Como mantenedor del repo, quiero que el dryrun de CI ejercite la ruta `BIB_AI_CLI=antigravity`, para que un cambio futuro no rompa silenciosamente la ruta no-Claude (como pasó con Gemini).

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** El wizard shall ofrecer exactamente dos opciones de AI CLI: `claude` y `antigravity` (la opción `gemini` desaparece).
- [ ] **Event-driven:** Cuando el usuario selecciona `antigravity`, el installer shall instalar el binario `agy` desde la fuente oficial de Google con versión pineada.
- [ ] **Event-driven:** Cuando el wizard llega al paso de login con `ai_cli=antigravity`, el sistema shall guiar el OAuth de `agy` mostrando una URL/código copiable desde el móvil, sin depender de un navegador local.
- [ ] **State-driven:** Mientras `ai_cli=antigravity`, el finale de `run.sh` y el `desktop-readme.md` shall mostrar instrucciones específicas de Antigravity (SSH/Termius + `tmux attach`; cero menciones a la app de Claude Code).
- [ ] **Unwanted:** Si el login de `agy` no puede completarse en entorno headless (p. ej. intenta abrir un navegador local), el wizard shall fallar con mensaje claro e instrucciones de recuperación, nunca colgarse esperando input imposible.
- [ ] **Event-driven:** Cuando la sesión tmux arranca con `ai_cli=antigravity`, `agy` shall cargar las skills de `~/.agents/skills/` y ejecutar `/tutorial` como prompt inicial.
- [ ] **Ubicuo:** El README público y la landing (`site/`) shall describir la opción Antigravity y no mencionar Gemini CLI como opción soportada.
- [ ] **Ubicuo:** El dryrun de CI shall ejercitar la ruta `BIB_AI_CLI=antigravity` además de la de `claude`.

### Requisitos no funcionales

- [ ] Idempotencia: los pasos de install/wizard pueden re-ejecutarse sin romper (patrón existente del repo).
- [ ] Strings de cara al usuario en inglés (convención del repo).
- [ ] Sin nuevos puertos públicos ni servicios expuestos — se mantiene el modelo Tailscale-only (posicionamiento seguridad-primero del launch).
- [ ] La abstracción `payload/lib/ai-cli.sh` sigue siendo la única fuente de verdad del CLI elegido; el dead code actual (`ai_cli_binary`/`ai_cli_headless_flag`/`ai_cli_login_cmd`) se elimina o se corrige y se usa de verdad — no queda código contradictorio.

### Referencias visuales

- **Wireframes:** N/A (producto de consola; el "UI" son las pantallas del wizard y los README)
- **Flujo de usuario:** elegir CLI → install → OAuth desde el móvil → tmux con /tutorial → finale con phone story del CLI elegido
- **Diseño UI:** mantener el tono épico-pero-aterrizado de las pantallas existentes del wizard
- **Referencia visual:** pantallas actuales de `payload/wizard/run.sh`

### Growth Notes (Andrea — si aplica)

- **Canal:** Content/Social (Show HN + r/selfhosted + LinkedIn, según LAUNCH-PLAN §4). Sin canal nuevo: este FEAT corrige copy dentro del launch ya planificado.
- **Jerarquía del mensaje:** el hook sigue siendo seguridad (42.665 instancias expuestas / 93,4% auth bypass) — NO se diluye. "Claude o Antigravity" es selling point **secundario**: en la landing va en la línea de requisitos ("a Claude subscription or a Google account for Antigravity CLI", estilo B2); en el Show HN, una frase en el cuerpo ("works with Claude Code or Google's Antigravity CLI — no vendor lock-in"), nunca en el título.
- **Ángulo "Gemini CLI murió":** utilizable, pero como **comentario preparado** para el thread de HN y mención en r/selfhosted (LAUNCH-PLAN ya contempla "refugiados Gemini CLI"), no como post propio. Frase tipo: "Google killed Gemini CLI for consumers on June 18; we migrated to its successor Antigravity and CI tests both paths". Refuerza el hook ("los demás lo hacen mal") sin competir con él. Caduca rápido: solo vale para el launch, no evergreen.
- **Métrica + target:** BIAB no tiene telemetría y NO se añade (contradiría el posicionamiento privacy/security-first — boundary implícito). Aproximación honesta: contar menciones de antigravity en issues/Discussions/testimonios post-launch. **Target: ≥15% de los reportes de instalación completada (gate §3 del LAUNCH-PLAN: ≥50 installs) mencionan la ruta antigravity a las 6 semanas.** Si es ~0%, la promesa multi-CLI no justifica su coste de mantenimiento — dato para el checkpoint de sep.
- **Riesgo de mensaje (spike T1):** no publicar NADA que prometa Antigravity (landing, README público servido, drafts de HN/LinkedIn) hasta que T1 sea GO — ya gated en §3 Ask First; esta nota lo extiende a los drafts del launch. Si T1 acaba en NO-GO, el copy del launch pasa a Claude-only honesto ("Claude Code today; second CLI when we can support it properly") — mejor que prometer y retractarse en el thread.

---

## 2. Spec Tecnica (Laura)

### Investigacion previa

**Estado del codigo (rutas verificadas con `ls`/`cat` el 2026-07-09):**

- `payload/lib/ai-cli.sh` — abstraccion del CLI. `BIB_SUPPORTED_AI_CLIS=("claude" "gemini")` (linea 9). Las funciones `ai_cli_binary` (l.61), `ai_cli_headless_flag` (l.69) y `ai_cli_login_cmd` (l.76) son **dead code** (cero call sites en el repo) y `ai_cli_login_cmd` es ademas incorrecta (`gemini auth login` no existe; el propio `38-ai-cli-login.sh` lo contradice). La unica funcion de mapeo usada es `ai_cli_install_script` (llamada desde `payload/install.sh:387`).
- `payload/install.sh` — flag `--ai-cli=<claude|gemini>` (l.50, l.79-80), validacion non-interactive (l.112), prompt interactivo con copy "Both have OAuth logins that work from your phone" (l.340-352), despacho del install script (l.387).
- `payload/wizard/05-choose-cli.sh` — chooser fallback; promete "Both choices have OAuth device flows that work from your phone" (l.24-29).
- `payload/install/41-gemini-cli.sh` — `npm install -g @google/gemini-cli` **sin pin de version** (l.13, l.25). Se reemplaza entero.
- `payload/wizard/38-ai-cli-login.sh` — branch gemini: verificacion por round-trip `echo health | gemini -p "..."` (l.53) y login entregando el TUI crudo al usuario con instrucciones /login + /exit (l.90-107). El branch claude (`claude auth login --claudeai`, l.89) **no se toca**.
- `payload/tmux/launch-main.sh` — `launch_cmd_for()` (l.46-62): claude usa `--remote-control <name> <prompt>`; el else lanza `$ai_cli` plano **sin** prompt inicial → gemini/antigravity nunca recibiria `/tutorial` hoy.
- `payload/wizard/run.sh` — FINALE (l.127-171) manda a TODOS los usuarios a instalar la app de Claude Code. Dead end critico para la ruta no-Claude.
- `payload/wizard/40-scaffold.sh` — skills a `~/.agents/skills/` (fuente de verdad) + symlinks a `~/.claude/skills/` via `install_skill()` (l.94-112); renderiza `desktop-readme.md` con `sed s|{{AI_CLI}}|...|` (l.179-188). Genera CLAUDE.md/GEMINI.md/AGENTS.md desde `payload/templates/PROJECT-CLAUDE.md` (l.69-83).
- `payload/tutorial/desktop-readme.md` (276 lineas) — solo la l.59 usa `{{AI_CLI}}`; 40+ lineas hard-wired a Claude (app, Remote Control, troubleshooting `/login`).
- `payload/test/dryrun.sh` — hardcodea `BIB_AI_CLI=claude` (l.22). Corre contra `/repo/payload/install.sh` en VM; **CI hoy no lo ejecuta** (`.github/workflows/ci.yml` = shellcheck + `bash -n` + personal-refs + archive-cleanliness).
- `README.md:28,68` y `site/index.html:57` — prometen "a Google account for Gemini CLI" (falso desde 2026-06-18).
- `tools/reset-for-gift.sh:73-75` — limpia `~/.config/gemini` y `~/.cache/gemini`.
- Comentarios menores con "gemini": `payload/lib/common.sh:160`, `payload/lib/prompt.sh:163`.
- `payload/docs/cli-skills-compatibility.md` — validacion 2026-05-25 con `gemini@0.43.0`: solo discovery de skills, nunca invocacion. Queda obsoleta; necesita addendum agy.
- **Copy shippable adicional con "gemini"** (hueco detectado en QA review de Pablo, verificado con grep 2026-07-09): `payload/skills/README.md` (l.5, 41, 44 — instrucciones de skills citando Gemini CLI), `payload/skills/first-project/SKILL.md` (l.51, 66 — genera `GEMINI.md` como contexto por proyecto), `payload/examples/FEAT-002-personal-slack-coach.md` (7 menciones — spec de ejemplo con `gemini -p` headless), `CLAUDE.md` raiz (l.23 — "bundled Claude Code / Gemini skills"), `iso-builder/user-data:59` (comentario), `payload/flavors/default/copy/welcome.txt:24` y `payload/flavors/gift/copy/welcome.txt:31` ("Claude or Gemini" en el banner de bienvenida) — los tres ultimos detectados al ejecutar el grep del criterio #1 contra `git archive HEAD` real. Los hits bajo `specs/`, `pairing/` y `payload/flavors/gift/maintainer/` no cuentan: son `export-ignore` y no entran en el arbol shippable. Dos casos que NO se modifican, con motivo: `payload/skills/backend-engineer/SKILL.md:15` menciona "Gemini API" como tecnologia de las apps que construye el usuario (no el CLI; sigue siendo valido) y `CHANGELOG.md` (l.24-25, 63) es historia inmutable de releases — ambos quedan eximidos del grep del criterio de aceptacion #1 con filtro documentado alli.
- **Fichero de contexto que lee agy — sin resolver:** `40-scaffold.sh` (l.69-83) y `/first-project` generan `CLAUDE.md`/`GEMINI.md`/`AGENTS.md` por carpeta. Fuentes web ([guia Arm](https://learn.arm.com/install-guides/antigravity/)) indican que agy lee `GEMINI.md` (legacy) o `.antigravity.md` como contexto de workspace, sin confirmacion empirica ni certeza sobre `AGENTS.md` → punto (8) del spike T1; la decision resultante (mantener/renombrar/añadir fichero) se aplica en `payload/wizard/40-scaffold.sh`, `payload/templates/PROJECT-CLAUDE.md` si hace falta y `payload/skills/first-project/SKILL.md`.

**Antigravity CLI (`agy`) — hallazgos web (2026-07-09, verificar en el spike):**

1. **Instalacion:** oficial via `curl -fsSL https://antigravity.google/cli/install.sh | bash` — binario Go unico que aterriza en `~/.local/bin` (fuentes: [docs oficiales](https://antigravity.google/docs/cli/install), [guia Arm](https://learn.arm.com/install-guides/antigravity/), [repo GitHub](https://github.com/google-antigravity/antigravity-cli)). **Pin de version: NO documentado** para install.sh; existen [GitHub releases](https://github.com/google-antigravity/antigravity-cli/releases) (1.1.0 del 2026-07-08, 1.0.16, 1.0.15...) con 8 assets por release → pinear descargando el binario del release directamente es viable, pero el naming de assets no pudo verificarse (la pagina de assets no cargo). El spike lo resuelve.
2. **Auth headless:** `agy auth login`; en sesion SSH/headless detecta el entorno y "prints an authorization URL plus a one-time code" que se abre en otro dispositivo — compatible con la historia Termius/movil (fuentes: [dev.to hands-on](https://dev.to/arindam_1729/antigravity-cli-a-hands-on-guide-to-googles-terminal-coding-agent-5bc7), [aibuilderclub guide](https://www.aibuilderclub.com/blog/antigravity-cli-guide)). NO acepta `GEMINI_API_KEY` (ignorada); CI usa `ANTIGRAVITY_TOKEN`; API key de consumidor sin planes ([issue #78](https://github.com/google-antigravity/antigravity-cli/issues/78)).
3. **⚠️ Persistencia de credenciales — EL riesgo del FEAT:** agy guarda el token OAuth **exclusivamente en el keyring del sistema** (`org.freedesktop.secrets` via libsecret) y rechaza fallbacks a fichero — colocar el token en `~/.gemini/antigravity-cli/*.json` se ignora ([issue #57](https://github.com/google-antigravity/antigravity-cli/issues/57), abierto sin fix; [foro Google AI](https://discuss.ai.google.dev/t/bug-antigravity-cli-agy-fails-to-persist-authentication-state-in-wsl-2-environment/146059)). En un Ubuntu Server 24.04 headless NO hay Secret Service por defecto → sin mitigacion, agy pediria re-login en cada arranque. Workaround reportado por la comunidad: `apt install dbus-x11 libsecret-1-0 gnome-keyring` + arrancar/desbloquear `gnome-keyring-daemon` en la sesion del usuario. Nadie lo ha validado sobre nuestro stack (systemd + SSH + tmux) → **spike obligatorio en Wave 1**.
4. **Config/paths para reset-for-gift:** settings en `~/.gemini/antigravity-cli/settings.json` (hereda el directorio legacy `~/.gemini/`); una fuente cita ademas `~/.config/antigravity/config.toml`. Credenciales en keyring (no en fichero) → el reset debe borrar tambien el secreto del keyring (p. ej. `secret-tool clear`), no solo directorios. Rutas exactas a confirmar en el spike.
5. **Skills:** SKILL.md es estandar abierto y agy lo soporta. Directorios que agy escanea segun [test empirico de Mete Atamel (2026-07-01)](https://atamel.dev/posts/2026/07-01_where_agy_agent_skills/): workspace `<workspace>/.agents/skills/` y globales `~/.gemini/config/skills/` (+ `~/.gemini/antigravity-cli/skills/`, `~/.gemini/skills/`). **`~/.agents/skills/` en el HOME (donde instala BIAB) no esta confirmado como ruta global de agy** — otra fuente ([codelab de skills](https://codelabs.developers.google.com/antigravity/how-to-create-agent-skills-for-antigravity-cli)) sugiere que si. Mitigacion barata en ambos casos: replicar el patron existente de symlinks (`~/.claude/skills/<name>` → `~/.agents/skills/<name>`) hacia el directorio global que agy si lea. Soporte de symlinks: a confirmar en spike.
6. **Prompt inicial:** agy tiene `-p/--print` (headless one-shot) y `-i/--prompt-interactive` (arranca el TUI con un prompt inicial) — el candidato para `/tutorial` es `agy -i '/tutorial'`. Fallback si `-i` no dispara la skill: `tmux send-keys` del texto tras arrancar el TUI. Bug conocido: `agy -p` puede perder stdout al hacer pipe ([aibuilderclub](https://www.aibuilderclub.com/blog/antigravity-cli-guide)) → afecta al comando de verificacion post-login; preferir `agy auth status` o equivalente si existe (spike).

**Riesgos tecnicos (orden de severidad):**

| # | Riesgo | Impacto | Mitigacion |
|---|--------|---------|------------|
| R1 | Token OAuth no persiste en headless sin Secret Service (issue #57) | Re-login en cada arranque → producto roto | Spike T1 valida gnome-keyring headless; si no hay solucion aceptable, PARAR y replantear FEAT (Ask First) |
| R2 | Keyring headless con unlock automatico = token cifrado con clave trivial | Degradacion de seguridad vs. posicionamiento "security-first" | Decision explicita de Jesus en Ask First; documentar el trade-off en el README si se acepta |
| R3 | agy no lee `~/.agents/skills/` global → `/tutorial` no existe al arrancar | Onboarding muerto | Symlink al dir global confirmado por el spike (patron ya existente con `~/.claude/skills/`) |
| R4 | Sin metodo documentado de pin de version del binario | Boundary "versiones pineadas" incumplible via install.sh oficial | Spike decide: asset de GitHub release con checksum, o install.sh oficial + verificacion `agy --version` contra version esperada |
| R5 | `agy -i '/tutorial'` no invoca la skill | Tutorial no arranca solo | Fallback `tmux send-keys` (mismo mecanismo que ya usa launch-main.sh) |
| R6 | Google renombra/reorganiza rutas (producto de 2 meses, cambia rapido) | Mantenimiento | Centralizar TODO el branching en `ai-cli.sh`; comentar fuentes y fecha en el codigo |

### Alcance

**Incluye:**

- Sustitucion completa de la opcion `gemini` por `antigravity` en todo el payload (install, wizard, tmux, docs, copy publico, tests).
- Spike de validacion E2E de agy en VM headless Ubuntu 24.04 ANTES de implementar (auth, persistencia, skills, prompt inicial).
- Limpieza del dead code de `ai-cli.sh` (NFR de §1): se eliminan `ai_cli_binary`/`ai_cli_headless_flag`/`ai_cli_login_cmd`; el branching real que se necesite se añade como funciones nuevas CON call sites.
- Finale de `run.sh` y `desktop-readme.md` bifurcados por `ai_cli` (historia movil no-Claude = SSH/Termius + `tmux attach`; ccgram solo documentado como opcion avanzada).
- Dryrun parametrizado por `BIB_AI_CLI` + job de CI que ejercita ambas rutas con mocks.

**NO incluye:**

- Ningun cambio al flujo de la ruta `claude` (login, Remote Control, finale claude) — solo se mueve copy compartido si hace falta bifurcar.
- Bridge Slack/Telegram propio (ccgram/cc-connect se citan en docs, no se integran).
- Soporte de un tercer CLI (codex u otros) ni redisenar la abstraccion para N CLIs.
- Traduccion de skills SDD opcionales (deferred previo).
- Flip a publico del repo, cambios de precios/posicionamiento en la landing mas alla del parrafo de requisitos.
- Migracion de usuarios existentes con gemini instalado (v0.x llego a 1 caja conocida — Paco — y se regestiona a mano si hace falta).

### Archivos afectados

| Ruta | Accion | Detalle |
|------|--------|---------|
| `payload/lib/ai-cli.sh` | MODIFICAR | `gemini`→`antigravity` en `BIB_SUPPORTED_AI_CLIS`; borrar dead code (l.61-83); nuevas funciones usadas de verdad (p. ej. `ai_cli_launch_cmd`, `ai_cli_verify_cmd`) |
| `payload/install.sh` | MODIFICAR | Usage, validacion non-interactive, prompt y copy `claude|antigravity` (l.50, 56, 112, 340-352) |
| `payload/wizard/05-choose-cli.sh` | MODIFICAR | Opciones + copy honesto sobre el OAuth de cada CLI |
| `payload/install/41-gemini-cli.sh` | ELIMINAR | Sustituido por el installer de agy |
| `payload/install/41-antigravity-cli.sh` | CREAR | Install pineado de `agy` + deps de keyring si el spike las confirma; idempotente |
| `payload/wizard/38-ai-cli-login.sh` | MODIFICAR | Branch antigravity: `agy auth login` guiado + verificacion + fallo claro (EARS Unwanted); branch claude intacto |
| `payload/tmux/launch-main.sh` | MODIFICAR | `launch_cmd_for()`: caso antigravity con prompt inicial `/tutorial` (l.46-62) |
| `payload/wizard/40-scaffold.sh` | MODIFICAR | `install_skill()`: symlink adicional al dir global de skills de agy (segun spike); ficheros de contexto generados (¿se mantiene `GEMINI.md`?) segun T1 punto (8) |
| `payload/wizard/run.sh` | MODIFICAR | FINALE bifurcado por `ai_cli` (l.127-171): claude = app CTA actual; antigravity = SSH/Termius + `tmux attach -t ai-platform` |
| `payload/tutorial/desktop-readme.md` | MODIFICAR | Secciones por CLI con marcadores de bloque que `40-scaffold.sh` filtra al renderizar (ya hace sed; añadir filtrado) |
| `payload/test/dryrun.sh` | MODIFICAR | `BIB_AI_CLI="${BIB_AI_CLI:-claude}"` parametrizable |
| `.github/workflows/ci.yml` | MODIFICAR | Job dryrun matrix `[claude, antigravity]` con `BIB_OAUTH_MOCK=1` + `BIB_TMUX_LAUNCH_CMD=true` |
| `README.md` | MODIFICAR | l.28, l.68: quitar Gemini, describir Antigravity con honestidad |
| `site/index.html` | MODIFICAR | l.57: idem (deploy gated por Jesus — Ask First) |
| `tools/reset-for-gift.sh` | MODIFICAR | l.73-75: rutas de agy (`~/.gemini/antigravity-cli`, etc. segun spike) + limpieza del secreto en keyring |
| `payload/lib/common.sh` | MODIFICAR | Comentario de state.json l.160 |
| `payload/lib/prompt.sh` | MODIFICAR | Comentario-ejemplo l.163 |
| `payload/docs/cli-skills-compatibility.md` | MODIFICAR | Addendum: resultados del spike con agy (discovery + invocacion, que nunca se probo con gemini) |
| `payload/skills/README.md` | MODIFICAR | l.5, 41, 44: Gemini CLI → Antigravity CLI (comando de listado de skills segun T1) |
| `payload/skills/first-project/SKILL.md` | MODIFICAR | l.51, 66: lista de ficheros de contexto generados, segun decision de T1 punto (8) |
| `payload/examples/FEAT-002-personal-slack-coach.md` | MODIFICAR | 7 menciones: `gemini -p` → invocacion headless de agy equivalente; "Claude Code or Gemini CLI" → Antigravity |
| `CLAUDE.md` | MODIFICAR | l.23: "bundled Claude Code / Gemini skills" → Antigravity |
| `iso-builder/user-data` | MODIFICAR | l.59 (comentario): "Claude/Gemini" → "Claude/Antigravity" |
| `payload/flavors/default/copy/welcome.txt` | MODIFICAR | l.24: "Claude or Gemini" → "Claude or Antigravity" |
| `payload/flavors/gift/copy/welcome.txt` | MODIFICAR | l.31: idem |

**Sin cambios (exentos, con motivo):** `payload/skills/backend-engineer/SKILL.md` ("Gemini API" = tecnologia de las apps del usuario, no el CLI — sigue siendo correcto) y `CHANGELOG.md` (historia de releases, no se reescribe). Ambos excluidos del grep del criterio #1.

### Dependencias

- **Binario `agy`** (Antigravity CLI, Go) — version pineada; fuente oficial Google (install.sh oficial o GitHub release, decide el spike). Sustituye a `@google/gemini-cli` (se deja de instalar).
- **Posibles paquetes apt** (solo ruta antigravity, si el spike los confirma necesarios): `gnome-keyring`, `libsecret-1-0`, `dbus-x11` — via `install/41-antigravity-cli.sh`, mismo patron apt que `install/00-base.sh`.
- Ninguna dependencia nueva en la ruta claude ni en el resto del stack.

### Tareas

**Wave 1 — Spike (GATE: si falla, el FEAT se replantea con Jesus antes de escribir una linea de Wave 2)**

<task id="T1">
SPIKE — validar agy E2E en VM headless Ubuntu 24.04 (multipass, mismo rig que FEAT-001). Verificar y documentar: (1) install oficial y como pinear version (¿env var de install.sh? ¿asset de GitHub release + checksum? naming exacto de assets); (2) `agy auth login` por SSH: ¿imprime URL + one-time code copiable? transcript literal; (3) persistencia del token tras logout/reboot SIN keyring y CON `gnome-keyring` headless (¿que unlock exige? ¿sobrevive a reboot con login por SSH key?); (4) discovery de skills: ¿lee `~/.agents/skills/`? ¿funciona symlink en `~/.gemini/config/skills/`? ¿`/tutorial` aparece en `/skills`?; (5) ¿`agy -i '/tutorial'` dispara la skill al abrir el TUI?; (6) rutas exactas de config/cache/credenciales para reset-for-gift; (7) comando de verificacion de login no interactivo (¿`agy auth status`? ¿round-trip `-p`?); (8) fichero de contexto de workspace: ¿agy lee `GEMINI.md`, `AGENTS.md`, `.antigravity.md` o varios? probar con contenido distintivo en cada uno y decidir que genera el scaffold (mantener `GEMINI.md`, renombrar, o añadir fichero). Registrar resultados como addendum en `payload/docs/cli-skills-compatibility.md` y las decisiones en §5 de este FEAT.
<verify>Existe el addendum en `payload/docs/cli-skills-compatibility.md` con transcripts reales de la VM para los 8 puntos, y §5 "Decisiones tomadas" registra: metodo de pin elegido, mecanismo de persistencia validado (o veredicto NO-GO), ruta de skills confirmada, comando de verificacion de login y fichero(s) de contexto que agy carga.</verify>
<done>Los 8 interrogantes tienen respuesta empirica (no de blog); en particular, un `agy -p "reply OK"` (o equivalente) funciona en la VM tras un reboot sin re-login. Si la persistencia headless resulta inviable o exige degradacion de seguridad, el spike termina en NO-GO documentado y se para (Ask First a Jesus) — eso tambien cuenta como done.</done>
</task>

**Wave 2 — Core (depende de T1 GO)**

<task id="T2">
Switch del identificador y del installer. En `payload/lib/ai-cli.sh`: `BIB_SUPPORTED_AI_CLIS=("claude" "antigravity")`, borrar `ai_cli_binary`/`ai_cli_headless_flag`/`ai_cli_login_cmd`, mapear `ai_cli_install_script` a `install/41-antigravity-cli.sh`. Crear `payload/install/41-antigravity-cli.sh` (idempotente, `set -euo pipefail`, version pineada en variable con comentario de fecha/fuente, verificacion `agy --version`, deps de keyring segun T1). Eliminar `payload/install/41-gemini-cli.sh`. Actualizar `payload/install.sh` (usage l.56, validacion l.112, prompt l.340-352), `payload/wizard/05-choose-cli.sh`, y comentarios en `payload/lib/common.sh:160` y `payload/lib/prompt.sh:163`.
<verify>`grep -ri gemini payload/ installer/ --include='*.sh'` devuelve cero lineas; `shellcheck payload/install/41-antigravity-cli.sh payload/lib/ai-cli.sh` y `bash -n` limpios; `sudo payload/install.sh --ai-cli=gemini` muere con "unsupported ai-cli"; en VM, ejecutar dos veces `payload/install/41-antigravity-cli.sh` deja `agy --version` == version pineada sin error en la segunda pasada.</verify>
<done>La opcion gemini ha desaparecido del arbol de scripts, `antigravity` instala un `agy` pineado de fuente oficial de forma idempotente, y no queda dead code en `ai-cli.sh` (toda funcion tiene call site verificable con grep).</done>
</task>

<task id="T3">
Login wizard. En `payload/wizard/38-ai-cli-login.sh`, branch `antigravity`: pantalla previa explicando el flujo (URL + code en Termius, igual de guiado que el branch claude), ejecutar `agy auth login` como target user, comando de verificacion el confirmado en T1, y — EARS Unwanted — si la verificacion falla tras el retry, `die` con instrucciones de recuperacion concretas (re-run install.sh, y el sintoma tipico de keyring si T1 lo identifico); nunca colgar esperando un navegador local. Branch claude byte-identico salvo refactor compartido inevitable.
<verify>`shellcheck` + `bash -n` limpios; `BIB_OAUTH_MOCK=1` cortocircuita igual que hoy; en VM antigravity el paso completa el login real y `phase_done ai_cli_done` queda en state.json; `git diff` del branch claude revisado a mano = sin cambios de comportamiento.</verify>
<done>Un usuario en Termius completa el OAuth de agy solo con lo que la pantalla le dice (validado en la pasada E2E de §4), y un fallo de auth termina en mensaje accionable, no en cuelgue.</done>
</task>

<task id="T4">
Sesion tmux + skills. En `payload/tmux/launch-main.sh`, `launch_cmd_for()`: caso `antigravity` lanza `agy` con `/tutorial` como prompt inicial usando el mecanismo validado en T1 (`agy -i '/tutorial'` o fallback send-keys). En `payload/wizard/40-scaffold.sh`, `install_skill()`: symlink adicional de cada skill al directorio global de agy confirmado en T1 (mismo patron que el symlink existente a `~/.claude/skills/`), y `chown` consecuente.
<verify>`shellcheck` + `bash -n` limpios; en VM antigravity: `tmux new-session` del wizard deja una sesion `ai-platform` donde `/skills` lista `tutorial` y el TUI arranca con el tutorial en marcha; con `BIB_TMUX_LAUNCH_CMD=true` el dryrun sigue construyendo la sesion sin CLI.</verify>
<done>Tras el wizard con antigravity, atacharse a `ai-platform` muestra a agy ejecutando /tutorial — mismo comportamiento observable que la ruta claude tiene hoy.</done>
</task>

**Wave 3 — Onboarding copy + publico + CI (depende de Wave 2)**

<task id="T5">
Finale y README de escritorio bifurcados. `payload/wizard/run.sh` (l.127-171): extraer el finale a dos bloques por `ai_cli` — claude conserva el CTA de la app + QR actual; antigravity instruye instalar Termius (o cualquier SSH client), `ssh <user>@<hostname>` via Tailscale y `tmux attach -t ai-platform`, con ccgram citado en una linea como opcion avanzada. `payload/tutorial/desktop-readme.md`: envolver el contenido Claude-only (Remote Control, app, troubleshooting /login) en marcadores `<!-- BIB:claude -->`/`<!-- BIB:end -->` (y equivalente antigravity) que `40-scaffold.sh` filtra con awk/sed al renderizar segun `state.ai_cli`. Tono epico-pero-aterrizado, ingles, coherente con el modelo one-session.
<verify>`bash -n` + shellcheck limpios; render de prueba del readme con `ai_cli=antigravity` no contiene "Claude Code app" ni "Remote Control" (`grep -c` == 0) y si contiene "tmux attach"; render con `ai_cli=claude` es identico al actual salvo los marcadores; el finale antigravity en dryrun no imprime el QR de claude.ai/download.</verify>
<done>Un usuario antigravity termina el wizard con instrucciones que puede seguir hasta el final (SSH → attach → tutorial) y su `~/README.md` no menciona una app que no puede usar.</done>
</task>

<task id="T6">
Copy publico + CI + reset. `README.md` (l.28, l.68) y `site/index.html` (l.57): sustituir la promesa de Gemini por Antigravity ("a Google account for Antigravity CLI" + nota honesta de requisitos) — el deploy de site/ queda gated por Jesus. Barrido del resto de copy shippable: `payload/skills/README.md` (l.5, 41, 44), `payload/examples/FEAT-002-personal-slack-coach.md` (invocacion headless de agy en lugar de `gemini -p`), `CLAUDE.md:23`, `payload/skills/first-project/SKILL.md` (l.51, 66 — segun decision de T1 punto 8), `iso-builder/user-data:59`, y los dos `welcome.txt` de `payload/flavors/{default,gift}/copy/` ("Claude or Gemini" → "Claude or Antigravity"). `payload/test/dryrun.sh`: `BIB_AI_CLI="${BIB_AI_CLI:-claude}"`. `.github/workflows/ci.yml`: job `dryrun` con matrix `ai_cli: [claude, antigravity]` sobre ubuntu-latest con `BIB_OAUTH_MOCK=1` y `BIB_TMUX_LAUNCH_CMD=true` (si el runner no soporta el install completo, degradar a container/multipass y documentarlo en el propio yml). NOTA explicita para QA: esta matrix corre con OAuth mockeado — valida el wiring del installer/wizard, **NO** la persistencia del token de agy (R1); esa solo la cubre la pasada manual E2E de §4 (CP-02). `tools/reset-for-gift.sh`: reemplazar rutas gemini por las rutas de agy confirmadas en T1 + limpieza del secreto del keyring (`secret-tool clear` o borrado del keyring file del usuario).
<verify>El grep exacto del criterio de aceptacion #1 (con sus exclusiones documentadas) == 0 hits; CI verde en la PR con ambos jobs de matrix pasando; en VM, tras login real de agy, ejecutar `tools/reset-for-gift.sh` y comprobar que `agy` vuelve a pedir login (token realmente purgado).</verify>
<done>Ninguna superficie publica promete Gemini CLI; un cambio futuro que rompa el wiring de la ruta antigravity pone CI en rojo (sin que ese verde se lea como cobertura de R1); una caja regalada no lleva el token de Google del maintainer dentro.</done>
</task>

### Patron de codigo

Branching por CLI existente en `payload/tmux/launch-main.sh` (l.46-62) — es exactamente el punto donde se añade el caso antigravity, y el patron a replicar (dryrun override primero, luego case por CLI):

```bash
# Dryrun: BIB_TMUX_LAUNCH_CMD overrides everything (used by tests).
launch_cmd_for() {
    local window_name="$1"
    local initial_prompt="${2:-}"
    if [[ -n "${BIB_TMUX_LAUNCH_CMD:-}" ]]; then
        echo "$BIB_TMUX_LAUNCH_CMD"
        return
    fi
    if [[ "$ai_cli" == "claude" ]]; then
        if [[ -n "$initial_prompt" ]]; then
            printf "claude --remote-control %q %q" "$window_name" "$initial_prompt"
        else
            printf "claude --remote-control %q" "$window_name"
        fi
    else
        echo "$ai_cli"
    fi
}
```

### Criterios de aceptacion

1. Cero menciones a Gemini en el arbol shippable, con dos exenciones documentadas. Comando exacto:
   ```bash
   tree="$(mktemp -d)" && git archive HEAD | tar -x -C "$tree"
   grep -ri gemini "$tree" --exclude=CHANGELOG.md | grep -vi 'gemini api'
   # → 0 lineas (exit code 1 del segundo grep)
   ```
   Exenciones y motivo: `CHANGELOG.md` es historia inmutable de releases (no se reescribe); el patron "Gemini API" (hoy solo `payload/skills/backend-engineer/SKILL.md:15`) se refiere a la API de modelos para las apps que construye el usuario, no al CLI retirado, y sigue siendo correcto. Cualquier otro hit es fallo del criterio.
2. En una VM/box headless Ubuntu 24.04 limpia: `install.sh --ai-cli=antigravity` completa el wizard entero desde Termius, y tras un **reboot** la sesion `ai-platform` arranca `agy` autenticado (sin re-login) con /tutorial en pantalla.
3. La misma pasada con `--ai-cli=claude` es indistinguible del comportamiento actual (regresion cero — verificable con el dryrun claude y la pasada E2E de §4).
4. CI en la PR: shellcheck + `bash -n` + personal-refs + archive-cleanliness + dryrun matrix `[claude, antigravity]`, todo verde. **Alcance del verde de CI:** la matrix corre con `BIB_OAUTH_MOCK=1` + `BIB_TMUX_LAUNCH_CMD=true`, asi que cubre el wiring (installer + wizard + estado), pero NO la persistencia del token de agy (R1) ni el login real — eso lo cubre exclusivamente el criterio #2 via la pasada manual E2E de QA (§4, CP-02). CI verde no sustituye al criterio #2.
5. La version de `agy` instalada es exactamente la pineada en `41-antigravity-cli.sh` (`agy --version` == constante del script) y re-ejecutar el installer no la cambia ni falla.
6. `tools/reset-for-gift.sh` deja `agy` des-autenticado (pide login en el siguiente arranque) — verificado en VM.

### Complejidad

**Media** (Sonnet) — es un rename+branch disciplinado sobre una abstraccion que ya existe, PERO con un spike gate en Wave 1 cuyo resultado puede escalar el FEAT (si el keyring headless se complica, reevaluar a alta/Opus o replantear con Jesus).

---

## 3. Boundaries

### Always

- `set -euo pipefail` en todo script bash; pasos idempotentes y re-ejecutables.
- Strings de cara al usuario en inglés.
- PR siempre; CI verde (shellcheck, `bash -n`, personal-refs guard, archive-cleanliness) antes de merge.
- Versiones pineadas para el binario `agy` (la falta de pin en `@google/gemini-cli` fue un error — no repetir).
- Mantener `payload/lib/ai-cli.sh` como única abstracción del CLI elegido; cualquier branching por CLI pasa por ahí o por `state.json`, nunca hardcodeado en pasos sueltos.
- Onboarding copy consistente con el modelo real del dispositivo (una sesión tmux `ai-platform`, sesiones independientes por proyecto).

### Ask First

- Cualquier cambio al flujo de auth/login de la ruta **Claude** (hoy funciona; no se toca sin OK).
- Publicar/desplegar los cambios de copy en la landing (`site/`) — outward-facing, Jesus revisa antes del deploy.
- La fuente de descarga del binario `agy` si no hay canal oficial documentado de Google (nunca un mirror de terceros sin OK).
- Cualquier decisión que implique pedir al usuario un proyecto GCP o billing (si el OAuth gratuito resultara inviable en headless, PARAR y consultar — cambia el pitch del producto).
- [Laura 2026-07-09] Instalar `gnome-keyring` con unlock automático o keyring sin contraseña para persistir el token OAuth de agy en headless (issue upstream #57): es un trade-off de seguridad real (token de Google cifrado con clave trivial en disco) que choca con el posicionamiento security-first — decisión explícita de Jesus tras el spike T1, y si se acepta, se documenta honestamente en el README.
- [Laura 2026-07-09] Añadir `dbus-x11`/`gnome-keyring` como dependencias del sistema (nueva superficie de paquetes en la caja del usuario) — confirmar tras el spike.

### Never

- Construir un bridge Slack/Telegram propio (ccgram/cc-connect se documentan, no se reimplementan — decisión del consejo 2026-07-09).
- Eliminar la opción `claude` ni degradar su experiencia actual.
- Abrir puertos públicos o añadir servicios expuestos (rompería el posicionamiento seguridad-primero).
- Tocar `.env`, credenciales o tokens; commitear secrets.
- Hacer el flip a público del repo dentro de este FEAT (es un gate separado de Jesus).
- Contenido de usuario final en rutas `export-ignore` de `.gitattributes`.
- [Laura 2026-07-09] Lanzar `agy` desde el wizard/tmux con `--approve all` ni `--dangerously-skip-permissions` — el auto-approve global en la caja del usuario anula el modelo de permisos del CLI.
- [Laura 2026-07-09] Persistir `ANTIGRAVITY_TOKEN` en disco de la caja del usuario (es mecanismo de CI, no de dispositivo de usuario final).

---

## 4. QA (Pablo)

> Casos de ACEPTACIÓN del FEAT completo (journey de usuario + regresiones). Los `<verify>` por tarea de §2 son la verificación unitaria de cada wave y NO se repiten aquí. Entornos: **VM-A** = VM multipass Ubuntu Server 24.04 limpia (mismo rig que FEAT-001, repo montado en `/repo`); **BOX** = box física headless (opcional, para la pasada final); **MOBILE** = cliente SSH en móvil (Termius) conectado por Tailscale. Los comandos marcados `[según T1]` usan el comando de verificación de login que confirme el spike (`agy auth status` o round-trip `-p`).

### Casos de prueba funcionales

| # | Caso | Pasos | Resultado esperado | Estado |
|---|------|-------|--------------------|--------|
| CP-01 | **Journey completo antigravity desde el móvil (Termius)** — historia de usuario 1 y 2 | 1. Lanzar VM-A limpia y ejecutar `sudo /repo/payload/install.sh` (interactivo) desde una sesión SSH abierta en Termius (MOBILE).<br>2. En el chooser, seleccionar `antigravity`.<br>3. En el paso de login, seguir SOLO lo que dice la pantalla: copiar la URL + one-time code mostrados, completar el OAuth de Google en el navegador del móvil, volver a Termius.<br>4. Dejar que el wizard termine (scaffold + tmux + finale).<br>5. Leer el finale completo en la pantalla de Termius.<br>6. Seguir las instrucciones del finale al pie de la letra: `ssh <user>@<hostname>` + `tmux attach -t ai-platform`. | El OAuth completa sin navegador local y sin input imposible; el wizard llega al finale sin colgarse; el finale NO contiene QR ni mención a la app de Claude Code y SÍ instrucciones SSH/Termius + `tmux attach -t ai-platform`; al atacharse, `agy` está corriendo con `/tutorial` en marcha. Todo el journey se completa usando únicamente el móvil. | ⬜ |
| CP-02 | **Persistencia del token tras reboot** — criterio de aceptación #2, riesgo R1 | 1. Partir de CP-01 completado (login real de agy hecho).<br>2. `sudo reboot` en la VM-A.<br>3. Reconectar por SSH (key auth, sin password de sesión gráfica).<br>4. Comprobar la sesión tmux: `sudo -u <user> tmux ls`.<br>5. Atacharse a `ai-platform` y observar el estado de agy.<br>6. Fuera de tmux, ejecutar el comando de verificación de login `[según T1]` (p. ej. `sudo -iu <user> agy -p "reply OK"`). | La sesión `ai-platform` existe tras el reboot; agy arranca **autenticado sin pedir re-login** (ni URL ni code en pantalla); el comando de verificación responde OK. Repetir un segundo reboot para descartar que el primero viviera de caché. | ⬜ |
| CP-03 | **reset-for-gift purga el token de Google** — criterio de aceptación #6 | 1. Partir de una VM-A con login real de agy completado y verificado.<br>2. Ejecutar `sudo tools/reset-for-gift.sh` (flujo completo de regalo).<br>3. Comprobar restos: directorios de config/cache de agy `[rutas según T1]` y el secreto en el keyring (`sudo -iu <user> secret-tool search --all service <atributo-según-T1>` o inspección del keyring file).<br>4. Arrancar agy de nuevo (`sudo -iu <user> agy`). | No queda token en keyring ni en `~/.gemini/antigravity-cli/` ni en ninguna ruta confirmada por T1; agy pide login desde cero (URL + code). Una caja regalada NO lleva la cuenta Google del maintainer dentro. | ⬜ |
| CP-04 | **Desktop README bifurcado (ruta antigravity)** | 1. En la VM-A post-wizard antigravity, abrir `/home/<user>/README.md`.<br>2. `grep -c -e "Claude Code app" -e "Remote Control" -e "claude.ai/download" /home/<user>/README.md`.<br>3. `grep -c "tmux attach" /home/<user>/README.md`.<br>4. Leerlo entero como usuario nuevo: seguir sus instrucciones de conexión móvil. | Paso 2 == 0 en total; paso 3 >= 1; las instrucciones del README son seguibles de principio a fin con antigravity (SSH/Termius + attach; ccgram citado solo como opción avanzada, sin instrucciones de bridge propio). | ⬜ |
| CP-05 | **Skills disponibles e invocables en agy** — requisito EARS de skills, riesgo R3/R5 | 1. En la sesión `ai-platform` de la VM-A antigravity, ejecutar `/skills` (o el listado equivalente de agy).<br>2. Verificar que `tutorial` y `first-project` aparecen.<br>3. Confirmar que `/tutorial` está de hecho ejecutándose desde el arranque (prompt inicial) y que sus primeros pasos responden.<br>4. Invocar `/first-project` hasta el punto de crear la sesión tmux del proyecto. | Las skills instaladas en `~/.agents/skills/` son visibles para agy (vía symlink al dir global confirmado en T1); `/tutorial` arrancó solo (sin send-keys manual del tester); `/first-project` crea una sesión tmux independiente con nombre del proyecto. | ⬜ |
| CP-06 | **CI ejercita ambas rutas** — historia de usuario 3 | 1. En la PR del FEAT, comprobar el workflow: job dryrun con matrix `ai_cli: [claude, antigravity]`.<br>2. Introducir en una branch de prueba un breakage deliberado solo-antigravity (p. ej. typo en `41-antigravity-cli.sh`) y empujar.<br>3. Revertir. | Paso 1: ambos jobs de la matrix verdes en la PR real. Paso 2: el job antigravity se pone ROJO y el claude sigue verde (el canario funciona de verdad, no es decorativo). | ⬜ |
| CP-07 | **Superficie pública sin Gemini** — criterio de aceptación #1 | 1. `git archive HEAD \| tar -xC /tmp/biab-ship && grep -ri gemini /tmp/biab-ship` (excluyendo, si Elena lo acepta, menciones históricas de `CHANGELOG.md` — ver Notas QA).<br>2. `grep -ri gemini README.md site/`.<br>3. Revisar la landing renderizada (`site/index.html`) a ojo: la promesa es "a Google account for Antigravity CLI" con nota honesta de requisitos. | Cero hits de `gemini` en código, copy y comentarios del árbol shippable; el copy público describe Antigravity sin prometer nada que el spike no haya validado. | ⬜ |
| CP-08 | **Pin de versión e idempotencia del installer de agy** — criterio de aceptación #5 | 1. En VM-A, ejecutar el flujo de install antigravity completo.<br>2. `agy --version` y comparar con la constante pineada: `grep -E 'AGY_VERSION|ANTIGRAVITY_VERSION' payload/install/41-antigravity-cli.sh`.<br>3. Re-ejecutar `sudo payload/install/41-antigravity-cli.sh`.<br>4. `agy --version` de nuevo. | Versión instalada == constante del script en ambas pasadas; la segunda pasada termina exit 0 sin re-descargar a una versión distinta ni romper nada. | ⬜ |

### Edge cases

| # | Caso | Input / condición | Resultado esperado | Estado |
|---|------|-------------------|--------------------|--------|
| EC-01 | Flag legacy `gemini` | `sudo payload/install.sh --ai-cli=gemini` y también `BIB_AI_CLI=gemini` en modo non-interactive | Muere inmediatamente con "unsupported ai-cli" (exit != 0), listando las opciones válidas. Sin cuelgue, sin instalación parcial. | ⬜ |
| EC-02 | Valor vacío/basura de CLI | `--ai-cli=` (vacío) y `--ai-cli=CLAUDE; rm -rf /` (mayúsculas + injection string) | Validación rechaza ambos con mensaje claro; ningún side effect (el string jamás se evalúa/ejecuta). | ⬜ |
| EC-03 | OAuth abandonado a mitad | En el paso de login antigravity, NO completar el OAuth: cerrar Termius / dejar expirar el one-time code / Ctrl-C sobre `agy auth login` | El wizard no se queda colgado indefinidamente esperando: la verificación post-login falla y — EARS Unwanted — termina en `die` con instrucciones de recuperación concretas (re-run de install.sh; síntoma de keyring si T1 lo identificó). El estado en `state.json` NO marca `ai_cli_done`. | ⬜ |
| EC-04 | Reboot antes de completar el login | Instalar con antigravity, interrumpir en el paso de login, `sudo reboot`, reconectar y re-ejecutar `sudo payload/install.sh` | El installer retoma en el paso de login (fases previas saltadas por state.json, no re-ejecutadas destructivamente); el login completa y el resto del wizard sigue normal. | ⬜ |
| EC-05 | Re-run completo tras éxito (idempotencia E2E) | Con el wizard antigravity terminado y funcionando, re-ejecutar `sudo payload/install.sh` entero | Ningún paso rompe; no exige re-OAuth si el token es válido; la sesión tmux `ai-platform` queda funcional (recreada o intacta); el README de escritorio no se duplica ni se corrompe. | ⬜ |
| EC-06 | Fallo de red al descargar agy | Simular fallo del fetch del binario (p. ej. cortar red o apuntar `AGY_VERSION` a un release inexistente en una copia del script) | `41-antigravity-cli.sh` muere con error claro (no deja un `agy` a medias en PATH); re-run tras restaurar la red instala bien. | ⬜ |
| EC-07 | Keyring no arrancado en un arranque concreto (si T1 confirma dependencia de gnome-keyring) | Matar/deshabilitar `gnome-keyring-daemon` en la sesión del usuario y arrancar la sesión tmux | agy NO se cuelga: o re-pide login con mensaje comprensible, o el launcher detecta el estado y lo explica. Documentado como troubleshooting en el desktop-readme antigravity si el spike confirma que puede pasar. | ⬜ |

### Regresión — la ruta `claude` es sagrada (criterio de aceptación #3)

Checklist: nada de esto debe cambiar de forma observable. Verificación en dos niveles — dryrun (automático) y una pasada E2E claude en VM-A idéntica a la que se haría hoy en main.

- [ ] **Dryrun claude**: `BIB_AI_CLI=claude payload/test/dryrun.sh` (default actual) termina `exit=0` con las mismas fases en `state.json` que en `main` (diff de state.json entre main y la branch == solo lo esperado).
- [ ] **E2E claude en VM-A**: install interactivo eligiendo `claude` → login `claude auth login --claudeai` intacto → sesión `ai-platform` con `claude --remote-control` y `/tutorial` → finale con el CTA de la app + QR de claude.ai/download **exactamente como hoy**.
- [ ] **desktop-readme claude**: el `~/README.md` renderizado con `ai_cli=claude` es idéntico al actual (diff contra un render de main == vacío, salvo que los marcadores de bloque sean invisibles en el output).
- [ ] **38-ai-cli-login.sh branch claude**: `git diff main -- payload/wizard/38-ai-cli-login.sh` revisado a mano — cero cambios de comportamiento en el branch claude (solo refactor compartido inevitable, si lo hay).
- [ ] **Skills claude**: los symlinks `~/.claude/skills/<name>` → `~/.agents/skills/<name>` siguen creándose y `/tutorial` sigue siendo el prompt inicial de la ruta claude.
- [ ] **reset-for-gift ruta claude**: sigue limpiando las credenciales de Claude como hasta ahora (el cambio de rutas gemini→agy no toca las líneas de claude).
- [ ] **CI existente**: shellcheck, `bash -n`, personal-refs guard y archive-cleanliness siguen verdes (los jobs nuevos son aditivos).
- [ ] **install.sh servido por la landing**: `site/build.sh` sigue produciendo un `install.sh` byte-idéntico al de `installer/web/install.sh` (los cambios de copy en `site/index.html` no rompen ese contrato).

### Criterios de testing

```bash
# --- Estático (local y CI, sin VM) ---
# 1. Lint de todo el bash tocado
shellcheck payload/install.sh payload/install/41-antigravity-cli.sh \
  payload/lib/ai-cli.sh payload/wizard/38-ai-cli-login.sh \
  payload/wizard/05-choose-cli.sh payload/wizard/40-scaffold.sh \
  payload/wizard/run.sh payload/tmux/launch-main.sh \
  payload/test/dryrun.sh tools/reset-for-gift.sh
find payload installer tools -name '*.sh' -exec bash -n {} +

# 2. Cero gemini en el árbol shippable (CP-07)
rm -rf /tmp/biab-ship && mkdir -p /tmp/biab-ship
git archive HEAD | tar -xC /tmp/biab-ship
grep -ri gemini /tmp/biab-ship && echo "FAIL: gemini remains" || echo "OK"
# (Nota: '~/.gemini/antigravity-cli' es una ruta legacy REAL de agy — si T1 la
# confirma, esas ocurrencias son legítimas y se excluyen con comentario inline.)

# 3. Dead code eliminado de ai-cli.sh (NFR §1)
grep -rn 'ai_cli_binary\|ai_cli_headless_flag\|ai_cli_login_cmd' payload/ installer/ \
  && echo "FAIL: dead code" || echo "OK"

# --- Dryrun (VM multipass con repo montado en /repo, rig FEAT-001) ---
multipass launch 24.04 --name biab-qa --cpus 2 --memory 4G --disk 15G
multipass mount "$(pwd)" biab-qa:/repo
# Ambas rutas, mockeadas:
multipass exec biab-qa -- sudo env BIB_AI_CLI=claude      bash /repo/payload/test/dryrun.sh
multipass exec biab-qa -- sudo env BIB_AI_CLI=antigravity bash /repo/payload/test/dryrun.sh
# El finale antigravity del dryrun no imprime el QR de claude:
multipass exec biab-qa -- sudo env BIB_AI_CLI=antigravity bash /repo/payload/test/dryrun.sh \
  | grep -c 'claude.ai/download'   # esperado: 0

# --- E2E antigravity (VM limpia, login REAL, luego CP-01..CP-05) ---
# Pin (CP-08):
multipass exec biab-qa -- agy --version
grep -E 'AGY_VERSION|ANTIGRAVITY_VERSION' payload/install/41-antigravity-cli.sh
# Persistencia post-reboot (CP-02):
multipass exec biab-qa -- sudo reboot; sleep 45
multipass exec biab-qa -- sudo -iu ubuntu tmux ls          # ai-platform presente
multipass exec biab-qa -- sudo -iu ubuntu agy -p "reply OK"  # [según T1] responde sin pedir login
# Purga de token (CP-03):
multipass exec biab-qa -- sudo bash /repo/tools/reset-for-gift.sh
multipass exec biab-qa -- sudo -iu ubuntu agy -p "reply OK" # esperado: pide login / falla auth

# --- Flag legacy y validación (EC-01/EC-02) ---
sudo payload/install.sh --ai-cli=gemini; echo "exit=$?"     # esperado: exit!=0 + "unsupported"
sudo env BIB_USER=ubuntu BIB_FLAVOR=default BIB_AI_CLI=gemini \
  payload/install.sh --non-interactive; echo "exit=$?"      # esperado: exit!=0

# --- CI (en la PR) ---
gh pr checks <PR>   # shellcheck + bash -n + personal-refs + archive-cleanliness + dryrun[claude] + dryrun[antigravity] verdes
```

### Smoke test post-deploy (tras merge, antes del flip a público)

1. `curl -fsSL https://buildersinabox.com/install.sh | head -50` — el bootstrap servido es el nuevo (menciona `antigravity`, no `gemini`) y byte-idéntico a `installer/web/install.sh`.
2. Landing en el navegador: la sección de requisitos dice Antigravity; cero menciones a Gemini CLI.
3. Una pasada E2E final en BOX física (no VM) de CP-01 + CP-02 — el keyring/systemd real puede diferir del de multipass; es EL riesgo del FEAT y merece hardware real antes del launch.

### Notas QA — huecos detectados en §2 (para Elena/Laura, no bloquean la DoR de §4)

1. **Archivos shippables con "gemini" que NO están en la tabla de §2**: `payload/skills/README.md`, `payload/skills/first-project/SKILL.md`, `payload/skills/backend-engineer/SKILL.md`, `payload/examples/FEAT-002-personal-slack-coach.md`, `CLAUDE.md` (raíz) y `CHANGELOG.md` — todos entran en `git archive HEAD` (verificado 2026-07-09) y harían FALLAR el criterio de aceptación #1 tal como está escrito. Hace falta o añadirlos a la tabla de T2/T6, o que Elena excluya explícitamente las menciones históricas (CHANGELOG) del criterio.
2. **`40-scaffold.sh` genera `GEMINI.md`** como fichero de contexto por proyecto (l.69-83). §2 no dice qué fichero de contexto lee agy (¿`GEMINI.md` heredado? ¿`AGENTS.md`?) y no está entre los 7 puntos del spike T1 — sugerido añadirlo como punto (8) del spike.
3. **CI matrix con `BIB_OAUTH_MOCK=1`** no ejercita el login real por diseño — correcto, pero significa que R1 (persistencia) queda cubierto SOLO por las pasadas manuales CP-02 y el smoke en BOX física. Que nadie marque el criterio #2 como cumplido con el dryrun verde.
4. **EC-07 depende del resultado de T1**: si el spike concluye que no hace falta keyring daemon, EC-07 se marca N/A con nota.

---

## 5. Implementacion (Laura — se rellena durante la implementacion)

### Branch

`feat/FEAT-013`

### Progreso

| Task | Estado | Commit | Notas |
|------|--------|--------|-------|
| T1 (spike) | ✅ GO | (VM biab-spike) | agy 1.1.0: token a fichero 0600, sin keyring. Addendum en `payload/docs/cli-skills-compatibility.md`. |
| T2 switch+installer | ✅ | `1285f00` | ai-cli.sh (`claude`+`antigravity`, dead code fuera); `41-antigravity-cli.sh` pineado+sha256; `41-gemini-cli.sh` borrado; install.sh/05-choose-cli/comentarios. |
| T3 login wizard | ✅ | `57a0db0` | branch antigravity: TUI + `agy models` verify + die accionable (EARS). Branch claude byte-idéntico en runtime. |
| T4 tmux+skills | ✅ | `1ade051` | `agy -i '/tutorial'`; symlink a `~/.gemini/skills/`; pre-seed `settings.json`; genera CLAUDE.md+AGENTS.md (sin GEMINI.md). |
| T5 finale+readme | ✅ | `c2e6702` | run.sh finale bifurcado (SSH/Termius+tmux attach, ccgram 1 línea); desktop-readme con marcadores `<!-- BIB:claude/antigravity -->` filtrados por awk en scaffold. |
| T6 copy+CI+reset | ✅ | `580096a`, `34edb48`, `ea192cb` | README/site (site sin deploy); barrido gemini; dryrun parametrizable; CI matrix `[claude, antigravity]` (wiring-smoke); reset-for-gift rutas agy. |

### Decisiones tomadas

- [2026-07-09] Opción B elegida por Jesus contra recomendación unánime del consejo (Claude-only): la promesa multi-CLI se arregla ANTES del launch, no se elimina.
- [2026-07-09] Descartado: auth por Gemini API key (no soportado upstream, issue #78). Descartado: bridge Slack/Telegram propio.
- **[2026-07-09 spike T1] R1 NO se materializa → SIN keyring.** agy 1.1.0 persiste el token OAuth en fichero plano `~/.gemini/antigravity-cli/antigravity-oauth-token` (0600) con fallback a fichero, sobrevive reboots sin Secret Service. NO se instalan `gnome-keyring`/`dbus-x11`/`libsecret`. **Los dos "Ask First" de Laura sobre keyring (§3) decaen (MOOT); R2 (degradación de seguridad) también MOOT** — mismo modelo user-only que Claude. El installer queda más simple (solo binario pineado).
- **[spike T1] `agy auth login` NO existe.** Login = arrancar el TUI (`agy`), elegir "Google OAuth" (URL OAuth larga + paste-back del authorization code) + onboarding (color/telemetría/trust-folder). T3 orquesta el TUI, no un subcomando headless.
- **[spike T1] Pin vía GitHub release + sha256**, no install.sh oficial (no pinea). Asset `agy_cli_linux_x64.tar.gz` (tarball = binario único `antigravity`, se instala como `agy`). Auto-update desactivado con `AGY_CLI_DISABLE_AUTO_UPDATE=1` en launcher + login.
- **[spike T1] Skills: symlink a `~/.gemini/skills/`** (dir global "Shared" de agy). agy NO escanea `~/.agents/skills/` del HOME (solo workspace). Mismo patrón que el symlink existente a `~/.claude/skills/`. Symlinks confirmados funcionando.
- **[spike T1] Fichero de contexto: `AGENTS.md`** (agy lee AGENTS.md y GEMINI.md; NO `.antigravity.md`). El scaffold genera CLAUDE.md + AGENTS.md y deja de generar GEMINI.md.
- **[spike T1] Verify login = `agy models </dev/null`** (exit 0 autenticado, sin gastar cuota, sin disparar OAuth). stdin siempre `</dev/null` (agy consume stdin abierto).
- **[spike T1] Pre-seed `settings.json`** (`allowNonWorkspaceAccess:true`, `enableTelemetry:false`, `trustedWorkspaces:[<ws abs>]`) para que el primer `/tutorial` sea zero-touch.
- **[implementación] CI: wiring-smoke hermético, no VM dryrun.** El runner de GitHub no tiene usuario `ubuntu`, systemd, Tailscale ni red a los endpoints de Google, así que el `dryrun.sh` completo (y sobre todo R1/persistencia) NO corre en CI — se cubre solo con la pasada manual multipass de §4 (CP-02). La matrix `[claude, antigravity]` corre `payload/test/wiring-smoke.sh` (resuelve CLI → install script + `bash -n`, rechazo de `gemini`, comando de lanzamiento correcto, render del README limpio). Es canario real: un typo solo-antigravity pone en rojo únicamente esa pata.
- **[implementación] Criterio #1 (grep gemini) — exclusión ampliada.** Además de `CHANGELOG.md` y `gemini api`, quedan como legítimas las rutas reales de agy (`~/.gemini/…` es su config-home heredado) y el fichero de contexto `GEMINI.md` que agy sí lee, más el string `gemini` del test de rechazo en `wiring-smoke.sh`. Ninguna presenta Gemini CLI como opción soportada. Verificado sobre `git archive HEAD`: cero menciones al *producto* Gemini CLI en el árbol shippable (todas las restantes son paths/filenames de agy o el test de rechazo).

### Blockers

- [ ] — (ninguno)

### Verificacion post-implementacion

- [x] Todos los `<verify>` estáticos de cada tarea pasan (shellcheck, `bash -n`, dead-code grep, grep gemini, render README)
- [x] Dryrun/wiring harness pasa en ambas rutas (`claude` y `antigravity`) con `BIB_OAUTH_MOCK=1` + `BIB_TMUX_LAUNCH_CMD=true`
- [x] Criterios de aceptacion estáticos (#1 grep, #4 CI matrix, #5 pin en constante) verificados
- [x] **E2E con auth real de Jesus (hezumartin@gmail.com) — GO (2026-07-09).** CP-08 install+idempotencia PASS; login real PASS; CP-01 `agy models` exit 0; **CP-02 persistencia: 2 reboots reales sin re-login — R1 NO se materializa (criterio #2 PASS)**; CP-05 skills+`/tutorial` PASS; CP-03 reset purga token PASS (borró hasta la SSH key = wipe real); regresión claude wiring-smoke PASS (criterio #3). VM `biab-e2e` purgada tras el test.
- [x] Sin secrets en el diff
- [x] Sin cambios fuera del scope (ruta claude runtime intacta; sin puertos; sin keyring; sin bridge; site sin deploy)
- [x] shellcheck + `bash -n` sin errores (CI-mode, todos los `*.sh`)
- [x] Code review (subagente code-reviewer) — 0 bugs bloqueantes; nit de idempotencia de `agy --version` corregido (commit f107623)
- [x] Papercut E2E del pre-seed de settings.json (2 prompts antes de /tutorial) corregido: scaffold ahora fusiona claves en vez de saltar (commit a447645)
- [ ] **PENDIENTE (Jesus, post-merge):** revisión del copy público de `site/` antes del deploy (gated); smoke opcional en box física; follow-ups menores (header "antigravity"→"agy" cosmético; trustedWorkspaces de subdirs de proyecto para `/first-project`)

---

## 6. Feedback (Jesus — post-implementacion)

### Bugs encontrados

—

### Mejoras sugeridas

—
