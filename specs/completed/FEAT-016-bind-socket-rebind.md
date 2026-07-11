# FEAT-016: BIND reabre el socket público (cerrar el residual 0.0.0.0 sin esperar reboot)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** media (pre-flip — cerrar antes del flip público; no bloquea FEAT-015 ni el resto)
- **Complejidad:** baja-media
- **E2E mode:** none
- **Reconciliation owner:** sdd-coordinator
- **Fase:** tecnica
- **Creado:** 2026-07-11
- **Actualizado:** 2026-07-11
- **Validado por Jesus:** [ ]

## 1. Requisitos (Elena)

### Problema

La re-E2E de FEAT-014 (2026-07-11) confirmó que `systemctl reload` (SIGHUP) **no reabre los sockets de escucha de sshd**: tras BIND vía reload, `sshd -T` ya refleja `ListenAddress <tailnet_ip>` pero `ss` sigue mostrando `0.0.0.0:22` — el corte de exposición pública a nivel de socket **se consolida solo en el siguiente reboot**. Los cambios de auth (password-off de HOLD-HARDENED) sí son inmediatos.

### Intent (why)

FEAT-014 se mergeó con este residual aceptado como follow-up (decisión Jesus 2026-07-11): es un avance neto de seguridad y el hueco es estrecho. Pero para un producto con hook de seguridad hay que cerrarlo ANTES del flip público. Caso afectado: **VPS operado solo por consola web** (sin sesión SSH) → va a BIND → restaura `password=yes` → deja `0.0.0.0:22` con contraseña hasta el próximo reboot. Es justo lo que un comentarista de HN buscaría.

### Solución propuesta

Que la ruta BIND cierre la exposición pública a nivel de socket de forma inmediata, **sin lockout**. Opciones a evaluar en §2 (Laura): (a) en BIND —que por definición ocurre SIN peer externo activo— un `restart` controlado es aceptable (no hay sesión externa que matar; las sesiones tailnet reconectan); (b) forzar rebinding de sockets de otra forma; (c) doble binario/ssh-socket. Requisito: tras BIND, `ss -tlnp | grep :22` NO debe mostrar `0.0.0.0` — solo la IP tailnet, inmediatamente, sin dejar al usuario fuera.

### Requisitos funcionales (EARS)

- [ ] **Event-driven:** Cuando el sistema entra en BIND, shall dejar `sshd` escuchando SOLO en la IP tailnet a nivel de socket de forma inmediata (no diferido a reboot).
- [ ] **Unwanted:** Si cerrar el socket público implicara cortar la única vía de acceso del operador, el sistema shall NO hacerlo sin ruta de recuperación (mantener la garantía anti-lockout de FEAT-014).
- [ ] **Ubicuo:** El comportamiento de HOLD-HARDENED / HOLD-OPEN / auth de FEAT-014 shall permanecer intacto.

### Boundaries
- **Always:** preservar la garantía anti-lockout de FEAT-014; re-verificar `tailscale ip -4` == IP bindeada **y** `sshd -t` en el instante JUSTO anterior al restart; degradar con `warn` si `ss` no existe.
- **Ask First:** [DANGER ZONE] cualquier `restart` de sshd — confirmar el análisis de que en BIND no hay sesión externa que proteger. **Requiere OK explícito de Jesus + E2E en caja real antes de merge.**
- **Never:** reintroducir el fallback a `restart` en paths con sesión externa viva (el bug que FEAT-014 cerró); restart en la ruta FORCE (rompe "revertible mientras conectado"); restart en `_sshd_check_and_reload`; restart si la interfaz tailnet no está arriba; lockout sin recuperación.

## 2. Spec Técnica (Laura)

### 2.0 Investigación (mecanismo verificado)

**El residual, confirmado en la re-E2E de FEAT-014 (2026-07-11):**
`systemctl reload ssh.service` envía SIGHUP a sshd. sshd re-lee su config (por eso
`sshd -T` refleja de inmediato `ListenAddress <tailnet_ip>` y el `password no` de
HOLD-HARDENED), **pero NO vuelve a hacer `bind()` de sus sockets de escucha**. El
socket público `0.0.0.0:22` que ya estaba abierto persiste en el kernel hasta el
siguiente arranque, cuando systemd relanza sshd y hace `bind()` sobre la
`ListenAddress` nueva. Verificado en caja: `sshd -T` correcto pero
`ss -tlnp` sigue mostrando `0.0.0.0:22`.

**Formato verificado de `ss` en esta caja** (necesario para el parser):
- Escucha: `ss -tlnH 'sport = :22'` → `LISTEN 0 4096 0.0.0.0:22 0.0.0.0:*` y
  `LISTEN 0 4096 [::]:22 [::]:*`. La **columna 4** es `Local Address:Port`.
- Peers establecidos (ya usado por `_ssh_peer_addrs`): `ss -Htn state established
  '( sport = :22 )'` → `0 0 <local>:22 <peer>:<port>`, columna 4 = peer.

**Por qué es tratable sin lockout — el invariante clave:** BIND (la ruta no-FORCE)
sólo se alcanza cuando `_external_ssh_peer` está **vacío** (ver
`ssh_finalize_decide`, líneas ~421-429). Es decir, por construcción **no existe
ninguna sesión SSH externa (no-tailnet) que dependa del listener público**.
Sub-casos dentro de BIND:
- (a) **Sin sesión SSH alguna** (NAT / mini PC por consola física / VPS por consola
  web del proveedor / FORCE) → no hay nada que cortar al cerrar el socket.
- (b) **Sólo sesiones tailnet** (un peer entrante por la tailnet fue justo lo que
  probó la alcanzabilidad) → reconectan sobre una tailnet ya probada arriba.

En ninguno de los dos un `restart` de sshd puede dejar fuera a un operador
externo — no hay ninguno. Ese es el crux que justifica el DANGER ZONE.

**Rechazadas:** (c) ssh-socket / doble binario — reintroduce la activación por
socket que `50-ssh.sh` deshabilita a propósito (rompería `ListenAddress`).
Forzar rebind vía `ss -K` (kill de sockets) no re-abre en la nueva dirección y es
frágil. La opción limpia es el `restart` controlado bajo guardas.

### 2.1 Diseño: escalada de rebind del socket + guardas

Tras un **reload exitoso** en `_ssh_bind_tailnet` (config ya validada y aplicada,
`ssh_finalized` estampado), y **sólo** si la llamada opta explícitamente a ello
(`allow_socket_rebind=1`, ver 2.1.2), invocar `_rebind_public_socket`:

1. Si `ss` no está disponible → `warn` y salir (el reboot estrecha el socket).
2. `_public_listener_present`: parsear `ss -tlnH 'sport = :22'`; si algún listener
   local es wildcard (`0.0.0.0` / `*` / `[::]`) o cualquier dirección
   **no-tailnet** no-loopback → hay socket público residual. Si sólo hay
   direcciones tailnet (`100.64/10`, `fd7a:115c:a1e0::/48`) o loopback → no hay
   nada que cerrar, salir (no-op idempotente).
3. **Guardas anti-lockout, re-evaluadas JUSTO antes del restart** (invariante
   FEAT-014):
   - `tailscale ip -4` sigue devolviendo **la misma** IP que bindeamos → la
     interfaz tailnet está arriba y `bind()` tendrá éxito. Nunca reiniciar hacia
     una config que no podría bindear (evita el lockout EADDRNOTAVAIL).
   - `sshd -t` sigue pasando.
   - Si **cualquiera** falla → **NO** reiniciar; conservar el estado aplicado por
     reload (diferido a reboot) y `warn`.
4. `systemctl restart ssh.service`. Éxito → `log`. Fallo → `warn` (el reboot
   estrecha el socket). Nunca cambia `BIB_SSH_STATE` ni desestampa `ssh_finalized`
   (es best-effort sobre un BIND ya consolidado).

Red de recuperación (ya existente, se referencia, no se toca): el drop-in de
ordenación de arranque `_install_ssh_boot_ordering`
(`10-buildersinabox-tailscale-wait.conf`) hace `After=tailscaled`, `ExecStartPre`
espera ≤60 s a que aparezca la IP tailnet, y `Restart=on-failure` — cubre un
`bind()` que aún compita en el arranque.

#### 2.1.1 Justificación de la seguridad del `restart` (crux del DANGER ZONE)

El modelo "reload, nunca restart" existe porque un restart tira TODAS las sesiones
vivas, incluida la pública que el operador podría estar usando → lockout (el bug
que FEAT-014 cerró). Aquí el restart es aceptable **exclusivamente** porque la
ruta que lo dispara (BIND no-FORCE) tiene demostrado `_external_ssh_peer` vacío:
no hay sesión externa que tirar. Las sesiones tailnet (caso b) reconectan sobre
una tailnet ya probada. `_sshd_check_and_reload` se deja **intacta**: sigue sin
reiniciar nunca en sus rutas de fallo de reload.

#### 2.1.2 Decisión sobre la ruta FORCE

`BIB_SSH_FORCE_TAILSCALE=1` es un "blind bind": puede ejecutarse mientras el
operador ESTÁ en una sesión pública que está migrando. La cabecera del script
documenta que se usa `reload` (no `restart`) precisamente para que un FORCE
equivocado siga siendo **reversible mientras se está conectado**. Un `restart`
rompería esa garantía.

**Decisión (la conservadora):** la escalada de rebind se limita a la ruta **BIND
no-FORCE** (`allow_socket_rebind=1`). FORCE mantiene `reload`-only
(`allow_socket_rebind=0`); su socket público se estrecha en el siguiente reboot.
Se descartó la alternativa "escalar en FORCE si `_external_ssh_peer` está vacío":
aunque también es segura frente a sesiones *externas*, un FORCE lanzado desde una
sesión **tailnet** dejaría `_external_ssh_peer` vacío y el restart tiraría esa
sesión — y como FORCE no verifica alcanzabilidad (blind), no hay prueba de que
reconecte. Preservar verbatim la propiedad "revertible mientras conectado" de
FORCE pesa más que cerrar el socket sin reboot en un camino de escape avanzado y
poco frecuente.

### 2.2 Archivos afectados

| Archivo | Cambio |
|---------|--------|
| `payload/wizard/35-ssh-finalize.sh` | +`_public_listener_present`, +`_rebind_public_socket`; `_ssh_bind_tailnet` acepta `allow_socket_rebind` y lo invoca en el éxito; `ssh_finalize_decide` pasa `1` en la ruta sin peer externo y `0` en FORCE; cabecera actualizada (BIND + FORCE). |
| `payload/install/50-ssh.sh` | Quitar el fallback `\|\| systemctl restart ssh.service` (línea ~86): en install el operador puede venir por `curl\|sudo bash` SOBRE ssh y un restart tiraría su sesión. Pasa a `reload \|\| warn` + comentario. `enable --now` ya arrancó el servicio. |
| `payload/test/ssh-finalize-decision.sh` | Mock `ss` responde a las dos consultas (established/listening); mock `tailscale ip -4` devuelve `MOCK_TAILSCALE_IP`; +`set_ss_listen`; +5 escenarios (11-15). |

### 2.3 Plan de tareas (waves)

- **Wave 1 — wizard fix.** Añadir helpers + wiring en `35-ssh-finalize.sh`.
  - `verify:` `bash -n payload/wizard/35-ssh-finalize.sh && shellcheck -S warning payload/wizard/35-ssh-finalize.sh`
  - `done:` `_ssh_bind_tailnet` llama a `_rebind_public_socket` sólo con `allow_socket_rebind=1`; FORCE pasa `0`; `_sshd_check_and_reload` sin cambios.
- **Wave 2 — install fix.** Quitar el fallback a restart en `50-ssh.sh`.
  - `verify:` `bash -n payload/install/50-ssh.sh && shellcheck -S warning payload/install/50-ssh.sh && ! grep -q 'restart ssh.service' payload/install/50-ssh.sh`
  - `done:` sólo queda `reload || warn`, con comentario del porqué.
- **Wave 3 — tests.** Extender el driver con escenarios 11-15.
  - `verify:` `bash payload/test/ssh-finalize-decision.sh`
  - `done:` todos los asserts (incl. los previos) en verde; se prueba restart-cuando-residual, no-restart-si-guarda-falla, no-restart-si-sólo-tailnet, FORCE-reload-only, y ss-ausente.
- **Wave 4 — E2E real (pre-merge, fuera de CI).** Ver 2.4 / §3. No se puede automatizar aquí.

### 2.4 Análisis anti-lockout

| Situación | Ruta | ¿Restart? | ¿Riesgo de lockout? |
|-----------|------|-----------|---------------------|
| BIND, sin sesión (NAT/consola/web) | no-FORCE, peer vacío | Sí, si hay socket público residual y guardas OK | No — no hay sesión que tirar |
| BIND, sólo sesión tailnet | no-FORCE, peer vacío | Sí (guardas OK) | No — reconecta sobre tailnet probada |
| BIND pero IP tailnet desaparece justo antes del restart | no-FORCE | **No** (guarda falla) | No — se conserva el estado por reload; el socket se estrecha en reboot |
| BIND pero `sshd -t` falla justo antes | no-FORCE | **No** (guarda falla) | No — igual que arriba |
| Socket ya tailnet-only | no-FORCE | No (no-op) | No |
| `ss` ausente | no-FORCE | No (warn) | No — reboot estrecha |
| Sesión externa presente | HOLD-HARDENED / HOLD-OPEN | No (ni bind ni restart) | Intacto (FEAT-014) |
| FORCE (blind) | FORCE | **No** (reload-only) | Reversible mientras conectado (preservado) |
| Fallo de reload / `sshd -t` en el bind | revert | No | Listener corriendo intacto |

Invariante preservado: **el restart sólo ocurre en la ruta donde está demostrado
que no hay peer externo, y sólo si la tailnet sigue arriba y `sshd -t` pasa en el
instante previo**. Nunca se reintroduce restart en `_sshd_check_and_reload` ni en
ninguna ruta con sesión externa viva.

## Notas
- Ver evidencia en la re-E2E: `scratchpad/feat014-e2e2.md` (histórico de sesión) y §5 de FEAT-014 completado.
- TODO relacionado ya anotado: el fallback `|| systemctl restart` de `50-ssh.sh` (preexistente) pendiente de quitar — puede agruparse aquí.

## 5. E2E (caja real) — PASS 2026-07-11

VM multipass `biab-016-e2e` (Ubuntu 24.04), branch `feat/FEAT-016`, Tailscale real (login Jesús, IP tailnet 100.78.25.78), `tailscale set --ssh=false` para testear sshd directo. Red de recuperación previa confirmada (recovery_key por tailnet + `biab-reset-ssh.sh`).

**Test central (BIND con socket rebind, white-box `_ssh_bind_tailnet <ip> 1` desde sesión tailnet — el path exacto con `allow_socket_rebind=1`):**
- BEFORE: `ss :22` = `0.0.0.0:22` + `[::]:22` (público), sshd MainPID 986.
- Log: "restarted ssh.service to release the lingering public :22 socket (now tailnet-only; no external session existed to drop)". rc=0.
- AFTER: sshd MainPID **11807** (restart real, vs FEAT-014 donde el reload dejaba 986), `ss :22` = **SOLO `100.78.25.78:22`** (tailnet-only, sin 0.0.0.0/[::]) **al instante** (el residual de FEAT-014 se consolidaba solo en reboot). `sshd -T listenaddress` = tailnet. BIB_SSH_STATE=BIND.
- **Sesión tailnet SOBREVIVIÓ al restart** (confirma `KillMode=process` + scope logind → el operador no se cae). La decisión BIND-vs-HOLD ya está cubierta por 53 unit tests + E2E FEAT-014; aquí se valida el mecanismo nuevo (restart suelta el socket), único desconocido empírico. El peer del bridge multipass (10.252.198.1, externo persistente) impedía el path no-FORCE por el wizard completo, de ahí la invocación white-box del path real.

**Regresión reboot (BUG 2 de FEAT-014 no reintroducido):** caja en BIND → `systemctl reboot` → alcanzable por tailnet en segundos, `ss :22` = solo `100.78.25.78:22`, **0 fallos de bind** (EADDRNOTAVAIL) en el journal de boot. Boot-ordering (`10-*-tailscale-wait`) intacto.

**Veredicto:** el socket público se cierra al instante en BIND sin lockout ni caída de sesión. Pendiente solo el OK explícito de Jesús (danger zone) para mergear PR #22.
