# FEAT-014: SSH seguro por defecto (Tailscale-only sin lockout), y copy honesta

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta (launch-blocker — el hook de seguridad es falso en VPS sin esto)
- **Complejidad:** media
- **E2E mode:** none
  > Scripts de dispositivo (bash). Verificación real = pasada E2E en VM con IP "pública" simulada + box detrás de NAT.
- **Reconciliation owner:** sdd-coordinator
- **Fase:** qa
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
- [x] Investigacion previa con rutas verificadas
- [x] Tabla archivos afectados
- [x] ≥1 task con verify/done
- [x] Patron de codigo real
- [x] Criterios globales verificables

### QA (§4) — owner Pablo
- [x] ≥1 funcional + ≥1 edge + ≥1 regresion
- [x] Criterios de testing ejecutables

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

### Investigacion previa (rutas verificadas)

- `payload/install/50-ssh.sh` — instala `openssh-server`, genera host keys si faltan, escribe el drop-in base `/etc/ssh/sshd_config.d/00-buildersinabox.conf` (`PasswordAuthentication yes`, `KbdInteractiveAuthentication yes`, `PermitRootLogin prohibit-password`, `PubkeyAuthentication yes`) y conmuta de `ssh.socket` a `ssh.service` (necesario para que un futuro `ListenAddress` tenga efecto). **El listener queda en `0.0.0.0:22` con contraseña.** No hace bind al tailnet.
- `payload/wizard/35-ssh-finalize.sh` — corre tras `tailscale up` (10-tailscale-up.sh). Prepara `~/.ssh/authorized_keys` (vacío; la importación real es en /tutorial Beat 2). Obtiene `tailscale ip -4`. Helper `_is_tailnet_addr` reconoce CGNAT `100.64.0.0/10` e IPv6 `fd7a:115c:a1e0::/48`. Helper `_ssh_peer_addrs` lista peers de sesiones SSH establecidas (`ss -Htn state established '( sport = :22 )'`). Si hay un peer **externo** (fuera del tailnet) y `BIB_SSH_FORCE_TAILSCALE!=1`, hoy **por defecto elige `keep-current-access`**: NO ata el listener, NO endurece, y estampa `phase_done "ssh_finalized"`. Si procede, escribe `01-buildersinabox-tailscale.conf` con `ListenAddress ${tailscale_ip}`, valida `sshd -t` y hace `reload` (las sesiones vivas sobreviven).
- `payload/skills/tutorial/SKILL.md` Beat 2 — tras `gh auth status` verde, importa `gh api /user/keys` a `~/.ssh/authorized_keys` (idempotente, `grep -Fqx`). Es el momento en que el target user pasa a tener una credencial de clave. Ocurre **después** del wizard.
- `payload/lib/common.sh` — `phase_done <name>` escribe `.phases.<name>=true` en `state.json`; `phase_is_done`, `state_get`, `log/warn/die`, `require_root`. `payload/lib/prompt.sh` — `prompt_header`, `prompt_choice` (default = 1ª opción, valor en `BIB_PROMPT_VALUE`, retorna !=0 en EOF).
- `README.md` §"Security model" (líneas 89-96) y `site/index.html` (línea 74 hero, línea 82 note) — hoy afirman **"Zero public ports"** en absoluto, falso durante la ventana VPS.
- Test infra: `payload/test/dryrun.sh` + `payload/test/wiring-smoke.sh` (hermético, `BIB_OAUTH_MOCK=1`; **no** ejercita 35-ssh-finalize). CI (`.github/workflows/ci.yml`) = shellcheck `-S warning` + `bash -n` + guard de refs personales + archive-cleanliness. La verificación real de sshd es **manual en VM (multipass)**, como ya se hace para FEAT-013 CP-02.

### Diseño elegido (anti-lockout)

**Invariante de seguridad:** nunca eliminar la última credencial funcional del único admin sobre su último camino funcional. El riesgo de lockout NO viene de endurecer *auth* (métodos), sino de cambiar el *ListenAddress* (qué interfaz escucha). Se separan las dos palancas.

`35-ssh-finalize.sh` decide entre **tres estados** (solo cuando hay `tailscale_ip`; en `BIB_OAUTH_MOCK=1` se salta igual que hoy):

1. **BIND (seguro — default cuando es seguro).** Se dispara si (i) **no hay ninguna sesión SSH externa** (caso NAT/mini PC, o VPS operado desde la consola web del proveedor — `_ssh_peer_addrs` vacío), **o** (ii) **existe una sesión entrante desde el tailnet** (prueba positiva de que el usuario ya alcanza la caja por Tailscale — VPS ya reconectado, o app de Claude conectada por el tailnet). → escribe `01-buildersinabox-tailscale.conf` (`ListenAddress ${tailscale_ip}`), **elimina** el drop-in de endurecimiento público si existía (para que el listener tailnet vuelva a aceptar contraseña, que es el modelo documentado para clientes de móvil), `sshd -t` + `reload`, y estampa `ssh_finalized`. Exposición pública eliminada.

2. **HOLD-HARDENED (seguro-suficiente — VPS con solo sesión pública pero con clave usable).** La única sesión es externa **y** `~/.ssh/authorized_keys` del target user **no está vacío**. → escribe `02-buildersinabox-public-hardening.conf` con `PasswordAuthentication no` + `KbdInteractiveAuthentication no` (el listener sigue en `0.0.0.0`, pero **key-only → no brute-forceable**). Imprime instrucciones de reconectar por el tailnet + re-run `BIB_SSH_FORCE_TAILSCALE=1`. **No** ata todavía (sin lockout: el usuario conserva su clave sobre el camino público). Estampa `ssh_public_hardened` pero **NO** `ssh_finalized`, para que el re-run complete el BIND.

3. **HOLD-OPEN (VPS con solo sesión pública y SIN clave usable — la contraseña es la única credencial).** `authorized_keys` vacío (típico durante el wizard, pre-Beat-2). Deshabilitar contraseña dejaría al usuario sin ninguna credencial → **no se toca auth**. Se mantiene contraseña + listener público, pero **NO se estampa como securizado**; se imprime aviso prominente + comandos exactos de reconexión/FORCE. Es la única ventana con exposición residual: explícita, corta y cerrada automáticamente en Beat 2.

**Cierre automático del bucle (Beat 2).** Tras importar las GitHub keys, /tutorial dispara `sudo BIB_SSH_FORCE_TAILSCALE=1 …/35-ssh-finalize.sh` si la caja no está `ssh_finalized`. En Beat 2 el usuario ya opera por el tailnet (app de Claude) → normalmente cae en **BIND** y queda securizado sin intervención. Si aún así no hay sesión tailnet, ahora al menos hay clave → HOLD-HARDENED (key-only, no expuesto a fuerza bruta).

**Semántica de `BIB_SSH_FORCE_TAILSCALE=1`** (escape hatch / recuperación): salta el prompt y ata al tailnet (comportamiento actual). Se mantiene `reload` (no `restart`) para que la sesión activa sobreviva: si el usuario forzó por error y el tailnet no enruta, lo detecta **mientras sigue conectado** y puede revertir. La ruta de recuperación se documenta (abajo).

**Por qué este diseño y no alternativas:** atar siempre al tailnet aunque el usuario venga por la IP pública (opción más simple en código) se rechaza por violar el invariante — si su cliente no enruta el tailnet, lockout. Endurecer a key-only siempre se rechaza porque durante el wizard el usuario puede no tener clave (import en Beat 2). El diseño de 3 estados es el mínimo que hace *seguro-por-defecto* cada target sin ninguna ruta de lockout: NAT y consola-VPS → BIND; VPS-por-SSH con clave → key-only inmediato; VPS-por-SSH sin clave → ventana explícita y auto-cerrada en Beat 2.

### Archivos afectados

| Archivo | Cambio |
|---------|--------|
| `payload/wizard/35-ssh-finalize.sh` | **[DANGER ZONE]** Máquina de estados BIND/HOLD-HARDENED/HOLD-OPEN; gate de presencia de clave; drop-in `02-…-public-hardening.conf`; estampado diferenciado (`ssh_finalized` vs `ssh_public_hardened`); mensajes de reconexión+recuperación. |
| `payload/skills/tutorial/SKILL.md` | Beat 2: tras import de keys, hook `BIB_SSH_FORCE_TAILSCALE=1` re-run si `!ssh_finalized`; copy del cierre. |
| `payload/install/50-ssh.sh` | Solo comentario de cabecera (modelo de seguridad actualizado). Sin cambio funcional del drop-in base. |
| `README.md` | §"Security model": sustituir el absoluto "Zero public ports" por postura precisa (tailnet-bound end state; key-only durante setup en VPS). |
| `site/index.html` | Hero (línea 74) + note (línea 82): wording preciso sin absoluto incumplible. |
| `payload/tutorial/desktop-readme.md` / `SECURITY.md` | Documentar ruta de recuperación (consola del proveedor, FORCE re-run, borrar drop-in). |
| `payload/test/ssh-finalize-decision.sh` (nuevo) | Driver unitario que mockea `ss`/`tailscale`/`authorized_keys` y asserta el estado elegido en los 3 escenarios. |

### Plan de tareas (waves)

**Wave 1 — lógica del dispositivo**

- [ ] **T1 — Refactor de la máquina de estados en `35-ssh-finalize.sh` [DANGER ZONE]**
  Sustituir el bloque `keep-current-access` por la decisión BIND/HOLD-HARDENED/HOLD-OPEN. BIND cuando no hay peer externo o hay peer tailnet; HOLD-HARDENED cuando solo peer externo + `authorized_keys` no vacío (drop-in `02-…-public-hardening.conf` con password/kbd off, sin bind, estampa `ssh_public_hardened`); HOLD-OPEN cuando solo peer externo + sin clave (no toca auth, no estampa `ssh_finalized`, aviso ruidoso). BIND elimina `02-…-public-hardening.conf` antes del `reload`. Todo con `sshd -t` previo y `reload` (no `restart`).
  - **verify:** `shellcheck -S warning payload/wizard/35-ssh-finalize.sh && bash -n payload/wizard/35-ssh-finalize.sh`
  - **done:** los 3 estados existen, ninguno deja `PasswordAuthentication yes` sobre `0.0.0.0` estampado como securizado, y solo BIND estampa `ssh_finalized`.

- [ ] **T5 — Driver de test unitario del decisor (`payload/test/ssh-finalize-decision.sh`, nuevo)**
  Mockea `ss` (peer externo / peer tailnet / vacío), `tailscale ip -4` y el contenido de `authorized_keys`; ejecuta el decisor y asserta estado + drop-ins escritos + fase estampada para los 3 escenarios. Sin tocar el sshd real (usar un `sshd_config.d` temporal / dry-run).
  - **verify:** `bash payload/test/ssh-finalize-decision.sh` sale 0
  - **done:** 3 asserts en verde (BIND / HOLD-HARDENED / HOLD-OPEN) + caso FORCE=1 → BIND.

**Wave 2 — cierre del bucle y recuperación**

- [ ] **T2 — Hook de auto-finish en /tutorial Beat 2**
  Tras el import de GitHub keys (SKILL.md líneas ~116-129), si `phase_is_done ssh_finalized` es falso, ejecutar `sudo BIB_SSH_FORCE_TAILSCALE=1 /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh`. Ajustar copy para explicar el cierre (SSH pasa a tailnet-only ahora que hay clave).
  - **verify:** `grep -n "BIB_SSH_FORCE_TAILSCALE" payload/skills/tutorial/SKILL.md` muestra el hook tras el import
  - **done:** Beat 2 dispara el re-run condicionado a `!ssh_finalized`; copy coherente con el modelo de un-solo-tmux.

- [ ] **T3 — Ruta de recuperación documentada + mensajes impresos**
  Los mensajes de HOLD (T1) imprimen los comandos exactos de recuperación; documentar en `payload/tutorial/desktop-readme.md` y/o `SECURITY.md`: (a) consola web/serie del proveedor VPS → `sudo rm /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf && sudo systemctl reload ssh`; (b) re-aplicar con `BIB_SSH_FORCE_TAILSCALE=1`; (c) consola física en mini PC.
  - **verify:** `grep -rn "BIB_SSH_FORCE_TAILSCALE\|01-buildersinabox-tailscale" SECURITY.md payload/tutorial/desktop-readme.md`
  - **done:** las 3 rutas de recuperación aparecen en doc y en el mensaje HOLD del script.

**Wave 3 — copy pública y verificación real**

- [ ] **T4 — Copy pública precisa (README + landing)**
  README §"Security model": reemplazar "Zero public ports" absoluto por postura por-target (NAT/homelab: nada escucha en internet; VPS: sshd atado al tailnet como estado final, key-only durante el setup mientras reconectas por Tailscale). Actualizar bullet "Lockout-safe hardening". `site/index.html` línea 74 + note línea 82: wording preciso, sin absoluto. Mantener el gancho vendible (Andrea) pero verdadero.
  - **verify:** `grep -n "Zero public ports" README.md site/index.html` sin coincidencias (o reformulado con matiz)
  - **done:** ninguna afirmación absoluta incumplible; postura VPS descrita explícitamente; hook de seguridad intacto.

- [ ] **T6 — Verificación E2E en VM (multipass) — REQUERIDA antes de fiarse [DANGER ZONE]**
  Dos escenarios, imitando FEAT-013 CP-02:
  1. **NAT/mini PC:** sin sesión SSH externa (o entrando por tailnet) → esperar **BIND**, `ListenAddress` tailnet, `ss -tlnp` sin `0.0.0.0:22`, reconexión por tailnet OK.
  2. **IP pública (VPS simulado):** entrar por SSH desde una IP no-tailnet; (a) sin clave → **HOLD-OPEN** (password sigue, no `ssh_finalized`, aviso); (b) con clave en `authorized_keys` → **HOLD-HARDENED** (`PasswordAuthentication no`, listener aún público, key-only funciona, password rechazada). Luego `BIB_SSH_FORCE_TAILSCALE=1` con sesión tailnet presente → **BIND**. Comprobar que la sesión pública activa sobrevive al `reload` (no lockout).
  - **verify:** ejecución manual documentada en §4 con salidas de `ss -tlnp`, `sshd -T | grep -i passwordauth`, y prueba de reconexión antes/después.
  - **done:** ambos escenarios pasan sin lockout y el estado final de cada target es el esperado; resultado anotado en §6.

### Patron de codigo real (a preservar)

El bloque de escritura de drop-in con validación `sshd -t` + `reload` de `35-ssh-finalize.sh` (líneas 135-152) es el patrón que T1 debe replicar para el nuevo `02-…-public-hardening.conf` y mantener para el bind:

```bash
if [[ -n "$tailscale_ip" ]]; then
    drop_in=/etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf
    cat > "${drop_in}.tmp" <<EOF
# Managed by Builders in a Box (payload/wizard/35-ssh-finalize.sh).
# Restrict sshd to listen only on the Tailscale interface address.
ListenAddress ${tailscale_ip}
EOF
    mv "${drop_in}.tmp" "$drop_in"
    if sshd -t 2>/dev/null; then
        systemctl reload ssh.service 2>/dev/null || systemctl restart ssh.service
        log "35-ssh-finalize: sshd bound to Tailscale address ${tailscale_ip}"
    else
        rm -f "$drop_in"
        warn "35-ssh-finalize: sshd config check failed, reverted Tailscale bind"
    fi
else
    log "35-ssh-finalize: no Tailscale IP available, leaving sshd on its default bind"
fi
```

Y el clasificador tailnet ya existente, que T1 reutiliza para distinguir peer externo de peer tailnet:

```bash
# Tailnet address spaces: IPv4 CGNAT 100.64.0.0/10, IPv6 fd7a:115c:a1e0::/48.
_is_tailnet_addr() {
    local ip="${1#::ffff:}"
    [[ "$ip" == fd7a:115c:a1e0:* ]] && return 0
    [[ "$ip" == 100.* ]] || return 1
    local second="${ip#100.}"
    second="${second%%.*}"
    [[ "$second" =~ ^[0-9]+$ ]] && (( second >= 64 && second <= 127 ))
}
```

### Criterios globales verificables

- `shellcheck -S warning` y `bash -n` en verde para todos los `.sh` tocados (gate CI).
- Tras el flujo completo en un VPS simulado: `ss -tlnp | grep ':22'` muestra **solo** la IP tailnet (BIND), o si en HOLD, `sshd -T | grep -i passwordauthentication` = `no` (HOLD-HARDENED) — **nunca** `passwordauthentication yes` sobre `0.0.0.0` estampado como securizado.
- En NAT: sin regresión — mismo resultado que hoy (BIND directo).
- Ninguna ejecución deja al único admin sin ruta de acceso (verificado en T6, ambos escenarios).
- Idempotencia: re-ejecutar 35-ssh-finalize no cambia el estado final.
- `git archive HEAD | tar -t` no incluye `specs/` ni maintainer paths (gate CI).

---

## 3. Boundaries

### Always
- `set -euo pipefail`, idempotente.
- Mantener una ruta de recuperación de acceso siempre (nunca lockout del único admin).
- Copy pública precisa; nada de absolutos incumplibles.
- Centralizar la lógica SSH en los scripts existentes (`50-ssh.sh` / `35-ssh-finalize.sh`), no dispersarla.
- **El bind tailnet-only (ListenAddress) solo se aplica con prueba positiva de alcanzabilidad por el tailnet** (peer entrante tailnet) o cuando no hay ninguna sesión SSH externa que dependa del listener público.
- `sshd -t` antes de recargar y `reload` (no `restart`) para que las sesiones vivas sobrevivan; revertir el drop-in si `sshd -t` falla.
- El drop-in de endurecimiento público (`02-…-public-hardening.conf`) existe **solo** mientras exista listener público; BIND lo elimina.

### Ask First
- **[DANGER ZONE] Cualquier cambio a `sshd` (config, listener, auth) requiere OK explícito de Jesus antes de merge** — puede dejar una caja inaccesible.
- Cambiar el default de `BIB_SSH_FORCE_TAILSCALE` o el flujo del prompt anti-lockout.
- Desplegar el copy de `site/` (outward-facing, gate de Jesus).

### Never
- Dejar `PasswordAuthentication yes` sobre una interfaz pública (0.0.0.0) como estado final por defecto.
- **Deshabilitar `PasswordAuthentication` sin una clave usable presente en `authorized_keys` del target user** (dejaría al usuario sin credencial → lockout). Esa es la razón de HOLD-OPEN vs HOLD-HARDENED.
- **Estampar `ssh_finalized` (securizado) mientras sshd siga con contraseña abierta sobre interfaz pública.**
- Lockout del único usuario admin sin ruta de recuperación.
- Abrir puertos nuevos.
- Tocar la ruta de la app de Claude / otras partes fuera de SSH+copy.
- Flip a público dentro de este FEAT.

---

## 4. QA (Pablo)

### Estrategia de testing

Cambio en `sshd` (DANGER ZONE) sobre scripts bash para Ubuntu 24.04. Dos capas:

1. **CI (barato, hermético):** `shellcheck -S warning` + `bash -n` sobre los `.sh` tocados, y el driver unitario del decisor (`payload/test/ssh-finalize-decision.sh`, T5) que mockea `ss`/`tailscale`/`authorized_keys`. **CI NO ejercita `35-ssh-finalize.sh` contra un sshd real** (es hermético, `BIB_OAUTH_MOCK=1` lo salta). El driver unitario cubre la *lógica de decisión*, no el efecto sobre el listener.
2. **E2E manual en VM (multipass) — fuente de verdad para el bind real.** Se simulan dos topologías:
   - **Topología A — NAT / mini PC:** VM sin IP pública alcanzable; el instalador se opera desde la consola local de la VM (no hay sesión SSH externa) o entrando por el tailnet.
   - **Topología B — VPS con IP pública:** el instalador se opera **por SSH público** (peer entrante desde una IP no-tailnet), que es donde vive el riesgo. Para el peer externo se usa una segunda VM/host que hace `ssh` a la IP de bridge de la VM (fuera de `100.64.0.0/10`).

Convención de nombres de estado (de §2): **BIND** (seguro), **HOLD-HARDENED** (key-only, listener aún público), **HOLD-OPEN** (contraseña, exposición residual explícita, no estampado).

**Setup común E2E** (documentado para reproducir; se anota el resultado real en §6):

```bash
# VM objetivo (Ubuntu 24.04)
multipass launch 24.04 --name biab-vps --cpus 2 --memory 2G --disk 12G
multipass exec biab-vps -- sudo bash -c 'curl -fsSL file:///…/install.sh | bash'  # o repo clonado
# IP de la VM (hace de "IP pública" no-tailnet):
BIAB_IP=$(multipass info biab-vps --format csv | awk -F, 'NR==2{print $3}')
```

### Casos de prueba

#### Funcionales

| # | Caso | Pasos | Resultado esperado | Estado |
|---|------|-------|--------------------|--------|
| F1 | **NAT/mini PC → BIND** | 1. Topología A, sin sesión SSH externa (operar por consola local de la VM). 2. Correr wizard hasta pasar `35-ssh-finalize` con `tailscale up` hecho. 3. `ss -Htn state established '( sport = :22 )'` (vacío o solo tailnet). | Estado **BIND**: existe `01-buildersinabox-tailscale.conf` con `ListenAddress <100.x>`; `ss -tlnp \| grep ':22'` muestra **solo** la IP tailnet, **no** `0.0.0.0:22`; `phase_is_done ssh_finalized` = true; `02-…-public-hardening.conf` **no** existe. | pendiente |
| F2 | **VPS por consola web (sin sesión SSH) → BIND** | 1. Topología B pero el instalador se corre **sin** peer SSH entrante (simula consola del proveedor). 2. `_ssh_peer_addrs` vacío. 3. Correr `35-ssh-finalize` con tailnet activo. | Estado **BIND** idéntico a F1 (no hay sesión pública que proteger): listener solo en IP tailnet, `ssh_finalized` estampado, sin exposición pública. | pendiente |
| F3 | **VPS por SSH público, sesión entrante desde el tailnet → BIND** | 1. Topología B. 2. Reconectar a la caja **por su IP tailnet** (100.x) y dejar esa sesión abierta. 3. Correr `35-ssh-finalize`. | `_ssh_peer_addrs` incluye peer tailnet → prueba positiva de alcanzabilidad → **BIND**. Listener queda solo en IP tailnet; la sesión pública previa (si existía) sobrevive al `reload`; `ssh_finalized` estampado. | pendiente |
| F4 | **VPS por SSH público CON clave → HOLD-HARDENED** | 1. Topología B, sesión SSH entrante **externa** (peer fuera del tailnet). 2. Sembrar `~/.ssh/authorized_keys` del target user **no vacío** (una clave válida del cliente). 3. Correr `35-ssh-finalize`. | Estado **HOLD-HARDENED**: existe `02-…-public-hardening.conf`; `sshd -T \| grep -i passwordauthentication` = `no` y `kbdinteractiveauthentication` = `no`; listener **sigue** en `0.0.0.0:22` (aún NO bind); `phase_is_done ssh_public_hardened` = true y `ssh_finalized` = **false**. **Sin lockout:** login por clave funciona; login por contraseña es **rechazado**. Se imprimen instrucciones de reconexión + `BIB_SSH_FORCE_TAILSCALE=1`. | pendiente |
| F5 | **VPS por SSH público SIN clave → HOLD-OPEN** | 1. Topología B, sesión SSH externa. 2. `~/.ssh/authorized_keys` **vacío/inexistente** (estado típico pre-Beat-2). 3. Correr `35-ssh-finalize`. | Estado **HOLD-OPEN**: `sshd -T \| grep -i passwordauthentication` = `yes` (no se toca auth: la contraseña es la única credencial); listener sigue público; `ssh_finalized` = **false** y `ssh_public_hardened` = **false** (no estampado como securizado). Se imprime aviso **prominente** de exposición residual + comandos exactos de reconexión/FORCE. | pendiente |
| F6 | **Cierre automático: HOLD-OPEN → /tutorial Beat 2 → BIND** | 1. Partir del estado F5 (HOLD-OPEN). 2. Completar `gh auth status` y ejecutar Beat 2: importa `gh api /user/keys` a `authorized_keys` y, como `!ssh_finalized`, dispara `sudo BIB_SSH_FORCE_TAILSCALE=1 …/35-ssh-finalize.sh`. 3. Tener sesión tailnet (app de Claude) activa. | Cae en **BIND** sin intervención: listener solo en IP tailnet, `ssh_finalized` estampado, exposición pública eliminada. Si no hubiese sesión tailnet pero ya hay clave → cae en **HOLD-HARDENED** (key-only), nunca queda contraseña pública estampada. | pendiente |

#### Edge cases

| # | Caso | Pasos | Resultado esperado | Estado |
|---|------|-------|--------------------|--------|
| E1 | **Usuario SALTA /tutorial Beat 2** (marcado por Laura) | 1. Estado F5 (HOLD-OPEN). 2. El usuario NO completa Beat 2 (no importa keys, no dispara FORCE). | La ventana HOLD-OPEN **no se cierra sola** — comportamiento esperado y documentado, no un fallo silencioso. Verificar que: el aviso de F5 dejó impresos en pantalla los comandos exactos de recuperación/cierre; `SECURITY.md`/`desktop-readme.md` describen cómo cerrarla manualmente (`BIB_SSH_FORCE_TAILSCALE=1` o reconectar por tailnet); y que en ningún momento se estampó `ssh_finalized`. La caja queda expuesta por contraseña pero el usuario fue avisado y tiene ruta de cierre. | pendiente |
| E2 | **Reboot a mitad del wizard** | 1. Interrumpir (reboot de la VM) justo tras `50-ssh.sh` pero antes de `35-ssh-finalize`. 2. Re-arrancar y dejar que el wizard reanude. | Tras reanudar, `35-ssh-finalize` produce el mismo estado final que sin interrupción (BIND en A, HOLD/BIND en B según clave/peer). No quedan drop-ins `.tmp` huérfanos; `sshd -t` sigue en verde. | pendiente |
| E3 | **Re-run idempotente** | 1. Tras alcanzar BIND (F1), volver a ejecutar `35-ssh-finalize` (con y sin `FORCE=1`). | Estado final idéntico: un solo `01-…-tailscale.conf`, sin `02-…`, `ss -tlnp` igual, `ssh_finalized` sigue true. Re-ejecutar HOLD-HARDENED tampoco duplica drop-ins ni revierte a contraseña. | pendiente |
| E4 | **FORCE=1 desde consola SIN sesión tailnet — bind ciego (riesgo #1 de Laura)** | 1. Topología B, operando por SSH público. 2. NO hay sesión entrante por el tailnet (tailnet arriba pero cliente no enruta). 3. Ejecutar `sudo BIB_SSH_FORCE_TAILSCALE=1 …/35-ssh-finalize.sh`. | El bind se aplica (semántica de FORCE), pero como se usa `reload` (no `restart`) **la sesión SSH pública activa sobrevive** → el usuario detecta que el tailnet no enruta *mientras sigue conectado* y puede revertir con la ruta de recuperación (E7/F-rec). Verificar explícitamente que la sesión pública NO se cae tras el `reload`. Documentar que FORCE es un escape hatch: úsese solo con acceso alternativo confirmado. | pendiente |
| E5 | **Tailscale aún no está `up` → no estampar hardened** | 1. Correr `35-ssh-finalize` con `tailscale ip -4` **vacío** (no-up). | No se escribe ningún bind ni endurecimiento; `sshd` queda en su bind por defecto; **no** se estampa `ssh_finalized` ni `ssh_public_hardened`. Log: "no Tailscale IP available, leaving sshd on its default bind". (State-driven req: nunca prometer hardened sin tailnet.) | pendiente |
| E6 | **`sshd -t` falla → revert seguro** | 1. Forzar un drop-in inválido (p.ej. `ListenAddress` con IP no resoluble simulada) para que `sshd -t` falle en el paso de bind. | El drop-in recién escrito se **elimina** (`rm -f`), no se hace `reload` con config rota, y se emite `warn`. El listener previo (público o tailnet) permanece intacto → sin lockout por config rota. | pendiente |

### Regresion (sagrada)

- [ ] **Caja NAT/mini PC que HOY funciona no cambia de comportamiento:** en topología A el resultado sigue siendo BIND directo al tailnet, mismo `ListenAddress`, misma fase `ssh_finalized`, misma UX del wizard (comparar con FEAT-013 CP-02). Ningún prompt nuevo ni ventana HOLD aparece en el camino NAT.
- [ ] **El listener tailnet acepta contraseña** (modelo documentado para clientes móviles): tras BIND, `sshd -T` NO debe tener `passwordauthentication no` heredado de un `02-…` no eliminado — BIND borra el hardening público.
- [ ] **Ruta de la app de Claude / login OAuth intactos:** `payload/skills/tutorial` Beat 1 (gh auth) y el resto de beats no se rompen por el hook nuevo del Beat 2; `wiring-smoke.sh` (BIB_OAUTH_MOCK=1) sigue en verde.
- [ ] **Resto del wizard intacto:** `10-tailscale-up`, scaffold, tmux `ai-platform` arrancan igual; `payload/test/dryrun.sh` y `wiring-smoke.sh` pasan.
- [ ] **`50-ssh.sh` sin cambio funcional:** solo comentario de cabecera; el drop-in base `00-buildersinabox.conf` es byte-idéntico salvo comentarios.

### Recuperacion (caso de prueba explícito)

- [ ] **F-rec — Recuperar acceso de alguien que quedó fuera.** Simular lockout (p.ej. E4 con tailnet que no enruta y la sesión pública cerrada). Verificar las tres rutas documentadas:
  1. **Consola web/serie del proveedor VPS:** `sudo rm /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf && sudo systemctl reload ssh` → el listener vuelve a `0.0.0.0:22`, acceso público restaurado. Comprobar con `ss -tlnp | grep ':22'`.
  2. **Re-aplicar bind cuando el tailnet ya enruta:** `sudo BIB_SSH_FORCE_TAILSCALE=1 …/35-ssh-finalize.sh` → vuelve a BIND.
  3. **Consola física (mini PC):** teclado+monitor, misma edición de drop-in que (1).
  - **Resultado esperado:** cada ruta restaura acceso sin reinstalar; los comandos exactos aparecen en `SECURITY.md`/`payload/tutorial/desktop-readme.md` **y** en el mensaje impreso por los estados HOLD.

### Criterios de testing

```bash
# --- CI (hermético) ---
shellcheck -S warning payload/wizard/35-ssh-finalize.sh payload/install/50-ssh.sh
bash -n payload/wizard/35-ssh-finalize.sh
bash payload/test/ssh-finalize-decision.sh   # T5: 3 estados + FORCE→BIND, sale 0

# --- E2E en VM (multipass) — fuente de verdad ---
# Listener efectivo (¿escucha en público o solo tailnet?):
ss -tlnp | grep ':22'                 # BIND ⇒ solo 100.x ; nunca 0.0.0.0:22 estampado como seguro
sshd -T | grep -i -e listenaddress -e passwordauthentication -e kbdinteractive
#   BIND         ⇒ listenaddress 100.x ; passwordauthentication puede ser yes (tailnet)
#   HOLD-HARDENED⇒ listenaddress 0.0.0.0 ; passwordauthentication no ; kbdinteractive no
#   HOLD-OPEN    ⇒ listenaddress 0.0.0.0 ; passwordauthentication yes (NO estampado seguro)

# Peers de sesiones SSH vivas (clasificar externo vs tailnet, como _ssh_peer_addrs):
ss -Htn state established '( sport = :22 )'

# Fase estampada:
grep -o '"ssh_finalized":[^,}]*\|"ssh_public_hardened":[^,}]*' /var/lib/buildersinabox/state.json

# Simular peer EXTERNO (desde host o segunda VM, contra la IP de bridge no-tailnet):
ssh -o PubkeyAuthentication=no user@"$BIAB_IP"   # debe: HOLD-OPEN acepta pass ; HOLD-HARDENED la rechaza
ssh -i client_key user@"$BIAB_IP"                # login por clave (F4) debe funcionar

# Anti-lockout en FORCE (E4): confirmar que la sesión pública sobrevive al reload
#   -> desde la sesión SSH pública ya abierta, tras el reload ejecutar `whoami` (no se debe cortar)

# Idempotencia (E3): correr dos veces y diffear
sudo BIB_SSH_FORCE_TAILSCALE=1 payload/wizard/35-ssh-finalize.sh
ls /etc/ssh/sshd_config.d/                        # un solo 01-… ; sin 02-… tras BIND ; sin .tmp
```

**Gate de aceptación:** ningún escenario deja `PasswordAuthentication yes` sobre `0.0.0.0` **estampado como `ssh_finalized`**; ambas topologías terminan en su estado esperado sin lockout; las tres rutas de recuperación funcionan. Resultado real (salidas de `ss`/`sshd -T`/reconexión) se anota en §6 antes de fiarse.

---

## 5. Implementacion (Laura)

### Branch
`feat/FEAT-014`

### Decisiones tomadas
- [2026-07-11] Jesus eligió "arreglar código + copy precisa" (no solo suavizar copy): el default seguro se hace verdad antes del flip. Detona porque la landing invita a VPS y el hook es seguridad.
- [2026-07-11] **HOLD-OPEN endurecido (decisión Jesus):** el wizard NO debe completar en estado HOLD-OPEN (VPS solo-password) de forma silenciosa. Exige **confirmación explícita** del usuario ("entiendo que mi SSH sigue expuesto a internet con contraseña") antes de terminar; sin esa confirmación, el wizard no da el setup por bueno. Convierte el hueco residual que marcó QA (E1/edge, saltar Beat 2) en elección consciente. → **Añadir a §2 una task**: en `35-ssh-finalize.sh`, rama HOLD-OPEN, confirmación bloqueante (`prompt_choice`, con escape documentado para modo no-interactivo) + no marcar el wizard como completo mientras la exposición residual siga sin reconocerse. Actualizar el EARS Unwanted de §1 en consecuencia.
- [2026-07-11] **FORCE ciego se queda documentado (decisión Jesus):** `BIB_SSH_FORCE_TAILSCALE=1` sigue siendo bind directo sin verificación de reachability por tailnet. Flag de usuario avanzado, auto-infligido; se documenta el riesgo (§2/recuperación) y NO se endurece.

---

## 6. Feedback (Jesus)

—
