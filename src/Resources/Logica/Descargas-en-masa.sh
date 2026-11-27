#!/bin/bash
# Lógica sin interfaz de Descargas en masa (antes: General/Descargas-en-masa.sh con
# Cantidad_URL.sh y Pedir_URLs.sh): baja varios archivos con wget a una carpeta.
# Usa los mismos eventos que Descargar.sh, así la ventana la maneja con la misma página.
#
# Uso: Descargas-en-masa.sh --destino DIR [--] URL...
#
# Eventos (stdout, uno por línea):
#   INICIO <n> <total> <url>   empieza la URL n de total
#   ARCHIVO <nombre>           archivo que se está bajando
#   PROGRESO <0-100>           porcentaje del archivo (solo cuando cambia)
#   LISTO <ruta>               archivo guardado en <ruta>
#   FALLO <mensaje>            falló la URL actual (sigue con la siguiente)
#   ERROR <mensaje>            error que impide seguir (termina)
#
# Código de salida: 0 todo bien, 1 falló alguna URL, 2 error de uso.
#
# Nunca pisa ni borra un archivo que ya estaba: si el nombre existe, guarda «nombre (2).ext»,
# «nombre (3).ext»... Cada descarga va primero a un archivo temporal propio y oculto en la misma
# carpeta (.descarga-XXXXXX); si falla o se cancela, se borra solo ese.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $*"; exit 2; }

destino=""
while (( $# )); do
    case "$1" in
        --destino) [[ $# -ge 2 ]] || error "Falta la carpeta después de --destino"; destino=$2; shift ;;
        --)        shift; break ;;
        -*)        error "Opción desconocida: $1" ;;
        *)         break ;;
    esac
    shift
done
(( $# )) || error "No se pasó ninguna URL"
[[ -n "$destino" ]] || error "Falta --destino"
mkdir -p "$destino" || error "No se pudo crear la carpeta $destino"

# Un nombre libre en la carpeta: el mismo si no existe, si no «base (2).ext», «base (3).ext»...
# (las extensiones dobles como .tar.gz quedan juntas: «archivo (2).tar.gz»)
nombre_libre() {
    local nombre="$1" base ext i=2
    [[ -e "$destino/$nombre" || -L "$destino/$nombre" ]] || { printf '%s' "$nombre"; return; }
    if [[ "$nombre" =~ ^(.+)(\.tar\.[A-Za-z0-9]+)$ || "$nombre" =~ ^(.+)(\.[^.]+)$ ]]; then
        base="${BASH_REMATCH[1]}" ext="${BASH_REMATCH[2]}"
    else
        base="$nombre" ext=""
    fi
    while [[ -e "$destino/$base ($i)$ext" || -L "$destino/$base ($i)$ext" ]]; do (( i++ )); done
    printf '%s' "$base ($i)$ext"
}

# El temporal de la descarga en curso: si se cancela, se borra solo ese
temporal=""
trap '[[ -n "$temporal" ]] && rm -f "$temporal"; exit 130' TERM INT

fallidas=0 n=0
for url in "$@"; do
    (( n++ ))
    emitir "INICIO $n $# $url"
    # Nombre: lo último de la URL, sin lo que va después de «?» (nunca «.» ni «..» ni oculto vacío)
    nombre=$(basename "${url%%\?*}")
    [[ -n "$nombre" && "$nombre" != / && "$nombre" != . && "$nombre" != .. ]] || nombre="descarga-$n"
    emitir "ARCHIVO $(nombre_libre "$nombre")"

    if ! temporal=$(mktemp "$destino/.descarga-XXXXXX"); then
        temporal=""
        emitir "FALLO No se pudo crear un archivo en $destino"
        (( fallidas++ ))
        continue
    fi
    ultimo=""
    while IFS= read -r linea; do
        if [[ "$linea" =~ ([0-9]+)% && "${BASH_REMATCH[1]}" != "$ultimo" ]]; then
            ultimo="${BASH_REMATCH[1]}"
            emitir "PROGRESO $ultimo"
        fi
    done < <(set -o pipefail; wget --progress=dot:mega -O "$temporal" -- "$url" 2>&1)
    if wait $!; then
        # Recién ahora se elige el nombre final (otro programa pudo crear uno igual mientras
        # bajaba) y mv -n nunca pisa: si justo apareció, se prueba con el siguiente
        final=""
        for _ in 1 2 3 4 5; do
            final="$destino/$(nombre_libre "$nombre")"
            mv -n -- "$temporal" "$final" 2>/dev/null
            [[ -e "$temporal" ]] || break
        done
        if [[ -e "$temporal" ]]; then
            rm -f -- "$temporal"
            emitir "FALLO No se pudo guardar $nombre en $destino"
            (( fallidas++ ))
        else
            # mktemp lo crea solo para el usuario (600): que quede como cualquier archivo nuevo
            chmod "$(printf '%o' $(( 0666 & ~0$(umask) )))" -- "$final" 2>/dev/null
            emitir "LISTO $final"
        fi
    else
        rm -f -- "$temporal"    # solo el temporal propio: nunca un archivo que ya estaba
        emitir "FALLO No se pudo descargar $url"
        (( fallidas++ ))
    fi
    temporal=""
done

(( fallidas == 0 ))
