# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: lo que el instalador (install.sh, y las comprobaciones de
# lib/common.sh que ejecuta primero) le dice a quien está al teclado. Es la
# gemela de ../en/install.sh: mismas claves, mismos %s, mismos comandos y flags.
BIB_MSG[install.err.root]='hay que ejecutarlo como root (usa sudo)'
BIB_MSG[install.err.os]='este paquete solo funciona en Ubuntu 24.04. Pasa --i-know-what-im-doing para forzarlo.'

# check_ssh_install_preflight (lib/common.sh)
BIB_MSG[install.preflight.warn]='\n⚠ Estás instalando por una conexión SSH y la red privada\n  (Tailscale) todavía no está activa. Más adelante, SSH se\n  restringe a esa red privada: si esta sesión no es accesible\n  por ella, te quedarás fuera.\n\n  Es lo esperado y es seguro en un VPS: el asistente primero\n  restringe a solo clave y nunca te deja fuera a mitad de\n  sesión. NO es seguro dentro de una VM sin consola (p. ej.\n  multipass, cuya shell ya es SSH): eso no está soportado.\n  Usa un hipervisor con consola real (VirtualBox, UTM,\n  virt-manager/Proxmox).\n\n'
BIB_MSG[install.preflight.notty]='no hay tty desde donde confirmar (o se usó --non-interactive). Define BIB_SSH_INSTALL_ACK=1 si entiendes el riesgo, o instala desde una consola.'
BIB_MSG[install.preflight.ask]='¿Continuar de todos modos? [s/N] '
BIB_MSG[install.preflight.yes]='y|s|si|sí'
BIB_MSG[install.preflight.aborted]='cancelado. Instala desde una consola, o define BIB_SSH_INSTALL_ACK=1 si entiendes el riesgo.'

# Un host solo con root: ofrecer crear el usuario humano.
BIB_MSG[install.rootuser.hint]='crea uno y vuelve a ejecutar:\n    adduser --gecos '\'''\'' <username> && usermod -aG sudo <username>\n    BIB_USER=<username> %s'
BIB_MSG[install.rootuser.noninteractive]='estás ejecutando como root y no hay ninguna cuenta de usuario de destino. Define BIB_USER=<usuario existente>, o %s'
BIB_MSG[install.rootuser.intro]='\nEstás ejecutando como root y no hay ninguna cuenta de usuario de destino.\nBuilders in a Box prepara el espacio de trabajo de un usuario normal, no de root.\nPuedo crear esa cuenta ahora (elegirás su contraseña en el siguiente paso).\n'
BIB_MSG[install.rootuser.ask]='\nNombre de usuario que crear (en minúsculas; déjalo en blanco para cancelar): '
BIB_MSG[install.rootuser.aborted]='cancelado. Para hacerlo a mano, %s'
BIB_MSG[install.rootuser.invalid]=''\''%s'\'' no es un nombre de usuario válido (minúsculas, dígitos, - y _).'
BIB_MSG[install.rootuser.failed]='no se pudo crear el usuario %s'

# La pregunta del nombre y el menú de CLI.
BIB_MSG[install.name.ask]='\n¿Con qué nombre quieres que te salude el asistente? (déjalo en blanco para omitir el saludo personalizado) \n> '
BIB_MSG[install.cli.intro]='Elige las suscripciones de IA que tienes.\nTodas inician sesión desde tu teléfono:\n\n'
BIB_MSG[install.cli.which]='¿Qué suscripciones de IA tienes?'

# --uninstall
BIB_MSG[install.uninstall.target_user]='el usuario de destino'
BIB_MSG[install.uninstall.nokey]='\n  AVISO — %s no tiene ninguna clave SSH en authorized_keys.\n  El acceso con contraseña funciona ahora gracias a un archivo de\n  configuración que esta desinstalación elimina. Lo que pase después lo\n  decide tu distribución, y en las imágenes de nube el valor por defecto\n  es "PasswordAuthentication no".\n  Si este equipo no tiene pantalla, abre una SEGUNDA sesión SSH y comprueba\n  que sigues pudiendo entrar ANTES de cerrar esta.\n\n'
BIB_MSG[install.uninstall.ack]='  Escribe sí (o yes) para continuar: '
BIB_MSG[install.uninstall.yes]='yes|s|si|sí'
BIB_MSG[install.uninstall.aborted]='desinstalación: cancelada, no se ha cambiado nada.\n'
BIB_MSG[install.uninstall.pack_run]='desinstalación: ejecutando el desmontaje del pack %s\n'
BIB_MSG[install.uninstall.pack_failed]='desinstalación: el desmontaje del pack %s ha fallado, se continúa\n'
BIB_MSG[install.uninstall.paseo_stop]='desinstalación: deteniendo biab-paseo\n'
BIB_MSG[install.uninstall.timer_stop]='desinstalación: desactivando biab-update.timer\n'
BIB_MSG[install.uninstall.not_ours]='desinstalación: se deja %s tal cual: no es nuestro\n'
BIB_MSG[install.uninstall.removing]='desinstalación: eliminando %s\n'
BIB_MSG[install.uninstall.socket]='desinstalación: se ha restaurado la activación por ssh.socket (se aplica en el próximo arranque; el sshd actual sigue en marcha)\n'
BIB_MSG[install.uninstall.link]='desinstalación: se deja %s tal cual: es un enlace simbólico\n'
BIB_MSG[install.uninstall.link_biab]='desinstalación: se deja %s tal cual: esa ruta (o ~/.biab) es un enlace simbólico\n'
BIB_MSG[install.uninstall.nothing]='desinstalación: no hay nada que eliminar: no se ha encontrado estado de BIAB\n'
BIB_MSG[install.uninstall.done]='desinstalación: completada. sshd vuelve a los valores por defecto de tu distribución.\ndesinstalación: se deja intacto a propósito: tu carpeta personal (así que tus\n               proyectos en ~/ai-platform/projects/ y el progreso del primer proyecto\n               en ~/.config/biab-first-project/ se conservan), la\n               pertenencia a la tailnet, tus inicios de sesión de GitHub y de agentes,\n               la contraseña de tu cuenta y los paquetes que instalamos (jq, gh, node,\n               tailscale, la IA).\n'

# --help
BIB_MSG[install.usage]='Uso: sudo install.sh [opciones]\n\nOpciones:\n  --ai=<claude|antigravity|codex|opencode>  Elige la IA que instalar (por defecto: claude).\n  --flavor=<default|gift>    Elige la variante de textos y banner (por defecto: default).\n  --profile=<dedicated|cloud>  Quién controla SSH en este equipo (por defecto: dedicated).\n                             '\''cloud'\'' es para un VPS gestionado por el proveedor: BIAB\n                             nunca escribe un archivo de configuración de sshd, nunca activa\n                             la contraseña y nunca asocia sshd a la tailnet.\n                             Se guarda en la primera instalación; sobrevive a biab update.\n  --lang=<en|es>             Idioma de las pantallas de configuración (por defecto: pregunta, si no en).\n                             Se guarda en la primera instalación; `biab lang` lo cambia.\n  --force                    Reinicia el estado de las fases del asistente para que se ejecute otra vez.\n                             No reinstala el stack.\n  --skip-wizard              Instala el stack y termina (sin pasos de OAuth).\n                             Útil para CI / preparar imágenes.\n  --non-interactive          Lee BIB_USER, BIB_NAME, BIB_FLAVOR, BIB_AI_CLI\n                             del entorno. Falla enseguida si falta alguna variable\n                             obligatoria. Lo usan CI y autoinstall.\n  --update                   Vuelve a ejecutar de forma idempotente en un equipo que ya\n                             pasó por la instalación una vez. Omite las fases completadas.\n  --uninstall                Elimina todo lo que es de BIAB y termina.\n                             Deja la carpeta personal, Tailscale, gh y la sesión de Claude.\n  --selftest                 Ejecuta la guarda de referencias personales sobre el árbol\n                             de instalación y verifica el esquema de state.json; termina.\n  --latest                   Con --update o --skip-wizard: instala las últimas versiones\n                             estables más recientes de cada herramienta en vez de las probadas.\n                             Sin probar y sin soporte; `biab update` vuelve a las probadas.\n  --auto-update on [schedule] | off | status\n                             El temporizador opcional de actualización (nunca usa --latest).\n  --i-know-what-im-doing     Continúa aunque el SO no sea Ubuntu 24.04.\n  -h, --help                 Muestra esta ayuda.\n'

BIB_MSG[install.pins.latest_warning]='AVISO: --latest instala la última versión de Claude Code, Codex, Paseo y agy, sin tener en cuenta las versiones que Builders in a Box probó juntas. Esta combinación no está probada ni tiene soporte. Ejecuta '\''biab update'\'' para volver a las versiones probadas.\n'
