#!/bin/bash
# Lógica sin interfaz de Minecraft (la usa la página «Panel de Minecraft»). Los servidores están en
# Minecraft Servers/Servidores/<servidor>/ con su servidor.conf (ver Minecraft-comun.sh).
#
# Uso: Minecraft.sh servidores                       todos los servidores y su estado
#      Minecraft.sh iniciar SERVIDOR                 lo abre en una terminal
#      Minecraft.sh detener SERVIDOR                 lo apaga guardando los mundos
#      Minecraft.sh reiniciar SERVIDOR               detener + iniciar
#      Minecraft.sh paper SERVIDOR...                lo pasa a la última compilación estable de Paper de su versión
#      Minecraft.sh plugins SERVIDOR                 sus plugins (reconocidos en Modrinth/GeyserMC) y si hay versión nueva
#      Minecraft.sh plugins-actualizar SERVIDOR [ARCHIVO...]   actualiza los que tienen versión nueva (todos o esos)
#      Minecraft.sh plugin TEXTO SERVIDOR...         instala un plugin de Modrinth (nombre, slug o URL) o de otra URL https
#      Minecraft.sh reiniciar-mundo SERVIDOR         guarda el mundo en Respaldos/ y lo borra (Paper hace uno nuevo)
#      Minecraft.sh ram SERVIDOR 8G                  cambia la memoria máxima
#      Minecraft.sh carpeta SERVIDOR                 abre la carpeta del servidor
#      Minecraft.sh consola SERVIDOR                 (interno) lo que corre la terminal de iniciar
#      Minecraft.sh instancias                       instancias de Prism Launcher
#      Minecraft.sh prism "INSTANCIA"                abre la instancia y entra al servidor de casa
#
# Eventos (stdout, uno por línea; los campos de SERVIDOR y PLUGIN van separados por tabuladores):
#   SERVIDOR ENCENDIDO|APAGADO<tab>nombre<tab>tipo<tab>versión<tab>tamaño del mundo<tab>último uso<tab>RAM<tab>jar
#   PLUGIN archivo<tab>nombre<tab>versión<tab>versión nueva<tab>AL_DIA|NUEVA|SIN_VERSION|DESCONOCIDO<tab>…
#   INSTANCIA <instancia>
#   ETAPA <texto>        ESPERA <segundos>   (detener: cuánto lleva guardando)
#   AVISO <texto>        LISTO <texto>        ERROR <texto>
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
servidor_valido() {
    [[ -n "$1" ]] && listar_servidores | grep -qxF -- "$1" || error "No existe el servidor «$1»." 2
}
apagado() {
    [[ -z "$(pid_servidor "$(carpeta_servidor "$1")")" ]]
}
# Abre la consola del servidor en una terminal que sigue abierta aunque se cierre el Manager
abrir_terminal() {
    setsid -f konsole --workdir "$(carpeta_servidor "$1")" -p tabtitle="$1" -e "$AQUI/Minecraft.sh" consola "$1" &>/dev/null
}
# Detiene el servidor guardando los mundos: Paper los guarda al recibir SIGTERM (como con «stop»)
detener() {
    local pid s
    pid=$(pid_servidor "$(carpeta_servidor "$1")")
    [[ -n "$pid" ]] || return 0
    emitir "ETAPA Deteniendo $1 (guardando mundos)"
    kill -TERM "$pid"
    for (( s = 0; s < 120; s++ )); do
        kill -0 "$pid" 2>/dev/null || return 0
        emitir "ESPERA $s"
        sleep 1
    done
    error "$1 no se detuvo después de 2 minutos."
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
    echo "== $servidor (${CONF_TIPO^} $CONF_VERSION, hasta $CONF_RAM de RAM). Para apagarlo: escribí «stop»."
    if [[ "$CONF_TIPO" == forge ]]; then
        bash ./run.sh nogui
    else
        [[ -f "$CONF_JAR" ]] || { echo "No está $CONF_JAR (revisá JAR en servidor.conf)."; read -r -p "Enter para cerrar…"; exit 1; }
        java -Xms1G -Xmx"$CONF_RAM" -jar "$CONF_JAR" nogui
    fi
    echo; echo "Servidor cerrado."
    read -r -t 30 -p "Enter para cerrar (se cierra solo en 30 s)…" || true
    ;;

iniciar)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" || { emitir "LISTO $servidor ya está encendido."; exit 0; }
    # Todos usan el puerto 25565: si hay otro prendido, este no podría arrancar
    while IFS= read -r otro; do
        [[ "$otro" != "$servidor" ]] && ! apagado "$otro" && error "Ya está encendido «$otro» (usan el mismo puerto). Detenelo primero."
    done < <(listar_servidores)
    abrir_terminal "$servidor"
    emitir "LISTO $servidor iniciado en una terminal."
    ;;

detener)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" && { emitir "LISTO $servidor ya estaba apagado."; exit 0; }
    detener "$servidor"
    emitir "LISTO $servidor detenido (mundos guardados)."
    ;;

reiniciar)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" && error "$servidor no está encendido."
    detener "$servidor"
    emitir "ETAPA Abriendo $servidor"
    abrir_terminal "$servidor"
    emitir "LISTO $servidor reiniciado."
    ;;

paper)
    shift
    (( $# )) || error "Elegí al menos un servidor." 2
    actualizados=0
    for servidor in "$@"; do
        servidor_valido "$servidor"
        leer_conf "$servidor"
        [[ "$CONF_TIPO" == paper ]] || { emitir "AVISO $servidor no es Paper: no se toca."; continue; }
        apagado "$servidor" || { emitir "AVISO $servidor está encendido: no se toca."; continue; }
        emitir "ETAPA Buscando la última compilación de Paper $CONF_VERSION"
        linea=$(python3 -I "$API" paper "$CONF_VERSION" 2>/dev/null | grep '^PAPER ' | head -n1)
        [[ -n "$linea" ]] || { emitir "AVISO No hay compilación estable de Paper $CONF_VERSION (o no hubo conexión)."; continue; }
        read -r _ build nombre sha256 url <<< "$linea"
        [[ "$nombre" =~ ^[A-Za-z0-9._\-]+\.jar$ && "$url" == https://* ]] || { emitir "AVISO Respuesta rara de PaperMC."; continue; }
        if [[ "$CONF_JAR" == "$nombre" ]]; then
            emitir "AVISO $servidor ya tiene Paper $CONF_VERSION compilación $build."
            continue
        fi
        carpeta=$(carpeta_servidor "$servidor")
        emitir "ETAPA Descargando Paper $CONF_VERSION compilación $build para $servidor"
        descargar_jar "$url" "sha256:$sha256" "$carpeta/$nombre" || { emitir "AVISO La descarga de Paper falló (o la suma no coincide)."; continue; }
        viejo="$CONF_JAR"
        cambiar_conf "$servidor" JAR "$nombre"
        [[ -n "$viejo" && -f "$carpeta/$viejo" && "$viejo" != "$nombre" ]] && a_respaldos "$servidor" viejo "$carpeta/$viejo"
        emitir "AVISO $servidor: ${viejo:-?} → $nombre"
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
    (( ${#jars[@]} )) || { emitir "LISTO $servidor no tiene plugins."; exit 0; }
    emitir "ETAPA Consultando Modrinth"
    python3 -I "$API" plugins "$CONF_VERSION" "${jars[@]}" 2>/dev/null | grep '^PLUGIN '
    emitir "LISTO ${#jars[@]} plugin(s) en $servidor."
    ;;

plugins-actualizar)
    servidor="${2:-}"; servidor_valido "$servidor"; shift 2
    apagado "$servidor" || error "$servidor está encendido: detenelo antes de cambiar plugins."
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
    (( ${#jars[@]} )) || error "$servidor no tiene plugins."
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
    emitir "LISTO $actualizados plugin(s) actualizado(s) en $servidor (los anteriores quedan en Respaldos/$servidor/plugins)."
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
            emitir "ETAPA Descargando $nombre para $servidor"
            descargar_jar "$texto" - "$plugins/$nombre" || { emitir "AVISO $servidor: la descarga falló o no es un .jar."; continue; }
        else
            emitir "ETAPA Buscando «$texto» en Modrinth para $CONF_VERSION"
            linea=$(python3 -I "$API" buscar "$CONF_VERSION" "$texto" 2>/dev/null | grep '^ENCONTRADO ' | head -n1)
            [[ -n "$linea" ]] || { emitir "AVISO $servidor: «$texto» no está en Modrinth para $CONF_VERSION."; continue; }
            IFS=$'\t' read -r slug titulo version url sha512 nombre <<< "${linea#ENCONTRADO }"
            [[ "$url" == https://* && "$nombre" =~ ^[^/]+\.jar$ ]] || { emitir "AVISO Respuesta rara de Modrinth."; continue; }
            emitir "ETAPA Descargando $titulo $version para $servidor"
            descargar_jar "$url" "sha512:$sha512" "$plugins/$nombre" || { emitir "AVISO $servidor: la descarga falló."; continue; }
            emitir "AVISO $servidor: $titulo $version instalado."
        fi
        instalados=$((instalados + 1))
    done
    emitir "LISTO Instalado en $instalados servidor(es). Se activa al iniciarlos (o reiniciarlos)."
    ;;

reiniciar-mundo)
    servidor="${2:-}"; servidor_valido "$servidor"
    apagado "$servidor" || error "$servidor está encendido: detenelo primero."
    carpeta=$(carpeta_servidor "$servidor")
    mundo=$(mundo_servidor "$servidor")
    partes=()
    for m in "$mundo" "${mundo}_nether" "${mundo}_the_end"; do [[ -d "$carpeta/$m" ]] && partes+=("$m"); done
    (( ${#partes[@]} )) || { emitir "LISTO $servidor no tenía mundo: se crea uno nuevo al iniciarlo."; exit 0; }
    destino="$RESPALDOS_MC_DIR/$servidor/mundos"
    mkdir -p "$destino"
    archivo="$destino/$mundo-$(date +%Y-%m-%d_%H-%M-%S).tar.zst"
    emitir "ETAPA Guardando el mundo en Respaldos (puede tardar)"
    tar --zstd -cf "$archivo" -C "$carpeta" "${partes[@]}" || { rm -f "$archivo"; error "No se pudo guardar el mundo: no se borró nada."; }
    for m in "${partes[@]}"; do rm -rf -- "${carpeta:?}/$m"; done
    emitir "LISTO Mundo de $servidor reiniciado. El anterior quedó en Respaldos/$servidor/mundos/$(basename "$archivo")."
    ;;

ram)
    servidor="${2:-}"; servidor_valido "$servidor"
    ram="${3:-}"
    [[ "$ram" =~ ^[0-9]+[GM]$ ]] || error "La memoria tiene que ser como 8G o 4096M." 2
    leer_conf "$servidor"
    [[ "$CONF_TIPO" == forge ]] && emitir "AVISO En Forge la memoria se cambia en user_jvm_args.txt; igual queda anotada."
    cambiar_conf "$servidor" RAM "$ram"
    emitir "LISTO $servidor va a usar hasta $ram de RAM (al iniciarlo de nuevo)."
    ;;

carpeta)
    servidor="${2:-}"; servidor_valido "$servidor"
    setsid -f xdg-open "$(carpeta_servidor "$servidor")" &>/dev/null
    emitir "LISTO Abriendo la carpeta de $servidor."
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
    error "Uso: Minecraft.sh servidores|iniciar|detener|reiniciar|paper|plugins|plugins-actualizar|plugin|reiniciar-mundo|ram|carpeta|instancias|prism ..." 2
    ;;
esac
