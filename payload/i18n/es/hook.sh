# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T5: los motivos que dan los hooks de protección en una pregunta de permiso
# (Claude Code, Codex, Antigravity). Una línea por mensaje, con la forma
# BIB_MSG[hook.tema.detalle]='formato printf'. Es la gemela de ../en/hook.sh: mismas
# claves, mismos comandos, rutas y nombres de archivo. Español neutro, tuteo. En
# inglés los hooks no cargan el catálogo (el texto es el literal del código), así que
# aquí solo hay lo que ve un dueño con el idioma en español. Los ids de regla y las
# decisiones no son texto y nunca salen de aquí.

BIB_MSG[hook.guard.blocked]='La protección de Builders in a Box bloqueó un comando destructivo'
BIB_MSG[hook.guard.confirm]='La protección de Builders in a Box pide confirmación'
BIB_MSG[hook.guard.no_command]='no se pudo leer el comando de la entrada de la herramienta'
BIB_MSG[hook.guard.rules_missing]='faltan las reglas de la protección o no se pueden leer (ejecuta: biab status)'

# Una por id de regla de guardrail-rules.sh (el id es el último componente).
BIB_MSG[hook.guard.why.rm-root]='borrado recursivo y forzado de una ruta raíz o del directorio personal'
BIB_MSG[hook.guard.why.mkfs]='mkfs (formatea un sistema de archivos)'
BIB_MSG[hook.guard.why.wipefs]='wipefs (borra las firmas de un sistema de archivos)'
BIB_MSG[hook.guard.why.dd-disk]='dd escribiendo directamente en un disco'
BIB_MSG[hook.guard.why.redirect-disk]='una redirección que sobrescribe un disco directamente'
BIB_MSG[hook.guard.why.sgdisk]='sgdisk escribiendo una tabla de particiones'
BIB_MSG[hook.guard.why.parted]='parted escribiendo particiones sin interacción'
BIB_MSG[hook.guard.why.fdisk-script]='fdisk con guion: escritura de particiones sin interacción'
BIB_MSG[hook.guard.why.fork-bomb]='bomba de procesos (fork bomb)'
BIB_MSG[hook.guard.why.pipe-sudo-shell]='un script remoto canalizado a una shell de root'
BIB_MSG[hook.guard.why.chmod-root]='chmod recursivo sobre una ruta raíz'
BIB_MSG[hook.guard.why.chown-root]='chown recursivo sobre una ruta raíz'
BIB_MSG[hook.guard.why.force-push-main]='push forzado a una rama protegida (main/master)'
BIB_MSG[hook.guard.why.pipe-shell]='descarga y ejecución de un script remoto'
BIB_MSG[hook.guard.why.force-with-lease]='push con force-with-lease'

BIB_MSG[hook.secret.blocked]='La protección de secretos de Builders in a Box bloqueó la lectura de un archivo secreto'
BIB_MSG[hook.secret.confirm]='La protección de secretos de Builders in a Box pide confirmación'
BIB_MSG[hook.secret.rules_missing]='secret-guard-rules.sh falta o no se puede leer (ejecuta: biab status)'
BIB_MSG[hook.secret.reason]='Leer un archivo de credenciales o secretos (.env / secrets / tokens de acceso / claves SSH) dejaría su contenido en texto plano en la transcripción de la sesión. Compara rutas, mtime, permisos o sha256, o pídele el valor al usuario.'
BIB_MSG[hook.secret.unattended]=' Sesión sin supervisión (bypassPermissions): denegado.'
