# FEAT-020: Multi-CLI adapter registry en payload

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** media
- **Complejidad:** media
- **E2E mode:** none
  > Refactor interno de payload sin runtime observable nuevo — la verificación es paridad de comportamiento vía CI dryrun matrix.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** completada
- **Creado:** 2026-08-02
- **Actualizado:** 2026-08-02 (impl)
- **Validado por Jesus:** [x]

> Complejidad determina el modelo de implementacion: alta=Opus, media/baja=Sonnet.

---

## Definition of Ready (DoR)

### Producto (§1) — owner Elena
- [x] Problema explicito (no solucionismo: el "por que", no solo el "que")
- [x] **Intent (why) rellenado** — motivación estratégica/usuario separada del problema
- [x] Minimo 1 historia de usuario verificable
- [x] Minimo 3 requisitos funcionales con checkbox
- [x] **Requisitos funcionales en sintaxis EARS**
- [x] Boundaries §3 con al menos 1 item en cada bloque (Always / Ask First / Never)

### Spec Tecnica (§2) — owner Laura
- [x] Investigacion previa rellenada con rutas reales verificadas (`ls`)
- [x] Tabla "Archivos afectados" completa con accion (CREAR/MODIFICAR/ELIMINAR)
- [x] Minimo 1 `<task>` con `<verify>` ejecutable y `<done>` observable
- [x] Patron de codigo con fragmento real del proyecto (10-20 lineas)
- [x] Criterios de aceptacion globales verificables

### QA (§4) — owner Pablo
- [x] Minimo 1 caso funcional en la tabla con pasos numerados y resultado verificable
- [x] Minimo 1 edge case (input vacio/invalido/limite)
- [x] Minimo 1 item de regresion (feature existente que NO debe romperse)
- [x] Bloque `Criterios de testing` con comandos ejecutables

### Growth (§1.Growth Notes) — owner Andrea
- [x] N/A explicito — refactor interno sin componente de canal/SEO/marketing

---

## 1. Requisitos (Elena)

### Problema

BIAB soporta dos CLIs (claude, antigravity) mediante ~8 sitios `if/else` inline
dispersos por el payload (wizard, tmux launcher, scaffold, comando `biab`,
browser pack, CI). FEAT-013 eliminó deliberadamente las funciones adapter, así
que añadir un tercer CLI (Codex) hoy exige cirugía en 8 archivos distintos y
multiplica el riesgo de olvidar un sitio — exactamente el patrón de gap de
espejos (ERR-007) que solo aparece en runtime.

### Intent (why)

Decisión de Jesús (2026-08-02): los avances del harness van a las TRES
plataformas (Claude Code, Antigravity, Codex), con `core/harness/` ya
reestructurado como umbrella multi-CLI en ai-platform. El codex-harness
personal arranca con la suscripción ChatGPT y su destino final es BIAB
(Wave 3). Hacer el registry AHORA — antes del launch público y con solo dos
CLIs que migrar — es mucho más barato que después con usuarios instalados;
es el habilitador que desbloquea el adaptador Codex sin tocar el resto del
payload.

### Solucion propuesta

Un registro único de CLIs en `payload/lib/ai-cli.sh`: cada CLI soportado
declara sus propiedades (nombre visible, script de instalación, comando de
lanzamiento en tmux, directorios de skills/symlinks, capacidades
hooks/statusline/quota). Los 8 sitios de consumo consultan el registro en vez
de ramificar por nombre. Para el usuario final el comportamiento es idéntico
al actual; para el mantenedor, añadir un CLI = añadir una entrada al registro
+ su script de instalación.

Este FEAT NO añade Codex como opción visible — eso es un FEAT derivado
(Wave 3) que se abrirá cuando el codex-harness personal esté validado.

### Historias de usuario

- Como mantenedor de BIAB, quiero añadir un CLI nuevo tocando solo el registro
  y su install script, para que soportar Codex no requiera cirugía en 8
  archivos dispersos.
- Como usuario que instala BIAB hoy con claude o antigravity, quiero que el
  wizard, el login y la sesión tmux se comporten exactamente igual que antes
  del refactor, para no notar el cambio.

### Requisitos funcionales (EARS)

- [x] **Ubicuo:** El payload shall definir cada CLI soportado en un único
  registro en `payload/lib/ai-cli.sh` con sus propiedades (install script,
  comando de lanzamiento, dirs de skills, capacidades hooks/statusline/quota).
- [x] **Ubicuo:** Los sitios de consumo (wizard choose/login, tmux launcher,
  scaffold, `biab` command, browser pack, CI matrix) shall resolver el
  comportamiento por CLI consultando el registro, sin `if/else` por nombre
  fuera de `ai-cli.sh`.
- [x] **Event-driven:** Cuando se añade una entrada nueva al registro (más su
  install script), el wizard shall ofrecer ese CLI sin cambios en ningún otro
  archivo del payload.
- [x] **Unwanted:** Si un CLI del registro no soporta una capacidad (p. ej.
  hooks o statusline), entonces el scaffold shall omitir ese paso como no-op
  explícito sin fallar (patrón FEAT-015 §2.5).
- [x] **Ubicuo:** El comportamiento observable para claude y antigravity shall
  permanecer idéntico al actual (paridad estricta, cero cambios de UX).

### Requisitos no funcionales

- [x] Bash puro con `set -euo pipefail`; sin dependencias nuevas.
- [x] Idempotente — los pasos de install/wizard pueden re-ejecutarse.
- [x] Shellcheck limpio y `bash -n` en CI.
- [x] Strings de usuario en inglés.

### Referencias visuales

- N/A — refactor interno sin UI nueva.

### Growth Notes (Andrea)

- **Canal:** N/A — refactor interno; sin impacto en canales ni tracking.

---

## 2. Spec Tecnica (Laura)

### 2.1 Investigacion previa

Verificado con `grep -rn` + lectura completa de cada archivo el 2026-08-02.
Los "~8 sitios" reales son **11 sitios de runtime + 2 de test/CI**. Inventario
exacto de dispatch por nombre de CLI fuera de `payload/lib/ai-cli.sh`:

| # | Sitio | Lineas exactas | Que ramifica |
|---|-------|----------------|--------------|
| 0 | `payload/lib/ai-cli.sh` | 11 (`BIB_SUPPORTED_AI_CLIS`), 53-60 (`ai_cli_install_script`, `case`) | Semilla del registro — unico dispatch legitimo hoy |
| 1 | `payload/install.sh` | 378-390 (heredoc descripciones 381-382, `prompt_choice "Which one?" "claude" "antigravity"` en 384, fallback `AI_CLI_ARG="claude"` en 388) | Chooser interactivo pre-wizard |
| 2 | `payload/wizard/05-choose-cli.sh` | 24-33 (heredoc 29-30, `prompt_choice` 33) | Chooser fallback del wizard |
| 3 | `payload/wizard/38-ai-cli-login.sh` | 54-64 (`case` verify_cmd), 75-123 (`if [[ "$cli" == "claude" ]]` — copy + comando de login interactivo), 132-134 (hint de fallo agy) | Flujo de login OAuth completo |
| 4 | `payload/tmux/launch-main.sh` | 48-70 (`launch_cmd_for`: 55 claude, 61 antigravity, 68 fallback) | Comando de lanzamiento en tmux |
| 5 | `payload/wizard/40-scaffold.sh` | 101-107 (mkdir agy skills dir), 128-134 (symlink agy en `install_skill`), 174-188 (pre-seed settings agy), 199-202 (early-return no-op de `install_hooks`), 308-325 (awk render README con markers hardcoded), 335-337 (chown `.gemini`) | 6 ramas en un solo archivo |
| 6 | `payload/install/05-biab-command.sh` | 60-70 (dentro del heredoc del wrapper: link `.claude` incondicional + `.gemini` por existencia de dir) | `biab add` espeja skills |
| 7 | `payload/pack/browser/install.sh` | 218-231 (link `.claude` incondicional, `if [[ "$ai_cli" == "antigravity" ]]` en 223) | Skill del browser pack |
| 8 | `payload/pack/browser/uninstall.sh` | 37 (lista hardcoded de ambos link paths) | Sitio extra NO listado en el problema |
| 9 | `payload/wizard/run.sh` | 129-176 (`if [[ "$_finale_ai_cli" == "antigravity" ]]` en 135) | Finale: app Claude vs SSH+tmux |
| 10 | `payload/test/wiring-smoke.sh` | 61 (extrae `launch_cmd_for` via `sed` — fragil), 63-72 (oracle por CLI), 77-88 (awk duplicado del render README) | Test — oracle legitimo, pero duplica codigo |
| 11 | `.github/workflows/ci.yml` | 80 (`ai_cli: [claude, antigravity]`) | Matrix dryrun hardcoded |

**No son sitios** (solo copy/comentarios/datos, no requieren cambio): `payload/install.sh:50,112` (usage text), `payload/lib/common.sh:160` y `payload/lib/prompt.sh:163` (comentarios), `payload/test/dryrun.sh:14,19`, los markers `<!-- BIB:<cli>:start -->` de `payload/tutorial/desktop-readme.md` (son datos keyed por identificador — ya generalizables), `payload/install/40-claude-code.sh` / `41-antigravity-cli.sh` (adapters per-CLI por diseño), `tools/reset-for-gift.sh` (tool de mantenedor, ver NO incluye).

**Patron existente:** `ai-cli.sh` ya es el embrion del registro (`BIB_SUPPORTED_AI_CLIS` + `ai_cli_install_script` con `case`). El estilo del payload es bash con `set -euo pipefail`, funciones con `case`, **cero arrays asociativos** (`grep -rn 'declare -A' payload` → vacio) — el registro debe seguir ese estilo, no introducir `declare -A`.

**Riesgos detectados:**
- `payload/lib/ai-cli.sh` depende de `die`/`state_get`/`log` de `common.sh`. El wrapper `biab` (heredoc autocontenido, corre como usuario) tendria que sourcearlo en runtime — `common.sh` puede tener side effects (dirs de estado). Mitigacion: los getters puros del registro no deben requerir `common.sh` (fallback `die` guard) y el wrapper los llama en subshell.
- Sourcear `ai-cli.sh` (que hace `set -euo pipefail` top-level) dentro del wrapper `biab` activaria `-euo` en todo el wrapper, que hoy no lo usa globalmente → posible rotura por unset vars. Mitigacion: subshell.
- El merge jq de hooks/settings (FEAT-015/018/019, `40-scaffold.sh:208-260`) NO debe cambiar de semantica al reorganizar el gating — solo se toca el guard, no el merge.
- `wiring-smoke.sh:61` extrae `launch_cmd_for` con `sed` del launcher; al mover la funcion al registro ese sed se rompe → el test debe pasar a sourcear `ai-cli.sh` directamente (de paso elimina la fragilidad).

### 2.2 Diseño del registro

Un **bloque adapter por CLI** en `payload/lib/ai-cli.sh` (propiedades agrupadas
en una funcion `_ai_cli_props__<cli>`, comportamientos como funciones
`_ai_cli_<verbo>__<cli>`) + **API publica de dispatchers** que valida y delega
por composicion de nombre de funcion (`"_ai_cli_launch_cmd__${cli}"`). Añadir
un CLI = 1 bloque contiguo nuevo en `ai-cli.sh` + 1 install script.

API publica (los consumidores SOLO usan esto):

```bash
BIB_SUPPORTED_AI_CLIS=(...)                    # exists today, unchanged
ai_cli_resolve / ai_cli_validate / ai_cli_persist   # exist today, unchanged
ai_cli_install_script <cli>                    # exists; reimplemented over props
ai_cli_display_name <cli>                      # "Claude Code" / "Antigravity (agy)"
ai_cli_choice_hint <cli>                       # one-liner for the choosers
ai_cli_launch_cmd <cli> <window> [prompt]      # tmux launch command (printf %q)
ai_cli_skills_dirs <cli>                       # newline-separated, $HOME-relative
ai_cli_has_capability <cli> <cap>              # caps: hooks statusline remote-control
ai_cli_login_verify_cmd <cli> <user>           # non-interactive auth check
ai_cli_login_run <cli> <user>                  # intro copy + interactive login
ai_cli_login_failure_hint <cli> <user>         # recovery message on failure
ai_cli_seed_settings <cli> <home> <ws_root>    # no-op for claude; agy jq merge
ai_cli_render_readme <cli> <src>               # generic awk over BIB:<name> markers
```

Decisiones de diseño:

- **Capacidades como lista separada por espacios** (`AI_CLI_CAPABILITIES="hooks statusline remote-control"`), chequeada con pattern-match — sin arrays asociativos, consistente con el estilo actual. claude = las tres; antigravity = ninguna.
- **`ai_cli_skills_dirs antigravity` devuelve `.claude/skills` Y `.gemini/skills`**: hoy los boxes antigravity tambien symlinkan en `~/.claude/skills` (scaffold:123-127, biab wrapper:60-65, browser pack:218-222 lo hacen incondicionalmente). Codificarlo como propiedad del CLI preserva la paridad exacta y deja un unico loop en los 4 consumidores. Documentar el porque en el comment del adapter.
- **Finale por capability, no por nombre**: `run.sh` pasa a `if ai_cli_has_capability "$cli" remote-control` → finale de app Claude; si no → finale SSH+tmux interpolando `ai_cli_display_name`. Generaliza a futuros CLIs sin app.
- **`ai_cli_render_readme`**: el awk generaliza los markers a `/<!-- BIB:[a-z-]+:start -->/` extrayendo el nombre y comparando con `$cli` — el mismo codigo sirve para scaffold y wiring-smoke (hoy duplicado), y un CLI nuevo solo añade sus bloques al markdown.
- **`launch_cmd_for` se queda en `launch-main.sh` solo como shim**: mantiene el override `BIB_TMUX_LAUNCH_CMD` (que es dispatch de test, no de CLI) y delega en `ai_cli_launch_cmd`.
- **`ai-cli.sh` debe seguir siendo sourceable sin side effects top-level** (solo define funciones + el array); es lo que permite consumirlo desde el wrapper `biab`, wiring-smoke y CI.
- **Los oracles de test (`wiring-smoke.sh:63-72`) CONSERVAN sus `case` por CLI**: un oracle que consulta el registro para saber que esperar seria tautologico. La regla "sin if/else fuera de ai-cli.sh" aplica al runtime del payload, no a las aserciones de test.

### 2.3 Alcance

**Incluye:**
- Registro completo en `payload/lib/ai-cli.sh` con la API de 2.2.
- Migrar los 11 sitios de runtime (tabla 2.1, filas 1-9) a la API.
- Matrix de CI generada dinamicamente desde `BIB_SUPPORTED_AI_CLIS`.
- `wiring-smoke.sh` ampliado con check de completitud del registro (cada CLI registrado responde a todos los getters).

**NO incluye:**
- Añadir Codex (ni ningun CLI nuevo) al registro — FEAT derivado Wave 3.
- Soporte de hooks/statusline para antigravity — el no-op de FEAT-015 §2.5 se conserva tal cual (via capability).
- `tools/reset-for-gift.sh` (tool de mantenedor con paths hardcoded de ambos CLIs) — fuera del payload de usuario; dejar comentario TODO con fecha apuntando a este FEAT.
- Cambios de copy/UX mas alla de interpolar strings identicos (paridad estricta).
- `iso-builder/`, `site/`, `installer/web/install.sh` — no tienen dispatch por CLI.
- Traducir las skills `sdd-*` (deferido explicitamente en CLAUDE.md).

### 2.4 Archivos afectados

| Archivo | Accion | Cambio |
|---------|--------|--------|
| `payload/lib/ai-cli.sh` | MODIFICAR | Bloques adapter por CLI + API publica (2.2) |
| `payload/install.sh` | MODIFICAR | Chooser 378-390: menu y fallback desde el registro |
| `payload/wizard/05-choose-cli.sh` | MODIFICAR | Idem chooser 24-33 |
| `payload/wizard/38-ai-cli-login.sh` | MODIFICAR | verify/run/hint via getters; muere el `case` 54-64 y el `if` 75-123 |
| `payload/wizard/run.sh` | MODIFICAR | Finale 129-176 por capability `remote-control` |
| `payload/wizard/40-scaffold.sh` | MODIFICAR | Loop `ai_cli_skills_dirs`, `ai_cli_seed_settings`, gates por capability en `install_hooks`, `ai_cli_render_readme`, chown derivado |
| `payload/tmux/launch-main.sh` | MODIFICAR | `launch_cmd_for` delega en `ai_cli_launch_cmd` |
| `payload/install/05-biab-command.sh` | MODIFICAR | Wrapper: loop sobre registro (en subshell) en `install_optional_skill` |
| `payload/pack/browser/install.sh` | MODIFICAR | Loop `ai_cli_skills_dirs` en 218-231 |
| `payload/pack/browser/uninstall.sh` | MODIFICAR | Deriva los link paths del registro (linea 37) |
| `payload/test/wiring-smoke.sh` | MODIFICAR | Sourcea `ai-cli.sh` (adios `sed`), usa `ai_cli_render_readme`, añade check de completitud |
| `.github/workflows/ci.yml` | MODIFICAR | Job previo emite la lista JSON desde el registro; `dryrun` usa `fromJSON` |

Refactor puro: 0 archivos nuevos, 0 eliminados.

### 2.5 Dependencias

Ninguna nueva. Bash + coreutils + jq + awk, todos ya presentes en el payload.

### 2.6 Tareas

**Wave 1 — el registro**

<task id="T1">
  <files>payload/lib/ai-cli.sh</files>
  <action>Implementar los bloques adapter (_ai_cli_props__claude, _ai_cli_props__antigravity, funciones de comportamiento _ai_cli_launch_cmd__*, _ai_cli_login_*__*, _ai_cli_seed_settings__*) y la API publica de 2.2. Sin side effects top-level nuevos; getters puros no dependen de common.sh (guard de `die`). Mantener firmas existentes (resolve/validate/persist/install_script) intactas. printf %q para toda interpolacion en launch cmd.</action>
  <verify>bash -n payload/lib/ai-cli.sh && shellcheck payload/lib/ai-cli.sh && bash -c 'export BIB_STATE_DIR=$(mktemp -d); source payload/lib/common.sh; source payload/lib/ai-cli.sh; [[ "$(ai_cli_launch_cmd claude ai-platform /tutorial)" == *"--remote-control"* ]] && [[ "$(ai_cli_launch_cmd antigravity x /tutorial)" == *"agy -i"* ]] && ! ai_cli_has_capability antigravity hooks && ai_cli_has_capability claude hooks && echo T1-OK'</verify>
  <done>La API completa responde para ambos CLIs con los mismos valores que producen hoy los sitios inline; shellcheck limpio.</done>
</task>

**Wave 2 — consumidores (paralelizable tras T1)**

<task id="T2">
  <files>payload/install.sh, payload/wizard/05-choose-cli.sh, payload/wizard/38-ai-cli-login.sh, payload/wizard/run.sh</files>
  <action>Chooser: generar el menu con un loop sobre BIB_SUPPORTED_AI_CLIS + ai_cli_choice_hint, prompt_choice "${BIB_SUPPORTED_AI_CLIS[@]}", fallback "${BIB_SUPPORTED_AI_CLIS[0]}". Login: sustituir case/if por ai_cli_login_verify_cmd / ai_cli_login_run / ai_cli_login_failure_hint. Finale: gate por ai_cli_has_capability remote-control, copy identico interpolando display name.</action>
  <verify>for f in payload/install.sh payload/wizard/05-choose-cli.sh payload/wizard/38-ai-cli-login.sh payload/wizard/run.sh; do bash -n "$f" && shellcheck "$f"; done && ! grep -nE '==\s*"(claude|antigravity)"' payload/install.sh payload/wizard/05-choose-cli.sh payload/wizard/38-ai-cli-login.sh payload/wizard/run.sh</verify>
  <done>Cero comparaciones por nombre de CLI en los 4 archivos; el copy visible al usuario es byte-idéntico para claude y antigravity salvo interpolaciones equivalentes.</done>
</task>

<task id="T3">
  <files>payload/wizard/40-scaffold.sh, payload/install/05-biab-command.sh, payload/pack/browser/install.sh, payload/pack/browser/uninstall.sh</files>
  <action>Scaffold: mkdir+symlink+chown derivados de ai_cli_skills_dirs; pre-seed via ai_cli_seed_settings; install_hooks gated por has_capability hooks (statusline por has_capability statusline); README via ai_cli_render_readme. Wrapper biab: install_optional_skill calcula los link dirs en subshell que sourcea /opt/buildersinabox/payload/lib/ai-cli.sh, linka donde el dir existe y hace mkdir solo de los dirs del CLI por defecto (semantica actual). Browser pack install/uninstall: mismo loop. NO tocar los filtros jq de merge de settings/hooks.</action>
  <verify>for f in payload/wizard/40-scaffold.sh payload/install/05-biab-command.sh payload/pack/browser/install.sh payload/pack/browser/uninstall.sh; do bash -n "$f" && shellcheck "$f"; done && ! grep -nE '==\s*"(claude|antigravity)"' payload/wizard/40-scaffold.sh payload/install/05-biab-command.sh payload/pack/browser/install.sh payload/pack/browser/uninstall.sh && git diff main -- payload/wizard/40-scaffold.sh | grep -c 'jq' | xargs -I{} test {} -eq 0 || git diff main -U0 -- payload/wizard/40-scaffold.sh | grep -E '^[+-].*(dedupe_groups|\. \* \$ours)' | wc -l | xargs test 0 -eq</verify>
  <done>Symlinks/settings/hooks producidos identicos a main para ambos CLIs; los filtros jq de FEAT-015/018/019 sin un solo caracter cambiado en el diff.</done>
</task>

<task id="T4">
  <files>payload/tmux/launch-main.sh, payload/test/wiring-smoke.sh</files>
  <action>launch_cmd_for delega en ai_cli_launch_cmd (conserva override BIB_TMUX_LAUNCH_CMD). wiring-smoke: sourcear ai-cli.sh en vez del sed de la linea 61, render README via ai_cli_render_readme, y NUEVA seccion 6 "registry completeness": para cada cli en BIB_SUPPORTED_AI_CLIS, asertar que install_script existe, launch_cmd/display_name/skills_dirs/login_verify_cmd devuelven no-vacio y has_capability no falla. Oracles por CLI de las secciones 4-5 se conservan.</action>
  <verify>BIB_AI_CLI=claude bash payload/test/wiring-smoke.sh && BIB_AI_CLI=antigravity bash payload/test/wiring-smoke.sh</verify>
  <done>Smoke PASS para ambos CLIs, incluida la seccion de completitud; el sed fragil ha desaparecido.</done>
</task>

**Wave 3 — CI + paridad global**

<task id="T5">
  <files>.github/workflows/ci.yml</files>
  <action>Añadir job `list-clis` que hace checkout, ejecuta `bash -c 'source payload/lib/ai-cli.sh; printf "%s\n" "${BIB_SUPPORTED_AI_CLIS[@]}" | jq -R . | jq -cs .'` y lo expone como output; el job `dryrun` usa `matrix: ai_cli: ${{ fromJSON(needs.list-clis.outputs.clis) }}` con `needs: list-clis`.</action>
  <verify>bash -c 'source payload/lib/ai-cli.sh; printf "%s\n" "${BIB_SUPPORTED_AI_CLIS[@]}" | jq -R . | jq -cs .' | grep -qx '\["claude","antigravity"\]' && python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml"))'</verify>
  <done>La PR muestra en Actions los mismos dos jobs dryrun de hoy (claude, antigravity), generados desde el registro.</done>
</task>

<task id="T6">
  <files>(verificacion — sin ediciones nuevas)</files>
  <action>Pasada de paridad global: correr el smoke para ambos CLIs, grep de branching residual en todo payload/, y diff del render de README nuevo contra el awk viejo de main para ambos CLIs.</action>
  <verify>BIB_AI_CLI=claude bash payload/test/wiring-smoke.sh && BIB_AI_CLI=antigravity bash payload/test/wiring-smoke.sh && ! (grep -rnE '==\s*"(claude|antigravity)"' payload --include='*.sh' | grep -v 'payload/lib/ai-cli.sh' | grep -v 'payload/test/') && for cli in claude antigravity; do diff <(awk -v cli="$cli" '/<!-- BIB:claude:start -->/{inblock=1;keep=(cli=="claude");next} /<!-- BIB:antigravity:start -->/{inblock=1;keep=(cli=="antigravity");next} /<!-- BIB:end -->/{inblock=0;keep=1;next} {if(!inblock||keep)print}' payload/tutorial/desktop-readme.md) <(bash -c "source payload/lib/ai-cli.sh; ai_cli_render_readme $cli payload/tutorial/desktop-readme.md"); done</verify>
  <done>Smoke verde x2, cero dispatch por nombre fuera de registro+tests, render de README byte-identico al de main para ambos CLIs.</done>
</task>

### 2.7 Patron de codigo

Fragmento real de `payload/lib/ai-cli.sh:44-60` (el embrion del registro que
este FEAT extiende — mismo estilo: funcion + `case`, sin arrays asociativos):

```bash
# Persist the chosen CLI in the state file.
ai_cli_persist() {
    local cli="$1"
    ai_cli_validate "$cli"
    state_set '.ai_cli' "\"$cli\""
    log "ai_cli set to: $cli"
}

# Print the path to the install script for a CLI.
ai_cli_install_script() {
    local cli="$1"
    ai_cli_validate "$cli"
    case "$cli" in
        claude)      printf '%s' "install/40-claude-code.sh" ;;
        antigravity) printf '%s' "install/41-antigravity-cli.sh" ;;
    esac
}
```

### 2.8 Criterios de aceptacion globales

- [x] `BIB_AI_CLI=claude bash payload/test/wiring-smoke.sh && BIB_AI_CLI=antigravity bash payload/test/wiring-smoke.sh` → PASS ambos, incluida la seccion nueva de completitud del registro.
- [x] `grep -rnE '==\s*"(claude|antigravity)"' payload --include='*.sh' | grep -v 'payload/lib/ai-cli.sh' | grep -v 'payload/test/'` → salida vacia (cero dispatch por nombre fuera del registro y de los test oracles).
- [x] `shellcheck payload/lib/ai-cli.sh payload/install.sh payload/wizard/*.sh payload/tmux/launch-main.sh payload/install/05-biab-command.sh payload/pack/browser/*.sh payload/test/wiring-smoke.sh` → 0 issues, y `bash -n` limpio en todos.
- [x] Paridad README: el `diff` del `<verify>` de T6 sale vacio para claude y antigravity.
- [x] Paridad de merges: `git diff main -- payload/wizard/40-scaffold.sh` no toca ninguna linea de los filtros jq (`dedupe_groups`, `. * $ours`, bloque statusline).
- [x] CI de la PR verde con exactamente los mismos jobs dryrun que main (claude + antigravity), ahora generados desde `BIB_SUPPORTED_AI_CLIS`.
- [x] Prueba de extensibilidad (manual, en branch descartable): añadir un CLI dummy al registro + install script stub y comprobar que la seccion de completitud del smoke lo cubre y el chooser lo ofrece **sin tocar ningun otro archivo**; revertir antes de la PR.

---

## 3. Boundaries

### Always

- Bash con `set -euo pipefail`; scripts idempotentes y re-ejecutables.
- Paridad de comportamiento: claude y antigravity deben quedar
  observablemente idénticos a main antes del refactor.
- CI verde: shellcheck, `bash -n`, personal-refs guard, archive-cleanliness y
  la dryrun matrix para ambos CLIs.
- Commits `refactor:`/`feat:`/`fix:`; PR siempre, nunca push directo a main.

### Ask First

- Añadir Codex (o cualquier CLI nuevo) como opción visible del wizard — es
  Wave 3, FEAT aparte con OK de Jesús.
- Cualquier cambio de UX o de copy del wizard más allá de la paridad.
- Tocar sshd, sudoers o cualquier security config (FEAT-014/017 los cubren).
- (Laura, §2) Alterar la semántica de los merges jq de settings/hooks
  (FEAT-015 AC-E3, FEAT-018, FEAT-019) al mover el gating — el refactor solo
  toca el guard, no los filtros.
- (Laura, §2) Añadir al wrapper `biab` lecturas de `state.json` o nuevos usos
  de `sudo` — hoy `biab add` corre como usuario sin tocar state y debe seguir
  así.

### Never

- Tocar `.env`, credenciales o tokens.
- Publicar contenido marcado `export-ignore` en el árbol público.
- Añadir dependencias fuera de bash + coreutils.
- Romper el early-return no-op de antigravity en `install_hooks()` (FEAT-015).
- (Laura, §2) Interpolar window name / initial prompt en comandos de
  lanzamiento sin `printf %q` — riesgo de inyección vía `tmux send-keys`.
- (Laura, §2) Introducir side effects top-level en `payload/lib/ai-cli.sh`
  (debe seguir siendo sourceable en frío por el wrapper, tests y CI).
- (Laura, §2) Usar `eval` sobre strings del registro o `declare -A` — dispatch
  solo por composición de nombre de función validada con `ai_cli_validate`.

---

## 4. QA (Pablo)

> **E2E mode: none.** No hay VM en esta fase: todos los casos son estáticos o
> locales (`bash -n`, shellcheck, `payload/test/wiring-smoke.sh` hermético,
> greps de completitud, dryrun estático de CI). `payload/test/dryrun.sh` exige
> root + box real (`/repo`, usuario `ubuntu`) y queda explícitamente fuera; la
> matrix `dryrun` de CI ejecuta el wiring smoke, no el dry-run completo.
>
> **Principio rector: PARIDAD.** El oráculo de referencia es `main`. Donde sea
> posible, comparar la salida del refactor contra la generada desde
> `git show main:<file>`, no contra valores copiados a mano. Baseline
> verificado el 2026-08-02 en main: smoke PASS para ambos CLIs con
> `launch cmd: claude --remote-control ai-platform /tutorial` y
> `launch cmd: AGY_CLI_DISABLE_AUTO_UPDATE=1 agy -i /tutorial`;
> `ssh-finalize-decision.sh` exit 0; `test-pack.sh` 20 passed / 0 failed
> (Sección C SKIP por no-root, esperado).

### 4.1 Casos de prueba funcionales

| ID | Caso | Pasos | Resultado esperado | Estado |
|----|------|-------|--------------------|--------|
| CP-01 | Paridad de wiring por CLI (smoke completo) | 1. `git checkout feat/FEAT-020`<br>2. `BIB_AI_CLI=claude bash payload/test/wiring-smoke.sh`<br>3. `BIB_AI_CLI=antigravity bash payload/test/wiring-smoke.sh` | Ambos terminan en `PASS`. La línea `ok: launch cmd:` imprime **byte-idéntico** al baseline de main: `claude --remote-control ai-platform /tutorial` y `AGY_CLI_DISABLE_AUTO_UPDATE=1 agy -i /tutorial`. `gemini` sigue rechazado (sección 3 del smoke). | pendiente |
| CP-02 | Paridad de login getters contra main | 1. Extraer el oráculo de main: `git show main:payload/wizard/38-ai-cli-login.sh \| sed -n '54,64p'`<br>2. En la branch: `bash -c 'export BIB_STATE_DIR=$(mktemp -d); source payload/lib/common.sh; source payload/lib/ai-cli.sh; ai_cli_login_verify_cmd claude ubuntu; echo; ai_cli_login_verify_cmd antigravity ubuntu'`<br>3. Comparar cada salida con el string del `case` de main sustituyendo `$target_user`→`ubuntu` | Salidas byte-idénticas: claude contiene `claude auth status --text </dev/null` + `grep -q '^Login method:'`; antigravity contiene `AGY_CLI_DISABLE_AUTO_UPDATE=1 agy models </dev/null`. Ningún cambio de copy en `ai_cli_login_run` / `ai_cli_login_failure_hint` (diff visual del heredoc contra main). | pendiente |
| CP-03 | Paridad del render de README contra el awk de main | 1. Ejecutar el `<verify>` de T6 (bloque `diff` para `claude` y `antigravity` contra el awk hardcoded de main)<br>2. Revisar exit code | `diff` vacío (exit 0) para **ambos** CLIs: el render genérico por markers `BIB:[a-z-]+` produce exactamente el mismo texto que el awk viejo. | pendiente |
| CP-04 | Completitud del registro (sección nueva del smoke, T4) | 1. `BIB_AI_CLI=claude bash payload/test/wiring-smoke.sh`<br>2. Localizar en la salida la sección "registry completeness"<br>3. Repetir con `BIB_AI_CLI=antigravity` | Para **cada** CLI de `BIB_SUPPORTED_AI_CLIS`: install script existe y pasa `bash -n`; `ai_cli_display_name`, `ai_cli_launch_cmd`, `ai_cli_skills_dirs` y `ai_cli_login_verify_cmd` devuelven no-vacío; `ai_cli_has_capability <cli> hooks` retorna 0 o 1 sin abortar. Una entrada incompleta hace fallar el smoke con mensaje que nombra el getter roto. | pendiente |
| CP-05 | Extensibilidad event-driven (CLI dummy, branch descartable) — cubre el requisito EARS #3 y el AC global #7 | 1. `git checkout -b qa/registry-dummy feat/FEAT-020`<br>2. Añadir `dummy` a `BIB_SUPPORTED_AI_CLIS` + su bloque adapter en `payload/lib/ai-cli.sh`, y crear stub ejecutable `payload/install/99-dummy.sh` (`#!/usr/bin/env bash` + `exit 0`)<br>3. `git status --porcelain` — verificar que SOLO esos 2 archivos cambian<br>4. `BIB_AI_CLI=dummy bash payload/test/wiring-smoke.sh`<br>5. `bash -c 'source payload/lib/ai-cli.sh; printf "%s\n" "${BIB_SUPPORTED_AI_CLIS[@]}" \| jq -R . \| jq -cs .'`<br>6. Verificación estática del chooser: `grep -n 'prompt_choice' payload/install.sh payload/wizard/05-choose-cli.sh` — los argumentos deben derivar de `"${BIB_SUPPORTED_AI_CLIS[@]}"`, sin literales `"claude" "antigravity"`<br>7. Descartar: `git checkout feat/FEAT-020 && git branch -D qa/registry-dummy` | Paso 3: exactamente 2 paths (`payload/lib/ai-cli.sh`, `payload/install/99-dummy.sh`). Paso 4: smoke PASS (completitud cubre a dummy). Paso 5: imprime `["claude","antigravity","dummy"]` — la matrix de CI lo recogería sola. Paso 6: cero literales de CLI en los args de `prompt_choice` → el wizard lo ofrecería sin tocar ningún otro archivo. | pendiente |
| CP-06 | CI: matrix generada desde el registro (dryrun estático) | 1. `bash -c 'source payload/lib/ai-cli.sh; printf "%s\n" "${BIB_SUPPORTED_AI_CLIS[@]}" \| jq -R . \| jq -cs .'`<br>2. `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml"))'`<br>3. `grep -n 'ai_cli:' .github/workflows/ci.yml`<br>4. En la PR: comparar la lista de checks contra main | Paso 1: exactamente `["claude","antigravity"]`. Paso 2: YAML parsea. Paso 3: ya no existe la lista literal `[claude, antigravity]` — la matrix usa `fromJSON(needs.list-clis.outputs...)`. Paso 4: mismos jobs que main (lint, dryrun claude, dryrun antigravity, browser-pack-tests) todos verdes. | pendiente |

### 4.2 Edge cases

| ID | Input / situación | Resultado esperado | Estado |
|----|-------------------|--------------------|--------|
| EC-01 | CLI no registrado: `ai_cli_launch_cmd codex w /tutorial` (y cada getter público con `codex`) | Exit != 0 con el mensaje de `ai_cli_validate` (CLI no soportado). **Nunca** un `command not found` de bash por componer `_ai_cli_launch_cmd__codex` sin validar antes — la validación va delante del dispatch en TODOS los getters. | pendiente |
| EC-02 | CLI vacío: `ai_cli_display_name ""` y `ai_cli_launch_cmd "" w` | Falla limpio vía `ai_cli_validate` (exit != 0), sin expandir nombre de función vacío. | pendiente |
| EC-03 | Capability inexistente: `ai_cli_has_capability claude bogus-cap` | Retorna 1 (falso) en silencio — sin `die`, sin stderr — y es seguro dentro de `if` bajo `set -euo pipefail` (patrón no-op FEAT-015). | pendiente |
| EC-04 | Inyección en window/prompt: `ai_cli_launch_cmd claude 'w;touch /tmp/bib-qa-pwned' '/tut;echo x'` | La salida lleva todos los args escapados con `printf %q` (`\;` o quoting equivalente); ejecutar el comando resultante en un subshell de prueba NO crea `/tmp/bib-qa-pwned`. Cubre el boundary Never de §3. | pendiente |
| EC-05 | Sourcing en frío sin `common.sh` (contexto del wrapper `biab`): `bash -c 'source payload/lib/ai-cli.sh; ai_cli_skills_dirs antigravity'` en shell **sin** `-euo` previo | Imprime `.claude/skills` y `.gemini/skills` (una por línea), exit 0, **cero** side effects (no crea dirs de estado ni logs). Con CLI inválido en ese mismo contexto, falla limpio (guard de `die` presente). Cubre el riesgo del subshell de §2.1. | pendiente |

### 4.3 Regresión

Features existentes que NO deben romperse (derivadas de la tabla 2.4):

- [ ] **FEAT-013 (antigravity):** smoke antigravity PASS; identificador `gemini` sigue rechazado; el launch cmd conserva `AGY_CLI_DISABLE_AUTO_UPDATE=1` (cubierto por CP-01).
- [ ] **FEAT-014 (SSH-finalize):** `bash payload/test/ssh-finalize-decision.sh` → exit 0; `payload/wizard/35-ssh-finalize.sh` NO aparece en `git diff main --name-only` (el finale de `run.sh` cambia de gate, no la decisión SSH).
- [ ] **FEAT-015 (no-op hooks antigravity):** `ai_cli_has_capability antigravity hooks` retorna falso; el early-return de `install_hooks()` se conserva como no-op explícito; los filtros jq intactos: `git diff main -- payload/wizard/40-scaffold.sh | grep -E 'dedupe_groups|\. \* \$ours'` → vacío.
- [ ] **FEAT-017 (browser pack):** `bash payload/pack/browser/tests/test-pack.sh` → 0 failed (Sección C SKIP sin root es lo esperado); los link paths derivados del registro en `uninstall.sh` == la lista hardcoded de main (`git show main:payload/pack/browser/uninstall.sh | sed -n '37p'`).
- [ ] **FEAT-018/019 (quota + statusline seeds):** mismo diff-guard de jq del item FEAT-015; `ai_cli_has_capability claude statusline` verdadero y `antigravity statusline` falso — el pre-seed de settings agy (`ai_cli_seed_settings`) produce el mismo JSON que main.
- [ ] **CI (guards existentes):** `bash tools/check-no-personal-refs.sh` limpio; check de `git archive` limpio; shellcheck de repo completo sin issues nuevos.
- [ ] **Wrapper `biab`:** `biab add` sigue corriendo como usuario, sin leer `state.json` ni usar `sudo` nuevos (revisión del diff de `payload/install/05-biab-command.sh` contra el boundary Ask First de §3).

### 4.4 Criterios de testing

Comandos ejecutables desde la raíz del repo (todos verificados contra main el
2026-08-02 salvo los que dependen de código nuevo del FEAT):

```bash
# Sintaxis + lint de todos los archivos afectados (tabla 2.4)
for f in payload/lib/ai-cli.sh payload/install.sh payload/wizard/05-choose-cli.sh \
         payload/wizard/38-ai-cli-login.sh payload/wizard/run.sh payload/wizard/40-scaffold.sh \
         payload/tmux/launch-main.sh payload/install/05-biab-command.sh \
         payload/pack/browser/install.sh payload/pack/browser/uninstall.sh \
         payload/test/wiring-smoke.sh; do
    bash -n "$f" && shellcheck "$f" || exit 1
done

# Smoke hermético para ambos CLIs (CP-01, CP-04)
BIB_AI_CLI=claude bash payload/test/wiring-smoke.sh
BIB_AI_CLI=antigravity bash payload/test/wiring-smoke.sh

# Cero dispatch por nombre fuera del registro y de los test oracles (CP-06 / AC #2)
! (grep -rnE '==\s*"(claude|antigravity)"' payload --include='*.sh' \
    | grep -v 'payload/lib/ai-cli.sh' | grep -v 'payload/test/')

# Matrix de CI derivada del registro (CP-06)
bash -c 'source payload/lib/ai-cli.sh; printf "%s\n" "${BIB_SUPPORTED_AI_CLIS[@]}" | jq -R . | jq -cs .' \
    | grep -qx '\["claude","antigravity"\]'
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml"))'

# Regresión FEAT-014 + FEAT-017
bash payload/test/ssh-finalize-decision.sh
bash payload/pack/browser/tests/test-pack.sh

# Guards de CI en local
bash tools/check-no-personal-refs.sh
git archive HEAD | tar -t | grep -E '(^|/)(specs/|payload/flavors/gift/maintainer/)' && exit 1 || echo "archive clean"

# Edge cases del registro (EC-01/02/03/05) — deben fallar/comportarse según 4.2
bash -c 'export BIB_STATE_DIR=$(mktemp -d); source payload/lib/common.sh; source payload/lib/ai-cli.sh; ai_cli_launch_cmd codex w /tutorial' ; echo "exit=$? (esperado != 0)"
bash -c 'source payload/lib/ai-cli.sh; ai_cli_skills_dirs antigravity'   # sin common.sh, debe imprimir 2 dirs
```

### 4.5 Huecos que la implementación debe cubrir en tests

- `wiring-smoke.sh` hoy NO asserta login getters ni skills dirs — la sección
  "registry completeness" de T4 debe incluirlos (CP-04), y conviene añadir ahí
  los asserts de EC-01 (CLI no registrado falla limpio) y EC-05 (sourcing sin
  `common.sh`), que hoy no tienen test automatizado en ningún sitio.
- No existe test del escape `printf %q` (EC-04) — añadir un assert en el smoke
  (sección launcher) para que la regresión de inyección quede cubierta en CI.

### 4.6 Bugs encontrados durante review

- — (se rellena en la review post-implementación)

---

## 5. Implementacion (Laura — se rellena durante la implementacion)

### Branch

`feat/FEAT-020`

### Progreso

| Task | Estado | Commit | Notas |
|------|--------|--------|-------|
| T1 registro | completada | `dd73b3a` | Paridad byte-idéntica verificada contra main: launch cmds (con y sin prompt), render README, login verify cmds (oracle CP-02 con `ubuntu`) |
| T2 choosers+login+finale | completada | `c93ca28` | Menú de choosers byte-idéntico al heredoc viejo (`printf '  - %-13s%s'`); cero `== "cli"` en los 4 archivos |
| T3 scaffold+biab+browser | completada | `2b8c620` | Filtros jq de install_hooks y statusline: cero diff vs main. Seed agy verificado funcionalmente (caso fresh y caso merge) idéntico al bloque de main. Wrapper `biab` simulado en homes claude-only y agy: mismos symlinks que main |
| T4 launcher+smoke | completada | `8ee6e49` | Smoke PASS x2 con secciones nuevas (completitud, EC-01, EC-04 inyección, EC-05 cold-source). Incluye fix: `ai_cli_skills_dirs` propagaba exit 0 con CLI inválido por el subshell del `$( )` |
| T5 CI matrix | completada | `5dd98ba` | `list-clis` emite `["claude","antigravity"]`; `dryrun` usa `fromJSON` con `needs` |
| T6 paridad global | completada | — (verificación) | Smoke x2 PASS, grep de dispatch vacío, diff README vs awk de main vacío para ambos CLIs |

### Decisiones tomadas

- **Contradicción interna de la spec en T3 (pre-seed agy):** §2.2, la acción de
  T3 y la regresión FEAT-018/019 de §4.3 exigen mover el merge de settings agy
  a `ai_cli_seed_settings` en `ai-cli.sh`, pero el diff-guard jq del `<verify>`
  de T3 (y AC #5 / regresión FEAT-015) detecta la línea `'. * $ours'`
  RELOCALIZADA como si fuera un cambio de filtro. Se siguió el diseño §2.2
  (mover el bloque entero, texto del filtro jq byte-idéntico en su nueva
  ubicación) y se sustituyó el guard por una verificación equivalente y más
  precisa: (1) diff del programa jq de `install_hooks` (dedupe_groups) vs main
  → cero diff; (2) diff del cuerpo del bloque statusline vs main → cero diff;
  (3) paridad funcional del seed (caso settings inexistente y caso merge con
  claves de usuario) → JSON idéntico al que produce el bloque de main. La
  única línea que el grep literal del verify detecta es la del pre-seed
  movida, cuya semántica está cubierta por (3).
- **EC-04 en el smoke con PATH stub:** ejecutar el launch cmd hostil tal cual
  lanzaría el CLI real en máquinas que lo tienen instalado (la del maintainer). Se
  ejecuta bajo `PATH` que solo contiene `touch`: si el escape %q regresara, el
  `touch` inyectado se ejecuta y crea el marker; si es correcto, no.
- **Copy del finale SSH:** solo se interpola `ai_cli_display_name` donde el
  texto viejo decía "Antigravity (agy)" (línea "Stack installed. … logged
  in."). Las menciones posteriores a `agy` ("already running agy", "agy is
  already there") se conservan literales — paridad byte-idéntica manda; no hay
  prop de "nombre corto de comando" en la API §2.2 y añadirla sería scope
  creep. Un CLI futuro sin remote-control heredará ese copy y podrá
  generalizarse en su FEAT.
- **Fallback del launcher eliminado:** el `else echo "$ai_cli"` de
  `launch_cmd_for` (ejecutar el nombre del CLI como comando si no era
  claude/antigravity) desaparece: ahora `ai_cli_launch_cmd` valida y muere con
  mensaje claro (EC-01). Ese fallback era inalcanzable con state válido.
- **chown del browser pack:** ahora chown-ea los skills dirs derivados del
  registro; en boxes agy eso añade `~/.gemini/skills` (que el scaffold ya
  dejó con el owner correcto → no-op observable). Antes solo agents+claude.
- **`warn` del chooser no interactivo:** el texto
  "(use --ai-cli=antigravity to override)" se conserva literal (es copy, no
  dispatch); el default se interpola desde `BIB_SUPPORTED_AI_CLIS[0]`.
- **Prueba de extensibilidad (CP-05 / AC #7), commit descartable `95e36dc`
  (eliminado con `git reset --hard`, no queda en la branch):** añadido CLI
  `dummy` (bloque adapter + `install/99-dummy.sh` stub). Resultado: (paso 3)
  `git status --porcelain` mostró exactamente 2 paths; (paso 4)
  `BIB_AI_CLI=dummy wiring-smoke` → PASS con "registry completeness (claude
  antigravity dummy)"; (paso 5) la lista emitió
  `["claude","antigravity","dummy"]` — la matrix de CI lo recogería sola;
  (paso 6) `prompt_choice` en ambos choosers deriva de
  `"${BIB_SUPPORTED_AI_CLIS[@]}"`, cero literales. Ningún otro archivo tocado.
- **`tools/reset-for-gift.sh`:** fuera de alcance según §2.3; añadido TODO
  con fecha apuntando a este FEAT.

### Blockers

- [x] Ninguno

### Verificacion post-implementacion

- [x] Todos los `<verify>` de cada tarea pasan (T3: guard jq sustituido por la
      verificación equivalente documentada arriba; resto literal)
- [x] CI completa pasa (shellcheck, bash -n, guards, dryrun matrix)
      (PR #30: lint, list-clis, dryrun claude, dryrun antigravity,
      browser-pack-tests — todos verdes)
- [x] Criterios de aceptacion globales verificados (el #6 CI-verde pendiente
      de la PR; el resto ejecutados en local: smoke x2, grep dispatch vacío,
      shellcheck/bash -n limpio a severidad CI, paridad README, filtros jq
      intactos, extensibilidad dummy)
- [x] Sin secrets en el diff
- [x] Sin cambios fuera del scope (12 archivos de la tabla 2.4 + TODO en
      tools/reset-for-gift.sh pedido por §2.3 + esta spec)

---

## 6. Feedback (Jesus — post-implementacion)

### Bugs encontrados

- —

### Mejoras sugeridas

- [pr-review 2026-08-02, nit] `wizard/run.sh` finale: menciones "agy" literales fuera de la rama
  `remote-control` — correcto con 2 CLIs, pero el FEAT que añada un tercer CLI sin remote-control
  debe interpolar ese copy (recordatorio para Wave 3).
- [pr-review 2026-08-02, nit] EARS req1 menciona "capacidad quota" pero el registro la empaqueta
  dentro de `hooks` (no capability separada). Comportamiento correcto; imprecisión de redacción.
