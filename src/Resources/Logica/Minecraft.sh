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
#      Minecraft.sh opciones                         (asistente) versiones, software de cada una, grupos y Javas instalados
#      Minecraft.sh buscar-modrinth complemento|modpack TIPO VERSION TEXTO   (asistente) proyectos de Modrinth que sirven
#      Minecraft.sh modpack-versiones SLUG           (asistente) versiones de un modpack que se pueden usar
#      Minecraft.sh crear < configuración           arma un servidor nuevo (ver «crear» más abajo); aparece solo en la lista
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
#   CREADO <servidor>    (crear: la ruta del servidor nuevo)
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

case "${1:-}" in
servidores)
    while IFS= read -r servidor; do
        leer_conf "$servidor"
        carpeta=$(carpeta_servidor "$servidor")
        apagado "$servidor" && estado=APAGADO || estado=ENCENDIDO
        tam=$(du -sh "$carpeta/$(mundo_servidor "$servidor")" 2>/dev/null | cut -f1)
        ultimo=$(stat -c %Y "$carpeta/logs/latest.log" 2>/dev/null)
        [[ -n "$ultimo" ]] && ultimo=$(date -d "@$ultimo" +%Y-%m-%d)
        printf 'SERVIDOR %s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$estado" "$servidor" "$CONF_TIPO" "$CONF_VERSION" \
            "${tam:--}" "${ultimo:--}" "$CONF_RAM" "${CONF_JAR:-run.sh}"
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
    destino="$RESPALDOS_MC_DIR/$servidor/mundos"
    mkdir -p "$destino"
    archivo="$destino/$mundo-$(date +%Y-%m-%d_%H-%M-%S).tar.zst"
    emitir "ETAPA Guardando el mundo en Respaldos (puede tardar)"
    tar --zstd -cf "$archivo" -C "$carpeta" "${partes[@]}" || { rm -f "$archivo"; error "No se pudo guardar el mundo: no se borró nada."; }
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

    emitir "ETAPA Consultando Mojang ($version)"
    linea=$(api_linea VANILLA vanilla "$version") || exit 1
    read -r _ url_vanilla sha1_vanilla java_pedido <<< "$linea"
    url_valida "$url_vanilla" && [[ "$sha1_vanilla" =~ ^[0-9a-f]{40}$ && "$java_pedido" =~ ^[0-9]{1,2}$ ]] || error "Respuesta rara de Mojang."
    bin_java=$(java_para "$java_pedido") || error "Minecraft $version necesita Java $java_pedido (o más nuevo) y no está instalado: sudo pacman -S jre$java_pedido-openjdk"
    java_n="${bin_java%/bin}"; java_n="${java_n%/jre}"; java_n="${java_n##*/java-}"; java_n="${java_n%-openjdk}"
    (( java_n == java_pedido )) || emitir "AVISO Minecraft $version pide Java $java_pedido; no está, así que uso Java $java_n (si no arranca: sudo pacman -S jre$java_pedido-openjdk)."

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
        rm -f "$pack"
    fi

    jar=""
    case "$tipo" in
        vanilla)
            emitir "ETAPA Bajando el servidor oficial de Minecraft $version"
            descargar_jar "$url_vanilla" "sha1:$sha1_vanilla" "$tmpd/server.jar" || error "No se pudo bajar el servidor de Minecraft (o la suma no coincide)."
            jar=server.jar ;;
        paper)
            emitir "ETAPA Buscando la última compilación de Paper $version"
            linea=$(api_linea PAPER paper "$version") || { emitir "ERROR Paper no tiene una compilación estable para $version."; exit 1; }
            read -r _ build jar sha256 url <<< "$linea"
            [[ "$jar" =~ ^[A-Za-z0-9._\-]+\.jar$ ]] && url_valida "$url" || error "Respuesta rara de PaperMC."
            emitir "ETAPA Bajando Paper $version compilación $build"
            descargar_jar "$url" "sha256:$sha256" "$tmpd/$jar" || error "No se pudo bajar Paper (o la suma no coincide)." ;;
        fabric)
            emitir "ETAPA Buscando Fabric para $version"
            linea=$(api_linea FABRIC fabric "$version" ${loader:+"$loader"}) || exit 1
            read -r _ loader jar url <<< "$linea"
            [[ "$jar" =~ ^[A-Za-z0-9._+\-]+\.jar$ ]] && url_valida "$url" || error "Respuesta rara de Fabric."
            emitir "ETAPA Bajando Fabric $loader"
            descargar_jar "$url" - "$tmpd/$jar" || error "No se pudo bajar Fabric."
            # El lanzador de Fabric usa server.jar: se baja ya (comprobado) para que el primer arranque no lo busque
            emitir "ETAPA Bajando el servidor oficial de Minecraft $version"
            descargar_jar "$url_vanilla" "sha1:$sha1_vanilla" "$tmpd/server.jar" || error "No se pudo bajar el servidor de Minecraft." ;;
        forge)
            emitir "ETAPA Buscando Forge para $version"
            linea=$(api_linea FORGE forge "$version" ${loader:+"$loader"}) || exit 1
            read -r _ loader url sha1 <<< "$linea"
            url_valida "$url" && [[ "$sha1" =~ ^[0-9a-f]{40}$ ]] || error "Respuesta rara de Forge."
            emitir "ETAPA Bajando el instalador de Forge $loader"
            descargar_jar "$url" "sha1:$sha1" "$tmpd/forge-instalador.jar" || error "No se pudo bajar Forge (o la suma no coincide)."
            emitir "ETAPA Instalando Forge $loader (baja sus librerías: puede tardar unos minutos)"
            ( cd "$tmpd" && "$bin_java/java" -jar forge-instalador.jar --installServer ) > "$tmpd/.forge-instalador.log" 2>&1 \
                || error "El instalador de Forge falló: $(tail -n 3 "$tmpd/.forge-instalador.log" | tr '\n' ' ')"
            rm -f "$tmpd"/forge-instalador.jar "$tmpd"/forge-instalador.jar.log "$tmpd"/.forge-instalador.log "$tmpd"/installer.log
            if [[ -f "$tmpd/run.sh" ]]; then
                printf -- '-Xmx%s\n' "$ram" >> "$tmpd/user_jvm_args.txt"
            else
                # Los Forge viejos no tienen run.sh: se arrancan con su jar
                for f in "$tmpd"/forge-*.jar; do
                    [[ -f "$f" && "$f" != *installer* && "$f" != *instalador* ]] && { jar=$(basename "$f"); break; }
                done
                [[ -n "$jar" ]] || error "Forge se instaló pero no encuentro cómo arrancarlo."
            fi ;;
    esac

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
