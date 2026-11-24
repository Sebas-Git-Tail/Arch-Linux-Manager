# Novedades de Arch-Linux-Manager

Lo que cambió en cada versión. El Manager lo muestra la primera vez que se abre una versión nueva y siempre
desde el botón del regalito. Los cambios marcados [Sebastián] solo aparecen en sus equipos.

## 4.16.0 (24/11/2026)
- [Sebastián] Panel de Minecraft con el estilo de Prism Launcher: los servidores como mosaicos con su ícono
  (el server-icon.png, o uno pixel-art según sea Vanilla, Paper, Fabric o Forge, con un punto verde si está
  prendido), agrupados con encabezados plegables, y a la derecha el elegido con su columna de acciones.
- [Sebastián] Doble clic (o «Administrar») abre el servidor como el «Editar» de Prism: páginas a la izquierda
  (Consola, Plugins/Mods, Jugadores, Opciones, Respaldos) e Iniciar/Detener/Reiniciar abajo.
- [Sebastián] Con Ctrl o Shift se eligen varios servidores para actualizar Paper o instalarles un plugin o mod.
- [Sebastián] «Jugar» abre las instancias de Prism desde la barra de arriba; «Carpetas» abre la de los
  servidores o la de los respaldos; los avisos quedan detrás del botón «Avisos».

## 4.15.0 (24/11/2026)
- [Sebastián] Panel de Minecraft: apagado automático. Un servidor sin jugadores se apaga solo a los 10 minutos
  (se cambia o se desactiva en Opciones) y, si la PC se prendió por WOL y nadie la está usando, después se apaga
  la PC. La lista muestra en cuánto se va a apagar.
- [Sebastián] Pestaña «Jugadores»: todos los que entraron alguna vez, quién está conectado, y botones para op,
  lista blanca, banear, perdonar y expulsar (con el servidor prendido usa sus comandos; apagado, sus archivos).
- [Sebastián] Pestaña «Opciones»: server.properties como formulario, con una explicación de cada opción; el
  mensaje de la lista (MOTD) con colores, dos líneas y vista previa; ícono del servidor; y con un clic Geyser +
  Floodgate (amigos con Bedrock) o BlueMap (mapa web).
- [Sebastián] Pestaña «Respaldos»: los mundos guardados y los jars, plugins y mods reemplazados, con «Restaurar»
  (guarda antes lo que hay) y «Guardar el mundo ahora» (también con el servidor prendido).
- [Sebastián] «Cambiar versión…»: otro software o versión para un servidor que ya existe, o actualizar el
  cargador de Fabric/Forge. Guarda el mundo antes, pasa los plugins/mods a la versión que sirve (de plugin a mod
  si el proyecto tiene las dos), agrega las dependencias que falten, y no deja bajar por debajo de la versión del
  mundo. La carpeta pasa a la de la versión nueva.
- [Sebastián] «Pack para jugadores…» (servidores Fabric/Forge): un .mrpack con los mods que necesitan los que
  entran, para abrir con Prism Launcher o la app de Modrinth.
- [Sebastián] Arreglado: un mundo de Paper ahora abre al pasarlo a Vanilla, Fabric o Forge (al crear o cambiar).

## 4.14.0 (23/11/2026)
- [Sebastián] Panel de Minecraft: «Crear servidor…» arma un servidor nuevo paso a paso: grupo y nombre,
  Vanilla, Paper, Fabric o Forge y la versión (solo las que existen para ese software), o un modpack de
  Modrinth; un mundo que ya tengas (carpeta, .zip o el de otro servidor), plugins (Paper) o mods
  (Fabric/Forge) de Modrinth con sus dependencias, y la configuración (memoria, modo, dificultad, jugadores…).
  Aparece solo en la lista y se administra como los demás.
- [Sebastián] Solo deja combinar lo que es compatible: plugins solo en Paper, mods del mismo cargador,
  nada de mods solo para el juego, modpacks de la misma versión y cargador, y no abre un mundo de una
  versión más nueva. Si algo falla o se cancela, no queda nada a medias.
- [Sebastián] Cada servidor nuevo usa el Java que pide su versión (si falta, dice cuál instalar).
- [Sebastián] En los servidores Fabric y Forge, la pestaña de plugins pasa a ser de mods (con actualización
  desde Modrinth), e «Instalar» le pone a cada servidor marcado la versión que le sirve.
- Las consultas a Modrinth, Fabric y Forge son más rápidas (antes podían tardar varios segundos por pedido).

## 4.13.1 (23/11/2026)
- [Sebastián] Panel de Minecraft: los grupos de servidores se despliegan al tocarlos (arrancan cerrados, salvo
  el que tenga uno encendido) y muestran cuántos servidores tienen y cuántos están encendidos.

## 4.13.0 (23/11/2026)
- [Sebastián] Panel de Minecraft: lee la carpeta nueva de servidores, ordenada por grupo
  (Servidores/<grupo>/<versión>/<servidor>), y la lista los muestra agrupados por esa carpeta.
  Puede haber dos servidores con el mismo nombre en grupos distintos; marcar un grupo marca todos los suyos.
- [Sebastián] Los jars, plugins y mundos reemplazados se guardan con la misma forma: Respaldos/<grupo>/<versión>/<servidor>.
- La lista de servidores del panel es más alta.

## 4.12.1 (23/11/2026)
- [Sebastián] Los servidores de Minecraft también se manejan desde la sección Minecraft de Android-Manager
  (por el servidor de casa), que además prende y apaga la PC.

## 4.12.0 (23/11/2026)
- Panel de Minecraft: pestaña «Consola» con lo que va pasando en el servidor elegido, quién está conectado
  y una caja para mandarle comandos (con las flechas volvés a los anteriores). Los plugins pasaron a su pestaña.
- Los servidores siguen prendidos aunque cierres su terminal o el Manager. Para apagarlos: Detener (o «stop»).
  «Abrir en una terminal» vuelve a mostrar la consola.
- Si hay gente conectada, Detener y Reiniciar ofrecen avisar en el chat y esperar un minuto (se puede cancelar).

## 4.11.0 (21/11/2026)
- Novedades: la primera vez que abrís una versión nueva te cuenta qué cambió. Siempre están en el botón del
  regalito, arriba a la derecha.
- Si el Manager se cierra por una falla, manda un informe al servidor (sin tus datos) para que se pueda arreglar.
  También lo podés mandar a mano desde Novedades, con un comentario.
- [Sebastián] Los informes de fallas de todas las apps se ven en http://100.101.213.44:8080/fallas/ (solo por
  Tailscale o en casa).
- [Sebastián] En la PC y en la del instituto, el Manager marca el equipo como tuyo: todas las apps muestran
  también las novedades «solo vos».

## 4.10.0 (19/11/2026)
- Apps del AUR: instala y actualiza las apps del AUR de cada equipo (Claude, Heroic y otras), sin yay ni paru.
  «Actualizar Arch» también las pone al día.

## 4.9.0 (19/11/2026)
- [Sebastián] Sección Servidor: genera las miniaturas de Bodrio y las páginas del sitio en el servidor, con una
  clave limitada. Se sacó «App».

## 4.8.0 (18/11/2026)
- Modo claro y oscuro con un botón (se recuerda).

## 4.7.0 (18/11/2026)
- La ventana se vuelve a abrir del mismo tamaño, y maximizada o en pantalla completa si lo estaba.

## 4.6.0 (17/11/2026)
- Interfaz nueva, igual en todas las apps.
