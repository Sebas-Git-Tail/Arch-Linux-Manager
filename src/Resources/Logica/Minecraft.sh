#!/bin/bash
# Lógica sin interfaz de Minecraft (la usa la página «Panel de Minecraft»). Los servidores están en
# Minecraft Servers/Servidores/<grupo>/<versión>/<servidor>/ con su servidor.conf (ver Minecraft-comun.sh).
# SERVIDOR es siempre su ruta dentro de Servidores/, como «Amigos/26.1/26.1.2 SMP-1» (la que da «servidores»).
#
# Uso: Minecraft.sh servidores                       todos los servidores y su estado
#      Minecraft.sh iniciar SERVIDOR                 lo prende (en tmux) y abre su consola en una terminal
#      Minecraft.sh detener SERVIDOR [SEGUNDOS]      lo apaga guardando los mundos (avisando antes en el chat)
#      Minecraft.sh reiniciar SERVIDOR [SEGUNDOS]    detener + iniciar
#      Minecraft.sh terminal SERVIDOR                abre su consola en una terminal (cerrarla no lo apaga)
#      Minecraft.sh comando SERVIDOR TEXTO           escribe un comando en su consola (ej. «say hola», sin «/»)
#      Minecraft.sh registro SERVIDOR                las últimas líneas de su registro y las que van llegando
#      Minecraft.sh jugadores SERVIDOR               quién está conectado (no escribe nada en la consola)
#      Minecraft.sh paper SERVIDOR...                lo pasa a la última compilación estable de Paper de su versión
#      Minecraft.sh plugins SERVIDOR                 sus plugins (Paper) o mods (Fabric/Forge), reconocidos en Modrinth, y si hay versión nueva
#      Minecraft.sh plugins-actualizar SERVIDOR [ARCHIVO...]   actualiza los que tienen versión nueva (todos o esos)
#      Minecraft.sh plugin TEXTO SERVIDOR...         instala un plugin (Paper) o mod (Fabric/Forge) de Modrinth (nombre, slug o
#                                                    URL), con sus dependencias, o de otra URL https; en cada servidor el que le sirve
#      Minecraft.sh reiniciar-mundo SERVIDOR         guarda el mundo en Respaldos/ y lo borra (Paper hace uno nuevo)
#      Minecraft.sh ram SERVIDOR 8G                  cambia la memoria máxima
#      Minecraft.sh carpeta SERVIDOR                 abre la carpeta del servidor
#      Minecraft.sh abrir-carpeta servidores|respaldos   abre la carpeta de todos los servidores o de los respaldos
#      Minecraft.sh opciones                         (asistente) versiones, software de cada una, grupos y Javas instalados
#      Minecraft.sh buscar-modrinth complemento|modpack TIPO VERSION TEXTO   (asistente) proyectos de Modrinth que sirven
#      Minecraft.sh modpack-versiones SLUG           (asistente) versiones de un modpack que se pueden usar
#      Minecraft.sh crear < configuración           arma un servidor nuevo (ver «crear» más abajo); aparece solo en la lista
#      Minecraft.sh cambiar SERVIDOR < TIPO/VERSION  otro software o versión (o actualizar el cargador), guardando el mundo antes
#      Minecraft.sh jugadores-lista SERVIDOR         quién entró, ops, lista blanca y baneados (JUGADOR …)
#      Minecraft.sh jugador SERVIDOR ACCION [NOMBRE] [MOTIVO]   op|deop|whitelist-add|whitelist-remove|ban|pardon|kick|
#                                                    lista-blanca-si|lista-blanca-no (prendido: con comandos; apagado: en los .json)
#      Minecraft.sh opciones-servidor SERVIDOR       server.properties con explicación (OPCION …) y ajustes del Manager (AJUSTE …)
#      Minecraft.sh propiedades-cambiar SERVIDOR < clave=valor   las cambia (solo las conocidas; también APAGAR_VACIO/APAGAR_PC)
#      Minecraft.sh ajuste SERVIDOR APAGAR_VACIO|APAGAR_PC VALOR   apagado automático (minutos, 0 = nunca) y si apaga la PC
#      Minecraft.sh icono SERVIDOR IMAGEN.png        server-icon.png (PNG de 64×64)
#      Minecraft.sh respaldos SERVIDOR               mundos guardados y jars/plugins/mods reemplazados (RESPALDO …)
#      Minecraft.sh respaldo-guardar SERVIDOR        guarda el mundo ahora (prendido: con save-off/save-all/save-on)
#      Minecraft.sh restaurar SERVIDOR mundo|jar|plugin|mod ARCHIVO   vuelve a un respaldo (guarda antes lo que hay)
#      Minecraft.sh pack-jugadores SERVIDOR DESTINO.mrpack   los mods que necesitan los jugadores (Fabric/Forge)
#      Minecraft.sh extra SERVIDOR geyser|bluemap    Geyser + Floodgate (Bedrock) o BlueMap (mapa web)
#      Minecraft.sh vigilar SERVIDOR                 (interno) apagado automático sin jugadores; lo lanza «iniciar»
#      Minecraft.sh consola SERVIDOR                 (interno) lo que corre dentro de tmux
#      Minecraft.sh instancias                       instancias de Prism Launcher
#      Minecraft.sh prism "INSTANCIA"                abre la instancia y entra al servidor de casa
#
# Eventos (stdout, uno por línea; los campos de SERVIDOR y PLUGIN van separados por tabuladores):
#   SERVIDOR ENCENDIDO|APAGADO<tab>ruta<tab>tipo<tab>versión<tab>tamaño del mundo<tab>último uso<tab>RAM<tab>jar
#   PLUGIN archivo<tab>nombre<tab>versión<tab>versión nueva<tab>AL_DIA|NUEVA|SIN_VERSION|DESCONOCIDO<tab>…
#   INSTANCIA <instancia>
#   ETAPA <texto>        ESPERA <segundos>   (detener: cuánto lleva guardando)
#   AVISO <texto>        LISTO <texto>        ERROR <texto>
#   CONSOLA COMANDOS|SOLO_LECTURA|APAGADO   (registro: si se le pueden mandar comandos)
#   LINEA <texto>        (registro: una línea del registro del servidor)
#   LATIDO               (registro: cada 15 s, para notar si se cortó la conexión; se ignora)
#   JUGADORES conectados<tab>máximo<tab>nombre,nombre…
#   VERSION v<tab>software,…   GRUPO g   JAVA n   RESULTADO …   MODPACK …   (asistente, ver minecraft_api.py)
#   CREADO <servidor>    (crear y cambiar: la ruta del servidor, que en cambiar puede ser otra)
#   SERVIDOR … tiene un noveno campo desde la 4.15.0: en cuántos minutos se apaga solo (vacío si no está por apagarse),
#   y un décimo desde la 4.16.0: la ruta de su server-icon.png (vacío si no tiene)
#
# Consola compartida (desde la 4.12.0): el servidor corre dentro de tmux (socket propio «minecraft»,
# sesión «mc-<servidor>»), así sigue prendido aunque se cierre la terminal o el Manager, y el panel
# puede mandarle comandos. Desde otro lado: tmux -L minecraft attach -t mc-Amigos_26_3_26_3_SMP-1
# MINECRAFT_SIN_TERMINAL=1 hace que iniciar/reiniciar no abran la terminal (pruebas, uso por SSH).
#
# Código de salida: 0 bien, 1 falló, 2 error de uso.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-1}"; }

AQUI="$(dirname "$(realpath "$0")")"
source "$AQUI/Minecraft-comun.sh"
COMMON="${COMMON:-$AQUI/../Common}"
source "$COMMON/Servidor.sh"   # SERVIDOR_MINECRAFT (de servidor.json, campo ip_minecraft)
API="$AQUI/minecraft_api.py"

PRISM_DIR="$HOME/.local/share/PrismLauncher/instances"
# Instancias de Prism que se abren sin conectarse a ningún servidor
declare -A SIN_SERVIDOR=(
    ["SevTech- Ages"]=1
)

# El servidor tiene que ser uno de los que existen (así no se puede apuntar a otra carpeta)
# y deja en NV su nombre para mostrar en los mensajes («26.1.2 SMP-1 (Amigos)»)
servidor_valido() {
    [[ -n "$1" ]] && listar_servidores | grep -qxF -- "$1" || error "No existe el servidor «$1»." 2
    NV=$(nombre_visible "$1")
}
apagado() {
    [[ -z "$(pid_servidor "$(carpeta_servidor "$1")")" ]]
}
# Cambia un ajuste del Manager en servidor.conf (comprobándolo) y dice qué quedó. Uso: aplicar_ajuste SERVIDOR CLAVE VALOR
aplicar_ajuste() {
    local texto
    case "$2" in
        APAGAR_VACIO) [[ "$3" =~ ^[0-9]{1,3}$ ]] && (( 10#$3 <= 720 )) || { emitir "ERROR Minutos: de 0 (nunca) a 720." >&3; return 2; }
                      texto=$( (( 10#$3 == 0 )) && echo "no se apaga solo" || echo "se apaga solo a los $((10#$3)) minutos sin jugadores") ;;
        APAGAR_PC)    [[ "$3" =~ ^(si|no)$ ]] || { emitir "ERROR APAGAR_PC tiene que ser si o no." >&3; return 2; }
                      texto=$([[ "$3" == si ]] && echo "si apagarlo deja la PC sin uso, la apaga (solo si la prendió el WOL)" || echo "nunca apaga la PC") ;;
        *) emitir "ERROR Ajuste desconocido." >&3; return 2 ;;
    esac
    cambiar_conf "$1" "$2" "$3"
    printf '%s\n' "$texto"
}
# Un mundo de Paper (26.x) para el juego normal (Vanilla, Fabric, Forge): Paper guarda world_gen_settings.dat en
# cada dimensión (dimensions/minecraft/overworld/data/…) y el juego lo busca en data/minecraft/ del mundo; sin él,
# el servidor se cuelga con «Overworld settings missing». Uso: mundo_desde_paper CARPETA_DEL_MUNDO
mundo_desde_paper() {
    local m="$1" origen="$1/dimensions/minecraft/overworld/data/minecraft/world_gen_settings.dat"
    if [[ -f "$origen" && ! -f "$m/data/minecraft/world_gen_settings.dat" ]]; then
        mkdir -p "$m/data/minecraft" && cp -- "$origen" "$m/data/minecraft/world_gen_settings.dat"
    fi
}
# ¿El .jar es un plugin de Paper, o un mod del cargador del servidor? (mira qué trae adentro)
complemento_sirve() {   # archivo tipo
    local lista; lista=$(unzip -Z1 "$1" 2>/dev/null) || return 1
    case "$2" in
        paper)  grep -qxE 'plugin\.yml|paper-plugin\.yml' <<< "$lista" ;;
        fabric) grep -qx 'fabric\.mod\.json' <<< "$lista" ;;
        forge)  grep -qxE 'META-INF/mods\.toml|mcmod\.info' <<< "$lista" ;;
        *)      return 1 ;;
    esac
}
que_complemento() {
    case "$1" in paper) echo "un plugin de Paper" ;; *) echo "un mod de $(nombre_tipo "$1")" ;; esac
}
# --- Consola compartida (tmux) -------------------------------------------------------------
TMUX_SOCKET="${MINECRAFT_TMUX:-minecraft}"
mc_tmux() { tmux -L "$TMUX_SOCKET" -f /dev/null "$@"; }
# Nombre de la sesión de tmux («Amigos/26.1/26.1.2 SMP-1» → «mc-Amigos_26_1_26_1_2_SMP-1»: tmux no acepta
# puntos ni dos puntos)
sesion() { local s="$1"; printf 'mc-%s\n' "${s//[^A-Za-z0-9_-]/_}"; }
# Carpeta de estado del apagado automático: la misma desde el panel y desde el celular (por SSH puede no estar
# XDG_RUNTIME_DIR), así hay un solo vigilante por servidor
dir_estado() {
    local d="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    [[ -d "$d" && -w "$d" ]] || d="/tmp/arch-linux-manager-$(id -u)"
    mkdir -p "$d/arch-linux-manager" 2>/dev/null
    printf '%s\n' "$d/arch-linux-manager"
}
# ¿Corre en tmux? (si se prendió de otra forma no se le pueden mandar comandos)
compartida() {
    command -v tmux &>/dev/null && mc_tmux has-session -t "=$(sesion "$1")" 2>/dev/null
}
# Escribe una línea en la consola del servidor, como si se tecleara
enviar() {
    local ses; ses=$(sesion "$1")
    mc_tmux send-keys -t "=$ses:" -l -- "$2" && mc_tmux send-keys -t "=$ses:" Enter
}
# Prende el servidor: dentro de tmux si está, si no en una terminal como antes de la 4.12.0
arrancar() {
    local ses carpeta
    carpeta=$(carpeta_servidor "$1")
    if command -v tmux &>/dev/null; then
        ses=$(sesion "$1")
        mc_tmux kill-session -t "=$ses" 2>/dev/null    # una que quedó de un apagado anterior
        mc_tmux new-session -d -s "$ses" -x 200 -y 50 -c "$carpeta" "$AQUI/Minecraft.sh" consola "$1" \
            || error "No se pudo abrir la consola (tmux) de $(nombre_visible "$1")."
        mc_tmux set -g mouse on \; set -g history-limit 20000 \; set -g status-left "" \
            \; set -g status-right-length 120 \; set -g status-style "bg=#00aae4,fg=black" \
            \; set -g status-right "Cerrar esta ventana NO apaga el servidor (para apagarlo: stop) " &>/dev/null
    else
        setsid -f konsole --workdir "$carpeta" -p tabtitle="$(nombre_visible "$1")" -e "$AQUI/Minecraft.sh" consola "$1" &>/dev/null
    fi
    # Apagado automático (ver «vigilar»)
    [[ "${MINECRAFT_VIGILAR:-1}" == 0 ]] || setsid -f bash "$AQUI/Minecraft.sh" vigilar "$1" &>/dev/null < /dev/null
}
# Guarda el mundo (con su nether y end) en Respaldos/<servidor>/mundos/<mundo>[-etiqueta]-<fecha>.tar.zst y dice
# la ruta. Si está prendido, pausa el guardado del servidor mientras copia (save-off, save-all flush, save-on).
# Los mensajes van por el fd 3 (se la llama dentro de $( )). Uso: archivo=$(guardar_mundo SERVIDOR [etiqueta])
guardar_mundo() {
    local servidor="$1" etiqueta="${2:+-$2}" carpeta mundo m destino archivo prendido=0 lineas i partes=()
    carpeta=$(carpeta_servidor "$servidor"); mundo=$(mundo_servidor "$servidor")
    for m in "$mundo" "${mundo}_nether" "${mundo}_the_end"; do [[ -d "$carpeta/$m" ]] && partes+=("$m"); done
    (( ${#partes[@]} )) || { printf 'ERROR %s todavía no tiene mundo.\n' "$(nombre_visible "$servidor")" >&3; return 1; }
    if ! apagado "$servidor"; then
        compartida "$servidor" || { printf 'ERROR %s se prendió sin consola compartida: detenelo para guardar el mundo.\n' "$(nombre_visible "$servidor")" >&3; return 1; }
        prendido=1
        lineas=$(wc -l < "$carpeta/logs/latest.log" 2>/dev/null || echo 0)
        enviar "$servidor" "save-off"; enviar "$servidor" "save-all flush"
        printf 'ETAPA Esperando que el servidor termine de guardar\n' >&3
        for (( i = 0; i < 60; i++ )); do
            tail -n +"$((lineas + 1))" "$carpeta/logs/latest.log" 2>/dev/null | grep -q 'Saved the game' && break
            sleep 0.5
        done
    fi
    destino="$RESPALDOS_MC_DIR/$servidor/mundos"; mkdir -p "$destino"
    archivo="$destino/$mundo$etiqueta-$(date +%Y-%m-%d_%H-%M-%S).tar.zst"
    printf 'ETAPA Guardando el mundo de %s (puede tardar)\n' "$(nombre_visible "$servidor")" >&3
    if ! tar --zstd -cf "$archivo" -C "$carpeta" "${partes[@]}"; then
        rm -f "$archivo"; (( prendido )) && enviar "$servidor" "save-on"
        printf 'ERROR No se pudo guardar el mundo.\n' >&3; return 1
    fi
    (( prendido )) && enviar "$servidor" "save-on"
    printf '%s\n' "$archivo"
}
# Abre la consola en una terminal que se puede cerrar sin apagar el servidor
abrir_terminal() {
    [[ "${MINECRAFT_SIN_TERMINAL:-}" == 1 ]] && return 0
    compartida "$1" || return 0
    setsid -f konsole -p tabtitle="$(nombre_visible "$1")" -e tmux -L "$TMUX_SOCKET" -f /dev/null attach -t "=$(sesion "$1")" &>/dev/null
}
# Detiene el servidor guardando los mundos. Con SEGUNDOS > 0 (y consola compartida) primero avisa en el
# chat y espera; si se cancela mientras espera, avisa que no se apaga. Uso: detener SERVIDOR [SEGUNDOS] [verbo]
detener() {
    local pid s espera="${2:-0}" verbo="${3:-apaga}"
    pid=$(pid_servidor "$(carpeta_servidor "$1")")
    [[ -n "$pid" ]] || return 0
    if (( espera > 0 )) && compartida "$1"; then
        # (el trap puede correr dentro de otra función: usa variables propias, no $1)
        AVISO_SERVIDOR="$1"; AVISO_VERBO="$verbo"
        trap 'enviar "$AVISO_SERVIDOR" "say Se canceló: el servidor no se $AVISO_VERBO." 2>/dev/null; exit 130' TERM INT HUP PIPE
        for (( s = espera; s > 0; s-- )); do
            kill -0 "$pid" 2>/dev/null || { trap - TERM INT HUP PIPE; return 0; }
            if (( s == espera || s == 30 || s == 10 || s <= 5 )); then
                enviar "$1" "say El servidor se $verbo en $s segundo$( (( s > 1 )) && echo s)."
            fi
            emitir "ETAPA Avisado en el chat: se $verbo en $s s"
            sleep 1
        done
        trap - TERM INT HUP PIPE
    fi
    emitir "ETAPA Deteniendo $(nombre_visible "$1") (guardando mundos)"
    # «stop» por la consola es lo mismo que hace un jugador; sin consola, SIGTERM (Paper guarda igual)
    if compartida "$1"; then enviar "$1" "stop"; else kill -TERM "$pid"; fi
    for (( s = 0; s < 120; s++ )); do
        kill -0 "$pid" 2>/dev/null || return 0
        emitir "ESPERA $s"
        sleep 1
    done
    error "$(nombre_visible "$1") no se detuvo después de 2 minutos."
}

# --- Instalar el software de un servidor (lo usan crear y cambiar) --------------------------------------
exec 3>&1    # los ERROR de api_linea van directo al panel aunque se la llame dentro de $( )
# La primera línea de minecraft_api.py que empieza con PREFIJO; si no hay, avisa su ERROR y falla.
# Uso: linea=$(api_linea PREFIJO orden argumentos...) || exit 1
api_linea() {
    local prefijo="$1" salida motivo; shift
    salida=$(python3 -I "$API" "$@" 2>&1)
    if grep -q "^$prefijo " <<< "$salida"; then grep -m1 "^$prefijo " <<< "$salida"; return 0; fi
    motivo=$(grep -m1 '^ERROR ' <<< "$salida" | cut -d' ' -f2-)
    printf 'ERROR %s\n' "${motivo:-No hubo respuesta de internet (o fue rara) en «$1».}" >&3
    return 1
}
# Qué pide esa versión: deja url_vanilla, sha1_vanilla, java_pedido, bin_java y java_n (el Java que se va a usar)
preparar_version() {
    local linea
    emitir "ETAPA Consultando Mojang ($1)"
    linea=$(api_linea VANILLA vanilla "$1") || exit 1
    read -r _ url_vanilla sha1_vanilla java_pedido <<< "$linea"
    url_valida "$url_vanilla" && [[ "$sha1_vanilla" =~ ^[0-9a-f]{40}$ && "$java_pedido" =~ ^[0-9]{1,2}$ ]] || error "Respuesta rara de Mojang."
    bin_java=$(java_para "$java_pedido") || error "Minecraft $1 necesita Java $java_pedido (o más nuevo) y no está instalado: sudo pacman -S jre$java_pedido-openjdk"
    java_n="${bin_java%/bin}"; java_n="${java_n%/jre}"; java_n="${java_n##*/java-}"; java_n="${java_n%-openjdk}"
    (( java_n == java_pedido )) || emitir "AVISO Minecraft $1 pide Java $java_pedido; no está, así que uso Java $java_n (si no arranca: sudo pacman -S jre$java_pedido-openjdk)."
}
# Baja e instala el software en la carpeta (después de preparar_version). Deja jar (vacío si arranca con
# run.sh) y loader (la versión de Fabric/Forge que quedó). Uso: instalar_software TIPO VERSION LOADER RAM CARPETA
instalar_software() {
    local tipo="$1" version="$2" ram="$4" dir="$5" linea build sha256 sha1 url f
    loader="$3"; jar=""
    case "$tipo" in
        vanilla)
            emitir "ETAPA Bajando el servidor oficial de Minecraft $version"
            descargar_jar "$url_vanilla" "sha1:$sha1_vanilla" "$dir/server.jar" || error "No se pudo bajar el servidor de Minecraft (o la suma no coincide)."
            jar=server.jar ;;
        paper)
            emitir "ETAPA Buscando la última compilación de Paper $version"
            linea=$(api_linea PAPER paper "$version") || { emitir "ERROR Paper no tiene una compilación estable para $version."; exit 1; }
            read -r _ build jar sha256 url <<< "$linea"
            [[ "$jar" =~ ^[A-Za-z0-9._\-]+\.jar$ ]] && url_valida "$url" || error "Respuesta rara de PaperMC."
            emitir "ETAPA Bajando Paper $version compilación $build"
            descargar_jar "$url" "sha256:$sha256" "$dir/$jar" || error "No se pudo bajar Paper (o la suma no coincide)." ;;
        fabric)
            emitir "ETAPA Buscando Fabric para $version"
            linea=$(api_linea FABRIC fabric "$version" ${loader:+"$loader"}) || exit 1
            read -r _ loader jar url <<< "$linea"
            [[ "$jar" =~ ^[A-Za-z0-9._+\-]+\.jar$ ]] && url_valida "$url" || error "Respuesta rara de Fabric."
            emitir "ETAPA Bajando Fabric $loader"
            descargar_jar "$url" - "$dir/$jar" || error "No se pudo bajar Fabric."
            # El lanzador de Fabric usa server.jar: se baja ya (comprobado) para que el primer arranque no lo busque
            emitir "ETAPA Bajando el servidor oficial de Minecraft $version"
            descargar_jar "$url_vanilla" "sha1:$sha1_vanilla" "$dir/server.jar" || error "No se pudo bajar el servidor de Minecraft." ;;
        forge)
            emitir "ETAPA Buscando Forge para $version"
            linea=$(api_linea FORGE forge "$version" ${loader:+"$loader"}) || exit 1
            read -r _ loader url sha1 <<< "$linea"
            url_valida "$url" && [[ "$sha1" =~ ^[0-9a-f]{40}$ ]] || error "Respuesta rara de Forge."
            emitir "ETAPA Bajando el instalador de Forge $loader"
            descargar_jar "$url" "sha1:$sha1" "$dir/forge-instalador.jar" || error "No se pudo bajar Forge (o la suma no coincide)."
            emitir "ETAPA Instalando Forge $loader (baja sus librerías: puede tardar unos minutos)"
            ( cd "$dir" && "$bin_java/java" -jar forge-instalador.jar --installServer ) > "$dir/.forge-instalador.log" 2>&1 \
                || error "El instalador de Forge falló: $(tail -n 3 "$dir/.forge-instalador.log" | tr '\n' ' ')"
            rm -f "$dir"/forge-instalador.jar "$dir"/forge-instalador.jar.log "$dir"/.forge-instalador.log "$dir"/installer.log
            if [[ -f "$dir/run.sh" ]]; then
                { grep -v -- '^-Xmx' "$dir/user_jvm_args.txt" 2>/dev/null; printf -- '-Xmx%s\n' "$ram"; } > "$dir/.jvm" && mv -f "$dir/.jvm" "$dir/user_jvm_args.txt"
            else
                # Los Forge viejos no tienen run.sh: se arrancan con su jar
                for f in "$dir"/forge-*.jar; do
                    [[ -f "$f" && "$f" != *installer* && "$f" != *instalador* ]] && { jar=$(basename "$f"); break; }
                done
                [[ -n "$jar" ]] || error "Forge se instaló pero no encuentro cómo arrancarlo."
            fi ;;
    esac
}

case "${1:-}" in
servidores)
    while IFS= read -r servidor; do
        leer_conf "$servidor"
        carpeta=$(carpeta_servidor "$servidor")
        apagado "$servidor" && estado=APAGADO || estado=ENCENDIDO
        tam=$(du -sh "$carpeta/$(mundo_servidor "$servidor")" 2>/dev/null | cut -f1)
        ultimo=$(stat -c %Y "$carpeta/logs/latest.log" 2>/dev/null)
        [[ -n "$ultimo" ]] && ultimo=$(date -d "@$ultimo" +%Y-%m-%d)
        apaga=""
        marca="$(dir_estado)/vacio-$(sesion "$servidor")"
        if [[ "$estado" == ENCENDIDO && -f "$marca" ]]; then
            apaga=$(( ($(cat "$marca" 2>/dev/null || echo 0) - $(date +%s) + 59) / 60 ))
            (( apaga >= 0 )) || apaga=0
        fi
        icono=""; [[ -f "$carpeta/server-icon.png" ]] && icono="$carpeta/server-icon.png"
        printf 'SERVIDOR %s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$estado" "$servidor" "$CONF_TIPO" "$CONF_VERSION" \
            "${tam:--}" "${ultimo:--}" "$CONF_RAM" "${CONF_JAR:-run.sh}" "$apaga" "$icono"
    done < <(listar_servidores)
    ;;

consola)
    servidor="${2:-}"; servidor_valido "$servidor"
    leer_conf "$servidor"
    cd "$(carpeta_servidor "$servidor")" || exit 1
    echo "== $NV ($(nombre_tipo "$CONF_TIPO") $CONF_VERSION, hasta $CONF_RAM de RAM). Para apagarlo: escribí «stop»."
    [[ -n "${TMUX:-}" ]] && echo "== Cerrar esta ventana no lo apaga: sigue en segundo plano (el Panel de Minecraft lo vuelve a mostrar)."
    # El Java que pidió al crearlo (si no, el de siempre)
    if [[ -n "$CONF_JAVA" ]]; then
        if bin_java=$(java_para "$CONF_JAVA"); then export PATH="$bin_java:$PATH"
        else echo "== Ojo: no está Java $CONF_JAVA (ni uno más nuevo): uso el de siempre."; fi
    fi
    if [[ "$CONF_TIPO" == forge && -f run.sh ]]; then
        bash ./run.sh nogui
    else
        [[ -f "$CONF_JAR" ]] || { echo "No está $CONF_JAR (revisá JAR en servidor.conf)."; read -r -p "Enter para cerrar…"; exit 1; }
        java -Xms1G -Xmx"$CONF_RAM" -jar "$CONF_JAR" nogui
    fi
    echo; echo "Servidor cerrado."
    # En tmux sin nadie mirando no hace falta esperar
    [[ -n "${TMUX:-}" && "$(tmux display-message -p '#{session_attached}' 2>/dev/null)" == 0 ]] && exit 0
    read -r -t 30 -p "Enter para cerrar (se cierra solo en 30 s)…" || true
    ;;

iniciar)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" || { emitir "LISTO $NV ya está encendido."; exit 0; }
    # Todos usan el puerto 25565: si hay otro prendido, este no podría arrancar
    while IFS= read -r otro; do
        [[ "$otro" != "$servidor" ]] && ! apagado "$otro" && error "Ya está encendido «$(nombre_visible "$otro")» (usan el mismo puerto). Detenelo primero."
    done < <(listar_servidores)
    # BlueMap baja recursos del juego solo si se acepta (se aceptó al instalarlo con «extra bluemap»)
    if [[ -f "$(carpeta_servidor "$servidor")/.bluemap-aceptado" ]]; then
        for f in "$(carpeta_servidor "$servidor")"/{plugins/BlueMap,config/bluemap}/core.conf; do
            [[ -f "$f" ]] && sed -i 's/^accept-download: *false/accept-download: true/' "$f"
        done
    fi
    arrancar "$servidor"
    abrir_terminal "$servidor"
    emitir "LISTO $NV iniciado."
    ;;

detener|reiniciar)
    accion="$1"; servidor="${2:-}"; servidor_valido "$servidor"
    segundos="${3:-0}"
    [[ "$segundos" =~ ^[0-9]{1,3}$ ]] || error "Los segundos de aviso tienen que ser un número (0 a 999)." 2
    if apagado "$servidor"; then
        [[ "$accion" == detener ]] && { emitir "LISTO $NV ya estaba apagado."; exit 0; }
        error "$NV no está encendido."
    fi
    if [[ "$accion" == detener ]]; then
        detener "$servidor" "$segundos" apaga
        emitir "LISTO $NV detenido (mundos guardados)."
    else
        detener "$servidor" "$segundos" reinicia
        emitir "ETAPA Abriendo $NV"
        arrancar "$servidor"
        abrir_terminal "$servidor"
        emitir "LISTO $NV reiniciado."
    fi
    ;;

terminal)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" && error "$NV no está encendido."
    compartida "$servidor" || error "$NV se prendió sin consola compartida: su terminal es la que se abrió al iniciarlo."
    MINECRAFT_SIN_TERMINAL=0 abrir_terminal "$servidor"
    emitir "LISTO Abriendo la consola de $NV (cerrar la terminal no lo apaga)."
    ;;

comando)
    servidor="${2:-}"; servidor_valido "$servidor"
    texto="${3:-}"
    texto="${texto#"${texto%%[![:space:]]*}"}"; texto="${texto%"${texto##*[![:space:]]}"}"    # sin espacios a los costados
    texto="${texto#/}"
    [[ -n "$texto" ]] || error "Escribí un comando (por ejemplo: say hola)." 2
    [[ "$texto" != *[[:cntrl:]]* ]] || error "El comando no puede tener saltos de línea ni caracteres de control." 2
    (( ${#texto} <= 500 )) || error "El comando es demasiado largo." 2
    apagado "$servidor" && error "$NV no está encendido."
    compartida "$servidor" || error "$NV se prendió sin consola compartida (desde otro lado o con un Manager anterior a la 4.12.0): reinicialo desde el panel para mandarle comandos."
    enviar "$servidor" "$texto" || error "No se pudo escribir en la consola de $NV."
    emitir "LISTO Enviado a $NV: $texto"
    ;;

registro)
    servidor="${2:-}"; servidor_valido "$servidor"
    if apagado "$servidor"; then emitir "CONSOLA APAGADO"
    elif compartida "$servidor"; then emitir "CONSOLA COMANDOS"
    else emitir "CONSOLA SOLO_LECTURA"; fi
    # Sigue el archivo aunque Paper lo cambie al reiniciar (-F); termina cuando el panel lo cancela, si
    # el Manager se cierra de golpe (--pid: el proceso que lo llamó) o si nadie lee: cada 15 s escribe
    # «LATIDO» y, si no puede (se cortó el SSH del celular), corta el tail.
    tail -n 300 -F --pid="$PPID" -- "$(carpeta_servidor "$servidor")/logs/latest.log" 2>/dev/null \
        > >(sed -u 's/\r$//; s/^/LINEA /') &
    cola=$!
    trap 'kill "$cola" 2>/dev/null' EXIT
    trap '' PIPE
    while kill -0 "$cola" 2>/dev/null; do
        sleep 15
        printf 'LATIDO\n' 2>/dev/null || break
    done
    ;;

jugadores)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" && exit 0
    puerto=$(sed -n 's/^server-port=//p' "$(carpeta_servidor "$servidor")/server.properties" 2>/dev/null | head -n1 | tr -d '\r ')
    [[ "$puerto" =~ ^[0-9]{1,5}$ ]] || puerto=25565
    python3 -I "$API" ping "$puerto" 2>/dev/null | grep '^JUGADORES ' || emitir "AVISO $NV todavía no contesta (puede estar arrancando)."
    exit 0
    ;;

paper)
    shift
    (( $# )) || error "Elegí al menos un servidor." 2
    actualizados=0
    for servidor in "$@"; do
        servidor_valido "$servidor"
        leer_conf "$servidor"
        [[ "$CONF_TIPO" == paper ]] || { emitir "AVISO $NV no es Paper: no se toca."; continue; }
        apagado "$servidor" || { emitir "AVISO $NV está encendido: no se toca."; continue; }
        emitir "ETAPA Buscando la última compilación de Paper $CONF_VERSION"
        linea=$(python3 -I "$API" paper "$CONF_VERSION" 2>/dev/null | grep '^PAPER ' | head -n1)
        [[ -n "$linea" ]] || { emitir "AVISO No hay compilación estable de Paper $CONF_VERSION (o no hubo conexión)."; continue; }
        read -r _ build nombre sha256 url <<< "$linea"
        [[ "$nombre" =~ ^[A-Za-z0-9._\-]+\.jar$ && "$url" == https://* ]] || { emitir "AVISO Respuesta rara de PaperMC."; continue; }
        if [[ "$CONF_JAR" == "$nombre" ]]; then
            emitir "AVISO $NV ya tiene Paper $CONF_VERSION compilación $build."
            continue
        fi
        carpeta=$(carpeta_servidor "$servidor")
        emitir "ETAPA Descargando Paper $CONF_VERSION compilación $build para $NV"
        descargar_jar "$url" "sha256:$sha256" "$carpeta/$nombre" || { emitir "AVISO La descarga de Paper falló (o la suma no coincide)."; continue; }
        viejo="$CONF_JAR"
        cambiar_conf "$servidor" JAR "$nombre"
        [[ -n "$viejo" && -f "$carpeta/$viejo" && "$viejo" != "$nombre" ]] && a_respaldos "$servidor" viejo "$carpeta/$viejo"
        emitir "AVISO $NV: ${viejo:-?} → $nombre"
        actualizados=$((actualizados + 1))
    done
    emitir "LISTO Paper actualizado en $actualizados servidor(es)."
    ;;

plugins)
    servidor="${2:-}"; servidor_valido "$servidor"
    leer_conf "$servidor"
    sub=$(carpeta_complementos "$CONF_TIPO")
    [[ -n "$sub" ]] || { emitir "LISTO $NV es $(nombre_tipo "$CONF_TIPO"): no usa plugins ni mods."; exit 0; }
    carpeta=$(carpeta_servidor "$servidor")
    shopt -s nullglob
    jars=("$carpeta/$sub"/*.jar)
    (( ${#jars[@]} )) || { emitir "LISTO $NV no tiene $sub."; exit 0; }
    emitir "ETAPA Consultando Modrinth"
    python3 -I "$API" plugins "$CONF_VERSION" "--tipo=$CONF_TIPO" "${jars[@]}" 2>/dev/null | grep '^PLUGIN '
    emitir "LISTO ${#jars[@]} $( [[ $sub == mods ]] && echo "mod(s)" || echo "plugin(s)") en $NV."
    ;;

plugins-actualizar)
    servidor="${2:-}"; servidor_valido "$servidor"; shift 2
    apagado "$servidor" || error "$NV está encendido: detenelo antes de cambiar plugins o mods."
    leer_conf "$servidor"
    sub=$(carpeta_complementos "$CONF_TIPO")
    [[ -n "$sub" ]] || error "$NV es $(nombre_tipo "$CONF_TIPO"): no usa plugins ni mods."
    carpeta=$(carpeta_servidor "$servidor")
    shopt -s nullglob
    if (( $# )); then
        jars=()
        for a in "$@"; do
            [[ "$a" != */* && -f "$carpeta/$sub/$a" ]] || error "No existe «$a» en $sub/." 2
            jars+=("$carpeta/$sub/$a")
        done
    else
        jars=("$carpeta/$sub"/*.jar)
    fi
    (( ${#jars[@]} )) || error "$NV no tiene $sub."
    emitir "ETAPA Consultando Modrinth"
    actualizados=0
    while IFS=$'\t' read -r archivo nombre actual nueva estado url suma nuevo_archivo; do
        archivo="${archivo#PLUGIN }"
        [[ "$estado" == NUEVA ]] || continue
        url_valida "$url" && [[ "$nuevo_archivo" =~ ^[^/]+\.jar$ ]] || { emitir "AVISO $nombre: respuesta rara, no se toca."; continue; }
        [[ "$suma" == sha256:* ]] || suma="sha512:$suma"
        emitir "ETAPA Descargando $nombre $nueva"
        tmp=$(mktemp -d)
        if ! descargar_jar "$url" "$suma" "$tmp/$nuevo_archivo"; then
            emitir "AVISO $nombre: la descarga falló (o la suma no coincide), queda el que estaba."
            rm -rf "$tmp"; continue
        fi
        a_respaldos "$servidor" "$sub" "$carpeta/$sub/$archivo"
        mv -f "$tmp/$nuevo_archivo" "$carpeta/$sub/$nuevo_archivo"
        rm -rf "$tmp"
        emitir "AVISO $nombre: $actual → $nueva"
        actualizados=$((actualizados + 1))
    done < <(python3 -I "$API" plugins "$CONF_VERSION" "--tipo=$CONF_TIPO" "${jars[@]}" 2>/dev/null | grep '^PLUGIN ')
    emitir "LISTO $actualizados actualizado(s) en $NV (los anteriores quedan en Respaldos/$servidor/$sub)."
    ;;

plugin)
    texto="${2:-}"; shift 2 2>/dev/null || true
    [[ -n "$texto" ]] || error "Escribí el nombre del plugin o mod (o su URL)." 2
    (( $# )) || error "Elegí al menos un servidor." 2
    instalados=0
    for servidor in "$@"; do
        servidor_valido "$servidor"
        leer_conf "$servidor"
        sub=$(carpeta_complementos "$CONF_TIPO")
        [[ -n "$sub" ]] || { emitir "AVISO $NV es $(nombre_tipo "$CONF_TIPO"): no usa plugins ni mods."; continue; }
        destino="$(carpeta_servidor "$servidor")/$sub"
        if [[ "$texto" == https://* && "$texto" != *modrinth.com/* ]]; then
            # Otra página: el archivo tal cual (lo último de la URL, sin lo que va después de «?»)
            nombre=$(basename "${texto%%\?*}"); [[ "$nombre" == *.jar ]] || nombre="$nombre.jar"
            emitir "ETAPA Descargando $nombre para $NV"
            tmp=$(mktemp -d)
            descargar_jar "$texto" - "$tmp/$nombre" || { emitir "AVISO $NV: la descarga falló o no es un .jar."; rm -rf "$tmp"; continue; }
            if ! complemento_sirve "$tmp/$nombre" "$CONF_TIPO"; then
                emitir "AVISO $NV: $nombre no es $(que_complemento "$CONF_TIPO"): no se instala."; rm -rf "$tmp"; continue
            fi
            mkdir -p "$destino"; mv -f "$tmp/$nombre" "$destino/$nombre"; rm -rf "$tmp"
        else
            emitir "ETAPA Buscando «$texto» en Modrinth para $(nombre_tipo "$CONF_TIPO") $CONF_VERSION"
            hubo=0
            while IFS=$'\t' read -r clase slug titulo version url sha512 nombre motivo; do
                if [[ "$clase" == NO_SIRVE ]]; then emitir "AVISO $NV: $slug: $titulo."; continue; fi
                url_valida "$url" && [[ "$nombre" =~ ^[^/]+\.jar$ ]] || { emitir "AVISO Respuesta rara de Modrinth."; continue; }
                [[ -f "$destino/$nombre" ]] && { hubo=1; continue; }
                emitir "ETAPA Descargando $titulo $version para $NV"
                descargar_jar "$url" "sha512:$sha512" "$destino/$nombre" || { emitir "AVISO $NV: la descarga de $titulo falló."; continue; }
                [[ "$motivo" == pedido ]] && emitir "AVISO $NV: $titulo $version instalado." || emitir "AVISO $NV: $titulo $version instalado ($motivo)."
                hubo=1
            done < <(python3 -I "$API" complementos "$CONF_TIPO" "$CONF_VERSION" "$texto" 2>/dev/null \
                     | sed -n 's/^\(COMPLEMENTO\|NO_SIRVE\) /\1\t/p')
            (( hubo )) || continue
        fi
        instalados=$((instalados + 1))
    done
    emitir "LISTO Instalado en $instalados servidor(es). Se activa al iniciarlos (o reiniciarlos)."
    ;;

reiniciar-mundo)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" || error "$NV está encendido: detenelo primero."
    carpeta=$(carpeta_servidor "$servidor")
    mundo=$(mundo_servidor "$servidor")
    partes=()
    for m in "$mundo" "${mundo}_nether" "${mundo}_the_end"; do [[ -d "$carpeta/$m" ]] && partes+=("$m"); done
    (( ${#partes[@]} )) || { emitir "LISTO $NV no tenía mundo: se crea uno nuevo al iniciarlo."; exit 0; }
    archivo=$(guardar_mundo "$servidor") || error "No se pudo guardar el mundo: no se borró nada."
    for m in "${partes[@]}"; do rm -rf -- "${carpeta:?}/$m"; done
    emitir "LISTO Mundo de $NV reiniciado. El anterior quedó en Respaldos/$servidor/mundos/$(basename "$archivo")."
    ;;

ram)
    servidor="${2:-}"; servidor_valido "$servidor"
    ram="${3:-}"
    [[ "$ram" =~ ^[0-9]+[GM]$ ]] || error "La memoria tiene que ser como 8G o 4096M." 2
    leer_conf "$servidor"
    cambiar_conf "$servidor" RAM "$ram"
    # Forge con run.sh toma la memoria de user_jvm_args.txt
    args="$(carpeta_servidor "$servidor")/user_jvm_args.txt"
    if [[ "$CONF_TIPO" == forge && -f "$args" ]]; then
        { grep -v -- '^-Xmx' "$args"; printf -- '-Xmx%s\n' "$ram"; } > "$args.nuevo" && mv -f "$args.nuevo" "$args"
    fi
    emitir "LISTO $NV va a usar hasta $ram de RAM (al iniciarlo de nuevo)."
    ;;

opciones)
    # Las versiones casi no cambian: se guardan 6 horas (sin avisos, que son de una consulta que falló)
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/Arch-Linux-Manager/minecraft-opciones.txt"
    if [[ -z "${MINECRAFT_API_FALSA:-}" && -s "$cache" && -n "$(find "$cache" -mmin -360 2>/dev/null)" ]]; then
        cat "$cache"
    else
        salida=$(python3 -I "$API" opciones 2>/dev/null | grep -E '^(VERSION|AVISO) ') || error "No se pudieron consultar las versiones de Minecraft (¿hay internet?)."
        printf '%s\n' "$salida"
        if [[ -z "${MINECRAFT_API_FALSA:-}" ]] && ! grep -q '^AVISO ' <<< "$salida"; then
            mkdir -p "$(dirname "$cache")" && printf '%s\n' "$salida" > "$cache"
        fi
    fi
    for d in "$SERVIDORES_DIR"/*/; do
        [[ -d "$d" && ! -f "$d/servidor.conf" ]] && emitir "GRUPO $(basename "$d")"
    done
    for d in "${MINECRAFT_JVM_DIR:-/usr/lib/jvm}"/java-*-openjdk; do
        n="${d##*/java-}"; n="${n%-openjdk}"
        [[ "$n" =~ ^[0-9]+$ ]] && { [[ -x "$d/bin/java" || -x "$d/jre/bin/java" ]]; } && emitir "JAVA $n"
    done
    exit 0
    ;;

buscar-modrinth)
    clase="${2:-}"; tipo="${3:-}"; version="${4:-}"; texto="${5:-}"
    [[ "$clase" =~ ^(complemento|modpack)$ && "$tipo" =~ ^(paper|fabric|forge|vanilla)?$ ]] || error "Uso: buscar-modrinth complemento|modpack TIPO VERSION TEXTO" 2
    [[ -z "$version" || "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || error "Versión rara." 2
    [[ "$texto" != *[[:cntrl:]]* ]] && (( ${#texto} <= 100 )) || error "Búsqueda rara." 2
    if [[ "$clase" == complemento ]] && ! admite "$tipo" plugins && ! admite "$tipo" mods; then
        error "Un servidor $(nombre_tipo "$tipo") no usa plugins ni mods." 2
    fi
    python3 -I "$API" buscar-modrinth "$clase" "${tipo:-fabric}" "$version" "$texto" 2>/dev/null | grep '^RESULTADO '
    exit 0
    ;;

modpack-versiones)
    slug="${2:-}"
    [[ "$slug" =~ ^[A-Za-z0-9_.-]{1,80}$ ]] || error "Modpack raro." 2
    python3 -I "$API" modpack-versiones "$slug" 2>&1 | grep -E '^(MODPACK|ERROR) '
    ;;

# Arma un servidor nuevo. La configuración llega por stdin, una CLAVE=valor por línea:
#   GRUPO, NOMBRE (la carpeta queda Servidores/<GRUPO>/<versión menor>/<VERSION> <NOMBRE>), TIPO, VERSION, EULA=true
#   (obligatorio: el usuario aceptó el EULA de Minecraft); opcionales: LOADER (Fabric/Forge; si no, el recomendado),
#   RAM, MOTD, MODO, DIFICULTAD, HARDCORE, JUGADORES, SEMILLA, WHITELIST, ONLINE, PVP, DISTANCIA,
#   MUNDO (carpeta o .zip con un mundo) o MUNDO_SERVIDOR (copiar el de otro servidor, apagado),
#   MODPACK_URL + MODPACK_SHA512 (de Modrinth) o MODPACK_ARCHIVO (.mrpack), y COMPLEMENTO (nombre/slug/URL de
#   Modrinth) o COMPLEMENTO_ARCHIVO (.jar) repetidos: plugins en Paper, mods en Fabric/Forge.
# Se arma en Minecraft Servers/.creando/ y recién al final (con servidor.conf adentro) se mueve a Servidores/:
# si algo falla o se cancela, no queda nada a medias en la lista.
crear)
    declare -A C=()
    complementos=(); complementos_archivo=()
    while IFS= read -r linea || [[ -n "$linea" ]]; do
        [[ -n "$linea" ]] || continue
        [[ "$linea" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || error "Línea rara en la configuración." 2
        clave="${BASH_REMATCH[1]}"; valor="${BASH_REMATCH[2]}"
        [[ "$valor" != *[[:cntrl:]]* ]] || error "La opción $clave tiene caracteres raros." 2
        case "$clave" in
            COMPLEMENTO) complementos+=("$valor") ;;
            COMPLEMENTO_ARCHIVO) complementos_archivo+=("$valor") ;;
            GRUPO|NOMBRE|TIPO|VERSION|LOADER|RAM|MOTD|MODO|DIFICULTAD|HARDCORE|JUGADORES|SEMILLA|WHITELIST|ONLINE|PVP|DISTANCIA|MUNDO|MUNDO_SERVIDOR|MODPACK_URL|MODPACK_SHA512|MODPACK_ARCHIVO|EULA)
                C[$clave]="$valor" ;;
            *) error "No conozco la opción $clave." 2 ;;
        esac
    done
    nombre_ok() { [[ "$1" =~ ^[[:alnum:]][[:alnum:]\ ._()+-]{0,39}$ && "$1" != *..* && "$1" != *[\ .] ]]; }
    grupo="${C[GRUPO]:-}"; nombre="${C[NOMBRE]:-}"; tipo="${C[TIPO]:-}"; version="${C[VERSION]:-}"
    nombre_ok "$grupo" || error "El grupo tiene que ser un nombre corto (letras, números, espacios, . _ - ( ) +)." 2
    nombre_ok "$nombre" || error "El nombre tiene que ser corto (letras, números, espacios, . _ - ( ) +)." 2
    [[ "$tipo" =~ ^(vanilla|paper|fabric|forge)$ ]] || error "El software tiene que ser Vanilla, Paper, Fabric o Forge." 2
    [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || error "Versión de Minecraft rara." 2
    [[ "${C[EULA]:-}" == true ]] || error "Hay que aceptar el EULA de Minecraft para crear un servidor." 2
    loader="${C[LOADER]:-}"; [[ -z "$loader" || "$loader" =~ ^[0-9A-Za-z.+-]{1,40}$ ]] || error "Versión del cargador rara." 2
    [[ "$tipo" == fabric || "$tipo" == forge || -z "$loader" ]] || error "Solo Fabric y Forge tienen versión de cargador." 2
    ram="${C[RAM]:-4G}"; [[ "$ram" =~ ^([1-9][0-9]*G|[1-9][0-9]{3,}M)$ ]] || error "La memoria tiene que ser como 4G (1G o más)." 2
    motd="${C[MOTD]:-$nombre}"; (( ${#motd} <= 60 )) || error "El mensaje de la lista (MOTD) es demasiado largo." 2
    modo="${C[MODO]:-survival}"; [[ "$modo" =~ ^(survival|creative|adventure|spectator)$ ]] || error "Modo de juego raro." 2
    dificultad="${C[DIFICULTAD]:-normal}"; [[ "$dificultad" =~ ^(peaceful|easy|normal|hard)$ ]] || error "Dificultad rara." 2
    for b in HARDCORE WHITELIST ONLINE PVP; do [[ -z "${C[$b]:-}" || "${C[$b]}" =~ ^(true|false)$ ]] || error "$b tiene que ser true o false." 2; done
    jugadores="${C[JUGADORES]:-20}"; [[ "$jugadores" =~ ^[0-9]{1,3}$ ]] && (( jugadores >= 1 && jugadores <= 500 )) || error "Jugadores: de 1 a 500." 2
    distancia="${C[DISTANCIA]:-10}"; [[ "$distancia" =~ ^[0-9]{1,2}$ ]] && (( distancia >= 2 && distancia <= 32 )) || error "Distancia de visión: de 2 a 32." 2
    semilla="${C[SEMILLA]:-}"; (( ${#semilla} <= 64 )) || error "La semilla es demasiado larga." 2
    # Compatibilidades
    if (( ${#complementos[@]} + ${#complementos_archivo[@]} )); then
        sub=$(carpeta_complementos "$tipo")
        [[ -n "$sub" ]] || error "Un servidor $(nombre_tipo "$tipo") no usa plugins ni mods." 2
    fi
    if [[ -n "${C[MODPACK_URL]:-}${C[MODPACK_ARCHIVO]:-}" ]]; then
        admite "$tipo" modpack || error "Los modpacks son para Fabric o Forge, no para $(nombre_tipo "$tipo")." 2
        [[ -z "${C[MODPACK_URL]:-}" || -z "${C[MODPACK_ARCHIVO]:-}" ]] || error "Elegí un solo modpack." 2
        if [[ -n "${C[MODPACK_URL]:-}" ]]; then
            url_valida "${C[MODPACK_URL]}" && [[ "${C[MODPACK_SHA512]:-}" =~ ^[0-9a-f]{128}$ ]] || error "Modpack de Modrinth raro." 2
        else
            [[ "${C[MODPACK_ARCHIVO]}" == /*.mrpack && -f "${C[MODPACK_ARCHIVO]}" ]] || error "No encuentro el archivo del modpack (.mrpack)." 2
        fi
    fi
    for f in "${complementos_archivo[@]}"; do
        [[ "$f" == /*.jar && -f "$f" ]] || error "No encuentro «$f»." 2
        complemento_sirve "$f" "$tipo" || error "$(basename "$f") no es $(que_complemento "$tipo")." 2
    done
    [[ -z "${C[MUNDO]:-}" || -z "${C[MUNDO_SERVIDOR]:-}" ]] || error "Elegí un solo mundo." 2
    if [[ -n "${C[MUNDO]:-}" ]]; then
        [[ "${C[MUNDO]}" == /* && -e "${C[MUNDO]}" ]] || error "No encuentro el mundo «${C[MUNDO]}»." 2
        origen_mundo="${C[MUNDO]}"
    elif [[ -n "${C[MUNDO_SERVIDOR]:-}" ]]; then
        servidor_valido "${C[MUNDO_SERVIDOR]}"
        apagado "${C[MUNDO_SERVIDOR]}" || error "$NV está encendido: detenelo para copiar su mundo."
        origen_mundo="$(carpeta_servidor "${C[MUNDO_SERVIDOR]}")/$(mundo_servidor "${C[MUNDO_SERVIDOR]}")"
        [[ -d "$origen_mundo" ]] || error "$NV todavía no tiene mundo."
    fi
    menor=$(cut -d. -f1,2 <<< "$version")
    servidor="$grupo/$menor/$version $nombre"
    final="$SERVIDORES_DIR/$servidor"
    [[ ! -e "$final" ]] || error "Ya existe un servidor «$version $nombre» en $grupo." 2
    NV=$(nombre_visible "$servidor")

    mkdir -p "$MINECRAFT_DIR/.creando" || error "No se pudo escribir en $MINECRAFT_DIR."
    tmpd=$(mktemp -d "$MINECRAFT_DIR/.creando/XXXXXX") || error "No se pudo escribir en $MINECRAFT_DIR."
    chmod 755 "$tmpd"
    trap 'rm -rf "$tmpd"' EXIT
    trap 'exit 130' TERM INT HUP
    preparar_version "$version"

    # Modpack primero: dice qué versión del cargador hace falta y trae sus mods y configuraciones
    if [[ -n "${C[MODPACK_URL]:-}${C[MODPACK_ARCHIVO]:-}" ]]; then
        pack="$tmpd/.modpack.mrpack"
        if [[ -n "${C[MODPACK_URL]:-}" ]]; then
            emitir "ETAPA Bajando el modpack"
            python3 -I "$API" bajar-modrinth "${C[MODPACK_URL]}" "${C[MODPACK_SHA512]}" "$pack" &> /dev/null \
                || error "No se pudo bajar el modpack (o la suma no coincide)."
        else
            cp -- "${C[MODPACK_ARCHIVO]}" "$pack" || error "No se pudo leer el modpack."
        fi
        emitir "ETAPA Instalando el modpack"
        # (con «FIN código» al final, para saber si terminó bien)
        motivo=""; codigo=1
        while IFS= read -r l; do
            case "$l" in
                LOADER\ *) loader="${l#LOADER }" ;;
                ETAPA\ *|AVISO\ *) emitir "$l" ;;
                ERROR\ *) motivo="${l#ERROR }" ;;
                FIN\ *) codigo="${l#FIN }" ;;
            esac
        done < <(python3 -I "$API" mrpack "$pack" "$tmpd" "$tipo" "$version" 2>&1; echo "FIN $?")
        [[ "$codigo" == 0 ]] || error "${motivo:-El modpack no se pudo instalar.}"
        [[ "$loader" =~ ^[0-9A-Za-z.+-]{1,40}$ ]] || error "El modpack no dice qué versión de $(nombre_tipo "$tipo") usa."
        # (queda como .modpack.mrpack: el pack para los jugadores parte de él, con lo que es solo del cliente)
    fi

    instalar_software "$tipo" "$version" "$loader" "$ram" "$tmpd"

    printf 'eula=true\n' > "$tmpd/eula.txt"
    # server.properties (las versiones de antes de la 1.13 usan números para el modo y la dificultad)
    if [[ "$version" =~ ^1\.([0-9]+) ]] && (( BASH_REMATCH[1] < 13 )); then
        declare -A num=([survival]=0 [creative]=1 [adventure]=2 [spectator]=3 [peaceful]=0 [easy]=1 [normal]=2 [hard]=3)
        modo_p="${num[$modo]}"; dificultad_p="${num[$dificultad]}"
    else
        modo_p="$modo"; dificultad_p="$dificultad"
    fi
    python3 -I "$API" propiedades "$tmpd/server.properties" "motd=$motd" "gamemode=$modo_p" "difficulty=$dificultad_p" \
        "hardcore=${C[HARDCORE]:-false}" "max-players=$jugadores" "level-seed=$semilla" "level-name=world" \
        "white-list=${C[WHITELIST]:-false}" "enforce-whitelist=${C[WHITELIST]:-false}" "online-mode=${C[ONLINE]:-true}" \
        "pvp=${C[PVP]:-true}" "view-distance=$distancia" "server-port=25565" &> /dev/null || error "No se pudo escribir server.properties."

    if [[ -n "${origen_mundo:-}" ]]; then
        emitir "ETAPA Copiando el mundo (puede tardar)"
        linea=$(api_linea MUNDO mundo "$origen_mundo" "$tmpd") || exit 1
        version_mundo="${linea#MUNDO }"
        if [[ "$version_mundo" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ && "$version_mundo" != "$version" \
              && "$(printf '%s\n%s\n' "$version_mundo" "$version" | sort -V | tail -n1)" == "$version_mundo" ]]; then
            error "El mundo es de Minecraft $version_mundo: no se puede abrir en $version (más vieja) sin romperlo."
        fi
        [[ "$tipo" == paper ]] || mundo_desde_paper "$tmpd/world"
        [[ "$version_mundo" == "?" ]] && emitir "AVISO No pude saber de qué versión es el mundo: si es de una más nueva que $version, no va a abrir."
        [[ "$version_mundo" != "?" && "$version_mundo" != "$version" ]] && emitir "AVISO El mundo es de $version_mundo: Minecraft lo actualiza a $version al abrirlo (no se puede volver atrás)."
    fi

    if (( ${#complementos[@]} )); then
        emitir "ETAPA Buscando $( [[ $sub == mods ]] && echo mods || echo plugins) en Modrinth"
        salida=$(python3 -I "$API" complementos "$tipo" "$version" "${complementos[@]}" 2>/dev/null)
        if grep -q '^NO_SIRVE ' <<< "$salida"; then
            error "No sirve para $(nombre_tipo "$tipo") $version: $(sed -n 's/^NO_SIRVE //p' <<< "$salida" | tr '\t' ':' | paste -sd ';' | sed 's/;/; /g')."
        fi
        while IFS=$'\t' read -r slug titulo ver url sha512 archivo motivo; do
            url_valida "$url" && [[ "$archivo" =~ ^[^/]+\.jar$ && "$sha512" =~ ^[0-9a-f]{128}$ ]] || error "Respuesta rara de Modrinth."
            [[ -f "$tmpd/$sub/$archivo" ]] && continue      # ya lo trajo el modpack
            emitir "ETAPA Bajando $titulo $ver"
            descargar_jar "$url" "sha512:$sha512" "$tmpd/$sub/$archivo" || error "No se pudo bajar $titulo (o la suma no coincide)."
            [[ "$motivo" == pedido ]] || emitir "AVISO También va $titulo ($motivo)."
        done < <(sed -n 's/^COMPLEMENTO //p' <<< "$salida")
    fi
    for f in "${complementos_archivo[@]}"; do
        mkdir -p "$tmpd/$sub"; cp -- "$f" "$tmpd/$sub/" || error "No se pudo copiar $(basename "$f")."
    done

    {
        echo "# Servidor de Minecraft (lo lee Arch-Linux-Manager: Logica/Minecraft.sh). Creado el $(date +%Y-%m-%d)."
        printf 'NOMBRE="%s"\nTIPO=%s\nVERSION=%s\nJAR="%s"\nRAM=%s\nJAVA=%s\n' "$version $nombre" "$tipo" "$version" "$jar" "$ram" "$java_n"
        [[ -n "$loader" ]] && printf 'LOADER="%s"\n' "$loader"
    } > "$tmpd/servidor.conf"
    mkdir -p "$(dirname "$final")" || error "No se pudo crear la carpeta del grupo."
    [[ ! -e "$final" ]] || error "Ya existe un servidor «$version $nombre» en $grupo."
    mv -T -- "$tmpd" "$final" || error "No se pudo mover el servidor a su lugar."
    trap - EXIT TERM INT HUP
    rmdir "$MINECRAFT_DIR/.creando" 2>/dev/null
    emitir "CREADO $servidor"
    emitir "LISTO $NV creado ($(nombre_tipo "$tipo") $version${loader:+, cargador $loader}, Java $java_n). Ya se puede iniciar."
    ;;

jugadores-lista)
    servidor="${2:-}"; servidor_valido "$servidor"
    carpeta=$(carpeta_servidor "$servidor")
    conectados=""
    if ! apagado "$servidor"; then
        compartida "$servidor" && emitir "CONSOLA COMANDOS" || emitir "CONSOLA SOLO_LECTURA"
        puerto=$(sed -n 's/^server-port=//p' "$carpeta/server.properties" 2>/dev/null | head -n1 | tr -d '\r ')
        [[ "$puerto" =~ ^[0-9]{1,5}$ ]] || puerto=25565
        conectados=$(python3 -I "$API" ping "$puerto" 2>/dev/null | sed -n 's/^JUGADORES [0-9]*\t[0-9]*\t//p')
    else
        emitir "CONSOLA APAGADO"
    fi
    blanca=$(python3 -I "$API" opciones-servidor "$carpeta" 2>/dev/null | awk -F'\t' '$1=="OPCION white-list" {print $6}')
    emitir "LISTA_BLANCA ${blanca:-false}"
    python3 -I "$API" jugadores-listar "$carpeta" "$conectados" 2>/dev/null | grep '^JUGADOR '
    exit 0
    ;;

jugador)
    servidor="${2:-}"; servidor_valido "$servidor"
    accion="${3:-}"; nombre="${4:-}"; motivo="${5:-}"
    [[ "$accion" =~ ^(op|deop|whitelist-add|whitelist-remove|ban|pardon|kick|lista-blanca-si|lista-blanca-no)$ ]] || error "Acción de jugador desconocida." 2
    if [[ "$accion" != lista-blanca-* ]]; then
        [[ "$nombre" =~ ^\.?[A-Za-z0-9_]{1,16}$ ]] || error "Nombre de jugador raro (hasta 16 letras, números o _)." 2
    fi
    [[ "$motivo" != *[[:cntrl:]]* ]] && (( ${#motivo} <= 100 )) || error "El motivo es demasiado largo o tiene caracteres raros." 2
    carpeta=$(carpeta_servidor "$servidor")
    declare -A que=([op]="ahora es operador" [deop]="ya no es operador" [whitelist-add]="está en la lista blanca"
                    [whitelist-remove]="salió de la lista blanca" [ban]="está baneado" [pardon]="ya no está baneado"
                    [kick]="fue expulsado" [lista-blanca-si]="Lista blanca activada" [lista-blanca-no]="Lista blanca desactivada")
    if ! apagado "$servidor"; then
        # Prendido: lo hace el servidor (si se tocaran sus archivos, los pisaría al apagarse)
        compartida "$servidor" || error "$NV se prendió sin consola compartida: reinicialo desde el panel para administrar jugadores."
        case "$accion" in
            op|deop|pardon) comando="$accion $nombre" ;;
            whitelist-add)    comando="whitelist add $nombre" ;;
            whitelist-remove) comando="whitelist remove $nombre" ;;
            ban|kick)         comando="$accion $nombre${motivo:+ $motivo}" ;;
            lista-blanca-si)  comando="whitelist on" ;;
            lista-blanca-no)  comando="whitelist off" ;;
        esac
        enviar "$servidor" "$comando" || error "No se pudo escribir en la consola de $NV."
    else
        case "$accion" in
            kick) error "$NV está apagado: no hay a quién expulsar." ;;
            lista-blanca-si|lista-blanca-no)
                valor=$([[ "$accion" == lista-blanca-si ]] && echo true || echo false)
                leer_conf "$servidor"
                python3 -I "$API" propiedades-cambiar "$carpeta/server.properties" "$CONF_VERSION" "white-list=$valor" "enforce-whitelist=$valor" &>/dev/null \
                    || error "No se pudo cambiar server.properties." ;;
            *)
                online=$(python3 -I "$API" opciones-servidor "$carpeta" 2>/dev/null | awk -F'\t' '$1=="OPCION online-mode" {print $6}')
                salida=$(python3 -I "$API" jugador-editar "$carpeta" "$accion" "$nombre" "$motivo" "${online:-true}" 2>&1) \
                    || error "$(sed -n 's/^ERROR //p' <<< "$salida" | head -n1)"
                grep '^AVISO ' <<< "$salida" ;;
        esac
    fi
    if [[ "$accion" == lista-blanca-* ]]; then emitir "LISTO ${que[$accion]} en $NV."
    else emitir "LISTO $nombre ${que[$accion]} en $NV."; fi
    ;;

opciones-servidor)
    servidor="${2:-}"; servidor_valido "$servidor"
    leer_conf "$servidor"
    python3 -I "$API" opciones-servidor "$(carpeta_servidor "$servidor")" 2>/dev/null | grep '^OPCION '
    # Las del Manager (servidor.conf)
    printf 'AJUSTE RAM\t%s\nAJUSTE APAGAR_VACIO\t%s\nAJUSTE APAGAR_PC\t%s\n' "$CONF_RAM" "$CONF_APAGAR_VACIO" "$CONF_APAGAR_PC"
    [[ -f "$(carpeta_servidor "$servidor")/server-icon.png" ]] && emitir "ICONO si" || emitir "ICONO no"
    exit 0
    ;;

propiedades-cambiar)
    # Las opciones llegan por stdin (clave=valor por línea; los saltos de línea del MOTD como \n)
    servidor="${2:-}"; servidor_valido "$servidor"
    leer_conf "$servidor"
    # (también APAGAR_VACIO= y APAGAR_PC=, que van a servidor.conf)
    pares=(); ajustes=()
    while IFS= read -r linea; do
        case "$linea" in
            APAGAR_VACIO=*|APAGAR_PC=*) ajustes+=("$linea") ;;
            [a-z0-9]*=*) pares+=("$linea") ;;
        esac
    done < <(head -n 60)
    (( ${#pares[@]} + ${#ajustes[@]} )) || error "No hay nada para cambiar." 2
    for a in "${ajustes[@]}"; do aplicar_ajuste "$servidor" "${a%%=*}" "${a#*=}" > /dev/null || exit 2; done
    if (( ${#pares[@]} )); then
        salida=$(python3 -I "$API" propiedades-cambiar "$(carpeta_servidor "$servidor")/server.properties" "$CONF_VERSION" "${pares[@]}" 2>&1) \
            || error "$(sed -n 's/^ERROR //p' <<< "$salida" | head -n1)"
    fi
    apagado "$servidor" && emitir "LISTO Opciones de $NV guardadas." || emitir "LISTO Opciones de $NV guardadas: se aplican al reiniciarlo."
    ;;

ajuste)
    servidor="${2:-}"; servidor_valido "$servidor"
    texto=$(aplicar_ajuste "$servidor" "${3:-}" "${4:-}") || exit 2
    emitir "LISTO $NV: $texto."
    ;;

icono)
    servidor="${2:-}"; servidor_valido "$servidor"
    archivo="${3:-}"
    [[ "$archivo" == /* && -f "$archivo" ]] || error "No encuentro la imagen." 2
    python3 -I "$API" png64 "$archivo" &>/dev/null || error "El ícono tiene que ser un PNG de 64×64." 2
    cp -- "$archivo" "$(carpeta_servidor "$servidor")/server-icon.png" || error "No se pudo copiar el ícono."
    apagado "$servidor" && emitir "LISTO Ícono de $NV cambiado." || emitir "LISTO Ícono de $NV cambiado: se ve al reiniciarlo."
    ;;

respaldos)
    servidor="${2:-}"; servidor_valido "$servidor"
    base="$RESPALDOS_MC_DIR/$servidor"
    shopt -s nullglob
    for f in "$base"/mundos/*.tar.zst "$base"/viejo/*.jar "$base"/plugins/*.jar "$base"/mods/*.jar; do
        sub="${f%/*}"; sub="${sub##*/}"
        case "$sub" in mundos) tipo=mundo ;; viejo) tipo=jar ;; plugins) tipo=plugin ;; mods) tipo=mod ;; esac
        printf 'RESPALDO %s\t%s\t%s\t%s\n' "$tipo" "$(basename "$f")" "$(date -r "$f" '+%Y-%m-%d %H:%M')" "$(du -h "$f" | cut -f1)"
    done | sort -t$'\t' -k3 -r
    exit 0
    ;;

respaldo-guardar)
    servidor="${2:-}"; servidor_valido "$servidor"
    archivo=$(guardar_mundo "$servidor" "copia") || exit 1
    emitir "LISTO Mundo de $NV guardado en Respaldos/$servidor/mundos/$(basename "$archivo")."
    ;;

restaurar)
    servidor="${2:-}"; servidor_valido "$servidor"
    tipo="${3:-}"; archivo="${4:-}"
    [[ "$archivo" =~ ^[^/]+$ && "$archivo" != .* ]] || error "Respaldo raro." 2
    apagado "$servidor" || error "$NV está encendido: detenelo antes de restaurar."
    leer_conf "$servidor"
    carpeta=$(carpeta_servidor "$servidor")
    base="$RESPALDOS_MC_DIR/$servidor"
    case "$tipo" in
        mundo)
            origen="$base/mundos/$archivo"
            [[ "$archivo" == *.tar.zst && -f "$origen" ]] || error "No existe ese respaldo del mundo." 2
            # Adentro solo puede haber <mundo>/, <mundo>_nether/ y <mundo>_the_end/ (nada de rutas que se salgan)
            lista=$(tar --zstd -tf "$origen" 2>/dev/null) || error "El respaldo está dañado."
            raiz=$(head -n1 <<< "$lista" | cut -d/ -f1)
            [[ "$raiz" =~ ^[A-Za-z0-9._\ -]+$ && "$raiz" != .* ]] || error "El respaldo tiene rutas raras: no se toca nada."
            if grep -vE "^${raiz//./\\.}(_nether|_the_end)?(/|$)" <<< "$lista" | grep -q . || grep -qE '(^|/)\.\.(/|$)' <<< "$lista"; then
                error "El respaldo tiene rutas raras: no se toca nada."
            fi
            mundo=$(mundo_servidor "$servidor")
            if [[ -d "$carpeta/$mundo" ]]; then
                guardado=$(guardar_mundo "$servidor" "antes-de-restaurar") || exit 1
                emitir "AVISO El mundo que había quedó en Respaldos/$servidor/mundos/$(basename "$guardado")."
            fi
            for m in "$mundo" "${mundo}_nether" "${mundo}_the_end" "$raiz" "${raiz}_nether" "${raiz}_the_end"; do rm -rf -- "${carpeta:?}/$m"; done
            emitir "ETAPA Restaurando el mundo (puede tardar)"
            tar --zstd -xf "$origen" -C "$carpeta" --no-same-owner --no-same-permissions || error "No se pudo descomprimir el respaldo."
            if [[ "$raiz" != "$mundo" ]]; then
                python3 -I "$API" propiedades-cambiar "$carpeta/server.properties" "$CONF_VERSION" "level-name=$raiz" &>/dev/null || true
            fi
            emitir "LISTO Mundo de $NV restaurado desde $archivo." ;;
        jar)
            origen="$base/viejo/$archivo"
            [[ "$archivo" == *.jar && -f "$origen" ]] || error "No existe ese jar." 2
            [[ "$CONF_TIPO" != forge ]] || error "Forge arranca con su run.sh: para cambiarlo, usá «Cambiar versión»."
            minuscula="${archivo,,}"
            case "$CONF_TIPO" in
                paper)   [[ "$minuscula" == paper* ]] ;;
                fabric)  [[ "$minuscula" == fabric-server* ]] ;;
                vanilla) [[ "$minuscula" == server*.jar || "$minuscula" == minecraft_server* ]] ;;
            esac || error "$archivo no parece de $(nombre_tipo "$CONF_TIPO"): no se usa."
            [[ -f "$carpeta/$archivo" ]] && error "Ya hay un $archivo en el servidor."
            [[ -n "$CONF_JAR" && -f "$carpeta/$CONF_JAR" ]] && a_respaldos "$servidor" viejo "$carpeta/$CONF_JAR"
            mv -- "$origen" "$carpeta/$archivo" || error "No se pudo restaurar el jar."
            cambiar_conf "$servidor" JAR "$archivo"
            emitir "LISTO $NV arranca otra vez con $archivo (el que tenía quedó en Respaldos)." ;;
        plugin|mod)
            sub=$( [[ "$tipo" == plugin ]] && echo plugins || echo mods )
            origen="$base/$sub/$archivo"
            [[ "$archivo" == *.jar && -f "$origen" ]] || error "No existe ese respaldo." 2
            [[ "$(carpeta_complementos "$CONF_TIPO")" == "$sub" ]] || error "$NV es $(nombre_tipo "$CONF_TIPO"): no usa $sub."
            complemento_sirve "$origen" "$CONF_TIPO" || error "$archivo no es $(que_complemento "$CONF_TIPO")."
            [[ -f "$carpeta/$sub/$archivo" ]] && error "Ya está $archivo en $sub/."
            mkdir -p "$carpeta/$sub" && mv -- "$origen" "$carpeta/$sub/$archivo" || error "No se pudo restaurar."
            emitir "LISTO $archivo vuelve a $NV (si quedó otra versión del mismo en $sub/, sacala desde la pestaña o la carpeta)." ;;
        *) error "Tipo de respaldo desconocido." 2 ;;
    esac
    ;;

# Cambia el software o la versión de un servidor (también sirve para actualizar el cargador de Fabric o Forge):
# guarda el mundo antes, pasa los plugins/mods a la versión nueva (o a Respaldos si no tienen) y, si la carpeta
# lleva la versión en el nombre («26.1.2 SMP-1»), la mueve a la de la versión nueva («26.3/26.3 SMP-1»).
# La configuración llega por stdin: TIPO=…, VERSION=…, LOADER=… (opcional)
cambiar)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" || error "$NV está encendido: detenelo antes de cambiar la versión."
    declare -A C=()
    while IFS= read -r linea || [[ -n "$linea" ]]; do
        [[ "$linea" =~ ^(TIPO|VERSION|LOADER)=([0-9A-Za-z.+-]*)$ ]] && C[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
    done
    tipo="${C[TIPO]:-}"; version="${C[VERSION]:-}"; loader="${C[LOADER]:-}"
    [[ "$tipo" =~ ^(vanilla|paper|fabric|forge)$ ]] || error "El software tiene que ser Vanilla, Paper, Fabric o Forge." 2
    [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || error "Versión de Minecraft rara." 2
    [[ "$tipo" == fabric || "$tipo" == forge || -z "$loader" ]] || error "Solo Fabric y Forge tienen versión de cargador." 2
    leer_conf "$servidor"
    carpeta=$(carpeta_servidor "$servidor")
    mundo=$(mundo_servidor "$servidor")
    # Un mundo no se puede abrir en una versión más vieja que la suya
    if [[ -f "$carpeta/$mundo/level.dat" ]]; then
        version_mundo=$(python3 -I "$API" mundo-version "$carpeta/$mundo/level.dat" 2>/dev/null | sed -n 's/^MUNDO //p')
        if [[ "$version_mundo" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ && "$version_mundo" != "$version" \
              && "$(printf '%s\n%s\n' "$version_mundo" "$version" | sort -V | tail -n1)" == "$version_mundo" ]]; then
            error "El mundo es de Minecraft $version_mundo: no se puede abrir en $version (más vieja) sin romperlo."
        fi
    fi
    exec 3>&1
    preparar_version "$version"
    # Mundo a salvo antes de tocar nada
    if [[ -d "$carpeta/$mundo" ]]; then
        guardado=$(guardar_mundo "$servidor" "antes-de-$tipo-$version") || exit 1
        emitir "AVISO El mundo quedó guardado en Respaldos/$servidor/mundos/$(basename "$guardado")."
    fi
    fecha=$(date +%Y%m%d-%H%M%S)
    # Lo del software anterior va a Respaldos/<servidor>/viejo/
    if [[ -n "$CONF_JAR" && -f "$carpeta/$CONF_JAR" && "$CONF_JAR" != server.jar ]]; then a_respaldos "$servidor" viejo "$carpeta/$CONF_JAR"; fi
    rm -f "$carpeta/server.jar"     # el oficial se vuelve a bajar (comprobado) si hace falta
    if [[ "$CONF_TIPO" == forge ]]; then
        mkdir -p "$RESPALDOS_MC_DIR/$servidor/viejo/forge-$fecha"
        for f in "$carpeta"/run.sh "$carpeta"/run.bat "$carpeta"/forge-*.jar; do
            [[ -f "$f" ]] && mv -- "$f" "$RESPALDOS_MC_DIR/$servidor/viejo/forge-$fecha/"
        done
        [[ "$tipo" == forge && -f "$carpeta/user_jvm_args.txt" ]] || { [[ -f "$carpeta/user_jvm_args.txt" ]] && mv -- "$carpeta/user_jvm_args.txt" "$RESPALDOS_MC_DIR/$servidor/viejo/forge-$fecha/"; }
    fi
    [[ "$CONF_TIPO" == fabric && "$tipo" != fabric ]] && rm -rf "$carpeta/.fabric"
    # Paper guarda el nether y el end aparte: los demás los quieren adentro del mundo (al revés, Paper los mueve solo)
    if [[ "$CONF_TIPO" == paper && "$tipo" != paper ]]; then
        mundo_desde_paper "$carpeta/$mundo"
        for par in "_nether:DIM-1" "_the_end:DIM1"; do
            aparte="$carpeta/$mundo${par%%:*}/${par#*:}"
            [[ -d "$aparte" && ! -e "$carpeta/$mundo/${par#*:}" ]] && mv -- "$aparte" "$carpeta/$mundo/${par#*:}"
            rm -rf -- "${carpeta:?}/$mundo${par%%:*}"
        done
    fi
    instalar_software "$tipo" "$version" "$loader" "$CONF_RAM" "$carpeta"
    # Plugins y mods: a la versión del mismo proyecto que sirve para el software y la versión nuevos
    viejo_sub=$(carpeta_complementos "$CONF_TIPO"); nuevo_sub=$(carpeta_complementos "$tipo")
    shopt -s nullglob
    jars=(); [[ -n "$viejo_sub" ]] && jars=("$carpeta/$viejo_sub"/*.jar)
    if (( ${#jars[@]} )); then
        if [[ -z "$nuevo_sub" ]]; then
            for j in "${jars[@]}"; do a_respaldos "$servidor" "$viejo_sub" "$j"; done
            emitir "AVISO $(nombre_tipo "$tipo") no usa plugins ni mods: los ${#jars[@]} que había quedaron en Respaldos/$servidor/$viejo_sub."
        else
            emitir "ETAPA Buscando en Modrinth las versiones para $(nombre_tipo "$tipo") $version"
            mkdir -p "$carpeta/$nuevo_sub"
            pasados=0; guardados=0
            while IFS=$'\t' read -r archivo nombre actual nueva estado url suma nuevo_archivo; do
                archivo="${archivo#PLUGIN }"; viejo="$carpeta/$viejo_sub/$archivo"
                if [[ "$estado" == NUEVA ]] && url_valida "$url" && [[ "$nuevo_archivo" =~ ^[^/]+\.jar$ ]]; then
                    [[ "$suma" == sha256:* ]] || suma="sha512:$suma"
                    emitir "ETAPA Bajando $nombre $nueva"
                    if descargar_jar "$url" "$suma" "$carpeta/$nuevo_sub/.nuevo-$nuevo_archivo"; then
                        a_respaldos "$servidor" "$viejo_sub" "$viejo"
                        mv -f "$carpeta/$nuevo_sub/.nuevo-$nuevo_archivo" "$carpeta/$nuevo_sub/$nuevo_archivo"
                        pasados=$((pasados + 1)); continue
                    fi
                    rm -f "$carpeta/$nuevo_sub/.nuevo-$nuevo_archivo"
                fi
                if [[ "$estado" == AL_DIA ]] || [[ "$estado" == DESCONOCIDO && "$viejo_sub" == "$nuevo_sub" && "$CONF_TIPO" == "$tipo" ]]; then
                    [[ "$viejo_sub" == "$nuevo_sub" ]] || mv -- "$viejo" "$carpeta/$nuevo_sub/"
                    [[ "$estado" == DESCONOCIDO ]] && emitir "AVISO $archivo no está en Modrinth: lo dejo, pero fijate si sirve para $version."
                    continue
                fi
                a_respaldos "$servidor" "$viejo_sub" "$viejo"; guardados=$((guardados + 1))
                emitir "AVISO $nombre no tiene versión para $(nombre_tipo "$tipo") $version: quedó en Respaldos/$servidor/$viejo_sub."
            done < <(python3 -I "$API" plugins "$version" "--tipo=$tipo" "${jars[@]}" 2>/dev/null | grep '^PLUGIN ')
            # Dependencias que ahora falten (p. ej. Fabric API, al pasar de Paper a Fabric)
            while IFS=$'\t' read -r slug titulo ver url sha512 archivo motivo; do
                url_valida "$url" && [[ "$archivo" =~ ^[^/]+\.jar$ ]] || continue
                [[ -f "$carpeta/$nuevo_sub/$archivo" ]] && continue
                descargar_jar "$url" "sha512:$sha512" "$carpeta/$nuevo_sub/$archivo" && emitir "AVISO También va $titulo (la necesitan los demás)."
            done < <(python3 -I "$API" dependencias "$tipo" "$version" "$carpeta/$nuevo_sub"/*.jar 2>/dev/null | sed -n 's/^COMPLEMENTO //p')
            [[ "$viejo_sub" == "$nuevo_sub" ]] || rmdir "$carpeta/$viejo_sub" 2>/dev/null
            emitir "AVISO $pasados $( [[ $nuevo_sub == mods ]] && echo "mod(s)" || echo "plugin(s)") pasados a $version$( (( guardados )) && echo ", $guardados guardados en Respaldos")."
        fi
    fi
    cambiar_conf "$servidor" TIPO "$tipo"; cambiar_conf "$servidor" VERSION "$version"
    cambiar_conf "$servidor" JAR "$jar"; cambiar_conf "$servidor" JAVA "$java_n"; cambiar_conf "$servidor" LOADER "$loader"
    # La carpeta lleva la versión en el nombre: se mueve a la de la versión nueva (con sus respaldos)
    nuevo="$servidor"; nombre_carpeta="${servidor##*/}"
    if [[ "$servidor" == */*/* && "$nombre_carpeta" == "$CONF_VERSION "* && "$CONF_VERSION" != "$version" ]]; then
        candidato="${servidor%%/*}/$(cut -d. -f1,2 <<< "$version")/$version ${nombre_carpeta#"$CONF_VERSION "}"
        if [[ -e "$SERVIDORES_DIR/$candidato" ]]; then
            emitir "AVISO Ya existe Servidores/$candidato: la carpeta queda donde estaba."
        else
            mkdir -p "$(dirname "$SERVIDORES_DIR/$candidato")" && mv -T -- "$carpeta" "$SERVIDORES_DIR/$candidato" && nuevo="$candidato"
            if [[ "$nuevo" != "$servidor" && -d "$RESPALDOS_MC_DIR/$servidor" && ! -e "$RESPALDOS_MC_DIR/$nuevo" ]]; then
                mkdir -p "$(dirname "$RESPALDOS_MC_DIR/$nuevo")" && mv -T -- "$RESPALDOS_MC_DIR/$servidor" "$RESPALDOS_MC_DIR/$nuevo"
            fi
            rmdir "$(dirname "$SERVIDORES_DIR/$servidor")" "$(dirname "$RESPALDOS_MC_DIR/$servidor")" 2>/dev/null
            cambiar_conf "$nuevo" NOMBRE "${nuevo##*/}"
        fi
    fi
    emitir "CREADO $nuevo"
    emitir "LISTO $(nombre_visible "$nuevo"): ahora es $(nombre_tipo "$tipo") $version${loader:+ (cargador $loader)}, con Java $java_n."
    ;;

pack-jugadores)
    servidor="${2:-}"; servidor_valido "$servidor"
    destino="${3:-}"
    [[ "$destino" == /*.mrpack && -d "$(dirname "$destino")" && -w "$(dirname "$destino")" ]] || error "Elegí dónde guardar el pack (.mrpack)." 2
    leer_conf "$servidor"
    admite "$CONF_TIPO" mods || error "$NV es $(nombre_tipo "$CONF_TIPO"): los jugadores no necesitan mods para entrar."
    carpeta=$(carpeta_servidor "$servidor")
    loader="$CONF_LOADER"
    if [[ -z "$loader" && "$CONF_TIPO" == fabric ]]; then
        loader=$(sed -n 's/^fabric-server-mc\.[^-]*-loader\.\(.*\)-launcher\..*\.jar$/\1/p' <<< "$CONF_JAR")
    elif [[ -z "$loader" ]]; then
        loader=$(grep -o "net/minecraftforge/forge/$CONF_VERSION-[^/]*" "$carpeta/run.sh" 2>/dev/null | head -n1 | sed "s|.*/$CONF_VERSION-||")
    fi
    [[ "$loader" =~ ^[0-9A-Za-z.+-]{1,40}$ ]] || error "No sé qué versión de $(nombre_tipo "$CONF_TIPO") tiene $NV (anotala como LOADER= en servidor.conf)."
    emitir "ETAPA Armando el pack (consultando Modrinth)"
    salida=$(python3 -I "$API" pack-jugadores "$carpeta" "$CONF_TIPO" "$CONF_VERSION" "$loader" "$NV" "$destino" 2>&1) \
        || error "$(sed -n 's/^ERROR //p' <<< "$salida" | head -n1)"
    grep '^AVISO ' <<< "$salida"
    IFS=$'\t' read -r con_descarga adentro solo_servidor <<< "$(sed -n 's/^PACK //p' <<< "$salida")"
    (( ${adentro:-0} )) && emitir "AVISO $adentro mod(s) no están en Modrinth: van adentro del pack."
    (( ${solo_servidor:-0} )) && emitir "AVISO $solo_servidor mod(s) son solo del servidor: no van en el pack."
    emitir "LISTO Pack para jugadores de $NV: $destino ($((con_descarga + adentro)) mods). Se abre con Prism Launcher o la app de Modrinth."
    ;;

extra)
    servidor="${2:-}"; servidor_valido "$servidor"
    que="${3:-}"
    leer_conf "$servidor"
    carpeta=$(carpeta_servidor "$servidor")
    sub=$(carpeta_complementos "$CONF_TIPO")
    [[ -n "$sub" ]] || error "$NV es Vanilla: los extras son plugins o mods (pasalo a Paper o Fabric con «Cambiar versión»)."
    case "$que" in
        geyser)
            [[ "$CONF_TIPO" != forge ]] || error "Geyser no tiene versión para Forge (sí para Paper y Fabric)."
            textos=(geyser); [[ "$CONF_TIPO" == fabric ]] && textos+=(floodgate) ;;
        bluemap) textos=(bluemap) ;;
        *) error "Extra desconocido (geyser o bluemap)." 2 ;;
    esac
    emitir "ETAPA Buscando $que en Modrinth para $(nombre_tipo "$CONF_TIPO") $CONF_VERSION"
    salida=$(python3 -I "$API" complementos "$CONF_TIPO" "$CONF_VERSION" "${textos[@]}" 2>/dev/null)
    # Floodgate para Paper no está en Modrinth: lo publica GeyserMC
    [[ "$que" == geyser && "$CONF_TIPO" == paper ]] && salida+=$'\n'$(python3 -I "$API" floodgate-paper 2>/dev/null)
    if grep -q '^NO_SIRVE ' <<< "$salida"; then
        error "No hay versión para $(nombre_tipo "$CONF_TIPO") $CONF_VERSION: $(sed -n 's/^NO_SIRVE //p' <<< "$salida" | cut -f1 | paste -sd, | sed 's/,/, /g')."
    fi
    while IFS=$'\t' read -r slug titulo ver url suma archivo motivo; do
        url_valida "$url" && [[ "$archivo" =~ ^[^/]+\.jar$ ]] || error "Respuesta rara de Modrinth/GeyserMC."
        [[ "$suma" == sha256:* ]] || suma="sha512:$suma"
        [[ -f "$carpeta/$sub/$archivo" ]] && continue
        emitir "ETAPA Bajando $titulo $ver"
        descargar_jar "$url" "$suma" "$carpeta/$sub/$archivo" || error "No se pudo bajar $titulo (o la suma no coincide)."
        emitir "AVISO $titulo $ver instalado."
    done < <(sed -n 's/^COMPLEMENTO //p' <<< "$salida")
    if [[ "$que" == geyser ]]; then
        emitir "LISTO Geyser y Floodgate en $NV: los de Bedrock (celular, consola) entran por el puerto 19132 UDP con su cuenta de Xbox, sin tener Java."
    else
        touch "$carpeta/.bluemap-aceptado"
        emitir "LISTO BlueMap en $NV: al iniciarlo arma el mapa (la primera vez tarda). Se ve en http://$(cat /etc/hostname 2>/dev/null || echo localhost):8100"
    fi
    ;;

# Apagado automático (desde la 4.15.0): lo arranca «arrancar» en segundo plano, uno por servidor. Cada minuto
# pregunta quién está conectado; si pasan APAGAR_VACIO minutos sin nadie, lo detiene, y con APAGAR_PC=si
# le pide al servidor de la casa que apague la PC (apagar-pc.sh decide: solo si la prendió el WOL en este
# arranque y nadie la está usando). Registro: ~/.local/state/Arch-Linux-Manager/minecraft-automatico.log
vigilar)
    servidor="${2:-}"; servidor_valido "$servidor"
    estado_dir=$(dir_estado)
    ses=$(sesion "$servidor"); marca="$estado_dir/vacio-$ses"
    registro_auto="${XDG_STATE_HOME:-$HOME/.local/state}/Arch-Linux-Manager/minecraft-automatico.log"
    mkdir -p "$(dirname "$registro_auto")"
    anotar_auto() { printf '%s %s %s\n' "$(date '+%F %T')" "$NV" "$*" >> "$registro_auto"; }
    # Uno solo por servidor: el último que arrancó reemplaza al anterior (que se va en su próxima vuelta)
    pidf="$estado_dir/vigilar-$ses.pid"
    exec 9> "$estado_dir/vigilar-$ses.lock"
    flock 9
    viejo=$(cat "$pidf" 2>/dev/null)
    [[ "$viejo" =~ ^[0-9]+$ && "$viejo" != "$$" ]] && kill "$viejo" 2>/dev/null
    echo "$$" > "$pidf"
    flock -u 9
    sigo() { [[ "$(cat "$pidf" 2>/dev/null)" == "$$" && -f "$(carpeta_servidor "$servidor")/servidor.conf" ]]; }
    intervalo="${MINECRAFT_VIGILAR_INTERVALO:-60}"
    # Espera a que java arranque (hasta 5 minutos)
    for (( i = 0; i < 300 / intervalo + 1; i++ )); do apagado "$servidor" || break; sigo || exit 0; sleep "$intervalo"; done
    vacio=0
    while ! apagado "$servidor"; do
        sleep "$intervalo"
        sigo || exit 0
        apagado "$servidor" && break
        leer_conf "$servidor"
        # BlueMap escribe su core.conf en el primer arranque: si se aceptó al instalarlo, se acepta y se recarga
        if [[ -f "$(carpeta_servidor "$servidor")/.bluemap-aceptado" ]]; then
            for f in "$(carpeta_servidor "$servidor")"/{plugins/BlueMap,config/bluemap}/core.conf; do
                if [[ -f "$f" ]] && grep -q '^accept-download: *false' "$f"; then
                    sed -i 's/^accept-download: *false/accept-download: true/' "$f"
                    compartida "$servidor" && enviar "$servidor" "bluemap reload"
                fi
            done
        fi
        (( CONF_APAGAR_VACIO > 0 )) || { vacio=0; rm -f "$marca"; continue; }
        if [[ -n "${MINECRAFT_JUGADORES_FALSO:-}" ]]; then
            n=$(cat "$MINECRAFT_JUGADORES_FALSO" 2>/dev/null)
        else
            puerto=$(sed -n 's/^server-port=//p' "$(carpeta_servidor "$servidor")/server.properties" 2>/dev/null | head -n1 | tr -d '\r ')
            [[ "$puerto" =~ ^[0-9]{1,5}$ ]] || puerto=25565
            n=$(python3 -I "$API" ping "$puerto" 2>/dev/null | sed -n 's/^JUGADORES \([0-9]*\).*/\1/p')
        fi
        [[ "$n" =~ ^[0-9]+$ ]] || continue          # todavía arrancando (o no contesta): no cuenta
        if (( n > 0 )); then vacio=0; rm -f "$marca"; continue; fi
        vacio=$((vacio + intervalo))
        limite=$((CONF_APAGAR_VACIO * ${MINECRAFT_VIGILAR_MINUTO:-60}))
        echo $(( $(date +%s) + limite - vacio )) > "$marca"
        (( vacio >= limite )) || continue
        anotar_auto "sin jugadores hace $CONF_APAGAR_VACIO min: se apaga"
        detener "$servidor" 0 apaga > /dev/null
        rm -f "$marca"
        if [[ "$CONF_APAGAR_PC" == si ]]; then
            otro=""
            while IFS= read -r s; do apagado "$s" || otro="$s"; done < <(listar_servidores)
            if [[ -n "$otro" ]]; then
                anotar_auto "la PC queda prendida: sigue encendido $(nombre_visible "$otro")"
            elif [[ -n "${MINECRAFT_APAGAR_PC_FALSO:-}" ]]; then
                echo "apagar pc" >> "$MINECRAFT_APAGAR_PC_FALSO"
            else
                resultado=$(bash "$AQUI/Acciones-servidor.sh" pc-apagar 2>&1 | tail -n 3 | tr '\n' ' ')
                anotar_auto "pedido de apagar la PC: $resultado"
            fi
        fi
        break
    done
    rm -f "$marca"
    [[ "$(cat "$pidf" 2>/dev/null)" == "$$" ]] && rm -f "$pidf"
    exit 0
    ;;

abrir-carpeta)
    case "${2:-}" in
        servidores) destino="$SERVIDORES_DIR" ;;
        respaldos)  destino="$RESPALDOS_MC_DIR"; mkdir -p "$destino" ;;
        *) error "Carpeta desconocida (servidores o respaldos)." 2 ;;
    esac
    setsid -f xdg-open "$destino" &>/dev/null
    emitir "LISTO Abriendo la carpeta de ${2}."
    ;;

carpeta)
    servidor="${2:-}"; servidor_valido "$servidor"
    setsid -f xdg-open "$(carpeta_servidor "$servidor")" &>/dev/null
    emitir "LISTO Abriendo la carpeta de $NV."
    ;;

instancias)
    for dir in "$PRISM_DIR"/*/; do
        [[ -d "$dir" ]] && emitir "INSTANCIA $(basename "$dir")"
    done
    ;;

prism)
    instancia="${2:-}"
    [[ -n "$instancia" && "$instancia" != */* && -d "$PRISM_DIR/$instancia" ]] || error "No existe la instancia «$instancia»." 2
    if [[ -n "${SIN_SERVIDOR[$instancia]:-}" ]]; then
        setsid -f prismlauncher -l "$instancia" &>/dev/null
    else
        setsid -f prismlauncher -l "$instancia" -s "$SERVIDOR_MINECRAFT" &>/dev/null
    fi
    emitir "LISTO Abriendo $instancia."
    ;;

*)
    error "Uso: Minecraft.sh servidores|iniciar|detener|reiniciar|terminal|comando|registro|jugadores|paper|plugins|plugins-actualizar|plugin|reiniciar-mundo|ram|carpeta|opciones|buscar-modrinth|modpack-versiones|crear|instancias|prism ..." 2
    ;;
esac
