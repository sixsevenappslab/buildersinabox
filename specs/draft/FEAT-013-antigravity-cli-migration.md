# FEAT-013: Migración del segundo CLI: Gemini CLI → Antigravity CLI (`agy`)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (bloquea el flip a público — decisión de Jesus 2026-07-09)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts de dispositivo (bash). La verificación automatizada es el dryrun harness; la validación real exige una pasada E2E en box headless física/VM (ver §4).
- **Reconciliation owner:** sdd-coordinator
- **Fase:** requisitos
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
- [ ] Investigacion previa rellenada con rutas reales verificadas (`ls`)
- [ ] Tabla "Archivos afectados" completa con accion (CREAR/MODIFICAR/ELIMINAR)
- [ ] Minimo 1 `<task>` con `<verify>` ejecutable y `<done>` observable (no "funciona bien")
- [ ] Patron de codigo con fragmento real del proyecto (10-20 lineas)
- [ ] Criterios de aceptacion globales verificables (no genericos)

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

> Pendiente — spawn sdd-spec-writer.

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

### Never

- Construir un bridge Slack/Telegram propio (ccgram/cc-connect se documentan, no se reimplementan — decisión del consejo 2026-07-09).
- Eliminar la opción `claude` ni degradar su experiencia actual.
- Abrir puertos públicos o añadir servicios expuestos (rompería el posicionamiento seguridad-primero).
- Tocar `.env`, credenciales o tokens; commitear secrets.
- Hacer el flip a público del repo dentro de este FEAT (es un gate separado de Jesus).
- Contenido de usuario final en rutas `export-ignore` de `.gitattributes`.

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
