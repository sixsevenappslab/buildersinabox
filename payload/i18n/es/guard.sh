# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: la nota con la que acaba el asistente cuando una protección de
# Codex espera la aprobación del dueño (lib/guard.sh, guard_pending_note). Las
# líneas caben en 40 columnas, el asistente del tamaño de un teléfono. Es la
# gemela de ../en/guard.sh. Desde T3 también el bloque
# "Red de seguridad" de `biab status` (guard_status_block), donde las dos primeras
# columnas (rótulo y estado) son palabras fijas y solo se traduce la frase.
BIB_MSG[guard.pending.unverifiable]='\nAún no se pudo comprobar la protección\nde %s. Si `biab status` no\nla muestra activa, ejecuta `%s`,\nluego escribe /hooks y apruébala.\n'
BIB_MSG[guard.pending.waiting]='\nFalta un paso: la protección de\n%s aún NO está activa. Para\naprobarla: `%s` y luego /hooks.\n'

BIB_MSG[guard.status.title]='Red de seguridad (%s):\n'
BIB_MSG[guard.status.base_yes]='Paseo pregunta antes de actuar'
BIB_MSG[guard.status.base_no]='no hay interfaz en la app del teléfono para %s: úsalo por ssh'
BIB_MSG[guard.status.sentinel]='hooks desactivados (hay un archivo centinela)'
BIB_MSG[guard.status.none]='Builders in a Box no añade ninguna protección en %s; solo las preguntas de permiso propias de %s protegen este equipo'
BIB_MSG[guard.status.active]='bloquea los comandos de shell destructivos más comunes (en la medida de lo posible)'
BIB_MSG[guard.status.active_noask]=' (sin preguntas de permiso en %s)'
BIB_MSG[guard.status.active_partial]=' (PARCIAL: solo patrones de shell; no se detectan todas las formas entrecomilladas o pegadas de rm/chmod/chown)'
BIB_MSG[guard.status.off]='hooks desactivados en settings.json (disableAllHooks)'
BIB_MSG[guard.status.disabled]='desactivada dentro de %s%s'
BIB_MSG[guard.status.pending1]='PENDIENTE DE APROBACIÓN: instalada, pero NO activa hasta que la apruebes'
BIB_MSG[guard.status.pending2]='Apruébala una vez: ejecuta `%s` y luego escribe /hooks'
BIB_MSG[guard.status.pending3]='Hasta entonces %s no la ejecuta (tampoco con `%s exec`)'
BIB_MSG[guard.status.changed1]='PENDIENTE DE APROBACIÓN: su entrada cambió después de que la aprobaras, así que %s ya no la ejecuta'
BIB_MSG[guard.status.changed2]='Revísala y apruébala otra vez: ejecuta `%s` y luego escribe /hooks'
BIB_MSG[guard.status.invalid]='%s no puede cargar su archivo de hooks o de configuración (no válido): arréglalo y luego ejecuta: sudo biab update'
BIB_MSG[guard.status.unverifiable]='no se puede comprobar qué carga %s ahora mismo (no se encuentra el comando o no responde): no se da por activa'
BIB_MSG[guard.status.missing]='la protección no está registrada para %s, o %s tiene los hooks desactivados en su propia configuración'
BIB_MSG[guard.status.partial]='parte de la protección está en su sitio'
BIB_MSG[guard.status.linked]='un archivo que BIAB escribe para esta protección (settings.json, hooks.json) es un enlace simbólico y BIAB no escribe a través de enlaces: añade los hooks en su destino tú mismo, o sustituye el enlace por un archivo'
BIB_MSG[guard.status.blocked]='registrada, pero falta su script o su archivo de reglas, o no es ejecutable'
BIB_MSG[guard.status.overridden]='anulada por otra configuración de %s'
BIB_MSG[guard.status.other]='estado: %s'
BIB_MSG[guard.status.night_yes]='compatible (hay que activarlo: biab pack add night-shift)'
BIB_MSG[guard.unproven.active]='instalada, SIN verificar: %s carga el plugin, pero nadie ha visto todavía que bloquee un comando, así que Builders in a Box no la cuenta'
BIB_MSG[guard.unproven.disabled]='instalada, SIN verificar, y desactivada dentro de %s%s'
BIB_MSG[guard.unproven.off]='instalada, SIN verificar, y los hooks están desactivados (hay un archivo centinela)'
BIB_MSG[guard.unproven.blocked]='instalada, SIN verificar, y %s no cargó su hook (o falta su script o su archivo de reglas)'
BIB_MSG[guard.unproven.unverifiable]='instalada, SIN verificar: no se puede comprobar qué carga %s ahora mismo (no se encuentra el comando o no responde)'
BIB_MSG[guard.unproven.other]='instalada, SIN verificar (estado: %s)'
