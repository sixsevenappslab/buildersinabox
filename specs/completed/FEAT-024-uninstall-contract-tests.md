# FEAT-024: Automated coverage for the install/uninstall ownership contract

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta
- **Complejidad:** media
- **Presupuesto de ejecucion:** max_turns=120 timeout=3600
- **E2E mode:** none
  > The logic under test is shell decision-making. It is exercised by mocking and
  > path redirection, exactly like the existing FEAT-014 unit driver — no runtime
  > UI or endpoint to drive.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** completada
- **Creado:** 2026-08-15
- **Actualizado:** 2026-08-15 (implementada, PR #52)
- **Validado por Jesus:** [x] 2026-08-15

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
- [x] Investigacion previa rellenada con rutas reales verificadas — completada:
      todas las rutas y líneas citadas verificadas con `grep -n`, y el diseño
      prototipado sobre una copia scratch del payload
- [x] Tabla "Archivos afectados" completa (7 ficheros)
- [x] Minimo 1 `<task>` con `<verify>` ejecutable y `<done>` observable (6 tareas)
- [x] Patron de codigo con fragmento real del proyecto
- [x] Criterios de aceptacion globales verificables
- [x] Presupuesto de ejecucion revisado — `max_turns=120 timeout=3600` se mantiene

### QA (§4) — owner Pablo
- [x] Minimo 1 caso funcional con pasos numerados — 37 casos (QA-01..QA-37) en
      7 bloques, con trazabilidad a la semilla manual del 2026-08-14
- [x] Minimo 1 edge case — 17 (E-01..E-17)
- [x] Minimo 1 item de regresion — 12 items, incluidas las suites existentes
      que T1 puede romper
- [x] Bloque `Criterios de testing` con comandos ejecutables — 6 bloques + la
      bateria de mutaciones del bloque F
- [x] Cobertura negativa: 8 mutaciones (QA-29..QA-36) que deben poner el driver
      en rojo, una de ellas contra el propio driver

### Growth (§1.Growth Notes) — owner Andrea
- [x] N/A — internal engineering quality, no growth surface.

> **DoR completa.** §1, §2, §3 y §4 rellenados. §2 corrió una ronda de
> reconciliación tras QA: §4 detectó que la costura `BIB_PROMPT_INPUT` no era
> inerte en producción, que `_bib_read_line _ack` sin `|| true` mataría el abort
> antes de imprimir su mensaje, y que el `<verify>` de mutación de T4 era
> vacuamente verde (su estado de salida era el del `git checkout` final, así que
> anunciaba MUTATION-CAUGHT aunque el driver fuese ciego — verificado). Los tres
> están corregidos arriba.
>
> **Validada por Jesus el 2026-08-15** y promovida a `active/`. Lista para
> implementar: Wave 1 (T1→T2) es secuencial, Wave 2 (T3, luego T4 y T5 en
> paralelo), Wave 3 (T6).

---

## 1. Requisitos (Elena)

### Problema

On 2026-08-14 a pre-launch audit of the install paths found six defects. Three
were behavioural bugs in code that runs as root on other people's machines, and
each one damaged something the user owned:

- `--uninstall` left `/etc/ssh/sshd_config.d/00-buildersinabox.conf` behind, so a
  box kept `PasswordAuthentication yes` forced ahead of the user's own hardening
  **after they believed they had removed us**.
- The wizard replaced the user's account password with no check and no prompt.
- The installer overwrote `/usr/local/bin/bd`, and `--uninstall` then deleted it —
  losing an unrelated script of theirs on the way in and again on the way out.

None of the three was caught by CI. They were found by reading the code. The
fixes for them then introduced three *more* bugs of the same class, each caught
only because a reviewer read the fix: a gate that would have shipped a flashed
gift box with a password that is public in this repo, an ownership check with no
migration path that would have frozen `bd` updates forever, and a "nothing was
changed" abort message printed after a system user had already been deleted.

The common shape: **the install/uninstall contract — "only touch what is ours,
and put back what we changed" — is asserted nowhere.** `dryrun.sh` and
`wiring-smoke.sh` never execute the wizard; `bash -n` checks syntax; `shellcheck`
checks style. The only real verification today is a human running commands on a
throwaway VM by hand, which is slow, unrepeatable, and was itself the source of
two VM lockouts during this audit.

### Intent (why)

The repo is about to be made public and the product installs itself as root on
machines its authors will never see. The failure modes above are not cosmetic:
one of them can leave a headless box unreachable, and another silently deletes a
file the user wrote. A stranger hitting one of these on day one is the difference
between a launch and a retraction — and unlike a normal OSS bug, they cannot
`git revert` their SSH access back.

The cost is low and the pattern is already proven in-repo: `payload/test/ssh-finalize-decision.sh`
tests exactly this class of root-only sshd logic **without root and without a VM**,
by mocking through `PATH` and sourcing the script as a library. Reusing that
approach is a day of work, not a project. Doing it now also converts the manual
VM checks done during this audit into something that runs on every PR.

### Solucion propuesta

A unit driver, `payload/test/uninstall-contract.sh`, that runs on a plain CI
runner and asserts the ownership contract for every file the installer claims,
using the FEAT-014 driver as its template: mocked `systemctl`/`apparmor_parser`,
`$BIB_*` paths redirected into temp dirs, no root, no network, no VM.

Each asserted case is one that a human found by hand during the 2026-08-14 audit.
The point is that they stop being things a human has to remember to check.

### Historias de usuario

- Como usuario que ejecuta `--uninstall`, quiero que la máquina quede como estaba
  antes de instalar, para no descubrir semanas después que sigue con la
  autenticación por contraseña forzada o sin un script mío que borré sin saberlo.
- Como mantenedor que abre una PR sobre el instalador, quiero que CI falle si
  rompo el contrato de propiedad, para no depender de que alguien lea el diff con
  suficiente atención.

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** The test driver shall run without root, without network access
      and without a VM, on a stock GitHub Actions runner.
- [ ] **Event-driven:** When `do_uninstall` runs, the driver shall assert that
      every BIAB-owned path listed in the install contract is removed, including
      `00-buildersinabox.conf`.
- [ ] **Event-driven:** When a file at a BIAB-claimed path does not carry the
      ownership marker, the driver shall assert it is left byte-identical by both
      install and uninstall.
- [ ] **State-driven:** While a claimed path holds a copy predating the ownership
      marker, the driver shall assert it is still recognised as ours and upgraded
      rather than abandoned.
- [ ] **Unwanted:** If the uninstall guard is declined, then the driver shall
      assert no destructive step ran — including the opt-in pack teardown, which
      executes before the removal loop.
- [ ] **Unwanted:** If the target account holds no usable SSH key, then the driver
      shall assert the uninstall warns before removing the drop-in that provides
      password auth.
- [ ] CI shall run the driver as a required check on every PR `[free-form]` —
      a workflow wiring statement, not system behaviour.

### Requisitos no funcionales

- [ ] Runtime under ~30s, so it is added to the existing `lint` job rather than
      becoming a new one.
- [ ] Zero new dependencies — bash, coreutils and the mocking approach already
      used by `ssh-finalize-decision.sh`.
- [ ] The driver must never touch the host's real `/etc`, `/usr/local/bin` or
      `~/.ssh`. Two multipass VMs were locked out during the manual audit by a
      test writing to `~ubuntu/.ssh/authorized_keys`; the automated version must
      make that impossible by construction, not by care.

### Referencias visuales

- N/A — no UI.

### Growth Notes (Andrea)

- N/A.

---

## 2. Spec Tecnica (Laura)

### Investigacion previa

Leído entero `payload/install.sh` (564 líneas, versión mergeada de #42 + #44 +
#41), `payload/wizard/35-ssh-finalize.sh` (592), `payload/test/ssh-finalize-decision.sh`
(406), `payload/lib/common.sh` (310), `payload/lib/prompt.sh`,
`payload/install/06-bd-cli.sh`, `payload/install/42-codex-cli.sh` y
`.github/workflows/ci.yml`. Todas las rutas verificadas con `ls`/`grep -n`; el
diseño de abajo está **prototipado y ejecutado** en una copia scratch del
payload (23 aserciones en verde, 0,22 s, sin root — ver "Riesgos" R0).

- **Patron existente a copiar:** `payload/test/ssh-finalize-decision.sh`. Mockea
  `ss`, `tailscale`, `sshd` y `systemctl` vía `PATH` (líneas 30-100), redirige
  state file y dir de drop-ins a temp dirs (105-113), sourcea
  `35-ssh-finalize.sh` como librería con `BIB_SSH_FINALIZE_LIB=1` y el guard
  vive al final del script sourceado (`35-ssh-finalize.sh:587-592`). No toca
  sshd real, no necesita root.
- **La sourceabilidad NO es el bloqueo principal — las rutas sí.** Las notas
  preliminares planteaban "guard `BIB_INSTALL_LIB=1` **o** extraer la lógica a
  `lib/common.sh`". Ninguna de las dos basta: `35-ssh-finalize.sh` ya nacía
  testeable porque **todo lo que escribe pasa por variables redirigibles**
  (`SSHD_DROPIN_DIR="${BIB_SSHD_DROPIN_DIR:-/etc/ssh/sshd_config.d}"` en
  `35-ssh-finalize.sh:81`, y `BIB_SSH_SERVICE_DROPIN_DIR` en :97).
  `do_uninstall` **no tiene ninguna**: escribe/borra 12 rutas absolutas
  literales repartidas en ~15 sitios (`install.sh:144, 176, 190-210, 221,
  238-242, 255, 264`; el `00-…conf` aparece dos veces —:144 y :203— y `bwrap`
  en cuatro). Sin una
  costura de rutas, sourcear `do_uninstall` y llamarlo en un runner significa
  ejecutar `rm -rf` contra el `/etc` real. Hacen falta **tres costuras**, no
  una (ver "Decision de diseño").
- **La `read` del guard SSH bloquea el requisito EARS de "abort".**
  `install.sh:157` condiciona el prompt a `-r /dev/tty`, que en un runner de
  GitHub es falso: el camino de abort **nunca se ejecutaría** en CI y el
  requisito §1 "Unwanted: si el guard se declina…" quedaría sin cubrir. El repo
  ya tiene el knob para esto y no está usado aquí: `BIB_PROMPT_INPUT`
  (`lib/prompt.sh:11`, helper `_bib_read_line` en :44) que `payload/test/dryrun.sh:28`
  ya explota. `install.sh` sourcea `lib/prompt.sh` en :29, así que la función
  está disponible dentro de `do_uninstall` sin añadir dependencias.
- **Duplicación de predicados de propiedad — son tres, no una:**
  1. `_authorized_keys_present()` (`35-ssh-finalize.sh:151-155`, usado en :532)
     y su regex copiada inline en `install.sh:149`.
  2. `bd_is_ours()` (`install/06-bd-cli.sh:31-35`, lado install) y el mismo
     predicado escrito como regex `'Installed by Builders in a Box|brain-dump capture CLI'`
     en `install.sh:224` (lado uninstall). **Este par es el que importa**: si
     divergen reaparece exactamente el bug de #44 (el instalador respeta un
     fichero que el desinstalador borra, o al revés).
  3. El marcador de autologin `'Builders in a Box — autologin'`
     (`install.sh:225`) contra la primera línea de
     `payload/systemd/getty@tty1.service.d/autologin.conf.in`.
- **`42-codex-cli.sh` usa un marcador más largo** (`BWRAP_PROFILE_MARKER`,
  :34) que *contiene* la cadena genérica que grepea `install.sh:239`. Funciona
  hoy por inclusión de substring, no por contrato. Se cubre con una aserción
  estática en el driver en vez de refactorizar el instalador.
- **Nadie sourcea `install.sh`.** Verificado (`grep -rn "install.sh"` sobre
  `installer/`, `payload/`, `tools/`, `.github/`): todos los consumidores lo
  *ejecutan* (`installer/web/install.sh:84`, `install/05-biab-command.sh:34,189`,
  `profile.d/biab-firstboot.sh:37-42`, `test/dryrun.sh:40`). El guard de
  librería no tiene consumidores previos que romper.
- **Wiring de CI:** step nuevo en el job `lint`, junto a
  `.github/workflows/ci.yml:53-54`. `ubuntu-latest` trae bash 5, coreutils, jq
  y `sshd`/`ssh-keygen` (el escenario `sshd -T` real de FEAT-014 corre allí).
- **Dependencias:** ninguna nueva.

### Decision de diseño: las tres costuras de `do_uninstall`

Copiamos el patrón de FEAT-014 (variables redirigibles + guard de librería),
**no** inventamos uno nuevo. Tres costuras, todas no-op en una máquina real:

| # | Costura | Dónde | Por qué |
|---|---------|-------|---------|
| 1 | `BIB_INSTALL_LIB=1` | `install.sh` — condición del `while` de parseo (:70) + `return` tras el entry point de uninstall (:310-312) | Permite sourcear el fichero: define `do_uninstall` sin ejecutar instalador ni wizard |
| 2 | `BIB_UNINSTALL_ROOT` | prefijo de las 12 rutas absolutas de `do_uninstall` (~15 sitios) | Redirige todo lo que se borra a un `mktemp -d`. Vacío por defecto ⇒ comportamiento byte-idéntico en producción |
| 3 | `BIB_PROMPT_INPUT`, **condicionado a modo librería** | `install.sh:157,160` — `-r "$_uninst_prompt_src"` + `_bib_read_line _ack \|\| true` | Knob **ya existente** (`lib/prompt.sh:11`); hace testeable el camino de abort del guard SSH |

> **Corrección tras QA (§4, QA-26/QA-27).** La costura 3 salió de §2 con dos
> defectos que §4 detectó y que quedan cerrados aquí:
>
> - **No era inerte en producción**, al contrario de lo que afirma §3 *Always*.
>   Leer `-r "$BIB_PROMPT_INPUT"` a secas hace que cualquiera que exporte la
>   variable (y `payload/test/dryrun.sh:28` ya la exporta) cambie el guard de
>   "avisar y continuar" a **abortar con rc=1** en un uninstall real. Se
>   resuelve igual que la costura 2 — se honra solo en modo librería:
>   `_uninst_prompt_src="/dev/tty"; [[ "${BIB_INSTALL_LIB:-0}" == "1" ]] && _uninst_prompt_src="${BIB_PROMPT_INPUT:-/dev/tty}"`.
> - **`_bib_read_line _ack` sin `|| true` mata `do_uninstall`.** La función
>   devuelve no-cero con EOF y línea vacía (verificado), y `install.sh:21`
>   declara `set -e`, así que el abort moriría **antes** de imprimir
>   `uninstall: aborted, nothing was changed.` — el mismo defecto de "mensaje
>   que miente" que el review de #42 ya corrigió una vez. El código actual
>   (`read -r _ack < /dev/tty || true`) sí lo tiene; la sustitución debe
>   conservarlo.

Detalles que el implementador no puede improvisar (todos comprobados en el
prototipo):

- **El guard de arranque va en la condición del `while`, no envolviéndolo.**
  Al sourcear, `$@` es el del *llamante*, así que el `case *)` mataría el driver
  con `unknown argument`. Se resuelve con
  `while [[ "${BIB_INSTALL_LIB:-0}" != "1" && $# -gt 0 ]]; do` — una línea, cero
  reindentado. El bloque de validación `--non-interactive` (:109-116) **no
  necesita guard**: sin parseo, `NON_INTERACTIVE` se queda en 0 y no entra.
- **El guard de cola es un `return`, no un `if` de 250 líneas.** `return 0` en
  el top-level de un fichero sourceado corta el sourcing ahí mismo; todo lo que
  hay debajo (selftest, preflight, stack, wizard) ni se ejecuta. Se escribe
  `return 0 2>/dev/null || exit 0` para que ejecutar `install.sh` con
  `BIB_INSTALL_LIB=1` exportado por accidente pare limpio en vez de reventar
  bajo `set -e`.
- **`BIB_UNINSTALL_ROOT` solo se honra en modo librería**
  (`[[ "${BIB_INSTALL_LIB:-0}" == "1" ]] && BIB_UNINSTALL_ROOT="${BIB_UNINSTALL_ROOT_TEST:-}"`).
  Una variable de entorno perdida no puede desviar un uninstall real.
- **Tres sitios que un `sed` ingenuo rompe** (fallaron en el prototipo antes de
  corregirlos). Los dos literales `/etc/systemd/system/ssh.service.d` NO son la
  misma cosa: el de **`install.sh:255`** está dentro de un **patrón** de
  `[[ == ]]`, no de una ruta — si no se prefija, `removed_ssh_dropin` se queda
  a 0 y no se recarga systemd; el de **`:264`** sí es una ruta real (el
  `rmdir`) y también se prefija. Y `_autologin_out`/`_firstboot_trigger`
  (:464,:471) son del camino de **install**, NO se prefijan.
- **`require_root` se neutraliza desde el driver** (`require_root() { :; }`
  tras el `source`), igual que el driver de FEAT-014 reasigna globals tras
  sourcear. No se toca `common.sh` para esto.
- **`do_uninstall` termina en `exit`**, así que el driver lo invoca en subshell
  con captura: `OUT="$(do_uninstall 2>&1)" || rc=$?`. Esto además permite
  asertar el `exit 1` del abort.
- **`getent` se mockea vía `PATH`** (devuelve un home dentro del sandbox): es
  lo único que resuelve el home del usuario objetivo, tanto en el guard SSH
  (:147) como en el barrido de `~/.bashrc.d/biab-*` (:284-296).

### Alcance

#### Incluye

- El driver `payload/test/uninstall-contract.sh` y su wiring en CI.
- Las tres costuras de `payload/install.sh` descritas arriba.
- Una definición única de los predicados de propiedad en `payload/lib/common.sh`,
  consumida por `do_uninstall`, `35-ssh-finalize.sh` y `install/06-bd-cli.sh`.

#### NO incluye (OBLIGATORIO)

- **No arreglar bugs.** Las PRs #41–#44 ya los arreglan; esta FEAT solo los
  convierte en aserciones. Si el driver descubre uno nuevo, se abre otra FEAT.
- **No testear el wizard completo** (`01-set-password`, `40-scaffold`, OAuth).
  Es tentador y es un epic. Esta FEAT cubre solo el contrato de propiedad de
  install/uninstall.
- **No sustituir la pasada manual en hardware.** El driver no valida el efecto
  sobre el listener vivo, igual que declara `ssh-finalize-decision.sh`.
- **No refactorizar** `do_uninstall` más allá de las tres costuras: cero
  cambios de orden, de mensajes o de lógica de decisión.
- **No ejecutar los scripts de `payload/install/*` de verdad** (son root-only y
  con destinos hardcoded). El lado install se cubre a nivel de **predicado
  compartido**, no ejecutando el instalador — ver R3.
- **No añadir un job nuevo a CI** (Boundaries §3): un step en `lint`.

### Archivos afectados

| Archivo | Accion | Cambio |
|---------|--------|--------|
| `payload/test/uninstall-contract.sh` | CREAR | El driver (~350 líneas, estilo FEAT-014) |
| `payload/install.sh` | MODIFICAR | 3 costuras: `BIB_INSTALL_LIB` (:70, :312), `BIB_UNINSTALL_ROOT` (11 rutas de `do_uninstall`), `BIB_PROMPT_INPUT` (:157,:160) |
| `payload/lib/common.sh` | MODIFICAR | `bib_authorized_keys_present`, `bib_path_is_ours` + constantes de marcador |
| `payload/wizard/35-ssh-finalize.sh` | MODIFICAR | `_authorized_keys_present` pasa a delegar/desaparecer (call site :532) |
| `payload/install/06-bd-cli.sh` | MODIFICAR | `bd_is_ours` delega en `bib_path_is_ours` con el patrón compartido |
| `.github/workflows/ci.yml` | MODIFICAR | Un step en el job `lint`, tras el de FEAT-014 (:53-54) |
| `CONTRIBUTING.md` | MODIFICAR | Una línea: cómo correr el driver en local (§5 Docs) |

### Dependencias

Ninguna nueva. Bash 5, coreutils, `jq` (ya lo usa `lib/common.sh` y ya está en
`ubuntu-latest`), y opcionalmente `sshd`/`ssh-keygen` para la aserción de
precedencia real, que **se salta limpiamente** si no existen (igual que
`ssh-finalize-decision.sh:290-321`).

### Tareas

**Wave 1 — las costuras (secuencial: T2 depende de T1)**

<task id="T1">
  <files>payload/lib/common.sh, payload/wizard/35-ssh-finalize.sh, payload/install/06-bd-cli.sh, payload/install.sh</files>
  <action>Definir en common.sh una sola vez: `BIB_OWNERSHIP_MARKER='Installed by Builders in a Box'`, `BIB_BD_OWNERSHIP_PATTERN` (marcador + `brain-dump capture CLI`, la ruta de migración de #44), `BIB_AUTOLOGIN_OWNERSHIP_PATTERN='Builders in a Box — autologin'`, `bib_path_is_ours <file> <pattern>` (grep -Eq, silencioso) y `bib_authorized_keys_present <file>` (movida tal cual desde 35-ssh-finalize.sh:151-155). Actualizar los tres consumidores: 35-ssh-finalize.sh:532, 06-bd-cli.sh:31-41 y el guard/`case` de install.sh:149,224-225. Semántica idéntica — es una deduplicación, no un cambio de criterio.</action>
  <verify>bash -n payload/lib/common.sh payload/install.sh payload/wizard/35-ssh-finalize.sh payload/install/06-bd-cli.sh && shellcheck -S warning payload/lib/common.sh payload/install.sh payload/wizard/35-ssh-finalize.sh payload/install/06-bd-cli.sh && bash payload/test/ssh-finalize-decision.sh && bash -c 'source payload/lib/common.sh; t=$(mktemp); printf "#!/bin/sh\n# brain-dump capture CLI\n" > "$t"; bib_path_is_ours "$t" "$BIB_BD_OWNERSHIP_PATTERN" && printf "# I love Builders in a Box\n" > "$t" && ! bib_path_is_ours "$t" "$BIB_BD_OWNERSHIP_PATTERN" && echo T1-OK'</verify>
  <done>Una sola definición de cada predicado; `grep -c 'brain-dump capture CLI' payload/install.sh payload/install/06-bd-cli.sh` deja de devolver 1 en ambos; FEAT-014 sigue verde.</done>
</task>

<task id="T2">
  <files>payload/install.sh</files>
  <action>Aplicar las tres costuras de la tabla de "Decision de diseño": (a) condición del `while` de parseo + `return 0 2>/dev/null || exit 0` justo tras el bloque `if [[ "$UNINSTALL_MODE" -eq 1 ]]`; (b) `BIB_UNINSTALL_ROOT` declarado junto a los demás defaults y honrado SOLO con `BIB_INSTALL_LIB=1`, prefijando las 11 rutas absolutas de `do_uninstall` — incluidos el patrón de `[[ == ]]` de :255 y el `rmdir` de :264, y EXCLUIDOS `_autologin_out`/`_firstboot_trigger` (:464,:471, camino de install); (c) `-r "$BIB_PROMPT_INPUT"` + `_bib_read_line _ack` en el prompt del guard. Comentario en cada costura explicando que existe para `payload/test/uninstall-contract.sh`.</action>
  <verify>bash -n payload/install.sh && shellcheck -S warning payload/install.sh && bash payload/install.sh --help >/dev/null && git diff -U0 payload/install.sh | grep -c '^[+-]' | xargs -I{} test {} -lt 80 && bash -c 'export BIB_INSTALL_LIB=1 BIB_STATE_DIR=$(mktemp -d); export BIB_STATE_FILE="$BIB_STATE_DIR/state.json" BIB_LOG_DIR=$(mktemp -d); source payload/install.sh some stray args; declare -F do_uninstall >/dev/null && [[ -z "${CHOSEN_CLI:-}" ]] && echo T2-OK'</verify>
  <done>`install.sh` sourceable con `BIB_INSTALL_LIB=1` (define `do_uninstall`, no ejecuta nada) y ejecutable exactamente como antes; diff por debajo de 80 líneas.</done>
</task>

**Wave 2 — el driver (T4 y T5 paralelizables tras T3)**

<task id="T3">
  <files>payload/test/uninstall-contract.sh</files>
  <action>Esqueleto estilo `ssh-finalize-decision.sh`: cabecera explicando qué cubre y qué no, `ok`/`bad`, contadores, `trap` de limpieza. AUTOPROTECCIÓN OBLIGATORIA antes de nada: abortar si `EUID -eq 0` y abortar si el sandbox no es un `mktemp -d` bajo `$TMPDIR`/`/tmp` — la NFR §1 es "imposible por construcción", no "por cuidado". Mocks en `$MOCK_BIN` (PATH): `systemctl` (registra en `MOCK_SYSTEMCTL_LOG`, `is-enabled` devuelve 1), `apparmor_parser` (registra args), `getent passwd` (home dentro del sandbox). Redirigir `BIB_STATE_DIR`/`BIB_STATE_FILE`/`BIB_LOG_DIR`/`BIB_LOG_FILE` y `BIB_UNINSTALL_ROOT_TEST` al sandbox, `source` de install.sh con `BIB_INSTALL_LIB=1`, `require_root() { :; }` y helper `run_uninstall` con captura de `$?` en subshell. Builder `seed()` que planta el árbol completo de un box instalado (drop-ins 00/01/10 + un `60-cloudimg-settings.conf` ajeno, `biab`, `biab-firstboot.sh`, `/opt/buildersinabox`, state.json, `~/.bashrc.d/biab-*` + un `mine.sh` ajeno, `~/.ssh/authorized_keys` con llave). Escenario A "teardown completo": todo lo nuestro fuera, lo ajeno intacto, `daemon-reload` + `reload ssh.service` + `enable ssh.socket` llamados, `stop`/`restart ssh` NUNCA, `ssh.service.d` vacío eliminado, exit 0.</action>
  <verify>shellcheck -S warning payload/test/uninstall-contract.sh && bash payload/test/uninstall-contract.sh && bash payload/test/uninstall-contract.sh --stray-arg && touch /tmp/feat024.mark && bash payload/test/uninstall-contract.sh && test -z "$(find /etc /usr/local/bin "$HOME/.ssh" -newer /tmp/feat024.mark 2>/dev/null)" && echo T3-OK</verify>
  <done>Escenario A en verde; `find` sobre `/etc`, `/usr/local/bin` y `~/.ssh` no encuentra nada modificado por la pasada (cero escrituras fuera del sandbox) y el driver aborta si se le lanza como root.</done>
</task>

<task id="T4">
  <files>payload/test/uninstall-contract.sh</files>
  <action>Escenarios de propiedad, cada uno citando en comentario el defecto del 2026-08-14 que reproduce: (B1) `bd` ajeno → byte-idéntico tras uninstall (`cmp -s` contra copia previa) [#44]; (B2) `bd` legacy sin marcador pero con la cabecera `brain-dump capture CLI` → reconocido como nuestro y borrado [review de #44: el check de propiedad sin ruta de migración congelaba `bd` para siempre]; (B3) fichero que solo *menciona* "Builders in a Box" en `/usr/local/bin/bd` y en `autologin.conf` → intacto; (B4) autologin ajeno intacto, autologin nuestro (primera línea de `systemd/getty@tty1.service.d/autologin.conf.in`) borrado; (B5) `/etc/apparmor.d/bwrap` ajeno → intacto Y `apparmor_parser` jamás invocado; nuestro → `-R` invocado ANTES del borrado [#41]; (B6) aserción estática: `BWRAP_PROFILE_MARKER` de `install/42-codex-cli.sh` contiene `$BIB_OWNERSHIP_MARKER` (si alguien acorta el marcador, el uninstall dejaría de reconocer su propio perfil). Los predicados de T1 se asertan además directamente sobre las 4 fixtures, que es la forma en que este driver cubre el lado *install* sin ejecutar el instalador.</action>
  <verify>bash payload/test/uninstall-contract.sh &amp;&amp; bash -c 'sed -i "s/|brain-dump capture CLI//" payload/lib/common.sh; bash -n payload/lib/common.sh || { git checkout payload/lib/common.sh; echo "mutation broke syntax, not a real check" >&amp;2; exit 1; }; rc=0; bash payload/test/uninstall-contract.sh >/dev/null 2>&amp;1 || rc=$?; git checkout payload/lib/common.sh; test "$rc" -ne 0' &amp;&amp; echo MUTATION-B2-CAUGHT</verify>
  <done>Los 6 grupos en verde y la mutación del patrón legacy hace fallar al driver.</done>
</task>

<task id="T5">
  <files>payload/test/uninstall-contract.sh</files>
  <action>Escenarios del guard SSH y de orden, con `BIB_PROMPT_INPUT` apuntando a un fichero del sandbox: (C1) `authorized_keys` solo con comentarios/blancos → se imprime el WARNING [el bug que dejaba una caja headless inalcanzable]; (C2) respuesta distinta de `yes` → exit 1, mensaje "nothing was changed", y NADA tocado: drop-ins presentes, `/opt` presente y — clave — el `uninstall.sh` del pack (fixture ejecutable que hace `touch`) NO ejecutado [review de #41/#44: el abort mentía si el teardown corría antes]; (C3) `yes` → el teardown del pack corre ANTES de que desaparezca `/opt/buildersinabox`; (C4) con llave presente el guard ni pregunta ni avisa; (C5) idempotencia: segunda pasada sobre un árbol ya limpio imprime "nothing to remove" y sale 0; (C6) precedencia real opcional: si hay `sshd`, generar hostkey con `ssh-keygen` e `Include` del dir de drop-ins del sandbox y comprobar con `sshd -T` que antes del uninstall `PasswordAuthentication` efectivo es `yes` (lo fuerza nuestro 00) y después es `no` (manda el `60-cloudimg` de la distro) — la prueba literal de la frase "sshd is back to your distribution defaults" [#42]; si no hay `sshd`, SKIP contado como ok.</action>
  <verify>bash payload/test/uninstall-contract.sh &amp;&amp; bash -c 'sed -i "s#/etc/ssh/sshd_config.d/00-buildersinabox.conf#/etc/ssh/sshd_config.d/00-MUTANT.conf#g" payload/install.sh; bash -n payload/install.sh || { git checkout payload/install.sh; echo "mutation broke syntax, not a real check" >&amp;2; exit 1; }; rc=0; bash payload/test/uninstall-contract.sh >/dev/null 2>&amp;1 || rc=$?; git checkout payload/install.sh; test "$rc" -ne 0' &amp;&amp; echo MUTATION-42-CAUGHT</verify>
  <done>C1-C6 en verde; quitar `00-buildersinabox.conf` de la lista de borrado hace fallar al driver (el bug de #42 queda atrapado).</done>
</task>

**Wave 3 — wiring**

<task id="T6">
  <files>.github/workflows/ci.yml, CONTRIBUTING.md</files>
  <action>Step nuevo en el job `lint`, inmediatamente después del de FEAT-014 (:53-54), con el mismo formato: `- name: Install/uninstall ownership contract (FEAT-024)` / `run: bash payload/test/uninstall-contract.sh`, y un comentario corto explicando que corre sin root y que el `sshd -T` real se salta si no hay binario. En CONTRIBUTING.md, junto a la mención existente de `payload/test/wiring-smoke.sh` (:64), una línea con cómo correrlo en local y el aviso de NO lanzarlo con sudo.</action>
  <verify>python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/ci.yml')); steps=[s.get('run','') for s in d['jobs']['lint']['steps']]; sys.exit(0 if any('uninstall-contract.sh' in s for s in steps) else 1)" && grep -q 'uninstall-contract' CONTRIBUTING.md && echo T6-OK</verify>
  <done>El step aparece en el job `lint` (no en uno nuevo) y la PR sale verde con el driver ejecutado.</done>
</task>

### Patron de codigo

Fragmento real de `payload/wizard/35-ssh-finalize.sh:587-592` — el guard de
librería que se replica en `install.sh`:

```bash
# Run unless sourced as a library (the unit test sets BIB_SSH_FINALIZE_LIB=1
# to source the functions without executing).
if [[ "${BIB_SSH_FINALIZE_LIB:-0}" != "1" ]]; then
    require_root
    ssh_finalize_main
fi
```

Y el bloque real de `payload/test/ssh-finalize-decision.sh:102-113` que el
driver nuevo copia línea por línea, cambiando el fichero sourceado y las
variables redirigidas:

```bash
# --- Source the finalize functions as a library ----------------------------
export BIB_SSH_FINALIZE_LIB=1
# Point state/log at a throwaway location before sourcing common.sh.
_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN" "$_SCRATCH"' EXIT
export BIB_STATE_DIR="$_SCRATCH/state"
export BIB_STATE_FILE="$_SCRATCH/state/state.json"
export BIB_LOG_DIR="$_SCRATCH/log"
export BIB_SSHD_DROPIN_DIR="$_SCRATCH/dropins"
mkdir -p "$BIB_STATE_DIR" "$BIB_LOG_DIR" "$BIB_SSHD_DROPIN_DIR"
# shellcheck source=../wizard/35-ssh-finalize.sh
source "${PAYLOAD_DIR}/wizard/35-ssh-finalize.sh"
```

Traducido a `install.sh` queda así (prototipado y ejecutado, no propuesto a
ciegas):

```bash
# Root prefix for every absolute path do_uninstall touches. Empty on a real
# box; honoured ONLY when sourced as a library, so a stray env var can never
# redirect a real uninstall.
BIB_UNINSTALL_ROOT=""
[[ "${BIB_INSTALL_LIB:-0}" == "1" ]] && BIB_UNINSTALL_ROOT="${BIB_UNINSTALL_ROOT_TEST:-}"
...
if [[ "$UNINSTALL_MODE" -eq 1 ]]; then
    do_uninstall
fi

# Sourced as a library by payload/test/uninstall-contract.sh: everything above
# is definitions + no-ops, everything below installs a machine. Stop here.
if [[ "${BIB_INSTALL_LIB:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
```

### Riesgos

- **R0 — el diseño ya está probado.** Prototipo completo (payload copiado a
  `/tmp`, las tres costuras aplicadas, driver de 5 escenarios): **23/23
  aserciones en verde en 0,22 s**, sin root, `shellcheck -S warning` limpio,
  `install.sh --help` intacto y el driver soportando argumentos sueltos. Los
  dos fallos encontrados en el camino (`ssh.service.d` como patrón de `[[ ]]`,
  doble prefijo por substring) están documentados arriba para que no se
  repitan.
- **R1 — una ruta a la que se le olvide el prefijo.** En el sandbox el fichero
  sobrevive y la aserción falla; el driver es su propio detector. Riesgo
  residual: correr el driver con `sudo` en una máquina real sí podría borrar
  algo. Mitigación dura: el driver aborta con `EUID -eq 0` (T3) y §3 lo
  prohíbe explícitamente.
- **R2 — `BIB_INSTALL_LIB=1` exportado por accidente en una máquina real**
  detendría la instalación tras el bloque de uninstall. Mitigación: nombre
  específico, `|| exit 0` para que pare limpio, y comentario en el propio
  guard.
- **R3 — el lado *install* del requisito EARS 3 no se cubre ejecutando el
  instalador.** `06-bd-cli.sh` es root-only y con destino hardcoded. Tras T1 el
  criterio de propiedad es literalmente la misma función en ambos lados, así
  que el driver lo cubre asertando el predicado compartido sobre las fixtures.
  El gate de autologin del lado install, además, **no** se decide por marcador
  sino por la existencia de `/etc/profile.d/biab-firstboot.sh` (`install.sh:471-473`,
  el fix de #44): eso queda fuera de esta FEAT y se documenta como hueco
  conocido.
- **R4 — sin cobertura del listener vivo**, igual que declara FEAT-014. La
  pasada manual en hardware sigue siendo necesaria (ver §1 NO incluye).
- **R5 — deuda existente que este FEAT no toca:** `install.sh:149` y
  `06-bd-cli.sh` seguirán siendo los únicos guardianes del contrato de
  propiedad para rutas nuevas; cualquier ruta que se añada a
  `paths_to_remove` en el futuro no lleva aserción automática. Mitigación
  barata: el driver falla si aparece una ruta en `paths_to_remove` que ningún
  escenario cubre — **no** se implementa en esta FEAT (coste alto, valor
  incierto); queda como TODO fechado en la cabecera del driver.

### Criterios de aceptacion

- [ ] `bash payload/test/uninstall-contract.sh` sale 0 como usuario normal, sin
      red y sin VM, en < 30 s (prototipo: 0,22 s).
- [ ] El driver aborta con mensaje claro si se ejecuta como root o si su
      sandbox no es un `mktemp -d`.
- [ ] Tras una pasada del driver, `find /etc /usr/local/bin "$HOME/.ssh" -newer
      MARCA` (con MARCA tocada justo antes) no devuelve nada: cero escrituras
      fuera del sandbox.
- [ ] Las tres mutaciones fallan el driver: quitar
      `00-buildersinabox.conf` de `paths_to_remove` (#42); quitar
      `brain-dump capture CLI` del patrón de `bd` (#44); mover el bloque del
      guard SSH detrás del loop de teardown de packs (#41).
- [ ] `bash payload/install.sh --help`, `payload/test/dryrun.sh` y
      `payload/test/ssh-finalize-decision.sh` siguen comportándose igual que en
      `main`.
- [ ] `shellcheck -S warning` y `bash -n` limpios en los 5 ficheros bash
      tocados (`install.sh`, `lib/common.sh`, `35-ssh-finalize.sh`,
      `06-bd-cli.sh`, `test/uninstall-contract.sh`).
- [ ] CI: el step vive dentro del job `lint` (no hay job nuevo) y la PR sale
      verde con él ejecutándose.
- [ ] `git diff main -- payload/install.sh` no cambia ni un mensaje al usuario,
      ni el orden de los pasos, ni un criterio de decisión: solo prefijos de
      ruta y guards.
- [ ] Presupuesto revisado: `max_turns=120 timeout=3600` es suficiente — un
      fichero nuevo (~350 líneas) y cuatro ediciones pequeñas, con el diseño ya
      validado.

---

## 3. Boundaries

### Always

- Correr sin root y contra temp dirs. Ninguna aserción puede depender de tocar
  `/etc`, `/usr/local/bin` ni `~/.ssh` reales del host o del runner.
- Cada caso del driver debe corresponder a un defecto real observado el
  2026-08-14, y citarlo en un comentario. Sin tests inventados "por cobertura".
- **El driver se autoprotege** (añadido por §2): aborta si `EUID -eq 0` y
  aborta si su raíz de sandbox no es un `mktemp -d`. La NFR de §1 dice
  "imposible por construcción", y un `rm -rf` con prefijo vacío corriendo como
  root es exactamente el accidente que hay que hacer imposible.
- **Las costuras de test son inertes en producción** (añadido por §2):
  `BIB_UNINSTALL_ROOT` solo se honra cuando `BIB_INSTALL_LIB=1`, y por defecto
  es cadena vacía, de modo que el comportamiento de un uninstall real es
  byte-idéntico al de `main`.

### Ask First

- Añadir un job nuevo a CI en vez de un step al job `lint` (coste de minutos).
- Cualquier refactor de `do_uninstall` que vaya más allá del hook de librería.
- **Añadir una cuarta costura** a `install.sh` más allá de las tres que fija
  §2 (`BIB_INSTALL_LIB`, `BIB_UNINSTALL_ROOT`, `BIB_PROMPT_INPUT`): cada knob
  nuevo es superficie de configuración en un script que corre como root.
- Extender el alcance al wizard completo.

### Never

- Modificar el comportamiento del instalador dentro de esta FEAT. Es una FEAT de
  verificación; si un test falla, la corrección va en su propia PR.
- Escribir tests que necesiten una VM o red en CI.
- **Ejecutar el driver con `sudo`** o con privilegios elevados, en local o en
  CI. Si necesita root para pasar, el diseño está mal.
- Tocar `firestore.rules` ni configuraciones de seguridad (no aplica aquí, pero
  la regla del repo se mantiene).

---

## 4. QA (Pablo)

### Qué se está probando aquí

El artefacto bajo prueba **es un test**. Eso cambia el criterio de aceptación:
que `bash payload/test/uninstall-contract.sh` salga 0 no demuestra nada por sí
solo — un driver que no asierta nada también sale 0. Este repo se ha comido ese
fallo dos veces, ambas encontradas leyendo código y no ejecutándolo:

- `payload/hooks/tests/run-tests.sh` tenía un bloque entero de aserciones contra
  un `settings.json` que el código bajo prueba nunca escribía: verde y vacío.
- El mismo fichero abortaba a mitad bajo un `set -e` heredado del script
  sourceado, saltándose ~40 aserciones posteriores **sin línea de resumen**, y
  el job de CI ni siquiera lo invocaba (ver el comentario en
  `.github/workflows/ci.yml:56-65`).

Por eso §4 se organiza en dos ejes, no en uno:

1. **Verde cuando debe estar verde** — bloques A–E: el driver reproduce los
   siete chequeos manuales del 2026-08-14 y no escribe fuera de su sandbox.
2. **Rojo cuando debe estar rojo** — bloque F: ocho mutaciones deliberadas
   (siete al código de producción, una al propio driver) que el driver
   **tiene que** detectar. Un driver que nadie ha visto fallar no es evidencia.

Regla derivada, y es criterio de aceptación de esta FEAT: el driver declara en
su cabecera un `EXPECTED_ASSERTIONS=<N>` y falla si `pass + fail != N`, además
de fallar si `fail > 0`. Sin ese contador, un `exit` a mitad de fichero (el bug
de `run-tests.sh`) es indistinguible de una pasada limpia. La línea de resumen
`uninstall-contract: <pass> passed, <fail> failed` debe imprimirse **siempre**,
también cuando el driver aborta — es decir, desde un `trap ... EXIT`, no como
última línea del flujo feliz.

### Trazabilidad: semilla manual del 2026-08-14 → caso

| Chequeo hecho a mano el 2026-08-14 | Caso que lo automatiza |
|---|---|
| `sshd -T` antes/después del uninstall (#42) | QA-22 (real) + QA-06 (hermético) |
| `bd` legacy sin marcador, con cabecera `brain-dump capture CLI` (#44) | QA-12 |
| `bd` ajeno intacto (#44) | QA-11 |
| Fichero ajeno que solo *menciona* el producto | QA-13 |
| `authorized_keys` con solo comentarios | QA-18 |
| Abort dejando intacto el teardown de packs (#41) | QA-19 |
| Autologin ajeno intacto | QA-14 |
| Perfil AppArmor `bwrap` ajeno / descarga antes de borrar (#41) | QA-15 |

### Casos funcionales

Estado inicial de todos: `pendiente`. Los pasos asumen `cwd` = raíz del repo y
un usuario **sin** privilegios (`id -u` distinto de 0).

#### Bloque A — arranque y autoprotección del driver

| ID | Caso | Pasos | Resultado esperado (verificable) | Estado |
|----|------|-------|----------------------------------|--------|
| QA-01 | Pasada normal | 1) `touch /tmp/feat024.mark` 2) `time bash payload/test/uninstall-contract.sh; echo "rc=$?"` | `rc=0`; última línea `uninstall-contract: <N> passed, 0 failed` con `<N>` igual al `EXPECTED_ASSERTIONS` de la cabecera; `real` < 30 s | pendiente |
| QA-02 | Aborta si corre como root | 1) `command -v fakeroot` (si falta, probar `unshare -r true`; si tampoco, imprimir SKIP explícito — nunca verde silencioso) 2) `fakeroot bash payload/test/uninstall-contract.sh; echo "rc=$?"` | `rc` distinto de 0; stderr menciona `EUID`/`root`; **cero** líneas `ok:` en la salida (aborta antes de asertar); `find /etc /usr/local/bin -newer /tmp/feat024.mark` vacío | pendiente |
| QA-03 | Aborta si no puede construir el sandbox | `TMPDIR=/nonexistent-feat024 bash payload/test/uninstall-contract.sh; echo "rc=$?"` | `rc` distinto de 0 y mensaje que nombra el sandbox; **no** llega a llamar a `do_uninstall` con prefijo vacío: `find /etc /usr/local/bin "$HOME/.ssh" -newer /tmp/feat024.mark 2>/dev/null` no devuelve nada | pendiente |
| QA-04 | Cero escrituras fuera del sandbox | 1) `touch /tmp/feat024.mark` 2) `bash payload/test/uninstall-contract.sh` 3) `find /etc /usr/local/bin "$HOME/.ssh" "$HOME/.bashrc.d" -newer /tmp/feat024.mark 2>/dev/null` | La `find` no imprime nada; además `ls -d /tmp/tmp.*` no deja sandboxes huérfanos del driver (el `trap` limpió) | pendiente |
| QA-05 | Argumentos y entorno hostil no rompen el sourcing | 1) `bash payload/test/uninstall-contract.sh --stray-arg` 2) `BIB_UNINSTALL_ROOT=/ BIB_INSTALL_LIB=1 bash payload/test/uninstall-contract.sh` | `rc=0` en las dos; la salida no contiene `unknown argument`; en (2) el prefijo efectivo sigue siendo el sandbox y no `/` (lo demuestra QA-25) | pendiente |

#### Bloque B — escenario A: teardown completo

Todos parten del `seed()` descrito en T3: drop-ins `00`/`01`/`02` + un
`60-cloudimg-settings.conf` ajeno, `10-buildersinabox-tailscale-wait.conf`,
`biab`, `biab-firstboot.sh`, `/opt/buildersinabox`, `state.json`, log dir,
`~/.bashrc.d/biab-*` + un `mine.sh` ajeno, `authorized_keys` con llave.

| ID | Caso | Pasos | Resultado esperado (verificable) | Estado |
|----|------|-------|----------------------------------|--------|
| QA-06 | Todo lo nuestro desaparece | 1) `seed()` 2) `run_uninstall` con llave presente 3) comprobar cada ruta bajo `$SANDBOX` | Ausentes las 9 rutas incondicionales de `paths_to_remove` (`install.sh:190-210`), **incluida** `/etc/ssh/sshd_config.d/00-buildersinabox.conf`, más los snippets `~/.bashrc.d/biab-*`; `rc=0`; la salida contiene literalmente `uninstall: complete. sshd is back to your distribution defaults.` | pendiente |
| QA-07 | Lo ajeno sobrevive byte a byte | 1) copiar `60-cloudimg-settings.conf` y `~/.bashrc.d/mine.sh` antes 2) `run_uninstall` 3) `cmp -s` contra las copias | `cmp -s` idéntico para los dos; ambos siguen existiendo; su `stat -c %Y` no ha cambiado | pendiente |
| QA-08 | Efectos systemd correctos y no destructivos | 1) `MOCK_SYSTEMCTL_LOG` vacío 2) `run_uninstall` 3) inspeccionar el log del mock | El log contiene `daemon-reload`, `reload ssh.service`, `is-enabled ssh.socket`, `disable ssh.service` y `enable ssh.socket`; **no** contiene `stop ssh` ni `restart ssh` ni `--now`; la salida contiene `uninstall: restored ssh.socket activation` | pendiente |
| QA-09 | `ssh.service.d` vacío se elimina | `seed()` sin drop-ins ajenos en ese dir → `run_uninstall` | El directorio `$SANDBOX/etc/systemd/system/ssh.service.d` ya no existe (`[[ ! -d ]]`) | pendiente |
| QA-10 | Idempotencia | 1) `run_uninstall` 2) `MOCK_SYSTEMCTL_LOG` vacío 3) `run_uninstall` otra vez sobre el mismo árbol | Segunda pasada: `rc=0`, salida contiene `uninstall: nothing to remove — no BIAB state found`, y `MOCK_SYSTEMCTL_LOG` queda **vacío** (no se recarga systemd cuando no se borró ningún drop-in) | pendiente |

#### Bloque C — predicados de propiedad

| ID | Caso | Pasos | Resultado esperado (verificable) | Estado |
|----|------|-------|----------------------------------|--------|
| QA-11 | `bd` ajeno intacto (#44) | 1) sembrar `$SANDBOX/usr/local/bin/bd` con un script del usuario 2) copiarlo 3) `run_uninstall` | `cmp -s` contra la copia: idéntico; sigue existiendo; la salida contiene `alone — it is not ours` nombrando esa ruta | pendiente |
| QA-12 | `bd` legacy sin marcador (#44) | sembrar `bd` cuya única señal es la cabecera `# brain-dump capture CLI` → `run_uninstall` | El fichero **no** existe tras la pasada; la salida contiene `uninstall: removing` con esa ruta | pendiente |
| QA-13 | Solo *menciona* el producto | sembrar `bd` con la línea `# I love Builders in a Box` y `autologin.conf` con `# inspired by Builders in a Box` → `run_uninstall` | Los dos siguen existiendo y `cmp -s` idénticos; dos líneas `alone — it is not ours` | pendiente |
| QA-14 | Autologin nuestro vs ajeno | (a) `autologin.conf` = primera línea de `payload/systemd/getty@tty1.service.d/autologin.conf.in`; (b) `autologin.conf` de un recetario kiosk cualquiera | (a) borrado; (b) intacto y `cmp -s` idéntico | pendiente |
| QA-15 | AppArmor `bwrap` (#41) | (a) perfil con `Installed by Builders in a Box`; (b) perfil ajeno. En (a), el mock de `apparmor_parser` registra args **y** anota si el fichero aún existía al ser invocado | (a) log del mock contiene `-R` con la ruta, la anotación dice que el fichero **existía** en ese momento, y tras la pasada el fichero no existe; (b) el log de `apparmor_parser` está vacío, el fichero intacto y aparece `leaving …/bwrap alone — it is not ours` | pendiente |
| QA-16 | Marcador de codex compatible (estática) | `grep BWRAP_PROFILE_MARKER payload/install/42-codex-cli.sh` y comparar contra `$BIB_OWNERSHIP_MARKER` | La cadena de `42-codex-cli.sh:34` **contiene** `$BIB_OWNERSHIP_MARKER` como substring; si alguien acorta el marcador compartido, esta aserción se pone roja antes de que el uninstall deje de reconocer su propio perfil | pendiente |
| QA-17 | Dedup de T1 sin cambio de criterio (diferencial) | Para cada fixture de QA-11..QA-14 y la matriz de `authorized_keys` de E-01..E-04, comparar el veredicto de `bib_path_is_ours` / `bib_authorized_keys_present` contra las implementaciones literales de `main` (`bd_is_ours` de `06-bd-cli.sh:31-35`, la regex `^[[:space:]]*[^[:space:]#]` de `install.sh:149`, el patrón inline de `install.sh:224-225`) inlineadas en el driver como referencia | Veredicto **idéntico** en las 10 fixturas. Divergencia = fallo, aunque el resto del driver esté verde: T1 se declara deduplicación, no cambio de criterio | pendiente |
| QA-18 | Sin llave usable → WARNING (bug #42) | `authorized_keys` solo con `#` y líneas en blanco → `run_uninstall` | La salida contiene `has no SSH key in authorized_keys` y el bloque de 5 líneas de aviso; el uninstall continúa (`rc=0`) porque no hay tty ni input | pendiente |

#### Bloque D — guard SSH, abort y orden

| ID | Caso | Pasos | Resultado esperado (verificable) | Estado |
|----|------|-------|----------------------------------|--------|
| QA-19 | Abort no toca nada (#41) | 1) `seed()` con pack cuyo `uninstall.sh` hace `touch $SENTINEL` 2) `authorized_keys` sin llave 3) `BIB_PROMPT_INPUT` = fichero con `no` 4) `run_uninstall` | `rc=1`; la salida contiene exactamente `uninstall: aborted, nothing was changed.`; siguen existiendo los 3 drop-ins, `/opt/buildersinabox`, `biab`, `state.json` y los snippets; `$SENTINEL` **no** existe; `MOCK_SYSTEMCTL_LOG` vacío | pendiente |
| QA-20 | Confirmar → teardown del pack antes de borrar `/opt` | igual que QA-19 pero con `yes`; el `uninstall.sh` del pack escribe en `$SENTINEL` si `/opt/buildersinabox` aún existe al ejecutarse | `rc=0`; `$SENTINEL` existe y su contenido indica `opt-present`; la salida contiene `uninstall: running pack teardown`; tras la pasada `/opt/buildersinabox` no existe | pendiente |
| QA-21 | Con llave, ni aviso ni pregunta | `authorized_keys` con una `ssh-ed25519` válida; `BIB_PROMPT_INPUT` = fichero con `no` | `rc=0`; la salida **no** contiene `has no SSH key` ni `Type yes to continue`; el fichero de input queda sin consumir (mismo `stat -c %s` y ninguna lectura registrada) | pendiente |
| QA-22 | Precedencia real con `sshd -T` (#42) | 1) si hay `sshd`: `ssh-keygen` de hostkey + `sshd_config` con `Include $SANDBOX/etc/ssh/sshd_config.d/*.conf` 2) medir `PasswordAuthentication` efectivo 3) `run_uninstall` 4) medir otra vez | Antes: `yes` (lo fuerza nuestro `00`); después: `no` (manda el `60-cloudimg` de la distro) — la prueba literal de la frase `sshd is back to your distribution defaults`. Sin `sshd`: se imprime `SKIP` visible y cuenta como `ok`, nunca como aserción silenciada | pendiente |
| QA-23 | Sin `00-…conf` el guard ni se ejecuta | `seed()` sin el drop-in `00`; `BIB_PROMPT_INPUT` = fichero con `no` | `rc=0`; la salida no contiene `WARNING` ni `Type yes`; el resto del árbol nuestro sí desaparece | pendiente |

#### Bloque E — las costuras son inertes en producción

Cubre el bloque *Always* de §3 ("las costuras de test son inertes en
producción") y el riesgo R2.

| ID | Caso | Pasos | Resultado esperado (verificable) | Estado |
|----|------|-------|----------------------------------|--------|
| QA-24 | El parseo de argumentos no cambia | 1) `bash payload/install.sh --help > /tmp/help-new.txt; echo rc=$?` 2) `git show main:payload/install.sh > /tmp/install-main.sh && bash /tmp/install-main.sh --help > /tmp/help-main.txt` 3) `diff` 4) `bash payload/install.sh --bogus; echo rc=$?` | `diff` vacío y `rc=0` en (1); en (4) `rc` distinto de 0 y stderr contiene `unknown argument: --bogus` | pendiente |
| QA-25 | `BIB_UNINSTALL_ROOT` hostil no se honra | `BIB_INSTALL_LIB=1 BIB_UNINSTALL_ROOT=/hostile` + variables de state/log al sandbox, `source payload/install.sh`, imprimir `"[$BIB_UNINSTALL_ROOT]"` | Imprime `[]` o el valor de `BIB_UNINSTALL_ROOT_TEST`, nunca `/hostile`; y estáticamente: la única asignación no vacía de `BIB_UNINSTALL_ROOT` en `install.sh` está en la misma línea que la condición `BIB_INSTALL_LIB` (`grep -n 'BIB_UNINSTALL_ROOT=' payload/install.sh` devuelve exactamente 2 líneas y la segunda contiene `BIB_INSTALL_LIB`) | pendiente |
| QA-26 | `BIB_PROMPT_INPUT` no altera un uninstall real | Comparar el comportamiento del guard entre `main` y la rama en tres entornos, con el árbol sembrado y sin llave: (a) `BIB_PROMPT_INPUT` sin definir y sin `/dev/tty` legible; (b) `BIB_PROMPT_INPUT=/dev/null`; (c) `BIB_PROMPT_INPUT` = fichero con `yes` | En los tres, y **sin** `BIB_INSTALL_LIB=1`, el resultado debe ser el mismo que en `main`: se imprime el WARNING y el uninstall **continúa** (`rc=0`). Ojo: con la costura tal cual la describe §2 (`-r "$BIB_PROMPT_INPUT"` sin condicionar a modo librería), (b) pasa a abortar con `rc=1` donde `main` continuaba — este caso es el que lo detecta. Si cumplirlo exige condicionar la costura a `BIB_INSTALL_LIB=1`, es una decisión de §2, no un cambio de QA | pendiente |
| QA-27 | El abort imprime su mensaje también con EOF | `BIB_PROMPT_INPUT` = fichero **vacío** (EOF inmediato), sin llave, `run_uninstall` | `rc=1` **y** la salida contiene `uninstall: aborted, nothing was changed.`. Detecta el `_bib_read_line _ack` sin `\|\| true`: bajo el `set -e` de `install.sh:21` un retorno no cero de la función mata `do_uninstall` sin imprimir el mensaje | pendiente |
| QA-28 | Sourcear no ejecuta nada; ejecutar con la var puesta para limpio | (a) `BIB_INSTALL_LIB=1 source payload/install.sh` → `declare -F do_uninstall`, `${CHOSEN_CLI:-}`, contenido del sandbox; (b) `BIB_INSTALL_LIB=1 bash payload/install.sh; echo rc=$?` | (a) `do_uninstall` definida, `CHOSEN_CLI` sin definir, ningún `install/*.sh` ejecutado (el mock de `run_install` no registra nada) y ningún fichero creado fuera del sandbox; (b) `rc=0` y sin traza de instalación (el `return 0 2>/dev/null \|\| exit 0` del riesgo R2) | pendiente |

#### Bloque F — anti-vacío: el driver tiene que poder fallar

Cada mutación se aplica sobre un árbol limpio, se corre el driver y se
revierte. **El resultado esperado es que el driver salga rojo**, y que lo haga
por la aserción concreta que se indica — no por un error de sintaxis. Se
ejecutan una vez antes de abrir la PR (procedimiento completo en "Criterios de
testing") y su salida se pega en la descripción de la PR.

| ID | Mutación (deliberada, revertida después) | Aserción que debe ponerse roja | Estado |
|----|------------------------------------------|-------------------------------|--------|
| QA-29 | Quitar `/etc/ssh/sshd_config.d/00-buildersinabox.conf` de `paths_to_remove` (`install.sh:203`) — el bug #42 | QA-06 y QA-22 | pendiente |
| QA-30 | Quitar `brain-dump capture CLI` del patrón compartido de `bd` (`lib/common.sh`, tras T1) — el bug de la review de #44 | QA-12 y QA-17 | pendiente |
| QA-31 | Mover el bloque del guard SSH (`install.sh:144-167`) detrás del bucle de teardown de packs (`:176-183`) — el bug de la review de #41 | QA-19 (el `$SENTINEL` aparecería pese al abort) | pendiente |
| QA-32 | Borrar el `grep -Eq "$_pat"` de `install.sh:227` y añadir siempre a `paths_to_remove` | QA-11, QA-13 y QA-14(b) | pendiente |
| QA-33 | Quitar la llamada `apparmor_parser -R` (`install.sh:240-241`) dejando el borrado | QA-15(a) | pendiente |
| QA-34 | Cambiar `systemctl reload ssh.service` por `restart` (`install.sh:266`) | QA-08 (la aserción "nunca restart") | pendiente |
| QA-35 | Quitar el prefijo `$BIB_UNINSTALL_ROOT` a una ruta cualquiera — usar `01-buildersinabox-tailscale.conf`, nunca una que exista en el host | Driver rojo porque el fichero del sandbox sobrevive; **y** `find /etc -newer MARCA` sigue vacío (el host real no se toca ni con la costura rota, porque el driver corre sin root) | pendiente |
| QA-36 | **Meta-mutación al propio driver**: (a) insertar `exit 0` justo después del bloque B, y (b) comentar una línea del `seed()` para que una aserción compare contra un fichero que nadie escribió | (a) el guard `pass + fail != EXPECTED_ASSERTIONS` pone rojo aunque `fail` sea 0 — el fallo exacto de `run-tests.sh`; (b) la aserción afectada se pone roja en vez de pasar por vacío | pendiente |

#### Bloque G — wiring de CI

| ID | Caso | Pasos | Resultado esperado (verificable) | Estado |
|----|------|-------|----------------------------------|--------|
| QA-37 | El step corre de verdad y en el job correcto | 1) `gh pr checks` sobre la PR 2) abrir el log del job `lint` 3) `gh run view --log \| grep 'uninstall-contract:'` | El log del step contiene la línea de resumen con `0 failed` y el número esperado de aserciones (no basta con "step verde"); el workflow sigue teniendo 4 jobs (`lint`, `list-clis`, `dryrun`, `browser-pack-tests`); el job `lint` no crece más de ~30 s respecto a la ejecución anterior en `main` | pendiente |

### Edge cases

Entradas vacías, inválidas y extremas. Todas se ejercitan dentro del sandbox
del driver salvo indicación contraria.

| ID | Entrada / condición | Resultado esperado (verificable) | Estado |
|----|---------------------|----------------------------------|--------|
| E-01 | `authorized_keys` no existe | Se toma el camino de WARNING (`has no SSH key`), sin error de `grep` en la salida; `rc=0` | pendiente |
| E-02 | `authorized_keys` de 0 bytes | Igual que E-01 | pendiente |
| E-03 | `authorized_keys` es un symlink colgante | Igual que E-01; ningún mensaje de `grep: No such file` fugado a stdout | pendiente |
| E-04 | `authorized_keys` con la llave en la última línea **sin salto final**, precedida de 3 comentarios | Se considera llave presente: ni WARNING ni prompt (`rc=0`) | pendiente |
| E-05 | `state.json` corrupto (no es JSON) | `jq` falla en silencio (`\|\| true` de `install.sh:129`), `target_user` cae a `SUDO_USER`/`USER`, `rc=0`, el barrido de `.bashrc.d` usa ese home | pendiente |
| E-06 | `state.json` con `.bib_user` distinto de `SUDO_USER` | Se usa el usuario de `state.json`: los snippets borrados son los del home que devuelve el mock de `getent` para **ese** usuario, y los del otro home siguen ahí | pendiente |
| E-07 | `getent passwd` no resuelve al usuario (cuenta ya borrada) | Sin barrido de `.bashrc.d`, sin crash, `rc=0`, y el guard SSH toma el camino de WARNING con el literal `the target user` | pendiente |
| E-08 | `~/.bashrc.d` existe pero sin ningún `biab-*` | El glob literal `biab-*` no se borra ni se cuenta (`[[ -e ]] \|\| continue`); `found_anything` no cambia por eso | pendiente |
| E-09 | `/usr/local/bin/bd` es un symlink a un script del usuario que **sí** lleva el marcador | Se borra el **symlink** y el destino sigue existiendo (`test -f "$TARGET"` tras la pasada). Es el único caso en que borramos algo que apunta fuera de nuestras rutas | pendiente |
| E-10 | `bd` sin permiso de lectura (`chmod 000`) | `grep` falla → se clasifica como ajeno → se deja (fallo hacia "no borrar"), con la línea `alone — it is not ours`. Ver "Huecos conocidos": como root el veredicto sería el contrario | pendiente |
| E-11 | `bd` de 0 bytes | No casa el patrón → se deja intacto | pendiente |
| E-12 | `/etc/systemd/system/ssh.service.d/` contiene un drop-in ajeno (`50-user.conf`) | El `rmdir` de `install.sh:264` falla en silencio; el directorio y el `50-user.conf` siguen ahí y `cmp -s` idéntico; `rc=0` y `daemon-reload` igualmente llamado | pendiente |
| E-13 | Ruta de sandbox con un espacio (`mktemp -d "$TMPDIR/feat024 with space.XXXXXX"`) | Todas las aserciones siguen verdes: prueba el entrecomillado del prefijo, incluido el patrón de `[[ "$p" == …/* ]]` de `install.sh:255` | pendiente |
| E-14 | `BIB_UNINSTALL_ROOT_TEST` vacío, `/` o inexistente al llamar al helper | El helper `run_uninstall` aborta antes de invocar nada y el driver sale rojo. Es la última barrera del riesgo R1 | pendiente |
| E-15 | Pack cuyo `uninstall.sh` no es ejecutable, y otro que sale con `rc=1` | El primero se salta sin mensaje; el segundo produce `uninstall: pack teardown … failed, continuing` y el uninstall global termina en `rc=0` | pendiente |
| E-16 | Dos packs instalados | Los dos teardown se ejecutan (dos sentinels) y ambos antes de que desaparezca `/opt/buildersinabox` | pendiente |
| E-17 | `autologin.conf` que dice `Builders in a Box - autologin` con guion normal en vez del em-dash `—` de la plantilla | **No** se reconoce como nuestro → se deja intacto. Documenta que el criterio es byte-exacto y que el marcador real lleva U+2014 (`install.sh:225`, `systemd/getty@tty1.service.d/autologin.conf.in:1`) | pendiente |

### Regresion

Lista de lo que ya funciona y no puede romperse. T1 toca tres consumidores
fuera del alcance directo de la FEAT y T2 toca el fichero que corre como root
en todas las máquinas: ahí está el riesgo.

- [ ] `bash payload/test/ssh-finalize-decision.sh` sigue verde **y con el mismo
      número de aserciones** que en `main` (T1 mueve `_authorized_keys_present`
      desde `35-ssh-finalize.sh:151-155`, con call site en `:532`).
- [ ] `bash payload/hooks/tests/run-tests.sh` sigue verde.
- [ ] `payload/test/wiring-smoke.sh` verde para `claude` y `antigravity` (la
      matriz `dryrun` de CI): el lado *install* no cambia de comportamiento.
- [ ] `bash tools/check-no-personal-refs.sh` verde con el driver nuevo — nada de
      rutas `/home/<usuario>`, hostnames ni rutas del checkout del mantenedor
      dentro de `payload/test/uninstall-contract.sh`.
- [ ] `git archive HEAD | tar -t` sigue sin `specs/` **y** ahora sí contiene
      `payload/test/uninstall-contract.sh`: el driver viaja con el payload
      (como los otros dos de `payload/test/`), no se le añade `export-ignore`.
- [ ] `bash payload/install.sh --help` idéntico a `main` (QA-24) y
      `--selftest` sin cambios de comportamiento.
- [ ] Los consumidores que **ejecutan** `install.sh` siguen funcionando y
      ninguno exporta `BIB_INSTALL_LIB`: `installer/web/install.sh:84`,
      `payload/install/05-biab-command.sh:34` y `:189`,
      `payload/profile.d/biab-firstboot.sh:42`, `payload/test/dryrun.sh:40`.
      Verificable con `grep -rn 'BIB_INSTALL_LIB' installer/ payload/ tools/ .github/`
      → solo `install.sh` y el driver.
- [ ] `payload/install/06-bd-cli.sh` sigue negándose a pisar un `bd` ajeno
      (mensaje `already exists and is not ours`) y sigue instalando encima de
      uno legacy sin marcador — el mismo veredicto que antes de delegar en
      `bib_path_is_ours` (lo asegura QA-17).
- [ ] `shellcheck -S warning` limpio en el árbol completo (el step de CI lo
      recorre entero, incluidos los extensionless por shebang) y `bash -n` en
      los entry points de `.github/workflows/ci.yml:35-43`.
- [ ] Ningún script de `payload/install/*` se ejecuta de verdad durante los
      tests (son root-only): el driver no debe invocarlos ni directa ni
      indirectamente — comprobable porque corre sin root y termina en `rc=0`.
- [ ] `.github/workflows/ci.yml` mantiene 4 jobs; el step nuevo vive dentro de
      `lint` (Boundaries §3).
- [ ] Ninguna de las rutas reales del host aparece modificada tras correr toda
      la batería (QA-04), incluida la pasada de mutaciones del bloque F.

### Criterios de testing

Comandos ejecutables. Todo desde la raíz del repo y **sin `sudo`** (§3 Never).

```bash
# 1) Pasada normal + presupuesto de tiempo + resumen no vacío
time bash payload/test/uninstall-contract.sh | tee /tmp/feat024-run.log
grep -Eq 'uninstall-contract: [0-9]+ passed, 0 failed' /tmp/feat024-run.log \
  || { echo "sin línea de resumen — posible abort a mitad"; exit 1; }

# 2) Cero escrituras fuera del sandbox
touch /tmp/feat024.mark
bash payload/test/uninstall-contract.sh >/dev/null
find /etc /usr/local/bin "$HOME/.ssh" "$HOME/.bashrc.d" \
     -newer /tmp/feat024.mark 2>/dev/null | tee /tmp/feat024-writes.txt
test ! -s /tmp/feat024-writes.txt

# 3) Autoprotección: como root debe abortar (QA-02)
if command -v fakeroot >/dev/null; then
    ! fakeroot bash payload/test/uninstall-contract.sh && echo "ROOT-GUARD-OK"
elif unshare -r true 2>/dev/null; then
    ! unshare -r bash payload/test/uninstall-contract.sh && echo "ROOT-GUARD-OK"
else
    echo "ROOT-GUARD-SKIPPED (ni fakeroot ni userns) — verificar a mano"
fi

# 4) Autoprotección: sandbox no construible (QA-03)
! TMPDIR=/nonexistent-feat024 bash payload/test/uninstall-contract.sh \
  && echo "SANDBOX-GUARD-OK"

# 5) Costuras inertes (QA-24 / QA-25 / QA-28)
# OJO: la copia de referencia tiene que vivir DENTRO de payload/ — install.sh
# sourcea lib/common.sh via $SCRIPT_DIR antes de parsear argumentos, asi que
# ejecutarla desde /tmp muere antes de llegar a --help.
git show main:payload/install.sh > payload/.install-main-ref.sh
diff <(bash payload/.install-main-ref.sh --help) <(bash payload/install.sh --help) \
  && echo "HELP-IDENTICAL"
rm -f payload/.install-main-ref.sh
grep -n 'BIB_UNINSTALL_ROOT=' payload/install.sh   # 2 líneas; la 2ª con BIB_INSTALL_LIB
grep -rn 'BIB_INSTALL_LIB' installer/ payload/ tools/ .github/  # solo install.sh + driver

# 6) Regresión de las suites existentes
bash payload/test/ssh-finalize-decision.sh
bash payload/hooks/tests/run-tests.sh
bash tools/check-no-personal-refs.sh
shellcheck -S warning payload/install.sh payload/lib/common.sh \
  payload/wizard/35-ssh-finalize.sh payload/install/06-bd-cli.sh \
  payload/test/uninstall-contract.sh
bash -n payload/install.sh payload/lib/common.sh payload/test/uninstall-contract.sh
```

**Batería de mutaciones (bloque F).** Se corre una vez, con el árbol limpio
(`git status --porcelain` vacío), antes de abrir la PR. Nota para el
implementador: los `<verify>` de §2 T4 y T5 encadenan `git checkout` al final,
así que el estado de salida del `bash -c` es el del `checkout` y **siempre da
0** — el mismo tipo de comando vacuamente verde que esta FEAT existe para
erradicar. Usar esta versión, que captura el `rc` del driver mutado:

```bash
# mutate "<etiqueta>" "<fichero>" "<expresion sed>"
# Las expresiones van entre comillas SIMPLES: nada de eval, nada de escapes.
mutate() {
    local label="$1" file="$2" expr="$3" rc=0
    git diff --quiet -- "$file" || { echo "ABORT: $file ya esta sucio"; return 2; }
    sed -i "$expr" "$file"
    # Un `sed` que no encaja con nada reporta MISSED sin haber probado NADA —
    # la misma enfermedad de verde-vacuo que esta FEAT existe para matar, un
    # nivel por encima. Dos expresiones de esta batería llegaron obsoletas a la
    # implementacion por esto exactamente (ver nota al pie).
    if git diff --quiet -- "$file"; then
        echo "ABORT: la mutacion no cambio ningun byte de $file (expresion obsoleta)"
        return 2
    fi
    if ! bash -n "$file" 2>/dev/null; then
        git checkout -- "$file"
        echo "ABORT: la mutacion rompio la sintaxis de $file (rojo por el motivo equivocado)"
        return 2
    fi
    bash payload/test/uninstall-contract.sh >/tmp/mut.log 2>&1 || rc=$?
    git checkout -- "$file"
    if [[ "$rc" -ne 0 ]]; then
        echo "MUTATION-CAUGHT  $label"
    else
        echo "MUTATION-MISSED  $label  <-- el driver NO detecta este bug"
        return 1
    fi
}

mutate "QA-29 (#42) 00-conf fuera de paths_to_remove" \
       payload/install.sh   '\#^[[:space:]]*"\${BIB_UNINSTALL_ROOT}/etc/ssh/sshd_config\.d/00-buildersinabox\.conf"$#d'
mutate "QA-30 (#44) patron legacy de bd" \
       payload/lib/common.sh 's/|brain-dump capture CLI//'
mutate "QA-32 propiedad ignorada, borrar siempre" \
       payload/install.sh   's/if bib_path_is_ours "\$_own" "\$_pat"; then/if true; then/'
mutate "QA-33 (#41) perfil borrado sin descargar" \
       payload/install.sh   's/apparmor_parser -R/true -R/'
mutate "QA-34 reload -> restart (lockout)" \
       payload/install.sh   's/systemctl reload ssh.service/systemctl restart ssh.service/'
# Las cinco EJECUTADAS contra el codigo implementado (5/5 MUTATION-CAUGHT, arbol
# limpio despues). Cada una toca exactamente una linea y deja el fichero
# sintacticamente valido; borrar la linea de `apparmor_parser -R` entera
# romperia su continuacion `\`, por eso se sustituye por `true`.
#
# NOTA — dos de estas expresiones nacieron obsoletas y hubo que corregirlas:
# QA-29 anclaba en `.conf$`, pero T2 dejo las rutas entre comillas (la linea
# ahora acaba en `"`), y QA-32 buscaba el `grep -Eq` inline que T1 sustituyo por
# `bib_path_is_ours`. Ninguna cambiaba un solo byte: reportaban MISSED sin haber
# probado nada, y la version anterior de esta seccion afirmaba que estaban
# "comprobadas contra el install.sh de esta rama". No lo estaban. De ahi el
# guard de "0 bytes cambiados" en `mutate()`.
#
# QA-31 (mover el guard SSH detras del teardown de packs), QA-35 (quitar un
# prefijo $BIB_UNINSTALL_ROOT) y QA-36 (meta-mutacion al propio driver) no son
# expresables con un sed de una linea: se aplican a mano, se corre el driver, se
# comprueba que sale rojo POR LA ASERCION indicada en la tabla, y se revierte con
# `git checkout --`. Pegar la salida en la PR.
```

**Post-merge (smoke).** No hay deploy: el artefacto es un test. La verificación
post-merge es (a) el job `lint` de `main` en verde con la línea de resumen del
driver en su log (QA-37), y (b) la pasada manual en hardware que §2 declara
insustituible (R4) — un `--uninstall` real en una caja de usar y tirar,
comprobando `sshd -T` y que `bd`/autologin ajenos siguen ahí.

### Huecos conocidos (asumidos, no a resolver en esta FEAT)

- **Root vs no-root en ficheros ilegibles (E-10).** El driver corre sin
  privilegios, así que un fichero `chmod 000` se clasifica como ajeno; en
  producción, root sí lo lee y podría clasificarlo como nuestro. La divergencia
  es hacia el lado seguro en el test y no se puede cerrar sin root.
- **Lado *install* solo a nivel de predicado** (R3): `06-bd-cli.sh` no se
  ejecuta de verdad. QA-17 cubre el criterio, no el efecto.
- **El gate de autologin del lado install** se decide por la existencia de
  `/etc/profile.d/biab-firstboot.sh` (`install.sh:471-473`), no por marcador:
  fuera de cobertura, tal como declara R3.
- **Sin cobertura del listener vivo** (R4) ni del wizard completo (§2 Alcance).
- **Rutas nuevas en `paths_to_remove` no llevan aserción automática** (R5): si
  alguien añade una ruta, ningún caso de §4 se pone rojo. Queda como TODO
  fechado en la cabecera del driver, igual que decide §2.

---

## 5. Docs

Cubierto por la tarea **T6** de §2: una línea en `CONTRIBUTING.md` con cómo
correr el driver en local, junto a la mención existente de los otros tests, más
el aviso de NO lanzarlo con `sudo` (el driver aborta si `EUID` es 0). No hace
falta documentación de usuario final: nada de esto cambia lo que ve quien
instala la caja.

---

## 6. Feedback

Implementada en PR #52. Para esta FEAT el merge **es** el despliegue: lo que
entrega es un step de CI, no algo que llegue a una caja.

Resultado: `payload/test/uninstall-contract.sh`, 78 aserciones, ~2 s, sin root
ni red ni VM, ejecutándose en el job `lint`. Verificado en el runner, no solo en
local — incluido el caso `sshd -T` real, que comprueba con un sshd de verdad que
antes del uninstall nuestro `00-` fuerza `PasswordAuthentication yes` y después
vuelve a mandar el drop-in de la distro. Esa es la prueba literal del bug de #42.

Desviaciones y correcciones, para quien lea esto después:

- El `<verify>` de T2 topa el diff de `install.sh` en 80 líneas; salieron 93. El
  código son 37 líneas añadidas; el resto es comentario a la densidad del
  fichero. No se recortaron explicaciones para cuadrar el número.
- Dos de los cinco `sed` de la batería de mutaciones de §4 nacieron obsoletos y
  no cambiaban ningún byte — reportaban `MISSED` sin probar nada, y el texto
  afirmaba que estaban comprobados contra esta rama. Corregidos y **ejecutados**
  (5/5 `MUTATION-CAUGHT`), con un guard de "0 bytes cambiados" en `mutate()`.
- E-07 esperaba el literal `the target user` para una cuenta irresoluble; esa
  cadena solo sale cuando `target_user` está vacío. El driver asierta ambos
  subcasos por separado.

Defecto encontrado por el propio driver, en la costura de esta FEAT y no en el
instalador: el for-list del teardown de packs interpolaba el prefijo sin
comillas, así que un prefijo con espacio no encajaba con nada y **se saltaba
todos los teardowns en silencio**. Corregido comillando el prefijo y dejando el
glob final sin comillar; E-13 lo asierta.

Sigue pendiente, sin cambios: el listener sshd vivo solo lo valida la pasada
manual en hardware, misma laguna declarada que FEAT-014.
