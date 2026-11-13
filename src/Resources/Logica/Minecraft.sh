#!/bin/bash
# Lógica sin interfaz de Minecraft (antes: Iniciar.sh, Reiniciar.sh, paper.sh, Plugins.sh y
# PrismLauncher.sh de Sebastian/Minecraft).
#
# Uso: Minecraft.sh servidores                     servidores Paper y si están encendidos
#      Minecraft.sh versiones                      carpetas «Paper ...»
#      Minecraft.sh instancias                     instancias de Prism Launcher
#      Minecraft.sh iniciar "Paper 26.2/SMP-1"     lo abre en una terminal
#      Minecraft.sh reiniciar "Paper 26.2/SMP-1"   lo detiene guardando los mundos y lo vuelve a abrir
#      Minecraft.sh paper "Paper 26.2" URL         pone el .jar en todos los servidores apagados de esa versión
#      Minecraft.sh plugin URL SERVIDOR...         pone el plugin en la carpeta plugins de cada servidor
#      Minecraft.sh prism "INSTANCIA"              abre la instancia y entra al servidor de casa
#
# Eventos (stdout, uno por línea):
#   SERVIDOR ENCENDIDO|APAGADO <servidor>
#   VERSION <versión>   INSTANCIA <instancia>
#   ETAPA <texto>        ESPERA <segundos>   (reiniciar: cuánto lleva guardando)
#   AVISO <texto>        LISTO <texto>        ERROR <texto>
#
# Código de salida: 0 bien, 1 falló, 2 error de uso.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-1}"; }

source "$(dirname "$(realpath "$0")")/Minecraft-comun.sh"

PRISM_DIR="$HOME/.local/share/PrismLauncher/instances"
SERVIDOR_MINECRAFT="192.168.100.7"
# Instancias de Prism que se abren sin conectarse a ningún servidor
declare -A SIN_SERVIDOR=(
    ["SevTech- Ages"]=1
)

# El servidor tiene que ser uno de los que existen (así no se puede apuntar a otra carpeta)
servidor_valido() {
    listar_servidores_paper | grep -qxF -- "$1" || error "No existe el servidor «$1»." 2
}

case "${1:-}" in
servidores)
    while IFS= read -r servidor; do
        if [[ -n "$(pid_servidor "$(carpeta_servidor "$servidor")")" ]]; then
            emitir "SERVIDOR ENCENDIDO $servidor"
        else
            emitir "SERVIDOR APAGADO $servidor"
        fi
    done < <(listar_servidores_paper)
    ;;

versiones)
    for dir in "$MINECRAFT_DIR"/Paper*/; do
        [[ -d "$dir" ]] && emitir "VERSION $(basename "$dir")"
    done
    ;;

instancias)
    for dir in "$PRISM_DIR"/*/; do
        [[ -d "$dir" ]] && emitir "INSTANCIA $(basename "$dir")"
    done
    ;;

iniciar)
    servidor="${2:-}"; servidor_valido "$servidor"
    carpeta=$(carpeta_servidor "$servidor")
    [[ -z "$(pid_servidor "$carpeta")" ]] || { emitir "LISTO $servidor ya está encendido."; exit 0; }
    [[ -x "$carpeta/Iniciar-Server.sh" ]] || error "No se encontró Iniciar-Server.sh en $carpeta"
    # setsid -f: la terminal del servidor sigue abierta aunque se cierre el Manager
    setsid -f konsole -e "$carpeta/Iniciar-Server.sh" &>/dev/null
    emitir "LISTO $servidor iniciado en una terminal."
    ;;

reiniciar)
    servidor="${2:-}"; servidor_valido "$servidor"
    carpeta=$(carpeta_servidor "$servidor")
    pid=$(pid_servidor "$carpeta")
    [[ -n "$pid" ]] || error "$servidor no está encendido."
    # Paper guarda los mundos al recibir SIGTERM, igual que con el comando «stop»
    emitir "ETAPA Deteniendo $servidor (guardando mundos)"
    kill -TERM "$pid"
    for (( s = 0; s < 120; s++ )); do
        kill -0 "$pid" 2>/dev/null || break
        emitir "ESPERA $s"
        sleep 1
    done
    kill -0 "$pid" 2>/dev/null && error "$servidor no se detuvo después de 2 minutos. No se reinició."
    emitir "ETAPA Abriendo $servidor"
    setsid -f konsole -e "$carpeta/Iniciar-Server.sh" &>/dev/null
    emitir "LISTO $servidor reiniciado."
    ;;

paper)
    version="${2:-}" url="${3:-}"
    [[ -d "$MINECRAFT_DIR/$version" && "$version" == Paper* && "$version" != */* ]] || error "No existe la versión «$version»." 2
    [[ "$url" == https://* ]] || error "La URL tiene que empezar con https://" 2
    # Destinos: Paper.jar de cada servidor de esa versión (se saltean los encendidos)
    destinos=(); saltados=()
    while IFS= read -r servidor; do
        [[ "$servidor" == "$version/"* ]] || continue
        carpeta=$(carpeta_servidor "$servidor")
        if [[ -n "$(pid_servidor "$carpeta")" ]]; then
            saltados+=("$servidor")
        else
            destinos+=("$carpeta/Paper.jar")
        fi
    done < <(listar_servidores_paper)
    (( ${#destinos[@]} )) || error "No hay servidores apagados de $version para actualizar."
    emitir "ETAPA Descargando Paper"
    descargar_jar "$url" "${destinos[@]}" || error "La descarga falló o no es un archivo .jar válido."
    (( ${#saltados[@]} )) && emitir "AVISO No se tocaron (encendidos): ${saltados[*]}"
    emitir "LISTO Paper actualizado en ${#destinos[@]} servidores de $version."
    ;;

plugin)
    url="${2:-}"; shift 2 2>/dev/null || true
    [[ "$url" == https://* ]] || error "La URL tiene que empezar con https://" 2
    (( $# )) || error "Elegí al menos un servidor." 2
    # Nombre del archivo: lo último de la URL, sin lo que va después de «?»
    nombre=$(basename "${url%%\?*}")
    [[ "$nombre" == *.jar ]] || nombre="$nombre.jar"
    destinos=()
    for servidor in "$@"; do
        servidor_valido "$servidor"
        destinos+=("$(carpeta_servidor "$servidor")/plugins/$nombre")
    done
    emitir "ETAPA Descargando $nombre"
    descargar_jar "$url" "${destinos[@]}" || error "La descarga falló o no es un archivo .jar válido."
    emitir "LISTO $nombre instalado en ${#destinos[@]} servidores. Se activa al reiniciarlos."
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
    error "Uso: Minecraft.sh servidores|versiones|instancias|iniciar|reiniciar|paper|plugin|prism ..." 2
    ;;
esac
