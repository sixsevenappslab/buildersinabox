# FEAT-014: SSH seguro por defecto (Tailscale-only sin lockout), y copy honesta

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (launch-blocker — el hook de seguridad es falso en VPS sin esto)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts de dispositivo (bash). Verificación real = pasada E2E en VM con IP "pública" simulada + box detrás de NAT.
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

En un VPS con IP pública, el instalador deja `sshd` escuchando en `0.0.0.0:22` con `PasswordAuthentication yes` (`payload/install/50-ssh.sh`), y el paso que lo cerraría a Tailscale-only (`payload/wizard/35-ssh-finalize.sh`) detecta la sesión SSH entrante por la IP pública y **por defecto elige "keep-current-access"** para no dejar al usuario fuera. Resultado por defecto en VPS: **SSH público con autenticación por contraseña** — brute-forceable, expuesto a internet. En una caja detrás de NAT (mini PC en casa) el problema no se materializa (sin IP pública), pero la landing invita explícitamente a instalar en VPS.

### Intent (why)

El hook de lanzamiento de BIAB es seguridad-primero ("no eres una de las 42.665 cajas expuestas"). Ese claim tiene que ser verdad en TODOS los targets soportados (mini PC, homelab, VPS) ANTES del flip público, o el primer comentario en Show HN será "dices cero puertos públicos pero tu instalador deja SSH con contraseña en 0.0.0.0 en un VPS" — y el hook se vuelve en contra. Es launch-blocker.

### Solucion propuesta

Hacer que el estado seguro (sshd atado a la interfaz de Tailscale, sin listener público con contraseña) sea el **resultado por defecto** en todos los targets, **sin dejar a nadie fuera de su propia caja**. En el caso VPS-conectado-por-IP-pública, en vez de mantener silenciosamente el listener público con contraseña, guiar al usuario a reconectarse por el tailnet antes de cerrar; y si aún no puede, como mínimo **no dejar contraseña sobre interfaz pública** (endurecer a key-only o no completar como "hardened"). Copy pública (README security-model + landing) descrita con precisión, sin absolutos que no se cumplan.

### Historias de usuario

- Como usuario que instala BIAB en un VPS, quiero terminar con SSH accesible solo por mi tailnet (no por la IP pública con contraseña), para no quedar expuesto a fuerza bruta desde internet.
- Como usuario que se conecta por la IP pública durante el install, quiero que el sistema me guíe a reconectarme por Tailscale antes de cerrar el puerto público, para no quedarme fuera de mi propia máquina.
- Como lector de la landing/README, quiero que el claim de seguridad sea preciso, para poder confiar en el resto del producto.

### Requisitos funcionales (EARS)

- [ ] **Ubicuo:** Una vez Tailscale está activo, el sistema shall atar `sshd` a la interfaz de Tailscale (ListenAddress del tailnet) en todos los targets soportados.
- [ ] **Unwanted:** Si al finalizar hay una sesión SSH entrante desde una dirección fuera del tailnet (caso VPS/IP pública), el sistema shall NO mantener silenciosamente un listener público con `PasswordAuthentication yes`; shall guiar a reconectar por el tailnet, y si el usuario mantiene acceso público temporal shall exigir key-only (sin contraseña sobre interfaz pública).
- [ ] **Event-driven:** Cuando el usuario confirma que llega por el tailnet, el sistema shall restringir `sshd` a la ListenAddress de Tailscale y eliminar la exposición pública.
- [ ] **State-driven:** Mientras Tailscale no esté activo, el sistema shall NO reportar/estampar el estado como "hardened" ni prometerlo.
- [ ] **Ubicuo:** El copy público (README "Security model" + landing) shall describir la postura SSH con precisión (bind Tailscale-only; el paso de reconexión en VPS), sin el absoluto "zero public ports" cuando no aplique.

### Requisitos no funcionales

- [ ] Nunca dejar al único admin fuera de su caja (debe existir ruta de recuperación documentada).
- [ ] Idempotente y re-ejecutable (patrón del repo).
- [ ] Sin regresión en el caso mini PC / NAT (hoy ya correcto).
- [ ] Strings de usuario en inglés.

### Growth Notes (Andrea — si aplica)

- **Canal:** el copy de seguridad es el núcleo del hook de Show HN / r/selfhosted. Andrea revisa que el claim preciso siga siendo vendible (que "hardened SSH, tailnet-only" sume en vez de sonar a disclaimer). Métrica: N/A directa (es corrección de credibilidad, no adquisición) — pero es prerequisito del mensaje de seguridad del launch.

---

## 2. Spec Tecnica (Laura)

> Pendiente — spawn sdd-spec-writer.

---

## 3. Boundaries

### Always
- `set -euo pipefail`, idempotente.
- Mantener una ruta de recuperación de acceso siempre (nunca lockout del único admin).
- Copy pública precisa; nada de absolutos incumplibles.
- Centralizar la lógica SSH en los scripts existentes (`50-ssh.sh` / `35-ssh-finalize.sh`), no dispersarla.

### Ask First
- **[DANGER ZONE] Cualquier cambio a `sshd` (config, listener, auth) requiere OK explícito de Jesus antes de merge** — puede dejar una caja inaccesible.
- Cambiar el default de `BIB_SSH_FORCE_TAILSCALE` o el flujo del prompt anti-lockout.
- Desplegar el copy de `site/` (outward-facing, gate de Jesus).

### Never
- Dejar `PasswordAuthentication yes` sobre una interfaz pública (0.0.0.0) como estado final por defecto.
- Lockout del único usuario admin sin ruta de recuperación.
- Abrir puertos nuevos.
- Tocar la ruta de la app de Claude / otras partes fuera de SSH+copy.
- Flip a público dentro de este FEAT.

---

## 4. QA (Pablo)

> Pendiente — spawn sdd-qa después de §2.

---

## 5. Implementacion (Laura)

### Branch
`feat/FEAT-014`

### Decisiones tomadas
- [2026-07-11] Jesus eligió "arreglar código + copy precisa" (no solo suavizar copy): el default seguro se hace verdad antes del flip. Detona porque la landing invita a VPS y el hook es seguridad.

---

## 6. Feedback (Jesus)

—
