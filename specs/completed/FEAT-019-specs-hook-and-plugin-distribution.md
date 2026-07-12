# FEAT-019: Specs visibles al arrancar sesión + skill de incidentes
# (ex "skills distribuidas como plugin" — Pieza 2 descartada 2026-07-12, ver banner abajo)

> Renumbered from FEAT-017 on 2026-07-12 — the FEAT-017 number was already
> owned by the browser-pack opt-in spec (in build). This is an unrelated
> feature; moved to the next free number (018 = quota coach).

> **DECISION 2026-07-12 — Pieza 2 (distribución por plugin) DESCARTADA.** Tras el spike de viabilidad
> (GO técnico en ambos CLIs pero valor marginal sobre copy+symlink: exige bumps de versión, dos copias
> físicas, divergencia agy sin `update`), Jesús optó por **mantener el copy+symlink preinstalado**. FEAT-019
> se cierra con **piezas 1 (SessionStart specs-hook) + 3 (skill `incident`) solamente**. Todo lo relativo a
> `.claude-plugin/`, `marketplace.json`, `payload/plugins/`, y la reescritura de la instalación de skills en
> el scaffold queda FUERA de scope. `biab add incident` usa el mecanismo de copia existente. Nota aparte
> (no bloqueante): el spike halló que `payload/docs/cli-skills-compatibility.md` está desactualizado (agy 1.0.13
> SÍ tiene `plugin install`); corregir ese doc en otro momento.

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (pre-flip — Jesús movió a pre-flip 2026-07-12)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts bash + config Claude Code. Verificación = box de prueba (o VM) con scaffold completo: disparar cada pieza en una sesión real.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** completado
- **Creado:** 2026-07-11
- **Actualizado:** 2026-07-12
- **Depende de:** FEAT-015 (default hooks — misma infraestructura de instalación de hooks del scaffold) · **FEAT-018 (quota coach — se implementa AHORA en `feat/FEAT-018-quota-coach`; FEAT-019 se rebasa encima, ver §2 "Acoplamiento crítico con FEAT-018")**

- **Validado por Jesus:** [x] (2026-07-12 — "018+019 ya"; pieza 2 descartada, merged #26, VM-verified)

---

## Definition of Ready (DoR)

### Producto (§1) — owner Elena
- [x] Problema explicito
- [x] Intent (why) rellenado
- [x] ≥1 historia de usuario
- [x] ≥3 requisitos funcionales EARS
- [x] Boundaries §3 con Always/Ask First/Never

### Spec Tecnica (§2) — owner Laura
- [x] Investigacion previa con rutas verificadas
- [x] Tabla archivos afectados
- [x] ≥1 task con verify/done
- [x] Patron de codigo real
- [x] Criterios globales verificables

### QA (§4) — owner Pablo
- [x] ≥1 funcional + ≥1 edge + ≥1 regresion
- [x] Criterios de testing ejecutables

### Growth (§1.Growth) — Andrea (si aplica)
- [ ] N/A probable (mejora de producto instalado; sin canal nuevo) — confirmar

---

## 1. Requisitos (Elena)

### Problema

Dos huecos que el upstream (ai-platform de Jesus, del que BIAB es la versión pública OSS) ya ha resuelto en su harness privado el 2026-07-11 y que aplican tal cual al box:

1. **Las specs SDD se vuelven invisibles.** BIAB shippea las skills `sdd-*` como core: el usuario acumula FEATs en `specs/draft|active` de sus proyectos, pero nada se las recuerda. En el upstream esto produjo drafts zombies de 40+ días detectados solo por una auditoría. La regla "menciona las specs pendientes al empezar" en prosa de CLAUDE.md es petición, no garantía — la versión determinista es un hook `SessionStart`.
2. **Las skills instaladas se congelan el día del install.** El scaffold copia `payload/skills/` a la config del usuario y ahí se quedan para siempre: un box instalado en julio nunca recibe las mejoras de skills de agosto. No hay canal de actualización. Claude Code ya tiene el mecanismo nativo para esto (plugins + marketplace git): empaquetar las skills bundled como plugin instalado desde el repo de BIAB da `claude plugin update` gratis.

Complemento menor (3): la práctica "log de incidentes" (ERR-NNN, qué se rompió y qué regla se aprendió) es parte de la práctica madura que BIAB dice heredar y hoy no se shippea.

### Intent (why)

La propuesta de valor de BIAB es "no heredas un agente en blanco, heredas una práctica madura" — y la práctica madura del upstream evoluciona. Este FEAT ataca las dos mitades de esa promesa: que la práctica **se vea** (specs pendientes en cada arranque de sesión, no enterradas) y que **siga viva después del install** (plugin actualizable en vez de copia congelada). Sin canal de updates, cada box instalado diverge del repo un poco más cada semana, y el proyecto OSS pierde su mejor argumento de retención.

### Solucion propuesta

1. **Hook `SessionStart` de specs pendientes** (5º hook del set de FEAT-015, mismo instalador): al arrancar/reanudar sesión, sube directorios desde cwd hasta encontrar `specs/draft|active`, y si hay FEATs pendientes inyecta un resumen como contexto (conteos, nombres, edad del draft más antiguo si >14 días). Silencioso si no hay specs. Mismo contrato FEAT-015: no-op degradado (sin `jq` → exit 0), nunca bloquea, en inglés. Portar de upstream `session-start-specs.sh` (traducir mensajes).
2. **Distribución de skills como plugin Claude Code:** añadir `.claude-plugin/marketplace.json` al repo BIAB (o repo hermano) empaquetando las skills bundled como plugin(s) siguiendo los grupos del `manifest.tsv` (core/optional). El wizard pasa de "copiar skills" a `claude plugin install <grupo>@buildersinabox`; `biab update` (o el propio Claude Code) trae versiones nuevas. Ruta Antigravity: mantener la copia actual como fallback documentado si agy no soporta plugins.
3. **Skill `incident` (opcional, grupo optional del manifest):** registra entradas ERR-NNN en un `INCIDENTS.md` del workspace del usuario (template embebido: síntoma, causa real, fix, regla aprendida). Versión genérica de la skill upstream (sin stratops).

### Historias de usuario

- Como usuario de BIAB que usa SDD, quiero ver al abrir sesión qué FEATs tengo en draft/active y cuáles llevan semanas paradas, para triarlas en vez de olvidarlas.
- Como usuario que instaló su box hace 3 meses, quiero recibir las mejoras de las skills bundled con un update normal, para que mi box no se quede anclado al día del install.
- Como mantenedor de BIAB, quiero publicar mejoras de skills sin pedir a los usuarios que re-instalen el box, para que el repo tenga un canal de mejora continua real.
- Como usuario, quiero un log de incidentes con template al que apuntar lo que se rompió, para acumular reglas aprendidas en vez de fixes aislados.

### Requisitos funcionales (EARS)

- [ ] **Event-driven:** Cuando una sesión de Claude Code arranca (startup/resume/clear) en un directorio con `specs/draft|active` no vacíos, el hook shall inyectar como contexto un resumen con conteos, nombres (máx. 6 por estado) y edad del draft más antiguo si supera 14 días.
- [ ] **Unwanted (silencio):** Si no hay carpeta specs o está vacía, el hook shall salir 0 sin emitir nada.
- [ ] **Optional (degradación):** Where `jq` no está disponible o el JSON de entrada es inválido, el hook shall ser no-op silencioso (exit 0), nunca bloquear la sesión.
- [ ] **Ubicuo:** El repo shall exponer un marketplace de plugins de Claude Code con las skills bundled agrupadas según `manifest.tsv` (core/optional), instalable con `claude plugin install`.
- [ ] **Event-driven:** Cuando el wizard configura Claude Code, el scaffold shall instalar las skills core vía plugin (con la copia actual como fallback si la instalación de plugin falla o el CLI elegido es Antigravity).
- [ ] **State-driven:** Mientras un box tenga el plugin instalado, `biab update` shall poder traer la última versión publicada de las skills sin tocar el resto del box.
- [ ] **Ubicuo (opcional):** El grupo optional shall incluir la skill `incident` que appendea entradas ERR-NNN con template fijo a `INCIDENTS.md` del workspace, asignando el número siguiente al máximo existente.

### Growth Notes (Andrea)

Probable N/A (mejora de producto instalado). Ángulo posible si se quiere: "your box updates its practice" como bullet de la landing post-flip — decidir en §1 review.

---

## 3. Boundaries (Always / Ask First / Never)

**Always:**
- Contrato de hooks FEAT-015: exit 0 salvo bloqueo intencional, degradación a no-op sin tooling, strings user-facing en inglés, desactivable por el usuario.
- Idempotencia del scaffold/wizard: re-ejecutar la instalación del plugin no duplica ni rompe.
- `shellcheck` + `bash -n` + personal-refs guard en CI como el resto del payload.

**Ask First:**
- Cambiar la estructura de grupos del `manifest.tsv` (core/optional) al mapearla a plugins.
- Publicar el marketplace en un repo separado del principal (afecta a la historia de instalación documentada).
- Cualquier copy nuevo en la landing derivado de esto.

**Never:**
- Telemetría o phone-home en el canal de updates (el update lo dispara el usuario; nada automático que llame fuera).
- Romper la ruta Antigravity: si agy no soporta plugins, la copia de skills actual se mantiene como ruta completa, no degradada.
- Borrar specs del usuario ni auto-archivar drafts viejos — el hook solo informa; triage es decisión del usuario.
- Tocar la política de red/SSH del box (fuera de scope).

---

## 2. Spec Técnica (Laura)

> ⚠️ **Acoplamiento crítico con FEAT-018 — leer antes de nada.**
> FEAT-018 (quota coach) se está implementando **ahora mismo** en la branch
> `feat/FEAT-018-quota-coach` y toca los mismos ficheros que FEAT-019:
> `payload/wizard/40-scaffold.sh` (añade un evento `UserPromptSubmit` al bloque
> jq de `install_hooks()`), `payload/skills/manifest.tsv` (añade `quota core`) y
> `payload/hooks/` (añade `biab-quota-nudge.sh` + casos en `tests/run-tests.sh`).
>
> **FEAT-019 se implementa DESPUÉS de FEAT-018 y se rebasa sobre él.** No se abre
> la branch de FEAT-019 hasta que FEAT-018 esté mergeado en `main`. Consecuencias
> concretas que la Pieza 2 (distribución por plugin) debe respetar:
> 1. La Pieza 2 **reescribe el mecanismo mismo de instalación de skills** (copia →
>    `claude plugin install`) del que depende `quota` de FEAT-018. El grupo de
>    plugin core debe seguir incluyendo `quota` — como el grupo se deriva de
>    `manifest.tsv` (que ya tendrá `quota core` tras FEAT-018), `quota` fluye al
>    plugin automáticamente. **No hardcodear la lista de skills del plugin:**
>    leerla del manifest o mantener el árbol del plugin como espejo del manifest.
> 2. El bloque jq de `install_hooks()` que edita la Pieza 1 (añadir `SessionStart`)
>    **debe conservar la clave `UserPromptSubmit` que FEAT-018 ya añadió** — merge
>    aditivo, nunca sobrescribir. Tras el rebase, el bloque `ours` de `install_hooks()`
>    contendrá PreToolUse + PostToolUse + Stop (FEAT-015) + UserPromptSubmit (FEAT-018)
>    + SessionStart (FEAT-019).
> 3. La skill `quota` de FEAT-018 es Claude-only (sus transcripts no existen en
>    Antigravity). En la ruta Antigravity de la Pieza 2 (que sigue siendo copia,
>    ver más abajo) `quota` se copia igual y responde con su mensaje de no-soporte:
>    comportamiento idéntico a FEAT-018, sin regresión.

### Investigación previa (rutas verificadas 2026-07-12)

**Upstream a portar/adaptar (leído, no copiar literal):**

- `ai-platform/core/claude-harness/hooks/session-start-specs.sh` — hook `SessionStart`
  de referencia para la Pieza 1. Sube desde `cwd` buscando `specs/draft|active`,
  imprime a stdout un resumen (conteos, nombres máx. 6, edad del draft más antiguo si
  >14 días). Ya hace `exit 0` en todo camino y degrada sin `jq`. **Diferencias a aplicar:**
  mensajes en inglés (hoy están en español + emoji), y adopción del esqueleto biab-*
  (`lib.sh`: `biab_hooks_disabled` kill-switch, `biab_read_stdin`, `biab_json`) en vez
  de su `set +e` + `jq` inline. La rama especial de "ai-platform root / core/specs" del
  upstream **se elimina** (es específica del monorepo de Jesús); el box solo tiene
  `specs/` por proyecto.
- `ai-platform/core/claude-harness/plugins/` — estructura marketplace+plugin de referencia
  para la Pieza 2. `.claude-plugin/marketplace.json` (name, owner, `plugins[]` con
  `{name, source: "./<dir>", description}`) + un dir de plugin `sdd-workflow/` con
  `.claude-plugin/plugin.json` (name, description, version, author) y un `skills/`
  con una carpeta `SKILL.md` por skill. **Hallazgo clave:** el plugin **duplica** las
  skills dentro de su árbol (`plugins/sdd-workflow/skills/<skill>/SKILL.md`), no las
  referencia. Para BIAB esto obliga a decidir el layout (ver Decisiones abiertas).
- `ai-platform/core/claude-harness/skills/incident/SKILL.md` — skill `incident` de
  referencia para la Pieza 3. **Fuertemente acoplada a stratops/mhserver:** ruta
  hardcodeada `~/ai-platform/stratops/ops/INCIDENTS.md`, formato de commit `docs(ops):`,
  referencias a "Jesús", EXEC-NNN, RUNBOOKS.md/DR.md. La versión BIAB debe ser genérica:
  sin stratops, sin nombres propios, sin convenciones de PR de mhserver, template
  embebido en la propia skill (el upstream delega el template a un fichero externo).

**CLI de plugins de Claude Code (verificado localmente con `claude plugin --help`):**

- `claude plugin marketplace add <source>` — `<source>` acepta **URL, path local, o
  repo de GitHub**. Flags: `--scope user|project|local` (default user), `--sparse <paths...>`
  (sparse-checkout para monorepos, p.ej. `--sparse .claude-plugin plugins`). El box
  instala desde un checkout git local en `/opt/buildersinabox` → **la fuente del
  marketplace puede ser ese path local**, lo que da install offline (sin red) y encaja
  con `biab update` (git pull del checkout).
- `claude plugin install <name>@<marketplace>` — `--scope user` (default) escribe en
  `~/.claude` → encaja con el modelo mono-usuario del box.
- `claude plugin update <name>` — trae la última versión (avisa "restart required").
- `claude plugin marketplace update [name]` — refresca el/los marketplace(s) desde su
  fuente.
- `claude plugin validate <path> --strict` — valida manifest de plugin/marketplace,
  exit 1 en warnings con `--strict` → **usable en CI**.

**Soporte de plugins en Antigravity (`agy`):** investigado vía
`payload/docs/cli-skills-compatibility.md` (spike FEAT-013 sobre agy 1.1.0) y grep del
payload. La superficie de agy es: carpetas `SKILL.md` bajo `~/.gemini/skills/` (dir
"Shared") + `settings.json`. **No hay ninguna evidencia de que agy soporte el mecanismo
de plugins/marketplace de Claude Code** (es específico de Claude Code: `claude plugin ...`
escribe en `~/.claude`, formato propio). **Conclusión operativa:** la ruta Antigravity
mantiene el mecanismo actual de copia+symlink (`install_skill`: copia a `~/.agents/skills`
→ symlink a `~/.gemini/skills`) **sin degradar** — es ruta completa, no fallback pobre
(Boundary "Never: romper la ruta Antigravity"). Confianza alta en que agy no tiene
plugins, pero **requiere una comprobación real en un box agy** antes de cerrar (ver
Decisiones abiertas c).

### Decisiones abiertas (Ask First — para Jesús)

Estas tres NO las decide Laura (§3 Boundaries las marca Ask First). Se listan con
recomendación; Jesús elige antes de implementar.

- **(a) ¿El marketplace vive en el repo BIAB o en un repo hermano?**
  Recomendación: **en el repo BIAB** (`.claude-plugin/marketplace.json`), fuente = path
  local del checkout `/opt/buildersinabox`. Ventajas: install offline, cero infra nueva,
  `biab update` (git pull) ya refresca la fuente. Contra: el árbol del plugin viaja en
  cada release. Repo hermano solo se justificaría si se quiere publicar el marketplace a
  usuarios de Claude Code fuera de BIAB — no es el caso hoy. **Riesgo a verificar:** que
  `claude plugin marketplace update` re-lea una fuente de tipo path-local (no solo repos
  git remotos). Si no lo hace, plan B: apuntar la fuente al **repo público de GitHub**
  (requiere red en `biab update`, aceptable) manteniendo `--sparse` para no clonar todo
  el payload.

- **(b) ¿Remapear la estructura core/optional del `manifest.tsv` a grupos de plugin?**
  Recomendación: **un solo plugin `biab-skills`** que agrupe todas las skills `core`
  (hoy todo es core), derivando la lista del propio `manifest.tsv`. El tier `optional`
  se reserva para grupos de plugin futuros (p.ej. `biab-incident`, Pieza 3), instalables
  con `biab add <group>` → `claude plugin install <group>@buildersinabox`. Esto conserva
  la semántica actual de `manifest.tsv` (core = instalado siempre, optional = opt-in) sin
  inventar una taxonomía nueva. **No** se propone reordenar ni renombrar tiers.

- **(c) ¿Antigravity soporta plugins?** Recomendación (safe default): **asumir que NO**
  y mantener para agy la copia+symlink actual como ruta completa. La copia es el default
  seguro. **Marcar que necesita comprobación real en un box agy** (spike corto: `agy` no
  expone `agy plugin ...` ni lee `~/.claude/plugins`). Si algún día agy soporta plugins,
  es FEAT propia; hoy no se toca su ruta.

### Tabla de archivos afectados

| Archivo | Cambio | Pieza |
|---------|--------|-------|
| `payload/hooks/biab-specs.sh` | **NUEVO** — hook `SessionStart`, esqueleto biab-*, strings en inglés (port de `session-start-specs.sh`) | 1 |
| `payload/hooks/tests/run-tests.sh` | +casos para el specs-hook (dispara / silencio / no-op sin jq) | 1 |
| `payload/wizard/40-scaffold.sh` | `install_hooks()`: +entrada `SessionStart` en el bloque jq (rebasado sobre el `UserPromptSubmit` de FEAT-018); reescritura de la instalación de skills (copia→plugin en Claude, copia en agy, fallback a copia) | 1, 2 |
| `.claude-plugin/marketplace.json` | **NUEVO** — marketplace del repo (Ask First: ubicación exacta — root vs `payload/`) declarando el/los grupo(s) de plugin | 2 |
| `payload/plugins/biab-skills/.claude-plugin/plugin.json` | **NUEVO** — manifest del plugin core (Ask First: layout — mover skills vs espejo del manifest) | 2 |
| `payload/plugins/biab-skills/skills/…` | **NUEVO/derivado** — skills core empaquetadas (derivadas de `manifest.tsv`; incluye `quota` de FEAT-018) | 2 |
| `payload/install/05-biab-command.sh` | `do_update()`: +`claude plugin marketplace update` + `claude plugin update`; `do_add()`: +caso que mapea grupo → `claude plugin install <group>@buildersinabox` | 2, 3 |
| `.gitattributes` | garantizar que el árbol del plugin y `marketplace.json` **shippean** (no caen en `specs/ export-ignore` ni similares) | 2 |
| `.github/workflows/ci.yml` | +paso `claude plugin validate --strict` sobre el marketplace/plugin (si el runner tiene `claude`; si no, validación de JSON con `jq -e`) | 2 |
| `payload/skills/incident/SKILL.md` | **NUEVO** — skill `incident` genérica en inglés (sin stratops), template embebido | 3 |
| `payload/skills/manifest.tsv` | +1 línea `incident	optional` | 3 |
| `docs/architecture.md` | canal de updates de skills (plugin+marketplace) | 5 |
| `payload/docs/cli-skills-compatibility.md` | anotar que la distribución por plugin es Claude-only; agy sigue por copia+symlink | 5 |
| `payload/docs/adopting-sdd.md` / README del payload | mención al canal de updates si nombran "las skills se copian" | 5 |

### Plan de tareas (waves — respetan el orden FEAT-018)

#### Wave 0 — Gate de rebase (bloqueante)

0. **No abrir la branch de FEAT-019 hasta que FEAT-018 esté mergeado en `main`.** Ramificar
   `feat/FEAT-019-...` desde ese `main`. Confirmar presencia de: `quota core` en
   `manifest.tsv`, la clave `UserPromptSubmit` en el bloque jq de `install_hooks()`, y
   `biab-quota-nudge.sh` en `payload/hooks/`.
   - verify: `grep -n 'quota' payload/skills/manifest.tsv` y `grep -n 'UserPromptSubmit' payload/wizard/40-scaffold.sh` devuelven las entradas de FEAT-018.
   - done: branch creada desde el `main` con FEAT-018 dentro; `git log` muestra el merge de FEAT-018 como ancestro.

#### Wave 1 — Pieza 1: hook `SessionStart` de specs (mínimo acoplamiento)

1. **`payload/hooks/biab-specs.sh`** — port de `session-start-specs.sh` al esqueleto biab-*:
   `source lib.sh`, `biab_hooks_disabled && exit 0`, `biab_read_stdin`, `cwd` vía
   `biab_json '.cwd'` (fallback `$PWD`), walk-up hasta `specs/draft|active`, resumen a
   stdout con conteos + nombres (máx 6, `paste -sd ', '`) + edad del más antiguo si >14 días.
   **Strings en inglés**, sin la rama `core/specs` del monorepo. `exit 0` en todo camino.
   - verify: `printf '{"cwd":"<dir con specs/draft>"}' | payload/hooks/biab-specs.sh` imprime el resumen; dir sin specs → sin salida, exit 0; sin `jq` en PATH → exit 0 sin salida.
   - done: `shellcheck -S warning` limpio; `bash -n` OK; exec bit; cero strings en español (personal-refs/no-Spanish guard).
2. **Registrar el hook en `install_hooks()`** (`40-scaffold.sh`): añadir al bloque jq `ours`
   la clave `SessionStart: [ { hooks: [ { type:"command", command: ($d + "/biab-specs.sh") } ] } ]`,
   **conservando** PreToolUse/PostToolUse/Stop (FEAT-015) y UserPromptSubmit (FEAT-018).
   Mantener el skip Antigravity (SessionStart es hook Claude-format).
   - verify: scaffold en box de prueba deja `SessionStart` en `~/.claude/settings.json` sin borrar los hooks previos (merge `. * $ours`); re-run idempotente (sin duplicados).
   - done: `bash -n 40-scaffold.sh` OK; `jq -e '.hooks.SessionStart and .hooks.UserPromptSubmit' settings.json` verdadero.
3. **Tests** en `payload/hooks/tests/run-tests.sh`: caso dispara-con-FEATs, caso silencio-sin-specs, caso no-op-sin-jq (usar el `make_min_path` existente sin `jq`).
   - verify: `bash payload/hooks/tests/run-tests.sh` verde incluyendo los nuevos casos.
   - done: harness pasa completo.

#### Wave 2 — Pieza 2: distribución por plugin (la reescritura grande; depende de Wave 0)

4. **Marketplace + plugin core** (tras decidir Ask First a+b): crear
   `.claude-plugin/marketplace.json` (name `buildersinabox`, owner, `plugins[]` con el grupo
   core) y el árbol del plugin `payload/plugins/biab-skills/` (`.claude-plugin/plugin.json`
   + `skills/` derivado de `manifest.tsv` — **incluye `quota`**). Validar layout con
   `claude plugin validate --strict`.
   - verify: `claude plugin validate .claude-plugin/marketplace.json --strict` y `claude plugin validate payload/plugins/biab-skills --strict` exit 0; el árbol del plugin lista exactamente las skills `core` del manifest.
   - done: JSON válido; `git archive HEAD | tar -t | grep plugins/` muestra que el árbol shippea (no export-ignored).
5. **Reescribir la instalación de skills en `40-scaffold.sh`**: para `scaffold_ai_cli == claude`
   → `claude plugin marketplace add <source> --scope user` (idempotente) + `claude plugin install biab-skills@buildersinabox --scope user`, ejecutado como el target_user
   (`sudo -u "$target_user"`, `HOME` correcto). **Fallback:** si cualquiera de esos comandos
   falla (o no hay `claude` en PATH, o falla pre-auth) → caer a la copia+symlink actual
   (`install_skill` del manifest). Para `antigravity` → **copia+symlink actual sin cambios**.
   - verify: box claude → `claude plugin list` muestra `biab-skills`; forzar fallo del plugin (PATH sin `claude`) → skills quedan por copia en `~/.claude/skills`; box agy → skills por symlink en `~/.gemini/skills` como hoy; re-run idempotente en las tres.
   - done: `bash -n` + `shellcheck` limpios; wiring-smoke claude+agy verde.
6. **`biab update` / `biab add`** en `05-biab-command.sh`: `do_update()` añade, tras el
   `git checkout`, `sudo -u <user> claude plugin marketplace update buildersinabox` +
   `claude plugin update biab-skills` (best-effort, no aborta si no hay plugin). `do_add()`
   mapea `<group>` → `claude plugin install <group>@buildersinabox` (con el caso `sdd`
   siguiendo como no-op amistoso).
   - verify: en box con plugin instalado, bump de versión del plugin en el repo → `biab update` trae la nueva versión (`claude plugin list` muestra el nuevo `version`); `biab add incident` instala el grupo optional.
   - done: `bash -n 05-biab-command.sh` + `shellcheck` limpios; `biab update` idempotente (sin plugin → mensaje claro, exit 0 en la parte de plugins).
7. **CI**: paso `claude plugin validate --strict` si el runner tiene `claude`; si no,
   fallback a `jq -e . .claude-plugin/marketplace.json` + `jq -e . payload/plugins/*/.claude-plugin/plugin.json`. Actualizar el paso `git archive cleanliness` si hace falta para no marcar el árbol del plugin como fuga.
   - verify: CI verde en la PR; el nuevo paso falla si se rompe el manifest a propósito.
   - done: workflow actualizado; `git archive HEAD | tar -t` limpio (sin maintainer paths, con el plugin dentro).

#### Wave 3 — Pieza 3: skill `incident` (grupo optional; depende de Wave 2 para el canal opt-in)

8. **`payload/skills/incident/SKILL.md`** — genérica en inglés: proceso (leer `INCIDENTS.md`
   del workspace → asignar `ERR-NNN` = máx existente +1 vía `grep -oE 'ERR-[0-9]+' | sort -V | tail -1`
   → append de entrada con template embebido: **Symptom / Root cause / Fix applied / Rule
   learned**, entrada más reciente arriba, actualizar "Last updated"). Sin stratops, sin
   nombres propios, sin convenciones de commit de mhserver. Ruta del log: `~/ai-platform/stratops/ops/INCIDENTS.md` (el scaffold ya crea `stratops/`; la skill hace `mkdir -p` de `ops/`
   y crea el fichero con cabecera + Template + Entries si no existe).
   - verify: en un workspace de prueba, invocar la skill dos veces crea `ERR-001` y luego `ERR-002` (número siguiente correcto); con un `INCIDENTS.md` que ya tiene `ERR-007`, la siguiente es `ERR-008`.
   - done: personal-refs/no-Spanish guard limpio; `manifest.tsv` con `incident optional`.
9. **`manifest.tsv`** +`incident	optional`; exponer el grupo en `do_add()` (Tarea 6).
   - verify: box por defecto NO instala `incident` (`claude plugin list` / `~/.claude/skills` sin ella); `biab add incident` la instala.
   - done: manifest actualizado; scaffold por defecto no la trae.

#### Wave final — Verificación global

10. `payload/hooks/tests/run-tests.sh` completo; `bash -n` de todos los `.sh` tocados;
    `shellcheck -S warning`; `claude plugin validate --strict`; scaffold end-to-end en box/VM
    de prueba (claude y antigravity); `payload/test/wiring-smoke.sh` matriz claude+agy; CI verde
    (shellcheck, bash -n, personal-refs, ssh-finalize, archive-cleanliness).

### Patrón de código a seguir (OBLIGATORIO)

- **Hook Pieza 1:** mismo esqueleto que `payload/hooks/biab-session-log.sh` /
  `biab-guardrail.sh` — `HOOK_DIR`/`source lib.sh`, `biab_hooks_disabled && exit 0`,
  `biab_read_stdin` + re-check, valores vía `biab_json`, degradación a no-op sin `jq`,
  `exit 0` en todo camino no bloqueante, strings en inglés. **No** copiar el `set +e` +
  `jq` inline del upstream: usar `lib.sh`.
- **Registro de hooks:** mismo patrón jq-merge de `install_hooks()` (FEAT-015) — construir
  `ours` con `jq -n`, mergear con `. * $ours` sobre el `settings.json` existente, nunca
  sobrescribir. Añadir `SessionStart` conservando `UserPromptSubmit` de FEAT-018.
- **Marketplace/plugin:** misma forma que `ai-platform/core/claude-harness/plugins/`
  (`.claude-plugin/marketplace.json` con `plugins[]`, plugin con `.claude-plugin/plugin.json`
  + `skills/`). Instalación por `claude plugin marketplace add` (path local) +
  `claude plugin install <name>@<marketplace>`.
- **`biab update`/`biab add`:** extender los `do_*()` existentes de `05-biab-command.sh`
  (best-effort, `exit 0` en la parte de plugins si no hay `claude`/plugin, mensajes en inglés).
- **Skill `incident`:** formato SKILL.md portable (frontmatter `name`+`description`, body
  self-contained), como el resto de `payload/skills/`.

### Criterios de aceptación (VERIFICABLES)

- [ ] `biab-specs.sh` inyecta el resumen cuando hay FEATs en `specs/draft|active`, guarda
      silencio sin specs, y es no-op (exit 0) sin `jq`.
- [ ] Tras el scaffold en un box claude, `~/.claude/settings.json` tiene `SessionStart`,
      `UserPromptSubmit` (FEAT-018), PreToolUse, PostToolUse y Stop simultáneamente (merge,
      no overwrite); re-run del scaffold no duplica entradas.
- [ ] Box claude: `claude plugin list` muestra el plugin core (incluida la skill `quota`);
      un bump de versión del plugin llega con `biab update`.
- [ ] Fallback: con el plugin install forzado a fallar (sin `claude` en PATH), las skills
      core quedan instaladas por la copia+symlink actual.
- [ ] Box Antigravity: ruta de skills idéntica a hoy (copia→`~/.agents/skills`→symlink
      `~/.gemini/skills`); el scaffold no intenta `claude plugin`.
- [ ] `incident` es optional: no se instala por defecto; `biab add incident` la trae; append
      asigna `ERR-NNN` = máx existente +1.
- [ ] CI completo verde; `claude plugin validate --strict` (o `jq -e` fallback) pasa; cero
      strings en español ni referencias personales en payload; `git archive` limpio con el
      árbol del plugin dentro.

---

## 4. QA (Pablo)

### Casos de prueba

#### Funcionales

1. **Specs-hook dispara** (Pieza 1): en un dir con `specs/draft/FEAT-A.md` + `specs/active/FEAT-B.md`,
   `printf '{"cwd":"<dir>"}' | payload/hooks/biab-specs.sh` imprime un resumen con los conteos
   (1 draft, 1 active) y los nombres; si el draft se antigua >14 días (touch con mtime viejo),
   el resumen incluye el aviso de "oldest".
2. **Plugin install + update** (Pieza 2): scaffold en box claude → `claude plugin list` muestra
   `biab-skills`; incluye la skill `quota` de FEAT-018. Bump de `version` en el `plugin.json` del
   repo + `biab update` → `claude plugin list` refleja la nueva versión.
3. **Incident asigna el número siguiente** (Pieza 3): con `INCIDENTS.md` que contiene `ERR-007`,
   la invocación crea `ERR-008` con el template completo (Symptom/Root cause/Fix/Rule learned),
   entrada más reciente arriba, "Last updated" al día. Sobre fichero inexistente, la primera
   entrada es `ERR-001` y se crea la cabecera.

#### Edge cases

4. **Specs-hook silencio sin specs**: dir sin `specs/` → sin salida, exit 0.
5. **Specs-hook no-op sin `jq`**: ejecutar con PATH mínimo sin `jq` (usar `make_min_path`) →
   exit 0, sin salida, nunca bloquea la sesión.
6. **Plugin install falla → fallback a copia**: forzar fallo (PATH del scaffold sin `claude`,
   o `claude plugin install` que retorna ≠0) → las skills core quedan instaladas por
   copia+symlink; la sesión funciona igual.
7. **Antigravity intacto**: box `ai_cli=antigravity` → el scaffold NO llama a `claude plugin`;
   skills por copia→`~/.agents/skills`→symlink `~/.gemini/skills`; `install_hooks` sigue haciendo
   skip de los hooks Claude-format (incluido `SessionStart`).
8. **`incident` no se instala por defecto**: box por defecto sin `incident` en skills/plugin;
   `biab add incident` la instala.

#### Regresión

9. **Suite de hooks intacta**: `payload/hooks/tests/run-tests.sh` completo pasa tras tocar
   `40-scaffold.sh` y añadir `biab-specs.sh` (guardrail/format/lint/session-log + el nudge de
   FEAT-018 siguen verdes).
10. **Merge de hooks preserva FEAT-015 + FEAT-018**: tras el scaffold, `settings.json` tiene
    `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit` (FEAT-018) y `SessionStart` (FEAT-019)
    a la vez; ninguno se pierde.
11. **Idempotencia del scaffold**: re-run no duplica entradas de hooks ni re-añade el marketplace
    (marketplace add / plugin install idempotentes); box con hooks/statusLine propios del usuario
    no se sobrescribe.
12. **Antigravity == FEAT-015/018**: scaffold agy sin errores nuevos; `quota` copiada responde con
    su mensaje de no-soporte (comportamiento FEAT-018).

### Criterios de testing (ejecutables)

```bash
# Sintaxis + lint de todo lo tocado
bash -n payload/hooks/biab-specs.sh payload/wizard/40-scaffold.sh payload/install/05-biab-command.sh
shellcheck -S warning payload/hooks/biab-specs.sh payload/install/05-biab-command.sh

# Suite de hooks (incluye los casos nuevos del specs-hook)
bash payload/hooks/tests/run-tests.sh

# Specs-hook: dispara / silencio / no-op sin jq
mkdir -p /tmp/qa/specs/draft && : > /tmp/qa/specs/draft/FEAT-A.md
printf '{"cwd":"/tmp/qa"}' | payload/hooks/biab-specs.sh            # → resumen
printf '{"cwd":"/tmp"}'    | payload/hooks/biab-specs.sh; echo "exit=$?"  # → sin salida, exit 0
PATH=/tmp/minpath printf '{"cwd":"/tmp/qa"}' | payload/hooks/biab-specs.sh; echo "exit=$?"  # → exit 0 sin salida

# Marketplace/plugin: validación (o jq -e si el runner no tiene claude)
claude plugin validate .claude-plugin/marketplace.json --strict
claude plugin validate payload/plugins/biab-skills --strict
jq -e . .claude-plugin/marketplace.json payload/plugins/biab-skills/.claude-plugin/plugin.json

# git archive: el árbol del plugin shippea, sin maintainer paths
git archive HEAD | tar -t | grep -E 'plugins/biab-skills' && echo "plugin ships"
git archive HEAD | tar -t | grep -E '(^|/)specs/' && echo "LEAK" || echo "clean"

# Wiring smoke por CLI (canary FEAT-013)
BIB_AI_CLI=claude       bash payload/test/wiring-smoke.sh
BIB_AI_CLI=antigravity  bash payload/test/wiring-smoke.sh

# Manual en box de prueba (claude): plugin instalado + update trae versión
sudo -u <user> claude plugin list
biab update && sudo -u <user> claude plugin list   # nueva versión tras bump
biab add incident && sudo -u <user> claude plugin list
```

---

## 5. Docs

Ficheros que necesitarán cambio de documentación:

- `docs/architecture.md` — describir el **canal de updates de skills** (marketplace + plugin,
  `biab update` refresca vía `claude plugin update`; ruta Antigravity por copia).
- `payload/docs/cli-skills-compatibility.md` — anotar que la distribución por plugin es
  **Claude-only**; agy sigue por copia+symlink `~/.agents/skills` → `~/.gemini/skills`.
- `payload/docs/adopting-sdd.md` y/o README del payload — actualizar cualquier frase que hoy
  diga "las skills se copian" para reflejar el plugin actualizable en boxes claude.
- `payload/install/05-biab-command.sh` (help inline de `biab update`/`biab add`) — mencionar
  el refresh de plugins y el nuevo grupo optional `incident`.
- Copy del tutorial (`payload/tutorial/`) — solo si menciona explícitamente la instalación de
  skills; revisar, probablemente sin cambio.

---

## 6. Feedback

_(vacío)_
