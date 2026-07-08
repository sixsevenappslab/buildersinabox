# FEAT-013: Migración del segundo CLI: Gemini CLI → Antigravity CLI (`agy`)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (bloquea el flip a público — decisión de Jesus 2026-07-09)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts de dispositivo (bash). La verificación automatizada es el dryrun harness; la validación real exige una pasada E2E en box headless física/VM (ver §4).
- **Reconciliation owner:** sdd-coordinator
- **Fase:** tecnica
- **Creado:** 2026-07-09
- **Actualizado:** 2026-07-09
- **Validado por Jesus:** [ ]

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
- [ ] Minimo 1 caso funcional en la tabla con pasos numerados y resultado verificable
- [ ] Minimo 1 edge case (input vacio/invalido/limite)
- [ ] Minimo 1 item de regresion (feature existente que NO debe romperse)
- [ ] Bloque `Criterios de testing` con comandos ejecutables (no pseudocodigo)

### Growth (§1.Growth Notes) — owner Andrea (solo si aplica)
- [ ] Canal + metrica + target, o marcado N/A explicito

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

> Pendiente de Andrea: la migración toca copy público (README + landing) y el mensaje multi-CLI del launch (Show HN / r/selfhosted). Definir cómo se cuenta "Claude o Antigravity" en la landing y si el dato "Gemini CLI murió el 18-jun" es utilizable como contenido.

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
| `payload/wizard/40-scaffold.sh` | MODIFICAR | `install_skill()`: symlink adicional al dir global de skills de agy (segun spike) |
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

### Dependencias

- **Binario `agy`** (Antigravity CLI, Go) — version pineada; fuente oficial Google (install.sh oficial o GitHub release, decide el spike). Sustituye a `@google/gemini-cli` (se deja de instalar).
- **Posibles paquetes apt** (solo ruta antigravity, si el spike los confirma necesarios): `gnome-keyring`, `libsecret-1-0`, `dbus-x11` — via `install/41-antigravity-cli.sh`, mismo patron apt que `install/00-base.sh`.
- Ninguna dependencia nueva en la ruta claude ni en el resto del stack.

### Tareas

**Wave 1 — Spike (GATE: si falla, el FEAT se replantea con Jesus antes de escribir una linea de Wave 2)**

<task id="T1">
SPIKE — validar agy E2E en VM headless Ubuntu 24.04 (multipass, mismo rig que FEAT-001). Verificar y documentar: (1) install oficial y como pinear version (¿env var de install.sh? ¿asset de GitHub release + checksum? naming exacto de assets); (2) `agy auth login` por SSH: ¿imprime URL + one-time code copiable? transcript literal; (3) persistencia del token tras logout/reboot SIN keyring y CON `gnome-keyring` headless (¿que unlock exige? ¿sobrevive a reboot con login por SSH key?); (4) discovery de skills: ¿lee `~/.agents/skills/`? ¿funciona symlink en `~/.gemini/config/skills/`? ¿`/tutorial` aparece en `/skills`?; (5) ¿`agy -i '/tutorial'` dispara la skill al abrir el TUI?; (6) rutas exactas de config/cache/credenciales para reset-for-gift; (7) comando de verificacion de login no interactivo (¿`agy auth status`? ¿round-trip `-p`?). Registrar resultados como addendum en `payload/docs/cli-skills-compatibility.md` y las decisiones en §5 de este FEAT.
<verify>Existe el addendum en `payload/docs/cli-skills-compatibility.md` con transcripts reales de la VM para los 7 puntos, y §5 "Decisiones tomadas" registra: metodo de pin elegido, mecanismo de persistencia validado (o veredicto NO-GO), ruta de skills confirmada y comando de verificacion de login.</verify>
<done>Los 7 interrogantes tienen respuesta empirica (no de blog); en particular, un `agy -p "reply OK"` (o equivalente) funciona en la VM tras un reboot sin re-login. Si la persistencia headless resulta inviable o exige degradacion de seguridad, el spike termina en NO-GO documentado y se para (Ask First a Jesus) — eso tambien cuenta como done.</done>
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
Copy publico + CI + reset. `README.md` (l.28, l.68) y `site/index.html` (l.57): sustituir la promesa de Gemini por Antigravity ("a Google account for Antigravity CLI" + nota honesta de requisitos) — el deploy de site/ queda gated por Jesus. `payload/test/dryrun.sh`: `BIB_AI_CLI="${BIB_AI_CLI:-claude}"`. `.github/workflows/ci.yml`: job `dryrun` con matrix `ai_cli: [claude, antigravity]` sobre ubuntu-latest con `BIB_OAUTH_MOCK=1` y `BIB_TMUX_LAUNCH_CMD=true` (si el runner no soporta el install completo, degradar a container/multipass y documentarlo en el propio yml). `tools/reset-for-gift.sh`: reemplazar rutas gemini por las rutas de agy confirmadas en T1 + limpieza del secreto del keyring (`secret-tool clear` o borrado del keyring file del usuario).
<verify>`grep -ri "gemini" README.md site/ tools/ .github/` == 0 hits; CI verde en la PR con ambos jobs de matrix pasando; en VM, tras login real de agy, ejecutar `tools/reset-for-gift.sh` y comprobar que `agy` vuelve a pedir login (token realmente purgado).</verify>
<done>Ninguna superficie publica promete Gemini CLI; un cambio futuro que rompa la ruta antigravity pone CI en rojo; una caja regalada no lleva el token de Google del maintainer dentro.</done>
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

1. `grep -ri gemini` sobre el arbol shippable (`git archive HEAD | tar -t` + grep de contenido) devuelve cero resultados — ni codigo, ni copy, ni comentarios.
2. En una VM/box headless Ubuntu 24.04 limpia: `install.sh --ai-cli=antigravity` completa el wizard entero desde Termius, y tras un **reboot** la sesion `ai-platform` arranca `agy` autenticado (sin re-login) con /tutorial en pantalla.
3. La misma pasada con `--ai-cli=claude` es indistinguible del comportamiento actual (regresion cero — verificable con el dryrun claude y la pasada E2E de §4).
4. CI en la PR: shellcheck + `bash -n` + personal-refs + archive-cleanliness + dryrun matrix `[claude, antigravity]`, todo verde.
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

> Pendiente — spawn sdd-qa después de §2.

---

## 5. Implementacion (Laura — se rellena durante la implementacion)

### Branch

`feat/FEAT-013`

### Progreso

| Task | Estado | Commit | Notas |
|------|--------|--------|-------|
| — | pendiente | — | — |

### Decisiones tomadas

- [2026-07-09] Opción B elegida por Jesus contra recomendación unánime del consejo (Claude-only): la promesa multi-CLI se arregla ANTES del launch, no se elimina.
- [2026-07-09] Descartado: auth por Gemini API key (no soportado upstream, issue #78). Descartado: bridge Slack/Telegram propio.

### Blockers

- [ ] —

### Verificacion post-implementacion

- [ ] Todos los `<verify>` de cada tarea pasan
- [ ] Dryrun harness pasa en ambas rutas (`claude` y `antigravity`)
- [ ] Criterios de aceptacion globales verificados
- [ ] Sin secrets en el diff
- [ ] Sin cambios fuera del scope
- [ ] shellcheck + `bash -n` sin errores

---

## 6. Feedback (Jesus — post-implementacion)

### Bugs encontrados

—

### Mejoras sugeridas

—
