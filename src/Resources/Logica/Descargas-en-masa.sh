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

fallidas=0 n=0
for url in "$@"; do
    (( n++ ))
    emitir "INICIO $n $# $url"
    # Nombre: lo último de la URL, sin lo que va después de «?»
    nombre=$(basename "${url%%\?*}")
    [[ -n "$nombre" && "$nombre" != / ]] || nombre="descarga-$n"
    emitir "ARCHIVO $nombre"

    ultimo=""
    while IFS= read -r linea; do
        if [[ "$linea" =~ ([0-9]+)% && "${BASH_REMATCH[1]}" != "$ultimo" ]]; then
            ultimo="${BASH_REMATCH[1]}"
            emitir "PROGRESO $ultimo"
        fi
    done < <(set -o pipefail; wget --progress=dot:mega -O "$destino/$nombre" -- "$url" 2>&1)
    if wait $!; then
        emitir "LISTO $destino/$nombre"
    else
        rm -f "$destino/$nombre"    # wget deja un archivo vacío o a medias
        emitir "FALLO No se pudo descargar $url"
        (( fallidas++ ))
    fi
done

(( fallidas == 0 ))
