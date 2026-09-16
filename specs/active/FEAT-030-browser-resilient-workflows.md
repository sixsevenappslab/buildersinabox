# FEAT-030: Browser resilient workflows

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta — desbloquea navegación web útil desde Ubuntu Server
- **Complejidad:** media — cambia el contrato del CLI y la estrategia de ejecución
- **E2E mode:** fixtures locales deterministas + smoke manual opcional en sitios reales
- **Depende de:** FEAT-017 (browser pack)
- **Fase:** implementación — código, tests y docs completos; pendiente review + PR
- **Creado:** 2026-09-14
- **Actualizado:** 2026-09-16
- **Validado por Jesus:** [x] — pidió implementar el piloto para que funcione out of the box

## Contexto

BIAB mantiene Ubuntu Server como sistema base y el browser pack como capacidad opt-in.
El piloto real mostró que el Chromium headless de escritorio puede ser bloqueado por
sitios como Sephora o Reddit, mientras que una emulación iPhone o un Chromium headful
bajo Xvfb sí consigue cargar la página. También mostró que los verbos aislados actuales
(`fill`, `click`) no sirven para una tarea de varios pasos porque cada invocación cierra
el navegador y pierde el estado vivo del DOM.

Esta FEAT convierte esos hallazgos en un comportamiento estable del pack. Después de
`biab pack add browser`, el usuario o agente obtiene un modo `auto` por defecto y puede
ejecutar una secuencia de acciones en una sola página y un solo proceso. No añade un
desktop a Ubuntu Server, un daemon, evasión stealth, proxies ni resolución automática
de CAPTCHA.

## 1. Requisitos

- [x] R1 — WHEN se usa `biab-browse` sin elegir modo, THE SYSTEM SHALL intentar la
      navegación inicial en este orden: desktop headless, iPhone headless y desktop
      headful bajo Xvfb.
- [x] R2 — WHEN la navegación inicial devuelve un bloqueo compatible con fallback,
      THE SYSTEM SHALL cambiar al siguiente modo únicamente antes de ejecutar ninguna
      acción. Nunca repetirá automáticamente un click, fill o workflow parcialmente
      ejecutado.
- [x] R3 — WHEN la página carga o falla por una causa distinta de un bloqueo compatible,
      THE SYSTEM SHALL detenerse sin probar otro modo. DNS, TLS, timeout, HTTP 401/404/
      429/5xx y CAPTCHA no activan fallback.
- [x] R4 — WHEN se pasa `--mode desktop|iphone|headful|auto`, THE SYSTEM SHALL usar
      exactamente el modo solicitado; `--headful-xvfb` seguirá funcionando como alias
      compatible de `--mode headful`.
- [x] R5 — WHEN se ejecuta `biab-browse run <url>` con un workflow JSON por stdin,
      THE SYSTEM SHALL validar y ejecutar, en el mismo navegador y por orden, hasta 20
      acciones `fill`, `click`, `select`, `wait_for` o `read_text`, deteniéndose en el
      primer error.
- [x] R6 — WHEN el workflow contiene valores sensibles, THE SYSTEM SHALL no ponerlos
      en argv ni registrarlos; stdin se copiará a un fichero temporal en un directorio
      root-owned que el browser user puede leer pero no escribir, y se eliminará al
      terminar. *(Corregido en review: la redacción original decía "0600 dentro del área
      privada del browser user" — ese diseño es el bug, ver Decisiones 2026-09-16.)*
- [x] R7 — WHEN se emula iPhone, THE SYSTEM SHALL aplicar viewport, touch y user-agent
      del dispositivo mediante CDP antes de navegar. Esto es emulación de Chromium, no
      Safari real, y se documentará así.
- [x] R8 — WHEN el fallback llega a headful, THE SYSTEM SHALL reutilizar el mecanismo
      lazy de Xvfb ya existente. El browser seguirá ejecutándose como `biab-browser`,
      sandboxed y con una sola ejecución concurrente.
- [x] R9 — WHEN un usuario consulta la skill, ayuda o arquitectura, THE SYSTEM SHALL
      explicar el modo auto, los modos manuales, workflows y límites honestos.

## 2. Diseño técnico

### CLI

```text
biab-browse [--mode auto|desktop|iphone|headful] [--profile NAME] open URL VERB [ARGS...]
biab-browse [--mode auto|desktop|iphone|headful] [--profile NAME] run URL < workflow.json
```

`auto` es el default. Los comandos `open URL read_text|click|fill|screenshot` siguen
siendo compatibles. `run` recibe un objeto JSON con una propiedad `actions`:

```json
{"actions":[{"action":"fill","selector":"#q","value":"hello"},{"action":"click","selector":"button"},{"action":"read_text","selector":"#result"}]}
```

### Política de fallback

El driver devuelve el código reservado `6` solo cuando la respuesta inicial es un
bloqueo reconocido antes de acciones. El wrapper es el único responsable de avanzar
al siguiente modo. La detección será deliberadamente estrecha: status 403 combinado
con título/cuerpo inequívoco, o una página corta con una frase de bloqueo conocida.
Una página normal que mencione “Access denied” en un artículo no debe dispararla.

Cada intento efímero usa un perfil nuevo. Un `--profile NAME` reutiliza expresamente
el perfil persistente entre intentos para conservar login/cookies.

### Workflow

El wrapper limita stdin a 64 KiB antes de elevar/copiar y crea el fichero bajo
`/run/biab-browser` (root-owned, 0711), **no** bajo `/var/lib/biab-browser`. El driver valida el esquema completo antes de navegar: objeto
raíz, array no vacío, máximo 20 acciones, campos y tipos permitidos, sin propiedades de
acción desconocidas. Los resultados `read_text` se imprimen en orden; las acciones de
mutación solo imprimen confirmaciones sin incluir `value`.

### Seguridad y privacidad

- Se preservan el usuario dedicado, `flock`, sandbox fail-closed y validación de
  screenshot de FEAT-017.
- No se añaden flags stealth, proxies, bypass de CAPTCHA ni credenciales compartidas.
- No hay telemetría remota. El modo finalmente usado se informa por stderr.
- Xvfb no expone un escritorio ni un puerto; solo proporciona display local temporal.

## 3. Boundaries

- **Always:** fallback antes de acciones; máximo tres intentos; sandbox activo;
  aislamiento por usuario; compatibilidad con los verbos actuales.
- **Ask first:** añadir un daemon/MCP persistente, automatizar login, compartir un
  perfil entre personas, o relajar el sandbox.
- **Never:** resolver CAPTCHA, ocultar automatización mediante stealth, rotar proxies,
  reintentar automáticamente una acción con efectos, instalar Ubuntu Desktop o exigir
  un Mac auxiliar.

## 4. QA

1. [x] El selector de modos devuelve `desktop-headless → iphone-headless →
   desktop-headful` para auto y un único intento para modos explícitos.
2. [x] Fixture local: desktop bloqueado + iPhone permitido; desktop devuelve 6,
   iPhone carga y reporta user-agent móvil.
3. [x] Fixture local: texto editorial que contiene “Access denied” no da falso positivo.
4. [x] Workflow fill → click → wait_for → read_text conserva el estado y devuelve el
   resultado final; un fallo intermedio detiene las acciones posteriores.
5. [x] JSON inválido, más de 20 acciones, acción/campo desconocido o stdin >64 KiB se
   rechazan con exit 2 sin navegar.
6. [x] Regresión: verbos existentes, screenshot, perfiles, lock y sandbox mantienen
   sus contratos.
7. [x] `bash -n`, `shellcheck`, personal-refs guard y suite del browser pack en verde.
8. [ ] Smoke manual opcional (no CI) en Sephora/Reddit documenta fecha y resultado sin
   convertir disponibilidad de terceros en criterio de aceptación.
   *Sigue abierto a propósito: el piloto del 2026-09-14 ya lo midió una vez, pero no
   es criterio de aceptación y no se repite en CI.*

## 5. Documentación

- `payload/pack/browser/skill/browser/SKILL.md`: receta recomendada y ejemplos.
- `docs/architecture.md`: estrategia de modos/fallback y límites.
- `README.md`: promesa breve y honesta del pack opt-in.
- Ayuda integrada de `biab-browse` como referencia operativa.

## 6. Implementación

### Branch

`feat/feat-030-browser-resilience`

### Progreso

| Task | Estado | Notas |
|---|---|---|
| Spec y tracking | hecho | alcance validado en conversación |
| CLI y fallback | hecho | `--mode` + escalera en `bin/biab-browse`, `browser_mode_attempts()` en `lib.sh` |
| Driver iPhone y workflow | hecho | emulación CDP + `run`; detector de bloqueo y esquema extraídos a `driver/lib.mjs` |
| Tests y docs | hecho | 44 casos nuevos (25 → 69, Secciones A+B en verde con Chromium real); SKILL.md, architecture.md, README, CHANGELOG |
| Review y PR | en curso | |

### Decisiones
- [2026-09-16] El trabajo estuvo sin commitear en `/tmp` desde el 14-09 (sesión de
  Codex Desktop que no llegó a cerrar). Rescatado en `24f0591`, worktree movido a
  `~/.worktrees/buildersinabox/feat-030-browser-resilience`.
- [2026-09-16] Las funciones puras del driver (detección de bloqueo y validación de
  workflow) viven en `driver/lib.mjs`, no dentro de `browse.mjs`. Motivo: son las dos
  decisiones que tienen que ser correctas exista o no un Chromium en el runner, y así
  se testean con `node` pelado — sin playwright, sin red.
- [2026-09-16] El slurp de stdin es `head -c`, no `dd bs=N count=1`. Medido: `dd` hace
  un solo `read(2)` y truncó un payload partido en dos escrituras (10512 de 10548
  bytes) en silencio. Aislado en `read_bounded_stdin()` en `lib.sh` para poder
  testear la regresión.
- [2026-09-16] El workflow se stagea en `/run/biab-browser` (root, 0711), no bajo
  `$BROWSER_HOME`. Motivo: en el resto del pack escribe el browser user y root solo
  lee de vuelta con recheck, así que que `biab-browser` sea dueño de esos directorios
  está bien. Un workflow invierte la dirección — escribe root — y el permiso de
  escritura sobre un *directorio* es lo que gobierna rename/unlink, sea de quien sea
  la entrada. Staged bajo `$BROWSER_HOME`, `biab-browser` podía cambiar la ruta por un
  symlink entre el `mktemp` y el `chmod`/escritura de root.
- [2026-09-16] Los comentarios de seguridad de FEAT-017 (arbitrary-write del
  screenshot, los dos TOCTOU, el `env_keep` del sudoers, el fail-closed del sandbox)
  se restauran tal cual. La reescritura los había borrado dejando el código intacto;
  el código sin el porqué es lo que hace que el siguiente lo rompa sin enterarse.

- [2026-09-14] Ubuntu Server sigue siendo el sistema base y browser sigue siendo un
  pack opt-in; “out of the box” significa listo tras `biab pack add browser`.
- [2026-09-14] `auto` es el default y el orden se fija en desktop headless, iPhone
  headless, desktop headful/Xvfb.
- [2026-09-14] No se hace fallback después de iniciar acciones para impedir dobles
  envíos o clicks.
- [2026-09-14] No se introduce Hermes, un daemon ni un navegador remoto en Mac.

### Blockers

Ninguno.

### Verificación (2026-09-16)

- Review de código independiente encontró 1 🔴: el fichero de workflow se creaba bajo
  `$BROWSER_HOME`, propiedad de `biab-browser`. Confirmado a mano (`chmod` y `>` a
  través de un symlink actúan sobre el objetivo) y corregido moviéndolo a
  `/run/biab-browser`. El 🟣 que el mismo review levantó sobre los perfiles efímeros
  **no** se confirmó: `chown -R` no sigue un symlink pasado como argumento (medido),
  así que ese camino no tiene la misma primitiva. Sigue siendo código de FEAT-017 sin
  tocar por esta FEAT.

- `payload/pack/browser/tests/test-pack.sh` → **69 passed, 0 failed** (main, con la
  misma Sección B viva, da 25 — son 44 casos nuevos). Sección B
  ejecutada de verdad contra Chromium local (playwright-core 1.61.1, `~/.cache/ms-playwright`),
  no en SKIP. Sección C sigue siendo root-only (pasada VM manual, igual que FEAT-017).
- Mutación comprobada dos veces: revertir `head -c` a `dd bs=N count=1` deja el test de
  truncado en FAIL (`10512 of 10548 bytes`), y revertir el staging del workflow a
  `$BROWSER_HOME` deja tres tests de QA-6 en FAIL. Las dos regresiones están realmente
  cazadas, no solo descritas.
- `bash -n`, `shellcheck -S warning`, `node --check` y `tools/check-no-personal-refs.sh`
  limpios.
- No verificado aquí: el comportamiento contra Sephora/Reddit reales (QA-8, manual y
  opcional) y la instalación real del pack en una caja (Sección C).
