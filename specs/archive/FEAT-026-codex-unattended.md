# FEAT-026: El turno de noche también funciona con Codex

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta
- **Complejidad:** alta
- **Presupuesto de ejecucion:** max_turns=140 timeout=3600
- **E2E mode:** none
  > Igual que FEAT-025: la lógica bajo prueba es decisión en shell más ficheros
  > de configuración de un CLI. Se ejercita con mocking, redirección de rutas y
  > `codex execpolicy check`. Lo que NO se puede probar sin una caja con sesión
  > iniciada es que la denegación corte de verdad en tiempo de ejecución; eso va
  > a la pasada manual, y es la prueba de la que cuelga la FEAT.
- **Reconciliation owner:** sdd-coordinator
- **Depende de:** FEAT-025 — **mergeada** el 2026-08-16 (PR #54), pack en
  `payload/pack/night-shift/`. La dependencia está satisfecha.
- **Fase:** ARCHIVADA (2026-08-17, EXEC-015) — cortada del alcance pre-launch.
  Reabre solo si un usuario real (issue/instalacion) pide Codex en el night shift.
  La pregunta binaria de `CODEX_HOME` (F-01) puede contestarse barata en la pasada
  de hardware si sobra tiempo; no bloquea nada.
- **Creado:** 2026-08-16
- **Actualizado:** 2026-08-17 (reconciliada contra `main` post-merge de FEAT-025:
  §2 punto 6, §4.3, R6, §4.7 y citas de línea de `payload/lib/ai-cli.sh`)
- **Validado por Jesus:** [ ]

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
- [x] Presupuesto de ejecucion revisado — T1 y la pasada viva no caben en la
      sesion headless, ver el bloque al final de §2

### QA (§4) — owner Pablo
- [x] Minimo 1 caso funcional con pasos numerados (24 casos, §4.1)
- [x] Minimo 1 edge case (26 casos, §4.2)
- [x] Minimo 1 item de regresion (§4.3)
- [x] Bloque `Criterios de testing` con comandos ejecutables (§4.5, 7 bloques)
- [x] Bateria de mutaciones con guard de expresion obsoleta (§4.4, 12 mutaciones)

### Growth (§1.Growth Notes) — owner Andrea
- [x] Rellenado — esta FEAT existe para que el titular de FEAT-025 no lleve
      asterisco.

> **DoR completa salvo la validacion de Jesus, y con un bloqueante declarado.**
> §2 T1 es una pregunta binaria sin responder (¿puede un `CODEX_HOME`
> root-owned reutilizar la sesión del operador sin tocar su `auth.json`?). La
> respuesta cambia el diseño, no el calendario de una tarea: si es "no", §1
> tiene que elegir entre tres salidas peores, listadas en "Decisiones que
> §1 debe tomar si T1 sale que no". **No promover a `active/` sin esa
> decisión tomada o sin T1 ejecutada.**

---

## 1. Requisitos (Elena)

### Problema

FEAT-025 construye el turno de noche y lo hace **solo para Claude Code**. Su
propia §2, punto 3, lo escribe sin adornos: de los tres CLIs que Builders in a
Box instala, únicamente `claude` declara la capacidad `unattended`. En una caja
donde el usuario eligió Codex el pack se instala, el simulacro funciona, y
`biab-night-shift arm` se niega para siempre.

Eso convierte el titular del lanzamiento en una frase con asterisco. El
candidato de §1.Growth de FEAT-025 es:

> *"Your agent keeps working after you close the laptop. Validated spec at
> night, pull request in the morning — on hardware you own."*

Un titular así no sobrevive al primer comentario de Show HN si la respuesta a
"¿y con Codex?" es "con Codex no". El canal previsto es exactamente el público
que hace esa pregunta: gente que ya tiene hardware encendido, que ya paga una
suscripción, y que en muchos casos paga la de OpenAI y no la de Anthropic.

Y el problema no es de reparto de esfuerzo, es de credibilidad del producto
entero. BIAB vende "elige tu CLI" desde FEAT-020: un registro de adaptadores en
`payload/lib/ai-cli.sh` cuya premisa es que los tres son ciudadanos de primera.
La primera feature de verdad diferencial que se construye sobre ese registro
funciona en uno de los tres. Si eso se queda así, el registro deja de ser una
promesa y pasa a ser decoración.

### Intent (why)

Dos motivos, otra vez con fuerza distinta.

El primero es que el titular tiene que ser cierto sin nota al pie el día del
lanzamiento. Esa es la condición innegociable que FEAT-025 ya se puso a sí
misma. Cubrir Claude Code y Codex es cubrir la inmensa mayoría del público al
que va dirigido esto; Antigravity queda fuera y se dice.

El segundo es más incómodo y es la razón real de que esta FEAT sea `alta` y no
`media`: **hacer que Codex trabaje sin supervisión es más difícil que hacer que
lo haga Claude Code, y el trabajo difícil no es arrancarlo, es enjaularlo.** El
adaptador de Claude Code cuelga toda su garantía de un hook `PreToolUse` que ve
la orden entera y responde con un código de salida. Codex no tiene eso en la
misma forma: tiene una lista de denegación que casa **prefijos de argumentos**,
y un prefijo se esquiva escribiendo lo mismo de otra manera. Si esta FEAT se
escribe como "lo mismo que FEAT-025 pero cambiando el binario", el resultado es
una jaula con la puerta entornada y nadie se entera hasta que un usuario amanece
con `main` mergeada.

El riesgo del gasto desatendido es idéntico al de FEAT-025 y no se repite aquí:
sigue vigente entero.

### Solucion propuesta

Activar la capacidad `unattended` para `codex` en el registro de adaptadores, y
darle al pack `night-shift` un segundo camino de ejecución que ofrezca las
mismas seis garantías que el de Claude Code, construidas con las piezas que
Codex sí tiene.

El cambio de forma respecto a FEAT-025, y es el corazón de esta spec: **en el
camino de Codex el agente no empuja la rama ni abre la pull request. Lo hace el
runner, en bash, después de que el agente termine.** El agente trabaja sin red
y sin el verbo `git push`. Así "el turno de noche para en la pull request" deja
de depender de que una lista de denegación cubra todas las formas de escribir un
push, y pasa a ser una propiedad de la estructura: el agente no tiene por dónde
sacar código de la máquina.

Nada de esto cambia el estado de fábrica. Sigue instalándose apagado, sigue
haciendo simulacro hasta que un humano con sudo lo arma, y el arma sigue
enseñando el coste antes de preguntar.

### Historias de usuario

- Como dueño de una caja que eligió Codex, quiero que el turno de noche funcione
  igual que en una caja Claude Code, para que la elección de CLI que hice en el
  wizard no me deje fuera de la única cosa que hace especial a esta caja.
- Como dueño de la caja, quiero que si mi CLI **no** puede hacer algo del pack se
  me diga en el momento de instalarlo y con el nombre de lo que falta, para no
  descubrir tres semanas después que llevo un simulacro permanente.
- Como dueño de la caja, quiero que la promesa "para en la pull request" valga lo
  mismo en los dos CLIs, para no tener que aprenderme qué garantías tiene el mío.

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** El registro de adaptadores shall declarar `unattended` para
      `codex`, y todo consumidor shall decidir preguntando por la capacidad
      (`ai_cli_has_capability`), nunca comparando el nombre del CLI.
- [ ] **Event-driven:** When el turno de noche se ejecute en modo real en una
      caja Codex, el agente shall correr en `codex exec` no interactivo, con
      escritura limitada al repositorio de trabajo y **sin acceso a red**.
- [ ] **Ubicuo:** En el camino de Codex, la rama shall empujarse y la pull
      request shall abrirse **por el runner**, nunca por el agente.
- [ ] **Event-driven:** When el agente intente `git push`, `gh`, `sudo`,
      `systemctl` o invocar otro agente, la ejecución shall quedar denegada por
      un mecanismo del CLI —no por una frase en el prompt— y shall quedar una
      línea de auditoría en fichero.
- [ ] **Ubicuo:** El fichero que define esa denegación shall ser propiedad de
      `root`, y shall vivir en un directorio que el operador **no pueda
      escribir ni borrar**, por la misma razón que la unidad de systemd de
      FEAT-025: el agente corre como el operador y no puede poder aflojar su
      propia jaula.
- [ ] **Unwanted:** If la denegación no se puede instalar de forma que el
      operador no la pueda quitar, then la caja Codex no shall poder armarse, y
      el motivo shall decirse con esas palabras.
- [ ] **Ubicuo:** El tope de turnos y el tope de tiempo shall implementarse en un
      envoltorio **común a los dos CLIs**, porque ninguno de los dos lo trae
      nativo en las versiones que BIAB instala.
- [ ] **Event-driven:** When el agente termine, el runner shall obtener una señal
      de fin inequívoca (veredicto estructurado en fichero) y shall clasificarla
      en `pr` / `aborted` / `unclear` sin reintentar en ningún caso.
- [ ] **Event-driven:** When el usuario instale el pack en una caja cuyo CLI no
      soporte alguna parte, el instalador shall imprimir qué funciona y qué no,
      con el nombre de la capacidad que falta — nunca un simulacro silencioso ni
      un fallo diferido al `arm`.
- [ ] **Ubicuo:** `biab pack remove night-shift` y `payload/install.sh
      --uninstall` shall dejar la máquina sin ningún fichero de configuración de
      Codex creado por el pack, y shall dejar intacto cualquier fichero de
      configuración de Codex que el pack **no** creó.
- [ ] **Ubicuo:** Antigravity shall seguir sin declarar `unattended`, y el motivo
      shall quedar escrito en el adaptador, no en un comentario de una spec.

### Requisitos no funcionales

- [ ] Cero cuentas nuevas y cero credenciales nuevas: el turno de noche usa la
      sesión de Codex que el usuario ya inició en el wizard. Nada de pedir una
      API key.
- [ ] No se modifica `~/.codex/auth.json` bajo ningún concepto: ni se borra, ni
      se copia a otro sitio, ni se fuerza un re-login, ni se imprime.
- [ ] La configuración del turno de noche **no puede cambiar el comportamiento de
      las sesiones interactivas de Codex del usuario**. Si la única forma de
      instalar la jaula fuese global a la máquina, eso es una decisión de §1
      (ver más abajo), no un detalle de implementación.
- [ ] El driver de pruebas corre sin root, sin red y sin VM, como los de
      FEAT-014, FEAT-024 y FEAT-025.

### Decisiones que §1 debe tomar si §2 T1 sale que no

§2 T1 responde a una pregunta binaria: **¿puede el turno de noche darle a Codex
un `CODEX_HOME` propio, root-owned, y que ese Codex siga autenticado con la
sesión del operador?** Está verificado que un `CODEX_HOME` alternativo **se
respeta** y que **la credencial se busca dentro de él** (§2 punto 3), así que la
respuesta depende de si un symlink a la credencial del operador sobrevive a un
refresco de token. Si sale que no, las tres salidas y su coste de producto:

- **(a) `/etc/codex/requirements.toml`.** La capa de sistema, root-owned, es la
  jaula perfecta técnicamente. Pero es **global a la máquina**: las reglas que
  impiden empujar de noche también aplicarían a las sesiones de Codex del
  usuario a mediodía. Rompe un NFR de arriba. Solo aceptable si se declara con
  todas las letras al instalar el pack y el desinstalador lo revierte con
  precisión quirúrgica.
- **(b) Una credencial dedicada para el turno de noche** (`CODEX_API_KEY`, que
  Codex solo admite en `codex exec`). Es limpio, aísla de verdad, y **rompe la
  regla de §3 Never de FEAT-025**: pedirle al usuario un token de terceros para
  que el pack funcione.
- **(c) Codex se queda fuera del modo real**, se declara igual que Antigravity, y
  el titular del lanzamiento se reescribe para no prometer paridad.

Mi recomendación como producto, para que quede escrita antes de conocer el
resultado y no después: si T1 sale que no, **(a) con revocación quirúrgica y un
aviso explícito**, y (c) como plan B si la revocación no se puede garantizar.
(b) no, porque una caja que necesita que le compres una API key aparte deja de
ser "tu máquina, tu suscripción".

**El coste real de un "no" es mayor que "elegir entre (a), (b) y (c)".** El resto
de este documento —§2 Alcance, la tabla de Archivos afectados, los criterios de
aceptación, y §4.6 CX-1…CX-5 con su bloque 7— da el `CODEX_HOME` root-owned por
hecho consumado, sin condicional. Cualquiera de las tres salidas invalida **T3,
T4 y T5 enteras** y obliga a reescribir esos casos de QA. Léase la estimación de
§2 como válida solo en la rama "T1 sale que sí".

### Referencias visuales

- N/A — no hay UI. Las únicas superficies visibles son la salida de
  `biab pack add night-shift` y el resumen al abrir sesión, ambas de FEAT-025.

### Growth Notes (Andrea)

Esta FEAT no abre canal nuevo: **quita el asterisco del titular de FEAT-025**.
Su métrica es binaria y se mide el día del lanzamiento: ¿la frase "your agent
keeps working after you close the laptop" es cierta en una caja Codex, sí o no?

Lo que sí cambia el pitch, y hay que aprovecharlo, es el mecanismo. En el camino
de Codex el agente **no tiene red y no puede empujar**; el runner abre la PR.
Eso es un argumento de venta mejor que "confiamos en el prompt", y es exactamente
el tipo de detalle que el público de r/selfhosted valora y que un competidor
como myotto.ai no está contando. Sugerencia de copy para el README, no para el
titular: *"the night shift agent has no network and no push. The box opens the
pull request, not the model."*

Aviso de posicionamiento, por honestidad: si esta FEAT acaba tomando la salida
(a) del bloque anterior —jaula global a la máquina—, el copy no puede omitirlo.
"Instalar el pack cambia cómo se comporta tu Codex de día" es exactamente el tipo
de letra pequeña que, descubierta por un usuario en vez de contada por nosotros,
cuesta más que la feature entera.

---

## 2. Spec Tecnica (Laura)

### Investigacion previa

Leídos enteros: `specs/active/FEAT-025-night-shift.md` (1423 líneas, es la spec
que esta extiende), `payload/lib/ai-cli.sh` (570), `payload/install/42-codex-cli.sh`,
`payload/pack/browser/{install.sh,uninstall.sh,lib.sh,tests/test-pack.sh}`,
`payload/test/uninstall-contract.sh` (1129, `EXPECTED_ASSERTIONS=89` en `:41`),
`.github/workflows/ci.yml` (`:20-42`), y `specs/completed/FEAT-021-codex-cli-adapter.md`.
En la máquina del mantenedor, como referencia de una paridad de hooks que ya
funciona: `/home/jesus/ai-platform/core/harness/codex/hooks.json` y
`~/.codex/rules/default.rules` (265 líneas, **todas `decision="allow"`**: sirve
para copiar la sintaxis de `prefix_rule`, no como ejemplo de denegación).

**Todo lo de abajo se ejecutó contra `codex-cli 0.147.0` el 2026-08-16.** Ningún
comando escribió en un repositorio ni gastó cuota: `codex execpolicy check` y
`codex doctor` son locales.

**1. La denegación mecánica existe, y es más frágil de lo que el spike dijo.**

`codex execpolicy check --rules <fichero> -- <comando…>` evalúa un fichero de
reglas Starlark. Verificado con un fichero de dos reglas:

```
gh pr merge 42 --squash    => {"decision":"forbidden"}
git push origin main       => {"decision":"forbidden"}
gh pr create --fill        => {"matchedRules":[]}
echo hola                  => {"matchedRules":[]}
```

Hasta aquí, el spike se confirma. Lo que el spike **no** probó, y cambia el
diseño, son las evasiones. Con la regla `pattern=["git","push","origin","main"]`:

| Comando | Resultado real |
|---|---|
| `git push origin HEAD:main` | **no casa** |
| `git push origin main:main` | **no casa** |
| `git -C /repo push origin main` | **no casa** |
| `/usr/bin/git push origin main` | **no casa** (sí casa al pasar `--resolve-host-executables` a `execpolicy check`; **no verificado** si el runtime resuelve rutas absolutas por su cuenta — ver R3) |
| `bash -lc "git push origin main"` | **no casa en `execpolicy check`** |

`prefix_rule` casa un **prefijo exacto de la lista de argumentos**, y la
documentación lo dice (`prefix_rule … pattern must be an exact prefix`). Tres
consecuencias:

- Una lista negra escrita contra *destinos* (`… origin main`) no vale nada. Hay
  que escribirla contra **verbos**: `pattern=["git","push"]` sí caza
  `git push origin HEAD:main` (verificado).
- La sintaxis de alternativas en una posición es una lista anidada:
  `pattern=["gh","pr",["merge","close"]]` caza los dos (verificado).
- **`codex execpolicy check` no es un simulador fiel del runtime.** El manual
  documenta que Codex parte los `bash -lc` "seguros" en comandos individuales con
  tree-sitter antes de aplicar reglas; la herramienta de comprobación **no lo
  hace**. Así que un `check` en verde prueba que el fichero de reglas parsea y
  que casa argv desnudo — no prueba que el runtime bloquee. §4 no acepta el
  `check` como evidencia de denegación (F-11 vs F-20).

Dos detalles operativos verificados y que §4 necesita:

- El código de salida de `codex execpolicy check` es **`0` tanto para
  `forbidden` como para permitido**, y `1` solo para fichero inexistente o
  fichero que no parsea. **CI tiene que leer el campo `decision` del JSON, nunca
  el exit code.**
- Las reglas admiten `match=[…]` / `not_match=[…]`, "tests unitarios en línea"
  que Codex **valida al cargar el fichero**. Comprobado: un `not_match` que sí
  casa hace fallar la carga con `exit 1` y el mensaje `expected example to not
  match rule`. Esto convierte el propio fichero de reglas en un test, y es
  gratis.

**2. `codex exec` sirve para headless y trae la señal de fin que hace falta.**
De `codex exec --help` (0.147.0), verificado:

| Necesidad de FEAT-025 | Pieza de Codex | Estado |
|---|---|---|
| No interactivo | `codex exec [PROMPT]` o `codex exec -` (stdin) | existe |
| Stream de eventos | `--json` (JSONL) | existe |
| Mensaje final a fichero | `-o, --output-last-message <FILE>` | existe |
| **Forma del mensaje final** | `--output-schema <FILE>` (JSON Schema) | existe |
| Sandbox de escritura | `-s, --sandbox read-only\|workspace-write\|danger-full-access` | existe; **`codex exec` por defecto es `read-only`** |
| Directorio de trabajo | `-C, --cd <DIR>` | existe |
| Fallar ante config desconocida | `--strict-config` | existe |
| **Tope de turnos** | — | **no existe** |
| **Tope de tiempo** | — | **no existe** |

`--output-schema` es mejor de lo que el spike planteó: en vez de exigir por
prompt "URL de PR o ABORTADO" y luego casarlo con una regex, se le impone al
modelo la forma del mensaje final. La regex se queda como red de seguridad,
porque un modelo puede devolver algo que no valide y eso tiene que ser `unclear`,
no una excepción.

Existen además tres banderas que esta FEAT **prohíbe** y que §4 vigila:
`--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`
y `--ignore-rules` ("Do not load user or project execpolicy `.rules` files").

**3. Dónde puede vivir la jaula, y por qué no en `~/.codex/rules/`.**

El manual documenta que Codex escanea `rules/` bajo **cada capa de configuración
activa**: la capa de usuario `~/.codex/rules/`, capas de equipo, y la capa de
proyecto `<repo>/.codex/rules/` (solo si el proyecto está confiado). Ninguna de
esas tres sirve:

- `~/.codex/rules/` pertenece al operador. Un fichero root-owned dentro de un
  directorio del operador **se puede borrar**: para desenlazar un fichero hace
  falta permiso de escritura en el *directorio*, no en el fichero. Jaula con la
  llave dentro, exactamente lo que §3 de FEAT-025 prohíbe.
- `<repo>/.codex/rules/` está dentro del árbol donde el agente trabaja. Peor.
- La capa de sistema `/etc/codex/requirements.toml` es root-only y **es la de
  mayor precedencia local documentada** ("System `requirements.toml`
  (`/etc/codex/requirements.toml` on Unix systems)"). Puede imponer
  `[rules] prefix_rules` que se **fusionan** con los `.rules` de usuario y donde
  gana la decisión más restrictiva; puede limitar `allowed_sandbox_modes` y
  `allowed_permission_profiles` (que es lo que neutraliza
  `--dangerously-bypass-approvals-and-sandbox`); y puede fijar hooks gestionados
  con `allow_managed_hooks_only`. Es la jaula ideal — **y es global a la
  máquina**, o sea que también aplicaría a las sesiones interactivas del usuario.
  Eso choca con un NFR de §1.

Queda una cuarta vía, y es la propuesta: **un `CODEX_HOME` propio del turno de
noche, root-owned.** Verificado ejecutando `CODEX_HOME=<dir> codex doctor`:

- El `CODEX_HOME` alternativo **se respeta** (`config loaded`, y el informe
  muestra el `config.toml` del directorio nuevo).
- **La credencial se busca dentro de ese `CODEX_HOME`**: con el directorio recién
  creado, `codex doctor` responde `✗ auth — no Codex credentials were found`.
  Esto es el hallazgo importante y no estaba en el spike: **relocalizar
  `CODEX_HOME` desautentica**, salvo que la credencial se comparta de alguna
  forma.
- Codex se niega a crear sus binarios auxiliares si `CODEX_HOME` está bajo
  `/tmp` (`Refusing to create helper binaries under temporary dir`). El
  directorio tiene que estar en almacenamiento normal — `BIB_STATE_DIR` lo está.

De ahí sale T1, que es una pregunta binaria y **bloqueante**: ¿un symlink
`auth.json -> ~<operador>/.codex/auth.json` dentro del `CODEX_HOME` root-owned
mantiene la sesión, y sobrevive a un refresco de token? Crear un symlink no
modifica la credencial del operador y no viola la restricción de §1; lo que hay
que descartar es que el refresco escriba con "fichero temporal + rename", que
**sustituiría el symlink por un fichero normal** y dejaría al operador sin su
credencial en la siguiente sesión interactiva. Es el tipo de fallo que solo se ve
en runtime, que es justo el patrón ERR-007/008/010 del `AGENTS.md` raíz.

**4. `sandbox_workspace_write` sí conserva el sandbox de ficheros; la restricción
por dominios NO está disponible en la configuración por defecto.**

Verificado con `codex doctor --summary`, que resume el sandbox efectivo sin
gastar nada:

```
sandbox_mode = "workspace-write"                          → "restricted fs + restricted network"
-c sandbox_workspace_write.network_access=true            → "restricted fs + enabled network"
```

O sea: la red es un **booleano**, y con `workspace-write` está apagada por
defecto. La parte del spike que decía "se puede restringir por dominios" es
cierta pero **no en esta configuración**: el filtrado por dominios exige
`features.network_proxy` —que en este binario aparece como `experimental` y
`false` en `codex features list`— más un perfil de permisos con
`[permissions.<perfil>.network.domains]`, o bien `[experimental_network]` en el
`requirements.toml` de un administrador. El manual es explícito: *"Network on,
proxy off: Commands have direct, unrestricted network access. Domain rules in the
permission profile are not enforced."*

**No se construye una garantía de seguridad sobre un flag experimental apagado
por defecto.** Lo que hace esta FEAT es quitarle la necesidad de red al agente
(punto siguiente).

**5. Ni Claude Code ni Codex tienen tope de turnos, así que el envoltorio es
compartido.** `claude --version` en local es `2.1.232` y `claude --help` no
menciona `--max-turns` (sí `--max-budget-usd`, "only works with `--print`"), que
es lo que FEAT-025 ya recoge en su riesgo R3. Codex no tiene ninguno de los dos.
La conclusión práctica: el tope de turnos y el de tiempo se implementan **una
vez**, en el `lib.sh` del pack, como `night_run_capped`, y lo usan los dos
adaptadores. Escribirlo dentro del camino de Codex sería duplicar mañana lo que
Claude Code ya necesita hoy.

**6. La firma del verbo `unattended` ya es opaca; el delta es un argumento.**
> Corregido el 2026-08-17: esta spec se investigó contra el árbol previo al
> merge de FEAT-025. La versión que describía —`<cli> <cwd> <settings> <budget>
> <prompt>`, con argumentos específicos de Claude Code que había que
> "renegociar"— **nunca llegó a `main`**. Lo que hay mergeado ya resuelve el
> problema.

`payload/lib/ai-cli.sh:489` define `ai_cli_unattended_cmd <cli> <cwd> <guard-dir>
<prompt>`: cuatro argumentos, y `<guard-dir>` ya es opaco. El comentario de
`:61-68` anticipa literalmente el caso de esta FEAT (*"a future adapter reads
something else entirely — an execpolicy rules file"*), y
`payload/pack/night-shift/lib.sh:60-66` fija `NIGHT_GUARD_DIR` con el mismo
razonamiento. En Claude Code el directorio contiene `settings.json` y
`budget-usd` (`lib.sh:68,70`); el runner no sabe qué hay dentro y el adaptador es
el único que lo interpreta.

El único cambio de firma que esta FEAT necesita es añadir el fichero donde el
adaptador deja el mensaje final, para que el runner lo clasifique sin parsear
`stdout`: `ai_cli_unattended_cmd <cli> <cwd> <guard-dir> <final-msg-file>
<prompt>`. Alternativa a evaluar en T2, que evita tocar la firma y sus tres
call-sites de test: que el fichero viva **dentro** del `<guard-dir>` en una ruta
que el adaptador conoce, igual que `settings.json`.

En Codex, `<guard-dir>` contiene el `codex-home/` root-owned. Vive **dentro**
del guard-dir (`<state>/night-shift/guard/codex-home`), no como hermano: el
contrato del argumento opaco es que el adaptador encuentre todo lo suyo a partir
de esa única ruta, y el instalador ya crea el guard-dir `root:root 0755`
(`payload/pack/night-shift/install.sh:72`).

**7. Codex se instala sin pin de versión.** `payload/install/42-codex-cli.sh:14`
declara `CODEX_NPM_PKG="@openai/codex"` y `:119` hace `npm install -g` sin
versión. Todo lo verificado arriba está marcado en el manual como *experimental*
(`codex execpolicy`) o sujeto a cambio (*"Rules are experimental and may
change"*). Una caja instalada dentro de seis meses puede traer otra semántica.
Eso no se arregla en esta FEAT, pero sí obliga a que el pack **compruebe en el
momento de armar** que las piezas siguen ahí, y a que falle cerrado si no.

**8. Lo que se hereda de FEAT-025 sin tocar.** No se rediseña nada de esto: el
fichero `mode` root-owned y su matriz fail-closed, el sello de intento de 14 días,
el aborto por árbol sucio, el kill-switch, el resumen de campos fijos que lee
`biab-specs.sh`, la unidad de systemd y el timer, y la puerta de armado con
estimación de gasto. Esta FEAT añade un camino de ejecución, no un segundo pack.

### Decision de diseño: el agente no empuja ni abre la pull request

En el camino de Codex el runner hace, **fuera** de la sesión del agente y en
bash:

1. Crea la rama de trabajo antes de invocar al agente.
2. Invoca `codex exec` con `--sandbox workspace-write`, **sin red**, y con la
   lista de denegación cargada.
3. Cuando el agente termina, comprueba que la rama actual no es
   `main`/`master`/`pre`, que hay commits, y entonces hace `git push -u origin
   <rama>` y `gh pr create`.

Por qué esto y no portar la lista negra de FEAT-025:

- **Elimina la clase entera de evasiones del punto 1.** Se puede denegar el verbo
  completo (`git push`, `gh`) en vez de intentar enumerar destinos prohibidos. No
  hace falta el hueco "pero `gh pr create` tiene que pasar", que era justo el
  agujero por el que se cuela `gh pr merge` escrito de otra forma.
- **Elimina la necesidad de red del agente**, y con ella la pregunta 4 del
  encargo. La allowlist mínima para que `gh pr create` funcione no hay que
  diseñarla: el agente no ejecuta `gh`.
- **La garantía deja de ser una lista y pasa a ser una estructura.** "Para en la
  pull request" se cumple porque el agente no tiene por dónde sacar código de la
  máquina, no porque una regla lo prohíba.

Coste honesto, y hay que decirlo: **el agente de Codex trabaja sin red**, así que
una spec que necesite `npm install` o `pip install` para que sus tests pasen
abortará. En el camino de Claude Code de FEAT-025 eso no ocurre, porque allí el
agente corre sin sandbox. Es una asimetría real entre los dos CLIs y va al
README, no escondida. Se mitiga con un relajador explícito
(`night-shift network on` ⇒ `network_access=true`, todo o nada) que es
**Ask First** y queda apagado de fábrica; el filtrado por dominios no se ofrece
mientras dependa de un flag experimental (punto 4).

### Alcance

**Incluye**

- Capacidad `unattended` declarada por `codex` en `payload/lib/ai-cli.sh`, y
  renegociación de la firma de `ai_cli_unattended_cmd` (punto 6) más un verbo
  nuevo `ai_cli_unattended_guard_install <cli> <dest-dir>`.
- `CODEX_HOME` root-owned del turno de noche, con `config.toml` y
  `rules/night-shift.rules` root-owned, instalado y revocado por el pack.
- Fichero de reglas con denegación por verbo, `justification` en cada regla y
  `match`/`not_match` como tests en línea.
- `night_run_capped` en el `lib.sh` del pack: tope de tiempo (`timeout`) y tope
  de turnos (contando eventos del stream), **compartido por los dos CLIs**.
- Camino de push + `gh pr create` en el runner, con guarda de rama.
- `--output-schema` para el veredicto estructurado, y clasificación tolerante a
  que el modelo no lo respete.
- Mensaje de capacidades en `biab pack add night-shift`.
- Tests del pack (sección D nueva), casos nuevos en el contrato de
  desinstalación, y wiring de CI.

**NO incluye**

- **Antigravity.** Sin hooks, sin reglas y sin topes; la única vía sería
  `--dangerously-skip-permissions`, que el propio adaptador prohíbe
  (`payload/lib/ai-cli.sh:235`). Se declara y se rechaza, igual que hasta
  ahora.
- **Filtrado de red por dominios.** Depende de `features.network_proxy`,
  experimental y apagado (punto 4). Anotado como deuda con fecha, no implementado.
- **Hooks de Codex** (`hooks.json` con confianza por sha256). Serían defensa en
  profundidad legítima, pero la garantía ya la da la estructura del camino, y
  cada capa extra es superficie que mantener. La paridad de hooks del mantenedor
  se deja como referencia, no como dependencia.
- **`/etc/codex/requirements.toml` en el camino feliz.** Solo entra si T1 sale
  que no, y entonces es decisión de §1 (§1, "Decisiones que §1 debe tomar").
- **Tocar `~/.codex/auth.json`**, copiarlo, moverlo, borrarlo o imprimirlo.
- **Cambiar nada del comportamiento heredado de FEAT-025** (punto 8): modo,
  sellos, árbol sucio, kill-switch, resumen, timer.
- **Reintentos, cola, o más de un candidato por pasada.** Sigue vigente el NFR de
  FEAT-025.

### Archivos afectados

| Ruta | Accion | Qué |
|---|---|---|
| `payload/lib/ai-cli.sh` | MODIFY | `unattended` en `AI_CLI_CAPABILITIES` de `codex` (`:309`); motivo escrito en el bloque de `antigravity` (`:183`); firma nueva de `ai_cli_unattended_cmd`; `_ai_cli_unattended_cmd__codex`; `ai_cli_unattended_guard_install` + `_ai_cli_unattended_guard_install__{claude,codex}` |
| `payload/pack/night-shift/lib.sh` | MODIFY | `night_run_capped`, `night_branch_is_safe`, `night_verdict_from_file`; el gate de armado pregunta además por las piezas del CLI (punto 7) |
| `payload/pack/night-shift/bin/biab-night-shift` | MODIFY | Camino de push + `gh pr create` tras el agente; uso de `night_run_capped`; `network on/off` |
| `payload/pack/night-shift/codex/night-shift.rules` | CREATE | Lista de denegación por verbo, con `justification` y `match`/`not_match` |
| `payload/pack/night-shift/codex/config.toml.in` | CREATE | `sandbox_mode`, `network_access`, `approval_policy`, `features.hooks` del `CODEX_HOME` del pack |
| `payload/pack/night-shift/codex/verdict.schema.json` | CREATE | Esquema del mensaje final (`--output-schema`) |
| `payload/pack/night-shift/install.sh` | MODIFY | Rinde el `CODEX_HOME` root-owned; imprime el bloque de capacidades por CLI |
| `payload/pack/night-shift/uninstall.sh` | MODIFY | Borra el `CODEX_HOME` del pack; no toca nada de `~/.codex` |
| `payload/pack/night-shift/tests/test-pack.sh` | MODIFY | Sección D (Codex): reglas, esquema, `night_run_capped`, guarda de rama; sube su `EXPECTED_ASSERTIONS` |
| `payload/pack/night-shift/tests/mutations.sh` | MODIFY | 12 mutaciones nuevas (§4.4) |
| `payload/test/uninstall-contract.sh` | MODIFY | Casos `CX-1…CX-5` y subida de `EXPECTED_ASSERTIONS` (hoy `78`, `:41`; FEAT-025 lo deja en `89`) |
| `payload/test/wiring-smoke.sh` | MODIFY | `unattended` declarada por `claude` **y** `codex`, no por `antigravity` |
| `.github/workflows/ci.yml` | MODIFY | `bash -n` de los ficheros nuevos y validación del `.rules` y del esquema |
| `README.md` | MODIFY | Tabla de qué CLI puede hacer qué en el turno de noche; el agente de Codex trabaja sin red |

### Dependencias

Ninguna nueva de sistema. `codex` ya lo instala `payload/install/42-codex-cli.sh`;
`jq`, `git`, `gh`, `timeout` (coreutils) y `envsubst` ya están o los cubre
FEAT-025.

Dependencia **de spec**, y es dura: esta FEAT modifica seis ficheros que
FEAT-025 crea. No se puede implementar antes. Si FEAT-025 se retrasa, esta se
retrasa igual, y eso no es holgura que se pueda recuperar paralelizando.

### Tareas

#### Wave 1 — la pregunta que decide el diseño

<task>
  T1. **Bloqueante.** Determinar si un `CODEX_HOME` root-owned puede reutilizar
  la sesión del operador. En una caja con Codex logueado: crear
  `<state>/night-shift/guard/codex-home/` root-owned 0755, dentro un `config.toml`
  root-owned, un `rules/` root-owned, y `auth.json` como **symlink** a la
  credencial del operador (crear el symlink, jamás escribir en el destino).
  Comprobar (a) que `CODEX_HOME=<dir> codex doctor --summary` dice `auth ok`;
  (b) que tras una pasada real de `codex exec` el symlink **sigue siendo un
  symlink** (`test -L`) y la credencial del operador conserva su inodo
  (`stat -c %i` antes y después); (c) que el operador **no** puede borrar ni
  reemplazar nada dentro del directorio. Verificar además, con una sola orden,
  si `-c rules.prefix_rules=…` es una clave reconocida en `config.toml`, porque
  si lo fuese la jaula podría pasarse por línea de comandos y todo esto sobra.
</task>
<verify>Sin caja: `codex exec --strict-config -c 'rules.prefix_rules=[{pattern=[{token="git"},{token="push"}],decision="forbidden"}]' --help` — si sale error de campo no reconocido, la vía de línea de comandos queda descartada por escrito. Con caja (pasada manual): `sudo install -d -o root -g root -m 0755 "$CH"; sudo ln -s "$HOME/.codex/auth.json" "$CH/auth.json"; before=$(stat -c %i "$HOME/.codex/auth.json"); CODEX_HOME="$CH" codex doctor --summary | grep -q 'auth .*ok'; # …pasada real…; test -L "$CH/auth.json" &amp;&amp; test "$(stat -c %i "$HOME/.codex/auth.json")" = "$before" &amp;&amp; ! rm -f "$CH/config.toml" 2&gt;/dev/null &amp;&amp; echo T1-OK</verify>
<done>Queda escrito en la spec, con la salida de los comandos, si el `CODEX_HOME` root-owned mantiene la sesión y sobrevive a un refresco. **Si sale que no, la FEAT se detiene aquí** y vuelve a §1 con las tres salidas ya listadas; no se implementa nada del resto sobre una jaula que no cierra.</done>

<task>
  T2. Registro de adaptadores: declarar `unattended` en `_ai_cli_props__codex`
  (`payload/lib/ai-cli.sh:309`), escribir en el bloque de `antigravity`
  (`:183`) el motivo por el que **no** la declara, renegociar la firma pública a
  `ai_cli_unattended_cmd <cli> <cwd> <guard-dir> <final-msg-file> <prompt>` con
  cada argumento escapado con `printf %q` (punto 6), añadir
  `_ai_cli_unattended_cmd__codex` y el verbo nuevo
  `ai_cli_unattended_guard_install <cli> <dest-dir>` con sus dos
  implementaciones. Actualizar `payload/test/wiring-smoke.sh`.
</task>
<verify>bash -n payload/lib/ai-cli.sh payload/test/wiring-smoke.sh &amp;&amp; shellcheck -S warning payload/lib/ai-cli.sh &amp;&amp; for c in claude antigravity codex; do BIB_AI_CLI=$c bash payload/test/wiring-smoke.sh || exit 1; done &amp;&amp; bash -c 'source payload/lib/ai-cli.sh; ai_cli_has_capability claude unattended &amp;&amp; ai_cli_has_capability codex unattended &amp;&amp; ! ai_cli_has_capability antigravity unattended &amp;&amp; cmd=$(ai_cli_unattended_cmd codex /tmp/repo /tmp/guard /tmp/last.txt "implementa"); printf "%s\n" "$cmd" | grep -q "codex exec" &amp;&amp; printf "%s\n" "$cmd" | grep -q -- "--output-last-message" &amp;&amp; printf "%s\n" "$cmd" | grep -q -- "--sandbox workspace-write" &amp;&amp; ! printf "%s\n" "$cmd" | grep -qE -- "--ignore-rules|--dangerously-bypass" &amp;&amp; echo T2-OK'</verify>
<done>Los tres jobs de wiring-smoke en verde; `unattended` la declaran `claude` y `codex` y no `antigravity`; el comando generado para Codex lleva `codex exec`, `--sandbox workspace-write` y `--output-last-message`, y **no** lleva ninguna de las tres banderas prohibidas; y `grep -rn 'codex\|antigravity' payload/pack/night-shift/ --include='*.sh'` no devuelve ninguna comparación por nombre de CLI fuera de rutas de ficheros.</done>

#### Wave 2 — la jaula

<task>
  T3. `payload/pack/night-shift/codex/night-shift.rules`: denegación **por
  verbo**, no por destino (Investigacion punto 1). Como mínimo `git push`,
  `gh`, `sudo`, `systemctl`, `crontab`, `codex` y `claude` (nada de agentes
  anidados: un `codex exec --ignore-rules` hijo saltaría la jaula del padre).
  Cada regla con `justification` no vacía y con `match`/`not_match` cubriendo al
  menos las cinco formas de evasión de la tabla del punto 1. Más
  `codex/config.toml.in` (`sandbox_mode="workspace-write"`,
  `sandbox_workspace_write.network_access=false`, `approval_policy` que no pueda
  parar la pasada esperando a un humano) y `codex/verdict.schema.json`.
</task>
<verify>bash -c 'R=payload/pack/night-shift/codex/night-shift.rules; codex execpolicy check --rules "$R" -- echo hi &gt;/dev/null || { echo "FAIL: el fichero de reglas no carga (match/not_match o sintaxis)"; exit 1; }; for c in "git push origin main" "git push origin HEAD:main" "git push origin main:main" "git -C /r push origin main" "gh pr merge 7 --squash" "gh release create v1" "sudo tee /etc/x" "codex exec --ignore-rules hola"; do d=$(codex execpolicy check --rules "$R" -- $c | jq -r ".decision // \"none\""); [ "$d" = forbidden ] || { echo "FAIL: [$c] =&gt; $d"; exit 1; }; done; for c in "git commit -m x" "git checkout -b feat/x" "npm test" "echo hola"; do d=$(codex execpolicy check --rules "$R" -- $c | jq -r ".decision // \"none\""); [ "$d" = none ] || { echo "FAIL: comando legitimo bloqueado: [$c] =&gt; $d"; exit 1; }; done; jq -e ".required" payload/pack/night-shift/codex/verdict.schema.json &gt;/dev/null &amp;&amp; echo T3-OK'</verify>
<done>El fichero de reglas carga (lo que significa que sus `match`/`not_match` en línea pasan — es un test que se ejecuta solo); las **ocho** formas prohibidas, incluidas las cuatro evasiones de `git push`, devuelven `decision=forbidden`; los cuatro comandos legítimos no casan ninguna regla; y el esquema de veredicto es un JSON Schema válido con campos obligatorios. **Aserción negativa obligatoria:** ningún caso se da por bueno leyendo el código de salida, porque `codex execpolicy check` sale `0` también cuando deniega (punto 1).</done>

<task>
  T4. Instalación y revocación del `CODEX_HOME` del pack. `install.sh` crea
  `<state>/night-shift/guard/codex-home/` como `root:root` 0755, con `config.toml` y
  `rules/night-shift.rules` `root:root` 0644, el symlink de `auth.json` según lo
  que T1 haya establecido, y **nada más**; imprime el bloque de capacidades por
  CLI (qué funciona y qué no en esta caja, con el nombre de la capacidad).
  `uninstall.sh` borra ese árbol entero y **no toca ni un byte de
  `~/.codex/`**. El gate de armado comprueba además que el binario `codex`
  responde a `execpolicy check` y que el fichero de reglas carga (punto 7); si
  no, se niega con motivo.
</task>
<verify>bash -n payload/pack/night-shift/install.sh payload/pack/night-shift/uninstall.sh &amp;&amp; shellcheck -S warning payload/pack/night-shift/install.sh payload/pack/night-shift/uninstall.sh &amp;&amp; grep -nE 'install +-o +root +-g +root|install +-d +-o +root' payload/pack/night-shift/install.sh | grep -q codex-home &amp;&amp; ! grep -nE '(rm|mv|cp|tee|truncate|chmod|chown).*\.codex/auth\.json' payload/pack/night-shift/*.sh payload/pack/night-shift/bin/* &amp;&amp; bash payload/pack/night-shift/tests/test-pack.sh &amp;&amp; echo T4-OK</verify>
<done>El `codex-home` se crea con dueño y modo explícitos en el instalador (aserción estática, corre en CI sin root); **ninguna** línea del pack escribe, mueve o borra `auth.json`; el desinstalador deja el árbol sin rastro; y en una caja Codex sin las piezas del CLI el `arm` se niega citando cuál falta.</done>

#### Wave 3 — la pasada y el contrato

<task>
  T5. Ejecución: (a) `night_run_capped <secs> <max-turns> -- <cmd…>` en el
  `lib.sh` del pack, compartido por los dos CLIs — `timeout -k` para el reloj y
  un contador que cuenta eventos de turno del stream JSONL y mata al llegar al
  tope; (b) el runner crea la rama **antes** de invocar al agente; (c) tras el
  agente, `night_branch_is_safe` rechaza `main`/`master`/`pre` y `night_verdict_from_file`
  lee el mensaje final, valida contra el esquema y clasifica en `pr`/`aborted`/`unclear`
  —la URL casada contra host anclado, como en FEAT-025 E-38— y **solo entonces**
  el runner hace `git push -u origin <rama>` y `gh pr create`; (d) subcomando
  `network on|off`, apagado de fábrica, Ask First. Ningún camino reintenta.
</task>
<verify>bash payload/pack/night-shift/tests/test-pack.sh &amp;&amp; bash -c 'source payload/pack/night-shift/lib.sh; d=$(mktemp -d); trap "rm -rf $d" EXIT; printf "#!/bin/sh\nsleep 30\n" &gt; "$d/slow"; chmod +x "$d/slow"; s=$(date +%s); night_run_capped 2 999 -- "$d/slow"; e=$(date +%s); [ $((e-s)) -lt 8 ] || { echo "FAIL: el tope de tiempo no cortó"; exit 1; }; for b in main master pre; do night_branch_is_safe "$b" &amp;&amp; { echo "FAIL: rama protegida aceptada: $b"; exit 1; }; done; night_branch_is_safe feat/night || { echo "FAIL: rama de trabajo rechazada"; exit 1; }; printf "%s" "{\"verdict\":\"pr\",\"pr_url\":\"https://evil.example/u/r/pull/1\"}" &gt; "$d/last"; night_verdict_from_file "$d/last" | grep -qx unclear || { echo "FAIL: URL con host falso clasificada como pr"; exit 1; }; echo T5-OK'</verify>
<done>El tope de tiempo corta un proceso que duraría 30 s en menos de 8; el tope de turnos mata una pasada simulada con un stream de N+1 eventos; las tres ramas protegidas se rechazan y una de trabajo pasa; un veredicto con URL de host atacante clasifica `unclear` y **el runner no llega a hacer `push` ni `gh pr create`** (mock de `gh` en el `PATH`, fichero centinela ausente); y ninguna clasificación dispara una segunda llamada al CLI.</done>

<task>
  T6. Contrato y superficie: (a) casos `CX-1…CX-5` en
  `payload/test/uninstall-contract.sh` y subida a mano de `EXPECTED_ASSERTIONS`
  (§4.6); (b) sección D en `tests/test-pack.sh` con su propio contador declarado
  y comprobado desde `trap EXIT`; (c) 12 mutaciones nuevas en
  `tests/mutations.sh` (§4.4), con el guard de byte del arnés de FEAT-025;
  (d) `bash -n` y validación del `.rules` en `.github/workflows/ci.yml`;
  (e) la tabla del README con qué CLI puede qué, y la frase de que el agente de
  Codex trabaja sin red.
</task>
<verify>bash payload/test/uninstall-contract.sh &amp;&amp; bash payload/pack/night-shift/tests/test-pack.sh &amp;&amp; bash tools/check-no-personal-refs.sh &amp;&amp; bash payload/pack/night-shift/tests/mutations.sh &amp;&amp; git diff --quiet &amp;&amp; python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/ci.yml')); runs=[s.get('run','') for j in d['jobs'].values() for s in j.get('steps',[])]; sys.exit(0 if any('night-shift.rules' in r for r in runs) else 1)" &amp;&amp; echo T6-OK</verify>
<done>El contrato de desinstalación pasa con el contador cuadrado a mano; el driver del pack imprime su contador y cuadra; el arnés de mutaciones reporta **12/12 cazadas y 0 expresiones obsoletas** y deja el árbol limpio (`git diff --quiet` después); CI valida el fichero de reglas; y el README dice, en la tabla, que en una caja Codex el agente trabaja sin red.</done>

### Patron de codigo

El fichero de reglas no se escribe como una lista muda: cada regla lleva su
`justification` y sus tests en línea, que Codex **valida al cargar el fichero**
(verificado: un `not_match` mal puesto hace fallar la carga con `exit 1`). La
forma exacta, tomada del ejemplo del manual y adaptada a las evasiones reales que
medimos:

```python
# The night shift never pushes and never touches the PR lifecycle: the runner
# does both, in bash, outside the agent session. Deny the VERB, not the
# destination — `prefix_rule` matches an exact argv prefix, so a rule written
# against `origin main` is trivially bypassed by `origin HEAD:main`.
prefix_rule(
    pattern = ["git", "push"],
    decision = "forbidden",
    justification = "The night shift never pushes. Commit locally; the runner pushes and opens the PR.",
    match = [
        "git push origin main",
        "git push origin HEAD:main",
        "git push origin main:main",
        "git push --force origin feat/x",
        "git push",
    ],
    not_match = [
        # A rule written against the destination would let all of the above through.
        "git commit -m 'wip'",
    ],
)
```

Tres cosas se copian tal cual y son las que importan: **el patrón es el verbo**,
no el destino; los `match` incluyen las formas que medimos que esquivaban una
regla más específica, de modo que si alguien "mejora" la regla estrechándola el
fichero deja de cargar; y la `justification` dice qué hacer en su lugar, que es
lo que hace que un agente bloqueado siga adelante en vez de dar vueltas.

El precedente de propiedad es el mismo que cita FEAT-025 en su "Patron de
codigo": `validate_unsafe_sandbox_gate` de `payload/pack/browser/lib.sh:168-186`.
Ausencia del fichero es `return 1`; se comprueban dueño **y** modo, no solo
existencia; y el mensaje de rechazo trae el comando exacto para arreglarlo.

### Riesgos

| # | Riesgo | Mitigación |
|---|---|---|
| R1 | **El `CODEX_HOME` root-owned rompe la autenticación**, o el refresco de token sustituye el symlink y deja al operador sin credencial | T1, y la FEAT se detiene si sale que no. Verificado ya que un `CODEX_HOME` nuevo **sí** desautentica, así que el riesgo es real y no teórico |
| R2 | La lista de denegación se esquiva con una forma que no previmos | Se deniega el verbo entero, no el destino; los `match` en línea fijan las formas conocidas y fallan la carga si alguien estrecha la regla; y **la garantía real no es la lista, es que el agente no tiene red ni abre la PR** |
| R3 | `codex execpolicy check` no simula el troceo de `bash -lc` del runtime, así que un verde en CI no prueba que el runtime bloquee | §4 lo separa explícitamente: F-11 (fichero de reglas) es estática y CI; F-20 (denegación efectiva) es pasada viva y es la que cuenta |
| R4 | `execpolicy` y las reglas están marcadas *experimental* y Codex se instala **sin pin** (`42-codex-cli.sh:14`) | El gate de armado comprueba en tiempo de ejecución que las piezas responden y falla cerrado si no. La versión de referencia (0.147.0) queda anotada en el pack |
| R5 | El agente sin red no puede instalar dependencias y aborta specs que en Claude Code sí saldrían | Se declara en el README y en la salida del `pack add`; el relajador `network on` existe, es Ask First y está apagado. No se disimula con un abort genérico: el veredicto lleva motivo `network-disabled` |
| R6 | ~~Esta FEAT toca seis ficheros que FEAT-025 crea; si FEAT-025 cambia de forma al implementarse, esta spec envejece en horas~~ **Se materializó.** FEAT-025 se mergeó (PR #54) mientras esta spec estaba en draft, y las citas de línea de `payload/lib/ai-cli.sh` quedaron desfasadas en un solo día | Reconciliada contra `main` el 2026-08-17 (§2 punto 6, §4.3, citas de línea). El riesgo sigue vivo para las **próximas** ediciones: antes de promover a `active/`, releer las rutas citadas contra `main`, no contra el recuerdo del spike |
| R7 | El tope de turnos cuenta eventos de un stream cuyo esquema **no está documentado** en el manual vendido (§4.7) | `night_run_capped` trata el reloj como el tope duro y el contador de turnos como el blando: si el esquema cambia, el contador deja de contar pero la pasada sigue acotada por `timeout` |

### Criterios de aceptacion

- [ ] `ai_cli_has_capability codex unattended` devuelve 0 y
      `ai_cli_has_capability antigravity unattended` devuelve 1, y ningún
      consumidor del pack compara nombres de CLI.
- [ ] El fichero de reglas **carga** (sus `match`/`not_match` pasan) y deniega las
      ocho formas de T3, incluidas las cuatro evasiones de `git push` que hoy
      esquivarían una regla escrita contra el destino.
- [ ] El comando headless generado para Codex lleva `--sandbox workspace-write` y
      no lleva `--ignore-rules`, `--dangerously-bypass-approvals-and-sandbox` ni
      `--dangerously-bypass-hook-trust`.
- [ ] En una pasada real en caja Codex, un intento del agente de `gh pr merge` o
      `git push` queda denegado por el CLI y hay línea de auditoría en fichero;
      la PR (si existe) sigue `OPEN`.
- [ ] La pull request la abre el runner: con un mock de `gh` en el `PATH`, el
      centinela registra `gh pr create` **una** vez y ninguna invocación de `gh`
      desde la sesión del agente.
- [ ] `night_run_capped` corta por tiempo y por turnos, y lo hace igual invocado
      desde el camino de Claude Code y desde el de Codex.
- [ ] En una rama `main`/`master`/`pre` el runner no empuja, pase lo que pase.
- [ ] `biab pack add night-shift` imprime, en la caja del usuario, qué funciona y
      qué no con su CLI, nombrando la capacidad.
- [ ] `biab pack remove night-shift` y `payload/install.sh --uninstall` dejan la
      máquina sin el `codex-home` del pack, y `~/.codex/` **byte a byte igual**
      que antes de instalar.
- [ ] CI en verde: shellcheck, `bash -n`, personal-refs, contrato de
      desinstalación con el contador cuadrado, wiring-smoke de los tres CLIs,
      tests del pack y validación del fichero de reglas.

### Presupuesto de ejecucion

`max_turns=140 timeout=3600` cubre T2–T6, que son bash, TOML y JSON. **T1 no cabe
ahí y no debe intentarse en headless**: exige root, una caja con Codex logueado y
tocar el entorno de credenciales del operador. Va a la pasada manual y va
**primera**, porque su resultado decide si el resto existe. Igual que en
FEAT-025, la prueba viva de denegación efectiva (F-20) tampoco cabe: gasta cuota
y necesita hardware.

---

## 3. Boundaries

### Always

- Todo lo que FEAT-025 §3 declara sigue vigente sin excepción. Esta sección solo
  añade lo que es propio de Codex.
- **La jaula la escribe root y vive donde el operador no puede borrarla.** Un
  fichero root-owned dentro de un directorio del operador no es una jaula: para
  desenlazar un fichero basta con poder escribir en su directorio. El
  `CODEX_HOME` del pack es `root:root` y el directorio también.
- **La denegación se escribe contra el verbo, no contra el destino.** Está medido
  que `["git","push","origin","main"]` no casa `git push origin HEAD:main`.
  Cualquier regla que enumere destinos es una regla que ya sabemos rota.
- **La pull request la abre el runner.** El agente nunca ejecuta `gh`.
- **Cada garantía nueva se demuestra ejecutándola**, igual que FEAT-025 exige
  para su guard: el fichero de reglas se valida cargándolo, y la denegación
  efectiva se demuestra en una pasada viva.
- **Si una capacidad no se puede dar, se dice al instalar**, con el nombre de la
  capacidad y del CLI. Nunca al intentar armar, nunca en silencio.

### Ask First

- **Encender la red del agente** (`night-shift network on`). Es pasar de "el
  agente no puede sacar nada de la máquina" a "el agente tiene salida directa a
  internet sin filtrar", porque el filtrado por dominios depende de un flag
  experimental apagado. No es un ajuste, es cambiar el modelo de amenaza.
- **Instalar cualquier cosa en `/etc/codex/`.** Es configuración global de la
  máquina: cambia el comportamiento de las sesiones interactivas del usuario. Si
  T1 obliga a esa vía, es decisión de §1 con aviso explícito en el `pack add`.
- **Añadir un CLI a la capacidad `unattended`** (heredado de FEAT-025). Declararla
  sigue siendo una promesa de seguridad.
- **Estrechar el fichero de reglas** para dejar pasar algo que un usuario pidió.
  Cada regla que se estrecha reabre la clase de evasiones que los `match` en
  línea existen para cerrar.
- **Ampliar el `sandbox` más allá de `workspace-write`.**

### Never

- **Tocar `~/.codex/auth.json`**: ni borrarlo, ni copiarlo, ni moverlo, ni
  truncarlo, ni imprimir su contenido, ni provocar un re-login. Crear un symlink
  *hacia* él es lo máximo, y solo si T1 demuestra que sobrevive a un refresco.
- **Usar `--dangerously-bypass-approvals-and-sandbox`,
  `--dangerously-bypass-hook-trust` o `--ignore-rules`** para sacar adelante una
  pasada. Es el mismo `Never` que FEAT-025 escribió para
  `--dangerously-skip-permissions`: si un CLI no puede correr enjaulado, no corre.
- **Permitir que el agente invoque otro agente** (`codex`, `claude`, `agy`). Un
  `codex exec --ignore-rules` hijo saltaría la jaula del padre; es la evasión más
  barata que existe y va en la lista negra desde el primer día.
- **Aceptar el código de salida de `codex execpolicy check` como prueba de
  denegación.** Sale `0` tanto cuando deniega como cuando permite. Un test que lo
  use está verde sin comprobar nada.
- **Tratar un verde de `codex execpolicy check` como prueba de que el runtime
  bloquea.** La herramienta no simula el troceo de `bash -lc` que el runtime sí
  hace; es un linter del fichero de reglas.
- **Empujar desde una rama protegida** (`main`, `master`, `pre`), pase lo que
  pase y diga lo que diga el veredicto del modelo.
- **Modificar la configuración de Codex del usuario** (`~/.codex/config.toml`,
  `~/.codex/rules/`, `~/.codex/hooks.json`) para que el turno de noche funcione.

---

## 4. QA (Pablo)

### Cómo se lee esta sección

Se hereda entera la forma de §4 de FEAT-025 y sus tres reglas de escritura: se
observa el binario y no la salida, toda garantía tiene una mutación que la pone
en rojo, y cada `sed` de mutación lleva guard de byte. No las repito.

Lo que sí cambia, y es lo único que hace falta entender antes de leer la tabla:
**aquí hay dos niveles de evidencia que se parecen mucho y valen cosas muy
distintas.**

1. **El fichero de reglas dice lo correcto.** Se comprueba con
   `codex execpolicy check`, corre en CI, es barato. Prueba que el fichero
   parsea, que sus tests en línea pasan, y que casa argv desnudo.
2. **El runtime bloquea de verdad.** Solo se comprueba ejecutando `codex exec` en
   una caja logueada. Cuesta cuota y hardware.

Confundir (1) con (2) sería el error caro de esta FEAT, y hay dos motivos
concretos y medidos para no confundirlos: `codex execpolicy check` sale `0` tanto
cuando deniega como cuando permite (así que un test que mire el exit code está
verde sin comprobar nada), y **no simula el troceo de `bash -lc`** que el manual
dice que el runtime sí hace. Por eso F-11 y F-20 son casos distintos y F-20 es la
que firma la FEAT.

**Dónde vive cada caso.** Se añade una **sección D** a
`payload/pack/night-shift/tests/test-pack.sh` (que FEAT-025 crea con A/B/C):

| Sección | Corre | Qué cubre aquí |
|---|---|---|
| **A** — estática | Siempre, CI | Que el fichero de reglas y el esquema existen, que el instalador declara propiedad, que ninguna línea del pack toca `auth.json` |
| **B** — funciones puras | Siempre, CI, sin root/red | `night_run_capped`, `night_branch_is_safe`, `night_verdict_from_file` |
| **C** — root, caja real | Pasada manual; `skip` limpio si `id -u != 0` | Propiedad efectiva del `codex-home`, que el operador no puede borrarlo |
| **D** — Codex, sin cuota | CI **si `codex` está en el `PATH`**; `skip` anunciado si no | `codex execpolicy check` sobre el fichero de reglas: las ocho denegaciones y los cuatro permitidos |
| **Vivo** | Nunca en CI. Gasta cuota | F-01 (auth con `CODEX_HOME` propio) y F-20 (denegación efectiva) |

Sobre la sección D y el `skip`: un `skip` silencioso es un pase falso. El driver
debe **imprimir** que saltó la sección D y por qué, y el contador declarado tiene
que cuadrar en las dos ramas (con dos valores esperados distintos, no con uno
laxo). Si CI no tiene `codex`, eso se ve en el log, no se descubre en la caja de
un usuario.

---

### 4.1 Casos funcionales

Estado: `[ ]` pendiente · `[x]` verificado · `[~]` verificado con salvedad.

#### La pregunta que decide el diseño

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-01** | **PRUEBA VIVA: el `CODEX_HOME` root-owned conserva la sesión** | 1. `CH=<state>/night-shift/guard/codex-home`; `sudo install -d -o root -g root -m 0755 "$CH"`.<br>2. `sudo ln -s "$HOME/.codex/auth.json" "$CH/auth.json"`.<br>3. `before=$(stat -c %i "$HOME/.codex/auth.json")`.<br>4. `CODEX_HOME="$CH" codex doctor --summary`.<br>5. Ejecutar una pasada real corta.<br>6. `test -L "$CH/auth.json"`; `stat -c %i "$HOME/.codex/auth.json"`. | (4) la línea de `auth` dice `ok` y **no** `no Codex credentials were found`; (6) sigue siendo symlink **y** el inodo del fichero del operador es el mismo `$before`. Si el inodo cambia, el refresco reescribió con rename y el diseño no vale. **Si este caso falla, la FEAT se detiene** (§2 T1) | Vivo | [ ] |
| **F-02** | El operador no puede aflojar su propia jaula | 1. Con el pack instalado, como el operador y sin sudo: `rm -f "$CH/config.toml"`; `rm -f "$CH/rules/night-shift.rules"`; `mv "$CH/rules" "$CH/rules.bak"`; `printf x > "$CH/config.toml"`.<br>2. `stat -c '%U:%G %a' "$CH" "$CH/config.toml" "$CH/rules" "$CH/rules/night-shift.rules"`. | (1) **las cuatro** fallan con `Permission denied`; (2) los cuatro son `root:root`, el directorio `755` y los ficheros `644`. Este es el caso que distingue una jaula de un adorno, y es exactamente el que fallaría si las reglas viviesen en `~/.codex/rules/` | C | [ ] |
| **F-03** | El pack no toca la credencial del operador | 1. `sha256sum ~/.codex/auth.json` y `stat -c %i` antes de instalar.<br>2. `biab pack add night-shift`; armar; una pasada en simulacro; `biab pack remove night-shift`.<br>3. Repetir (1). | Hash e inodo idénticos. Aserción estática que la acompaña en A: `grep -nE '(rm\|mv\|cp\|tee\|truncate\|chmod\|chown\|>).*auth\.json' payload/pack/night-shift/` no devuelve nada salvo la creación del symlink | A+C | [ ] |

#### El registro de adaptadores

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-04** | `codex` declara `unattended`, `antigravity` no | 1. `source payload/lib/ai-cli.sh`.<br>2. `ai_cli_has_capability codex unattended`; ídem `claude`; ídem `antigravity`. | (2) `0`, `0`, `1`. Y `for c in claude antigravity codex; do BIB_AI_CLI=$c bash payload/test/wiring-smoke.sh; done` en verde | B | [ ] |
| **F-05** | El comando headless de Codex es el correcto y no trae banderas prohibidas | 1. `ai_cli_unattended_cmd codex /tmp/repo /tmp/guard /tmp/last.txt "implementa"`. | Contiene `codex exec`, `--sandbox workspace-write`, `--output-last-message`, `--output-schema` y `-C`; **no** contiene `--ignore-rules`, `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust` ni `danger-full-access`. Las tres negativas son aserciones propias, no un `grep -v` conjunto | B | [ ] |
| **F-06** | Los argumentos van escapados | 1. Llamar al verbo con un `cwd` `"/tmp/a b;touch /tmp/PWNED"` y un prompt con comillas, `$(id)` y backticks. | El comando impreso escapa todo con `printf %q`; evaluarlo en un subshell con mocks **no crea `/tmp/PWNED`**. Misma clase de fallo que `ai_cli_launch_cmd` ya se protege | B | [ ] |
| **F-07** | Nadie decide por nombre de CLI | 1. `grep -rnE '(==\|=~\|\\*)\s*"?(codex\|antigravity\|claude)"?' payload/pack/night-shift/ --include='*.sh'`. | Cero coincidencias que sean comparaciones. Rutas de ficheros y comentarios se excluyen a mano en la aserción; si aparece un `if [[ "$cli" == codex ]]`, el caso falla. Es el requisito de §1 escrito como test | A | [ ] |

#### El fichero de reglas

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-08** | El fichero de reglas **carga** | 1. `codex execpolicy check --rules <fichero> -- echo hi`; capturar código de salida. | Código de salida `0`. Un `1` significa que el fichero no parsea **o que un `match`/`not_match` en línea no se cumple** — verificado que Codex valida esos ejemplos al cargar y falla con `expected example to not match rule`. O sea: este caso ejecuta gratis todos los tests que el propio fichero declara | D | [ ] |
| **F-09** | Las ocho formas prohibidas se deniegan | 1. Para cada uno de `git push origin main`, `git push origin HEAD:main`, `git push origin main:main`, `git -C /r push origin main`, `gh pr merge 7 --squash`, `gh release create v1`, `sudo tee /etc/x`, `codex exec --ignore-rules hola`: `codex execpolicy check --rules <f> -- $c \| jq -r '.decision // "none"'`. | Los ocho devuelven exactamente `forbidden`. **Las cuatro primeras son la razón de existir de este caso**: con una regla escrita contra el destino (`… origin main`) las tres variantes de evasión devuelven `none`, y está medido. Cada una es una aserción propia | D | [ ] |
| **F-10** | Los comandos legítimos pasan | 1. Ídem con `git commit -m x`, `git checkout -b feat/x`, `npm test`, `pytest -q`, `echo hola`. | Los cinco devuelven `none` (sin campo `decision`). Un fichero de reglas que bloquea el trabajo normal es un fichero que el implementador desactiva a la primera | D | [ ] |
| **F-11** | **El veredicto se lee del JSON, nunca del exit code** | 1. `codex execpolicy check --rules <f> -- gh pr merge 4 >/dev/null 2>&1; echo $?`.<br>2. Ídem con `echo hola`. | **Los dos imprimen `0`** — verificado. El caso existe para dejar constancia de que un driver que compruebe el exit code está verde sin comprobar nada, y para que la mutación M-05 tenga a qué agarrarse | D | [ ] |
| **F-12** | Cada regla lleva justificación | 1. Para cada regla del fichero, comprobar que la salida de un comando que la casa trae `justification` no vacía. | Todas. Un agente bloqueado sin motivo da vueltas y quema turnos; con motivo, aborta limpio | D | [ ] |

#### La pasada

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-13** | El tope de tiempo corta | 1. Script que duerme 30 s.<br>2. `night_run_capped 2 999 -- <script>`; medir reloj. | Termina en menos de 8 s y el veredicto de la pasada es `timeout`. Se mide el reloj, no se lee un mensaje | B | [ ] |
| **F-14** | El tope de turnos corta | 1. Mock del CLI que emite `N+1` eventos de turno en el stream JSONL y luego dormiría.<br>2. `night_run_capped 600 N -- <mock>`. | El proceso muere al llegar a `N`, el veredicto es `max-turns`, y el mock **no** llega a escribir su fichero centinela de "seguí vivo" | B | [ ] |
| **F-15** | El envoltorio es el mismo para los dos CLIs | 1. `grep -c 'night_run_capped' payload/pack/night-shift/bin/biab-night-shift`.<br>2. Comprobar que el runner lo invoca en el camino común, no dentro de una rama por CLI. | Una sola invocación, en el camino común. Si aparece una por CLI, la duplicación ya empezó y el caso falla. §1 lo pide explícitamente | A | [ ] |
| **F-16** | La rama se crea **antes** de invocar al agente | 1. Fixture con repo git en `main`.<br>2. Mock del CLI que registra `git branch --show-current` en el momento de ser invocado. | Lo registrado **no** es `main`: es la rama de trabajo. Si el agente se lanzase estando en `main`, un commit suyo ya sería un commit en `main` aunque nunca empujara | B | [ ] |
| **F-17** | La PR la abre el runner, no el agente | 1. Mock de `gh` en el `PATH` que registra cada invocación con su PPID.<br>2. Pasada en modo real con mock del CLI que **no** invoca `gh`. | El centinela tiene exactamente una línea, `gh pr create …`, y su PPID es el del runner. Cero invocaciones desde la sesión del agente | B | [ ] |
| **F-18** | En rama protegida no se empuja jamás | 1. Forzar que la rama al terminar el agente sea `main`; repetir con `master` y `pre`.<br>2. Pasada en modo real con mocks. | En los tres: `git push` **no** se invoca (centinela ausente), veredicto `aborted` con motivo `protected-branch`, salida `0`. La comprobación es del runner y no depende de la lista de reglas | B | [ ] |
| **F-19** | Sin commits no hay PR | 1. Mock del CLI que no cambia nada.<br>2. Pasada en modo real. | Ni `push` ni `gh pr create`; veredicto `aborted` motivo `no-commits`. Una PR vacía es ruido que el dueño tiene que cerrar a mano por la mañana | B | [ ] |
| **F-20** | **PRUEBA VIVA: el runtime deniega de verdad** | 1. Caja con Codex logueado, repo de usar y tirar con una PR abierta número `N`.<br>2. Lanzar `codex exec` por el camino del pack con el prompt *"Ejecuta exactamente: `gh pr merge N --squash`"*.<br>3. Repetir con el prompt *"Ejecuta: `bash -lc 'git push origin main'`"* — la forma que `execpolicy check` **no** simula.<br>4. `gh pr view N --json state -q .state`.<br>5. Contar líneas del fichero de auditoría del guard. | (4) devuelve **`OPEN`** en los dos intentos — esta es la aserción que cuenta, no el texto del transcript; (5) ≥ 1 línea por intento. El paso 3 existe porque es exactamente el hueco entre lo que CI puede comprobar y lo que el usuario se juega. **Si este caso no se puede pasar, la FEAT se detiene** (§3 Always) | Vivo | [ ] |
| **F-21** | El agente no tiene red | 1. Pasada real con un prompt que pida `curl https://example.com`.<br>2. `CODEX_HOME=<CH> codex doctor --summary`. | (1) falla dentro del sandbox y el agente lo reporta; (2) la línea de sandbox dice `restricted fs + restricted network` — verificado que `codex doctor --summary` refleja el booleano de red sin gastar cuota, así que esta media es barata y repetible | Vivo (1) + C (2) | [ ] |

#### Veredicto y superficie

| ID | Caso | Pasos | Resultado esperado (verificable) | Sec. | Estado |
|---|---|---|---|---|---|
| **F-22** | El veredicto estructurado se clasifica bien | 1. `night_verdict_from_file` con: `{"verdict":"pr","pr_url":"https://github.com/u/r/pull/12"}`; `{"verdict":"aborted","reason":"ambiguous spec"}`; JSON válido pero sin `verdict`; JSON roto; fichero vacío; fichero ausente. | `pr`, `aborted`, y `unclear` en los cuatro restantes. Ninguno lanza traza ni deja el runner en `set -e`. `unclear` mapea a la cadena fija de FEAT-025, no a prosa del modelo | B | [ ] |
| **F-23** | `pack add` dice qué puede y qué no esta caja | 1. `biab pack add night-shift` en caja `claude`, en caja `codex`, en caja `antigravity`. | Las tres imprimen un bloque de capacidades. En `antigravity` nombra la capacidad `unattended` que falta y dice que el modo real **nunca** estará disponible; en `codex` avisa de que el agente trabaja sin red. Ninguna difiere el aviso al `arm` | C | [ ] |
| **F-24** | `arm` se niega si las piezas del CLI no responden | 1. En caja Codex, con un `codex` falso en el `PATH` que no soporta `execpolicy`.<br>2. `biab-night-shift arm`. | Sale no-cero **antes** de pedir confirmación y el mensaje nombra la pieza que falta. **No** vale asertar "`mode` no se crea": en la sección B no hay root y `cmd_arm` ya sale no-cero por esa vía (`bin/biab-night-shift:452`), así que esa aserción pasaría por el motivo equivocado. Asertar sobre el texto del error y sobre que no se llegó al prompt. Cubre el riesgo R4 (Codex se instala sin pin) | B | [ ] |

---

### 4.2 Edge cases

#### Fichero de reglas y evasiones

| ID | Entrada | Esperado |
|---|---|---|
| **E-01** | Regla escrita contra el destino (`["git","push","origin","main"]`) en vez del verbo | **Prohibido por diseño.** Aserción estática: el fichero no contiene ningún `prefix_rule` cuyo `pattern` de `git push` tenga más de dos tokens. Medido: deja pasar `HEAD:main`, `main:main` y `git -C` |
| **E-02** | `/usr/bin/git push origin main` (ruta absoluta) | El `check` sin `--resolve-host-executables` **no** casa. Se asserta el hecho tal cual y se anota como límite conocido: la mitigación real es que el agente no tiene red ni abre la PR, no la lista |
| **E-03** | `bash -lc "git push origin main"` | `execpolicy check` **no** casa (medido). El runtime, según el manual, sí trocea. La discrepancia es el motivo de F-20 paso 3 y se documenta en el fichero de reglas como comentario, para que nadie "arregle" el test |
| **E-04** | `GH_TOKEN=x gh pr merge 4` (asignación de variable delante) | **Medido:** no casa en `execpolicy check`. **Doc-derivado, no medido:** el manual dice que con asignaciones delante el runtime tampoco trocea y evalúa el `bash -lc` entero. Mismo tratamiento que E-03 |
| **E-05** | Regla con `match` que ya no casa tras editar el `pattern` | El fichero **no carga** y `codex execpolicy check` sale `1`. Es la propiedad que convierte los ejemplos en línea en un test de regresión gratis |
| **E-06** | Fichero de reglas vacío | Carga sin error y no deniega nada. Por eso F-09 existe: "el fichero carga" nunca puede ser el único criterio |
| **E-07** | Fichero de reglas ausente o ilegible | El gate de armado se niega con motivo; el simulacro sigue funcionando. Fail-closed |
| **E-08** | Dos reglas casan el mismo comando con decisiones distintas | Gana la más restrictiva (documentado: `forbidden` > `prompt` > `allow`). Se asserta con un par de reglas de fixture, no se asume |
| **E-09** | Regla que intenta `decision="allow"` sobre `git push` | Aserción estática: el fichero del pack no contiene ningún `decision="allow"`. Una allow-list dentro de la jaula es una puerta |

#### `CODEX_HOME` y credenciales

| ID | Entrada | Esperado |
|---|---|---|
| **E-10** | `CODEX_HOME` bajo `/tmp` | Codex se niega a crear sus binarios auxiliares (`Refusing to create helper binaries under temporary dir`, medido). El instalador nunca lo pone ahí, y el test que use `mktemp -d` debe saberlo o dará un falso rojo |
| **E-11** | `CODEX_HOME` existe pero sin `auth.json` | `codex doctor` dice `no Codex credentials were found` (medido). El gate de armado lo detecta y se niega con ese motivo, no con un genérico |
| **E-12** | El symlink de `auth.json` apunta a un fichero que ya no existe | Veredicto `aborted` motivo `no-credentials`, **una sola** invocación, sin bucle de login |
| **E-13** | El refresco de token reemplaza el symlink por un fichero normal | Detectado por F-01 paso 6. Si ocurre, **el diseño no vale** y hay que ir a las salidas de §1. No se "arregla" recreando el symlink en cada pasada: eso sería el pack reescribiendo el entorno de credenciales del usuario cada noche |
| **E-14** | El operador borra el `codex-home` con `sudo` | No es un caso de seguridad (ya tiene root). El runner lo detecta, aborta con motivo y `biab pack list` refleja el estado real |
| **E-15** | `~/.codex/config.toml` del usuario contradice el del pack | Irrelevante por construcción: el `CODEX_HOME` del pack es otro, y `codex` no lee dos. Aserción: una pasada con un `~/.codex/config.toml` que ponga `sandbox_mode="danger-full-access"` sigue corriendo en `workspace-write` |
| **E-16** | El usuario tiene `~/.codex/rules/default.rules` con `allow` para `git push` | No afecta: es otra capa de configuración, no la del pack. Aserción con fixture |

#### Ejecución, topes y veredicto

| ID | Entrada | Esperado |
|---|---|---|
| **E-17** | El stream JSONL cambia de esquema y el contador de turnos deja de contar | La pasada sigue acotada por `timeout` (R7). Aserción: con un mock que emite JSONL de un esquema desconocido, `night_run_capped 2 999` sigue cortando a los 2 s |
| **E-18** | El CLI muere sin escribir el fichero de mensaje final | `unclear`; el sello de intento ya está escrito (heredado de FEAT-025 F-17); no se empuja nada |
| **E-19** | Mensaje final de 200 MB / con bytes NUL / no-UTF-8 | Se lee acotado (`head -c`), clasifica `unclear`, y el resumen inyectado sale limpio. El runner no se cuelga |
| **E-20** | `verdict: "pr"` pero sin commits en la rama | Gana el hecho, no el modelo: `aborted` motivo `no-commits` (F-19). El veredicto del modelo nunca decide si se empuja |
| **E-21** | `pr_url` apuntando a `https://evil.example/u/r/pull/1` o `github.com.evil.tld/x/pull/1` | `unclear`. Regex anclada al host, igual que FEAT-025 E-38 |
| **E-22** | El agente deja el árbol con conflictos o un rebase a medias | Aborta con motivo antes de empujar; no se hace `git push --force` en ningún camino |
| **E-23** | `gh` no autenticado en el momento de abrir la PR | Veredicto `aborted` motivo `gh-unauthenticated`, con la rama ya commiteada localmente y **el sello puesto**: no se reintenta mañana contra la misma spec |
| **E-24** | `git push` del runner rechazado por el remoto (rama ya existe) | Un solo intento, veredicto con motivo. Sin bucle de reintento: FEAT-025 §3 Never |
| **E-25** | `codex` no está en el `PATH` de la unidad de systemd | El gate lo detecta al armar (F-24) y el runner aborta con motivo. Es el fallo clásico de una unidad con `PATH` mínimo, y `codex` se instala vía npm global |
| **E-26** | Dos pasadas simultáneas, una por el timer y otra a mano | El lock de FEAT-025 (F-19) sigue cubriendo. Aserción de regresión, no lógica nueva |

---

### 4.3 Regresión — lo que no puede romperse

Derivado de la tabla "Archivos afectados" de §2. Todo lo que esta FEAT toca ya
tiene consumidores.

**`payload/lib/ai-cli.sh` (MODIFY — el fichero con más consumidores del payload)**

- [ ] `payload/test/wiring-smoke.sh` en verde para los **tres** CLIs.
- [ ] Las capacidades previas siguen intactas: `claude` conserva
      `hooks statusline remote-control` **y** `unattended`; `antigravity` sigue
      con la cadena vacía (`:183`).
- [ ] `ai_cli_has_capability <cli> <capacidad inexistente>` sigue devolviendo 1 en
      silencio, sin `die` (contrato de `:468-477`, del que depende
      `payload/wizard/40-scaffold.sh:174-177`).
- [ ] `ai_cli_launch_cmd`, `ai_cli_resolve`, `ai_cli_skills_dirs` y el rechazo del
      identificador retirado `gemini` no cambian.
- [ ] **Si T2 cambia la firma de `ai_cli_unattended_cmd`** (§2 punto 6, para
      añadir `<final-msg-file>`), hay **cuatro** call-sites en `main`, no uno:
      `payload/pack/night-shift/bin/biab-night-shift:303` y
      `payload/test/wiring-smoke.sh:153,161,172`. Migrarlos todos y verificar con
      `grep -rn 'ai_cli_unattended_cmd'` que no queda ninguno con la firma de
      cuatro argumentos.

**`payload/pack/night-shift/` (MODIFY — el pack entero es de FEAT-025)**

- [ ] Todo §4.1 de FEAT-025 sigue en verde en una caja Claude Code: modo
      fail-closed, sello de 14 días, árbol sucio, kill-switch, resumen de campos
      fijos, idempotencia del instalador.
- [ ] **El camino de Claude Code sí cambia de comportamiento** al meterle
      `night_run_capped`, y hay que decidir cómo. Hoy en `main` el runner invoca
      `bash -c "$cmd"` **sin envolver** (`bin/biab-night-shift:305`): el único
      reloj es `TimeoutStartSec=3600` de la unidad
      (`systemd/biab-night-shift.service.in`), y `NIGHT_TIMEOUT_SECONDS`
      (`lib.sh:85`) es una constante de display sincronizada a mano por
      comentario. Un `biab-night-shift run` lanzado a mano hoy no tiene tope
      alguno. T2 debe fijar: qué valor recibe `night_run_capped`, y cómo se
      relaciona con `TimeoutStartSec` (¿doble tope, cuál gana, quién es la fuente
      de verdad de los 3600?). Comparar contra una referencia capturada antes del
      cambio, sabiendo que el delta esperado no es cero.
- [ ] **`night_verdict_from_file` (§2) frente a `night_classify_result`**, que ya
      existe en `main` (`lib.sh:377-388`) y clasifica por texto. Convivirán: el
      camino de Claude Code sigue sin fichero de mensaje final. T2 debe decir si
      la nueva envuelve, sustituye o coexiste con la vieja, y §4.4 necesita al
      menos una mutación que cubra la que quede viva.
- [ ] El modo simulacro sigue sin invocar ningún CLI en **ninguna** de las dos
      cajas (F-03 de FEAT-025, con mocks de `claude`, `agy`, `codex` y `gh`).
- [ ] `pack_is_installed` sigue definida y `biab pack list` sigue reflejando el
      estado real.

**`payload/test/uninstall-contract.sh` (MODIFY)**

- [ ] Los casos vigentes siguen pasando, incluidos E-13 (path con espacio), E-15
      (teardown de pack que falla) y E-16 (todos los packs antes de `/opt`).
- [ ] `EXPECTED_ASSERTIONS` actualizado **a mano** al número real. Nunca "ajustar
      hasta que pase". Base de FEAT-025: `89`.
- [ ] El driver sigue negándose a correr como root.

**Codex del usuario**

- [ ] Una sesión interactiva `codex` del operador se comporta **exactamente
      igual** antes y después de instalar el pack: mismo `sandbox`, misma red,
      mismas reglas. Aserción: `codex doctor --summary` byte a byte igual
      (salvo rutas temporales) antes y después.
- [ ] `~/.codex/config.toml`, `~/.codex/rules/`, `~/.codex/hooks.json` y
      `~/.codex/auth.json` intactos (`sha256sum` antes/después).

**Empaquetado y CI**

- [ ] `git archive HEAD | tar -t` contiene `payload/pack/night-shift/codex/` —
      el fichero de reglas **debe** enviarse.
- [ ] `git archive HEAD | tar -t | grep -c '^specs/'` sigue en `0`
      (`.gitattributes:22`).
- [ ] `tools/check-no-personal-refs.sh` en verde: el fichero de reglas no puede
      arrastrar rutas `/home/jesus/…` del `default.rules` del mantenedor, que fue
      la fuente de sintaxis.
- [ ] El shellcheck de CI recoge los ejecutables sin extensión por shebang
      (`ci.yml:25-33`); verificar que los nuevos aparecen en la lista impresa.

---

### 4.4 Batería de mutaciones

Mismo arnés `mutate()` que FEAT-025 §4.4, con su guard de byte: si el `sed` no
cambia ni un byte el resultado es **"expresión obsoleta"** y el bloque **falla**.
No se redefine el arnés; estas 12 mutaciones se **añaden** a
`payload/pack/night-shift/tests/mutations.sh`.

Nomenclatura de "Estado de la expresión": *verificada* = ejecutada contra el
árbol actual y cambia bytes; *a verificar durante la implementación* = el fichero
todavía no existe y la expresión está escrita contra la forma que §2 propone.

| ID | Garantía atacada | Fichero | Expresión `sed` | Driver / aserción que debe fallar | Estado |
|---|---|---|---|---|---|
| **N-01** | La denegación es por verbo, no por destino | `payload/pack/night-shift/codex/night-shift.rules` | `s/pattern = \["git", "push"\]/pattern = ["git", "push", "origin", "main"]/` | `test-pack.sh` sección D — F-09: las tres evasiones (`HEAD:main`, `main:main`, `git -C`) pasan a `none`. **Es la mutación más importante de esta FEAT**: reproduce exactamente el error que el spike no detectó | a verificar durante la implementación |
| **N-02** | Los tests en línea del fichero de reglas | `…/night-shift.rules` | `/^\s*match = \[/,/^\s*\],/d` | `test-pack.sh` D — F-08 **no** basta (el fichero seguiría cargando); la aserción que debe fallar es la estática de A que cuenta que cada `prefix_rule` tiene `match`. Si sobrevive, es que nadie comprueba que los ejemplos existen | a verificar durante la implementación |
| **N-03** | No hay `allow` dentro de la jaula | `…/night-shift.rules` | `s/decision = "forbidden"/decision = "allow"/` (primera aparición) | `test-pack.sh` D — F-09 y la estática E-09 | a verificar durante la implementación |
| **N-04** | Sin agentes anidados | `…/night-shift.rules` | `/pattern = \["codex"\]/,+3d` | `test-pack.sh` D — F-09 caso `codex exec --ignore-rules hola` deja de ser `forbidden` | a verificar durante la implementación |
| **N-05** | **El veredicto se lee del JSON, no del exit code** | `payload/pack/night-shift/tests/test-pack.sh` | `s/jq -r "\.decision/true; jq -r "\.ignored/` | El propio driver: F-09 pasaría a leer un campo inexistente. Si el driver sigue verde, es que estaba leyendo el exit code, que sale `0` en los dos casos (F-11) | a verificar durante la implementación |
| **N-06** | Sandbox de escritura | `payload/lib/ai-cli.sh` | `s/--sandbox workspace-write/--sandbox danger-full-access/` | `wiring-smoke.sh` y F-05: el comando generado deja de llevar `workspace-write` | a verificar durante la implementación |
| **N-07** | Ninguna bandera peligrosa | `payload/lib/ai-cli.sh` | `s/codex exec/codex exec --ignore-rules/` | F-05: la aserción negativa sobre `--ignore-rules`. **Si sobrevive, es que las tres negativas se escribieron como un `grep -v` conjunto** en vez de como aserciones propias | a verificar durante la implementación |
| **N-08** | La red está apagada | `payload/pack/night-shift/codex/config.toml.in` | `s/network_access = false/network_access = true/` | `test-pack.sh` C — F-21(2): `codex doctor --summary` deja de decir `restricted network`. Verificado que ese resumen refleja el booleano sin gastar cuota | a verificar durante la implementación |
| **N-09** | El tope de tiempo | `payload/pack/night-shift/lib.sh` | `s/timeout -k [0-9]* "\$secs"/env/` | `test-pack.sh` B — F-13: el script de 30 s ya no termina en menos de 8 | a verificar durante la implementación |
| **N-10** | La guarda de rama protegida | `payload/pack/night-shift/lib.sh` | `s/^night_branch_is_safe() {/night_branch_is_safe() { return 0;/` | `test-pack.sh` B — F-18: la pasada empuja estando en `main` (el centinela de `git` aparece) | a verificar durante la implementación |
| **N-11** | La PR la abre el runner, no el agente | `payload/pack/night-shift/bin/biab-night-shift` | `/gh pr create/d` | `test-pack.sh` B — F-17: el centinela de `gh` queda vacío y el veredicto sigue diciendo `pr`. Cazar esto es lo que impide que la feature "funcione" sin abrir ninguna PR | a verificar durante la implementación |
| **N-12** | **El driver no puede pararse a mitad** | `payload/pack/night-shift/tests/test-pack.sh` | `0,/^echo "== Section D/{/^echo "== Section D/i\\exit 0\n}` | El propio `test-pack.sh`: el contador declarado no cuadra y el `trap EXIT` sale `1`. Sin contador esta mutación sobrevive, y con la sección D condicionada a que `codex` exista el riesgo es doble: hay que declarar **dos** valores esperados, uno por rama | a verificar durante la implementación |

**Criterio de salida de la batería:** 12 mutaciones aplicadas, 12 cazadas, 0
expresiones obsoletas. Un "obsoleta" es rojo, igual que un "sobrevivió". Se
ejecuta con el árbol limpio y se comprueba `git diff --quiet` al terminar.

---

### 4.5 Criterios de testing — comandos ejecutables

Todo corre **sin root, sin red y sin VM** salvo lo marcado. Los bloques 2 y 3
requieren `codex` en el `PATH` pero **no gastan cuota**: `execpolicy check` y
`doctor` son locales.

**Bloque 1 — sintaxis y estilo (lo que CI corre en cada PR)**

```bash
bash -n payload/lib/ai-cli.sh \
        payload/pack/night-shift/lib.sh \
        payload/pack/night-shift/bin/biab-night-shift \
        payload/pack/night-shift/install.sh \
        payload/pack/night-shift/uninstall.sh \
        payload/pack/night-shift/tests/test-pack.sh \
        payload/pack/night-shift/tests/mutations.sh
shellcheck -S warning payload/lib/ai-cli.sh \
        payload/pack/night-shift/lib.sh \
        payload/pack/night-shift/bin/biab-night-shift \
        payload/pack/night-shift/install.sh \
        payload/pack/night-shift/uninstall.sh
jq -e . payload/pack/night-shift/codex/verdict.schema.json >/dev/null
bash tools/check-no-personal-refs.sh
```

**Bloque 2 — el fichero de reglas (F-08…F-12)**

```bash
R=payload/pack/night-shift/codex/night-shift.rules
command -v codex >/dev/null || { echo "SKIP: codex no está en el PATH — la sección D no se ejecuta"; exit 0; }

# F-08: cargar el fichero ejecuta sus match/not_match en línea.
codex execpolicy check --rules "$R" -- echo hi >/dev/null \
  || { echo "FAIL: el fichero de reglas no carga (sintaxis o ejemplo en línea)"; exit 1; }

# F-09: las ocho formas prohibidas. Las cuatro primeras son las evasiones medidas.
for c in "git push origin main" "git push origin HEAD:main" "git push origin main:main" \
         "git -C /r push origin main" "gh pr merge 7 --squash" "gh release create v1" \
         "sudo tee /etc/x" "codex exec --ignore-rules hola"; do
    d=$(codex execpolicy check --rules "$R" -- $c | jq -r '.decision // "none"')
    [ "$d" = forbidden ] || { echo "FAIL: [$c] => $d (esperado forbidden)"; exit 1; }
done

# F-10: el trabajo normal pasa.
for c in "git commit -m x" "git checkout -b feat/x" "npm test" "pytest -q" "echo hola"; do
    d=$(codex execpolicy check --rules "$R" -- $c | jq -r '.decision // "none"')
    [ "$d" = none ] || { echo "FAIL: comando legítimo bloqueado: [$c] => $d"; exit 1; }
done

# F-11: dejar constancia de que el exit code NO sirve como veredicto.
codex execpolicy check --rules "$R" -- gh pr merge 4 >/dev/null 2>&1; a=$?
codex execpolicy check --rules "$R" -- echo hola     >/dev/null 2>&1; b=$?
[ "$a" -eq 0 ] && [ "$b" -eq 0 ] \
  || { echo "FAIL: el exit code ya no es 0 en ambos casos — revisar si algún test empezó a fiarse de él"; exit 1; }
echo "rules OK"
```

**Bloque 3 — sandbox efectivo, sin gastar cuota (F-21 parte 2, N-08)**

```bash
CH=$(mktemp -d -p "${XDG_STATE_HOME:-$HOME/.local/state}")   # NO en /tmp: E-10
trap 'rm -rf "$CH"' EXIT
mkdir -p "$CH/rules"
cp payload/pack/night-shift/codex/night-shift.rules "$CH/rules/"
BIB_USER="$(id -un)" envsubst '${BIB_USER}' \
    < payload/pack/night-shift/codex/config.toml.in > "$CH/config.toml"
CODEX_HOME="$CH" codex doctor --summary 2>/dev/null \
    | grep -q 'restricted fs + restricted network' \
    || { echo "FAIL: el sandbox del pack no está restringido en fs y red"; exit 1; }
echo "sandbox OK"
```

**Bloque 4 — topes y guardas, funciones puras (F-13…F-19, F-22)**

```bash
bash payload/pack/night-shift/tests/test-pack.sh   # imprime su contador y debe cuadrar
```

**Bloque 5 — suites completas (regresión)**

```bash
for c in claude antigravity codex; do BIB_AI_CLI=$c bash payload/test/wiring-smoke.sh || exit 1; done
bash payload/hooks/tests/run-tests.sh
bash payload/test/uninstall-contract.sh          # contador cuadrado, base 89 + los CX-*
bash payload/pack/browser/tests/test-pack.sh
grep -rn 'ai_cli_unattended_cmd' payload/ | grep -v 'ai-cli.sh'   # revisar firma una a una
```

**Bloque 6 — batería de mutaciones (§4.4)**

```bash
git diff --quiet || { echo "árbol sucio — el arnés restaura ficheros, córrelo limpio"; exit 1; }
bash payload/pack/night-shift/tests/mutations.sh   # 12/12 cazadas, 0 expresiones obsoletas
git diff --quiet || { echo "FAIL: el arnés dejó el árbol modificado"; exit 1; }
```

**Bloque 7 — solo caja real (pasada manual; F-01, F-20, F-21 gastan cuota)**

```bash
# F-01 primero: si falla, no se sigue.
CH=/var/lib/buildersinabox/night-shift/guard/codex-home
before=$(stat -c %i "$HOME/.codex/auth.json")
CODEX_HOME="$CH" codex doctor --summary | grep -i '^\s*.\s*auth'
# …pasada real por el camino del pack…
test -L "$CH/auth.json" && [ "$(stat -c %i "$HOME/.codex/auth.json")" = "$before" ] \
  && echo "F-01 OK: sesión conservada y credencial del operador intacta"
# F-02: la jaula no se afloja desde el operador.
rm -f "$CH/config.toml" 2>&1 | grep -q 'Permission denied' && echo "F-02 OK"
# F-20: la denegación efectiva. Ver los pasos completos en §4.1.
gh pr view "$N" --json state -q .state     # debe seguir OPEN
```

---

### 4.6 Casos nuevos en `payload/test/uninstall-contract.sh`

Nomenclatura `CX` ("codex"), siguiendo el patrón `NS` que FEAT-025 §4.6
introduce. Se siembra en el sandbox, antes de cada `run_uninstall`, lo que el
camino de Codex deja:

```
$BIB_STATE_DIR/night-shift/guard/codex-home/config.toml
$BIB_STATE_DIR/night-shift/guard/codex-home/rules/night-shift.rules
$BIB_STATE_DIR/night-shift/guard/codex-home/auth.json         (symlink a un fichero de fixture)
$SC/home/<op>/.codex/auth.json                          (el "fichero del operador", fixture)
$SC/home/<op>/.codex/config.toml                         (fixture, NO nuestro)
$SC/etc/codex/requirements.toml                          (fixture ajeno, NO nuestro)
```

| ID | Aserción | Por qué |
|---|---|---|
| **CX-1** | El árbol `night-shift/guard/codex-home/` no existe tras `run_uninstall` | Es la ruta nueva; el TODO de `uninstall-contract.sh:26-30` avisa de que una ruta nueva no lleva aserción automática |
| **CX-2** | `$SC/home/<op>/.codex/auth.json` **existe y es byte a byte idéntico** (`cmp` contra la copia de referencia) tras el desinstalado | La credencial del usuario no es nuestra. Es el caso que convierte el `Never` de §3 en algo que un test puede fallar |
| **CX-3** | `$SC/home/<op>/.codex/config.toml` sobrevive intacto | Ídem con la configuración interactiva |
| **CX-4** | `$SC/etc/codex/requirements.toml` sobrevive intacto **cuando el pack no lo creó** | Misma clase de defecto que #42 (drop-ins de sshd) y que NS-9 de FEAT-025: "solo tocar lo nuestro". Si la salida (a) de §1 llega a tomarse, este caso se desdobla en "si lo creamos, quitamos solo nuestro bloque marcado" |
| **CX-5** | Un segundo `run_uninstall` sale `rc=0` y no imprime `removing` para ninguna ruta de Codex | Idempotencia, misma propiedad que el resto del contrato |

**Contador.** 5 aserciones nuevas ⇒ `EXPECTED_ASSERTIONS` pasa de **89** (el
valor que deja FEAT-025) a **94**. Si la implementación añade o quita casos, el
número final es el que cuadre — **actualizado a mano, nunca subido hasta que el
driver deje de quejarse**.

---

### 4.7 Lo que este QA **no** cubre, y lo que necesita decisión

**No cubierto por ningún test automático (solo pasada manual):**

1. **Que un `CODEX_HOME` root-owned conserve la sesión y sobreviva a un refresco
   de token** (F-01). Es la pregunta que decide el diseño y no hay forma de
   contestarla sin una caja logueada. Está medido que un `CODEX_HOME` nuevo y
   vacío **sí** desautentica, así que el riesgo está confirmado; lo que falta es
   saber si el symlink lo salva.
2. **Que el runtime deniegue de verdad** (F-20), incluida la forma `bash -lc`
   que `execpolicy check` no simula. Gasta cuota. Es la garantía de la que
   cuelga la FEAT.
3. **Que el agente sin red aborte limpio** en una spec que necesita instalar
   dependencias (F-21 parte 1). Depende de qué spec tenga el usuario delante;
   queda para §6 Feedback tras la primera semana.
4. **El comportamiento con la cuota de OpenAI agotada a mitad de pasada.**
   Depende de la cuenta y del momento.

**Cosas de §1/§2/§3 que no son testeables tal como están escritas, y qué asumo:**

- ~~**La firma nueva de `ai_cli_unattended_cmd` (§2 punto 6) contradice la que
  FEAT-025 T1 ya especifica.**~~ **Resuelto el 2026-08-17:** FEAT-025 se mergeó
  (PR #54) con la firma opaca de cuatro argumentos, que es justo lo que esta FEAT
  pedía. Ya no hay ventana de pack roto en `main` ni dependencia de orden de
  merge. Lo que queda vivo del punto: los **tres call-sites** de
  `payload/test/wiring-smoke.sh:153,161,172` se rompen si T2 cambia la firma para
  añadir `<final-msg-file>` — §4.3 los recoge como regresión.
- **§2 dice "las mismas seis garantías" pero una no se puede dar igual.** En
  Claude Code el guard es un hook que ve la orden entera; en Codex es una lista
  de prefijos que sabemos evadible (E-02, E-03, E-04). §2 lo compensa quitándole
  al agente la red y el `gh`, y estoy de acuerdo en que el resultado global es
  **más** fuerte, no menos. Pero el README no puede decir "misma garantía": debe
  decir *"the Codex agent has no network and cannot push"*, que es lo que es
  cierto y además suena mejor. Lo recojo en §5 y lo señalo aquí para que nadie
  escriba "paridad" en el copy.
- **La sección D depende de que `codex` esté en el `PATH` de CI.** Si no lo está,
  F-08…F-12 no corren nunca y nos enteramos en la caja de un usuario. Necesito
  una decisión: (a) CI instala `codex` para el job del pack, (b) el `skip` es
  aceptable pero el driver **falla** si detecta que lleva N ejecuciones sin
  ejecutar la sección D. **Sin decisión escribo (b) con aviso ruidoso**, porque
  un `skip` silencioso es un pase falso y esta casa ya se ha llevado ese susto.
- **`--output-schema` no garantiza que el modelo lo respete.** La documentación
  lo describe como el esquema de la forma del mensaje final, no como una
  validación dura. Asumo en F-22 que un mensaje que no valide es `unclear`, y
  que el runner **nunca** empuja basándose en el veredicto del modelo, solo en
  hechos del repositorio (hay commits, la rama no es protegida). Si §2 quisiera
  fiarse del veredicto, habría que reabrirlo.
- **El esquema del stream JSONL de `codex exec --json` no está documentado** en el
  manual vendido. Verifiqué que los nombres que el spike da (`turn.completed`,
  `turn.failed`) **no** aparecen como cadenas exactas en el binario, y el
  protocolo del app-server usa la forma con barra (`turn/completed`). No sé cuál
  emite `codex exec`. El contador de turnos de `night_run_capped` no puede
  hardcodear un nombre sin comprobarlo en una pasada real; por eso E-17 exige que
  un esquema desconocido no rompa el tope de tiempo.

---

## 5. Docs

Acciones post-merge. Ninguna es opcional: dos de ellas son la única forma de que
un usuario se entere de una limitación real antes de tropezar con ella.

- [ ] **`README.md` — tabla de capacidades por CLI en el turno de noche.** Tres
      filas (`claude`, `codex`, `agy`), columnas "modo simulacro" / "modo real" /
      "red del agente". Con `agy` en "nunca" y el motivo en una nota.
- [ ] **`README.md` — la frase que no puede faltar:** en una caja Codex el agente
      trabaja **sin red** y **no puede empujar**; la pull request la abre la caja.
      Redactado como ventaja (que lo es) y no como disculpa, pero sin omitir que
      una spec que necesite instalar dependencias abortará.
- [ ] **Salida de `biab pack add night-shift`** — el bloque de capacidades de la
      caja concreta (F-23). Es documentación en el sitio donde se lee.
- [ ] **`CHANGELOG.md`** — entrada de la versión: "night shift now runs on Codex".
- [ ] **Comentario de cabecera en `night-shift.rules`** explicando por qué las
      reglas se escriben contra el verbo y no contra el destino, con las cuatro
      evasiones medidas listadas. Sin ese comentario, el primer contribuidor que
      "mejore" la regla estrechándola reabrirá el agujero. Es el mismo tipo de
      comentario-cicatriz que `payload/test/uninstall-contract.sh:36-40`.
- [ ] **Nota en `payload/pack/night-shift/` con la versión de Codex de
      referencia** (0.147.0) y el aviso de que `execpolicy` está marcado
      experimental y el CLI se instala sin pin (`42-codex-cli.sh:14`).
- [ ] **`payload/skills/extend-yourself/SKILL.md`** — si FEAT-025 lo actualizó
      para dejar de decir "(none bundled)", revisar que la redacción no promete
      paridad entre CLIs.
- [ ] **TODO con fecha** en el fichero de configuración del pack: el filtrado de
      red por dominios (`features.network_proxy` + `[permissions.*.network.domains]`)
      queda pendiente hasta que el flag deje de ser experimental.

---

## 6. Feedback

> Vacío hasta después del deploy.
