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
- **Fase:** requisitos
- **Creado:** 2026-08-15
- **Actualizado:** 2026-08-15
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
- [ ] Investigacion previa rellenada con rutas reales verificadas — **parcial**: rutas
      verificadas con `ls`, pero §2 la debe completar `sdd-spec-writer`
- [ ] Tabla "Archivos afectados" completa
- [ ] Minimo 1 `<task>` con `<verify>` ejecutable y `<done>` observable
- [ ] Patron de codigo con fragmento real del proyecto
- [ ] Criterios de aceptacion globales verificables
- [ ] Presupuesto de ejecucion revisado

### QA (§4) — owner Pablo
- [ ] Minimo 1 caso funcional con pasos numerados
- [ ] Minimo 1 edge case
- [ ] Minimo 1 item de regresion
- [ ] Bloque `Criterios de testing` con comandos ejecutables

### Growth (§1.Growth Notes) — owner Andrea
- [x] N/A — internal engineering quality, no growth surface.

> **DoR incompleta a proposito.** §1 y §3 estan listos. §2 y §4 los deben rellenar
> `sdd-spec-writer` y `sdd-qa`. No promover a `active/` hasta entonces.

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

> **Pendiente.** Rellenar con `sdd-spec-writer`. Notas de investigación previa ya
> verificadas para no repetir el trabajo:

### Investigacion previa (preliminar, verificada con `ls`/`grep`)

- **Patron existente a copiar:** `payload/test/ssh-finalize-decision.sh` (23 KB).
  Mockea `ss`, `tailscale`, `sshd` y `systemctl` vía `PATH`, redirige el state
  file y el dir de drop-ins a temp dirs, y sourcea `35-ssh-finalize.sh` como
  librería mediante `BIB_SSH_FINALIZE_LIB=1` (ver `35-ssh-finalize.sh:583-585`).
  No toca sshd real y no necesita root — corre en un runner normal.
- **Bloqueo conocido:** `payload/install.sh` **no tiene** un hook equivalente.
  `do_uninstall` no se puede sourcear sin ejecutar el script. Hará falta añadir
  un guard del mismo estilo (`BIB_INSTALL_LIB=1`) o extraer la lógica de
  propiedad a `payload/lib/common.sh`. Esta es la decisión de diseño principal
  de §2.
- **Duplicación a resolver de paso:** `_authorized_keys_present()` existe en
  `35-ssh-finalize.sh:147-150` y su regex está copiada inline en el guard nuevo
  de `do_uninstall`. Moverla a `lib/common.sh` da una sola definición para el
  test y para ambos usos.
- **Wiring de CI:** añadir junto a `.github/workflows/ci.yml:53-54`
  (`bash payload/test/ssh-finalize-decision.sh`), dentro del job `lint`.
- **Dependencias:** ninguna nueva.

### Alcance

#### Incluye

- El driver `payload/test/uninstall-contract.sh` y su wiring en CI.
- El hook mínimo en `payload/install.sh` que permita sourcear `do_uninstall`.

#### NO incluye (OBLIGATORIO)

- **No arreglar bugs.** Las PRs #41–#44 ya los arreglan; esta FEAT solo los
  convierte en aserciones. Si el driver descubre uno nuevo, se abre otra FEAT.
- **No testear el wizard completo** (`01-set-password`, `40-scaffold`, OAuth).
  Es tentador y es un epic. Esta FEAT cubre solo el contrato de propiedad de
  install/uninstall.
- **No sustituir la pasada manual en hardware.** El driver no valida el efecto
  sobre el listener vivo, igual que declara `ssh-finalize-decision.sh`.
- **No refactorizar** `do_uninstall` más allá del hook necesario para testearlo.

### Archivos afectados

| Archivo | Accion |
|---------|--------|
| `payload/test/uninstall-contract.sh` | CREAR |
| `payload/install.sh` | MODIFICAR (hook de librería) |
| `payload/lib/common.sh` | MODIFICAR (mover `_authorized_keys_present`) |
| `.github/workflows/ci.yml` | MODIFICAR (un step en `lint`) |

### Tareas

> Pendiente — `sdd-spec-writer`.

---

## 3. Boundaries

### Always

- Correr sin root y contra temp dirs. Ninguna aserción puede depender de tocar
  `/etc`, `/usr/local/bin` ni `~/.ssh` reales del host o del runner.
- Cada caso del driver debe corresponder a un defecto real observado el
  2026-08-14, y citarlo en un comentario. Sin tests inventados "por cobertura".

### Ask First

- Añadir un job nuevo a CI en vez de un step al job `lint` (coste de minutos).
- Cualquier refactor de `do_uninstall` que vaya más allá del hook de librería.
- Extender el alcance al wizard completo.

### Never

- Modificar el comportamiento del instalador dentro de esta FEAT. Es una FEAT de
  verificación; si un test falla, la corrección va en su propia PR.
- Escribir tests que necesiten una VM o red en CI.
- Tocar `firestore.rules` ni configuraciones de seguridad (no aplica aquí, pero
  la regla del repo se mantiene).

---

## 4. QA (Pablo)

> **Pendiente.** Rellenar con `sdd-qa`.
>
> Semilla: los casos ya ejercitados a mano el 2026-08-14 y que el driver debe
> reproducir — `sshd -T` antes/después del uninstall; `bd` legacy sin marcador;
> `bd` ajeno; fichero ajeno que solo *menciona* el producto; `authorized_keys`
> con solo comentarios; abort dejando intacto el teardown de packs; autologin
> ajeno intacto en install y en uninstall.

---

## 5. Docs

> Pendiente. Como mínimo: nota en `CONTRIBUTING.md` sobre cómo correr el driver
> en local, junto a la mención existente de los otros tests.

---

## 6. Feedback

> Vacío hasta después del deploy.
