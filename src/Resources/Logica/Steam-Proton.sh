#!/bin/bash
# Lógica sin interfaz de GE-Proton (una versión de Proton con más arreglos) para Steam
# (antes: General/Steam-Proton.sh).
#
# Uso: Steam-Proton.sh ultima          la última versión para esta arquitectura
#      Steam-Proton.sh instaladas      las versiones de GE-Proton instaladas
#      Steam-Proton.sh instalar URL [--sin-suma]
#                                      descarga, verifica e instala (quita las anteriores).
#                                      Si esa versión no publica su suma SHA-512, no instala
#                                      nada (SIN_SUMA, código 3) salvo que se pase --sin-suma
#                                      (la ventana lo pasa solo si el usuario lo confirma).
#
# Eventos (stdout, uno por línea):
#   ARQUITECTURA <x86_64|aarch64...>
#   ULTIMA <versión> <url>
#   INSTALADA <versión>
#   ETAPA <texto>            descargando / verificando / instalando
#   PROGRESO <0-100>         avance de la descarga (solo cuando cambia)
#   AVISO <texto>
#   SIN_SUMA <nombre>        esa versión no publica suma SHA-512: no se instaló (código 3)
#   LISTO <versión>          quedó instalada
#   ERROR <texto>            no se pudo (termina)
#
# Código de salida: 0 bien, 1 falló la descarga o la instalación, 2 error de uso o de red,
# 3 la versión no publica suma SHA-512 (confirmar y repetir con --sin-suma).

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
    sin_suma=no
    [[ "${3:-}" == --sin-suma ]] && sin_suma=si
    [[ "$url" == https://* && "$url" == *.tar.gz ]] || error "La URL tiene que ser https y terminar en .tar.gz"
    [[ "$url" == *"-$ARQ.tar.gz" ]] || emitir "AVISO Esa versión no es para $ARQ: Steam no va a poder usarla."
    nombre=$(basename "$url")
    temporal=$(mktemp -d)
    trap 'rm -rf "$temporal"' EXIT

    # GE-Proton publica la suma .sha512sum de cada versión: se baja antes que el .tar.gz. Si no
    # está, no se instala nada sin que el usuario lo acepte (no habría forma de saber si la
    # descarga está dañada o no es la que publicó GE-Proton). Solo un 404 es «no publica suma»:
    # una falla de red no tiene que terminar en ofrecer instalar sin verificar
    codigo_http=$(curl -sSL -w '%{http_code}' "${url%.tar.gz}.sha512sum" -o "$temporal/suma.sha512sum" 2>/dev/null)
    codigo_curl=$?
    if [[ "$sin_suma" == no ]] && { (( codigo_curl != 0 )) || [[ "$codigo_http" != 200 && "$codigo_http" != 404 ]]; }; then
        error "No se pudo consultar la suma SHA-512 de $nombre (¿sin conexión?). No se instaló nada." 1
    fi
    if [[ "$codigo_http" != 200 ]] \
            || ! [[ "$(awk '{print $1; exit}' "$temporal/suma.sha512sum")" =~ ^[0-9a-f]{128}$ ]]; then
        if [[ "$sin_suma" == no ]]; then
            emitir "SIN_SUMA $nombre"
            error "$nombre no publica suma SHA-512: no se instaló nada (no se puede comprobar que la descarga esté bien)." 3
        fi
        rm -f "$temporal/suma.sha512sum"
    fi

    emitir "ETAPA Descargando $nombre"
    ultimo=""
    while IFS= read -r linea; do
        if [[ "$linea" =~ ([0-9]+)% && "${BASH_REMATCH[1]}" != "$ultimo" ]]; then
            ultimo="${BASH_REMATCH[1]}"
            emitir "PROGRESO $ultimo"
        fi
    done < <(set -o pipefail; wget --progress=dot:mega -O "$temporal/$nombre" "$url" 2>&1)
    wait $! || error "No se pudo descargar $nombre" 1

    # Se comprueba que la descarga no esté dañada antes de tocar lo instalado
    emitir "ETAPA Verificando"
    if [[ -f "$temporal/suma.sha512sum" ]]; then
        esperada=$(awk '{print $1; exit}' "$temporal/suma.sha512sum")
        obtenida=$(sha512sum "$temporal/$nombre" | awk '{print $1}')
        [[ "$esperada" == "$obtenida" ]] || error "La descarga está dañada (la suma SHA-512 no coincide)." 1
        emitir "AVISO Suma SHA-512 correcta."
    else
        emitir "AVISO Instalada sin verificar: esta versión no publica suma SHA-512 (lo aceptaste)."
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
    error "Uso: Steam-Proton.sh ultima | instaladas | instalar URL [--sin-suma]"
    ;;
esac
