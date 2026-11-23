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
#      Minecraft.sh plugins SERVIDOR                 sus plugins (reconocidos en Modrinth/GeyserMC) y si hay versión nueva
#      Minecraft.sh plugins-actualizar SERVIDOR [ARCHIVO...]   actualiza los que tienen versión nueva (todos o esos)
#      Minecraft.sh plugin TEXTO SERVIDOR...         instala un plugin de Modrinth (nombre, slug o URL) o de otra URL https
#      Minecraft.sh reiniciar-mundo SERVIDOR         guarda el mundo en Respaldos/ y lo borra (Paper hace uno nuevo)
#      Minecraft.sh ram SERVIDOR 8G                  cambia la memoria máxima
#      Minecraft.sh carpeta SERVIDOR                 abre la carpeta del servidor
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
    echo "== $NV (${CONF_TIPO^} $CONF_VERSION, hasta $CONF_RAM de RAM). Para apagarlo: escribí «stop»."
    [[ -n "${TMUX:-}" ]] && echo "== Cerrar esta ventana no lo apaga: sigue en segundo plano (el Panel de Minecraft lo vuelve a mostrar)."
    if [[ "$CONF_TIPO" == forge ]]; then
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
    carpeta=$(carpeta_servidor "$servidor")
    shopt -s nullglob
    jars=("$carpeta"/plugins/*.jar)
    (( ${#jars[@]} )) || { emitir "LISTO $NV no tiene plugins."; exit 0; }
    emitir "ETAPA Consultando Modrinth"
    python3 -I "$API" plugins "$CONF_VERSION" "${jars[@]}" 2>/dev/null | grep '^PLUGIN '
    emitir "LISTO ${#jars[@]} plugin(s) en $NV."
    ;;

plugins-actualizar)
    servidor="${2:-}"; servidor_valido "$servidor"; shift 2
    apagado "$servidor" || error "$NV está encendido: detenelo antes de cambiar plugins."
    leer_conf "$servidor"
    carpeta=$(carpeta_servidor "$servidor")
    shopt -s nullglob
    if (( $# )); then
        jars=()
        for a in "$@"; do
            [[ "$a" != */* && -f "$carpeta/plugins/$a" ]] || error "No existe el plugin «$a»." 2
            jars+=("$carpeta/plugins/$a")
        done
    else
        jars=("$carpeta"/plugins/*.jar)
    fi
    (( ${#jars[@]} )) || error "$NV no tiene plugins."
    emitir "ETAPA Consultando Modrinth"
    actualizados=0
    while IFS=$'\t' read -r archivo nombre actual nueva estado url suma nuevo_archivo; do
        archivo="${archivo#PLUGIN }"
        [[ "$estado" == NUEVA ]] || continue
        [[ "$url" == https://* && "$nuevo_archivo" =~ ^[^/]+\.jar$ ]] || { emitir "AVISO $nombre: respuesta rara, no se toca."; continue; }
        [[ "$suma" == sha256:* ]] || suma="sha512:$suma"
        emitir "ETAPA Descargando $nombre $nueva"
        tmp=$(mktemp -d)
        if ! descargar_jar "$url" "$suma" "$tmp/$nuevo_archivo"; then
            emitir "AVISO $nombre: la descarga falló (o la suma no coincide), queda el que estaba."
            rm -rf "$tmp"; continue
        fi
        a_respaldos "$servidor" plugins "$carpeta/plugins/$archivo"
        mv -f "$tmp/$nuevo_archivo" "$carpeta/plugins/$nuevo_archivo"
        rm -rf "$tmp"
        emitir "AVISO $nombre: $actual → $nueva"
        actualizados=$((actualizados + 1))
    done < <(python3 -I "$API" plugins "$CONF_VERSION" "${jars[@]}" 2>/dev/null | grep '^PLUGIN ')
    emitir "LISTO $actualizados plugin(s) actualizado(s) en $NV (los anteriores quedan en Respaldos/$servidor/plugins)."
    ;;

plugin)
    texto="${2:-}"; shift 2 2>/dev/null || true
    [[ -n "$texto" ]] || error "Escribí el nombre del plugin (o su URL)." 2
    (( $# )) || error "Elegí al menos un servidor." 2
    instalados=0
    for servidor in "$@"; do
        servidor_valido "$servidor"
        leer_conf "$servidor"
        plugins="$(carpeta_servidor "$servidor")/plugins"
        if [[ "$texto" == https://* && "$texto" != *modrinth.com/* ]]; then
            # Otra página: el archivo tal cual (lo último de la URL, sin lo que va después de «?»)
            nombre=$(basename "${texto%%\?*}"); [[ "$nombre" == *.jar ]] || nombre="$nombre.jar"
            emitir "ETAPA Descargando $nombre para $NV"
            descargar_jar "$texto" - "$plugins/$nombre" || { emitir "AVISO $NV: la descarga falló o no es un .jar."; continue; }
        else
            emitir "ETAPA Buscando «$texto» en Modrinth para $CONF_VERSION"
            linea=$(python3 -I "$API" buscar "$CONF_VERSION" "$texto" 2>/dev/null | grep '^ENCONTRADO ' | head -n1)
            [[ -n "$linea" ]] || { emitir "AVISO $NV: «$texto» no está en Modrinth para $CONF_VERSION."; continue; }
            IFS=$'\t' read -r slug titulo version url sha512 nombre <<< "${linea#ENCONTRADO }"
            [[ "$url" == https://* && "$nombre" =~ ^[^/]+\.jar$ ]] || { emitir "AVISO Respuesta rara de Modrinth."; continue; }
            emitir "ETAPA Descargando $titulo $version para $NV"
            descargar_jar "$url" "sha512:$sha512" "$plugins/$nombre" || { emitir "AVISO $NV: la descarga falló."; continue; }
            emitir "AVISO $NV: $titulo $version instalado."
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
    [[ "$CONF_TIPO" == forge ]] && emitir "AVISO En Forge la memoria se cambia en user_jvm_args.txt; igual queda anotada."
    cambiar_conf "$servidor" RAM "$ram"
    emitir "LISTO $NV va a usar hasta $ram de RAM (al iniciarlo de nuevo)."
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
    error "Uso: Minecraft.sh servidores|iniciar|detener|reiniciar|terminal|comando|registro|jugadores|paper|plugins|plugins-actualizar|plugin|reiniciar-mundo|ram|carpeta|instancias|prism ..." 2
    ;;
esac
