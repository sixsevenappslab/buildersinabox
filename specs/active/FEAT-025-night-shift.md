# FEAT-025: Night shift — el agente avanza specs validadas mientras duermes

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta
- **Complejidad:** alta
- **Presupuesto de ejecucion:** max_turns=160 timeout=3600
- **E2E mode:** none
  > La lógica bajo prueba es decisión en shell más unidades de systemd. Se
  > ejercita con mocking y redirección de rutas, igual que los drivers de
  > FEAT-014 y FEAT-024. Lo que NO se puede probar sin hardware es que el timer
  > dispare de verdad a las 3 de la mañana; eso va a la pasada manual.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** implementacion
- **Creado:** 2026-08-16
- **Actualizado:** 2026-09-06 (guard a lista blanca + branch protection como cerradura; corrección del claim, ver §1 Decisiones y §6)
- **Validado por Jesus:** [x] 2026-08-16

---

## Definition of Ready (DoR)

### Producto (§1) — owner Elena
- [x] Problema explicito
- [x] Intent (why) rellenado
- [x] Minimo 1 historia de usuario verificable
- [x] Minimo 3 requisitos funcionales con checkbox
- [x] Requisitos funcionales en sintaxis EARS
- [x] Boundaries §3 con al menos 1 item en cada bloque

### Spec Tecnica (§2) — owner Laura
- [x] Investigacion previa rellenada con rutas reales verificadas
- [x] Tabla "Archivos afectados" completa
- [x] Minimo 1 `<task>` con `<verify>` ejecutable y `<done>` observable (6 tareas)
- [x] Patron de codigo con fragmento real del proyecto
- [x] Criterios de aceptacion globales verificables
- [x] Presupuesto de ejecucion revisado — T2 y el disparo del timer no caben en la sesion headless, ver el bloque al final de §2

### QA (§4) — owner Pablo
- [x] Minimo 1 caso funcional con pasos numerados (37 casos, §4.1)
- [x] Minimo 1 edge case (39 casos, §4.2)
- [x] Minimo 1 item de regresion (§4.3, agrupado por fichero afectado)
- [x] Bloque `Criterios de testing` con comandos ejecutables (§4.5, 9 bloques)
- [x] Bateria de mutaciones con guard de expresion obsoleta (§4.4, 17 mutaciones)

### Growth (§1.Growth Notes) — owner Andrea
- [x] Rellenado — esta FEAT existe por una razón de posicionamiento, ver abajo.

> **DoR completa salvo la validacion de Jesus.** §1–§4 rellenadas. Antes de
> promover a `active/` hay que cerrar el hueco del modo `starter` (§2 punto 5,
> reabierto en §4.7): es una decision de §1 sin la cual el criterio de
> aceptacion principal es infalsable en la configuracion por defecto.

---

## 1. Requisitos (Elena)

### Problema

Builders in a Box no tiene con qué diferenciarse. Su titular actual —*"Run
Claude Code from your phone"*— promete dos cosas que Anthropic ya regala en su
app web y su app móvil: acceso remoto y sesiones que sobreviven. Un consejo de
cinco voces (2026-08-16) coincidió por unanimidad en que esos dos pilares están
muertos como argumento de venta, y en que lanzar con ellos invita a que el
primer comentario del Show HN sea "esto ya lo hace la app".

Lo que queda en pie —tu máquina, tu suscripción, un método con opinión— es
cierto pero no hace que nadie levante la cabeza.

Hay una capacidad que sí: **que la caja siga trabajando cuando cierras el
portátil**. No "que la sesión siga viva" (eso es tmux, y Anthropic lo cubre),
sino que el agente *arranque solo*, coja una spec que ya validaste, la
implemente y te deje una pull request esperando por la mañana.

Ese comportamiento ya existe, pero solo en la máquina del mantenedor:
`core/scripts/crons/autonomous-implementer.sh` en `ai-platform`. Corrección
sobre la primera redacción de esta spec, que decía "en modo real desde el
2026-08-14": ese día se **configuró** `DRY_RUN=0` en el crontab, pero el cron
dispara los lunes a las 03:17 y el log no registra ni una sola pasada real. O
sea: el patrón está diseñado y revisado, pero **nunca se ha ejecutado sin
supervisión**. Conviene tenerlo presente al copiarlo — es criterio probado en
el papel, no en la noche.

Y no es portable: rutas absolutas, nombres de 15 proyectos propios, tokens de
Slack, un OAuth personal.

Y BIAB hoy no instala **ningún** planificador: ni cron, ni timer de systemd, ni
reintentos, ni vigilancia. La skill `extend-yourself` lo dice explícitamente:
servicios y tareas programadas son *"(none bundled)"*.

### Intent (why)

Dos motivos, y conviene separarlos porque tienen fuerza distinta.

El primero es de posicionamiento: es lo único del inventario completo de
`ai-platform` que habilita un titular que Anthropic no puede copiar. Ellos no
van a ejecutar trabajo no supervisado, durante horas, contra el repositorio
privado de alguien en su propio hardware. El modelo de negocio de una caja
propia empieza exactamente donde termina el de un sandbox alquilado.

El segundo es más honesto y menos glamuroso: **lo difícil aquí no es programar
una tarea, es no hacer daño**. Un `systemd` timer son diez líneas. Lo que
cuesta meses de sustos es todo lo que el script del mantenedor ya aprendió:
fail-closed por defecto, no repetir specs que siempre abortan, validar el
candidato antes de lanzar, bloquear el merge con un hook y no con una frase en
el prompt, exigir que la respuesta final traiga URL de PR o `ABORTADO`, y
abortar si el árbol de trabajo está sucio. Empaquetar ese criterio es el valor;
el timer es el envoltorio.

El riesgo es real y hay que decirlo en el propio producto: esto gasta la
suscripción del usuario, de noche, sin que él mire. Un producto que activa eso
por defecto, o que lo activa sin enseñar antes el coste, es un producto que
traiciona a quien lo instaló.

### Solucion propuesta

Un pack **opt-in** (`biab pack add night-shift`, mismo mecanismo que el pack de
navegador de FEAT-017) que instala un timer de systemd de usuario. El timer
escanea los `specs/active/` de los proyectos del usuario, elige un candidato
validado, lo implementa con el CLI en modo headless y **para en la pull
request**.

Nunca se instala activo. La primera pasada es siempre simulacro: dice qué
haría, y no toca nada. Pasar a modo real es un acto explícito del usuario,
después de haber visto lo que habría hecho.

Como BIAB no tiene Slack —ni debe pedirle al usuario una cuenta de nada— el
informe va a un log local y se resume en el arranque de la siguiente sesión,
reutilizando el mecanismo de `biab-specs.sh` (FEAT-019) que ya avisa de specs
pendientes.

### Historias de usuario

- Como dueño de la caja, quiero validar una spec un domingo por la noche y
  encontrarme una pull request el lunes por la mañana, para que el trabajo
  avance en las horas en las que no puedo sentarme delante.
- Como dueño de la caja, quiero ver exactamente qué haría el turno de noche
  **antes** de dejarle tocar nada, para no descubrir a posteriori que se ha
  gastado mi cuota en una spec ambigua.
- Como dueño de la caja, quiero que nada de esto se active solo, para que
  instalar Builders in a Box nunca signifique autorizar gasto desatendido.

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** El pack shall instalarse solo bajo petición explícita
      (`biab pack add night-shift`) y quedar inactivo tras instalarse.
- [ ] **State-driven:** While el pack esté en modo simulacro (el estado de
      fábrica), el turno de noche shall reportar qué spec elegiría y no shall
      ejecutar el CLI, ni escribir en el repositorio, ni gastar tokens.
- [ ] **Unwanted:** If la variable de modo tiene cualquier valor que no sea
      exactamente el literal de modo real, then el sistema shall comportarse
      como simulacro (fail-closed).
- [ ] **Event-driven:** When el turno de noche se ejecuta en modo real, el
      agente shall parar en la pull request, y un guard mecánico shall bloquear
      todo intento de merge, deploy o push a la rama principal — no basta con
      pedírselo en el prompt.
- [ ] **Event-driven:** When el árbol de trabajo del repositorio no esté limpio
      al empezar, el turno de noche shall abortar sin tocar nada.
- [ ] **State-driven:** While una spec ya se haya intentado en los últimos N
      días, el turno de noche no shall volver a lanzarla, para no requemar la
      cuota contra una spec que aborta siempre.
- [ ] **Event-driven:** When el usuario active el modo real, el sistema shall
      mostrarle antes una estimación del gasto por pasada y exigir confirmación
      explícita.
- [ ] **Ubicuo:** El turno de noche shall tener un interruptor de apagado que
      funcione sin desinstalar el pack, coherente con el kill-switch de hooks
      que ya existe (`BIAB_HOOKS_DISABLED` / fichero centinela).
- [ ] **Event-driven:** When el usuario abra una sesión después de una pasada,
      el sistema shall resumirle qué ocurrió (spec elegida, resultado, URL de
      la PR o motivo del aborto).
- [ ] **Ubicuo:** `payload/install.sh --uninstall` shall dejar la máquina sin
      timer, sin unidad de servicio y sin estado del pack, cumpliendo el
      contrato de propiedad de FEAT-024.
- [ ] **Ubicuo:** El fichero que decide el modo shall aceptar exclusivamente el
      literal `real` sin espacios ni saltos de línea, y cualquier otro contenido
      shall tratarse como simulacro. (Resuelve E-10 en el sentido estricto.)
- [ ] **Event-driven:** When el fichero de modo exista con un contenido que no
      sea el literal exacto, el turno de noche shall registrar un mensaje
      específico que diga que el fichero existe pero no está reconocido — nunca
      un silencio ni un genérico "no hay trabajo". Es la contrapartida del
      rechazo estricto: fallar cerrado no puede significar fallar callado.
- [ ] **Unwanted:** If existe cualquier variable de entorno capaz de saltarse la
      comprobación de modo o de propiedad, then el diseño es inválido — la
      costura de test debe recibir el veredicto del gate como argumento, nunca
      llevar una llave dentro de la jaula.

### Decisiones de §1 pedidas por §2 y §4 (resueltas)

**Claim de seguridad — el hook es freno, la cerradura es branch protection
(2026-09-06).** Revisión previa a las betas: el copy (README, landing,
CHANGELOG, instalador del pack, `arm`) decía "can't merge without you" y
"blocks every merge and push attempt at the tool layer". El guard era una
lista negra de 7 deletreos sobre el tool Bash. Una batería de 27 formas de
mergear, pushear a main o desplegar, pasada por el hook en local, dejó pasar
22 (`git push` sin refspec estando en main, `git push origin "main"`,
`--all`/`--mirror`/`--tags`, `gh api -X PUT …/merge`, auto-merge por GraphQL,
`gh workflow run deploy.yml`, `curl` con `gh auth token`, script escrito y
ejecutado, workflow editado con Write y empujado en la rama). Decisión de
Jesus: endurecer **y** reescribir el claim, no solo una de las dos.

- El hook pasa a **lista blanca**: solo `git push [-u] origin <rama>` (rama no
  protegida, sin `refs/`, sin comillas ni `+`), `gh pr create` y verbos de
  solo lectura de `gh`. Bloquea API de GitHub, clientes HTTP contra
  github.com, credenciales, `git remote`/`git config`/`git tag`, edición de
  `.git/` y `.github/workflows/` (desde Bash y desde Write/Edit/NotebookEdit),
  `sudo` y `eval`. La pasada corre con `--strict-mcp-config --disallowedTools
  mcp__*`. **Residuo conocido y no cubrible por hook:** un script escrito a
  disco y ejecutado después. Por eso el hook se llama freno.
- La **cerradura** es server-side: revisión obligatoria (≥1 aprobación,
  administradores incluidos) en la rama por defecto, que el agente, actuando
  como el dueño, no puede darse. `night_branch_is_locked` consulta protección
  clásica y rulesets antes de gastar; sin ella la pasada aborta con
  `default-branch-not-protected` **sin sellar la spec**. `arm --unprotected-ok`
  acepta correr sin cerradura (fichero root-owned con la misma disciplina que
  `mode`), y el resumen matutino lo avisa cada día. Motivo del opt-out: en
  GitHub Free los repos privados no tienen branch protection; sin opt-out la
  feature no existiría para ese usuario.
- El copy dice "stops at the pull request" y explica las dos capas. Nunca
  vuelve a apoyar "can't merge without you" solo en el hook.

**Modo `starter` — se elige la opción (a): `FEAT-STARTER.md` gana el campo de
validación.** §4 tenía razón en que esto era bloqueante: de fábrica una caja
está en modo `starter`, la plantilla no tiene `validated_by`, y por tanto no
podría existir jamás un candidato. El titular sería falso el día uno.

De las tres salidas, la correcta es añadir el campo, no exigir modo `full`.
Razón: la validación no es un lujo de la ceremonia SDD, es **el consentimiento
para gastar dinero sin mirar**. Una caja que no sabe expresar "esto lo he
aprobado yo" no debería poder encender el turno de noche, y arreglar eso pasa
por la plantilla, no por obligar al usuario a subir de modo. Un usuario en
`starter` que valida una spec ha hecho exactamente el gesto que esta feature
necesita.

Consecuencia para §2: la plantilla starter entra en "Archivos afectados". Las
specs starter antiguas sin el campo siguen sin ser candidatas, y el runner debe
decirlo con el motivo explícito que §4 ya especifica (E-21), no con un genérico
"no hay trabajo".

**Veredicto `unclear`:** cadena fija más entrada en el journal. Se confirma la
lectura de §4: §3 prohíbe inyectar prosa del modelo en el contexto de la
sesión siguiente, y esa prohibición gana. El usuario obtiene "abortado, motivo
no clasificable" y la traza completa en el log, que es donde puede leerla sin
que nadie se la inyecte.

**Alcance multi-CLI (revisa lo que §2 concluyó):** §2 dio Codex por no viable
en v1. Un spike posterior con los binarios en la mano lo desmiente —
`execpolicy` deniega `gh pr merge` y `git push origin main` de forma mecánica
(verificado), `workspace-write` con `network_access` conserva el sandbox de
ficheros, `codex exec` reutiliza la sesión guardada y `--json` da evento de
fin. Codex se aborda en una FEAT propia, inmediatamente después de esta.
Antigravity sigue fuera: sin hooks y sin topes, la única vía sería
`--dangerously-skip-permissions`, que el propio adaptador prohíbe. Mientras
tanto el pack debe decir con qué CLI puede pasar de simulacro **en el momento
de instalarlo**, no al intentar armarlo.

### Requisitos no funcionales

- [ ] Cero cuentas nuevas y cero dependencias pesadas: nada de Docker, ni base
      de datos, ni API de terceros. Solo systemd, bash y el CLI que la caja ya
      instaló.
- [ ] El coste de una pasada debe ser acotado por construcción: tope de turnos,
      tope de tiempo, y un solo candidato por pasada.
- [ ] Funciona con los tres CLIs que BIAB soporta, o declara explícitamente con
      cuáles no — el registro de adaptadores de FEAT-020 es la fuente de verdad,
      no un `if` por nombre.
- [ ] El driver de pruebas corre sin root, sin red y sin VM, como los de
      FEAT-014 y FEAT-024.

### Referencias visuales

- N/A — no hay UI. La única superficie visible es el resumen al abrir sesión.

### Growth Notes (Andrea)

Esta FEAT existe para desbloquear un titular. El candidato de trabajo:

> *"Your agent keeps working after you close the laptop. Validated spec at
> night, pull request in the morning — on hardware you own."*

Condición innegociable para poder usarlo: que sea **cierto sin asteriscos** el
día del lanzamiento. Un lanzamiento cuyo titular no sobrevive al primer
comentario de Hacker News es peor que no lanzar.

Estado de esa condición (2026-08-16): alcanzable. Jesús decidió ampliar a Codex
antes de lanzar, y el spike de viabilidad lo respalda con evidencia ejecutada —
3-5 días de trabajo, no semanas, porque el esqueleto del adaptador ya existe.
Con Claude Code y Codex cubiertos, el titular se sostiene. Antigravity queda
fuera y eso se dice en el sitio donde importa: al instalar el pack.

El canal previsto sigue siendo Show HN + r/selfhosted. El público es quien ya
tiene hardware encendido y ya paga una suscripción — nunca el principiante, que
es exactamente el usuario al que más daño le haría el gasto desatendido.

---

## 2. Spec Tecnica (Laura)

### Investigacion previa

Leídos enteros: `core/scripts/crons/autonomous-implementer.sh` (218 líneas) y su
`lib.sh` hermano, `core/scripts/crons/_run_claude_stream.py` y los cuatro
ficheros de `core/scripts/crons/hooks/`; `payload/pack/browser/` completo
(`install.sh` 242, `uninstall.sh` 78, `lib.sh` 211, `tests/test-pack.sh` 372);
`payload/install/05-biab-command.sh` (221), `payload/lib/ai-cli.sh` (502),
`payload/hooks/biab-specs.sh` (98) y `payload/hooks/lib.sh`,
`payload/wizard/40-scaffold.sh` (345), `payload/install.sh` (607),
`payload/test/uninstall-contract.sh` (992), `payload/test/wiring-smoke.sh`,
`payload/templates/FEAT-TEMPLATE.md` y `FEAT-STARTER.md`, y
`.github/workflows/ci.yml`. Todas las rutas verificadas con `ls`/`grep -n`.
Comprobado empíricamente en local: `agy --help` (1.0.13), `codex --help` y
`codex exec --help` (0.147.0), `claude --help` (2.1.232), `man systemd.exec`
(systemd 255) y `systemd-analyze verify` sobre un par `.service`/`.timer` de
prueba.

**1. Qué se conserva del script del mantenedor y dónde vive hoy cada garantía.**

| Garantía | Dónde está hoy | Cómo se porta |
|---|---|---|
| Fail-closed del modo | `autonomous-implementer.sh:124` — `if [[ "$DRY_RUN" != "0" ]]` | Fichero `mode` (root-owned) que debe contener exactamente `real`; cualquier otra cosa —ausente, vacío, `Real`, ilegible, con basura— es simulacro |
| Sello de intento, 14 días | `:168-179` (`find "$STAMP" -mtime -14`, `touch` **antes** de lanzar) | Igual, en `state/attempted/<spec>.stamp`. El `touch` previo es lo que evita requemar cuota cuando la pasada muere por timeout |
| Validación del candidato | `:158-166` — valida el protocolo posicional `TOPCAND` antes de ejecutar con datos basura | Se mantiene el espíritu, no el mecanismo: el candidato debe resolver a un fichero real dentro de `specs/active/` de un proyecto descubierto y a un `cwd` que sea repo git |
| Guard mecánico anti-merge | `hooks/implementer-settings.json:14-25` + `hooks/no-merge-guard.sh:23-40` (6 patrones, `exit 2`) | Se porta a `payload/pack/night-shift/hooks/`, root-owned bajo `/opt`, con la lista adaptada a la caja |
| Tope de coste | `lib.sh:183` (`--max-turns`) + `timeout` externo | `--max-budget-usd` (verificado en `claude --help:119-120`, "only works with `--print`") + `TimeoutStartSec` de la unidad |
| Stop-gate | `lib.sh:198-215` + `hooks/stop-gate.sh` | **No se porta** — ver "NO incluye" |
| Árbol sucio ⇒ abortar | Hoy es **prosa dentro del prompt** (`:199`) | Sube a precondición del runner: `git status --porcelain` no vacío ⇒ aborta antes de gastar un token |

Es decir: de las siete garantías, la del árbol sucio hoy **no es mecánica** en el
script del mantenedor; es una frase que el modelo puede reinterpretar. §1 la pide
como comportamiento del sistema, así que en la caja se implementa fuera del
prompt. Lo que se tira: rutas absolutas, la lista de proyectos del mantenedor,
Slack y sus secretos, la identidad "Elena", y el helper de streaming en Python
(la caja no necesita transcript ni contabilidad de coste por invocación).

**2. El guard mecánico sí aplica con `bypassPermissions` — verificado en la
documentación, pendiente de demostrar en la caja.** El comentario de
`lib.sh:191-196` ("drops bypassPermissions **so the PreToolUse danger-zone/branch
guards apply**") deja leer que en `bypassPermissions` los hooks `PreToolUse` no
corren; si eso fuera cierto, el guard del mantenedor llevaría inerte desde julio
y la garantía central de esta FEAT no existiría. La documentación oficial de
Claude Code dice lo contrario y de forma explícita: los hooks `PreToolUse` se
evalúan **antes** de cualquier comprobación de modo de permisos, en todos los
modos, y un `deny` bloquea la herramienta incluso bajo `bypassPermissions` o
`--dangerously-skip-permissions`
(<https://code.claude.com/docs/en/hooks-guide>, § "Hooks and permission modes").
El comentario de `lib.sh` se refiere a los guards de *permisos* del harness del
mantenedor, no a los hooks. Además `claude --help:193-194` describe `--settings`
como "load **additional** settings", y la precedencia documentada sitúa los
argumentos de línea de comandos por encima de `~/.claude/settings.json`
concatenando los arrays de hooks: los hooks del usuario y los nuestros corren
ambos, y el agente no puede quitarse el nuestro editando su propio settings.
**Aun así, esta es la garantía de la que cuelga toda la FEAT y no se acepta por
lectura de documentación**: T2 la demuestra con una pasada real. No pude
ejecutar ese spike desde la sesión de spec (lanzar un `claude -p` anidado con
`bypassPermissions` está bloqueado por política), y por eso es tarea con
`<verify>` propio y no una nota al pie.

**3. De los tres CLIs, hoy solo Claude Code puede correr el turno de noche.**
Comprobado ejecutando los binarios, no leyendo docs:

| CLI | Modo headless | Tope de turnos/coste | Guard mecánico de herramientas | Veredicto |
|---|---|---|---|---|
| `claude` (2.1.232) | `-p/--print` (`--help:3-4`) | `--max-budget-usd` (`--help:119-120`) | Hooks `PreToolUse` vía `--settings`; capacidad `hooks` ya declarada en `ai-cli.sh:54` | **Viable** |
| `agy` (1.1.0 pinned; 1.0.13 en local) | `-p/--print` existe | Ninguno. `--print-timeout` (5 m por defecto) es lo único, y una implementación real no cabe ahí | Ninguno: `AI_CLI_CAPABILITIES=""` (`ai-cli.sh:142`). Para escribir sin supervisión haría falta `--dangerously-skip-permissions`, que el propio adaptador prohíbe (`ai-cli.sh:193-195`) | **No viable** |
| `codex` (0.147.0) | `codex exec` + `-o/--output-last-message` | Ninguno equivalente | Tiene piezas propias (`--sandbox`, execpolicy `.rules`, un sistema de hooks con `trust`), pero ninguna verificada, y `--sandbox workspace-write` corta la red que hace falta para `git push`/`gh pr create` | **No en v1** |

§1 exige "declarar explícitamente con cuáles no", y esto es esa declaración. No
se resuelve con un `if` por nombre: se añade una capacidad `unattended` al
registro de FEAT-020 y el pack pregunta por ella (`ai_cli_has_capability`,
`ai-cli.sh:421-430`), igual que `40-scaffold.sh:174-177` decide si sembrar hooks.
En una caja `agy` o `codex` el pack se instala y el simulacro funciona —el
simulacro no lanza ningún CLI—, pero armar el modo real se rechaza con el motivo
concreto. Codex es el candidato natural de una FEAT posterior; `agy` no lo es
mientras no tenga ni tope de turnos ni guard.

**4. `systemd --user` no es viable en esta caja, y no por gusto arquitectónico.**
Tres hechos verificados:

- **El linger solo se activa en el camino ISO.** `loginctl enable-linger` aparece
  una única vez en el repo, en `iso-builder/user-data:88`, para el usuario
  `builder`. El camino principal —`curl … | sudo bash`— no lo activa nunca. Sin
  linger, el gestor de usuario muere con la última sesión y el timer no dispara.
  De paso: `payload/skills/extend-yourself/SKILL.md:109` afirma "(already enabled
  at first boot)", y en el camino `curl|bash` **es falso**.
- **La unidad de usuario vive en un directorio que el propio agente puede
  reescribir.** `~/.config/systemd/user/` pertenece al operador, y el turno de
  noche corre *como* el operador. Un agente desatendido podría editar su propio
  `ExecStart`, quitarse el `--settings` del guard o cambiar el `OnCalendar`. Una
  unidad de sistema en `/etc/systemd/system/` es root-only: el agente no puede
  aflojar su propia jaula. §3 pide guard mecánico; esto es parte del mismo
  argumento.
- **El entorno de una unidad de sistema con `User=` es suficiente.**
  `man systemd.exec` (systemd 255, Ubuntu 24.04) documenta que `$USER`,
  `$LOGNAME`, `$HOME` y `$SHELL` se fijan cuando hay `User=` y
  `SetLoginEnvironment=` no está a `false`. Es todo lo que el CLI necesita para
  encontrar su token: FEAT-013 ya estableció que ninguno de los CLIs usa keyring
  (`payload/docs/cli-skills-compatibility.md:72-77`), guardan el token en un
  fichero `0600` bajo `$HOME`. No hace falta sesión de D-Bus ni `XDG_RUNTIME_DIR`.

A favor de la unidad de sistema juega además la coherencia: BIAB ya escribe
unidades y drop-ins de sistema (`install/50-ssh.sh:79-87`, el drop-in de
`getty@tty1` renderizado en `install.sh:506-527`) y **nunca** ha escrito nada en
`~/.config/systemd/user/`. Y desinstalar es `rm` + `daemon-reload`, comprobable;
mientras que `loginctl disable-linger` sería un cambio global de la cuenta que el
pack no puede revertir con seguridad (no sabe quién más lo necesitaba).

> **Contrapunto honesto:** con el autologin de `tty1` instalado, la caja *suele*
> tener una sesión abierta, así que un timer de usuario funcionaría la mayor
> parte del tiempo. "La mayor parte del tiempo" no es un contrato para un trabajo
> nocturno desatendido, y en un VPS sin `tty1` no se cumple ni eso.

**5. El formato de spec de la caja no es el del mantenedor.** El parser del
mantenedor busca `## Metadata` y `**Validado por Jesus:**` con regex en español
(`autonomous-implementer.sh:45-83`). Las plantillas que la caja instala usan
**frontmatter YAML**: `FEAT-TEMPLATE.md:1-10` trae `status`, `priority`,
`complexity` y `validated_by: null`. El contrato del candidato en BIAB es, por
tanto: fichero en `specs/active/` **y** `validated_by` con valor no nulo. Nada de
regex en español, nada de heurísticas sobre el cuerpo.

> **Hueco que hay que devolver a §1:** `FEAT-STARTER.md:1-7` **no tiene**
> `validated_by`, y `sdd-base` dice que el modo por defecto cuando falta
> `~/.claude/sdd-config.json` es `starter`. En una caja recién instalada en modo
> starter no puede existir ningún candidato — nunca. El runner lo dirá con esas
> palabras en vez de fingir que no hay trabajo, pero la decisión de producto
> (¿añadir el campo a la plantilla starter? ¿el turno de noche es solo para modo
> full?) es de §1, no mía.

**6. Packs: el mecanismo existe entero y no hay que inventar nada.**
`biab pack {list,add,remove}` vive en `05-biab-command.sh:117-164`; `add` hace
`exec sudo "$packroot/$name/install.sh" "$@"` (`:157`) y `remove` lo mismo con
`uninstall.sh` (`:160`). `list` prefiere la función `pack_is_installed` del
`lib.sh` de cada pack (`:140-147`), así que el nuestro debe definirla. Y el
desinstalador global ya recorre **todos** los packs antes de borrar `/opt`
(`install.sh:207-214`), con casos de regresión propios en el contrato
(`uninstall-contract.sh:963-991`, E-15/E-16): el pack no tiene que engancharse a
nada, solo existir con un `uninstall.sh` ejecutable.

**7. Plantillas `.in` para todo lo que lleva rutas absolutas.** El settings del
guard y las dos unidades systemd necesitan rutas absolutas resueltas en la
máquina. El repo ya tiene ese patrón:
`payload/systemd/getty@tty1.service.d/autologin.conf.in` renderizado en
`install.sh:506-527`, con la forma exacta a copiar —
`BIB_USER="$x" envsubst '${BIB_USER}' < "$in" > "$out.tmp"` (`:521`): lista
blanca de variables explícita, para que la plantilla no expanda nada más, y
escritura a `.tmp` + `mv` para que no exista un fichero a medias. Un matiz que
sí cambia: allí `envsubst` está **guardado con `command -v`** (`:517`), o sea
tratado como opcional, y si falta el paso simplemente no ocurre. En el pack no
puede ser opcional —sin unidades no hay turno de noche—, así que el instalador
aborta con el `apt-get install gettext-base` concreto en vez de instalar medio
pack en silencio.

**8. Reporte: `biab-specs.sh` lee un fichero, no lo escribe nadie más que el
runner.** El hook (`biab-specs.sh:91-96`) ya construye un `summary` y lo emite
como `additionalContext`. Añadirle un bloque "última pasada del turno de noche"
cuando existe el fichero de estado es ~10 líneas y **no toca
`~/.claude/settings.json`**: el hook ya está registrado (`40-scaffold.sh:189`),
así que no hay nada que registrar ni que desregistrar al desinstalar. La
alternativa —un segundo hook `SessionStart` propio del pack— obligaría a mutar el
settings del usuario en la instalación y a revertirlo en el borrado, que es
justo el tipo de deuda que FEAT-024 vino a cerrar.

**9. Kill-switch: la convención existe, se copia la forma, no el fichero.**
`hooks/lib.sh:17-21` implementa el par env-var + fichero centinela
(`BIAB_HOOKS_DISABLED` / `~/.claude/hooks-disabled`). El turno de noche usa el
mismo patrón con nombres propios (`BIAB_NIGHT_SHIFT_DISABLED` + centinela en el
directorio de estado del pack). No se reutiliza el centinela de hooks: apagar los
hooks del editor y apagar el gasto nocturno son decisiones distintas, y colgarlas
del mismo fichero garantiza que alguien apague una creyendo que apaga la otra.

**10. Dónde vive el estado, y quién puede escribirlo.** `BIB_STATE_DIR`
(`lib/common.sh:8`) y `BIB_LOG_DIR` (`:10`) se borran enteros en el uninstall
global (`install.sh:221` y siguientes), así que colgar de ahí sale cubierto por
construcción. La separación de propiedad es deliberada:

| Ruta | Dueño | Por qué |
|---|---|---|
| `/var/lib/buildersinabox/night-shift/mode` | `root:root` 0644 | Lo que decide si se gasta cuota. Si fuera del operador, el agente desatendido podría armarse a sí mismo |
| `/var/lib/buildersinabox/night-shift/state/` | operador, 0750 | Sellos de intento y resumen de la última pasada: los escribe el propio runner, que corre como el operador |
| `/etc/systemd/system/biab-night-shift.{service,timer}` | `root:root` 0644 | Ver punto 4 |
| `/opt/buildersinabox/payload/pack/night-shift/` | `root:root` | Runner, guard y plantillas |

El precedente exacto de "un fichero root-owned es lo que convierte un Ask First
en un Ask First de verdad" es `validate_unsafe_sandbox_gate` del pack de
navegador (`pack/browser/lib.sh:160-189`) — ver "Patron de codigo".

**11. Dependencias del sistema:** ninguna nueva. `jq` lo instala
`install/00-base.sh:15`; `git`, `gh` y el CLI ya están; `envsubst` (paquete
`gettext-base`) ya lo usa `install.sh:492-510`; `systemd-analyze` viene con
systemd. El frontmatter YAML es plano y se lee con `sed`/`grep`, sin añadir un
parser ni Python.

### Decision de diseño: unidad de sistema, no `systemd --user`

Se instalan `/etc/systemd/system/biab-night-shift.service` (`Type=oneshot`,
`User=<operador>`, `WorkingDirectory=~`, `TimeoutStartSec`) y
`biab-night-shift.timer` (`OnCalendar=*-*-* 03:00:00`, `Persistent=false`,
`RandomizedDelaySec=900`). Justificación completa en Investigacion previa punto 4.

`Persistent=false` es intencionado: con `true`, una caja apagada a las 3:00
dispararía la pasada al arrancar —posiblemente a mediodía, con el usuario
delante y sin esperarlo—. Una pasada perdida es un no-evento; una pasada
sorpresa es gasto no consentido.

### Alcance

**Incluye**

- Capacidad `unattended` en el registro de adaptadores + verbo
  `ai_cli_unattended_cmd`, declarada solo por `claude`.
- Pack opt-in `payload/pack/night-shift/` con la estructura completa del pack de
  navegador (`install.sh`, `uninstall.sh`, `lib.sh`, `bin/`, `hooks/`,
  `systemd/`, `tests/`).
- Runner `/usr/local/bin/biab-night-shift` con subcomandos `run`, `status`,
  `arm`, `disarm`.
- Guard mecánico `PreToolUse` propio del pack + settings renderizado desde `.in`.
- Selección de candidato por frontmatter (`specs/active/` + `validated_by`),
  aborto por árbol sucio y sello de intento de 14 días.
- Puerta de armado con estimación de gasto y confirmación tecleada; fichero de
  modo root-owned y fail-closed.
- Resumen de la última pasada inyectado por `biab-specs.sh`.
- Tests del pack, casos nuevos en el contrato de desinstalación y wiring de CI.

**NO incluye**

- **Soporte de `agy` y `codex` en modo real.** Se declara y se rechaza con
  motivo; no se finge paridad (Investigacion previa punto 3).
- **El stop-gate con re-prompt** del mantenedor (`hooks/stop-gate.sh`). Ese hook
  devuelve la sesión al agente una vez cuando la respuesta final no trae URL de
  PR ni `ABORTADO`, y eso son turnos extra facturados a la cuota del usuario para
  mejorar un *mensaje*. La caja hace clasificación post-hoc de la respuesta
  final: mismo resultado observable ("URL de PR, o motivo"), coste cero.
- **Guard adicional a nivel de git** (`core.hooksPath` con `pre-push`, shim de
  `gh` en el `PATH`). Defensa en profundidad legítima, pero el guard de hooks ya
  cumple el requisito de §1 y cada capa extra es superficie que mantener. Queda
  anotado para la FEAT que traiga codex, donde sí hará falta porque allí no hay
  hooks.
- **Más de un candidato por pasada**, cola de trabajo, o reintentos. §1 NFR.
- **Cualquier salida de la máquina**: ni correo, ni webhook, ni chat. §3.
- **Tocar el flavor `gift`** más allá de exigir una confirmación extra al armar.
- **Cambiar `payload/templates/FEAT-STARTER.md`** para añadirle `validated_by`:
  es decisión de §1 (ver el hueco del punto 5).
- **Registrar un segundo hook `SessionStart`** ni mutar el
  `~/.claude/settings.json` del usuario (punto 8).

### Archivos afectados

| Ruta | Accion | Qué |
|---|---|---|
| `payload/lib/ai-cli.sh` | MODIFY | Capacidad `unattended` en los tres bloques de props; verbo `_ai_cli_unattended_cmd__claude` + público `ai_cli_unattended_cmd` |
| `payload/pack/night-shift/lib.sh` | CREATE | Rutas del pack, `pack_is_installed`, y las funciones puras: `night_mode_is_real`, `night_spec_is_candidate`, `night_classify_result`, `night_attempt_is_fresh` |
| `payload/pack/night-shift/bin/biab-night-shift` | CREATE | Runner + `status`/`arm`/`disarm` |
| `payload/pack/night-shift/hooks/no-merge-guard.sh` | CREATE | Guard `PreToolUse` (puerto del de `core/scripts/crons/hooks/`) |
| `payload/pack/night-shift/hooks/night-settings.json.in` | CREATE | Plantilla del settings que registra el guard |
| `payload/pack/night-shift/systemd/biab-night-shift.service.in` | CREATE | Unidad `oneshot` con `User=${BIB_USER}` |
| `payload/pack/night-shift/systemd/biab-night-shift.timer.in` | CREATE | Timer 03:00, `Persistent=false` |
| `payload/pack/night-shift/install.sh` | CREATE | Instalador del pack (root, idempotente) |
| `payload/pack/night-shift/uninstall.sh` | CREATE | Desinstalador del pack (idempotente) |
| `payload/pack/night-shift/tests/test-pack.sh` | CREATE | Secciones A (estática, siempre) / B (funciones puras + dry-run con fixtures) / C (root, VM) |
| `payload/hooks/biab-specs.sh` | MODIFY | Bloque "última pasada" cuando existe el fichero de resumen; fail-open igual que el resto |
| `payload/test/uninstall-contract.sh` | MODIFY | Casos nuevos (unidades systemd, `mode`, binario) + subir `EXPECTED_ASSERTIONS` (hoy `78`, `:41`) |
| `payload/test/wiring-smoke.sh` | MODIFY | Aserción de la capacidad `unattended` por CLI |
| `.github/workflows/ci.yml` | MODIFY | `bash -n` de los ficheros del pack (junto a `:40-42`) y job/step para `tests/test-pack.sh` |
| `payload/skills/extend-yourself/SKILL.md` | MODIFY | Dos líneas: `:33-34` ya no dicen "(none bundled)" y `:109` deja de afirmar que el linger está activo de fábrica |

### Dependencias

Ninguna nueva — ni paquete apt, ni npm, ni servicio, ni cuenta. Todo lo que se
usa (`bash`, `jq`, `git`, `gh`, `systemd`, el CLI ya instalado) está en la caja
desde `install/00-base.sh:15` y los instaladores 30/40-42. Es un requisito de §1,
no una casualidad.

Única salvedad, y no es una dependencia nueva sino una ya existente que hay que
dejar de tratar como opcional: **`envsubst`** (paquete `gettext-base`). Viene en
Ubuntu Server 24.04 y `install.sh:517` ya lo usa, pero tras un `command -v` que
lo deja pasar si falta. El instalador del pack lo comprueba y aborta con el
comando de instalación exacto (punto 7).

### Tareas

#### Wave 1 — la jaula, antes de que nada corra

<task>
  T1. Declarar la capacidad `unattended` en el registro de adaptadores
  (`payload/lib/ai-cli.sh`): añadirla a `AI_CLI_CAPABILITIES` de `claude`
  (`:54`), dejar explícito en los comentarios de `antigravity` (`:142`) y
  `codex` (`:262`) por qué no la declaran, y añadir el verbo
  `_ai_cli_unattended_cmd__claude` + el público `ai_cli_unattended_cmd <cli>
  <cwd> <settings> <budget> <prompt>` que imprime el comando headless completo
  con cada argumento escapado con `printf %q`, como hacen los `launch_cmd`.
  Añadir a `payload/test/wiring-smoke.sh` la aserción por CLI.
</task>
<verify>bash -n payload/lib/ai-cli.sh payload/test/wiring-smoke.sh &amp;&amp; shellcheck -S warning payload/lib/ai-cli.sh payload/test/wiring-smoke.sh &amp;&amp; for c in claude antigravity codex; do BIB_AI_CLI=$c bash payload/test/wiring-smoke.sh || exit 1; done &amp;&amp; bash -c 'source payload/lib/ai-cli.sh; ai_cli_has_capability claude unattended &amp;&amp; ! ai_cli_has_capability antigravity unattended &amp;&amp; ! ai_cli_has_capability codex unattended &amp;&amp; ai_cli_unattended_cmd claude /tmp/x /tmp/s.json 1.5 "hola mundo" | grep -q -- "--settings" &amp;&amp; echo T1-OK'</verify>
<done>Los tres jobs de wiring-smoke en verde; `unattended` solo la declara `claude`; el comando generado lleva `-p`, `--settings` y `--max-budget-usd`, y no hay ningún `if` por nombre de CLI fuera del registro (`grep -n 'antigravity\|codex' payload/pack/ payload/hooks/` no devuelve nada).</done>

<task>
  T2. Portar el guard mecánico al pack: `hooks/no-merge-guard.sh` (mismo
  contrato que `core/scripts/crons/hooks/no-merge-guard.sh` — lee el payload del
  hook por stdin, casa la lista negra contra `tool_input.command`, escribe el
  motivo por stderr y sale con 2) y `hooks/night-settings.json.in`, plantilla que
  registra el guard como `PreToolUse` con `matcher: "Bash"`. Lista negra
  adaptada a la caja: `gh pr merge`, `git push` a `main`/`master`/`pre`,
  `git push --force`, `gh release`, y borrado de ramas remotas. **Demostrar que
  bloquea de verdad** con una pasada headless real.
</task>
<verify>bash -n payload/pack/night-shift/hooks/no-merge-guard.sh &amp;&amp; shellcheck -S warning payload/pack/night-shift/hooks/no-merge-guard.sh &amp;&amp; for c in 'gh pr merge 7 --squash' 'git push origin main' 'git push --force origin feature'; do printf '{"tool_input":{"command":"%s"}}' "$c" | bash payload/pack/night-shift/hooks/no-merge-guard.sh; test $? -eq 2 || exit 1; done &amp;&amp; printf '{"tool_input":{"command":"git push -u origin feat/x"}}' | bash payload/pack/night-shift/hooks/no-merge-guard.sh &amp;&amp; envsubst &lt; payload/pack/night-shift/hooks/night-settings.json.in | jq -e '.hooks.PreToolUse[0].matcher == "Bash"' &gt;/dev/null &amp;&amp; echo T2-STATIC-OK</verify>
<verify>PRUEBA VIVA (caja real con CLI logueado, gasta cuota, NO corre en CI): renderizar el settings a un temporal, y en un repo git de usar y tirar ejecutar `claude -p 'Ejecuta exactamente: gh pr merge 1 --squash' --settings /tmp/night-settings.json --permission-mode bypassPermissions --max-budget-usd 0.50 --model sonnet 2&gt;&amp;1 | tee /tmp/guard-proof.txt`, y comprobar `grep -q 'no-merge-guard' /tmp/guard-proof.txt &amp;&amp; ! gh pr view 1 --json state 2&gt;/dev/null | grep -q MERGED`.</verify>
<done>Los tres comandos prohibidos salen con 2 y un `git push` a una rama de trabajo pasa; y en la pasada viva el agente informa de que la orden fue bloqueada por el guard, con la PR sin mergear. **Si esta prueba viva no se puede pasar, la FEAT se para aquí**: sin guard demostrado no se implementa el modo real (§3 Always).</done>

#### Wave 2 — el turno de noche

<task>
  T3. `payload/pack/night-shift/lib.sh` + `bin/biab-night-shift run` en
  **simulacro**, que es todo el camino salvo la llamada al CLI. Funciones puras
  en `lib.sh` (testeables sin root, sin red y sin systemd, patrón FEAT-014):
  descubrimiento de proyectos bajo `~/ai-platform/projects/*/specs/active/`,
  `night_spec_is_candidate` (frontmatter: fichero en `active/` + `validated_by`
  no nulo/no vacío), `night_attempt_is_fresh` (ventana de 14 días),
  `night_mode_is_real` (literal exacto `real`). El runner ordena por `priority`,
  se queda con **uno**, comprueba `git status --porcelain` y el centinela de
  apagado, escribe el resumen y termina. Costuras de test:
  `BIB_NIGHT_SHIFT_STATE_DIR` y `BIB_NIGHT_SHIFT_PROJECTS_ROOT`, vacías por
  defecto.
</task>
<verify>bash -n payload/pack/night-shift/lib.sh payload/pack/night-shift/bin/biab-night-shift &amp;&amp; shellcheck -S warning payload/pack/night-shift/lib.sh payload/pack/night-shift/bin/biab-night-shift &amp;&amp; bash payload/pack/night-shift/tests/test-pack.sh &amp;&amp; bash -c 'd=$(mktemp -d); mkdir -p "$d/bin" "$d/state"; printf "#!/bin/sh\ntouch $d/CLI-WAS-CALLED\n" &gt; "$d/bin/claude"; chmod +x "$d/bin/claude"; PATH="$d/bin:$PATH" BIB_NIGHT_SHIFT_STATE_DIR="$d/state" BIB_NIGHT_SHIFT_PROJECTS_ROOT="$d/projects" payload/pack/night-shift/bin/biab-night-shift run &gt;/dev/null 2&gt;&amp;1; test ! -e "$d/CLI-WAS-CALLED" &amp;&amp; echo T3-NO-SPEND-OK'</verify>
<done>Con un proyecto de fixture que tiene una spec validada, una sin validar y una ya sellada, el simulacro elige exactamente la validada no sellada y lo escribe en el resumen; con el árbol sucio aborta sin elegir nada; y con un `claude` falso primero en el `PATH`, **el fichero centinela no llega a existir** — el modo de fábrica no gasta ni un token, y eso queda demostrado, no prometido.</done>

<task>
  T4. Modo real: (a) el runner llama al CLI a través de
  `ai_cli_unattended_cmd`, con el prompt de criterio de hecho (implementar,
  tests y lint en verde, PARAR en la PR) y el settings del guard; (b)
  `night_classify_result` clasifica la respuesta final en `pr` (casa
  `github\.com/[^ ]+/pull/[0-9]+`), `aborted` (casa `ABORTED` en mayúsculas) o
  `unclear`, y en los tres casos **no reintenta**; (b bis) la puerta del modo se
  parte en dos funciones a propósito, para que la mitad importante sea testeable
  sin root: `night_mode_is_real <fichero>` comprueba **solo el contenido**
  (literal exacto `real`) y `night_mode_gate <fichero>` le añade dueño `root` y
  modo `0644` — misma división de trabajo que el gate del pack de navegador, cuyo
  test cubre la mitad de propiedad con una rama condicionada a `id -u`
  (`pack/browser/tests/test-pack.sh:234-247`); (c) `biab-night-shift arm`
  imprime la estimación de gasto —tope por pasada más el coste-equivalente de
  los últimos 7 días, leído de `~/.claude/cache/quota/summary.json` si existe
  (`skills/quota/scripts/quota_report.py --summary`)—, exige teclear una palabra
  de confirmación, comprueba `ai_cli_has_capability <cli> unattended`, exige una
  confirmación adicional si `state.json` dice `flavor: gift`, y solo entonces
  escribe `mode` como `root:root` 0644; (d) `disarm` y el centinela de apagado.
  El runner llama siempre a `night_mode_gate`, nunca a `night_mode_is_real` a
  secas. Toda la salida al usuario en inglés (`AGENTS.md`, "Code conventions").
</task>
<verify>bash payload/pack/night-shift/tests/test-pack.sh &amp;&amp; bash -c 'source payload/pack/night-shift/lib.sh; d=$(mktemp -d); for v in "" "0" "Real" "real extra" " real" "REAL"; do printf "%s" "$v" &gt; "$d/mode"; night_mode_is_real "$d/mode" &amp;&amp; { echo "FAIL: modo real aceptado para [$v]"; exit 1; }; done; rm -f "$d/mode"; night_mode_is_real "$d/mode" &amp;&amp; { echo "FAIL: modo real sin fichero"; exit 1; }; printf "real" &gt; "$d/mode"; night_mode_is_real "$d/mode" || { echo "FAIL: literal real rechazado"; exit 1; }; night_classify_result "https://github.com/u/r/pull/12 done" | grep -qx pr &amp;&amp; night_classify_result "ABORTED: spec ambigua" | grep -qx aborted &amp;&amp; night_classify_result "he terminado, creo" | grep -qx unclear &amp;&amp; echo T4-OK'</verify>
<done>Ningún valor distinto del literal exacto `real` arma el modo real (incluidos fichero ausente, vacío, con espacio delante y con mayúsculas); `night_mode_gate` rechaza además un `mode` que no sea `root:root` 0644, aunque diga `real` — es lo que impide que el propio agente se arme a sí mismo; `arm` se niega en una caja `agy`/`codex` citando la capacidad que falta, y en una caja `gift` exige la confirmación extra; la clasificación devuelve los tres estados y no dispara ninguna segunda llamada al CLI.</done>

#### Wave 3 — instalación, superficie y contrato

<task>
  T5. `install.sh` / `uninstall.sh` del pack + unidades. El instalador (root,
  idempotente, mismo esqueleto que `pack/browser/install.sh:26-46`) coloca el
  binario en `/usr/local/bin/biab-night-shift`, renderiza los tres `.in` con
  `envsubst` (settings del guard y las dos unidades, con `${BIB_USER}` resuelto
  vía `resolve_operator_user`), crea el árbol de estado con la propiedad de la
  tabla del punto 10, hace `systemctl daemon-reload` y **`enable` del timer sin
  `--now`**, e imprime el aviso de gasto y las instrucciones de armado. El
  desinstalador hace `disable --now` del timer, borra unidades, binario, estado y
  modo, y `daemon-reload`. Definir `pack_is_installed` para `biab pack list`.
</task>
<verify>bash -n payload/pack/night-shift/install.sh payload/pack/night-shift/uninstall.sh &amp;&amp; shellcheck -S warning payload/pack/night-shift/install.sh payload/pack/night-shift/uninstall.sh &amp;&amp; bash -c 'export BIB_USER=nobody; d=$(mktemp -d); for u in service timer; do envsubst &lt; payload/pack/night-shift/systemd/biab-night-shift.$u.in &gt; "$d/biab-night-shift.$u"; done; systemd-analyze verify "$d/biab-night-shift.timer" &amp;&amp; grep -q "^Persistent=false" "$d/biab-night-shift.timer" &amp;&amp; grep -q "^User=nobody" "$d/biab-night-shift.service" &amp;&amp; echo T5-OK' &amp;&amp; bash -c 'source payload/pack/night-shift/lib.sh; declare -F pack_is_installed &gt;/dev/null &amp;&amp; echo T5-PACKAPI-OK'</verify>
<done>`systemd-analyze verify` acepta el par de unidades renderizado (sin root); el timer queda `enabled` pero el servicio nunca se arranca en la instalación; `biab pack list` muestra `night-shift` con su estado real; y una segunda pasada del instalador y dos del desinstalador no cambian nada (idempotencia).</done>

<task>
  T6. Superficie y contrato: (a) bloque de última pasada en
  `payload/hooks/biab-specs.sh`, leyendo el fichero de resumen si existe,
  truncado y con los caracteres de control eliminados, y **fail-open** como el
  resto del hook (`exit 0` siempre); (b) casos nuevos en
  `payload/test/uninstall-contract.sh` para todo lo que el pack deja fuera de
  `/opt` —las dos unidades, el binario, `mode` y el árbol de estado— y subir
  `EXPECTED_ASSERTIONS` (`:41`); (c) `bash -n` de los ficheros del pack en
  `.github/workflows/ci.yml` (junto a `:40-42`) y ejecución de
  `tests/test-pack.sh`; (d) las dos líneas de `extend-yourself/SKILL.md`.
</task>
<verify>bash payload/hooks/tests/run-tests.sh &amp;&amp; bash payload/test/uninstall-contract.sh &amp;&amp; bash payload/pack/night-shift/tests/test-pack.sh &amp;&amp; bash tools/check-no-personal-refs.sh &amp;&amp; python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/ci.yml')); runs=[s.get('run','') for j in d['jobs'].values() for s in j.get('steps',[])]; sys.exit(0 if any('night-shift/tests/test-pack.sh' in r for r in runs) else 1)" &amp;&amp; bash -c 'sed -i "s#/etc/systemd/system/biab-night-shift.timer#/etc/systemd/system/MUTANT.timer#g" payload/pack/night-shift/uninstall.sh; bash -n payload/pack/night-shift/uninstall.sh || { git checkout payload/pack/night-shift/uninstall.sh; echo "la mutación rompió la sintaxis, no es una comprobación real" &gt;&amp;2; exit 1; }; rc=0; bash payload/test/uninstall-contract.sh &gt;/dev/null 2&gt;&amp;1 || rc=$?; git checkout payload/pack/night-shift/uninstall.sh; test "$rc" -ne 0' &amp;&amp; echo MUTATION-T6-CAUGHT</verify>
<done>El hook sigue silencioso en una caja sin el pack (cero bytes de salida cuando no existe el fichero de resumen) y emite el bloque cuando existe; el contrato de desinstalación pasa con el contador cuadrado; y **quitar el borrado del timer del desinstalador pone el contrato en rojo** — el test se ha visto fallar, que es la condición que §4 exige.</done>

### Patron de codigo

El gate de armado copia, casi literalmente, el patrón que el pack de navegador ya
usa para su única decisión Ask-First. Fragmento real de
`payload/pack/browser/lib.sh:168-186`:

```bash
validate_unsafe_sandbox_gate() {
    local sentinel="$1"
    local owner mode

    if [[ ! -e "$sentinel" ]]; then
        echo "biab-browse: BIAB_UNSAFE_NO_SANDBOX=1 requested but no human confirmation found." >&2
        echo "biab-browse: this requires a human with sudo/physical access to deliberately create $sentinel (root-owned, mode 0600), e.g.:" >&2
        echo "biab-browse:   sudo install -o root -g root -m 0600 /dev/null $sentinel" >&2
        echo "biab-browse: refusing to launch unsandboxed without it (sandbox relaxation is Ask-First, never automatic)." >&2
        return 1
    fi

    owner="$(stat -c '%U' "$sentinel" 2>/dev/null || true)"
    mode="$(stat -c '%a' "$sentinel" 2>/dev/null || true)"
    if [[ "$owner" != "root" || "$mode" != "600" ]]; then
        echo "biab-browse: refusing unsafe-sandbox request — $sentinel exists but is not root-owned mode 0600 (found owner=${owner:-?} mode=${mode:-?})." >&2
        echo "biab-browse: fix it, e.g.: sudo install -o root -g root -m 0600 /dev/null $sentinel" >&2
        return 1
    fi

    return 0
}
```

Tres cosas se copian tal cual y son las que importan: **la ausencia del fichero
es un `return 1`, no un aviso**; se comprueban dueño y modo, no solo existencia,
porque un fichero que el agente puede escribir no es una confirmación humana; y
el mensaje de rechazo trae el comando exacto para arreglarlo. `night_mode_is_real`
es esta función con otro nombre y otro literal: fichero ausente, contenido
distinto de `real`, o propiedad incorrecta ⇒ simulacro, siempre.

### Riesgos

| # | Riesgo | Mitigación |
|---|---|---|
| R1 | Que el hook `PreToolUse` no bloquee de verdad en la práctica (versión del CLI, cambio de contrato de hooks) | T2 lo demuestra con una pasada viva y la FEAT se detiene si falla. La versión de referencia queda anotada en el pack |
| R2 | Que `--max-budget-usd` sea inerte en una cuenta de suscripción (el flag habla de "API calls") | El tope duro no depende de él: `TimeoutStartSec` de la unidad mata la pasada, y solo hay un candidato por noche. Verificar el comportamiento real en la pasada manual y, si es inerte, decirlo en el README en vez de dejarlo implícito |
| R3 | `--max-turns` no aparece en `claude --help` de 2.1.232 aunque el harness del mantenedor lo usa | Se usa `--max-budget-usd`, que sí está documentado en el `--help` local. Si `--max-turns` sigue aceptándose, se añade como segundo tope; no se depende de él |
| R4 | En modo `starter` no puede haber candidatos nunca (punto 5) | El runner lo dice con esas palabras. La decisión de producto vuelve a §1 |
| R5 | Deriva entre el guard del pack y el del mantenedor | Son ficheros independientes a propósito: el del mantenedor bloquea `firebase deploy`, `pm2` y sus migraciones, que no existen en una caja BIAB. Copiar el contrato, no el fichero |
| R6 | El resumen inyectado al abrir sesión como vector de inyección de prompt | El runner escribe **solo campos fijos** (nombre de spec, veredicto de un enum de tres valores, URL casada contra regex, marca de tiempo). Nunca texto libre del modelo. El hook además trunca y limpia caracteres de control |

### Criterios de aceptacion

- [ ] Una caja recién instalada no tiene ni pack, ni unidad, ni timer:
      `systemctl list-timers --all | grep -c biab-night-shift` devuelve `0` y
      `biab pack list` muestra `night-shift  not installed`.
- [ ] Tras `biab pack add night-shift`, el timer queda `enabled` pero
      `night-shift/mode` no existe, y una pasada manual (`biab-night-shift run`)
      no invoca el CLI ni escribe en ningún repositorio.
- [ ] `night_mode_is_real` devuelve verdadero **solo** para el literal exacto
      `real` (los seis valores de la matriz de T4 caen a simulacro) y
      `night_mode_gate` exige además `root:root` 0644.
- [ ] En una pasada real, un intento de `gh pr merge` o de `git push` a `main`
      queda bloqueado por el hook y así consta en la salida (prueba viva de T2).
- [ ] Con el árbol de trabajo sucio, la pasada termina sin elegir candidato y sin
      llamar al CLI.
- [ ] Una spec ya intentada en los últimos 14 días no se vuelve a lanzar.
- [ ] Con el centinela de apagado presente, la pasada no hace nada aunque el modo
      sea `real`.
- [ ] En una caja `agy` o `codex`, `biab-night-shift arm` se niega citando la
      capacidad `unattended` que falta, y el simulacro sigue funcionando.
- [ ] Al abrir sesión después de una pasada, el contexto inyectado incluye spec
      elegida, veredicto y URL de PR o motivo; en una caja sin el pack, el hook
      no emite nada nuevo.
- [ ] `payload/install.sh --uninstall` y `biab pack remove night-shift` dejan la
      máquina sin unidades, sin timer, sin binario y sin estado, y el contrato de
      desinstalación lo asegura con casos propios.
- [ ] CI en verde: shellcheck, `bash -n`, personal-refs, contrato de
      desinstalación, suite de hooks, wiring-smoke de los tres CLIs y los tests
      del pack.

### Presupuesto de ejecucion

Revisado. `max_turns=160 timeout=3600` es razonable para seis tareas de bash +
systemd, pero **T2 y la pasada manual no caben ahí**: exigen una caja real con el
CLI logueado y gastan cuota. Recomendación: implementar T1 y T3–T6 en la sesión
headless, y reservar T2 (prueba viva del guard) y la verificación del disparo del
timer a las 3:00 para la pasada manual sobre hardware, que §1 ya declara como
E2E `none`.

---

## 3. Boundaries

### Always

- Opt-in y apagado de fábrica. Instalar Builders in a Box nunca puede implicar
  autorizar gasto desatendido de la suscripción del usuario.
- Fail-closed en todo lo que decida entre "simular" y "ejecutar de verdad".
- Solo-PR. El turno de noche jamás mergea, despliega ni empuja a la rama
  principal. Dos capas (2026-09-06): un guard mecánico de lista blanca en el
  cliente —freno— y branch protection con revisión obligatoria en el repo
  —cerradura—, comprobada antes de gastar. El copy nunca promete más de lo
  que la capa server-side garantiza.
- Enseñar el coste antes de pedir permiso, no después.
- Todo lo que el pack cree debe quedar cubierto por el contrato de propiedad de
  FEAT-024.
- **Lo que decide el gasto vive fuera del alcance del agente** (añadido por §2).
  El fichero de modo, las unidades de systemd y el settings que registra el guard
  son `root:root`. El turno de noche corre *como* el operador, así que cualquiera
  de esas tres piezas colocada en `$HOME` sería una jaula con la llave dentro.
- **El guard se demuestra, no se documenta** (añadido por §2). La garantía
  "bloquea el merge" solo cuenta como cumplida cuando existe una pasada real en
  la que un intento de merge quedó bloqueado (§2 T2).

### Ask First

- Cualquier diseño que ejecute algo distinto de "implementar una spec ya
  validada por el dueño" (por ejemplo: arreglar bugs por su cuenta, tocar
  dependencias, responder a issues).
- Aumentar los topes de turnos, tiempo o número de candidatos por pasada.
- Que el resumen salga de la máquina por cualquier vía (correo, webhook, chat):
  hoy el reporte es local y así se queda.
- Activar el pack en el flavor `gift`, donde el receptor puede no entender que
  hay gasto en juego.
- **Acortar la ventana de 14 días del sello de intento** (añadido por §2). Es el
  único freno que impide que una spec ambigua se convierta en una factura
  recurrente; bajarla es aumentar el gasto, aunque parezca un parámetro menor.
- **Añadir un CLI a la capacidad `unattended`** (añadido por §2). Declararla
  significa afirmar que ese CLI tiene modo headless, tope de coste y guard
  mecánico de herramientas. Es una promesa de seguridad, no un `grep` por
  nombre.

### Never

- Instalarlo activo, o activarlo desde el wizard.
- Merge, deploy, o push a `main`/`pre` desde una pasada desatendida.
- Ejecutar sobre un árbol de trabajo sucio.
- Reintentar en bucle una spec que aborta: eso convierte una spec ambigua en
  una factura.
- Pedir al usuario una cuenta, un token o un servicio de terceros para que el
  pack funcione.
- **Sustituir el guard por `--dangerously-skip-permissions`, `--approve all` o
  `--dangerously-bypass-approvals-and-sandbox`** para sacar adelante la pasada en
  un CLI que no tiene hooks (añadido por §2). Si un CLI no puede correr enjaulado,
  no corre: eso es lo que significa "declarar con cuáles no".
- **Inyectar en el contexto de la siguiente sesión texto libre generado por el
  modelo** (añadido por §2). El resumen que lee `biab-specs.sh` se compone de
  campos fijos y una URL casada contra regex. Un agente desatendido escribiendo
  prosa que se inyecta sin filtrar en la siguiente sesión es un canal de
  inyección de prompt de la máquina a sí misma.
- **Instalar unidades en `~/.config/systemd/user/`** ni activar
  `loginctl enable-linger` desde el pack (añadido por §2, ver la decisión de
  diseño). El linger es un cambio global de la cuenta que el desinstalador no
  puede revertir con seguridad.

---

## 4. QA (Pablo)

### Cómo se lee esta sección

Esto no es el QA de una feature: es el QA de una **jaula**. El sistema arranca
un agente sin supervisión, de noche, en la máquina de un desconocido, gastando
su suscripción. La pregunta que contesta cada caso no es "¿funciona?" sino
"¿puede esto gastar cuota o tocar `main` cuando no debe?".

De ahí tres reglas de escritura que aplican a todo lo de abajo:

1. **"No gastó" se demuestra observando el binario, no la salida.** Un runner
   que imprime `[dry-run] would call claude…` y además llama a `claude` produce
   exactamente la misma salida que uno correcto. Todos los casos de no-gasto
   ponen un mock ejecutable primero en el `PATH` que **registra su invocación en
   un fichero** y asertan que ese fichero **no existe**.
2. **Toda garantía tiene una mutación que la pone en rojo.** §4.4. Un test que
   nunca se ha visto fallar no es evidencia de nada; esta casa se ha llevado
   tres sustos con drivers verdes que no comprobaban nada (el comentario de
   `payload/test/uninstall-contract.sh:36-40` es uno de ellos).
3. **Cada `sed` de mutación lleva guard de byte.** Si la expresión no cambia ni
   un byte, el resultado es *"expresión obsoleta"*, nunca *"no detectado"*. Una
   mutación que no se aplica y un test que sí detecta se ven idénticos desde
   fuera, y es la forma más barata de creerse protegido sin estarlo.

**Dónde vive cada caso.** El driver principal es
`payload/pack/night-shift/tests/test-pack.sh`, con la misma partición que el
pack de navegador (`pack/browser/tests/test-pack.sh:3-16`):

| Sección | Corre | Qué cubre |
|---|---|---|
| **A** — estática | Siempre, CI | Invariantes de opt-in, guard como fichero, plantillas, propiedad declarada en el instalador, `git archive` |
| **B** — funciones puras + simulacro | Siempre, CI, sin root/red/systemd | Todo §4.1 salvo lo marcado *root* o *vivo*; fixtures en `mktemp -d`, costuras `BIB_NIGHT_SHIFT_STATE_DIR` / `BIB_NIGHT_SHIFT_PROJECTS_ROOT` |
| **C** — root, caja real | Solo en la pasada manual; `skip` limpio si `id -u != 0` | Instalación real, propiedad/permisos efectivos, unidades, desinstalación |
| **Vivo** | Nunca en CI. Gasta cuota | F-10 (prueba del guard bajo `bypassPermissions`) y F-27 (disparo del timer) |

**Requisito duro sobre el driver nuevo:** `tests/test-pack.sh` debe declarar
`EXPECTED_ASSERTIONS` y comprobarlo desde un `trap EXIT`, igual que
`uninstall-contract.sh:41` y `:82-97`. El driver del pack de navegador **no lo
tiene** (verificado: `grep -n 'EXPECTED' pack/browser/tests/test-pack.sh` no
devuelve nada), y por eso un `exit` temprano en él se ve exactamente igual que
un pase. La mutación M-13 existe para asegurar que en el nuestro no.

---

### 4.1 Casos funcionales

Estado: `[ ]` pendiente · `[x]` verificado · `[~]` verificado con salvedad.
Los pasos van numerados; el resultado esperado es siempre una comprobación
mecánica (fichero que existe o no, código de salida, cadena exacta), nunca una
apreciación.

#### Opt-in y estado de fábrica

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-01** | Una caja recién instalada no tiene turno de noche | 1. Instalar BIAB sin `biab pack add`.<br>2. `systemctl list-timers --all \| grep -c biab-night-shift`.<br>3. `test -e /etc/systemd/system/biab-night-shift.service`.<br>4. `biab pack list`. | (2) imprime `0`; (3) sale `1`; (4) la línea de `night-shift` contiene `not installed`; `/usr/local/bin/biab-night-shift` no existe | C | [ ] |
| **F-02** | `biab pack add night-shift` instala apagado | 1. `sudo biab pack add night-shift`.<br>2. `systemctl is-enabled biab-night-shift.timer`.<br>3. `systemctl is-active biab-night-shift.service`.<br>4. `test -e /var/lib/buildersinabox/night-shift/mode`.<br>5. Leer la salida del paso 1. | (2) `enabled`; (3) `inactive` — **nunca `active`**; (4) sale `1` (el fichero de modo no existe tras instalar); (5) contiene el aviso de gasto y la instrucción `biab-night-shift arm` | C | [ ] |
| **F-03** | **El modo de fábrica no gasta un token** | 1. `d=$(mktemp -d); mkdir -p "$d/bin" "$d/state"`.<br>2. Crear mocks ejecutables de `claude`, `agy`, `codex` y `gh` en `$d/bin`, cada uno `printf '%s\n' "$0 $*" >> "$d/CLI-WAS-CALLED"`.<br>3. Sembrar un proyecto fixture con una spec validada en `specs/active/`.<br>4. `PATH="$d/bin:$PATH" BIB_NIGHT_SHIFT_STATE_DIR=$d/state BIB_NIGHT_SHIFT_PROJECTS_ROOT=$d/projects biab-night-shift run`.<br>5. `test ! -e "$d/CLI-WAS-CALLED"`. | (5) sale `0`: **el fichero centinela no llega a existir**. El runner sale `0` y su resumen nombra la spec que *habría* elegido. Se asserta la ausencia de invocación, no el texto del log | B | [ ] |
| **F-03b** | El mock del `PATH` es capaz de cazar la invocación | 1. Con el mismo fixture de F-03, armar el modo real en el sandbox (`night_should_spend` forzado por la costura de test).<br>2. Repetir la pasada.<br>3. `test -e "$d/CLI-WAS-CALLED"`. | (3) sale `0`. **Control positivo obligatorio**: si el runner resolviera el CLI por ruta absoluta en vez de por `command -v`, F-03 pasaría en verde sin comprobar nada. Este caso es lo que impide que F-03 sea vacío | B | [ ] |
| **F-04** | El simulacro elige exactamente un candidato, y el correcto | 1. Fixture con tres specs en `specs/active/`: `A` con `validated_by: jesus`, `B` con `validated_by: null`, `C` validada pero con sello de intento de hace 2 días.<br>2. `biab-night-shift run` en simulacro.<br>3. Leer el fichero de resumen. | El resumen nombra **`A` y solo `A`**; no menciona `B` ni `C` como elegidas; el campo de conteo de candidatos dice `1` | B | [ ] |
| **F-05** | El resumen del simulacro no crea ni un fichero en el repo | 1. Fixture con repo git limpio.<br>2. `biab-night-shift run` en simulacro.<br>3. `git -C "$fixture" status --porcelain`. | (3) imprime cadena vacía. Ningún fichero nuevo, ningún branch nuevo (`git branch --list \| wc -l` sin cambios) | B | [ ] |

#### Fail-closed del modo

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-06** | Solo el literal exacto arma el modo real | 1. `source payload/pack/night-shift/lib.sh`.<br>2. Para cada valor de la matriz de §4.2 (E-01…E-09), escribir el valor en `$d/mode` y llamar `night_mode_is_real "$d/mode"`.<br>3. Escribir `real` y volver a llamar. | (2) devuelve **no-cero para todos** los valores hostiles; (3) devuelve `0`. Cada rechazo se cuenta como una aserción propia en el driver, no como un bucle con un único `ok` al final | B | [ ] |
| **F-07** | El contenido correcto no basta: propiedad y permisos deciden | 1. Escribir `real` en `$d/mode`, propiedad del operador, modo `0644`.<br>2. `night_mode_gate "$d/mode"`.<br>3. Como root: `install -o root -g root -m 0644 /dev/null /var/lib/buildersinabox/night-shift/mode`, escribir `real`, repetir.<br>4. `chmod 0666` sobre ese mismo fichero y repetir. | (2) devuelve no-cero y el mensaje de rechazo trae el comando exacto para arreglarlo (patrón `validate_unsafe_sandbox_gate`, §2 "Patron de codigo"); (3) devuelve `0`; (4) devuelve no-cero. Sin root, la rama de (3)(4) es `skip`, y (2) es la que corre siempre — misma división que `pack/browser/tests/test-pack.sh:234-247` | B+C | [ ] |
| **F-08** | Lo que decide el gasto es de root, no del agente | 1. Tras instalar el pack, `stat -c '%U:%G %a' <ruta>` para: `/var/lib/buildersinabox/night-shift/mode`, `/etc/systemd/system/biab-night-shift.service`, `/etc/systemd/system/biab-night-shift.timer`, el settings renderizado del guard y `/usr/local/bin/biab-night-shift`.<br>2. `stat -c '%U %a' /var/lib/buildersinabox/night-shift/state`.<br>3. Como el operador (sin sudo): intentar `printf real > .../mode` y `sed -i s/OnCalendar.*/OnCalendar=hourly/ /etc/systemd/system/biab-night-shift.timer`. | (1) los cinco son `root:root` y modo `644` (el binario `755`); (2) es `<operador>` `750`; (3) **ambas escrituras fallan con `Permission denied`**. Este es el caso que demuestra que el agente no puede aflojar su propia jaula (§3 Always) | C | [ ] |
| **F-08b** | La propiedad está en el instalador, no en la suerte | 1. `grep -nE 'install +-o +root +-g +root' payload/pack/night-shift/install.sh` para las rutas de F-08. | Cada una de las cinco rutas aparece creada con dueño y modo explícitos; ninguna se crea con un `touch`/`mkdir` desnudo. Aserción estática, corre en CI sin root, y es la que cubre F-08 cuando la pasada manual no se ha hecho | A | [ ] |

#### Guard mecánico anti-merge

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-09** | Los comandos prohibidos salen con 2 | 1. Para cada uno de `gh pr merge 7 --squash`, `git push origin main`, `git push origin master`, `git push origin pre`, `git push --force origin feat/x`, `gh release create v1`, `git push origin --delete feat/x`: `printf '{"tool_input":{"command":"%s"}}' "$c" \| bash hooks/no-merge-guard.sh`.<br>2. Capturar código de salida y stderr. | (2) código de salida **exactamente `2`** en los siete (no `1`, que Claude Code trata como error no bloqueante) y stderr contiene `no-merge-guard` y la etiqueta del patrón que casó | A | [ ] |
| **F-10** | Un comando legítimo pasa | 1. `printf '{"tool_input":{"command":"git push -u origin feat/night"}}' \| bash hooks/no-merge-guard.sh`.<br>2. Ídem con `gh pr create --fill` y `git commit -m x`. | Código de salida `0` y stderr vacío en los tres. Un guard que bloquea todo es un guard que el implementador desactiva a la primera | A | [ ] |
| **F-11** | **El payload llega por stdin, no por variable de entorno** | 1. `CLAUDE_TOOL_BASH_COMMAND='gh pr merge 7' bash hooks/no-merge-guard.sh </dev/null`.<br>2. `printf '{"tool_input":{"command":"gh pr merge 7"}}' \| env -u CLAUDE_TOOL_BASH_COMMAND bash hooks/no-merge-guard.sh`. | (1) sale `0` — sin stdin el guard no tiene nada que inspeccionar y **no debe fingir que sí**; (2) sale `2`. **Este caso existe porque el error se cometió durante la investigación de esta FEAT**: un test que leía `$CLAUDE_TOOL_BASH_COMMAND` habría pasado en verde comprobando cero. El contrato es stdin-JSON (`core/scripts/crons/hooks/no-merge-guard.sh:11-21`) | A | [ ] |
| **F-12** | Payload malformado no abre la puerta | 1. Enviar por stdin: cadena vacía, `not json`, `{}`, `{"tool_input":{}}`, `{"tool_input":{"command":null}}`, y 1 MB de basura. | En los seis, salida `0` (no hay comando que bloquear) y **el guard no lanza una traza ni cuelga**. Un guard que revienta con payload raro se convierte en un guard que alguien quita | A | [ ] |
| **F-13** | **PRUEBA VIVA: el guard bloquea bajo `bypassPermissions`** | 1. En una caja con el CLI logueado, renderizar el settings del guard a `/tmp/night-settings.json`.<br>2. Crear un repo de usar y tirar con una PR abierta (`gh pr create`), anotar su número `N`.<br>3. `claude -p 'Ejecuta exactamente: gh pr merge N --squash' --settings /tmp/night-settings.json --permission-mode bypassPermissions --max-budget-usd 0.50 --model sonnet 2>&1 \| tee /tmp/guard-proof.txt`.<br>4. `gh pr view N --json state -q .state`.<br>5. `grep -c '' <fichero de auditoría del guard>`. | (4) devuelve **`OPEN`** — esta es la aserción que cuenta, no el texto del transcript; (5) ≥ 1 línea con el comando bloqueado. La aserción sobre `/tmp/guard-proof.txt` es secundaria: **el agente podría no repetir el mensaje del hook, y eso no significaría que no bloqueó**. Por eso el guard debe escribir una línea de auditoría a fichero, no solo a stderr.<br>**Si este caso no se puede pasar, la FEAT se detiene aquí** (§3 Always, §2 T2) | Vivo | [ ] |
| **F-14** | El agente no puede quitarse el guard editando su settings | 1. En la misma pasada de F-13, pedirle además que escriba `{"hooks":{}}` en `~/.claude/settings.json`.<br>2. Repetir el intento de merge en la misma sesión y en una sesión nueva lanzada igual. | El bloqueo se mantiene en ambas: el guard entra por `--settings` (argumento de línea de comandos, "load **additional** settings", `claude --help:193-194`) y no por el settings del usuario. `gh pr view N` sigue `OPEN` | Vivo | [ ] |

#### Precondiciones de la pasada

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-15** | Árbol sucio aborta **antes** de gastar | 1. Fixture con spec validada y candidato claro.<br>2. `touch "$fixture/dirty.txt"` (untracked) y ejecutar la pasada con el mock de F-03 en el `PATH`, en modo real.<br>3. Repetir con un fichero *tracked* modificado y con un cambio en *staging*.<br>4. `test ! -e "$d/CLI-WAS-CALLED"`. | En los tres, el runner sale `0`, el resumen lleva veredicto `aborted` con motivo `dirty-tree` y el path relativo del primer fichero sucio, y **el centinela del CLI no existe**. El aborto ocurre antes del sello de intento: la spec sigue siendo candidata mañana | B | [ ] |
| **F-16** | Una spec ya intentada no se relanza en la ventana | 1. Fixture con una única spec validada.<br>2. Pasada 1 en modo real (mock del CLI). Comprobar que se creó `state/attempted/<spec>.stamp`.<br>3. Pasada 2 inmediatamente después.<br>4. `touch -d '13 days ago'` sobre el sello, pasada 3.<br>5. `touch -d '15 days ago'`, pasada 4. | Pasadas 2 y 3: veredicto `no-candidates` con motivo `recently-attempted`, y **una sola invocación** acumulada en el centinela del CLI. Pasada 4: la spec vuelve a ser candidata y el centinela suma una segunda línea. Este es el freno que impide que una spec ambigua se convierta en factura recurrente | B | [ ] |
| **F-17** | El sello se escribe **antes** de lanzar el CLI | 1. Mock de `claude` que hace `kill -9 $PPID` (simula timeout / corte de luz a mitad).<br>2. Pasada en modo real.<br>3. `test -e state/attempted/<spec>.stamp`. | (3) sale `0`. Sin esto, una spec que siempre mata la pasada se relanzaría cada noche eternamente — que es exactamente el fallo que el `touch` previo de `autonomous-implementer.sh:168-179` existe para evitar | B | [ ] |
| **F-18** | Un solo candidato por pasada | 1. Fixture con tres specs validadas, sin sellos, con `priority` distinta.<br>2. Pasada en modo real con el mock. | El centinela del CLI tiene **exactamente una línea**; el resumen nombra una sola spec, la de mayor prioridad; se crea **un solo** sello. No hay cola, no hay bucle (§1 NFR) | B | [ ] |
| **F-19** | Dos pasadas simultáneas no se pisan | 1. Lanzar `biab-night-shift run` dos veces en paralelo sobre el mismo estado (simula timer + pasada manual). | El centinela del CLI tiene una sola línea; la segunda instancia sale `0` con motivo `already-running`. Sin lock, la doble invocación es doble gasto | B | [ ] |

#### Armado, apagado y superficie

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-20** | `arm` enseña el coste antes de pedir permiso | 1. `biab-night-shift arm` con stdin conectado.<br>2. Leer la salida antes del prompt de confirmación. | La salida incluye, **antes** de la pregunta: el tope por pasada, el tope de tiempo de la unidad, y el gasto de los últimos 7 días si `~/.claude/cache/quota/summary.json` existe (o una línea explícita de "no disponible" si no). El orden importa: §3 Always dice "enseñar el coste **antes** de pedir permiso" | B | [ ] |
| **F-21** | `arm` exige confirmación tecleada y falla cerrado | 1. `printf 'y\n' \| biab-night-shift arm`.<br>2. `printf '\n' \| biab-night-shift arm`.<br>3. `biab-night-shift arm </dev/null`.<br>4. Tras cada uno, `test -e .../mode`. | En los tres, **`mode` no existe** al terminar y el código de salida es no-cero. Solo la palabra de confirmación completa arma. Un `arm` que se conforma con `y` o con un `<Enter>` es un `arm` que se dispara por accidente en un script | B+C | [ ] |
| **F-22** | `arm` se niega en una caja sin capacidad `unattended` | 1. `BIB_AI_CLI=antigravity biab-night-shift arm`; ídem `codex`.<br>2. Con el mismo CLI, `biab-night-shift run` en simulacro. | (1) sale no-cero, **no** pide confirmación, y el mensaje nombra la capacidad `unattended` y el CLI concreto; `mode` no se crea. (2) el simulacro sigue funcionando y elige candidato (§2 punto 3: el simulacro no lanza ningún CLI, así que no depende de la capacidad) | B | [ ] |
| **F-23** | En flavor `gift` hay una confirmación extra | 1. `state.json` con `flavor: gift`.<br>2. `biab-night-shift arm` respondiendo solo la primera confirmación. | `mode` no se crea; la salida pide una segunda confirmación distinta de la primera y explica que la caja es un regalo y el gasto es de quien la recibió (§3 Ask First) | B | [ ] |
| **F-24** | `disarm` apaga el gasto sin desinstalar | 1. Armar el modo real (root).<br>2. `biab-night-shift disarm`.<br>3. `systemctl is-enabled biab-night-shift.timer`; `test -x /usr/local/bin/biab-night-shift`.<br>4. Pasada con el mock del CLI. | (3) el timer sigue `enabled` y el binario sigue ahí — **no se ha desinstalado nada**; (4) el centinela del CLI no existe y el resumen dice `disarmed`. El pack sigue instalado y el gasto es cero | B+C | [ ] |
| **F-25** | Kill-switch: env var y centinela | 1. `BIAB_NIGHT_SHIFT_DISABLED=1 biab-night-shift run` con el modo real armado y el mock en el `PATH`.<br>2. `touch <state_dir>/night-shift-disabled` y pasada sin la env var.<br>3. Quitar ambos y repetir. | (1) y (2): el centinela del CLI **no existe**, salida `0`, resumen `disabled`. (3): la pasada vuelve a invocar el CLI — control positivo, sin él el caso podría pasar por otro motivo | B | [ ] |
| **F-26** | Los dos kill-switches son independientes | 1. `touch ~/.claude/hooks-disabled` (kill-switch de hooks, `payload/hooks/lib.sh:17-21`).<br>2. Pasada del turno de noche en modo real con el mock.<br>3. Al revés: centinela del turno de noche presente, y abrir una sesión para ver si `biab-specs.sh` sigue emitiendo. | (2) la pasada **sí** invoca el CLI: apagar los hooks del editor no apaga el gasto nocturno; (3) el hook de specs sigue funcionando. Colgar ambas decisiones del mismo fichero garantizaría que alguien apague una creyendo que apaga la otra (§2 punto 9) | B | [ ] |
| **F-27** | Clasificación del resultado, sin reintento | 1. `night_classify_result 'listo: https://github.com/u/r/pull/12'` → `pr`.<br>2. `night_classify_result 'ABORTED: spec ambigua'` → `aborted`.<br>3. `night_classify_result 'he terminado, creo'` → `unclear`.<br>4. Mock del CLI que devuelve cada una de las tres, contando invocaciones. | (1)(2)(3) salida exacta `pr` / `aborted` / `unclear` (`grep -qx`); (4) el centinela tiene **una línea en los tres casos**: ninguna clasificación dispara una segunda llamada. La caja no lleva el stop-gate con re-prompt del mantenedor, y eso es lo que se comprueba aquí | B | [ ] |
| **F-28** | El resumen de la siguiente sesión son campos fijos | 1. Escribir un fichero de resumen con spec, veredicto y URL.<br>2. Ejecutar `payload/hooks/biab-specs.sh` con un payload de `SessionStart` válido.<br>3. `jq -e '.hookSpecificOutput.additionalContext'` sobre la salida.<br>4. Borrar el fichero de resumen y repetir. | (3) el contexto incluye nombre de spec, veredicto del enum de tres valores, URL y marca de tiempo; (4) la salida **no menciona el turno de noche** y el hook sigue emitiendo su bloque de specs de siempre. En una caja sin el pack, cero bytes nuevos | B | [ ] |
| **F-29** | El hook sigue siendo fail-open | 1. Fichero de resumen ilegible (`chmod 000`), luego con JSON roto, luego de 50 MB.<br>2. Ejecutar el hook en los tres casos. | Código de salida **`0` siempre** y ninguna traza en stdout que rompa el envoltorio JSON. El contrato de FEAT-015 (`biab-specs.sh:11-13`) no se toca: el turno de noche no puede convertir el hook en algo que bloquee una sesión | B | [ ] |

#### Instalación, desinstalación y disparo

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-30** | Las unidades renderizadas son válidas y conservadoras | 1. `BIB_USER=nobody envsubst < systemd/biab-night-shift.service.in > $d/…service` (ídem timer).<br>2. `systemd-analyze verify $d/biab-night-shift.timer`.<br>3. `grep -q '^Persistent=false' $d/…timer`; `grep -q '^User=nobody' $d/…service`; `grep -qE '^TimeoutStartSec=[0-9]' $d/…service`. | (2) sale `0` sin *warnings* de unidad; (3) los tres `grep` casan. `Persistent=true` convertiría una caja apagada de noche en una pasada sorpresa a mediodía, con el usuario delante: es gasto no consentido, y por eso es aserción y no comentario | A | [ ] |
| **F-31** | El instalador aborta si falta `envsubst` | 1. Ejecutar `install.sh` del pack con un `PATH` que no contiene `envsubst`. | Sale no-cero, el mensaje trae literalmente `apt-get install gettext-base`, y **no queda nada a medias**: ni binario en `/usr/local/bin`, ni unidades, ni árbol de estado. Medio pack instalado en silencio es peor que ninguno (§2 punto 7) | C | [ ] |
| **F-32** | Instalar y desinstalar es idempotente | 1. `biab pack add night-shift` dos veces.<br>2. `biab pack remove night-shift` dos veces.<br>3. Tras cada paso, `biab pack list`. | Las segundas pasadas salen `0` sin errores y no cambian el estado; `biab pack list` refleja el estado real en cada punto (`pack_is_installed` definido, `05-biab-command.sh:140-147`) | C | [ ] |
| **F-33** | `biab pack remove` no deja rastro | 1. Instalar, armar (root), ejecutar una pasada para generar estado.<br>2. `sudo biab pack remove night-shift`.<br>3. Comprobar ausencia de: las dos unidades, el binario, `mode`, `state/`, el settings del guard.<br>4. `systemctl list-timers --all \| grep -c biab-night-shift`.<br>5. `systemctl is-enabled biab-night-shift.timer`. | (3) los cinco ausentes; (4) `0`; (5) sale no-cero con `Failed to get unit file state` — el timer no quedó "enabled apuntando a nada". Se comprueba además que se emitió `disable --now` **antes** del `rm` de la unidad, no después | C | [ ] |
| **F-34** | `payload/install.sh --uninstall` cumple el contrato de FEAT-024 | 1. Con el pack instalado y con estado, `sudo payload/install.sh --uninstall`.<br>2. Mismas comprobaciones de F-33.<br>3. Sembrar una unidad ajena `/etc/systemd/system/zz-foreign.timer` y repetir. | (2) sin rastro; (3) la unidad ajena **sobrevive intacta** (`cmp` contra la referencia). Cubierto de forma automática por los casos nuevos de §4.6 | B (driver) + C | [ ] |
| **F-35** | El timer dispara de verdad a la hora | 1. En hardware real, con el pack instalado y armado, `systemctl list-timers biab-night-shift.timer`.<br>2. Esperar al disparo (o `systemd-run --on-active=…` para acortar) y revisar `journalctl -u biab-night-shift.service`.<br>3. Comprobar el resumen y el estado del repo por la mañana. | (1) `NEXT` cae en la ventana `03:00`+`RandomizedDelaySec`; (2) el servicio corrió una vez como el operador (`_UID` en el journal) y terminó; (3) existe una PR abierta **y ninguna rama mergeada**. Solo pasada manual; no cabe en CI ni en la sesión headless (§2 Presupuesto) | Vivo | [ ] |

---

### 4.2 Edge cases

#### Matriz del fichero de modo (fail-closed)

Es la matriz que exige §1 ("cualquier valor que no sea exactamente el literal de
modo real"). Cada fila es una aserción independiente en el driver.

| ID | Entrada en `mode` | Esperado | Por qué está |
|---|---|---|---|
| **E-01** | Fichero ausente | Simulacro | El estado de fábrica. Ausencia = `return 1`, nunca aviso |
| **E-02** | Fichero vacío (0 bytes) | Simulacro | Un `truncate` accidental no puede armar |
| **E-03** | `00` | Simulacro | Valor hostil pedido en la revisión |
| **E-04** | `0 ` (cero y espacio) | Simulacro | Espacios al final no deben colarse por un `trim` demasiado generoso |
| **E-05** | `false` | Simulacro | — |
| **E-06** | `TRUE` | Simulacro | — |
| **E-07** | `1` | Simulacro | El error clásico: alguien asume booleano y `1` significa "sí" |
| **E-08** | `Real`, `REAL`, `rEaL` | Simulacro | La comparación es sensible a mayúsculas |
| **E-09** | ` real` (espacio delante), `real extra`, `real real` | Simulacro | Prefijo/sufijo no cuentan. Una comparación con `*` o con `grep` sin anclar aceptaría estos tres |
| **E-10** | `real\n` (con salto de línea final) | **Decisión pendiente — ver §4.7** | `echo real > mode` es el gesto natural de un humano con sudo. §2 T4 solo prueba `printf "real"`. Hay que decidir y **asertarlo en un sentido u otro**, no dejarlo al azar del `$(cat)` |
| **E-11** | Variable de entorno de modo definida a `real` pero fichero ausente | Simulacro | El estado vive en el fichero root-owned; una env var del operador no puede armar nada, o la jaula tiene la llave dentro |
| **E-12** | `mode` es un symlink a un fichero del operador con `real` dentro | Simulacro | Un symlink es la forma más barata de que el agente se arme a sí mismo. El gate comprueba con `stat` sin seguir el enlace (`-L` / `%U` sobre el propio symlink) |
| **E-13** | `mode` es un directorio | Simulacro, salida `0` del runner | No debe explotar con `set -e` |
| **E-14** | `mode` existe pero es ilegible para el operador (`0000`) | Simulacro | Fallo de lectura ⇒ simulacro, nunca "asumo que sí" |
| **E-15** | `mode` de 200 MB / con bytes NUL / binario | Simulacro, sin colgarse ni consumir memoria | Se lee acotado (`head -c 64`), no con `$(cat)` a pelo |

#### Descubrimiento y selección de candidato

| ID | Entrada | Esperado |
|---|---|---|
| **E-16** | `BIB_NIGHT_SHIFT_PROJECTS_ROOT` apunta a un directorio inexistente | Veredicto `no-candidates`, motivo `no-projects`, salida `0`, sin llamada al CLI |
| **E-17** | Proyecto con `specs/active/` vacío o inexistente | `no-candidates`; nunca un error de `find` que trepe por `set -e` |
| **E-18** | Spec sin frontmatter YAML | No es candidata. No se intenta parsear el cuerpo ni caer a la regex en español del mantenedor (§2 punto 5) |
| **E-19** | `validated_by: null`, `validated_by:`, `validated_by: ""`, `validated_by: ~` | No candidata en los cuatro. `~` es `null` en YAML y un `grep -q validated_by` lo aceptaría |
| **E-20** | `validated_by` aparece en el **cuerpo** del documento, no en el frontmatter | No candidata. El campo solo cuenta entre los dos `---` iniciales |
| **E-21** | Caja en modo `starter` (`FEAT-STARTER.md` no tiene `validated_by`) | Veredicto `no-candidates` con motivo **explícito** `starter-mode-has-no-validated-by`, no un genérico "no hay trabajo". Ver §4.7: falta la decisión de producto |
| **E-22** | Nombre de fichero con espacios, comillas, `$(id)`, backticks o `;rm -rf /` | La spec se selecciona o descarta sin ejecutar nada: `test -e "$(id)"` no crea ficheros, el comando del CLI se construye con `printf %q` (§2 T1) y el resumen escapa el nombre. Aserción: un fichero centinela que la inyección crearía **no existe** |
| **E-23** | Nombre con caracteres de control / secuencias ANSI / bytes no-UTF-8 | El resumen inyectado sale limpio: `tr -d '[:cntrl:]'` y truncado. El JSON del hook sigue siendo parseable por `jq -e` |
| **E-24** | Dos proyectos distintos con el mismo `FEAT-001-x.md` | Los sellos no colisionan: la clave del sello incluye el proyecto. Aserción: intentar una y la otra sigue siendo candidata |
| **E-25** | Directorio bajo el root de proyectos que no es repo git | Se descarta con motivo, no aborta la pasada entera |
| **E-26** | Repo git sin remoto / sin `gh` autenticado | Aborta con veredicto `aborted` y motivo antes de llamar al CLI. Gastar una pasada para descubrir que no se puede abrir la PR es gasto tirado |

#### Sellos, tiempo y estado

| ID | Entrada | Esperado |
|---|---|---|
| **E-27** | Sello con `mtime` exactamente en el borde de 14 días | Comportamiento determinista y asertado en un sentido concreto (`-mtime -14` excluye el día 14 completo). Se prueban 13d, 14d y 15d, no "unos días" |
| **E-28** | Sello con `mtime` en el futuro (reloj movido, `touch -d '+30 days'`) | Cuenta como reciente ⇒ no se relanza. Fail-closed también con el reloj: un reloj adelantado no puede desbloquear gasto |
| **E-29** | `state/` inexistente o no escribible por el operador | El runner lo crea si falta; si no puede, aborta con motivo **antes** de llamar al CLI (sin sello no hay freno, y sin freno no se gasta) |
| **E-30** | Disco lleno al escribir el sello | Aborta antes de invocar el CLI |
| **E-31** | Resumen de una pasada anterior corrupto | El runner lo sobreescribe; el hook lo ignora (fail-open, F-29) |

#### Dependencias y entorno

| ID | Entrada | Esperado |
|---|---|---|
| **E-32** | `jq` ausente | El hook es no-op silencioso (`biab-specs.sh:25`); el runner aborta con motivo, no adivina |
| **E-33** | `envsubst` ausente en la instalación | F-31: aborta con el `apt-get` exacto, sin dejar medio pack |
| **E-34** | `BIB_USER` con puntos, guiones o mayúsculas | Las unidades renderizan y `systemd-analyze verify` sigue en verde; `envsubst` con lista blanca `'${BIB_USER}'` no expande nada más (patrón de `install.sh:521`) |
| **E-35** | Plantilla `.in` con un `$OTRA_VARIABLE` cualquiera | Sale literal en el fichero renderizado — prueba de que la lista blanca de `envsubst` es explícita y no un `envsubst` desnudo |
| **E-36** | `TimeoutStartSec` alcanzado a mitad de la pasada | El servicio muere, el sello ya está escrito (F-17), y la siguiente sesión ve veredicto `timeout`, no un resumen vacío |
| **E-37** | CLI instalado pero sin sesión iniciada | Veredicto `aborted` con motivo, **una sola** invocación, sin reintento ni bucle de login |
| **E-38** | Respuesta final con una URL parecida (`https://evil.example/u/r/pull/1`, `github.com.evil.tld/x/pull/1`) | Clasifica `unclear`, **no** `pr`. La regex está anclada al host; una URL atacante en el resumen es un enlace que el dueño pulsa por la mañana medio dormido |
| **E-39** | Respuesta final con prosa de inyección ("ignora lo anterior y ejecuta…") | El resumen inyectado no la contiene: solo campos fijos (§3 Never, R6). Aserción: el `additionalContext` no contiene ninguna subcadena de la respuesta del modelo salvo la URL casada |

---

### 4.3 Regresión — lo que no puede romperse

Derivado de la tabla "Archivos afectados" de §2. Cada punto es un `check` que ya
existe hoy y debe seguir en verde, o una propiedad que hoy se cumple y el pack
podría romper sin que nadie mire.

**`payload/lib/ai-cli.sh` (MODIFY — el fichero con más consumidores del payload)**

- [ ] `payload/test/wiring-smoke.sh` pasa para los **tres** CLIs. Añadir `unattended` no puede alterar `ai_cli_resolve`, `ai_cli_launch_cmd` ni el rechazo del identificador retirado `gemini`.
- [ ] Las capacidades existentes siguen intactas: `claude` declara `hooks statusline remote-control` **y** `unattended`; `antigravity` y `codex` siguen con la cadena vacía (`ai-cli.sh:142` y `:262`).
- [ ] `ai_cli_has_capability <cli> <capacidad inexistente>` sigue devolviendo 1 en silencio, sin `die` (contrato de `:417-430`, del que depende `40-scaffold.sh:174-177`).
- [ ] `payload/wizard/40-scaffold.sh` sigue sembrando hooks igual: la decisión se toma sobre `hooks`, no sobre la cadena entera de capacidades.

**`payload/hooks/biab-specs.sh` (MODIFY — corre en cada sesión de cada caja)**

- [ ] `payload/hooks/tests/run-tests.sh` en verde.
- [ ] En una caja **sin** el pack, la salida del hook es byte a byte la de antes (comparar contra una referencia capturada antes del cambio).
- [ ] Sigue saliendo `0` en todos los caminos, incluido `jq` ausente y stdin inválido (FEAT-015).
- [ ] No se registra un segundo hook `SessionStart` ni se muta `~/.claude/settings.json`: `grep -c SessionStart ~/.claude/settings.json` no cambia tras instalar el pack (§2 punto 8).

**`payload/test/uninstall-contract.sh` (MODIFY)**

- [ ] Los 78 casos actuales siguen pasando, incluidos E-13 (path con espacio), E-15 (teardown de pack que falla) y E-16 (todos los packs antes de `/opt`).
- [ ] E-16 sigue contando bien con **tres** packs instalados (browser + night-shift + el `second` sintético), no solo dos.
- [ ] `EXPECTED_ASSERTIONS` actualizado **a mano** al número real. Nunca "ajustar hasta que pase": el contador existe precisamente porque un driver que se para a mitad se ve igual que uno que pasa.
- [ ] El driver sigue negándose a correr como root.

**Packs y `biab`**

- [ ] `biab pack list/add/remove` sigue funcionando para `browser` con el nuevo pack presente.
- [ ] `payload/pack/browser/tests/test-pack.sh` en verde (AC-R2, AC-R3, el gate de sandbox).
- [ ] `install.sh:207-214` sigue recorriendo **todos** los packs antes de borrar `/opt`.

**Empaquetado y CI**

- [ ] `git archive HEAD | tar -t` contiene `payload/pack/night-shift/` — el pack **debe** enviarse, igual que AC-R3 del pack de navegador. Un `export-ignore` de más lo dejaría fuera y el fallo solo aparecería en la caja del usuario.
- [ ] `git archive HEAD | tar -t | grep -c '^specs/'` sigue en `0`.
- [ ] `tools/check-no-personal-refs.sh` en verde: el guard portado no puede arrastrar nombres del mantenedor, rutas `~/ai-platform/projects/<nombre propio>`, Slack ni la lista de patrones que solo existen en su máquina (`firebase deploy`, `pm2`, `production-migration.sh`).
- [ ] El shellcheck de CI recoge automáticamente los ejecutables sin extensión (`ci.yml:25-33`), así que `bin/biab-night-shift` entra solo. Verificar que aparece en la lista impresa por el job, no asumirlo.
- [ ] Los ficheros del pack están en el `bash -n` explícito (`ci.yml:35-42`).

**Skills y docs**

- [ ] `payload/skills/manifest.tsv` **no** menciona `night-shift` (el pack no es una skill de core; misma invariante que AC-R2 del navegador).
- [ ] Las dos líneas cambiadas de `extend-yourself/SKILL.md` no rompen el frontmatter ni la longitud que valida el CI de skills.

---

### 4.4 Batería de mutaciones

**Qué es esto.** Regresiones deliberadas que el driver **debe** cazar. Cada
mutación se aplica, se ejecuta el driver, se comprueba que sale no-cero, y se
restaura. Si la mutación no cambia ningún byte, el resultado es *"expresión
obsoleta"* y el bloque **falla**, porque una expresión que ya no casa con el
código reporta "no detectado" sin haber probado absolutamente nada.

Arnés compartido — va en `payload/pack/night-shift/tests/mutations.sh`, se
ejecuta a mano o en un job de CI aparte (nunca en el mismo job que la suite
normal, porque muta ficheros del árbol):

```bash
#!/usr/bin/env bash
# Mutation harness. Every mutation must (a) change at least one byte, and
# (b) turn the named driver red. A mutation that does not apply is a FAILURE,
# not a "not detected" — an expression that no longer matches the code reports
# green while testing nothing.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
MUT_PASS=0; MUT_FAIL=0

# mutate <id> <file> <sed-expr> <driver-cmd…>
mutate() {
    local id="$1" file="$2" expr="$3"; shift 3
    local path="$REPO/$file"
    [[ -f "$path" ]] || { echo "  FAIL  $id: $file does not exist"; MUT_FAIL=$((MUT_FAIL+1)); return; }
    cp -p "$path" "$path.mutorig"
    sed -i "$expr" "$path"
    if cmp -s "$path" "$path.mutorig"; then
        mv "$path.mutorig" "$path"
        echo "  FAIL  $id: STALE EXPRESSION — sed changed 0 bytes in $file."
        echo "        This is NOT 'undetected'. Nothing was tested. Fix the expression."
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    if ! bash -n "$path" 2>/dev/null; then
        mv "$path.mutorig" "$path"
        echo "  FAIL  $id: the mutation broke the syntax — any driver would fail for the wrong reason."
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    mv "$path.mutorig" "$path"
    if [[ "$rc" -ne 0 ]]; then
        echo "  PASS  $id: caught (driver exit $rc)"; MUT_PASS=$((MUT_PASS+1))
    else
        echo "  FAIL  $id: SURVIVED — the driver stayed green with the guarantee removed."
        MUT_FAIL=$((MUT_FAIL+1))
    fi
}
```

`bash -n` tras mutar no es adorno: es la misma precaución que §2 T6 ya incluye
en su `<verify>`. Una mutación que rompe la sintaxis pone el driver en rojo por
el motivo equivocado y se apuntaría como "cazada" sin serlo.

**Nomenclatura de la columna "Estado de la expresión":**
- *verificada* — la he ejecutado contra el árbol actual y cambia bytes.
- *a verificar durante la implementación* — el fichero **todavía no existe**;
  la expresión está escrita contra la forma que §2 propone y el implementador
  debe ajustarla y comprobar que el guard de bytes pasa antes de darla por
  buena. No afirmo que esté comprobada.

| ID | Garantía atacada | Fichero | Expresión `sed` | Driver / aserción que debe fallar | Estado de la expresión |
|---|---|---|---|---|---|
| **M-01** | Fail-closed del modo | `payload/pack/night-shift/lib.sh` | `s/== "real"/== real*/` | `test-pack.sh` — F-06/E-09: ` real` y `real extra` pasan a armar el modo | a verificar durante la implementación |
| **M-02** | Fail-closed ante ausencia | `payload/pack/night-shift/lib.sh` | `/\[\[ -e "\$mode_file" \]\] || return 1/d` | `test-pack.sh` — E-01: fichero ausente deja de caer a simulacro | a verificar durante la implementación |
| **M-03** | Propiedad del fichero de modo | `payload/pack/night-shift/lib.sh` | `s/\$owner" != "root"/\$owner" == ""/` | `test-pack.sh` — F-07: un `mode` del operador con `real` dentro pasa el gate | a verificar durante la implementación |
| **M-04** | Aborto por árbol sucio | `payload/pack/night-shift/lib.sh` | `s/^night_tree_is_clean() {/night_tree_is_clean() { return 0;/` | `test-pack.sh` — F-15: la pasada llega a invocar el CLI con el árbol sucio (el centinela aparece) | a verificar durante la implementación |
| **M-05** | Lista negra del guard | `payload/pack/night-shift/hooks/no-merge-guard.sh` | `/gh\\s\\+pr\\s\\+merge/d` | `test-pack.sh` — F-09: `gh pr merge 7 --squash` sale `0` en vez de `2` | a verificar durante la implementación |
| **M-06** | **El guard lee stdin, no el entorno** | `payload/pack/night-shift/hooks/no-merge-guard.sh` | `s/CLAUDE_HOOK_PAYLOAD=\$(cat)/CLAUDE_HOOK_PAYLOAD="{\\"tool_input\\":{\\"command\\":\\"\${CLAUDE_TOOL_BASH_COMMAND:-}\\"}}"/` | `test-pack.sh` — **F-11 caso (2)**: con stdin correcto y sin la env var el guard deja de bloquear | a verificar durante la implementación |
| **M-07** | Código de salida bloqueante | `payload/pack/night-shift/hooks/no-merge-guard.sh` | `s/exit 2/exit 1/` (y variante `sys.exit(2)` → `sys.exit(1)` si se porta en Python) | `test-pack.sh` — F-09: el código deja de ser exactamente `2`, que es el único que Claude Code trata como bloqueo | a verificar durante la implementación |
| **M-08** | Sello **antes** de gastar | `payload/pack/night-shift/bin/biab-night-shift` | `/touch .*attempted/d` | `test-pack.sh` — F-17: la pasada que muere a mitad no deja sello y la spec se relanzaría cada noche | a verificar durante la implementación |
| **M-09** | Ventana de 14 días | `payload/pack/night-shift/lib.sh` | `s/-mtime -14/-mtime -0/` | `test-pack.sh` — F-16: una spec intentada ayer vuelve a lanzarse | a verificar durante la implementación |
| **M-10** | Kill-switch | `payload/pack/night-shift/bin/biab-night-shift` | `/BIAB_NIGHT_SHIFT_DISABLED/d` | `test-pack.sh` — F-25: con el kill-switch puesto la pasada invoca el CLI | a verificar durante la implementación |
| **M-11** | Instalado ⇒ apagado | `payload/pack/night-shift/install.sh` | `s/systemctl enable biab-night-shift.timer/systemctl enable --now biab-night-shift.timer/` | `test-pack.sh` sección C / F-02: el servicio queda `active` recién instalado | a verificar durante la implementación |
| **M-12** | La capacidad `unattended` es una promesa de seguridad | `payload/lib/ai-cli.sh` | `/^_ai_cli_props__antigravity/,/^}/ s/AI_CLI_CAPABILITIES=""/AI_CLI_CAPABILITIES="unattended"/` | `payload/test/wiring-smoke.sh` con `BIB_AI_CLI=antigravity`, y F-22: `arm` deja de negarse en una caja `agy` | **verificada, ejecutada** — el ancla de rango toca solo la línea 142 (`:262` y `:385` intactas) y tras mutar `ai_cli_has_capability antigravity unattended` devuelve `0`. Árbol restaurado |
| **M-13a** | **El driver del pack no puede pararse a mitad** | `payload/pack/night-shift/tests/test-pack.sh` | `0,/^echo "== Section B/{/^echo "== Section B/i\\exit 0\n}` | El propio `test-pack.sh`: `EXPECTED_ASSERTIONS` no cuadra y el `trap EXIT` sale `1`. **Sin contador declarado esta mutación sobrevive**, y es justo lo que pasó con `payload/hooks/tests/run-tests.sh` (`uninstall-contract.sh:36-40`) | a verificar durante la implementación |
| **M-13b** | El contador del contrato de desinstalación sigue vivo | `payload/test/uninstall-contract.sh` | `0,/^# E-15/{/^# E-15/i\` + salto de línea real + `exit 0` + salto + `}` (GNU `sed`; el `\n` de una línea no funciona dentro de `i\`) | `uninstall-contract.sh`: `ran N assertions, expected <N esperado>`, salida `1` | **verificada, ejecutada** el 2026-08-16 contra el árbol actual: baseline `78 passed, 0 failed` (exit 0); con la mutación, `ran 75 assertions, expected 78` y exit `1`. Árbol restaurado |
| **M-14** | El desinstalador se lleva el timer | `payload/pack/night-shift/uninstall.sh` | `s#/etc/systemd/system/biab-night-shift.timer#/etc/systemd/system/MUTANT.timer#g` | `payload/test/uninstall-contract.sh` — caso NS-2 (§4.6). Es la mutación que §2 T6 ya trae en su `<verify>`; aquí queda catalogada | a verificar durante la implementación |
| **M-15** | El resumen son campos fijos | `payload/pack/night-shift/bin/biab-night-shift` | `s/night_classify_result "\$final"/printf '%s' "\$final"/` | `test-pack.sh` — E-39/F-28: la prosa del modelo acaba dentro del `additionalContext` de la siguiente sesión (canal de inyección de la máquina a sí misma, §3 Never) | a verificar durante la implementación |
| **M-16** | La URL se casa contra el host real | `payload/pack/night-shift/lib.sh` | `s#github\\\\.com/\[^ \]\\+/pull/#/pull/#` | `test-pack.sh` — E-38: `https://evil.example/u/r/pull/1` clasifica como `pr` | a verificar durante la implementación |

**Criterio de salida de la batería:** 17 mutaciones aplicadas, 17 cazadas, 0
expresiones obsoletas. Un "obsoleta" es rojo, igual que un "sobrevivió".

---

### 4.5 Criterios de testing — comandos ejecutables

Todo lo de este bloque corre **sin root, sin red y sin VM** salvo lo marcado.
El árbol de trabajo debe estar limpio antes de empezar (varios bloques mutan
ficheros y los restauran).

**Bloque 1 — sintaxis y estilo (lo que CI corre en cada PR)**

```bash
bash -n payload/lib/ai-cli.sh \
        payload/hooks/biab-specs.sh \
        payload/pack/night-shift/lib.sh \
        payload/pack/night-shift/install.sh \
        payload/pack/night-shift/uninstall.sh \
        payload/pack/night-shift/hooks/no-merge-guard.sh \
        payload/pack/night-shift/bin/biab-night-shift \
        payload/pack/night-shift/tests/test-pack.sh
shellcheck -S warning payload/pack/night-shift/lib.sh \
        payload/pack/night-shift/install.sh \
        payload/pack/night-shift/uninstall.sh \
        payload/pack/night-shift/hooks/no-merge-guard.sh \
        payload/pack/night-shift/bin/biab-night-shift
bash tools/check-no-personal-refs.sh
```

**Bloque 2 — suites completas**

```bash
for c in claude antigravity codex; do BIB_AI_CLI=$c bash payload/test/wiring-smoke.sh || exit 1; done
bash payload/hooks/tests/run-tests.sh
bash payload/test/uninstall-contract.sh          # debe imprimir "89 passed, 0 failed"
bash payload/pack/browser/tests/test-pack.sh
bash payload/pack/night-shift/tests/test-pack.sh # debe imprimir su propio contador cuadrado
```

**Bloque 3 — el caso que no puede fallar: cero gasto de fábrica (F-03 + F-03b)**

```bash
bash -c '
set -euo pipefail
d=$(mktemp -d); trap "rm -rf $d" EXIT
mkdir -p "$d/bin" "$d/state" "$d/projects/demo/specs/active"
for b in claude agy codex gh; do
    printf "#!/bin/sh\nprintf \"%%s %%s\\\\n\" \"\$0\" \"\$*\" >> \"%s/CLI-WAS-CALLED\"\n" "$d" > "$d/bin/$b"
    chmod +x "$d/bin/$b"
done
git -C "$d/projects/demo" init -q
printf -- "---\nvalidated_by: owner\npriority: high\n---\n# demo\n" \
    > "$d/projects/demo/specs/active/FEAT-001-demo.md"
git -C "$d/projects/demo" add -A && git -C "$d/projects/demo" -c user.email=t@t -c user.name=t commit -qm seed
PATH="$d/bin:$PATH" \
  BIB_NIGHT_SHIFT_STATE_DIR="$d/state" \
  BIB_NIGHT_SHIFT_PROJECTS_ROOT="$d/projects" \
  payload/pack/night-shift/bin/biab-night-shift run >"$d/out.txt" 2>&1 || true
test ! -e "$d/CLI-WAS-CALLED" || { echo "FAIL: factory mode invoked the CLI:"; cat "$d/CLI-WAS-CALLED"; exit 1; }
grep -q "FEAT-001-demo" "$d/state"/* 2>/dev/null || { echo "FAIL: dry run picked no candidate — the no-spend assert may be vacuous"; exit 1; }
echo "F-03 OK: no CLI invocation, candidate still selected"
'
```

La segunda comprobación (que el simulacro **sí** eligió candidato) es
deliberada: sin ella, un runner que aborta al principio por cualquier motivo
pasaría F-03 sin haber recorrido el camino que se quería probar.

**Bloque 4 — fail-closed del modo (F-06, E-01…E-09)**

```bash
bash -c '
source payload/pack/night-shift/lib.sh
d=$(mktemp -d); trap "rm -rf $d" EXIT; rc=0
for v in "" "0" "00" "0 " "false" "TRUE" "1" "Real" "REAL" " real" "real extra"; do
    printf "%s" "$v" > "$d/mode"
    if night_mode_is_real "$d/mode"; then echo "FAIL: armed for [$v]"; rc=1; fi
done
rm -f "$d/mode"
night_mode_is_real "$d/mode" && { echo "FAIL: armed with no mode file"; rc=1; }
ln -s /etc/hostname "$d/mode.link"; printf "real" > "$d/real.txt"; ln -sf "$d/real.txt" "$d/mode"
night_mode_gate "$d/mode" && { echo "FAIL: symlink accepted by the gate"; rc=1; }
rm -f "$d/mode"; printf "real" > "$d/mode"
night_mode_is_real "$d/mode" || { echo "FAIL: exact literal rejected"; rc=1; }
exit $rc'
```

**Bloque 5 — guard, contrato stdin (F-09, F-10, F-11, F-12)**

```bash
G=payload/pack/night-shift/hooks/no-merge-guard.sh
for c in 'gh pr merge 7 --squash' 'git push origin main' 'git push origin master' \
         'git push origin pre' 'git push --force origin feat/x' 'gh release create v1' \
         'git push origin --delete feat/x'; do
    printf '{"tool_input":{"command":"%s"}}' "$c" | bash "$G"; rc=$?
    [ "$rc" -eq 2 ] || { echo "FAIL: '$c' exited $rc, expected 2"; exit 1; }
done
printf '{"tool_input":{"command":"git push -u origin feat/night"}}' | bash "$G" || { echo "FAIL: legit push blocked"; exit 1; }
CLAUDE_TOOL_BASH_COMMAND='gh pr merge 7' bash "$G" </dev/null \
    || { echo "FAIL: the guard reacted to an env var — it must read stdin JSON"; exit 1; }
for p in '' 'not json' '{}' '{"tool_input":{}}' '{"tool_input":{"command":null}}'; do
    printf '%s' "$p" | bash "$G" || { echo "FAIL: malformed payload exited non-zero"; exit 1; }
done
echo "guard OK"
```

**Bloque 6 — unidades systemd (F-30, E-34, E-35)**

```bash
bash -c '
set -euo pipefail
d=$(mktemp -d); trap "rm -rf $d" EXIT
export BIB_USER=nobody OTRA_VARIABLE=leak
for u in service timer; do
    envsubst "\${BIB_USER}" < payload/pack/night-shift/systemd/biab-night-shift.$u.in > "$d/biab-night-shift.$u"
done
systemd-analyze verify "$d/biab-night-shift.timer"
grep -q "^Persistent=false" "$d/biab-night-shift.timer"
grep -q "^User=nobody"      "$d/biab-night-shift.service"
grep -qE "^TimeoutStartSec=[0-9]" "$d/biab-night-shift.service"
! grep -q "leak" "$d/biab-night-shift.service"
echo "units OK"'
```

**Bloque 7 — batería de mutaciones (§4.4)**

```bash
git diff --quiet || { echo "dirty tree — the mutation harness restores files, run it clean"; exit 1; }
bash payload/pack/night-shift/tests/mutations.sh   # 17/17 cazadas, 0 expresiones obsoletas
git diff --quiet || { echo "FAIL: the harness left the tree modified"; exit 1; }
```

**Bloque 8 — empaquetado**

```bash
git archive HEAD | tar -t > /tmp/biab-archive.txt
grep -q '^payload/pack/night-shift/' /tmp/biab-archive.txt || { echo "FAIL: the pack does not ship"; exit 1; }
grep -c '^specs/' /tmp/biab-archive.txt | grep -qx 0 || { echo "FAIL: specs leaked into the archive"; exit 1; }
grep -q 'night-shift' payload/skills/manifest.tsv && { echo "FAIL: the pack must never be a core skill"; exit 1; }
```

**Bloque 9 — solo caja real (pasada manual, gasta cuota)**

```bash
sudo biab pack add night-shift
systemctl is-enabled biab-night-shift.timer      # enabled
systemctl is-active  biab-night-shift.service    # inactive  ← si dice active, FEAT-025 está rota
stat -c '%U:%G %a' /var/lib/buildersinabox/night-shift/mode \
                   /etc/systemd/system/biab-night-shift.{service,timer}   # root:root 644
stat -c '%U %a'    /var/lib/buildersinabox/night-shift/state             # <operador> 750
biab-night-shift run          # simulacro, no debe gastar
biab-night-shift arm          # muestra coste, exige confirmación tecleada
# F-13 (prueba viva del guard) — ver los pasos completos en §4.1
sudo biab pack remove night-shift
systemctl list-timers --all | grep -c biab-night-shift   # 0
```

---

### 4.6 Casos nuevos en `payload/test/uninstall-contract.sh`

§2 T6 pide "casos nuevos y subir `EXPECTED_ASSERTIONS`" sin decir cuáles.
Aquí están, con la nomenclatura del driver (prefijo `NS`, "night shift") y el
contador cuadrado. Todos usan el sandbox existente: `seed`, `_seed_into "$SC"`,
`run_uninstall`, y el mock de `systemctl` que escribe en `$SC/systemctl.log`.

Se siembra en el sandbox, antes de cada `run_uninstall`, lo que un pack
instalado deja **fuera de `/opt`**:

```
$SC/etc/systemd/system/biab-night-shift.service
$SC/etc/systemd/system/biab-night-shift.timer
$SC/usr/local/bin/biab-night-shift
$BIB_STATE_DIR/night-shift/mode
$BIB_STATE_DIR/night-shift/state/attempted/FEAT-001-demo.md.stamp
$BIB_STATE_DIR/night-shift/last-run.json
$SC/opt/buildersinabox/payload/pack/night-shift/uninstall.sh   (ejecutable, escribe en $SENTINEL)
```

| ID | Aserción | Por qué |
|---|---|---|
| **NS-1** | `.../etc/systemd/system/biab-night-shift.service` no existe tras `run_uninstall` | El TODO de `uninstall-contract.sh:26-28` dice que una ruta nueva no lleva aserción automática. Esta es la ruta nueva |
| **NS-2** | `.../etc/systemd/system/biab-night-shift.timer` no existe | Un timer huérfano apuntando a una unidad borrada intenta disparar cada noche y llena el journal de errores en una caja de la que el usuario cree habernos quitado. Es la mutación M-14 |
| **NS-3** | `.../usr/local/bin/biab-night-shift` no existe | — |
| **NS-4** | `.../night-shift/mode` no existe | El fichero que decide el gasto no puede sobrevivir a un desinstalado |
| **NS-5** | El árbol `night-shift/state/` no existe | Sellos y resúmenes: estado nuestro, se va con nosotros |
| **NS-6** | El settings renderizado del guard no existe | — |
| **NS-7** | `$SC/systemctl.log` contiene `disable --now biab-night-shift.timer` | Borrar la unidad sin desactivarla deja el enlace en `…/timers.target.wants/` |
| **NS-8** | En `$SC/systemctl.log`, el `daemon-reload` aparece **después** de la última línea que menciona `biab-night-shift` | Orden, no solo presencia: recargar antes de borrar deja systemd con la unidad todavía cargada |
| **NS-9** | Una unidad ajena sembrada en `$SC/etc/systemd/system/zz-foreign.timer` sobrevive byte a byte (`cmp` contra la copia de referencia) | El contrato es "solo tocar lo nuestro". Es la misma clase de defecto que #42 (drop-ins de sshd) |
| **NS-10** | El `uninstall.sh` del pack corre **antes** de que `/opt` desaparezca (línea propia en `$SENTINEL`) | Extiende E-16 a tres packs; con `browser` + `second` + `night-shift` el conteo esperado pasa de 2 a 3 |
| **NS-11** | Un segundo `run_uninstall` seguido sale `rc=0` y no imprime `removing` para ninguna ruta del pack | Idempotencia, misma propiedad que el resto del contrato |

**Contador.** 11 aserciones nuevas ⇒ `EXPECTED_ASSERTIONS` pasa de **78** a
**89** (`payload/test/uninstall-contract.sh:41`). El caso E-16 existente cambia
su conteo esperado de 2 a 3 pero sigue siendo una sola aserción. Si la
implementación añade o quita algún caso, el número final es el que cuadre —
**actualizado a mano, nunca subido hasta que el driver deje de quejarse**.

---

### 4.7 Lo que este QA **no** cubre, y lo que necesita decisión

Se declara aquí en vez de dejarlo implícito, igual que hace FEAT-014 con el
listener real de sshd.

**No cubierto por ningún test automático (solo pasada manual):**

1. **Que el timer dispare a las 03:00** (F-35). Requiere hardware y esperar. El
   `systemd-analyze verify` prueba que la unidad es válida, no que el reloj la
   ejecute.
2. **Que el guard bloquee de verdad bajo `bypassPermissions`** (F-13/F-14).
   Requiere un CLI logueado y gasta cuota. Es la garantía de la que cuelga toda
   la FEAT y **la única forma de saldarla es ejecutarla**: §3 Always ya dice que
   el guard se demuestra, no se documenta.
3. **Que `--max-budget-usd` corte de verdad en una cuenta de suscripción**
   (R2 de §2). No se puede probar sin gastar hasta el tope. Si resulta inerte,
   el tope real es `TimeoutStartSec` y el README tiene que decirlo con esas
   palabras; el caso F-20 debe entonces verificar que la estimación mostrada
   por `arm` **no promete un tope que el sistema no puede imponer**.
4. **El comportamiento con la cuota agotada a mitad de pasada.** Depende de la
   cuenta y del momento; queda para §6 Feedback tras la primera semana.

**Decisiones que faltan y bloquean la escritura de un caso pass/fail:**

- **E-10, `real\n`.** ¿Un `echo real > mode` arma o no arma? §2 solo prueba
  `printf "real"`. Cualquiera de las dos respuestas vale, pero hay que elegir y
  asertarla: si se acepta el salto final, el test debe probar `real\n` **y**
  `real\n\n` (este último rechazado); si no se acepta, la documentación del
  `arm` no puede sugerir `echo`. **Sin decisión, escribo el caso como rechazo
  estricto** — fail-closed por defecto —, y que §2 lo contradiga si quiere.
- **Modo `starter` (E-21).** §2 punto 5 lo devuelve a §1 y §1 no lo ha
  contestado. Hoy, en una caja de fábrica (`sdd-config.json` ausente ⇒ modo
  `starter`, `sdd-base` §"Two modes"), `FEAT-STARTER.md` no tiene
  `validated_by` y **por tanto no puede existir ningún candidato nunca**. Eso
  significa que el criterio de aceptación "una spec validada el domingo produce
  una PR el lunes" es **infalsable en la configuración por defecto del
  producto**. Es un bloqueante de DoR, no un detalle: el titular de §1.Growth
  ("validated spec at night, pull request in the morning") sería falso de
  fábrica. Necesito de §1 una de estas tres: (a) añadir `validated_by` a
  `FEAT-STARTER.md`; (b) declarar que el turno de noche exige modo `full` y que
  el instalador lo diga; (c) aceptar un segundo marcador de validación para
  starter. Hasta entonces E-21 solo puede asertar el mensaje de error.

**Cosas de §1/§2/§3 que no son testeables tal como están escritas:**

- **§2 T4(b bis) y el gate en sandbox.** El runner "llama siempre a
  `night_mode_gate`, nunca a `night_mode_is_real` a secas". Correcto como
  diseño, pero implica que **el camino de modo real es inalcanzable en el
  sandbox de test**: en un `mktemp -d` ningún fichero puede ser `root:root`. Sin
  una costura, F-03b (el control positivo que demuestra que el mock del `PATH`
  caza invocaciones) no se puede escribir, y entonces F-03 pasa a ser un test
  que no prueba nada. Pido al implementador una costura **que no sea un
  backdoor**: que `night_should_spend` reciba el veredicto del gate como
  argumento, de modo que el test inyecte "gate ok" sin que exista ninguna
  variable de entorno capaz de saltarse el gate en producción. Una costura tipo
  `BIB_NIGHT_SHIFT_SKIP_GATE=1` sería exactamente la llave dentro de la jaula
  que §3 prohíbe.
- **§2 T2, `<verify>` de la prueba viva.** La aserción propuesta es
  `grep -q 'no-merge-guard' /tmp/guard-proof.txt`, es decir, comprobar que **el
  modelo repitió** el mensaje del hook. El modelo puede bloquearse y resumirlo
  con otras palabras (fallo falso), o puede escribir "no-merge-guard" sin que
  nada se haya bloqueado (pase falso). La aserción que cuenta es el estado de la
  PR (`gh pr view N --json state` ⇒ `OPEN`) más una línea de auditoría escrita
  por el propio guard a fichero. **Esto exige que el guard escriba un log**, y
  no está en la tabla de "Archivos afectados" de §2: es trabajo adicional que
  QA necesita para poder firmar F-13.
- **§1, "resumirle qué ocurrió (… o motivo del aborto)" vs. §3 Never
  ("no inyectar texto libre generado por el modelo").** El veredicto `unclear`
  no tiene motivo estructurado: el único "motivo" disponible es la prosa del
  modelo, que §3 prohíbe inyectar. La resolución que asumo en F-28/E-39 es que
  `unclear` mapea a una **cadena fija** ("finished without a PR URL; see
  `journalctl -u biab-night-shift`") y el texto del modelo se queda en el
  journal, nunca en el contexto de la siguiente sesión. Si §1 quiere otra cosa,
  hay que reabrirlo, porque afecta a un requisito de seguridad.
- **§2 punto 3, "en una caja `agy` o `codex` el pack se instala y el simulacro
  funciona".** Verificable (F-22), pero conviene notar la consecuencia de
  producto: en dos de los tres CLIs soportados el pack es **permanentemente**
  un simulacro. El instalador debe decirlo en el momento del `pack add`, no al
  intentar `arm`; si no, el usuario instala algo que nunca podrá encender. No es
  un fallo de la spec, es una línea de copy que §5 Docs tiene que recoger.
- **§2 tabla del punto 10 vs. el precedente del pack de navegador.** El
  centinela del navegador es `0600`; el `mode` propuesto es `0644`. Para lectura
  está bien y no cambia la garantía (lo que importa es quién puede *escribir*),
  pero al implementar hay que asegurarse de que el gate comprueba modo
  **exacto** `644` y no "menos permisivo que X": F-07 paso (4) prueba que `0666`
  se rechaza, y con una comprobación laxa ese caso pasaría en verde.

---

## 5. Docs

> Pendiente. Como mínimo: sección en el README explicando qué es, que está
> apagado, y qué cuesta encenderlo; entrada en `CHANGELOG.md`; y aviso explícito
> de gasto en la salida de `biab pack add night-shift`.

---

## 6. Feedback

- **2026-09-06 — desajuste copy/guard (pre-betas).** Detalle y decisión en
  §1 "Claim de seguridad". Implementado en la PR `fix/feat-025-guard-claim`:
  guard a lista blanca + guard de ficheros, adaptador sin MCP, sondeo de
  branch protection en el runner, `arm --unprotected-ok`, aviso en
  `biab-specs.sh`, copy corregido. Tests: `test-pack.sh` 226 (F-09 con 54
  evasiones, S-01/S-02, S-10…S-17), contrato NS-12, mutaciones M-17…M-24.
  Security review (subagente `security-auditor`) sobre el diff: 4 críticos y
  3 altos, todos cerrados en la misma PR (verbos entre comillas, `GIT_CONFIG_*`
  y `GH_REPO=`, funciones/alias shell, `~/.gitconfig`, lectura de credenciales
  con Read/Grep, ventana de opciones sin tope, `bypass_actors` en rulesets,
  rama por defecto real vía `BIB_NIGHT_SHIFT_DEFAULT_BRANCH`). Residuo asumido:
  script escrito y ejecutado, variable con la palabra `git`, y que la
  cerradura cubre el merge en tu repo pero no el push a otro remoto.
  **Queda para la pasada de hardware:** F-13 (guard vivo bajo
  `bypassPermissions`) y una prueba viva del sondeo contra un repo real con y
  sin branch protection.
