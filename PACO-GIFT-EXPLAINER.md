---
title: "El regalo para Paco — un Builders in a Box"
subtitle: "Qué le hemos preparado entre todos y cómo lo va a vivir, paso a paso"
audience: "Las personas que participamos en el regalo a Paco"
language: "Español"
intended_use: "Subir a NotebookLM y generar un vídeo explicativo para enseñar al grupo qué le estamos regalando"
---

# El regalo para Paco

Le estamos regalando entre todos un **Builders in a Box** — un pequeño ordenador con un USB que, juntos, convierten una caja vacía en su entorno personal de desarrollo con inteligencia artificial. Pensado para que Paco pueda construir software desde el móvil, en cualquier momento, sin depender de servicios externos ni saber montar infraestructura por su cuenta.

Este documento explica qué hay en la caja, qué experiencia va a vivir Paco desde que la abra hasta que esté trabajando con Claude desde su móvil, y qué va a poder construir él en los primeros días. Está escrito para que cualquiera de nosotros (no necesariamente programador) pueda entender el regalo.

---

## 1 · La idea grande, en una frase

> *Un mini PC vacío + un USB = en 25 minutos, Paco tiene su propio servidor de desarrollo personal en casa, con un asistente de inteligencia artificial dentro, accesible desde el móvil con un solo tap, y dos proyectos reales esperándole para empezar.*

No es un servicio en la nube. No es una suscripción. Es **hardware suyo, datos suyos, claves suyas**. Lo controla, lo apaga, lo cambia. Le dura años.

---

## 2 · Por qué Paco

Paco quiere construir cosas. Tiene ideas. Tiene tiempo aquí y allá: el metro, una tarde de fin de semana, las dos horas después de cenar. Pero hoy esas ventanas de tiempo se le escapan porque para "ponerse" necesita ir al ordenador, abrir cosas, recordar dónde dejó el contexto.

Nuestro regalo es eliminar esa fricción. Paco abre la **app de Claude Code** en su móvil, hace tap en una de sus sesiones, y está dentro de su entorno de trabajo, con Claude esperándole, en la ventana exacta donde lo dejó. **Cero comandos, cero SSH, cero "configurar el cliente".** Si tiene 15 minutos, son 15 minutos productivos. Si tiene 3 horas, son 3 horas productivas.

También le quitamos el miedo de "no sé montar nada". El USB se encarga de todo. Paco enchufa, sigue 4 pasos en pantalla, y está listo.

---

## 3 · Qué hay en la caja

1. **Un mini PC** — un AMD Ryzen 3 7430U con 32 GB de RAM, suficiente para tener varios proyectos corriendo en paralelo durante años. Caja del tamaño de un libro, silencioso, consume poco. Se conecta a la corriente y al router por cable.

2. **Un USB** — un pendrive con todo lo necesario para instalar Ubuntu y el entorno de Paco. Es la pieza mágica. Hicimos el USB nosotros.

3. **Una tarjeta de bienvenida** — del tamaño de una postal pequeña, con los 4 pasos del primer arranque, para que Paco no tenga que buscar nada.

---

## 4 · La experiencia, minuto a minuto

### Minuto 0 — Paco desempaqueta

Abre la caja, ve el mini PC, el USB y la tarjeta. Lee la tarjeta:

```
1. Plug everything in. Ethernet, monitor, keyboard, USB stick. Power on.
2. Wait ~10 minutes. Ubuntu installs by itself.
3. Follow the wizard on screen. ~5 minutes of logins.
4. Install the Claude Code app on your phone. Your sessions appear there.
```

Conecta cable Ethernet, monitor HDMI, teclado USB (los necesita una sola vez, los desconecta para siempre después de los primeros 25 minutos). Conecta el USB. Pulsa el botón de encendido.

### Minuto 1–10 — Ubuntu se instala solo

El mini PC arranca desde el USB. Aparece el instalador de Ubuntu, pero Paco no tiene que hacer nada: el USB lleva una configuración que dice *"instálate solo, así, con este usuario, con este disco, sin preguntar"*.

Mientras tanto en pantalla pasan logs técnicos. Paco puede ir a por un café.

El sistema se reinicia automáticamente cuando termina.

### Minuto 11 — el wizard arranca solo

El mini PC reinicia. La pantalla muestra el prompt de login. Pero antes de que Paco escriba nada, el sistema hace login automático con el usuario `paco`, y arranca un asistente de configuración (lo llamamos "el wizard").

Lo primero que ve Paco es esto:

```
======================================================================
  Builders in a Box — setup wizard
======================================================================

We'll walk through a few quick steps. Each step gives you a URL to open
on your phone (or laptop). Read the URL straight from this screen,
type it into your phone's browser, complete the login, and come back
here and press Enter.

Heads up — this wizard will ask you to log into three services:

  1. Tailscale  (private network for SSH from your phone)
  2. GitHub     (so this device can clone/commit/push for you)
  3. Your AI CLI: Claude Code or Gemini

If you don't have a Tailscale or GitHub account yet, that's fine: the
login page lets you sign up in 30 seconds.

Press Enter to begin.
```

Pulsa Enter.

### Minuto 12 — la contraseña sudo (importante)

Antes que nada, el wizard le pide a Paco que elija una contraseña para su usuario. Esta es la contraseña que el sistema le pedirá cuando quiera instalar software o cambiar cosas importantes.

El wizard insiste mucho en esto:

> *IMPORTANT — read this slowly:*
>
> *• Pick something you'll remember in 6 months.*
> *• Write it down. Paper diary, password manager, sticky note in a drawer.*
> *• Nobody can recover it for you.*
> *• If you lose it, you re-flash the USB and start over.*

Paco escribe una contraseña (no se ve en pantalla mientras escribe). La confirma una segunda vez. El wizard espera a que Paco la haya **escrito en algún sitio seguro** antes de continuar.

### Minuto 13 — elige su asistente de IA

```
Choose your AI coding CLI

Pick one:
  1) claude [default]
  2) gemini

Your choice [claude]:
```

Paco pulsa Enter y elige Claude Code (porque ya tiene cuenta de Claude).

### Minuto 14 — Tailscale

```
======================================================================
  Login: Tailscale
======================================================================

Open this URL on your phone or laptop to complete Tailscale login:

    https://login.tailscale.com/a/abc123...

Press Enter once you have completed the Tailscale login.
```

**Qué es Tailscale:** una red privada que conecta los dispositivos de Paco entre sí, donde quiera que estén. Aunque su móvil esté en una cafetería y el mini PC en su casa, ven el uno al otro como si estuvieran en la misma red local. Le da privacidad y seguridad sin tener que abrir puertos en el router. Tailscale es la red por la que viaja todo el tráfico que hace falta para que la app de Claude Code llegue al mini PC.

Paco no tiene cuenta de Tailscale. Abre la URL en su móvil, la página le ofrece crear cuenta gratis (20 segundos), aprueba que el mini PC se una a su red. Vuelve al teclado del mini PC, pulsa Enter.

### Minuto 16 — GitHub

```
======================================================================
  Login: GitHub
======================================================================

Open this URL on your phone or laptop to complete GitHub login:

    https://github.com/login/device?user_code=ABCD-1234

Press Enter once you have completed the GitHub login.
```

**Qué es GitHub:** el sitio donde el código vive en internet. Paco va a guardar todo su trabajo allí. Si el mini PC un día se rompe, su código sigue intacto.

Paco no tiene cuenta de GitHub. Misma historia: abre la URL, sign-up rápido, mete el código de un solo uso que muestra la pantalla, autoriza. Vuelve y pulsa Enter.

### Minuto 18 — Claude

Login a Claude Code, también vía URL. Esta vez Paco sí tiene cuenta. Sesión iniciada en 30 segundos.

### Minuto 19 — SSH preparado como respaldo

El wizard configura SSH como fallback por si algún día el camino principal (la app de Claude Code) no funciona: bindea el servicio SSH solo a la red de Tailscale, importa las claves públicas de Paco desde GitHub. Todo sin que Paco tenga que hacer nada. **En el día a día Paco no usará SSH** — solo está ahí por si acaso.

### Minuto 20 — el nombre del primer proyecto

```
Pick a name for your first project:
(lowercase letters, digits and hyphens. 2-31 chars.)
>
```

Paco escribe algo, por ejemplo `paco-app`. El wizard crea la estructura de carpetas, instala los archivos de contexto para la IA, copia 19 habilidades pre-cargadas (volvemos a esto en un momento), y pone dos proyectos guiados esperándole.

### Minuto 21 — la sesión persistente con Remote Control

El wizard lanza una **sesión de tmux** llamada `main`. tmux es un programa que mantiene varias ventanas de terminal abiertas a la vez, y **sobrevive a desconexiones**. Esto es clave: aunque Paco cierre el móvil, la sesión sigue viva en el mini PC, esperándole donde la dejó.

La sesión tiene **tres ventanas**:

- `platform` — para tocar el propio entorno (cambios al sistema)
- `paco-app` — el proyecto principal de Paco
- `stratops` — su espacio personal de estrategia y operaciones (OKRs, notas, roadmap)

En cada ventana se lanza Claude Code automáticamente. Y aquí viene la pieza clave: **el wizard activa Remote Control en cada ventana automáticamente**, sin que Paco tenga que hacer nada.

Remote Control es una feature nativa de Claude Code. Lo que hace: la sesión de Claude que está corriendo en el mini PC queda "expuesta" para que la app de Claude Code (móvil, tablet o desktop) la encuentre y permita conectarse. Es como si las tres ventanas del mini PC quedaran visibles para Paco desde cualquier dispositivo donde tenga la app instalada con su cuenta de Claude.

### Minuto 22 — opcional: preparar Slack

```
Optional: prepare your Slack coach

A "Slack coach" is a daemon that lives in a private Slack channel of
yours and chats with you about how your work is going — empathic,
knows what's happening on the device, helps when you're stuck.

Set up Slack coach credentials now?
  1) skip for now [default]
  2) yes, walk me through it
```

Si Paco quiere, el wizard le guía paso a paso por api.slack.com para crear una "Slack App" que más adelante será su coach personal. Captura los tokens necesarios. No instala todavía nada — solo deja las credenciales listas para cuando Paco implemente el coach él mismo (lo veremos en la siguiente sección).

Si Paco prefiere ir a esto luego, el wizard sigue sin más.

### Minuto 25 — setup completo

```
======================================================================
  Setup complete
======================================================================

Stack installed, logins done, workspace scaffolded, tmux session ready
with Remote Control enabled in every window.

To connect from your phone:
  1. Install the Claude Code app from your phone's app store.
  2. Sign in with the same Claude account you just used in this wizard.
  3. The app will list your three sessions — platform / paco-app /
     stratops — automatically.
  4. Tap any of them. You're inside.

No SSH client. No keys. No host setup. Just the Claude Code app.
```

El wizard termina. Paco saca el móvil, abre el App Store o Google Play, instala **Claude Code**. Lo abre. Hace login con su cuenta de Claude. La app le muestra las tres sesiones en una lista. Tap en `paco-app`. **Está dentro.**

### Minuto 26 — primera conversación, ya desde el móvil

Paco está mirando la pantalla de su móvil. Ve la ventana de Claude Code, esperándole en su proyecto. Escribe:

```
/first-project
```

Y Claude le responde con una conversación guiada:

> *Hola Paco. Voy a explicarte rápido qué es Git y GitHub, vamos a poner tu proyecto en GitHub para que tengas un respaldo, y luego te presento la primera FEAT que ya viene escrita y esperándote. ¿Listo?*

(Paco contesta que sí.)

> *GitHub es básicamente un sitio donde guardas el código. Vamos a poner tu proyecto allí. ¿Lo quieres público o privado? Te recomiendo privado, siempre puedes hacerlo público después.*

Y Claude ejecuta los comandos uno por uno, explicándole qué hace cada cosa, esperando confirmación. En 4 minutos, el proyecto está en GitHub, hay un primer commit, y Claude le presenta el siguiente paso.

Y todo eso lo está haciendo Paco con el móvil en la mano, sin haberse conectado a "nada", sin escribir un solo comando de Linux. La app es el cliente. El mini PC es el servidor. Pero Paco no tiene que pensar en esa distinción.

---

## 5 · Cómo se reconecta Paco al día siguiente (y al siguiente)

Esto es lo que más nos importa que entiendas, porque es lo que hace al regalo realmente útil.

Mañana por la mañana, Paco va en el metro. Saca el móvil. Abre la app de **Claude Code**. **No hay paso intermedio.** Las tres sesiones de su mini PC siguen ahí, vivas, exactamente donde las dejó anoche. Tap en `paco-app`. Está dentro, hablando con Claude.

No abre Termius. No hace SSH. No escribe `tmux attach`. No se acuerda de ningún comando. **Solo abre la app y hace tap.**

**Y lo mismo funciona desde el portátil.** Claude Code también tiene app de Mac/Windows/Linux. Paco la instala con la misma cuenta y ve las mismas tres sesiones — misma conversación, mismo contexto, otra pantalla. Móvil para una idea rápida en el metro, portátil para profundizar el sábado por la tarde. La sesión no se entera de qué pantalla está mirando: es siempre la misma, viva en su mini PC.

Esto pasa porque:

1. El mini PC nunca se apaga (o si lo apaga, arranca solo y vuelve a montar las sesiones).
2. tmux mantiene las tres ventanas vivas en el mini PC indefinidamente.
3. Claude Code corre dentro de cada ventana con Remote Control activado.
4. La app de Claude Code en el móvil de Paco descubre esas sesiones porque están registradas con su cuenta de Claude.

**Es la diferencia entre "abro el ordenador y me pongo" y "continúo donde estaba".** Para alguien que solo tiene 15 minutos sueltos en el día, esa diferencia es enorme: 15 minutos productivos contra 15 minutos perdidos en "preparar el setup".

---

## 6 · Los dos proyectos que vienen pre-cargados

Aquí está la parte bonita del regalo. No solo le damos un servidor — le damos **dos proyectos reales para construir**, con sus especificaciones ya escritas. Paco no se queda mirando una terminal vacía pensando "y ahora qué". Tiene cosas concretas que hacer, en orden, con Claude ayudándole en cada paso.

### Proyecto 1 — Un coach personal en Slack (FEAT-002)

**¿Qué es?** Un asistente que vive en un canal privado de Slack de Paco. No es para programar — es para hablar de cómo va el trabajo, de cómo se siente, de qué está atascado. Empático, sin paternalismo. Sabe lo que está pasando en el mini PC (qué commits ha hecho hoy Paco, si lleva 4 horas en el mismo archivo, si es muy tarde y aún está conectado).

**¿Cómo funciona?** Reacciona cuando Paco le habla en Slack, y también le escribe **proactivamente** cuando detecta cosas interesantes:

- Por la mañana: *"Buenos días Paco. Anoche cerraste a las 23:40. Hoy tienes 2 PRs abiertos, ¿por dónde quieres empezar?"*
- Por la tarde: *"Llevas 4 horas en el mismo archivo sin hacer commit. ¿Quieres una pausa o estás en flow?"*
- Por la noche: *"Es tarde. ¿Algo te tiene atrapado o estás disfrutándolo?"*

Es un detalle humano que transforma el mini PC de "un servidor" en "un entorno que cuida de su dueño".

**¿Y por qué Paco lo construye, en vez de dárselo hecho?** Porque el regalo no es solo el coach — el regalo es **aprender a construir cosas como esta**. Le damos la especificación completa (qué debe hacer, cómo debe comportarse, qué tecnologías usar) y Claude le ayuda a programarlo. En el proceso, Paco aprende:

- Qué es un daemon de fondo en Linux (systemd)
- Cómo se integra con Slack (Socket Mode)
- Cómo llamar a Claude desde código
- Cómo manejar memoria persistente (el coach recuerda conversaciones pasadas)
- Cómo publicar mensajes proactivos sin ser pesado (rate limiting)

Cuando termine, no solo tiene su coach — sabe construir cosas así.

**Tiempo estimado:** un par de tardes con Claude guiándole desde el móvil.

### Proyecto 2 — Una app de finanzas personales en producción (FEAT-003)

**¿Qué es?** Una web app, accesible en un dominio que Paco compra, donde puede:

- Subir un extracto bancario en formato CSV (drag & drop en una página web, o enviándolo a un canal de Slack)
- Tener un scraper automático que entra a su banco una vez al día y trae los movimientos nuevos
- Ver toda la información en un dashboard mobile-first: gasto por categoría, top comercios, evolución de los últimos 6 meses
- **La IA categoriza automáticamente** cada transacción (Mercadona → Alimentación, Uber → Transporte, etc.) — Paco solo corrige lo que la IA se equivoque
- Buscar en lenguaje natural: *"¿cuánto gasté en cafetería el trimestre pasado?"* → respuesta directa

**¿Dónde se aloja?** En la cuenta de Cloudflare de Paco. **Es suyo**. El dominio es suyo. Los datos son suyos. No hay nadie en medio.

**¿Qué aprende Paco construyéndolo?**

- Abrir una cuenta en Cloudflare (la habilidad `/second-project` le guía)
- Comprar un dominio (Cloudflare lo hace en 2 minutos sin comisiones absurdas)
- Desplegar una app real con un comando (`wrangler deploy`)
- Conectar varios servicios: bases de datos, almacenamiento, IA
- Hacer un scraper con Playwright (la herramienta estándar)
- Mostrar datos en un dashboard con gráficos

**Tiempo estimado:** entre 4 y 8 evenings, dependiendo de cuánto profundice. Pero la primera versión funcionando con CSV upload puede estar en una tarde.

Cuando termine este proyecto, Paco tiene una experiencia real de "he tenido una idea, la he especificado, la he construido, la he desplegado, está viva en internet en mi dominio". Esa experiencia es transformadora.

---

## 7 · Cómo es la vida normal de Paco con el mini PC

Después del primer día, así trabaja Paco:

### Por la mañana, en el metro

Paco abre la **app de Claude Code** en el móvil. La app le muestra sus tres sesiones. Tap en `paco-app`. Está dentro, exactamente donde lo dejó anoche. Si dejó una conversación con Claude a medias, sigue viva.

Le pregunta a Claude: *"¿Qué iba a hacer hoy?"* y Claude le responde con el contexto que tiene del último día.

Trabaja 25 minutos. Cierra el móvil. La sesión sigue corriendo en el mini PC.

### Después de cenar

Vuelve. Tap en la app. Sigue donde lo dejó.

Cambia entre ventanas dentro de la app (las tres aparecen como pestañas). Cada ventana es un contexto distinto con su propia conversación.

### Cuando se atasca

Tipea `/remote-control` dentro de Claude Code para generar un enlace de compartir (la sesión ya está en modo remote-control, pero esto genera un enlace específico para invitar a otra persona). Lo manda por WhatsApp. Esa otra persona se conecta, ve su sesión live, puede tomar control y arreglar lo que esté roto.

O simplemente envía un mensaje a su coach en `#coach` de Slack: *"estoy atascado con el wizard de Cloudflare, ¿alguna pista?"* y el coach (que sabe en qué proyecto está y qué intentó la última vez) le da contexto.

### Cuando quiere ver dónde se le va el dinero

Abre su app de finanzas en el dominio que compró. La que él construyó. Ve sus gráficos. Sus categorías. Sus comercios. Pregunta en lenguaje natural y le responde con un número.

### Cuando quiere construir otra cosa

Tipea `/sdd-coordinator` en cualquier ventana de Claude. La habilidad le habla como un Product Lead y le ayuda a definir la nueva feature. Después `/sdd-spec-writer` actúa como Tech Lead, etc. Hay 19 habilidades pre-cargadas, cada una con su voz y su rol, todas funcionando con la misma IA.

---

## 8 · La filosofía del regalo

No le estamos regalando solo un mini PC. Le estamos regalando:

1. **Soberanía** — el hardware es suyo, los datos son suyos, las claves son suyas. Nada depende de un servicio que pueda subir precio mañana, cerrar, o cambiar términos. Si Paco quiere mudar todo a otra máquina, lo hace en una tarde porque todo está en su GitHub.

2. **Cero fricción** — desde que enchufa hasta que está construyendo, son 25 minutos. La pieza más mágica viene después: cada día siguiente Paco no "abre el ordenador y se pone", sino que **abre una app y continúa**. Esa diferencia hace que ratos sueltos del día se conviertan en trabajo real.

3. **Acompañamiento real** — el coach de Slack es la versión humana de "un sistema que cuida". No es notificaciones automatizadas. Es un asistente con personalidad, que sabe contexto, que escribe con empatía.

4. **Aprendizaje haciendo** — los dos proyectos pre-cargados son una mini-curriculum. Cuando termine el segundo, Paco sabe construir y desplegar productos digitales completos, en producción, en su propio dominio.

5. **Compartibilidad** — Remote Control significa que cualquiera de nosotros puede ayudarle en directo cuando se atasque, viendo su pantalla, tomando control si hace falta. El regalo no termina cuando se lo entregamos.

---

## 9 · Datos técnicos para los curiosos

| Cosa | Especificación |
|---|---|
| Hardware | Mini PC AMD Ryzen 3 7430U, 32 GB RAM, SSD |
| Sistema operativo | Ubuntu Server 24.04 LTS |
| Conexión | Ethernet por cable (WiFi en v2) |
| Red privada | Tailscale (cuenta de Paco) |
| Acceso primario (móvil + portátil) | App oficial de Claude Code (iOS / Android / Mac / Windows / Linux) + Remote Control activado en cada sesión |
| Acceso desde móvil — respaldo | Termius o cualquier cliente SSH, vía Tailscale SSH |
| Asistente de IA | Claude Code (cuenta de Paco) |
| Habilidades pre-cargadas | 19 (SDD workflow, consultores backend/UX/exec/product-marketing, herramientas code-review/qa/docs, onboarding first-project/second-project/whats-ahead, extend-yourself) |
| Proyectos pre-cargados | 2 FEATs (coach Slack + app finanzas) |
| Sesión persistente | tmux (sobrevive a desconexiones y reinicios de la app) |
| Comparte sesión live | `/remote-control` (slash command) genera enlace para invitar a terceros |
| Backup del código | GitHub (privado por defecto) |
| Coste mensual de Paco | 0€ (Claude Max si ya lo tiene; servicios cloud en tier gratuito; dominio ~10€/año cuando llegue a FEAT-003) |

---

## 10 · Qué pasa si algo va mal

Cosas que pueden fallar y cómo se recupera:

- **Paco olvida su contraseña sudo:** re-flashea el USB, instala de nuevo. Pierde lo local; el código sigue en GitHub. ~30 minutos de molestia.
- **El mini PC se rompe físicamente:** Paco compra otro mini PC (cualquier x86 con UEFI vale). Enchufa el USB. En 25 minutos vuelve a estar donde estaba. El código sigue en GitHub.
- **La app de Claude Code no encuentra las sesiones del mini PC:** Paco usa el respaldo SSH (Termius + Tailscale), entra al mini PC, reactiva `/remote-control` en cada ventana, y la app las vuelve a ver.
- **Cae la conexión a internet:** el mini PC sigue funcionando localmente. Tailscale se reconecta solo cuando vuelve la red. Las sesiones tmux quedan intactas.
- **Anthropic / Tailscale / GitHub cambia algo:** los scripts del USB son código abierto, los puede editar él o pedirle a Claude que los actualice.

No hay punto único de fallo del que no se pueda recuperar. Esto es importante: **el regalo está diseñado para durar años**.

---

## 11 · Que Paco pueda modificar y extender todo

Esto es una pieza importante del regalo que es fácil pasar por alto. **El sistema entero está diseñado para que Paco lo modifique a su gusto, no para que se quede congelado en la versión que le entregamos.**

Concretamente:

- **El código completo está en su mini PC.** Todos los scripts del wizard, todas las habilidades, todas las configuraciones — todo vive en `/opt/buildersinabox/` y `~/ai-platform/payload/`. Paco puede leerlo, copiarlo, modificarlo. Nada está oculto.

- **Tiene una habilidad específica para esto: `/extend-yourself`.** Cuando Paco quiera teach al sistema un truco nuevo (una nueva habilidad de Claude, un atajo de shell, un nuevo paso del wizard, un servicio en background), tipea `/extend-yourself` y Claude le guía paso a paso por la convención: dónde poner el archivo, qué frontmatter llevar, cómo hacer que tmux/Claude lo descubra.

- **Los patrones son uniformes y aprendibles.** Las 19 habilidades pre-cargadas son ellas mismas la documentación: cuando Paco quiera crear la suya, Claude le enseña la estructura del archivo copiando una de las existentes. No tiene que aprenderse un framework — solo imitar un patrón que ya conoce.

- **Sin sudo lockdown.** La contraseña es suya, los archivos son suyos, las decisiones son suyas. Si quiere romper algo y aprender de ello, puede.

El mensaje subyacente es: *este no es un electrodoméstico que se compra y se usa hasta que deja de funcionar. Es un punto de partida que crece contigo*. Cuanto más lo use Paco, más suyo va a ser.

---

## 12 · Devolver el regalo: Paco puede contribuir mejoras

Builders in a Box es **código abierto**. El repositorio público vive en GitHub, y cualquier mejora que Paco haga en su mini PC — una habilidad nueva útil, un fix de un bug, un nuevo proyecto pre-cargado que él haya escrito y crea que otros podrían disfrutar — puede subirla de vuelta al repo.

El flujo es estándar (Paco va a aprenderlo de todas formas con FEAT-002 y FEAT-003):

1. Fork del repo en su GitHub.
2. Hacer la mejora en su mini PC.
3. Push a su fork.
4. `gh pr create` desde el terminal.

Y esa mejora pasa a estar disponible para todas las personas que reciban un Builders in a Box en el futuro. Su trabajo se queda como parte del regalo que otros van a recibir.

No es obligatorio — está perfectamente bien que Paco use su mini PC como caja personal y nunca mande un PR. Pero la puerta está abierta, y la habilidad `/extend-yourself` le enseña explícitamente cómo cruzarla.

---

## 13 · Cierre

Lo que le damos a Paco no es un producto. Es un punto de partida. Es la diferencia entre *"quiero ponerme a construir cosas"* y *"estoy construyendo cosas, ahora mismo, desde el sofá, con mi café al lado y la voz de mi coach diciéndome que vaya a dormir".*

Si en 6 meses Paco ha implementado el coach, ha desplegado la app de finanzas, y ha empezado un tercer proyecto suyo propio — el regalo habrá hecho su trabajo. Y si en 6 meses lo único que ha hecho es echar un vistazo y dejarlo aparcado — también está bien, el mini PC esperará. No caduca.

Que lo disfrute. Lo hemos preparado con cariño.
