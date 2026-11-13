#!/bin/bash
# Lógica sin interfaz de GE-Proton (una versión de Proton con más arreglos) para Steam
# (antes: General/Steam-Proton.sh).
#
# Uso: Steam-Proton.sh ultima          la última versión para esta arquitectura
#      Steam-Proton.sh instaladas      las versiones de GE-Proton instaladas
#      Steam-Proton.sh instalar URL    descarga, verifica e instala (quita las anteriores)
#
# Eventos (stdout, uno por línea):
#   ARQUITECTURA <x86_64|aarch64...>
#   ULTIMA <versión> <url>
#   INSTALADA <versión>
#   ETAPA <texto>            descargando / verificando / instalando
#   PROGRESO <0-100>         avance de la descarga (solo cuando cambia)
#   AVISO <texto>
#   LISTO <versión>          quedó instalada
#   ERROR <texto>            no se pudo (termina)
#
# Código de salida: 0 bien, 1 falló la descarga o la instalación, 2 error de uso o de red.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-2}"; }

DIRECTORIO="$HOME/.local/share/Steam/compatibilitytools.d"
API="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"

# GE-Proton publica un .tar.gz por arquitectura; sin filtrar se agarraba el primero de la
# lista (aarch64) aunque la computadora fuera x86_64
ARQ=$(uname -m)
emitir "ARQUITECTURA $ARQ"

case "${1:-}" in
ultima)
    url=$(curl -fsSL "$API" 2>/dev/null | grep -o "\"browser_download_url\": *\"[^\"]*-$ARQ\.tar\.gz\"" | head -n1 | cut -d'"' -f4)
    [[ -n "$url" ]] || error "No se pudo consultar la última versión en GitHub."
    nombre=$(basename "$url")
    emitir "ULTIMA ${nombre%.tar.gz} $url"
    ;;

instaladas)
    for carpeta in "$DIRECTORIO"/GE-Proton*/; do
        [[ -d "$carpeta" ]] && emitir "INSTALADA $(basename "$carpeta")"
    done
    ;;

instalar)
    url="${2:-}"
    [[ "$url" == https://* && "$url" == *.tar.gz ]] || error "La URL tiene que ser https y terminar en .tar.gz"
    [[ "$url" == *"-$ARQ.tar.gz" ]] || emitir "AVISO Esa versión no es para $ARQ: Steam no va a poder usarla."
    nombre=$(basename "$url")
    temporal=$(mktemp -d)
    trap 'rm -rf "$temporal"' EXIT

    emitir "ETAPA Descargando $nombre"
    ultimo=""
    while IFS= read -r linea; do
        if [[ "$linea" =~ ([0-9]+)% && "${BASH_REMATCH[1]}" != "$ultimo" ]]; then
            ultimo="${BASH_REMATCH[1]}"
            emitir "PROGRESO $ultimo"
        fi
    done < <(set -o pipefail; wget --progress=dot:mega -O "$temporal/$nombre" "$url" 2>&1)
    wait $! || error "No se pudo descargar $nombre" 1

    # GE-Proton publica la suma .sha512sum de cada versión: si está, se comprueba que la
    # descarga no esté dañada antes de tocar lo instalado
    emitir "ETAPA Verificando"
    if curl -fsSL "${url%.tar.gz}.sha512sum" -o "$temporal/suma.sha512sum" 2>/dev/null; then
        esperada=$(awk '{print $1}' "$temporal/suma.sha512sum")
        obtenida=$(sha512sum "$temporal/$nombre" | awk '{print $1}')
        [[ "$esperada" == "$obtenida" ]] || error "La descarga está dañada (la suma SHA-512 no coincide)." 1
        emitir "AVISO Suma SHA-512 correcta."
    else
        emitir "AVISO Esta versión no publica suma SHA-512: no se pudo verificar."
    fi

    emitir "ETAPA Instalando"
    tar -xzf "$temporal/$nombre" -C "$temporal" || error "No se pudo descomprimir $nombre" 1
    # La carpeta que trae el .tar.gz (normalmente igual al nombre sin .tar.gz)
    version=$(tar -tzf "$temporal/$nombre" | head -n1 | cut -d/ -f1)
    [[ -n "$version" && -d "$temporal/$version" ]] || error "El archivo no tiene el formato esperado." 1

    # Recién con la nueva versión lista se reemplazan las anteriores
    mkdir -p "$DIRECTORIO"
    for viejo in "$DIRECTORIO"/GE-Proton*/; do
        [[ -d "$viejo" ]] && rm -rf "$viejo"
    done
    mv "$temporal/$version" "$DIRECTORIO/" || error "No se pudo mover $version a $DIRECTORIO" 1
    emitir "LISTO $version"
    ;;

*)
    error "Uso: Steam-Proton.sh ultima | instaladas | instalar URL"
    ;;
esac
