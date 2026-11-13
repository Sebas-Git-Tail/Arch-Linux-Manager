# Se incluye con source desde Logica/Minecraft.sh y Logica/Respaldo.sh (antes:
# Common/Minecraft.sh, ahora sin ventanas). Detecta solos los servidores Paper de todas
# las versiones, con esta estructura:
#   Minecraft Servers/Paper <versión>/<servidor>/Paper <versión>/Paper.jar

MINECRAFT_DIR="/home/sebastian/Escritorio/Cosas/Minecraft Servers"

# Muestra un servidor por línea, como «Paper 26.2/SMP-1»
listar_servidores_paper() {
    local dir
    for dir in "$MINECRAFT_DIR"/Paper*/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        printf '%s\n' "${dir#"$MINECRAFT_DIR"/}"
    done
}

# Carpeta real del servidor (donde están Paper.jar e Iniciar-Server.sh).
# Uso: carpeta_servidor "Paper 26.2/SMP-1"
carpeta_servidor() {
    local version="${1%%/*}"
    local carpeta="$MINECRAFT_DIR/$1/$version"
    if [[ ! -d "$carpeta" ]]; then
        # Por si la subcarpeta tiene otro nombre: la primera que tenga Iniciar-Server.sh
        carpeta=$(dirname "$(find "$MINECRAFT_DIR/$1" -maxdepth 2 -name Iniciar-Server.sh -print -quit)")
    fi
    printf '%s\n' "$carpeta"
}

# PID del java de un servidor que esté corriendo (vacío si está apagado).
# Uso: pid_servidor "/ruta/a/la/carpeta/del/servidor"
pid_servidor() {
    local pid
    for pid in $(pgrep -x java); do
        [[ "$(readlink "/proc/$pid/cwd")" == "${1%/}" ]] && { echo "$pid"; return; }
    done
}

# Descarga a un archivo temporal, comprueba que sea un .jar válido y recién ahí lo copia
# a cada destino. Así una página de error nunca reemplaza a un .jar que funciona.
# Uso: descargar_jar URL destino1 [destino2...]   (devuelve 1 si la descarga no sirve)
descargar_jar() {
    local url="$1"; shift
    local tmp destino
    tmp=$(mktemp --suffix=.jar)
    if ! curl -fsSL --retry 2 -o "$tmp" "$url" || ! unzip -tq "$tmp" &>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    for destino in "$@"; do
        mkdir -p "$(dirname "$destino")"
        cp "$tmp" "$destino"
    done
    rm -f "$tmp"
}
