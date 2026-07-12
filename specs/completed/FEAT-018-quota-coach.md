# FEAT-018: Quota coach — visibilidad y frenos de consumo del plan Claude en la box

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** media (post-launch — refuerza la propuesta "práctica madura, no agente en blanco")
- **Complejidad:** media
- **E2E mode:** none
  > Scripts bash/python + skill + hook de Claude Code. Verificación = correr el agregador contra transcripts reales, disparar el hook en sesión real y observar el statusline.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** completado
- **Creado:** 2026-07-11
- **Actualizado:** 2026-07-11
  <!-- Adaptación del quota coach de ai-platform (PR #271) a la realidad BIAB -->

- **Validado por Jesus:** [x] (2026-07-12 — "implementa FEAT 18"; merged #24, VM-verified)

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
- [x] N/A métrica directa — pero "quota coach" es ítem anunciable en landing/README (misma categoría que "hooks" en FEAT-015)

---

## 1. Requisitos (Elena)

### Problema

Una box BIAB corre Claude Code desatendido: el usuario la maneja desde el móvil, con hooks, skills y sesiones largas en tmux que consumen su plan personal (Pro/Max) sin que él lo vea. La cuota real del plan **no es accesible programáticamente** (solo `/usage` interactivo), así que cuando el usuario se topa con el rate limit ya es tarde: no sabe qué proyecto, qué modelo o qué subagente se comió la semana. En ai-platform este mismo problema se resolvió con un "quota coach" (PR #271) que demostró en su primera ejecución que el 95% del gasto iba a modelos caros contra una política declarada de Sonnet-default. Una box heredada de BIAB debería traer esa visibilidad de serie.

### Intent (why)

La promesa de BIAB es "no heredas un agente en blanco, heredas una práctica madura". Una práctica madura incluye saber cuánto quemas y dónde. Para un usuario que paga su propio plan, el coach convierte una factura opaca en decisiones concretas (bajar de modelo, bajar effort, agrupar sesiones), y reduce el riesgo #1 de churn de una box desatendida: "me fundí el plan en dos días y no sé por qué".

### Solucion propuesta

Portar el quota coach de ai-platform adaptado a la realidad BIAB, con 3 piezas sobre un mismo agregador:

1. **Skill `quota`** (core, bundled) — script python (stdlib-only) que reconstruye el consumo desde los transcripts locales (`~/.claude/projects/**/*.jsonl`), pondera tokens por precio API de cada modelo ("$eq", proxy de cuota) y saca reporte por modelo/proyecto/día con flags accionables. En inglés (audiencia internacional).
2. **Hook `biab-quota-nudge.sh`** (UserPromptSubmit) — si la sesión corre en un modelo caro (Opus/Fable), inyecta 1 vez por sesión/día el burn semanal y sugiere `/model sonnet` / `/effort low` para trabajo rutinario. Neutral: BIAB no impone política de modelo, informa.
3. **Statusline opcional** — segmento `wk $Neq` coloreado por tendencia semanal. Solo se instala si el usuario NO tiene `statusLine` propio configurado.

### Historias de usuario

- Como usuario de BIAB con plan Pro, quiero preguntar "how much have I burned this week?" y obtener un desglose por modelo y proyecto, para decidir dónde recortar antes de chocar con el rate limit.
- Como usuario que lanza sesiones largas desde el móvil, quiero un aviso al arrancar en un modelo caro con mi burn semanal, para bajar a Sonnet cuando la tarea no lo necesita.
- Como usuario nuevo, quiero ver mi burn semanal en el statusline sin configurar nada, para desarrollar intuición de coste desde el día 1.

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** El agregador shall reconstruir el consumo desde `~/.claude/projects/**/*.jsonl` ponderando tokens por precio API por modelo (input/output/cache read/cache write 5m-1h), sin dependencias fuera de la stdlib de python3.
- [ ] **Event-driven:** Cuando el usuario invoque la skill `quota`, el sistema shall presentar reporte por modelo/proyecto/día con % de subagentes, cache hit rate y flags accionables (modelo caro dominante, subagentes >40%, cache hit <50%).
- [ ] **Event-driven:** Cuando una sesión corra en modelo caro (opus/fable/mythos) y exista summary cacheado, el hook shall inyectar `additionalContext` con el burn semanal, máximo 1 vez por sesión y día.
- [ ] **State-driven:** Mientras el summary cacheado tenga >6h, el hook shall lanzar un refresh en background (flock, sin bloquear el prompt).
- [ ] **Optional:** Donde el usuario no tenga `statusLine` configurado en settings.json, el scaffold shall instalar el statusline BIAB con segmento `wk $Neq` coloreado vs semana anterior.
- [ ] **Unwanted:** Si `~/.claude/projects/` no existe o está vacío (box Antigravity, box recién estrenada), el agregador shall salir con mensaje claro ("no Claude Code transcripts found yet") y exit 0.
- [ ] **Unwanted:** Si el summary cacheado no existe, el hook shall salir silenciosamente (exit 0) sin bloquear ni ensuciar el prompt.

### Requisitos no funcionales

- Hook <100ms en el camino caliente (solo lee JSON pequeño; el parseo pesado va en background).
- Agregador con cache incremental por fichero (mtime+size): primera pasada completa, siguientes ~segundos.
- Todo user-facing en inglés. Sin referencias personales (CI personal-refs guard).
- Precios hardcodeados en una tabla `PRICES` única y comentada (mantenimiento explícito si Anthropic reprecia).

### Referencias visuales

Statusline: `Sonnet 5 · ⎇ main · myproject · ctx 41k 20% · wk $23eq` (segmento final verde/amarillo/rojo según burn vs semana anterior).

### Growth Notes (Andrea)

N/A métrica directa. Anunciable como bullet en landing/README junto a hooks: "built-in usage coach — know what your agent burns". Coordinar copy con FEAT-012 (launch demo assets) si sigue abierto.

---

## 2. Spec Tecnica (Laura)

### Investigacion previa

Rutas verificadas en el repo (2026-07-11):

- `payload/hooks/` — patrón existente: `biab-guardrail.sh`, `biab-format.sh`, `biab-lint.sh`, `biab-session-log.sh` + `lib.sh` compartida + `tests/run-tests.sh`.
- `payload/wizard/40-scaffold.sh:196` — `install_hooks()` registra hooks vía merge jq sobre settings.json; **skip explícito en boxes Antigravity** (línea 200, "Claude-format hooks not applicable").
- `payload/skills/manifest.tsv` — tiers `core|optional`; todo lo actual es core.
- No existe statusline en el payload hoy (verificado con find) — el segmento statusline es pieza nueva, de ahí la condición "solo si el usuario no tiene uno".
- Implementación de referencia (adaptar, no copiar literal): `ai-platform/core/claude-harness/skills/quota/scripts/quota_report.py`, `hooks/model-nudge.sh`, `statusline.py` (PR ai-platform#271). Diferencias a aplicar: inglés, sin política Sonnet-default de mhserver (mensaje neutral), convenciones biab-* (lib.sh, set -euo pipefail), guard python3/jq con `command -v`.

### Alcance

#### Incluye

- Skill `quota` (SKILL.md inglés + `scripts/quota_report.py`) como core en manifest.
- Hook `biab-quota-nudge.sh` + registro en `40-scaffold.sh` + tests.
- Statusline BIAB condicional (solo si no hay `statusLine` configurado).
- Docs: bullet en README de skills + entrada en `payload/docs/cli-skills-compatibility.md` (skill Claude-only).

#### NO incluye (OBLIGATORIO)

- Lectura de la cuota oficial del plan (no existe API; el coach es proxy $eq).
- Cambio automático de modelo/effort (los hooks solo pueden avisar).
- Integración con `morning-check` (posible FEAT futura: burn de ayer en el resumen matutino).
- Soporte Antigravity (sus transcripts no son formato Claude Code; skill sale con mensaje claro).
- Telemetría/envío de datos fuera de la box (nunca — ver Boundaries).

### Archivos afectados

| Archivo | Cambio |
|---------|--------|
| `payload/skills/quota/SKILL.md` | NUEVO — skill en inglés |
| `payload/skills/quota/scripts/quota_report.py` | NUEVO — agregador stdlib-only |
| `payload/skills/manifest.tsv` | +1 línea `quota	core` |
| `payload/hooks/biab-quota-nudge.sh` | NUEVO — nudge UserPromptSubmit |
| `payload/hooks/tests/run-tests.sh` | +casos para el nudge |
| `payload/wizard/40-scaffold.sh` | registro del hook en el bloque jq de `install_hooks()`; instalación condicional del statusline |
| `payload/statusline/biab-statusline.py` | NUEVO — statusline mínimo (modelo, ctx%, wk $eq) |
| `payload/docs/cli-skills-compatibility.md` | anotar `quota` como Claude-only |

### Dependencias

- python3 (garantizado en Ubuntu 24.04), jq (ya dependencia de FEAT-015), flock (util-linux, base).
- Ninguna librería python externa (stdlib only).

### Tareas

#### Wave 1 — agregador + skill

1. **Portar `quota_report.py`** con modos `--report --days N`, `--refresh`, `--summary`; cache en `~/.claude/cache/quota/`; salida en inglés; exit 0 con mensaje si no hay transcripts.
   - verify: `python3 quota_report.py --report --days 14` contra una box con historial produce tablas y flags; segunda run <5s; box vacía → mensaje "no transcripts" exit 0.
   - done: script + shebang + exec bit; shellcheck N/A (python), `python3 -m py_compile` pasa.
2. **SKILL.md** en inglés: proceso (run script → present flags first → map de recomendaciones model/effort/cache/subagents) + limitación explícita ($eq ≠ cuota oficial; `/usage` para el dato real).
   - verify: skill descubierta por Claude Code en box de prueba; invocación produce reporte.
   - done: manifest.tsv actualizado; personal-refs guard pasa.

#### Wave 2 — hook nudge (depende de wave 1)

3. **`biab-quota-nudge.sh`**: convenciones biab-* (lib.sh, guards `command -v jq/python3`), detección de modelo del transcript tail, marker 1×/sesión/día en `~/.claude/cache/quota/`, refresh background con flock si summary >6h, mensaje neutral en inglés ("This session runs on {model}. Last 7 days: ${N}eq burned, {H}% on expensive models. For routine work consider /model sonnet or /effort low.").
   - verify: primera invocación con summary presente y modelo opus emite additionalContext; segunda misma sesión = silencio; sin summary = exit 0 silencioso; modelo sonnet = exit 0.
   - done: shellcheck limpio; tests añadidos a `tests/run-tests.sh` pasan.
4. **Registro en `40-scaffold.sh`**: añadir al array UserPromptSubmit del bloque jq (crear el evento si no existe); mantener skip Antigravity.
   - verify: scaffold en box de prueba deja el hook en settings.json sin romper hooks previos del usuario (merge, no overwrite); re-run idempotente.
   - done: `bash -n` + shellcheck limpios.

#### Wave 3 — statusline condicional (depende de wave 1)

5. **`biab-statusline.py`** mínimo (modelo, ctx tokens/%, `wk $Neq` desde summary.json, colores ANSI) + instalación en scaffold **solo si** `jq -e '.statusLine' settings.json` falla.
   - verify: box sin statusline → instalado y pinta las 3 partes con stdin simulado; box con statusline previo → no se toca.
   - done: idempotente; py_compile pasa.

#### Wave final — Verificacion global

6. Correr `payload/hooks/tests/run-tests.sh` completo, scaffold end-to-end en box/VM de prueba (claude y antigravity), CI verde (shellcheck, bash -n, personal-refs, archive-cleanliness).

### Patron de codigo a seguir (OBLIGATORIO)

- Hooks: mismo esqueleto que `payload/hooks/biab-guardrail.sh` (lib.sh, `set -euo pipefail`, exit 0 en todo camino no-bloqueante, output JSON con jq -nc).
- Registro: mismo patrón jq-merge de `install_hooks()` en `40-scaffold.sh` (FEAT-015) — merge aditivo, nunca sobrescribir configuración del usuario.
- Referencia funcional: ai-platform PR #271 (adaptar mensajes/política, ver Investigación previa).

### Criterios de aceptacion (VERIFICABLES)

- [ ] En una box con historial, `quota` reporta $eq por modelo/proyecto/día y ≥1 flag cuando aplica; segunda ejecución <5s.
- [ ] Nudge: aparece 1 vez por sesión/día solo en modelos caros; nunca rompe el prompt (exit 0 en todos los caminos de error).
- [ ] Statusline: instalado solo en ausencia de uno previo; muestra `wk $Neq` con color de tendencia.
- [ ] Box Antigravity: scaffold no registra el hook; skill instalada responde con mensaje claro de no-soporte.
- [ ] CI completo verde; cero strings en español ni referencias personales en payload.

---

## 3. Boundaries

### Always

- Exit 0 en hooks ante cualquier error (una box desatendida no puede quedarse bloqueada por el coach).
- Merge aditivo sobre settings.json — preservar siempre la configuración previa del usuario.
- Todo el análisis 100% local: los transcripts y agregados nunca salen de la box.
- Mensajes neutrales: informar del coste, no imponer política de modelo.

### Ask First

- Cualquier envío de datos de uso fuera de la box (hoy: prohibido; si algún día se propone, opt-in explícito y FEAT propia).
- Cambiar el tier de la skill a `optional` o retirar el statusline condicional.
- Actualizar la tabla `PRICES` (verificar precios vigentes en docs de Anthropic antes).

### Never

- Telemetría silenciosa o analytics del uso del usuario.
- Sobrescribir un `statusLine` o hooks existentes del usuario.
- Bloquear un prompt (decisión `block`) desde el nudge — es informativo, no guardarraíl.
- Agregación pesada de transcripts en el camino síncrono del hook. Excepción acotada y aceptada: la detección del modelo actual lee solo la cola del transcript (`tac | head -500 | jq`) — el nudge necesita el modelo vigente *ahora* para decidir, así que mover esto a background rompería la feature. Coste medido en VM/box real: ~4ms en transcripts pequeños/medios, hasta ~100-120ms en un transcript grande (~65MB, usuario muy pesado), en el límite del NFR <100ms pero sin violar el contrato (el hook sigue no-bloqueante y exit 0). Toda agregación pesada sigue yendo al refresh en background.

---

## 4. QA (Pablo)

### Casos de prueba

#### Funcionales

1. Box con ≥1 semana de historial: `quota --report --days 14` → tablas por modelo/proyecto/día, % subagentes, cache hit; suma de $eq por modelo == total (±redondeo).
2. Sesión en opus con summary presente: primer prompt → additionalContext con burn semanal; prompt siguiente misma sesión → sin output.
3. Box virgen sin `statusLine`: tras scaffold, statusline instalado y funcional con stdin simulado de Claude Code.

#### Edge cases

4. `~/.claude/projects/` inexistente → skill: mensaje "no transcripts found yet", exit 0; hook: silencio, exit 0.
5. summary.json corrupto (JSON inválido) → hook y statusline salen limpios sin traza de error al usuario.
6. Transcript con líneas malformadas / modelos desconocidos / `<synthetic>` → agregador los salta sin abortar.
7. Dos prompts simultáneos con summary caducado → un solo refresh (flock), sin pileup de procesos python.
8. Usuario con hooks UserPromptSubmit propios ya configurados → registro añade sin borrar los suyos.

### Regresion

9. `payload/hooks/tests/run-tests.sh` completo pasa (guardrail/format/lint/session-log intactos tras tocar 40-scaffold.sh).
10. Scaffold Antigravity: comportamiento idéntico a FEAT-015 (skip hooks Claude-format), sin errores nuevos.
11. Re-run del scaffold (idempotencia): settings.json sin entradas duplicadas del hook.

### Criterios de testing

```bash
# Suite de hooks
bash payload/hooks/tests/run-tests.sh

# Sintaxis y lint
bash -n payload/wizard/40-scaffold.sh payload/hooks/biab-quota-nudge.sh
shellcheck payload/hooks/biab-quota-nudge.sh
python3 -m py_compile payload/skills/quota/scripts/quota_report.py payload/statusline/biab-statusline.py

# Manual en box de prueba
python3 ~/.claude/skills/quota/scripts/quota_report.py --report --days 7
echo '{"transcript_path":"<real>","session_id":"t1","prompt":"x"}' | bash <hooks-dir>/biab-quota-nudge.sh
```

---

## 5. Implementacion (Laura — se rellena durante la implementacion)

### Branch

`feat/FEAT-018-quota-coach`

### Progreso

| Task | Estado | Commit | Notas |
|------|--------|--------|-------|
| 1 quota_report.py | hecho | — | modos report/refresh/summary; cache incremental; empty-box exit 0 |
| 2 SKILL.md | hecho | — | inglés, tono neutral, +manifest quota=core |
| 3 biab-quota-nudge.sh | hecho | — | UserPromptSubmit; guards command -v; 1×/sesión/día; refresh background flock |
| 4 40-scaffold.sh | hecho | — | UserPromptSubmit en bloque jq; skip Antigravity intacto |
| 5 biab-statusline.py + install condicional | hecho | — | solo si no hay .statusLine; merge aditivo |
| 6 verificación global | hecho | — | run-tests.sh 76/76; shellcheck/bash -n/py_compile/personal-refs OK |

### Decisiones tomadas

- [2026-07-11] Adaptación de ai-platform PR #271; mensaje del nudge neutral (BIAB no impone Sonnet-default).
- [2026-07-12] Familia de modelo renombrada `fable-5`→`fable` (neutral); guard extra: registros con familia fuera de `PRICES` se saltan (robustez ante caché de versiones previas).
- [2026-07-12] project_from_path generalizado (sin rutas personales) para pasar el personal-refs guard.
- [2026-07-12] Statusline minimizado a 3 segmentos (modelo · ctx · wk $eq) según instrucción de scope.

### Blockers

- [ ] —

### Verificacion post-implementacion

- [x] Todos los `<verify>` de cada tarea pasan
- [x] `payload/hooks/tests/run-tests.sh` pasa (76 passed, 0 failed)
- [x] Criterios de aceptacion globales verificados
- [x] Sin secrets en el diff
- [x] Sin cambios fuera del scope
- [x] CI verde localmente (shellcheck -S warning, bash -n, personal-refs); archive-cleanliness N/A (statusline no export-ignored)
- [x] Verificación en VM real: scaffold end-to-end (claude + antigravity boxes) — joint disposable-VM pass 2026-07-12, additive merge + statusline + Antigravity path all confirmed

---

## 6. Feedback (Jesus — post-implementacion)

> Pendiente.
