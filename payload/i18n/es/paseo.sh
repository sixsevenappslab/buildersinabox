# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: la pantalla de emparejamiento y el último texto del asistente
# (lib/paseo.sh). Es la gemela de ../en/paseo.sh: mismas claves, mismos %s. Los
# rótulos de la app Paseo (Settings, Add host, Direct connection, Use SSL) se
# quedan tal cual: son lo que el dueño ve en pantalla. T3 añadió los avisos de la
# conversión de Antigravity, el texto de la migración y el rechazo de enlaces.
BIB_MSG[paseo.pairing.note_short]='La app puede llamar a este equipo "%s" (nombre de máquina).'
BIB_MSG[paseo.pairing.note_long]='La app muestra este equipo con un nombre largo que empieza\npor "%s" (su nombre de máquina).'
BIB_MSG[paseo.pairing.body]='En la app Paseo, abre Settings, luego Add host, luego\nelige Direct connection e introduce:\n\n  Host:      %s\n  Port:      %s\n  Password:\n  %s\n\nDeja "Use SSL" desactivado. Tu teléfono necesita tener\nTailscale activado (lo configuraste antes).\n\n%s\nPara cambiarle el nombre, abre los ajustes del host en\nla app y pulsa el lápiz.\n\n'
BIB_MSG[paseo.fallback]='Siempre puedes trabajar por SSH, sin app:\n\nssh %s@%s\n\nLuego ejecuta:  %s\n'
BIB_MSG[paseo.finale.ready]='Has iniciado sesión en %s y tu primer agente está en marcha.\n\n'
BIB_MSG[paseo.finale.paired]='Abre la app Paseo en tu teléfono. Encontrarás el\nespacio de trabajo "%s" y el agente\n"%s".\n\nEl agente ya está hablando: te dará la bienvenida y te\nguiará por tu primer proyecto, paso a paso.\n'
BIB_MSG[paseo.finale.unpaired]='Tu teléfono todavía no está emparejado. Cuando quieras,\nejecuta esto en el equipo:\n\n%s\n\n%s\n'

BIB_MSG[paseo.err.symlink]='paseo: no se puede continuar: %s es un enlace simbólico. BIAB nunca escribe a través de enlaces en tu carpeta personal. Quita el enlace (o muévelo) y vuelve a ejecutar el paso.\n'
BIB_MSG[paseo.reason.nouser]='no se encontró al usuario del equipo en el estado de la configuración'
BIB_MSG[paseo.agy.conv_head]='\nAntigravity ahora funciona en la app Paseo. Pregunta antes de ejecutar comandos de shell y\nantes de escribir archivos en tu proyecto, tu carpeta personal, ~/.biab o /var/tmp'
BIB_MSG[paseo.agy.conv_reads]=',\ny antes de leer archivos fuera de tu proyecto.\n'
BIB_MSG[paseo.agy.conv_dot]='.\n'
BIB_MSG[paseo.agy.conv_noask]='No pregunta antes de leer dentro del proyecto, buscar en la web, abrir páginas web\no escribir en /tmp. El aviso solo ofrece permitir una vez o rechazar, sin\npermitir siempre; el interruptor Auto Accept de la app es aparte. (Medido con agy 1.4.11.)\n'
BIB_MSG[paseo.agy.conv_tightened]='Tu ajuste de agy allowNonWorkspaceAccess estaba en true; ahora está en false, que es\nlo que hace que se pregunte al leer fuera del proyecto.\n'
BIB_MSG[paseo.agy.conv_noreads]='Leer fuera de tu proyecto no pregunta en este equipo: allowNonWorkspaceAccess en\n%s/.gemini/antigravity-cli/settings.json no está en false.\n'
BIB_MSG[paseo.agy.conv_tail]='Las conversaciones iniciadas en el antiguo modo de acceso total siguen en la app pero no se\npueden continuar: inicia un agente nuevo. Aplicar esto reinicia el servicio de la app del\nteléfono, lo que termina cualquier agente que estuviera en marcha.\n\n'
BIB_MSG[paseo.agy.report]='\nAntigravity ahora pregunta antes de leer archivos fuera de tu proyecto: tu ajuste de agy\nallowNonWorkspaceAccess estaba en true y ahora está en false. Tu carpeta de skills\nno se ve afectada.\n\n'
BIB_MSG[paseo.agy.warn_link]='%s (o una carpeta por encima) es un enlace simbólico, no un archivo normal o no es un objeto JSON, así que BIAB lo dejó como estaba. Leer fuera de tu proyecto no preguntará hasta que contenga "allowNonWorkspaceAccess": false; ponlo a mano. '\''biab update'\'' volverá a mirar.'
BIB_MSG[paseo.agy.warn_write]='no se pudo cambiar allowNonWorkspaceAccess en %s. Leer fuera de tu proyecto no preguntará hasta que contenga "allowNonWorkspaceAccess": false; ponlo a mano. '\''biab update'\'' lo intentará de nuevo.'
BIB_MSG[paseo.migrate.done]='\nTus proyectos ya están en la app Paseo (espacios de trabajo con el nombre "%s...").\nTus sesiones de tmux no se tocaron.\n\nPara emparejar tu teléfono, ejecuta esto en un terminal:  %s\n\n'
BIB_MSG[paseo.agy.warn_unverified]='Los ajustes del proveedor de Antigravity aún no están verificados, así que se conservó la antigua clave de activación (mira '\''biab status'\'' para ver el archivo y qué hacer)'
