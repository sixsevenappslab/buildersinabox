# Tu Builders in a Box

<!-- BIB:paseo:start -->
Lo lograste. El dispositivo está configurado. A partir de ahora abres tu
equipo desde la **app Paseo** en tu teléfono (o en tu laptop), por tu red
privada de Tailscale. Tu agente y tus proyectos son espacios de trabajo en
la app; siguen funcionando en el equipo cuando la cierras, y retomas justo
donde lo dejaste. No necesitas un cliente SSH en el día a día.
<!-- BIB:end -->

## Empieza aquí

<!-- BIB:paseo:start -->
Abre la app Paseo y busca el espacio de trabajo **"BIAB · ai-platform"**
con el agente **"BIAB · Start here"**. Ya está en marcha y te saluda solo:
abre el tutorial por ti.
<!-- BIB:end -->
<!-- BIB:codex:start -->
(En Codex invocas las skills como `$tutorial`, no como `/tutorial`.)
<!-- BIB:end -->
<!-- BIB:opencode:start -->
(OpenCode carga las skills con su propia herramienta `skill`: no escribes
`/tutorial`, lo pides, por ejemplo "ejecuta la skill tutorial".)
<!-- BIB:end -->
<!-- BIB:paseo:start -->

¿Aún no lo has emparejado? Ejecuta esto en el equipo y sigue los pasos que
imprime:

    sudo biab paseo pair
<!-- BIB:end -->

El tutorial es la introducción guiada: 8 pasos cortos, unos 10 minutos, y
puedes saltarlo. Cubre la autenticación de GitHub, las dos specs de proyecto
incluidas, la creación de tu primer proyecto, cómo cambia el contexto de tu
IA según la carpeta, darle a cada proyecto su propio lugar de trabajo, y las
skills de SDD con una demostración en vivo de `/sdd-coordinator`.

Si ya terminaste el tutorial y quieres repasar la visión de conjunto,
escribe `/whats-ahead`. Para preparar más proyectos después, usa
`/first-project` y `/second-project`.

## Cómo te conectas desde el teléfono (o la laptop)

Durante la configuración, el asistente te pregunta si sigues desde una laptop
o desde un teléfono, y te muestra solo los pasos de ese dispositivo. Esta
página guarda la ruta como referencia para más adelante.

<!-- BIB:paseo:start -->
La forma sencilla y por defecto es la app Paseo, por tu red privada de
Tailscale:

1. Instala la app **Paseo** desde la tienda de aplicaciones de tu teléfono.
2. Comprueba que **Tailscale** está conectado en ese dispositivo, con la
   misma cuenta que usaste durante la configuración.
3. En la app, abre Settings, luego Add host y elige **Direct
   connection**. Introduce el host, el puerto y la contraseña que imprime
   `sudo biab paseo pair` en el equipo. Deja "Use SSL" desactivado.
4. La app lista tus espacios de trabajo. Justo después de la configuración
   verás uno: "BIAB · ai-platform". Cada proyecto que crees con
   `/first-project` añade su propio espacio de trabajo.

Toca un espacio de trabajo para abrirlo y luego inicia un agente nuevo o
abre uno que ya esté en marcha.
<!-- BIB:end -->

## Qué está funcionando ahora mismo

<!-- BIB:paseo:start -->
Un pequeño servicio en segundo plano, `biab-paseo`, con el que habla la app.
Escucha solo en tu red de Tailscale (nunca en tu red doméstica ni en
internet), pide la contraseña y tiene el relay desactivado. Un vigilante lo
reinicia si se detiene; `biab status` muestra cómo va.

Tu primer agente se ejecuta en el espacio de trabajo `~/ai-platform/` con la
skill `/tutorial`. Cada proyecto que creas pasa a ser su propio espacio de
trabajo, con sus propios agentes.
<!-- BIB:end -->
<!-- BIB:opencode:start -->

OpenCode se ejecuta en la app con reglas de permisos que BIAB escribió en
`~/.config/opencode/opencode.json`: te pregunta antes de editar un archivo,
abrir una página web o ejecutar un comando de shell, salvo unos pocos de solo
lectura (`git log`, `ls`, `pwd`). OpenCode por sí mismo lo permite
todo si no se le indica lo contrario, así que BIAB solo lo ofrece en la app
mientras ese archivo siga preguntando. Si lo cambias para que las ediciones o
los comandos dejen de preguntar, el siguiente `biab update` te lo dice y
OpenCode sigue accesible por SSH. Dos límites: un proyecto que tenga su
propio `opencode.json` puede anular estas reglas, y "Always allow" en la app
dura solo la sesión. OpenCode no tiene turno de noche.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->

Antigravity se ejecuta en la app con su modo `agy acp`. Te pregunta antes de
ejecutar un comando de shell, escribir un archivo en el proyecto, en tu
carpeta personal, en `~/.biab` o en `/var/tmp`, o leer un archivo fuera de tu
proyecto: la petición aparece en la app y espera tu respuesta. No pregunta
antes de leer dentro del proyecto, buscar en la web, abrir una página web ni
escribir en `/tmp`. El aviso ofrece solo permitir una vez o rechazar, sin
permitir siempre; el interruptor Auto Accept es aparte.
<!-- BIB:end -->

## Hablar con tu IA

Cuando estés dentro de cualquier sesión, escribe sin más. Tu IA te escucha.
Prueba:

> *"Ayúdame a esbozar cómo sería un programador de mensajes de Slack"*

> *"Guíame para escribir un pequeño script de Python que vigile mi carpeta
>  de descargas y renombre los PDF."*

> *"Revisa lo que acabo de cambiar y dime si algo parece mal."*

## Skills — tu IA con experiencia concreta

Este dispositivo trae **19 skills precargadas**. Escribe `/` dentro de
cualquier sesión y empieza a teclear el nombre. Algunas que quizá quieras:

### Introducción guiada
- `/tutorial` — la introducción posterior a la instalación (8 pasos, unos 10
  min). Empieza sola la primera vez que abres tu primer agente; puedes
  volver a invocarla cuando quieras para retomar el siguiente paso sin hacer.
- `/first-project` — se invoca desde el paso 4 de `/tutorial`, y también por
  su cuenta. Elige un nombre, crea la carpeta, copia la spec FEAT elegida,
  hace init + commit + push a GitHub (si has iniciado sesión) y lo convierte
  en un espacio de trabajo propio.
- `/second-project` — tu segundo recorrido guiado: elegir una plataforma en
  la nube (Cloudflare, Firebase o GCP), comprar un dominio y empezar
  FEAT-003 (la app de finanzas personales que se publica en producción).
- `/whats-ahead` — recorrido de repaso del sistema cuando ya terminaste el
  tutorial.
- `/extend-yourself` — para cuando quieras enseñarle un truco nuevo al
  dispositivo (skill, ayudante de shell, paso del asistente, FEAT incluida).
  Te guía sobre dónde poner cada cosa.

### Construir productos digitales de principio a fin
- `/sdd-base` — léela primero para entender el flujo de trabajo que defiende
  este dispositivo (desarrollo guiado por specs).
- `/sdd-coordinator` — habla con ella como con un Product Lead. "Quiero
  construir X, ayúdame a escribir una spec."
- `/sdd-spec-writer` — voz de Tech Lead. Investiga tu código y redacta la
  spec técnica.
- `/sdd-qa` — voz de QA Lead. Escribe planes de pruebas.
- `/sdd-growth` — voz de Growth. Útil cuando una función toca marketing o
  onboarding.
- `/sdd-docs` — planifica el trabajo de documentación cuando se publica una
  función.

### Consultoría experta a demanda
- `/backend-engineer` — perspectiva de backend senior.
- `/ui-ux-consultant` — consejos de UI/UX.
- `/executive` — estrategia y priorización.
- `/product-marketing` — posicionamiento, conversión, crecimiento.

### Herramientas a nivel de código
- `/code-review` — pásale un diff o una rama y recibe una revisión
  estructurada.
- `/code-simplifier` — refactoriza código reciente para que sea más claro.
- `/qa-testing` — genera un plan de pruebas a partir de una spec.
- `/documentator` — genera documentación técnica (CLAUDE.md, changelogs).
- `/ux-review` — evaluación heurística de UX.

¿Quieres más skills más adelante? Deja una carpeta en
`~/.agents/skills/<name>/` que contenga un `SKILL.md`. Se enlaza solo en la
ruta de skills de tu IA (eso es lo que hace `biab add`).

## Cambiar de contexto

<!-- BIB:paseo:start -->
Cada proyecto es su propio espacio de trabajo en la app, con sus propios
agentes y su propia carpeta. Abre otro espacio de trabajo para cambiar de
contexto. Para una carpeta aparte que no sea un proyecto, ejecuta
`/opt/buildersinabox/paseo/bin/biab-workspace <carpeta>` y también aparece en
la app.
<!-- BIB:end -->

<!-- BIB:guard-claude:start -->
## Protección de comandos de shell

En Claude Code, la protección de comandos de shell es el hook **Guardrail**
que se describe justo debajo: antes de que se ejecute un comando de shell,
bloquea los claramente destructivos y te pregunta por los arriesgados pero
legítimos. Es un freno, no un candado: una lista de patrones que atrapa las
formas habituales de destruir un equipo, no un sandbox, y vive en un archivo
de tu carpeta personal, así que un agente al que dejes editar su propia
configuración puede cambiarla. `biab status` muestra si está registrada.

<!-- BIB:end -->
<!-- BIB:guard-codex:start -->
## Protección de comandos de shell

Builders in a Box registra una protección para Codex. Antes de que se ejecute
un comando de shell, rechaza los claramente destructivos (`rm -rf /`, `mkfs`,
`dd` sobre un disco, una fork bomb, `curl … | sudo bash`, un force-push a
`main`/`master`).

**Necesita tu aprobación una vez.** Codex ejecuta un hook solo después de que
lo apruebes: entra por SSH, ejecuta `codex`, escribe `/hooks` y aprueba la
entrada de Builders in a Box. Hasta entonces `biab status` dice PENDING
APPROVAL y Codex se salta la protección (`codex exec` también). Si la entrada
se edita más tarde, Codex vuelve a preguntar y `biab status` te lo avisa.

Lo que no hace. Nunca te pide que confirmes nada: un simple
`curl … | bash` o un push con `--force-with-lease` se deja a las reglas de
aprobación propias de Codex. Es una lista de patrones, no un sandbox, así que
un comando destructivo escrito de una forma que ningún patrón recoge pasa. Y
es un freno, no un candado: vive en `~/.codex/hooks.json`, en tu carpeta
personal, así que un agente al que dejes editar su propia configuración puede
quitarla (`biab status` lo detecta). La protección se ha comprobado en las
pruebas contra la propia lista de hooks de Codex; falta todavía verla
rechazar un comando en una sesión real con la sesión iniciada.
<!-- TODO(2026-11-05): drop the last sentence once the hardware pass (FEAT-042 T6) has seen it block. -->

Para desactivarla: `touch ~/.biab/hooks-disabled`, o define
`BIAB_HOOKS_DISABLED=1`, o desactiva la entrada en `/hooks`.

<!-- BIB:end -->
<!-- BIB:guard-opencode:start -->
## Protección de comandos de shell

OpenCode ya pregunta antes de ejecutar un comando de shell (arriba). Además,
Builders in a Box añade reglas de rechazo a `permission.bash` en
`~/.config/opencode/opencode.json`, después de tus propias claves y sin
cambiar nunca ninguna tuya. Rechazan las formas simples de `mkfs`, `wipefs`,
`dd` sobre un disco, una redirección a un disco, escrituras con `parted` y
`sgdisk`, un `rm` recursivo, y `chmod` o `chown` de `/` o de tu carpeta
personal, y un force-push a `main`/`master`.

**Esta protección cubre un conjunto menor que la de Claude Code y Codex, y
`biab status` dice PARTIAL.** OpenCode compara cada comando con patrones de
texto fijos, no con expresiones regulares, así que algunas formas pasan: una
tubería hacia un shell (`curl … | bash`), un destino entre comillas
(`rm -rf "/"`), `rm -rf /*`, comandos dentro de `bash -c`, un comando que
empieza por otra cosa (`sudo` antes de un force-push, `env`, `VAR=1 rm`) y un
comando partido en dos líneas. También puede rechazar algunos comandos
inofensivos, como `git push -f` a una rama cuyo nombre contiene `main`.

Dos límites más. No está confirmado que un subagente obedezca estas reglas. Y
un `opencode.json` propio de un proyecto que lo permita todo, o los ajustes
`OPENCODE_PERMISSION` y `OPENCODE_CONFIG_CONTENT`, las anulan. Es un freno, no
un candado: el archivo es tuyo.

Para desactivarla: `touch ~/.biab/hooks-disabled` impide que Builders in a Box
añada reglas. Las que ya están en el archivo se quedan; para quitarlas, borra
las claves que imprime `bash /opt/buildersinabox/payload/hooks/opencode-guard.sh keys`.

<!-- BIB:end -->
<!-- BIB:guard-antigravity:start -->
## Protección de comandos de shell

Builders in a Box instala un plugin de Antigravity (`biab-guard` en
`~/.gemini/config/plugins/biab-guard`) con hooks `PreToolUse`, `PostToolUse`
y `SessionStart`. Antes de que se ejecute un comando de shell, bloquea los
claramente destructivos (`rm -rf /`, `mkfs`, `dd` sobre un disco, una fork
bomb, `curl … | sudo bash`, un force-push a `main`/`master`) y te pide que
confirmes los arriesgados pero legítimos (un simple `curl … | bash`, un push
con `--force-with-lease`), con las mismas reglas que la protección de Claude
Code. También pregunta antes de que `run_command`, `read_file` o `view_file`
lean un archivo de credenciales o secretos (`.env`, claves privadas de
`~/.ssh`, archivos de tokens de las CLI), da formato a los archivos editados
cuando hay un formateador instalado y muestra las specs pendientes al empezar
la sesión.

Es un freno, no un candado: una lista de patrones, no un sandbox, y vive en
tu carpeta personal (`~/.gemini/config/plugins/biab-guard`), así que un agente
al que dejes editar su propia configuración puede desactivarla o quitarla
(`biab status` lo detecta).

Para desactivarla: `touch ~/.biab/hooks-disabled`, define
`BIAB_HOOKS_DISABLED=1` o ejecuta `agy plugin disable biab-guard`.

<!-- BIB:end -->
<!-- BIB:no-guard:start -->
## Aquí no hay protección de comandos de shell

Builders in a Box no añade ninguna protección propia de comandos de shell a
esta IA. Lo que protege el equipo aquí son los avisos de permisos de la
propia IA (descritos arriba), y valen tanto como tus respuestas: lee un
comando antes de permitirlo. `biab status` lo muestra como `guard none`.

<!-- BIB:end -->
<!-- BIB:claude:start -->
## Hooks — protecciones y pulido automáticos

Tu equipo trae cuatro hooks de Claude Code, activados por defecto. Se
ejecutan solos alrededor de lo que hace el agente, sin que tengas que pedir
nada:

- **Guardrail** — antes de que se ejecute cualquier comando de shell, bloquea
  los inequívocamente destructivos (`rm -rf /`, `mkfs`, `dd` sobre un disco,
  una fork bomb, `curl … | sudo bash`, un force-push a `main`/`master`) y te
  pide que confirmes los arriesgados pero legítimos (un simple
  `curl … | bash`, un push con `--force-with-lease`). Los comandos de todos
  los días pasan directamente.
- **Formateador** — después de que el agente edita o escribe un archivo,
  ejecuta sobre él el formateador de tu proyecto (prettier / black / ruff /
  gofmt / rustfmt / shfmt). ¿No hay formateador instalado? No hace nada.
- **Avisos del linter** — ejecuta el linter de tu proyecto sobre el archivo
  editado y devuelve los hallazgos al agente para que se corrija solo. Nunca
  bloquea la edición.
- **Registro de sesión** — al terminar una sesión, añade una línea a
  `~/.claude/logs/biab-sessions.log` (hora, sesión, carpeta, cuántas
  ediciones/comandos, qué archivos se tocaron). Solo metadatos: nunca tus
  comandos, el contenido de tus archivos ni secretos. Útil para auditar el
  trabajo sin supervisión.

Todo se degrada sin ruido: si no hay un formateador o un linter instalado, el
hook simplemente no hace nada.

**Para desactivarlos**, elige una opción:

- Quita la clave `hooks` de `~/.claude/settings.json` (o solo el bloque que
  no quieras).
- Define `BIAB_HOOKS_DISABLED=1` en tu entorno.
- Crea el archivo centinela: `touch ~/.claude/hooks-disabled`.

(Estos hooks usan el formato de configuración propio de Claude Code. Las
demás IA tienen su propia protección, o ninguna: consulta "Protección
de comandos de shell" más arriba.)

<!-- BIB:end -->
<!-- BIB:paseo:start -->
## Acceso de respaldo — SSH

Si alguna vez la app Paseo no puede llegar a tu equipo, hay una alternativa
que no necesita ninguna app:

1. Instala Termius (o cualquier cliente SSH) en tu teléfono.
2. Añade un host con el nombre que muestra `tailscale status` en el
   dispositivo (es el nombre del dispositivo en tu tailnet).
3. La autenticación es la contraseña de tu cuenta, o tu clave de GitHub si
   la importaste.
4. Una vez dentro, inicia tu IA a mano (`claude`, `codex` o `agy`).

Tus claves SSH de GitHub también están en `~/.ssh/authorized_keys`, así que
un simple `ssh <username>@<tailscale-ip>` también funciona. `biab status`
imprime este comando siempre que el servicio de la app no está sano.
<!-- BIB:end -->

## Si SSH falla alguna vez

<!-- BIB:paseo:start -->
SSH por Tailscale es tu alternativa cuando la app no puede llegar al equipo,
así que ten esto a mano:
<!-- BIB:end -->

- Comprueba que el equipo está en tu tailnet: ejecuta `tailscale status`
  desde otro dispositivo. Si el equipo aparece sin conexión, apágalo y
  vuelve a encenderlo.
- Tus claves SSH de GitHub están en `~/.ssh/authorized_keys`, así que `ssh
  <username>@<tailscale-ip>` funciona con tu clave en lugar de la contraseña.
<!-- BIB:antigravity:start -->
- Si `agy` dice que cerraste la sesión, entra por SSH y ejecuta `agy` una vez
  de forma interactiva para repetir el OAuth de Google (elige "Google
  OAuth", pega el código de autorización).
<!-- BIB:end -->
<!-- BIB:opencode:start -->
- Si `opencode` dice que cerraste la sesión, entra por SSH y ejecuta
  `opencode auth login` (elige OpenCode Go o Zen y pega tu clave de
  https://opencode.ai/auth, o elige otro proveedor que pagues).
<!-- BIB:end -->
<!-- BIB:codex:start -->
- Si `codex` dice que cerraste la sesión, entra por SSH y ejecuta `codex login
  --device-auth` (antes comprueba que "device code login" esté activado en
  ChatGPT → Settings → Security), o redirige el puerto de inicio de sesión e
  inicia sesión de la forma normal: `ssh -L 1455:localhost:1455
  <username>@<tailscale-ip>` y luego `codex login`.
<!-- BIB:end -->

**¿Te quedaste fuera después de limitar SSH a Tailscale (VPS)?** Cuando
Tailscale está activo, sshd queda restringido solo a tu dirección privada de
Tailscale. Si la tailnet no enruta y no puedes volver a entrar, cualquiera de
estas opciones restaura el acceso sin reinstalar:

1. Desde la consola web o serie de tu proveedor de VPS, vuelve a abrir el
   acceso público de sshd:

       sudo rm -f /etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf \
                  /etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf
       sudo systemctl daemon-reload && sudo systemctl reload ssh

2. Cuando puedas volver a llegar al equipo por la tailnet, aplica de nuevo la
   restricción:

       sudo BIB_SSH_FORCE_TAILSCALE=1 \
           /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh

   (`BIB_SSH_FORCE_TAILSCALE=1` aplica la restricción sin volver a comprobar
   el enrutamiento de la tailnet: úsalo solo si tienes confirmado otro
   acceso. sshd se recarga, no se reinicia, así que una sesión activa
   sobrevive.)

3. En un mini PC, conecta un teclado y un monitor y haz la misma edición que
   en el punto (1).

## Dónde está cada cosa

```
~/ai-platform/                   <- la raíz de tu espacio de trabajo
├── CLAUDE.md / AGENTS.md
├── projects/
│   └── {{PROJECT_NAME}}/
│       ├── CLAUDE.md / AGENTS.md
│       └── specs/
│           ├── draft/FEAT-002-personal-slack-coach.md   <- tu primer trabajo
│           ├── draft/FEAT-003-personal-finance-app.md   <- el segundo
│           ├── active/      (cuando empiezas a implementar)
│           └── completed/   (cuando lo publicas)
└── stratops/
    ├── CLAUDE.md / AGENTS.md
    └── README.md

~/.agents/skills/                <- skills incluidas (y las que añadas)
<!-- BIB:claude:start -->
~/.claude/skills/                <- las mismas skills, enlazadas desde arriba
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
~/.claude/skills/                <- las mismas skills, enlazadas desde arriba
<!-- BIB:end -->
~/.bashrc.d/                     <- ayudantes de shell (p. ej. git-helpers.sh)
/var/lib/buildersinabox/         <- estado de la configuración (no lo toques si no te lo piden)
/var/log/buildersinabox/         <- registros del arranque y del asistente
```

<!-- BIB:claude:start -->
## La URL de inicio de sesión de Claude es demasiado larga para el OCR — qué hacer

El tercer inicio de sesión del asistente es el de Claude Code. Dentro de la
interfaz de Claude escribes `/login` y imprime una URL de OAuth muy larga,
incómoda de teclear a mano y demasiado larga para que el reconocimiento de
texto de tu teléfono la capture con fiabilidad desde un monitor.

Por eso el asistente de configuración hace una pausa hacia la mitad y te
pide que entres por SSH desde otro dispositivo, teléfono O laptop, a tu
elección. En una sesión SSH la URL aparece en una terminal de verdad, donde
puedes mantener pulsado para copiar (teléfono) o arrastrar con el ratón
(laptop), y pegarla directamente en tu navegador.

Si acabaste intentando iniciar sesión en Claude en el monitor del propio
dispositivo y estás atascado, entra por SSH desde tu teléfono o tu laptop:

- **Desde tu teléfono**: abre ConnectBot o Termius (configura el host con la
  contraseña de sudo como credencial), conéctate, y luego `claude` y
  `/login`. Mantén pulsada la URL para copiarla.

- **Desde tu laptop**: desde cualquier ordenador de tu tailnet:
      ssh {{TARGET_USER}}@{{HOSTNAME}}
  Ejecuta `claude` y `/login`. Copia y pega en la terminal.

- **Salta Claude ahora y vuelve más tarde**:
      t="$(sudo mktemp /var/lib/buildersinabox/state.XXXXXX)" && \
      sudo jq '.phases.ai_cli_done = true' \
        /var/lib/buildersinabox/state.json | sudo tee "$t" >/dev/null && \
      sudo mv "$t" /var/lib/buildersinabox/state.json && \
      sudo chmod 644 /var/lib/buildersinabox/state.json && \
      sudo /opt/buildersinabox/payload/install.sh
  El asistente sigue sin Claude. Inicia sesión más tarde entrando por SSH y
  ejecutando `claude` y luego `/login`.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
## La URL de inicio de sesión de agy es larga — qué hacer

Antigravity inicia sesión con OAuth de Google. Cuando ejecutas `agy` sin
sesión iniciada, eliges "Google OAuth" y imprime una URL de inicio de sesión
larga, incómoda de teclear a mano y demasiado larga para que el
reconocimiento de texto de tu teléfono la capture con fiabilidad desde un
monitor.

Por eso el asistente de configuración hace una pausa hacia la mitad y te
pide que entres por SSH desde otro dispositivo, teléfono O laptop, a tu
elección. En una sesión SSH la URL aparece en una terminal de verdad, donde
puedes mantener pulsado para copiar (teléfono) o arrastrar con el ratón
(laptop), y pegarla directamente en tu navegador, iniciar sesión y pegar el
código de autorización de vuelta en `agy`.

Si `agy` alguna vez dice que cerraste la sesión, entra por SSH y ejecuta
`agy` una vez de forma interactiva para repetirlo:

    ssh {{TARGET_USER}}@{{HOSTNAME}}
    agy        # elige "Google OAuth", pega el código
<!-- BIB:end -->
<!-- BIB:codex:start -->
## El inicio de sesión de Codex usa un código de dispositivo — qué hacer

Codex inicia sesión con tu cuenta de ChatGPT mediante un código de
dispositivo. Primero, desde cualquier navegador, ACTIVA "device code login"
en ChatGPT → Settings → Security (sin eso el inicio de sesión con código se
rechaza). Después, en una sesión SSH, ejecuta el inicio de sesión: la URL y el
código corto aparecen en una terminal de verdad, donde puedes mantener
pulsado para copiar (teléfono) o arrastrar con el ratón (laptop):

    ssh {{TARGET_USER}}@{{HOSTNAME}}
    codex login --device-auth   # abre la URL, introduce el código, aprueba

Si el inicio de sesión con código no funciona de ninguna manera, redirige el
puerto local de inicio de sesión de Codex e inicia sesión de la forma
normal:

    ssh -L 1455:localhost:1455 {{TARGET_USER}}@{{HOSTNAME}}
    codex login
<!-- BIB:end -->

## Cuando algo no va bien

<!-- BIB:paseo:start -->
- **La app no se conecta:** ejecuta `biab status` en el equipo (o por SSH).
  Dice si el servicio de la app está sano y, si no, imprime el comando SSH
  que sigue funcionando. Comprueba también que Tailscale está activo en tu
  teléfono.
- **La app vuelve a pedir la contraseña, o cambiaste de teléfono:** ejecuta
  `sudo biab paseo pair` para ver los valores, o `sudo biab paseo pair
  --rotate` para una contraseña nueva.
- **`biab status` dice que el servicio se dio por vencido:** ejecuta
  `sudo biab paseo restart`.
<!-- BIB:end -->
<!-- BIB:claude:start -->
- **Claude dice "please login" o se niega a arrancar:** entra por SSH (ruta
  de respaldo de arriba), ejecuta `claude` una vez de forma interactiva y
  repite el inicio de sesión.
<!-- BIB:end -->
<!-- BIB:antigravity:start -->
- **`agy` dice "please sign in" o se niega a arrancar:** ejecuta `agy` una
  vez de forma interactiva por SSH y repite el OAuth de Google.
<!-- BIB:end -->
<!-- BIB:opencode:start -->
- **`opencode` dice que no tiene credenciales o se niega a arrancar:**
  ejecuta `opencode auth login` por SSH y pega tu clave otra vez.
<!-- BIB:end -->
<!-- BIB:codex:start -->
- **`codex` dice "please sign in" o se niega a arrancar:** ejecuta `codex login
  --device-auth` por SSH (antes activa "device code login" en ChatGPT →
  Settings → Security), o redirige el puerto y ejecuta `codex login`.
<!-- BIB:end -->
- **No puedes llegar al dispositivo de ninguna manera:** comprueba
  `tailscale status` desde otro dispositivo de tu tailnet. Si el equipo
  aparece sin conexión, apágalo y vuelve a encenderlo (o reinícialo desde la
  consola de tu proveedor).
- **El asistente no terminó y quieres reiniciarlo:** como root, ejecuta
  `touch /var/lib/buildersinabox/firstboot.pending` y reinicia.
- **Idioma equivocado:** `biab lang` muestra el idioma de este equipo y
  `biab lang en` o `biab lang es` lo cambia, también para el agente y
  para los proyectos nuevos. Este archivo solo se reescribe si no lo has editado; si
  no, la versión nueva se guarda a su lado como `README.<code>.md`
  (`<code>` es el idioma nuevo, `en` o `es`).

## Recuperación — empezar de cero

Esta máquina es tuya. Si alguna vez necesitas borrarlo todo y empezar de
nuevo, reinstala Ubuntu Server 24.04 (o vuelve a aprovisionar el VPS, o
vuelve a grabar la memoria USB si este equipo llegó como regalo) y ejecuta el
instalador otra vez:

    curl -fsSL https://buildersinabox.com/install.sh | sudo bash

Tu código está a salvo: vive en GitHub. Reinstalar solo pierde el estado
local (registros, la sesión local de IA, lo que no hayas subido).

Para quitar Builders in a Box de esta máquina sin reinstalar el sistema
operativo:

    sudo /opt/buildersinabox/payload/install.sh --uninstall

Eso quita todo lo que es de BIAB y deja intactos tu carpeta personal,
Tailscale y tus sesiones de GitHub y de la IA.

## Qué es este equipo — y qué no

Es **tuyo**. Tuyos son el hardware, los datos y las claves. Nada de aquí
llama a casa salvo las llamadas a la API de IA que *tú* haces con *tu*
propia cuenta.
<!-- BIB:paseo:start -->
Lo único extra que se ejecuta es el servicio de la app del teléfono: escucha
solo en tu red privada de Tailscale, pide una contraseña y tiene el relay
desactivado. `sudo /opt/buildersinabox/payload/install.sh --uninstall` lo
quita.
<!-- BIB:end -->

**No** es un servicio gestionado. No hay equipo de soporte. Si una
actualización de origen cambia una opción de una CLI y algo se rompe, tienes que
arreglarlo tú (o quien te lo regaló). Todo es código abierto en
`/opt/buildersinabox/` (el repositorio git completo) y
`~/ai-platform/payload/` (tu copia viva): léelo, cámbialo, hazlo tuyo.

Cuando quieras enseñarle al dispositivo un truco nuevo (una skill nueva, un
ayudante de shell, un paso del asistente, una FEAT incluida), escribe
`/extend-yourself` en cualquier sesión. Es una guía interactiva de todo lo que
puedes añadir. Todo el sistema está pensado para que lo modifique su dueño;
nada está hecho para quedarse congelado.
