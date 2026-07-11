# FEAT-017: Specs visibles al arrancar sesión + skills distribuidas como plugin

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** media (post-flip; no bloquea launch)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts bash + config Claude Code. Verificación = box de prueba (o VM) con scaffold completo: disparar cada pieza en una sesión real.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** requisitos
- **Creado:** 2026-07-11
- **Actualizado:** 2026-07-11
- **Depende de:** FEAT-015 (default hooks — misma infraestructura de instalación de hooks del scaffold)

- **Validado por Jesus:** [ ]

---

## Definition of Ready (DoR)

### Producto (§1) — owner Elena
- [x] Problema explicito
- [x] Intent (why) rellenado
- [x] ≥1 historia de usuario
- [x] ≥3 requisitos funcionales EARS
- [x] Boundaries §3 con Always/Ask First/Never

### Spec Tecnica (§2) — owner Laura
- [ ] Investigacion previa con rutas verificadas
- [ ] Tabla archivos afectados
- [ ] ≥1 task con verify/done
- [ ] Patron de codigo real
- [ ] Criterios globales verificables

### QA (§4) — owner Pablo
- [ ] ≥1 funcional + ≥1 edge + ≥1 regresion
- [ ] Criterios de testing ejecutables

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

_Pendiente — rellenar con sdd-spec-writer. Referencia upstream: `ai-platform/core/claude-harness/hooks/session-start-specs.sh` (hook, portar+traducir), `ai-platform/core/claude-harness/plugins/` (estructura marketplace+plugin, PR ai-platform 2026-07-11). Investigar: soporte de plugins en Antigravity; instalación de marketplace desde repo git público vs path local; interacción con `payload/skills/manifest.tsv` y el instalador de FEAT-015._

---

## 4. QA (Pablo)

_Pendiente — rellenar con sdd-qa._

---

## 5. Docs

_Pendiente. Tocará como mínimo: `docs/architecture.md` (canal de updates de skills), README del payload, copy del tutorial si menciona skills._

---

## 6. Feedback

_(vacío)_
