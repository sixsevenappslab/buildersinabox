# FEAT-027: Try it in a VM — el camino de prueba sin hardware

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (pre-Show HN, no bloquea el flip)
- **Complejidad:** baja — spec ligera
- **E2E mode:** una pasada real en VM local (la mitad del punto de la FEAT)
- **Depende de:** nada de código; EXEC-015 (amendment 2026-08-19)
- **Fase:** implementacion (R1-R3 hechos; R4 pendiente de pasada real en VM/hipervisor de Jesus)
- **Creado:** 2026-08-19
- **Actualizado:** 2026-08-20 (R1-R3 implementados)
- **Validado por Jesus:** [ ] <!-- la decisión de alcance sí la tomó el 2026-08-18 -->

## Contexto y por qué ahora

El único usuario real (Paco) nunca llegó a configurar la caja. Diagnóstico de
Jesús: la fricción no es la instalación, es **tener un entorno de servidor** y
**vivir en el terminal**. La segunda barrera define la audiencia (el flip la
mide); la primera sí se puede bajar hoy: que cualquiera pruebe BIAB en una VM
en su portátil, sin mini PC, sin VPS, sin tarjeta.

Verificado contra `main` (2026-08-19):

- El orden del wizard ya es correcto para una VM: `10-tailscale-up` sube el
  tailnet **antes** de que `35-ssh-finalize` cierre el `ListenAddress`
  (`payload/wizard/`: 01 → 10 → 35 → 36).
- Ya existe guard anti-lockout para instalaciones sobre SSH (VPS): key-only o
  aviso ruidoso sin cerrar (README §Security, `35-ssh-finalize.sh`).
- **La trampa real es la VM sin consola** (multipass): su `shell` va por SSH,
  y `50-ssh.sh:79` + el ListenAddress del tailnet lo dejan fuera. Dos VMs
  bricked en la auditoría de FEAT-024. Con consola de verdad
  (VirtualBox/UTM/virt-manager/Proxmox), el flujo es idéntico al del monitor
  físico y **ya funciona** — nunca se ha documentado ni verificado como camino.

## 1. Requisitos

- [x] R1 — WHEN un visitante sin hardware lee el README, THE SYSTEM SHALL
      ofrecerle un camino "Try it in a VM first" con hipervisores concretos
      (VirtualBox, UTM, virt-manager/Proxmox) y el tiempo esperado.
      → `README.md` §"No spare hardware? Try it in a VM first" + línea en
      `site/index.html`.
- [x] R2 — WHEN la instalación corre dentro de una sesión SSH sin tailnet
      activo, THE SYSTEM SHALL avisar antes de tocar sshd de que esta
      instalación recorta el SSH de LAN, recomendar consola, y pedir
      confirmación explícita (`BIB_SSH_INSTALL_ACK=1` o prompt tty).
      Cubre multipass Y el instalador curioso en su servidor de LAN.
      → `payload/lib/common.sh:check_ssh_install_preflight`, llamado desde
      `payload/install.sh` justo tras `require_supported_os` (salvo
      `--skip-wizard`, que nunca corre `35-ssh-finalize.sh` y no tiene nada
      que proteger). Falla cerrado (sin tty y sin ack → aborta, cero
      cambios). Detección de sesión SSH vía `ss -Htn state established` como
      fallback — `SSH_CONNECTION`/`SSH_TTY` no sobreviven a `sudo` con
      `env_reset` en el one-liner real `curl | sudo bash` (bug encontrado y
      corregido en code-review antes de mergear).
- [x] R3 — multipass se declara **no soportado** en README y en el aviso de
      R2 (no se arregla: mantener SSH de LAN abierto rompería el modelo de
      seguridad que es el titular).
- [ ] R4 — el camino VM completo (curl → wizard → Claude desde el móvil vía
      tailnet → `--uninstall`) se ejecuta UNA vez de verdad y lo observado se
      anota en esta spec antes de completarla. **Pendiente — requiere que
      Jesus la corra con un hipervisor real (VirtualBox/UTM/virt-manager);
      no ejecutable desde este entorno.**

## 2. Spec técnica (esbozo — spec ligera)

| Fichero | Cambio |
|---|---|
| `README.md` | Sección "No spare hardware? Try it in a VM" tras Requirements: 3 hipervisores con consola, RAM/disco mínimos, nota multipass, y "a €4 VPS also works" |
| `payload/install.sh` | Preflight R2: si `SSH_CONNECTION`/`SSH_TTY` presentes y `tailscale status` no responde → bloque de aviso + confirmación. Reutilizar el patrón del prompt de `do_uninstall` (`BIB_PROMPT_INPUT`) |
| `payload/test/uninstall-contract.sh` o test propio | Aserción del preflight: con `SSH_CONNECTION` sembrada y sin ack → exit no-cero antes de tocar nada; con ack → sigue |
| `site/index.html` | Una línea en el hero-secundario: "no hardware? try it in a VM" (no más) |

**Fuera de alcance (Never):** cambiar el modelo sshd/ListenAddress; soportar
multipass; imágenes de VM preconstruidas (OVA/qcow2); cualquier GUI.

**Timebox:** 1-2 días incluida la pasada real. Si la pasada real descubre más
de un fix, los extras van a issues post-flip, no a esta FEAT.

## 3. Boundaries

- **Always:** la pasada real de R4 antes de mover a completed; el aviso R2
  falla cerrado (sin tty y sin ack → aborta).
- **Ask first:** cualquier cambio en `50-ssh.sh`/`35-ssh-finalize.sh` más
  allá de *añadir* el preflight (danger zone sshd).
- **Never:** debilitar el cierre tailnet-only; retrasar el flip por esta FEAT
  (si el día del flip llega antes, se lanza sin ella).

## 4. QA (mínimo)

1. [x] Preflight: sesión con `SSH_CONNECTION` sembrada, sin tailnet, sin ack →
   aborta con el aviso, exit no-cero, cero cambios en disco.
   → `payload/test/ssh-install-preflight.sh` escenario 4 (+ escenario 5 para
   `NON_INTERACTIVE=1`).
2. [x] Preflight: mismo caso con `BIB_SSH_INSTALL_ACK=1` → continúa.
   → escenario 3.
3. [x] Preflight: consola limpia (sin vars SSH) → ni aviso ni prompt.
   → escenario 1 (+ escenario 2: SSH con tailnet ya arriba → tampoco avisa).
4. [ ] Pasada viva (R4): VM VirtualBox o virt-manager, Ubuntu Server 24.04 →
   curl → wizard parte A en consola → SSH por tailnet desde el móvil →
   `/tutorial` arranca → `--uninstall` deja la VM limpia. Cronometrar: el
   número real sustituye al "~15 min" del README si difiere. **Pendiente,
   requiere hardware/hipervisor real.**
5. [x] Regresión: `wiring-smoke.sh` (claude/antigravity/codex),
   `uninstall-contract.sh`, `ssh-finalize-decision.sh`, personal-refs guard,
   shellcheck — todos en verde localmente antes del PR.

## 5. Docs

README (R1), SECURITY.md si el aviso R2 introduce texto nuevo de lockout,
LAUNCH-PLAN §4: el cuerpo del Show HN gana la línea "try it in a VM first".
