# FEAT-015: Hooks por defecto (guardrail + formateo + lint + log de sesión)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (pre-launch — se anuncia en la propuesta de valor de la landing)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts + config de hooks de Claude Code. Verificación = disparar cada hook en una sesión real y observar el efecto.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** requisitos
- **Creado:** 2026-07-11
- **Actualizado:** 2026-07-11
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
- [ ] Canal + metrica + target o N/A

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

> Pendiente — spawn sdd-spec-writer.

---

## 3. Boundaries

### Always
- Hooks agnósticos de lenguaje, no-op limpio si falta la herramienta.
- Fail-open en formateo/lint/log (nunca romper la acción del agente); fail-closed solo en el guardrail.
- Desactivables y documentados.
- `set -euo pipefail`, idempotente, inglés.
- Instalar vía el scaffold existente (`40-scaffold.sh`), en la config del usuario.

### Ask First
- La lista exacta de comandos que el guardrail bloquea (falsos positivos molestan; falsos negativos son peligrosos) — revisión de Jesus antes de fijarla.
- Cualquier hook que envíe datos fuera de la caja (el log es LOCAL; nada de telemetría sin OK explícito).
- Desplegar copy de `site/` (gate de Jesus).

### Never
- Telemetría o envío de datos del usuario fuera de la caja.
- Un guardrail tan agresivo que rompa flujos normales (bloquear solo lo inequívocamente destructivo).
- Hooks que dependan de un lenguaje concreto sin degradar.
- Persistir secretos en el log de sesión.
- Flip a público dentro de este FEAT.

---

## 4. QA (Pablo)

> Pendiente — spawn sdd-qa después de §2.

---

## 5. Implementacion (Laura)

### Branch
`feat/FEAT-015`

### Decisiones tomadas
- [2026-07-11] Jesus eligió los 4 hooks (guardrail + formateo + lint + log) para shippar antes del flip, para anunciar "hooks" con verdad.

---

## 6. Feedback (Jesus)

—
