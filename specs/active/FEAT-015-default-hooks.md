# FEAT-015: Hooks por defecto (guardrail + formateo + lint + log de sesión)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (pre-launch — se anuncia en la propuesta de valor de la landing)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts + config de hooks de Claude Code. Verificación = disparar cada hook en una sesión real y observar el efecto.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** validacion
- **Creado:** 2026-07-11
- **Actualizado:** 2026-07-11
  <!-- QA §4 rellenada 2026-07-11 (Pablo) -->

- **Validado por Jesus:** [x] (2026-07-11)

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
- [x] Canal + metrica + target o N/A ("hooks" = ítem real de la propuesta de valor; N/A métrica directa)

---

## 1. Requisitos (Elena)

### Problema

La propuesta de valor de BIAB es "no heredas un agente en blanco, heredas una práctica madura". Hoy esa práctica son skills, pero **no hay hooks** — nada que actúe automáticamente sobre las acciones del agente (formatear, avisar de comandos peligrosos, devolver errores de lint, registrar la sesión). Un agente que corre desatendido desde el móvil se beneficia especialmente de guardarraíles y automatismos que no dependen de que el usuario esté mirando. Y no podemos anunciar "hooks" en la landing hasta que existan de verdad.

### Intent (why)

Jesus decidió (2026-07-11) construir hooks ANTES del flip para poder anunciarlos con verdad en la propuesta de valor (no como promesa futura). Encaja con dos pilares del producto: el **guardrail** extiende el "seguro por defecto" de la red a las acciones del agente (marca seguridad-primero), y formateo/lint/log elevan la calidad del trabajo desatendido. Es el diferenciador real (cualquiera monta tmux+Tailscale; nadie trae la práctica curada).

### Solucion propuesta

Shippar 4 hooks de Claude Code por defecto, instalados por el scaffold en la configuración del usuario, **agnósticos de lenguaje y con degradación a no-op** cuando la herramienta no existe:

1. **Guardrail (PreToolUse sobre Bash):** bloquea/avisa ante comandos destructivos (`rm -rf /` y variantes de raíz, `git push --force` a `main`/`master`, `curl|bash`/`wget|sh` de fuentes no confiables, `dd` a discos, `mkfs`). Bloqueo con mensaje claro; el agente recibe el motivo.
2. **Formateo al editar (PostToolUse sobre Edit/Write):** detecta el formatter del proyecto (prettier/black/gofmt/rustfmt/…) y formatea el fichero tocado. No-op si no hay formatter.
3. **Feedback de lint (PostToolUse):** corre el linter del proyecto tras editar y devuelve los errores al agente para autocorrección. No-op si no hay linter.
4. **Log de sesión (Stop):** registra un resumen de lo que hizo el agente en la sesión (ficheros tocados, comandos) en un log local, para auditar trabajo desatendido desde el móvil.

Compatibles con Antigravity donde el formato de hooks lo permita (agy conserva Hooks); si difiere, degradar en la ruta antigravity y documentarlo. Todos desactivables por el usuario.

### Historias de usuario

- Como usuario que deja al agente trabajando desde el móvil, quiero que un guardrail bloquee comandos destructivos, para no volver a una caja rota.
- Como usuario, quiero que el código que el agente edita salga ya formateado y sin errores de lint evidentes, para no revisar ruido.
- Como usuario, quiero un log de lo que el agente hizo en la sesión, para auditar el trabajo desatendido.
- Como lector de la landing, quiero que "hooks" sea algo que se instala de verdad, no una promesa.

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** El scaffold shall instalar los 4 hooks por defecto en la config del usuario, activos tras el setup.
- [ ] **Unwanted:** Si el agente intenta ejecutar un comando destructivo reconocido, el hook guardrail shall bloquearlo y devolver el motivo al agente.
- [ ] **Event-driven:** Cuando el agente edita/crea un fichero, el hook de formateo shall formatearlo con el formatter del proyecto si existe.
- [ ] **Event-driven:** Cuando el agente edita un fichero, el hook de lint shall correr el linter y devolver errores al agente si los hay.
- [ ] **Event-driven:** Cuando la sesión del agente para, el hook de log shall registrar un resumen local.
- [ ] **Optional (degradación):** Where el formatter/linter del proyecto no existe, el hook shall ser no-op silencioso (nunca romper la acción del agente).
- [ ] **Unwanted:** Si un hook falla o tarda demasiado, el sistema shall no bloquear ni corromper la acción del agente (fail-open salvo el guardrail, que es fail-closed por diseño).

### Requisitos no funcionales

- [ ] Agnóstico de lenguaje; degradación a no-op limpia.
- [ ] Desactivables por el usuario (documentado).
- [ ] Rápidos (no penalizar cada edición perceptiblemente).
- [ ] Idempotente; strings en inglés.

### Growth Notes (Andrea — si aplica)

- **Canal:** "hooks" pasa a ser un ítem real de la propuesta de valor (landing + README + Show HN). El guardrail refuerza el mensaje seguridad-primero. Métrica: N/A directa; es diferenciador de producto.

---

## 2. Spec Tecnica (Laura)

### 2.0 Investigacion previa (rutas verificadas)

- **Instalación de skills/config hoy:** `payload/wizard/40-scaffold.sh` copia skills a `~/.agents/skills/` y las symlinkea a `~/.claude/skills/<name>` (y `~/.gemini/skills/` en cajas antigravity). El único `settings.json` que se pre-siembra hoy es el de **agy** (`~/.gemini/antigravity-cli/settings.json`, líneas 174-188) vía `jq '. * $ours'` (merge: nuestras claves ganan, las de agy sobreviven). **No existe hoy ningún `~/.claude/settings.json` sembrado** (`find payload -name settings.json` → vacío; grep confirma que solo se referencia el de agy). → Los hooks de Claude Code necesitan que sembremos ese fichero nuevo.
- **Helpers disponibles** (`payload/lib/common.sh`): `log/warn/die`, `state_get '.ai_cli'`, `phase_is_done/phase_done`. `jq` está garantizado (lo instala `payload/install/00-base.sh` línea 15: `apt_install ... jq ...`).
- **CI** (`.github/workflows/ci.yml`): `shellcheck -S warning` corre sobre **todos** los `*.sh` del repo vía `find` → los scripts de hook se lintarán automáticamente, sin tocar CI. También `bash -n` a entry points y guard de refs personales.
- **`.gitattributes`:** `specs/` es `export-ignore` (no shippa). `payload/hooks/` **sí** shippará (no está marcado) — correcto, es contenido de la caja. No añadir `payload/hooks/` a export-ignore.
- **`biab add` / update** (`payload/install/05-biab-command.sh`): `biab update` hace git-sync de `/opt/buildersinabox`. Los scripts de hook se **referencian por ruta absoluta a `/opt/buildersinabox/payload/hooks/`** (no se copian a `~`), así que `biab update` los refresca solos — importante para el guardrail (parche de seguridad sin re-scaffold).

### 2.1 Formato de hooks confirmado (fuente: docs oficiales)

Fuente: `https://code.claude.com/docs/en/hooks` (301 desde `docs.claude.com/en/docs/claude-code/hooks`), consultado 2026-07-11. Estructura EXACTA en `settings.json`:

```json
{
  "hooks": {
    "PreToolUse":  [ { "matcher": "Bash",       "hooks": [ { "type": "command", "command": "/abs/path/biab-guardrail.sh" } ] } ],
    "PostToolUse": [ { "matcher": "Edit|Write",  "hooks": [ { "type": "command", "command": "/abs/path/biab-format.sh" },
                                                             { "type": "command", "command": "/abs/path/biab-lint.sh" } ] } ],
    "Stop":        [ {                            "hooks": [ { "type": "command", "command": "/abs/path/biab-session-log.sh" } ] } ]
  }
}
```

Puntos confirmados por la doc que fijan el diseño:

- **stdin (JSON):** todo evento de tool recibe `{ session_id, transcript_path, cwd, permission_mode, hook_event_name, tool_name, tool_input:{...} }`. Para Bash → `tool_input.command`; para Edit/Write → `tool_input.file_path`. Stop recibe `session_id`, `transcript_path`, `cwd` (sin `tool_input`).
- **Matcher:** `"Bash"` (exacto) y `"Edit|Write"` (lista con pipe) son sintaxis válida literal de la doc. Sin matcher (omitido) = dispara en todo → usado en Stop.
- **PreToolUse bloquea de dos formas** — elegimos la **JSON `permissionDecision`** (exit 0) sobre exit-2 porque el motivo se muestra limpio a Claude y no aparece como "hook error":
  ```json
  { "hookSpecificOutput": { "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Destructive command blocked by Builders in a Box guardrail: <patrón>" } }
  ```
  `permissionDecision` admite `deny` (bloquea), `ask` (pregunta al usuario), `allow`. Si el hook hace `exit 0` **sin** JSON → flujo de permisos normal (no decide). Este es el no-op del guardrail para comandos benignos.
- **Feedback al agente (PostToolUse, fail-open):** exit 0 con
  ```json
  { "hookSpecificOutput": { "hookEventName": "PostToolUse",
      "additionalContext": "<salida del linter>" } }
  ```
  `additionalContext` se inyecta en el siguiente turno del modelo — canal **no bloqueante** ideal para el lint (el agente ve los errores y autocorrige sin que la edición falle). exit-2/stderr sería bloqueante → **no** lo usamos en format/lint (violaría fail-open).
- **Exit codes:** `0` = éxito (stdout se parsea como JSON si lo hay); `2` = error bloqueante (stderr → Claude, acción bloqueada); **otro** = error no-bloqueante (`<hook> hook error` + primera línea de stderr, la ejecución continúa). → Los hooks fail-open (format/lint/log) terminan siempre en `exit 0`; un fallo interno degrada a no-op, nunca a `exit 2`.

### 2.2 Dónde viven los scripts y cómo se instalan

**Nuevo directorio `payload/hooks/`** (hermano de `payload/skills/`, `payload/bashrc.d/`). Los 4 scripts + una `lib.sh` compartida viven ahí y **se referencian por ruta absoluta** desde `~/.claude/settings.json` (no se copian a `~`). Razones:

1. Fuente única + `biab update` (git-sync de `/opt/buildersinabox`) refresca el guardrail sin re-scaffold (crítico para seguridad; los skills copiados a `~` NO se refrescan con la lógica idempotente actual — problema que aquí evitamos).
2. Menos superficie en `~`; desactivar = editar/quitar el bloque en `settings.json` (documentado), sin residuos.

La ruta absoluta se calcula en tiempo de seed con `$PAYLOAD_DIR` (el scaffold ya lo tiene, línea 14) → robusto ante cualquier prefijo de instalación, no hardcodea `/opt`.

**Seeding de `~/.claude/settings.json`** — nuevo paso `install_hooks()` en `40-scaffold.sh`, espejo del merge de agy (líneas 178-187):

```bash
# ---------------------------------------------------------------------------
# Seed Claude Code hooks: guardrail + format + lint + session log.
# Mirrors the agy settings merge — our `hooks` key wins, the user's other
# settings survive. Scripts are referenced by absolute path so `biab update`
# refreshes them in place. Claude Code only: agy's hook format differs (2.5).
# ---------------------------------------------------------------------------
install_hooks() {
    local hooks_src="${PAYLOAD_DIR}/hooks"
    [[ -d "$hooks_src" ]] || { warn "40-scaffold: payload/hooks/ missing, skipping hooks"; return 0; }
    if [[ "$scaffold_ai_cli" == "antigravity" ]]; then
        log "40-scaffold: antigravity box — Claude-format hooks not applicable, skipping (see FEAT-015 §2.5)"
        return 0
    fi
    chmod +x "$hooks_src"/*.sh 2>/dev/null || true   # git preserves +x, belt-and-braces
    local claude_dir="${target_home}/.claude"
    local settings="${claude_dir}/settings.json"
    mkdir -p "$claude_dir"
    local ours
    ours="$(jq -n --arg d "$hooks_src" '{
      hooks: {
        PreToolUse:  [ { matcher: "Bash",      hooks: [ { type: "command", command: ($d + "/biab-guardrail.sh") } ] } ],
        PostToolUse: [ { matcher: "Edit|Write", hooks: [ { type: "command", command: ($d + "/biab-format.sh") },
                                                          { type: "command", command: ($d + "/biab-lint.sh") } ] } ],
        Stop:        [ {                         hooks: [ { type: "command", command: ($d + "/biab-session-log.sh") } ] } ]
      } }')"
    if [[ -f "$settings" ]] && jq -e . "$settings" >/dev/null 2>&1; then
        printf '%s\n' "$(jq --argjson ours "$ours" '. * $ours' "$settings")" > "$settings"
    else
        printf '%s\n' "$ours" > "$settings"
    fi
    log "40-scaffold: seeded Claude hooks at $settings"
}
```

Se llama junto al resto del scaffold; el `chown -R ... "${target_home}/.claude"` que ya existe (línea 259) cubre el nuevo `settings.json`. Idempotente: re-ejecutar reescribe el mismo `.hooks` (merge determinista). **Nota merge:** `. * $ours` reemplaza los arrays `.hooks.PreToolUse/PostToolUse/Stop` por completo (jq `*` en arrays = gana el de la derecha) pero conserva otras claves de settings y otros eventos de hook que el usuario hubiera añadido. Aceptable: el scaffold corre una vez (`phase_is_done`).

### 2.3 Detección agnóstica de formatter/linter (no-op si nada)

`lib.sh` expone `biab_have <bin>` (`command -v`, con preferencia por `node_modules/.bin/` local vía `cwd`). Cada hook lee `cwd` de stdin y hace `cd "$cwd"` para resolver binarios y config locales. Mapeo por extensión de `tool_input.file_path`:

| Ext | Formatter (biab-format) | Linter (biab-lint, additionalContext) |
|-----|-------------------------|----------------------------------------|
| `.js .jsx .ts .tsx .json .css .md .yaml` | `prettier --write` (prefiere `node_modules/.bin/prettier`) | `eslint --format compact` **solo si hay config** (`.eslintrc*`/`eslint.config.*`) |
| `.py` | `black` → si no, `ruff format` | `ruff check` → si no, `flake8` |
| `.go` | `gofmt -w` | `gofmt -l` (+ `go vet` si el paquete compila, best-effort) |
| `.rs` | `rustfmt` | `clippy-driver`/`cargo clippy` solo si presente (best-effort) |
| `.sh` | `shfmt -w` si presente | `shellcheck -f gcc` |

**Regla de oro (no-op limpio):** si el binario no resuelve → `exit 0` sin tocar el fichero ni emitir contexto. Extensión desconocida → no-op. El formatter nunca corre si falta la herramienta (nunca deja el fichero a medias). Todo termina en `exit 0` (fail-open).

### 2.4 Guardrail — lógica y lista inicial (Ask First para Jesus)

`biab-guardrail.sh` lee `tool_input.command`, lo normaliza (colapsa espacios) y lo compara contra una tabla de patrones. **Match → `permissionDecision: "deny"`** con motivo citando el patrón. **Sin match → `exit 0`** (no-op, flujo normal). **Fail-closed acotado:** si `jq` no puede parsear stdin o el comando es ininteligible → `permissionDecision: "ask"` (ni deny ciego que bloquearía todo por un bug, ni allow silencioso que dejaría pasar un `rm -rf /`). Un bug del script nunca abre la puerta a lo destructivo, pero tampoco brickea la caja.

**Lista inicial propuesta (PENDIENTE de fijar por Jesus — §3 Ask First):**

1. **Borrado recursivo de raíz:** `rm` con `-rf`/`-fr`/`-r -f` sobre `/`, `/*`, `~`, `$HOME`, o con `--no-preserve-root`.
2. **Destructores de disco/FS:** `mkfs.*`, `wipefs`, `dd ... of=/dev/sd*|/dev/nvme*|/dev/disk*`, `> /dev/sd*`, `parted`/`fdisk`/`sgdisk` con escritura no interactiva.
3. **Fork bomb:** `:(){ :|:& };:` (y variantes).
4. **Remote-a-shell privilegiado:** `curl|wget ... | sudo bash|sh` (código remoto no verificado → shell root). `curl|bash` sin sudo se **degrada a `ask`** (es como se instala BIAB — evitar falso positivo duro).
5. **Permisos suicidas en raíz:** `chmod -R 777 /`, `chown -R ... /`, `chmod -R 000 /`.
6. **Force-push a rama protegida:** `git push --force`/`-f` a `main`/`master`/`origin HEAD:main`. `--force-with-lease` en rama de feature se **degrada a `ask`** (evitar bloquear el flujo normal de rebase).

Riesgo de falsos positivos: (1)(2)(3)(5) son inequívocamente destructivos → `deny`. (4)(6) tienen usos legítimos → `ask` en los casos ambiguos. Jesus fija la línea final antes de implementar.

### 2.5 Compatibilidad Antigravity — DEGRADAR + documentar

El formato de hooks de agy **no** es el `settings.json` de Claude Code (agy conserva un concepto "Hooks" pero su esquema es distinto y hoy sub-documentado; además en caja antigravity puede que Claude Code ni esté instalado). **Decisión:** en la ruta `ai_cli == antigravity`, `install_hooks()` hace no-op y loguea el skip (ver snippet §2.2). Los 4 hooks son **Claude Code-only en este FEAT**; portar el guardrail al formato de agy es un FEAT futuro. Se documenta en §5/README para no prometer hooks en cajas antigravity.

### 2.6 Log de sesión (Stop) — local, sin secretos

`biab-session-log.sh` (matcher vacío → Stop) lee `session_id`, `cwd`, `transcript_path` de stdin y **añade una línea sanitizada** a `~/.claude/logs/biab-sessions.log` (modo `0600`, append-only). Contenido: `timestamp \t session_id \t cwd \t <nº edits> \t <nº bash> \t <basenames de ficheros tocados>`. **Nunca** registra: strings de comandos, contenido de ficheros, variables de entorno, tokens (los comandos pueden llevar secretos). Los contadores/basenames se extraen best-effort del `transcript_path` (grep de `tool_use` por nombre); si el parseo falla → registra solo timestamp+session+cwd y `exit 0` (fail-open). Sin telemetría, sin salida de la caja (§3 Never). Crecimiento del log: se deja nota TODO para logrotate en v0.2 (no bloqueante).

### 2.7 Desactivar (documentado)

- **Todos los hooks:** quitar la clave `hooks` de `~/.claude/settings.json` (o el matcher-group concreto).
- **Kill-switch sin editar JSON:** `lib.sh` chequea al arrancar `BIAB_HOOKS_DISABLED=1` (env) o el sentinel `~/.claude/hooks-disabled`; si existe, todos los hooks hacen no-op inmediato (`exit 0`). Barato y reversible.

### 2.8 Archivos afectados

| Archivo | Acción | Nota |
|---------|--------|------|
| `payload/hooks/lib.sh` | NEW | Helpers: `biab_disabled`, `biab_have`, lectura segura de stdin, `cd $cwd`. `set -euo pipefail`. |
| `payload/hooks/biab-guardrail.sh` | NEW | PreToolUse/Bash. `permissionDecision deny/ask`. Fail-closed acotado. |
| `payload/hooks/biab-format.sh` | NEW | PostToolUse/Edit\|Write. Formatter agnóstico, no-op, fail-open. |
| `payload/hooks/biab-lint.sh` | NEW | PostToolUse/Edit\|Write. Linter → `additionalContext`. Fail-open. |
| `payload/hooks/biab-session-log.sh` | NEW | Stop. Log local 0600 sanitizado. |
| `payload/hooks/tests/*.bats`/`*.sh` | NEW | Harness de stdin fixtures por hook (usado en T3/T4/T5). |
| `payload/wizard/40-scaffold.sh` | EDIT | Añadir `install_hooks()` + su llamada (§2.2). |
| `payload/tutorial/desktop-readme.md` (o `whats-ahead` skill) | EDIT | Doc user-facing: qué hacen los hooks + cómo desactivar (§5, sdd-docs). |
| `.github/workflows/ci.yml` | SIN CAMBIO | shellcheck ya barre `payload/hooks/*.sh` vía `find`. |
| `.gitattributes` | SIN CAMBIO | `payload/hooks/` debe shippar; no marcar export-ignore. |

### 2.9 Plan de tareas (waves)

**Wave 1 — scripts**

- [ ] **T1. Crear `payload/hooks/` (lib.sh + 4 scripts, esqueleto + no-op/degradación).**
  Todos con `set -euo pipefail`, kill-switch (`BIAB_HOOKS_DISABLED`/sentinel), lectura de stdin con jq y fallback, `cd $cwd`. Strings en inglés.
  - *verify:* `shellcheck -S warning payload/hooks/*.sh` limpio; `for f in payload/hooks/*.sh; do bash -n "$f"; done` OK; `printf '{}' | payload/hooks/biab-format.sh; echo $?` → `0`.
  - *done:* 5 ficheros existen, con bit `+x`, shellcheck verde, cada script hace `exit 0` con stdin vacío/`{}`.

- [ ] **T2. Guardrail: patrones + decisión JSON (implementa la lista §2.4 propuesta; marcar en el PR que Jesus la valide).**
  - *verify:* `echo '{"tool_input":{"command":"rm -rf / --no-preserve-root"}}' | payload/hooks/biab-guardrail.sh | jq -r '.hookSpecificOutput.permissionDecision'` → `deny`; `echo '{"tool_input":{"command":"ls -la"}}' | payload/hooks/biab-guardrail.sh; echo $?` → `0` sin stdout; `echo 'garbage' | payload/hooks/biab-guardrail.sh | jq -r '.hookSpecificOutput.permissionDecision'` → `ask`.
  - *done:* cada patrón de §2.4 tiene un caso en `tests/` (deny) + un benigno cercano que NO dispara (p.ej. `rm -rf ./build` → allow); `curl|bash` sin sudo → `ask`.

**Wave 2 — format/lint/log**

- [ ] **T3. Formateo + lint agnósticos con no-op (§2.3).**
  - *verify (tool presente):* con `black` instalado, Edit sobre un `.py` desalineado → fichero queda formateado; `biab-lint.sh` sobre `.py` con error → stdout JSON con `additionalContext` no vacío.
  - *verify (no-op):* ejecutar con `PATH=/usr/bin` sin formatter/linter (o binario ausente) → `exit 0`, fichero **sin cambios**, sin stdout.
  - *done:* tabla §2.3 cubierta para ≥3 lenguajes (py, js/ts, sh) + prueba de no-op con herramienta ausente.

- [ ] **T4. Log de sesión sanitizado (§2.6).**
  - *verify:* `printf '{"session_id":"t","cwd":"/tmp","transcript_path":"/nonexistent"}' | biab-session-log.sh` → añade 1 línea a `~/.claude/logs/biab-sessions.log`; `stat -c %a` del log → `600`; `grep -Ei 'token|password|BEGIN|sk-|command' logs/biab-sessions.log` → vacío.
  - *done:* fichero 0600, append-only, sin strings de comandos/entorno; parseo de transcript inexistente degrada a línea mínima + `exit 0`.

**Wave 3 — wiring + verificación E2E**

- [ ] **T5. Seeding en `40-scaffold.sh` (`install_hooks()`, §2.2) + doc de desactivar.**
  - *verify:* correr el scaffold contra un `HOME` fixture con `ai_cli=claude` → `jq -e '.hooks.PreToolUse[0].hooks[0].command' ~/.claude/settings.json` apunta al abs path real de `biab-guardrail.sh`; segunda corrida → `git diff`/hash del `.hooks` idéntico (idempotente); con `ai_cli=antigravity` → **no** se crea `~/.claude/settings.json` y el log dice "skipping".
  - *done:* `settings.json` sembrado con 3 eventos y comandos abs-path; idempotente; ruta agy degradada y logueada; doc de desactivar en el README user-facing.

- [ ] **T6. Verificación disparando cada hook en una sesión Claude real/simulada.**
  - *verify:* en una sesión `claude` sobre la caja (o `claude -p` headless con los hooks activos): (a) pedir `rm -rf /tmp/biab-test --no-preserve-root` → **bloqueado** con el motivo del guardrail; (b) editar un `.py` → sale formateado y el lint aparece como contexto; (c) editar un fichero de ext sin toolchain → sin ruido; (d) terminar la sesión → línea nueva en `biab-sessions.log`. Además `bash payload/test/wiring-smoke.sh` (matriz claude/antigravity) y `shellcheck -S warning payload/hooks/*.sh` verdes.
  - *done:* los 4 hooks observados en efecto real; CI local verde (shellcheck + bash -n + archive-clean); caja antigravity confirma degradación documentada.

---

## 3. Boundaries

### Always
- Hooks agnósticos de lenguaje, no-op limpio si falta la herramienta.
- Fail-open en formateo/lint/log (nunca romper la acción del agente); fail-closed **acotado** solo en el guardrail (match→deny, parse-error→ask, nunca deny-ciego que bloquee todo).
- Desactivables y documentados (quitar clave `hooks` en `settings.json`, o kill-switch `BIAB_HOOKS_DISABLED`/sentinel).
- `set -euo pipefail`, idempotente, inglés.
- Instalar vía el scaffold existente (`40-scaffold.sh`), sembrando `~/.claude/settings.json`.
- Scripts referenciados por ruta absoluta a `payload/hooks/` (fuente única; `biab update` refresca el guardrail sin re-scaffold).

### Ask First
- La lista exacta de comandos que el guardrail bloquea (§2.4 propone una inicial; falsos positivos molestan, falsos negativos son peligrosos) — revisión de Jesus antes de fijarla. Concretamente: si `curl|bash` sin sudo y `git push --force-with-lease` en feature van a `ask` (propuesto) o se dejan pasar.
- Cualquier hook que envíe datos fuera de la caja (el log es LOCAL; nada de telemetría sin OK explícito).
- Desplegar copy de `site/` (gate de Jesus).

### Never
- Telemetría o envío de datos del usuario fuera de la caja.
- Un guardrail tan agresivo que rompa flujos normales (bloquear solo lo inequívocamente destructivo; lo ambiguo → `ask`).
- Hooks que dependan de un lenguaje concreto sin degradar.
- Persistir secretos en el log de sesión (ni strings de comandos, ni contenido de ficheros, ni env/tokens — solo timestamp, session_id, cwd, contadores y basenames).
- Format/lint que usen `exit 2` (bloquearían la edición → viola fail-open); solo `permissionDecision`/exit-2 en el guardrail.
- Prometer hooks en cajas antigravity en este FEAT (Claude Code-only; ver §2.5).
- Flip a público dentro de este FEAT.

### Riesgos detectados (§2)
1. **Falsos positivos del guardrail** rompen el flujo normal → mitigado con `ask` para casos ambiguos (`curl|bash` sin sudo, `--force-with-lease`); lista final la valida Jesus.
2. **Rendimiento por edición:** format+lint corren en cada Edit/Write. Riesgo de latencia perceptible en repos grandes → format solo sobre el fichero tocado, lint acotado al fichero, no-op rápido si no hay toolchain. QA debe medir.
3. **Antigravity sin hooks:** las cajas agy quedan sin guardrail hasta un FEAT de portado — el mensaje "seguro por defecto" es Claude-only por ahora; documentarlo para no sobreprometer.

---

## 4. QA (Pablo)

### 4.0 Estrategia

Son 4 scripts bash de hook + un merge de config JSON. La verificación se hace en dos planos:

1. **Contrato del hook (aislado, reproducible en CI-local):** cada hook es una caja `stdin JSON → exit code + stdout JSON`. Se dispara con `printf '<json>' | hook.sh`, se inspecciona `$?` y se parsea el stdout con `jq`. Esto es determinista y no necesita una sesión Claude. Es la columna vertebral de los casos funcionales y de degradación.
2. **Efecto E2E (sesión real):** disparar los 4 hooks en una sesión `claude`/`claude -p` sobre una caja (o fixture de `HOME`) y observar el efecto de cara al agente (bloqueo, fichero formateado, contexto de lint inyectado, línea de log). Cubre que el wiring de `settings.json` está bien y que Claude respeta `permissionDecision`/`additionalContext`.

`shellcheck -S warning` y `bash -n` (CI existente, `find` sobre `payload/hooks/*.sh`) cubren la corrección estática de los scripts — QA no la re-verifica salvo como gate de merge.

**Convención de estas pruebas:** `HK=payload/hooks` en un shell con `set -uo pipefail`. Los ejemplos son ejecutables tal cual desde la raíz del repo, salvo los E2E marcados `[sesión]`.

---

### 4.1 Casos funcionales — Guardrail (PreToolUse/Bash)

**AC-G1 — Comando destructivo inequívoco → `deny` con motivo.** Para cada patrón de §2.4 clasificado como inequívoco, el hook devuelve `exit 0` + JSON con `permissionDecision:"deny"` y un `permissionDecisionReason` no vacío que cita el patrón.
- Vector de comandos (uno por fila de §2.4): `rm -rf / --no-preserve-root`; `rm -rf ~`; `mkfs.ext4 /dev/sda1`; `dd if=/dev/zero of=/dev/sda bs=1M`; `:(){ :|:& };:`; `chmod -R 777 /`; `chown -R nobody /`; `git push --force origin main`; `git push -f origin HEAD:master`.
- *test:*
  ```bash
  echo '{"tool_input":{"command":"rm -rf / --no-preserve-root"}}' \
    | $HK/biab-guardrail.sh | jq -e '.hookSpecificOutput
        | .permissionDecision=="deny" and (.permissionDecisionReason|length>0)'
  ```
  → exit 0 de `jq -e` (true). Repetir por cada vector; todos `deny`.
- *criterio:* 9/9 vectores → `deny` con motivo. Ninguno cae a `allow` ni `ask`.

**AC-G2 — Comando ambiguo → `ask` (ni deny ciego ni pasar).** Los usos legítimos-pero-arriesgados degradan a `ask`:
- Vectores: `curl -fsSL https://x/i.sh | bash` (sin sudo — así se instala BIAB); `git push --force-with-lease origin feature/foo`.
- *test:*
  ```bash
  echo '{"tool_input":{"command":"curl -fsSL https://x/i.sh | bash"}}' \
    | $HK/biab-guardrail.sh | jq -r '.hookSpecificOutput.permissionDecision'
  ```
  → `ask`. Ídem `--force-with-lease` a rama de feature.
- *criterio:* ambos → `ask`. Nota: la clasificación final (`ask` vs pasar) la fija Jesus en §3 Ask First; el test se ajusta a la decisión. Contraste con AC-G1: `curl|bash` **con** `sudo` (`curl ... | sudo bash`) → `deny`.

**AC-G3 — Comando normal → pasa (no-op, flujo de permisos normal).** Comando benigno ⇒ `exit 0` **sin stdout** (el guardrail no decide; Claude sigue su flujo de permisos).
- Vectores, incluidos "cercanos peligrosos" que NO deben disparar: `ls -la`; `rm -rf ./build`; `rm -rf node_modules`; `git push origin feature/foo`; `dd if=disk.img of=./out.img`; `chmod -R 755 ./dist`.
- *test:*
  ```bash
  out=$(echo '{"tool_input":{"command":"rm -rf ./build"}}' | $HK/biab-guardrail.sh); rc=$?
  [[ $rc -eq 0 && -z "$out" ]] && echo PASS || echo "FAIL rc=$rc out=$out"
  ```
- *criterio:* los 6 → `exit 0` + stdout vacío. **Cero falsos positivos** en la lista de cercanos (riesgo #1 de §3). Este AC es la red anti-falso-positivo: `rm -rf ./build` es el caso canónico que NO puede bloquearse.

**AC-G4 — Contrato de entrada (`tool_input.command`, exit 0 + JSON válido).** El guardrail lee el campo correcto y su stdout, cuando existe, es JSON parseable con la forma exacta de §2.1.
- *test:* para un vector `deny`, `... | jq -e '.hookSpecificOutput.hookEventName=="PreToolUse"'`. Y verificar que se lee `tool_input.command` (no otro campo): un JSON con `command` en otra ruta (`{"command":"rm -rf /"}` sin `tool_input`) NO debe disparar `deny` (no es el contrato) → cae al camino parse/campo-ausente (ver AC-G5).

---

### 4.2 Casos funcionales — Formateo (PostToolUse/Edit|Write) + Log (Stop)

**AC-F1 — Proyecto CON formatter → el fichero se formatea.** En un dir con `black` disponible, un `.py` desalineado editado queda reformateado.
- *setup:* dir temporal con `pyproject.toml` vacío; `bad.py` con `x=1;y=2` (mal formateado); `black` en PATH.
- *test:*
  ```bash
  d=$(mktemp -d); printf 'x=1;y=2\n' > "$d/bad.py"
  before=$(md5sum "$d/bad.py")
  printf '{"cwd":"%s","tool_input":{"file_path":"%s/bad.py"}}' "$d" "$d" \
    | $HK/biab-format.sh; rc=$?
  after=$(md5sum "$d/bad.py")
  [[ $rc -eq 0 && "$before" != "$after" ]] && echo PASS || echo FAIL
  ```
  El contenido pasa a estar formateado (dos líneas `x = 1` / `y = 2`).
- *criterio:* fichero modificado, `exit 0`. Repetir para `.js`/`.ts` con `prettier` y `.sh` con `shfmt` (≥3 lenguajes, cubre tabla §2.3).

**AC-L1 — Log Stop registra resumen local SIN secretos.** La sesión que para añade una línea al log con timestamp/session/cwd/contadores/basenames y nada más.
- *test:*
  ```bash
  printf '{"session_id":"t1","cwd":"/tmp","transcript_path":"/nonexistent"}' \
    | HOME=$(mktemp -d) $HK/biab-session-log.sh; echo "rc=$?"
  ```
  → añade 1 línea a `$HOME/.claude/logs/biab-sessions.log`.
- *criterio:* la línea contiene `session_id` y `cwd`; el fichero es `0600` (`stat -c %a` → `600`); transcript inexistente degrada a línea mínima + `exit 0` (no rompe el Stop). El caso "sin secretos" se prueba a fondo en AC-LOG1 (§4.5).

**AC-LI1 — Lint devuelve el error como `additionalContext` (no bloqueante).** Un fichero con error de lint produce `exit 0` + JSON `additionalContext` con el error; la edición NO se marca fallida.
- *setup:* dir con config de linter (p.ej. `.eslintrc.json` mínimo o proyecto `ruff`), fichero con violación clara (import sin usar / var indefinida).
- *test:*
  ```bash
  printf '{"cwd":"%s","tool_input":{"file_path":"%s/bad.py"}}' "$d" "$d" \
    | $HK/biab-lint.sh | jq -e '.hookSpecificOutput.additionalContext | length>0'
  ```
  → true; y el `exit` del hook es `0` (nunca `2`).
- *criterio:* `additionalContext` no vacío con el texto del linter, `exit 0`. Si NO hay error de lint → `additionalContext` ausente/vacío y `exit 0` (silencio, no ruido). Confirmar que **nunca** usa `exit 2` (grep del script: no debe existir `exit 2`).

---

### 4.3 Degradación (edge crítico — fail-open)

**AC-D1 — Proyecto SIN formatter/linter → no-op silencioso, la acción NO se rompe.** Con la toolchain ausente, format y lint no tocan el fichero, no emiten stdout, y salen `0`.
- *test (formatter ausente):*
  ```bash
  d=$(mktemp -d); printf 'x=1;y=2\n' > "$d/bad.py"; before=$(md5sum "$d/bad.py")
  printf '{"cwd":"%s","tool_input":{"file_path":"%s/bad.py"}}' "$d" "$d" \
    | env -i PATH=/usr/bin HOME="$d" $HK/biab-format.sh; rc=$?
  after=$(md5sum "$d/bad.py")
  [[ $rc -eq 0 && "$before" == "$after" ]] && echo PASS || echo FAIL
  ```
  (PATH acotado a `/usr/bin` para garantizar ausencia de `black`/`prettier` locales; ajustar si el runner los tuviera en `/usr/bin`.)
- *criterio:* fichero **sin cambios**, stdout vacío, `exit 0`. Ídem `biab-lint.sh` → sin `additionalContext`, `exit 0`. Nunca deja el fichero a medias (regla de oro §2.3).

**AC-D2 — Extensión desconocida → no-op.** `tool_input.file_path` con ext no mapeada (`foo.xyz`, `Makefile`, sin extensión) → `exit 0`, sin cambios, sin stdout, tanto en format como en lint.

**AC-D3 — Hook que falla internamente → fail-open (salvo guardrail).** Un fallo del propio script (binario del formatter presente pero que peta, config corrupta, jq falla en un campo opcional) degrada a no-op con `exit 0` en format/lint/log. **Nunca** `exit 2`.
- *test:* alimentar stdin malformado a los fail-open: `printf 'not-json' | $HK/biab-format.sh; echo $?` → `0`; ídem `biab-lint.sh` y `biab-session-log.sh`. Y `printf '{}' | $HK/biab-format.sh; echo $?` → `0` (campos ausentes).
- *criterio:* los 3 fail-open salen `0` ante stdin vacío/`{}`/basura. El guardrail NO entra aquí — su fallo se cubre en AC-E1 (fail-closed).

**AC-D4 — Kill-switch corta en seco.** Con `BIAB_HOOKS_DISABLED=1` o el sentinel `~/.claude/hooks-disabled`, los 4 hooks hacen no-op inmediato (`exit 0`, sin efecto), incluido el guardrail.
- *test:*
  ```bash
  echo '{"tool_input":{"command":"rm -rf / --no-preserve-root"}}' \
    | BIAB_HOOKS_DISABLED=1 $HK/biab-guardrail.sh; rc=$?
  out=$(echo '{"tool_input":{"command":"rm -rf / --no-preserve-root"}}' | BIAB_HOOKS_DISABLED=1 $HK/biab-guardrail.sh)
  [[ $rc -eq 0 && -z "$out" ]] && echo PASS || echo FAIL
  ```
- *criterio:* con kill-switch, el guardrail NO emite `deny` (no-op) — comportamiento esperado y documentado (el usuario apagó los hooks a conciencia). Verificar también con el sentinel-file.

---

### 4.4 Edge — guardrail parse-error, merge de settings

**AC-E1 — Guardrail con parse-error → fail-closed ACOTADO (`ask`, no `deny` ciego ni pasar).** stdin no parseable o comando ininteligible ⇒ `permissionDecision:"ask"`.
- *test:*
  ```bash
  echo 'garbage-not-json' | $HK/biab-guardrail.sh | jq -r '.hookSpecificOutput.permissionDecision'   # ask
  printf '{}' | $HK/biab-guardrail.sh | jq -r '.hookSpecificOutput.permissionDecision'                 # ask (command ausente)
  printf '{"tool_input":{}}' | $HK/biab-guardrail.sh | jq -r '.hookSpecificOutput.permissionDecision'  # ask
  ```
- *criterio:* los tres → `ask`. **Nunca** `deny` (bloquearía todo por un bug — anti-brick) ni `allow`/exit-0-silencioso (dejaría pasar un destructivo si el parseo del comando peligroso falla). Este es el balance de §2.4: un bug del script no abre la puerta ni brickea la caja.

**AC-E2 — Merge jq en caja fresca (único caso soportado).** Sobre un `HOME` fixture sin `~/.claude/settings.json` previo, `install_hooks()` crea el fichero con los 3 eventos y comandos por ruta absoluta real.
- *test:*
  ```bash
  # tras correr el scaffold con ai_cli=claude contra el HOME fixture:
  jq -e '.hooks.PreToolUse[0].hooks[0].command | endswith("/biab-guardrail.sh")' $H/.claude/settings.json
  jq -e '.hooks.PostToolUse[0].hooks | length == 2' $H/.claude/settings.json
  jq -e '.hooks.Stop[0].hooks[0].command | endswith("/biab-session-log.sh")' $H/.claude/settings.json
  jq -e '(.hooks.PreToolUse[0].hooks[0].command | startswith("/"))' $H/.claude/settings.json   # abs path
  ```
- *criterio:* 3 eventos presentes, PostToolUse con 2 hooks (format+lint), todos abs-path apuntando a scripts existentes (`test -x` sobre cada `command`). Idempotencia: segunda corrida → hash del `.hooks` idéntico (AC-R2).

**AC-E3 — Merge jq con settings de usuario preexistentes → reemplaza arrays; documentar el riesgo.** Laura marcó `. * $ours`: jq `*` sobre arrays hace que **gane el de la derecha** (nuestros arrays reemplazan los del usuario evento a evento), pero conserva otras claves top-level y otros eventos de hook.
- *test:*
  ```bash
  # fixture: settings.json de usuario con una clave propia + un hook PreToolUse propio
  printf '%s' '{"env":{"FOO":"bar"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/user/mine.sh"}]}]}}' > $H/.claude/settings.json
  # correr install_hooks, luego:
  jq -e '.env.FOO=="bar"' $H/.claude/settings.json                                             # clave propia SOBREVIVE
  jq -e '[.hooks.PreToolUse[].hooks[].command] | index("/user/mine.sh") | not' $H/.claude/settings.json  # su PreToolUse fue REEMPLAZADO
  ```
- *criterio:* `.env.FOO` sobrevive; el `PreToolUse` propio del usuario se pierde (reemplazado por el nuestro). **Riesgo documentado:** el scaffold es caja-fresca (`phase_is_done`, corre una vez), así que en el flujo soportado el usuario no tiene hooks previos. Pero si alguien re-scaffoldea o llega con un `settings.json` que ya trae `PreToolUse`/`PostToolUse`/`Stop`, esos arrays se sobrescriben silenciosamente. QA marca esto como **hueco conocido** (ver §4.7) — mitigación (merge por-array en vez de reemplazo) es candidata a v0.2, no bloquea el FEAT porque el caso soportado es caja nueva.

---

### 4.5 Edge — log nunca captura secretos

**AC-LOG1 — El log NUNCA persiste strings de comando, contenido, env ni tokens.** Aunque una sesión ejecute un comando con un token, el log solo tiene metadatos.
- *test (transcript sintético con secreto):*
  ```bash
  H=$(mktemp -d); mkdir -p "$H/.claude/logs"
  tp="$H/transcript.jsonl"
  # transcript falso con un tool_use Bash que lleva un token en el comando:
  printf '%s\n' '{"type":"tool_use","name":"Bash","input":{"command":"curl -H \"Authorization: Bearer sk-SECRET-TOKEN-12345\" https://api.x"}}' > "$tp"
  printf '{"session_id":"t","cwd":"/tmp","transcript_path":"%s"}' "$tp" \
    | HOME="$H" $HK/biab-session-log.sh
  grep -Ei 'sk-SECRET-TOKEN|Bearer|Authorization|curl|password|BEGIN' "$H/.claude/logs/biab-sessions.log" \
    && echo "FAIL: secret leaked" || echo "PASS: no secret in log"
  ```
- *criterio:* `grep` del token falso (y de `Bearer`/`Authorization`/el string del comando) sobre el log → **vacío**. El log solo debe contener timestamp, session_id, cwd, contadores y basenames de ficheros. Este AC es el gate duro de §3 Never ("persistir secretos").

**AC-LOG2 — Basenames sí, rutas/contenido no problemático.** Si el transcript toca `secrets/prod.env`, el log puede registrar el basename `prod.env` (metadato) pero NO su contenido. Verificar que solo aparecen basenames, no diffs ni valores.

---

### 4.6 Regresión

**AC-R1 — Ruta `claude` y scaffold existente intactos.** Tras añadir `install_hooks()`, el scaffold sigue: symlinkeando skills (`~/.claude/skills/<name>` → `~/.agents/skills/`), pre-sembrando el `settings.json` de **agy** (`~/.gemini/antigravity-cli/settings.json`) sin tocar, y el `chown -R` de `~/.claude` cubre el nuevo `settings.json`.
- *test:* correr el scaffold completo contra fixture `ai_cli=claude`; verificar: (a) los symlinks de skills siguen existiendo y apuntan bien (`readlink`); (b) el merge de agy no cambió; (c) `stat -c %U ~/.claude/settings.json` → el usuario objetivo (no root).
- *criterio:* skills, agy pre-seed y ownership sin regresión. El único fichero nuevo es `~/.claude/settings.json`.

**AC-R2 — Idempotencia del seed.** Segunda corrida de `install_hooks()` → `.hooks` idéntico (merge determinista).
- *test:* `h1=$(jq -S '.hooks' $s | md5sum); <re-run>; h2=$(jq -S '.hooks' $s | md5sum); [[ "$h1" == "$h2" ]]`.
- *criterio:* hash igual; sin duplicar hooks en los arrays.

**AC-R3 — Caja antigravity: sin hooks pero sin romper.** Con `ai_cli=antigravity`, `install_hooks()` hace no-op, loguea el skip, y **no** crea `~/.claude/settings.json`; el resto del scaffold agy (skills en `~/.gemini/`, merge de su settings) intacto.
- *test:* scaffold con fixture `ai_cli=antigravity` → `[[ ! -f ~/.claude/settings.json ]]`; log contiene "skipping"/"not applicable"; el `~/.gemini/antigravity-cli/settings.json` de agy se sembró bien.
- *criterio:* cero `settings.json` de Claude en caja agy, scaffold agy completo, skip logueado. Cubre riesgo #3 de §3 (agy sin guardrail — documentado, no roto).

**AC-R4 — CI verde.** `shellcheck -S warning payload/hooks/*.sh`, `bash -n` sobre cada script, guard de refs personales y archive-cleanliness siguen pasando con los 5 scripts nuevos.

---

### 4.7 Rendimiento (riesgo #2 de §3 — medir)

**AC-P1 — Latencia añadida por format+lint por edición.** Medir el coste que format+lint añaden a cada Edit/Write, que corren en serie tras cada edición.
- *test:*
  ```bash
  d=<repo JS mediano con prettier+eslint config>; f="$d/src/index.js"
  time ( printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$d" "$f" | $HK/biab-format.sh
         printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$d" "$f" | $HK/biab-lint.sh )
  ```
  Medir p50 y p95 sobre ≥20 iteraciones en: (a) fichero pequeño repo pequeño, (b) fichero en repo grande (eslint con muchos plugins).
- *umbral aceptable:* **format+lint combinados < 1.5 s p95 por edición** en un repo típico; el **no-op (sin toolchain) < 150 ms p95** (camino que debe ser barato — es el común en cajas recién montadas). Si un repo real supera el umbral, documentar y considerar (v0.2) lint asíncrono o debounce. El no-op rápido es requisito no-funcional (§1) — su medición es gate.
- *criterio:* p95 reportado para los dos escenarios; no-op bajo umbral; hallazgo anotado si se supera.

**AC-P2 — El guardrail no añade latencia perceptible.** El guardrail corre en cada Bash. Medir su coste (solo regex/jq, sin toolchain externa).
- *umbral:* **< 100 ms p95** por comando. *criterio:* reportado.

---

### 4.8 E2E — sesión Claude real (observar efecto)

**AC-X1 [sesión].** En `claude`/`claude -p` sobre la caja con los hooks activos: (a) pedir `rm -rf /tmp/biab-test --no-preserve-root` → **bloqueado**, el agente ve el motivo del guardrail; (b) editar un `.py` desalineado en un proyecto con `black` → sale formateado y el error de lint aparece como contexto en el siguiente turno; (c) editar un fichero de ext sin toolchain → sin ruido, edición normal; (d) terminar la sesión → línea nueva en `~/.claude/logs/biab-sessions.log`.
- *criterio:* los 4 efectos observados de cara al agente/usuario (no solo el contrato aislado). `bash payload/test/wiring-smoke.sh` (matriz claude/antigravity) verde.

---

### 4.9 Criterios de testing (resumen ejecutable)

- **Contrato por hook:** `printf '<json>' | hook.sh`, inspeccionar `$?` y `jq -e` sobre stdout. Fixtures de stdin por caso en `payload/hooks/tests/`.
- **Guardrail:** matriz `deny`/`ask`/`pasa` con `jq -r '.hookSpecificOutput.permissionDecision'`; parse-error → `ask`.
- **Format/lint no-op:** `env -i PATH=/usr/bin` + `md5sum` antes/después (fichero intacto) + stdout vacío + `exit 0`; grep de `exit 2` en los fail-open → **debe ser vacío**.
- **Log sin secretos:** transcript sintético con token falso → `grep -Ei 'token|Bearer|password|BEGIN|sk-|<command-string>' log` → **vacío**; `stat -c %a log` → `600`.
- **Seed:** `jq -e` sobre `~/.claude/settings.json` (3 eventos, PostToolUse len 2, abs-paths a scripts `test -x`); idempotencia por hash `jq -S '.hooks' | md5sum`.
- **Regresión agy:** fixture `ai_cli=antigravity` → `[[ ! -f ~/.claude/settings.json ]]` + skip logueado.
- **Rendimiento:** `time` × ≥20 iteraciones, reportar p50/p95; umbrales AC-P1/AC-P2.
- **CI:** `shellcheck -S warning payload/hooks/*.sh` + `bash -n` verdes.

---

### 4.10 Huecos de testabilidad detectados en §2 (para Laura/Elena)

1. **Merge jq destructivo con hooks de usuario preexistentes (AC-E3):** el diseño `. * $ours` **reemplaza** los arrays `PreToolUse/PostToolUse/Stop` completos. En el flujo soportado (caja fresca, `phase_is_done` una vez) es inocuo, pero no hay test que garantice el caso "usuario que ya trae sus propios hooks" porque ese caso **no está soportado**. Riesgo real si `biab update` o un re-scaffold futuro tocan settings con hooks ajenos. Recomendación QA: (a) documentar explícito en §5/README "el seed asume caja nueva; si tienes hooks propios, mergéalos a mano", y (b) considerar en v0.2 merge por-array (append en vez de replace) o un guard `if .hooks.PreToolUse existe y no es nuestro → warn`.
2. **`additionalContext` como canal de lint depende de comportamiento no verificado de Claude:** el contrato aislado (AC-LI1) confirma que el hook **emite** el JSON correcto, pero que Claude **inyecte y actúe** sobre ese contexto solo se comprueba E2E (AC-X1b), que es manual/no-CI. No hay forma barata de automatizar "el agente autocorrigió". Aceptable, pero es el eslabón menos cubierto — marcar como verificación manual obligatoria en el PR.
3. **Detección de secretos en el log es por diseño (metadatos-only), no por scrubbing:** AC-LOG1 verifica que un token no aparece, pero el hook nunca debe *intentar* extraer strings de comando del transcript. Si la implementación de §2.6 parsea el transcript para contar `tool_use`, hay que asegurar que NO llega a serializar `input.command`. Riesgo: un cambio futuro que "enriquezca" el log podría filtrar. Recomendación: test AC-LOG1 debe quedar como **regresión permanente** en CI-local (no solo one-off), y un comentario en el script marcando la línea como frontera de seguridad.
4. **Umbrales de rendimiento (AC-P1) sin baseline previo:** §2 marca el riesgo pero no fija número. QA propone < 1.5 s p95 (format+lint) y < 150 ms (no-op), pero son estimaciones sin medición en hardware real (mini PC). Hueco: hay que medir en la caja objetivo, no solo en el server de dev, porque el hardware BIAB es más lento (ver memoria hardware). El umbral puede necesitar ajuste tras la primera medición real.
5. **`env -i PATH=/usr/bin` para simular ausencia de toolchain (AC-D1) es frágil:** si el runner de CI tiene `black`/`prettier` en `/usr/bin` el test da falso PASS. Recomendación: usar un `PATH` a un dir vacío controlado (`mktemp -d`) en vez de `/usr/bin`, para garantizar ausencia real de binarios.

---

## 5. Implementacion (Laura)

### Branch
`feat/FEAT-015`

### Decisiones tomadas
- [2026-07-11] Jesus eligió los 4 hooks (guardrail + formateo + lint + log) para shippar antes del flip, para anunciar "hooks" con verdad.
- [2026-07-11] **Lista del guardrail aprobada por Jesus (Ask First resuelto):** DENY — `rm -rf` de raíz/`--no-preserve-root`, `mkfs`/`wipefs`/`dd of=/dev/*`/`fdisk`, fork bomb, `curl|wget | sudo bash`, `chmod/chown -R` sobre `/`, `git push --force` a `main`/`master`. ASK — `curl|bash` sin sudo, `git push --force-with-lease` en feature. Parse-error → ask. Lista conservadora a propósito (un guardrail agresivo se desactiva y deja de proteger).

---

## 6. Feedback (Jesus)

—
