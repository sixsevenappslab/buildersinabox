# FEAT-016: BIND reabre el socket público (cerrar el residual 0.0.0.0 sin esperar reboot)

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** media (pre-flip — cerrar antes del flip público; no bloquea FEAT-015 ni el resto)
- **Complejidad:** baja-media
- **E2E mode:** none
- **Reconciliation owner:** sdd-coordinator
- **Fase:** requisitos
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
- **Always:** preservar la garantía anti-lockout de FEAT-014; `sshd -t` antes de aplicar.
- **Ask First:** [DANGER ZONE] cualquier `restart` de sshd — confirmar el análisis de que en BIND no hay sesión externa que proteger.
- **Never:** reintroducir el fallback a `restart` en paths con sesión externa viva (el bug que FEAT-014 cerró); lockout sin recuperación.

## 2. Spec Técnica (Laura)
> Pendiente.

## Notas
- Ver evidencia en la re-E2E: `scratchpad/feat014-e2e2.md` (histórico de sesión) y §5 de FEAT-014 completado.
- TODO relacionado ya anotado: el fallback `|| systemctl restart` de `50-ssh.sh` (preexistente) pendiente de quitar — puede agruparse aquí.
