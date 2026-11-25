# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: el asistente de consola (wizard/run.sh y los pasos 01..50). Una
# línea por mensaje, con la forma BIB_MSG[area.tema.detalle]='formato printf'
# (el valor lleva su propio \n; una comilla simple dentro se escribe '\''). Es la
# gemela de ../en/wizard.sh: mismas claves, mismos %s, mismos comandos. Español
# neutro, tuteo, sin regionalismos. Las líneas de prosa caben en 60 columnas.
#
# Glosario (fíjalo antes de añadir mensajes): box = "equipo", phone = "teléfono",
# laptop = "laptop", password = "contraseña", sign in = "iniciar sesión",
# link = "enlace", workspace = "espacio de trabajo", skills = "skills".

# Los seis hitos y sus tiempos estimados (los usa también wizard_next_milestone).
BIB_MSG[wizard.title.secure]='Protege este equipo'
BIB_MSG[wizard.title.private]='Conéctalo en privado'
BIB_MSG[wizard.title.remote]='Sigue en otro dispositivo'
BIB_MSG[wizard.title.ai]='Conecta tu IA'
BIB_MSG[wizard.title.workspace]='Prepara tu espacio'
BIB_MSG[wizard.title.start]='Empieza a construir'
BIB_MSG[wizard.title.cloud_ssh]='Revisa cómo te conectas'
BIB_MSG[wizard.title.app]='Abre tu equipo en la app'
BIB_MSG[wizard.eta.min1]='1 minuto'
BIB_MSG[wizard.eta.min2]='unos 2 minutos'
BIB_MSG[wizard.eta.min3]='unos 3 minutos'
BIB_MSG[wizard.eta.min4]='unos 4 minutos'
BIB_MSG[wizard.eta.min6]='unos 6 minutos'
BIB_MSG[wizard.eta.min8]='unos 8 minutos'
BIB_MSG[wizard.eta.moment]='un momento'

# Preguntas que esperan un Enter.
BIB_MSG[wizard.confirm.begin]='Pulsa Enter para empezar.'
BIB_MSG[wizard.confirm.continue]='Pulsa Enter para continuar.'
BIB_MSG[wizard.confirm.pw_ready]='Pulsa Enter cuando quieras elegirla.'
BIB_MSG[wizard.confirm.pw_stored]='Pulsa Enter cuando la hayas guardado en un lugar seguro.'
BIB_MSG[wizard.confirm.ts_link]='Pulsa Enter para obtener el enlace de Tailscale.'
BIB_MSG[wizard.confirm.bridge_connected]='Pulsa Enter cuando diga Connected.'
BIB_MSG[wizard.confirm.bridge_sshapp]='Pulsa Enter cuando tu app de SSH esté lista.'

# wizard/run.sh
BIB_MSG[wizard.intro.hi]='Hola%s. En unos pocos pasos, este equipo estará listo\npara construir desde tu teléfono o tu laptop.\n\n'
BIB_MSG[wizard.intro.need]='\nVas a necesitar:\n  - tu teléfono\n%s\nUnos 10 minutos. Los pasos:\n\n  1. Elegir una contraseña para este equipo\n  2. Conectarlo en privado a tus dispositivos\n  3. %s\n  4. Elegir tus IAs e iniciar sesión\n  5. Preparar tu espacio de trabajo\n  6. Abrirlo en la app de tu teléfono\n\nConsejo: si el texto se ve pequeño, pellizca la pantalla\npara ampliarlo, o gira el teléfono de lado.\n\n'
BIB_MSG[wizard.intro.need_default]='  - una cuenta de al menos una IA: Claude,\n    ChatGPT, Google u OpenCode (paso 4)'
BIB_MSG[wizard.intro.step3_cloud]='Revisar cómo te conectas'
BIB_MSG[wizard.intro.step3_default]='Continuar desde tu teléfono o tu laptop'
BIB_MSG[wizard.resume.ssh]='Estás conectado a distancia. Seguiremos\ndesde esta terminal.\n\n'
BIB_MSG[wizard.resume.local]='Seguiremos desde el siguiente paso pendiente.\n\n'
BIB_MSG[wizard.finale.ready]='Tu Builders in a Box ya está listo%s.\n\n'

# 01-set-password.sh
BIB_MSG[wizard.pw.have.title]='Ya tienes una contraseña'
BIB_MSG[wizard.pw.have.body]='%s ya tiene una contraseña que funciona en este\nequipo.\n\nBuilders in a Box usa la contraseña de tu cuenta para\niniciar sesión desde tu teléfono, así que necesita una.\nNo tiene que ser nueva: lo normal es conservar la que\nya tienes.\n'
BIB_MSG[wizard.pw.have.question]='¿Qué quieres hacer?'
BIB_MSG[wizard.pw.have.keep]='Conservar mi contraseña actual'
BIB_MSG[wizard.pw.have.new]='Poner una nueva'
BIB_MSG[wizard.pw.scope_cloud]='el acceso sudo (administrador) a este equipo'
BIB_MSG[wizard.pw.scope_dedicated]='el acceso sudo (administrador) y tu acceso remoto'
BIB_MSG[wizard.pw.intro]='Aquí eliges la contraseña de "%s" en este equipo.\nProtege %s.\n\nNecesitarás: un gestor de contraseñas, o papel, para\nguardarla. No hay forma de recuperarla: si la pierdes,\nhay que configurar el equipo de nuevo desde cero.\n\n'
BIB_MSG[wizard.pw.prompt]='Elige una contraseña segura:'
BIB_MSG[wizard.pw.done]='Listo: la contraseña de "%s" está establecida.\nGuárdala ahora, antes de continuar.\n\n'

# 10-tailscale-up.sh
BIB_MSG[wizard.ts.intro]='Tailscale crea un enlace privado entre este equipo y tu\nteléfono o laptop. Solo tus propios dispositivos pueden\nusarlo.\n\nNecesitarás: una cuenta de Tailscale (gratuita). La página\nde inicio de sesión te deja crear una, o usar Google,\nMicrosoft o Apple.\n\nA continuación aparecen un enlace y un código QR. Abre el\nenlace en tu teléfono, inicia sesión y aprueba este equipo.\n\n'
BIB_MSG[wizard.ts.done]='\nListo: este equipo está en tu red privada.\nNombre: %s\nDirección: %s\n'
BIB_MSG[wizard.ts.addr_none]='aún no se muestra'

# 35-ssh-finalize.sh
BIB_MSG[wizard.ssh.cloud]='Tu proveedor de nube gestiona el SSH de este servidor\n(provider-managed). Builders in a Box no lo cambia:\nno añade acceso con contraseña ni toca ningún ajuste\nde SSH.\n\nEl puerto 22 puede seguir abierto a internet. Cerrarlo\nse hace en la consola de tu proveedor, más adelante,\ncuando compruebes que la app funciona.\n\nListo: SSH queda como lo dejó tu proveedor.\n\n'
BIB_MSG[wizard.ssh.open.title]='SSH sigue abierto a internet en este equipo'
BIB_MSG[wizard.ssh.open.body]='Este equipo es accesible por SSH desde %s, que está FUERA\nde tu red de Tailscale, y todavía no hay ninguna clave SSH registrada,\nasí que la contraseña es la única forma de entrar. Desactivarla ahora te\ndejaría fuera, por eso Builders in a Box NO ha marcado SSH como\nprotegido en este equipo.\n\nQué significa: mientras no lo cierres, cualquiera en internet puede\nintentar adivinar tu contraseña por SSH.\n\nPara cerrarlo, haz UNA de estas dos cosas:\n\n  1. Vuelve a conectarte a este equipo por Tailscale y ejecuta:\n       ssh %s@%s      # comprueba que llegas por la tailnet\n       sudo BIB_SSH_FORCE_TAILSCALE=1 \\\n           /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh\n     (asocia sshd solo a tu dirección privada de Tailscale)\n\n  2. Termina /tutorial en la app de Claude Code: el Beat 2 importa tu clave\n     SSH de GitHub y cierra esto automáticamente.\n\nCómo recuperarte si te quedas fuera está en ~/README.md\n("Si SSH falla alguna vez") y en SECURITY.md.\n'
BIB_MSG[wizard.ssh.open.question]='Entiendo que mi SSH sigue expuesto a internet con contraseña. ¿Qué hago ahora?'
BIB_MSG[wizard.ssh.open.opt_reconnect]='Reconectar primero por Tailscale'
BIB_MSG[wizard.ssh.open.opt_continue]='Lo entiendo, seguir expuesto por ahora'
BIB_MSG[wizard.ssh.reconnect.title]='SSH restringido a solo clave (accesible aún, no solo por tailnet)'
BIB_MSG[wizard.ssh.reconnect.body]='Estás conectado desde fuera de tu red de Tailscale, así que SSH sigue\nescuchando en la interfaz pública, pero el acceso con contraseña ya está\nDESACTIVADO y no se puede adivinar por fuerza bruta (solo clave).\n\nPara terminar de limitar SSH a tu dirección privada de Tailscale, vuelve a\nconectarte por Tailscale primero (para no quedarte fuera) y ejecuta:\n\n    ssh %s@%s      # comprueba que llegas por la tailnet\n    sudo BIB_SSH_FORCE_TAILSCALE=1 \\\n        /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh\n\nCómo recuperarte si te quedas fuera está en ~/README.md\n("Si SSH falla alguna vez") y en SECURITY.md.\n'

# 36-phone-bridge.sh
BIB_MSG[wizard.bridge.pick]='El próximo inicio de sesión es más fácil copiando y pegando.\nElige tu dispositivo: solo verás sus instrucciones.\n'
BIB_MSG[wizard.bridge.question]='¿Desde dónde vas a continuar?'
BIB_MSG[wizard.bridge.opt_laptop]='Laptop (recomendado)'
BIB_MSG[wizard.bridge.opt_phone]='Teléfono'
BIB_MSG[wizard.bridge.laptop]='Usa tu laptop para el resto de la configuración.\n\n1. Instala Tailscale.\n   Inicia sesión con la misma cuenta:\n\nhttps://tailscale.com/download\n\n2. Abre su terminal y conéctate:\n\nssh %s@%s\n\nSi ese nombre no funciona, usa:\n\nssh %s@%s\n\n3. En la sesión SSH, ejecuta:\n\nbiab\n'
BIB_MSG[wizard.bridge.phone1]='En tu teléfono, instala Tailscale.\nInicia sesión con la misma cuenta:\n\nhttps://tailscale.com/download\n'
BIB_MSG[wizard.bridge.phone2]='Instala una app de SSH, como Termius:\n\nhttps://termius.com/download\n'
BIB_MSG[wizard.bridge.phone3]='Crea una conexión SSH nueva con:\n\nHost\n%s\n\nUsername\n%s\n\nPassword\nLa contraseña que elegiste en el paso 1.\n\nSi el nombre del host no funciona, usa:\n\n%s\n\nDespués de conectarte, ejecuta:\n\nbiab\n'
BIB_MSG[wizard.bridge.ts_ip_fallback]='tu IP de Tailscale'
BIB_MSG[wizard.bridge.finished]='\nEl monitor ya ha terminado. Continúa con la sesión SSH.\n'

# 05-choose-cli.sh
BIB_MSG[wizard.cli.installing]='Instalando %s. Tarda uno o dos minutos...\n'
BIB_MSG[wizard.cli.installed]='Listo: %s está instalado.\n\n'
BIB_MSG[wizard.cli.install_failed]='05-choose-cli: %s ha fallado para %s (código de salida %s); los detalles están en %s. Ejecuta '\''sudo biab'\'' para reintentarlo.'
BIB_MSG[wizard.cli.menu_title]='Tus suscripciones de IA'
BIB_MSG[wizard.cli.card_title]='Tus suscripciones de IA'
BIB_MSG[wizard.cli.menu_intro]='Esta es la IA que se ejecutará en este equipo y\nconstruirá contigo. Todas inician sesión desde tu teléfono:\n\n'
BIB_MSG[wizard.cli.confirmed]='\nListo: se usará %s.\n\n'
BIB_MSG[wizard.cli.need]='Para iniciar sesión necesitarás:\n  %s\n\n'
BIB_MSG[wizard.cli.multi_intro]='Elige las IAs que pagas e instálalas en este equipo.\nLa primera será la principal (arranca /tutorial).\nPulsa Enter para mantener: %s\n\n'
BIB_MSG[wizard.cli.multi_pick]='¿Qué suscripciones de IA tienes?'
BIB_MSG[wizard.cli.secondary_install_failed]='Aviso: no se pudo instalar %s (salida %s,\ndetalles en %s). Seguimos con el resto.\nReintenta luego con: biab subscription add %s\n\n'

# 38-ai-cli-login.sh
BIB_MSG[wizard.login.intro]='Ahora inicias sesión en %s, para que la IA de\neste equipo trabaje con tu cuenta.\n\nVas a necesitar:\n  %s\n\n'
BIB_MSG[wizard.login.done]='\nListo: has iniciado sesión en %s.\n'
BIB_MSG[wizard.login.already]='%s ya tiene la sesión iniciada.\n'
BIB_MSG[wizard.login.secondary_intro]='\nSiguiente IA: %s\nVas a necesitar:\n  %s\n\n'
BIB_MSG[wizard.login.secondary_ask]='Pulsa Enter para entrar, o s para saltar.\n> '
BIB_MSG[wizard.login.secondary_skipped]='Se omite %s por ahora.\nInicia sesión luego con: biab subscription add %s\n\n'
BIB_MSG[wizard.login.secondary_failed]='No se pudo verificar el acceso de %s.\nSeguimos con el resto.\nReintenta luego con: biab subscription add %s\n\n'

# 40-scaffold.sh
BIB_MSG[wizard.scaffold.intro]='Esto prepara tu espacio de trabajo: una carpeta llamada\nai-platform en tu carpeta personal, más los skills que usa\ntu IA (revisión de código, specs, depuración y más).\n\nNo necesitas nada. Tarda más o menos un minuto.\n\n'
BIB_MSG[wizard.scaffold.done]='Listo: %s skills instalados. Tu espacio de trabajo está\nen ~/ai-platform\n'

# 50-paseo.sh
BIB_MSG[wizard.paseo.intro]='Esto inicia tu primer agente de IA en el equipo y te da\nla forma de hablar con él desde tu teléfono: la app Paseo.\n\n'
BIB_MSG[wizard.paseo.starting]='Iniciando tu primer agente...\n\n'
BIB_MSG[wizard.paseo.not_answering]='El servicio de la app todavía no responde.\n\n'
BIB_MSG[wizard.paseo.no_app]='%s todavía no funciona en la app Paseo.\n\n'
BIB_MSG[wizard.paseo.not_permissioned]='%s funciona en la app solo mientras sus propios\najustes le hagan pedir permiso antes de editar archivos\no ejecutar comandos. Ahora mismo: %s\nCorrígelo y ejecuta "biab" de nuevo.\n\n'
BIB_MSG[wizard.paseo.pair_intro]='Tu primer agente ya está funcionando en este equipo. Ahora\nconecta a él la app de tu teléfono.\n\nNecesitarás: tu teléfono, con Tailscale activado, y la app\nPaseo de la tienda de apps de tu teléfono.\n\n'
BIB_MSG[wizard.paseo.pair_ask]='Cuando la app muestre tu equipo, pulsa Enter.\nEscribe s para saltar y emparejar más tarde.\n> '
BIB_MSG[wizard.paseo.pair_notseen]='El equipo todavía no ve tu teléfono. Revisa la contraseña,\nque Tailscale esté activo y "Use SSL" desactivado.\n\n'
BIB_MSG[wizard.paseo.paired]='Listo: tu teléfono está conectado.\n\nHemos borrado la pantalla para que la contraseña no quede\nvisible (algunas apps guardan su propio historial).\nPara verla de nuevo:\n\n%s\n\n'
BIB_MSG[wizard.paseo.pair_later]='Sin problema. Para emparejar más tarde, ejecuta esto\nen el equipo:\n\n%s\n\nHemos borrado la pantalla para que la contraseña no quede\nvisible (algunas apps guardan su propio historial). Ese\ncomando la muestra de nuevo.\n\n'
BIB_MSG[wizard.paseo.extra_providers]='Otras IAs disponibles en la app Paseo: %s\n'
BIB_MSG[wizard.paseo.extra_ssh]='También instaladas por SSH (sin Paseo): %s\n'
