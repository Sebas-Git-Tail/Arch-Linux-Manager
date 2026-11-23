# shellcheck shell=bash
# Se incluye con source desde Logica/Minecraft.sh y Logica/Respaldo.sh. Servidores de Minecraft
# ordenados (desde el 16/11/2026; por grupo desde el 23/11/2026):
#
#   Minecraft Servers/Servidores/<grupo>/<versión>/<servidor>/   todo adentro directo (server.properties,
#                                                     world/, plugins/, el jar) + servidor.conf
#   Minecraft Servers/Respaldos/<grupo>/<versión>/<servidor>/    jars y plugins reemplazados, mundos reiniciados
#
# Cada servidor se identifica por su ruta dentro de Servidores/ («Amigos/26.1/26.1.2 SMP-1»): así puede haber
# dos «26.1.2 SMP-1» en grupos distintos. Se muestra como «26.1.2 SMP-1 (Amigos)». Cualquier carpeta con
# servidor.conf hasta 3 niveles adentro aparece sola en el panel (también directo en Servidores/, sin grupo).
#
# servidor.conf (lo único que hay que tocar a mano, si hace falta):
#   NOMBRE="26.3 SMP-1"   TIPO=paper|forge   VERSION=26.3   JAR="paper-26.3-244.jar"   RAM=8G
# (NOMBRE es solo informativo: manda la carpeta.) Forge arranca con su run.sh (la RAM va en user_jvm_args.txt).

MINECRAFT_DIR="${MINECRAFT_DIR:-/home/sebastian/Escritorio/Cosas/Minecraft Servers}"
SERVIDORES_DIR="$MINECRAFT_DIR/Servidores"
RESPALDOS_MC_DIR="$MINECRAFT_DIR/Respaldos"

# Un servidor por línea (su ruta dentro de Servidores/, como «Amigos/26.1/26.1.2 SMP-1»), ordenados por
# grupo, versión y nombre. No cuenta un servidor.conf que esté dentro de otro servidor.
listar_servidores() {
    local conf rel padre dentro
    while IFS= read -r -d '' conf; do
        rel="${conf%/servidor.conf}"; rel="${rel#"$SERVIDORES_DIR"/}"
        [[ "$rel" != *[[:cntrl:]]* && "/$rel/" != */../* && "/$rel/" != */./* ]] || continue
        padre="$rel"; dentro=0
        while [[ "$padre" == */* ]]; do
            padre="${padre%/*}"
            [[ -f "$SERVIDORES_DIR/$padre/servidor.conf" ]] && { dentro=1; break; }
        done
        (( dentro )) || printf '%s\n' "$rel"
    done < <(find "$SERVIDORES_DIR" -mindepth 2 -maxdepth 4 -name servidor.conf -type f -print0 2>/dev/null) | sort -V
}
listar_servidores_paper() { listar_servidores; }    # nombre viejo (lo usa Respaldo.sh)

# Nombre para mostrar: «Amigos/26.1/26.1.2 SMP-1» → «26.1.2 SMP-1 (Amigos)» (sin grupo, tal cual)
nombre_visible() {
    if [[ "$1" == */* ]]; then printf '%s (%s)\n' "${1##*/}" "${1%%/*}"; else printf '%s\n' "$1"; fi
}

# Carpeta del servidor. Uso: carpeta_servidor "Amigos/26.1/26.1.2 SMP-1"
carpeta_servidor() {
    printf '%s\n' "$SERVIDORES_DIR/$1"
}

# Lee servidor.conf sin ejecutarlo (solo las claves conocidas, con el formato esperado) y deja
# CONF_TIPO, CONF_VERSION, CONF_JAR y CONF_RAM. Uso: leer_conf "Amigos/26.3/26.3 SMP-1"
leer_conf() {
    local conf linea clave valor
    conf="$(carpeta_servidor "$1")/servidor.conf"
    CONF_TIPO=paper; CONF_VERSION=""; CONF_JAR=""; CONF_RAM=8G
    [[ -f "$conf" ]] || return 1
    while IFS= read -r linea || [[ -n "$linea" ]]; do
        [[ "$linea" =~ ^([A-Z]+)=(.*)$ ]] || continue
        clave="${BASH_REMATCH[1]}"; valor="${BASH_REMATCH[2]}"
        valor="${valor#\"}"; valor="${valor%\"}"
        case "$clave" in
            TIPO)    [[ "$valor" =~ ^(paper|forge)$ ]] && CONF_TIPO="$valor" ;;
            VERSION) [[ "$valor" =~ ^[0-9][0-9a-z.\-]*$ ]] && CONF_VERSION="$valor" ;;
            JAR)     [[ "$valor" =~ ^[A-Za-z0-9._\-]+\.jar$ ]] && CONF_JAR="$valor" ;;
            RAM)     [[ "$valor" =~ ^[0-9]+[GM]$ ]] && CONF_RAM="$valor" ;;
        esac
    done < "$conf"
    return 0
}

# Cambia (o agrega) una clave de servidor.conf. Uso: cambiar_conf "Amigos/26.3/26.3 SMP-1" JAR "paper-26.3-253.jar"
cambiar_conf() {
    local conf="$(carpeta_servidor "$1")/servidor.conf" clave="$2" valor="$3" tmp
    tmp=$(mktemp)
    if grep -q "^$clave=" "$conf"; then
        awk -v c="$clave" -v v="\"$valor\"" 'BEGIN { FS = OFS = "=" } $1 == c { print c "=" v; next } { print }' "$conf" > "$tmp"
    else
        cat "$conf" > "$tmp"; printf '%s="%s"\n' "$clave" "$valor" >> "$tmp"
    fi
    cat "$tmp" > "$conf" && rm -f "$tmp"
}

# PID del java de un servidor que esté corriendo (vacío si está apagado).
# Uso: pid_servidor "/ruta/a/la/carpeta/del/servidor"
pid_servidor() {
    local pid
    for pid in $(pgrep -x java); do
        [[ "$(readlink "/proc/$pid/cwd")" == "${1%/}" ]] && { echo "$pid"; return; }
    done
}

# Nombre del mundo (level-name de server.properties; «world» si no dice)
mundo_servidor() {
    local nivel
    nivel=$(sed -n 's/^level-name=//p' "$(carpeta_servidor "$1")/server.properties" 2>/dev/null | head -n1 | tr -d '\r')
    [[ "$nivel" =~ ^[A-Za-z0-9._\ \-]+$ && "$nivel" != *..* ]] || nivel=world
    printf '%s\n' "$nivel"
}

# Descarga a un archivo temporal, comprueba que sea un .jar válido (y la suma, si se da) y recién ahí
# lo copia a cada destino. Así una página de error nunca reemplaza a un .jar que funciona.
# Uso: descargar_jar URL SUMA destino1 [destino2...]   SUMA: «sha256:…», «sha512:…» o «-»
descargar_jar() {
    local url="$1" suma="$2"; shift 2
    local tmp destino
    tmp=$(mktemp --suffix=.jar)
    if ! curl -fsSL --retry 2 -A "Sebas-Git-Tail/Arch-Linux-Manager" -o "$tmp" "$url" || ! unzip -tq "$tmp" &>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    case "$suma" in
        sha256:*) [[ "$(sha256sum "$tmp" | cut -d' ' -f1)" == "${suma#sha256:}" ]] || { rm -f "$tmp"; return 1; } ;;
        sha512:*) [[ "$(sha512sum "$tmp" | cut -d' ' -f1)" == "${suma#sha512:}" ]] || { rm -f "$tmp"; return 1; } ;;
    esac
    for destino in "$@"; do
        mkdir -p "$(dirname "$destino")"
        cp "$tmp" "$destino"
    done
    rm -f "$tmp"
}

# Mueve un archivo a Respaldos/<servidor>/<subcarpeta>/ (sin pisar uno que ya esté ahí)
a_respaldos() {   # $1 servidor, $2 subcarpeta, $3 archivo
    local dest="$RESPALDOS_MC_DIR/$1/$2" nombre
    mkdir -p "$dest"
    nombre="$(basename "$3")"
    [[ -e "$dest/$nombre" ]] && nombre="$(date +%Y%m%d-%H%M%S)-$nombre"
    mv -f "$3" "$dest/$nombre"
}
