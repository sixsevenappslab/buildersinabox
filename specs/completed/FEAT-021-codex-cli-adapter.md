# FEAT-021: Codex CLI adapter (Wave 3 del plan multi-CLI)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (Jesús decidió 2026-08-03: Wave 3 antes del launch)
- **Complejidad:** media
- **E2E mode:** none (smoke hermético + dryrun CI; E2E real en hardware el día del PC)
- **Reconciliation owner:** sdd-coordinator
- **Fase:** completada
- **Creado:** 2026-08-03
- **Actualizado:** 2026-08-03
- **Validado por Jesus:** [x] (2026-08-03)

---

## Definition of Ready (DoR)

### Producto (§1) — owner Elena
- [x] Problema explicito
- [x] Intent (why) rellenado
- [x] Minimo 1 historia de usuario verificable
- [x] Minimo 3 requisitos funcionales EARS con checkbox
- [x] Boundaries §3 con Always / Ask First / Never

### Spec Tecnica (§2) — owner Laura
- [x] Investigacion previa con rutas verificadas (agente contrato FEAT-020 + web research Codex, 2026-08-03)
- [x] Tabla archivos afectados con accion
- [x] Tasks con `<verify>` ejecutable y `<done>` observable
- [x] Patron de codigo real del proyecto
- [x] Criterios de aceptacion verificables

### QA (§4) — owner Pablo
- [x] Funcional + edge + regresion + criterios ejecutables

### Growth — owner Andrea
- [x] Rellenado: el titular multi-CLI del launch pasa de 2 a 3 CLIs.

---

## 1. Requisitos (Elena)

### Problema

BIAB soporta Claude Code y Antigravity, pero no Codex — el CLI del ecosistema ChatGPT, el de mayor base de usuarios potencial. Un usuario con suscripción ChatGPT (incluso Free) hoy no puede usar BIAB con su cuota.

### Intent (why)

Decisión de Jesús (2026-08-03): lanzar con 3 CLIs como titular ("works with Claude Code, Antigravity and Codex"). El blocker histórico de FEAT-001 ("no OAuth device flow", 2026-05) está **refutado**: OpenAI documenta `codex login --device-auth` para headless (código aprobable desde el móvil), con port-forward `:1455` como fallback. FEAT-020 dejó el coste marginal de un CLI nuevo en ~2 archivos.

### Solucion propuesta

`codex` aparece como tercera opción en los choosers del installer/wizard. El wizard guía el device-auth (incluido el toggle previo "device code login" en los Security Settings de ChatGPT). El box queda con Codex corriendo en tmux, leyendo `AGENTS.md` (que BIAB ya scaffolda) y las skills desde `~/.agents/skills` — que Codex lee **nativamente** (es su path estándar): cero symlinks nuevos.

### Historias de usuario

- Como usuario con ChatGPT Plus, quiero elegir Codex en el instalador y autenticarme desde el móvil con un código, para usar mi cuota ChatGPT en mi box sin navegador en la máquina.
- Como usuario de Codex, quiero que las skills del bundle (`$sdd-coordinator`, etc.) y el contexto AGENTS.md funcionen igual que en los otros CLIs.

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** El registry shall exponer `codex` como CLI soportado (choosers, scaffold, tmux, CI derivan solos del array).
- [ ] **Event-driven:** Cuando el usuario elija codex, el wizard shall explicar el toggle de Security Settings ANTES de lanzar `codex login --device-auth`.
- [ ] **Unwanted:** Si la verificación de login falla repetidamente, el sistema shall ofrecer el fallback documentado (`ssh -L 1455:localhost:1455` + login normal, o API key).
- [ ] **Ubicuo:** El finale del wizard shall usar el nombre de comando del CLI elegido (nueva prop `AI_CLI_COMMAND`) — elimina el nit "agy" literal de FEAT-020 (`wizard/run.sh:143,172`).
- [ ] **State-driven:** Mientras el CLI sea codex, el scaffold shall no crear symlinks de skills redundantes (su dir nativo ES `~/.agents/skills`, la fuente de verdad de BIAB).

### Requisitos no funcionales

- [ ] Paridad de invariantes FEAT-020: cero dispatch por nombre de CLI fuera de `ai-cli.sh`; `printf %q` en launch_cmd; sourceable en frío.
- [ ] Anuncio público de soporte Codex (README/landing) **gated** a la verificación en hardware real (TUI de Codex en tmux tiene bugs abiertos: colores, Enter tras completar tarea, corrupción tras corte de stream).

### Growth Notes (Andrea)

- **Canal:** Launch (Show HN / README). **Impacto:** titular "3 CLIs, bring your own subscription" — amplía el mercado direccionable a usuarios ChatGPT (todos los planes, incluso Free, incluyen Codex CLI).

---

## 2. Spec Tecnica (Laura)

### Investigacion previa

- **Contrato FEAT-020** (`payload/lib/ai-cli.sh`): añadir CLI = entrada en `BIB_SUPPORTED_AI_CLIS` (`:21`) + bloque adapter con 5 props (`AI_CLI_DISPLAY_NAME/CHOICE_HINT/INSTALL_SCRIPT/SKILLS_DIRS/CAPABILITIES`) + 6 verbos (`props`, `launch_cmd`, `login_verify_cmd`, `login_run`, `login_failure_hint`, `seed_settings`) + 1 install script. 12 sitios de consumo derivan solos (choosers `install.sh:384-392` y `wizard/05-choose-cli.sh:32-37`, login `38-ai-cli-login.sh`, finale `run.sh:134-137`, scaffold, `tmux/launch-main.sh`, `05-biab-command.sh`, browser pack, `test/wiring-smoke.sh:99-148`, CI matrix `list-clis`/`dryrun`, docs, README markers).
- **Codex (web research 2026-08-03):** npm `@openai/codex` v0.146.0 con binarios linux-x64/arm64; auth headless `codex login --device-auth` (requiere toggle en ChatGPT Security Settings; token en `~/.codex/auth.json` con auto-refresh); lee AGENTS.md en cadena (global → git-root → cwd); skills en `~/.agents/skills` (estándar cross-tool, invocación `$nombre` o implícita; `/nombre` solo vía custom prompts deprecados); config `~/.codex/config.toml`; sin hooks/statusline/remote-control.
- **Fit clave:** BIAB ya usa `~/.agents/skills` como fuente de verdad y ya scaffolda `AGENTS.md` en todos los boxes — Codex los consume nativamente sin adaptación.
- **Riesgos:** (1) toggle Security Settings = fricción de onboarding, mitigar con copy del wizard; (2) TUI en tmux con bugs abiertos (openai/codex #22761, #12645, #13842, #22726) — gate de hardware antes de anunciar; (3) `install_skill` intentaría symlink self-referencial si SKILLS_DIRS=".agents/skills" — el guard `[[ -e || -L ]]` lo salta (verificar en smoke); (4) invocación de skills es `$nombre`, no `/nombre` — el copy de onboarding que dice "type /tutorial" necesita rama codex.

### Alcance

**Incluye:** bloque adapter codex + prop nueva `AI_CLI_COMMAND` (3 CLIs) + `install/42-codex-cli.sh` + fix nit finale + ramas codex en copy de onboarding CLI-gated + fila en `docs/cli-skills-compatibility.md` + markers `BIB:codex` en `tutorial/desktop-readme.md`.
**NO incluye:** anuncio en README/landing/site (gated a hardware); harness personal `core/harness/codex/` (proyecto aparte); soporte de hooks/statusline para codex; pin sha256 del binario (npm firma; seguir patrón claude, no antigravity); migrar custom prompts.

### Archivos afectados

| Archivo | Accion |
|---------|--------|
| `payload/lib/ai-cli.sh` | MODIFICAR (array + bloque codex + prop `AI_CLI_COMMAND` en los 3 bloques + getter `ai_cli_command`) |
| `payload/install/42-codex-cli.sh` | CREAR |
| `payload/wizard/run.sh` | MODIFICAR (líneas 143 y 172: "agy" → `$(ai_cli_command ...)`) |
| `payload/skills/{tutorial,first-project,whats-ahead}/SKILL.md` | MODIFICAR (rama codex donde ya hay branch por CLI; `$skill` vs `/skill`) |
| `payload/docs/cli-skills-compatibility.md` | MODIFICAR |
| `payload/tutorial/desktop-readme.md` | MODIFICAR (bloques `<!-- BIB:codex:start -->`) |
| `payload/test/wiring-smoke.sh` | MODIFICAR solo si la sección completeness necesita el getter nuevo |

### Dependencias

- Ninguna nueva en el repo; en el box: `@openai/codex` vía npm (ya presente por `00-base.sh`).

### Tareas

#### Wave 1

<task id="1">
  <name>Bloque adapter codex + prop AI_CLI_COMMAND</name>
  <files>payload/lib/ai-cli.sh</files>
  <action>Añadir "codex" a BIB_SUPPORTED_AI_CLIS. Bloque adapter: DISPLAY_NAME="Codex CLI"; CHOICE_HINT="OpenAI Codex — sign in with your ChatGPT account"; INSTALL_SCRIPT="install/42-codex-cli.sh"; SKILLS_DIRS=".agents/skills"; CAPABILITIES="" (sin hooks/statusline/remote-control). Verbos: launch_cmd (binario `codex`, initial prompt con printf %q; para el tutorial usar prompt en lenguaje natural, no slash); login_verify_cmd (no interactivo, exit 0 sii autenticado — `codex login status` o test de `~/.codex/auth.json`, confirmar subcomando en implementación); login_run (copy explicando el toggle "device code login" en ChatGPT Security Settings ANTES de ejecutar `codex login --device-auth` como target user); login_failure_hint (toggle + fallback `ssh -L 1455:localhost:1455` + API key); seed_settings (`:` salvo que el dryrun demuestre que el primer arranque necesita `~/.codex/config.toml` pre-sembrado). Prop nueva AI_CLI_COMMAND ("claude"/"agy"/"codex") en los TRES bloques + getter público `ai_cli_command` siguiendo el patrón de los getters existentes.</action>
  <verify>BIB_AI_CLI=codex bash payload/test/wiring-smoke.sh</verify>
  <done>Smoke PASS con "registry completeness (claude antigravity codex)"; cold-source (env -i) sigue pasando.</done>
</task>

<task id="2">
  <name>Install script 42-codex-cli.sh</name>
  <files>payload/install/42-codex-cli.sh</files>
  <action>Patrón de 40-claude-code.sh (npm install -g @openai/codex; idempotencia por `command -v codex`; require_root; source ../lib/common.sh). Sin pin sha256 (patrón claude, no antigravity).</action>
  <verify>bash -n payload/install/42-codex-cli.sh && shellcheck payload/install/42-codex-cli.sh</verify>
  <done>Sintaxis y shellcheck limpios; estructura espejo de 40-claude-code.sh.</done>
</task>

#### Wave 2

<task id="3">
  <name>Fix nit finale: "agy" literal → ai_cli_command</name>
  <files>payload/wizard/run.sh</files>
  <action>En la rama SSH del finale (sin remote-control), sustituir "agy" literal (líneas ~143 y ~172) por interpolación de `$(ai_cli_command "$cli")`. El copy de la rama remote-control no cambia.</action>
  <verify>grep -n '\bagy\b' payload/wizard/run.sh | grep -v ai_cli || echo CLEAN</verify>
  <done>CLEAN; un box codex mostraría "codex is already there..." en el finale.</done>
</task>

<task id="4">
  <name>Onboarding y docs con rama codex</name>
  <files>payload/skills/{tutorial,first-project,whats-ahead}/SKILL.md, payload/docs/cli-skills-compatibility.md, payload/tutorial/desktop-readme.md</files>
  <action>Donde esas skills ya ramifican por CLI (claude vs agy), añadir rama codex: invocación de skills con `$nombre` (no `/nombre`), sin app companion ni remote sessions (mismo tratamiento que agy), AGENTS.md como context file. Fila codex en cli-skills-compatibility.md (dir nativo `~/.agents/skills`, sin symlinks). Bloques `<!-- BIB:codex:start -->` en desktop-readme.md. Cambios de copy mínimos, en inglés.</action>
  <verify>grep -c "BIB:codex" payload/tutorial/desktop-readme.md && grep -c codex payload/docs/cli-skills-compatibility.md</verify>
  <done>Ambos greps > 0; las 3 skills tienen rama codex coherente con su rama agy existente.</done>
</task>

#### Wave final

<task id="5">
  <name>Verificación global + PR</name>
  <files>payload/</files>
  <action>Correr wiring-smoke con los 3 CLIs; regenerar lista CI (`source payload/lib/ai-cli.sh; printf ...`) → ["claude","antigravity","codex"]; guard cero-dispatch (`grep -rnE '== *"(claude|antigravity|codex)"' payload --include='*.sh' | grep -v ai-cli.sh | grep -v test/`); guard personal-refs; PR con CI (aparecerá `dryrun (codex)` en la matrix).</action>
  <verify>for c in claude antigravity codex; do BIB_AI_CLI=$c bash payload/test/wiring-smoke.sh || exit 1; done && bash tools/check-no-personal-refs.sh</verify>
  <done>3× smoke PASS, guards limpios, CI de la PR verde incluyendo dryrun (codex).</done>
</task>

### Patron de codigo a seguir

Bloque adapter existente (`payload/lib/ai-cli.sh`, patrón antigravity):

```bash
_ai_cli_props__antigravity() {
    AI_CLI_DISPLAY_NAME="Antigravity (agy)"
    AI_CLI_CHOICE_HINT="Google's agentic CLI, free Gemini quota"
    AI_CLI_INSTALL_SCRIPT="install/41-antigravity-cli.sh"
    AI_CLI_SKILLS_DIRS=$'.claude/skills\n.gemini/skills'
    AI_CLI_CAPABILITIES=""
}
```

### Criterios de aceptacion (VERIFICABLES)

- [ ] `BIB_AI_CLI=codex bash payload/test/wiring-smoke.sh` → PASS.
- [ ] Lista CI = `["claude","antigravity","codex"]`; job `dryrun (codex)` verde.
- [ ] `git diff --stat` de Wave 1 ≈ 2 archivos (ai-cli.sh + install script) — valida la promesa de FEAT-020.
- [ ] Cero "agy" literal en `wizard/run.sh` fuera de interpolaciones.
- [ ] **Gate de anuncio:** E2E en hardware real (día PC): device-auth desde móvil OK + sesión tmux usable → solo entonces se toca README/landing.

---

## 3. Boundaries

### Always
- Invariantes FEAT-020: validate antes de dispatch, `printf %q`, cero side-effects top-level, sourceable en frío.
- Copy en inglés; commits `feat:`/`fix:`; PR + CI verde.

### Ask First
- Pre-sembrar `~/.codex/config.toml` con cualquier default no trivial (modelo, approval mode).
- Cualquier cambio en el flujo de login de los otros 2 CLIs.
- Tocar README público / landing / site (gated a hardware).

### Never
- Dispatch por nombre de CLI fuera de `ai-cli.sh`.
- Tocar `manifest.tsv`, flujo de skills, o los installers de claude/antigravity.
- Anunciar soporte Codex públicamente antes del E2E en hardware.

---

## 4. QA (Pablo)

### Casos de prueba

#### Funcionales
| # | Caso | Pasos | Resultado esperado | Estado |
|---|------|-------|--------------------|--------|
| 1 | Registry completeness codex | 1. `BIB_AI_CLI=codex bash payload/test/wiring-smoke.sh` | PASS; sección 6 lista los 3 CLIs | pendiente |
| 2 | Choosers derivan solos | 1. grep de los choosers: sin literal "codex" añadido a mano en install.sh / 05-choose-cli.sh | 0 hits (derivan del array) | pendiente |
| 3 | E2E hardware (día PC) | 1. Install eligiendo codex 2. Toggle Security Settings 3. `--device-auth` aprobado desde móvil 4. Sesión tmux + `$sdd-coordinator` | Login persiste (`~/.codex/auth.json`), skill responde, AGENTS.md cargado | pendiente |

#### Edge cases
| # | Caso | Pasos | Resultado esperado | Estado |
|---|------|-------|--------------------|--------|
| 1 | Symlink self-referencial de skills | 1. Scaffold con codex (dryrun) 2. Revisar `~/.agents/skills/` | `install_skill` salta el link (target ya existe); sin loops ni errores | pendiente |
| 2 | Login sin toggle activado | 1. `codex login --device-auth` con device-auth deshabilitado en la cuenta | `login_failure_hint` muestra toggle + fallback port-forward | pendiente |
| 3 | CLI inválido sigue fallando limpio | 1. `ai_cli_display_name bogus` | die limpio (EC-01 de FEAT-020) | pendiente |

### Regresion
- [ ] `BIB_AI_CLI=claude` y `BIB_AI_CLI=antigravity` wiring-smoke PASS (sin regresión por la prop nueva).
- [ ] Finale rama remote-control (claude) byte-idéntico; rama SSH con agy sigue diciendo "agy" (ahora interpolado).
- [ ] Browser pack install/uninstall no afectado.

### Criterios de testing
```bash
for c in claude antigravity codex; do BIB_AI_CLI=$c bash payload/test/wiring-smoke.sh; done
bash -c 'source payload/lib/ai-cli.sh; printf "%s\n" "${BIB_SUPPORTED_AI_CLIS[@]}" | jq -R . | jq -cs .'
grep -n '\bagy\b' payload/wizard/run.sh | grep -v ai_cli
bash tools/check-no-personal-refs.sh
```

---

## 5. Implementacion (se rellena durante la implementacion)

### Branch
`feat/FEAT-021-codex-adapter`

### Progreso
| Task | Estado | Commit | Notas |
|------|--------|--------|-------|
| 1-5 | hecho | 2059ece + c8230a9 (PR #32, mergeada 2026-08-03) | review APROBADO (2 nits corregidos: README gated por CLI, copy "Both"→"All"). Pendiente NO bloqueante: E2E hardware día PC = gate del anuncio público |

### Blockers
- [x] Validación de Jesús — OK 2026-08-03.

---

## 6. Feedback (Jesus — post-implementacion)

—
