#!/bin/bash
# Lógica sin interfaz de Tutoriales (antes: General/Tutoriales.sh y Common/URL.sh): lista
# los videos .mkv de la carpeta Tutoriales del servidor web. La ventana los reproduce con
# mpv directo desde el servidor, sin descargarlos.
#
# Uso: Tutoriales.sh
#
# Eventos (stdout, uno por línea):
#   VIDEO <nombre> <url>     un video (nombre sin .mkv; la url va al final)
#   ERROR <texto>            no se pudo (termina)
#
# Código de salida: 0 bien, 1 no se encontraron videos, 2 sin conexión con el servidor.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-2}"; }

COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Servidor.sh"   # direcciones del servidor web y responde()
source "$COMMON/MAC.sh"        # es_maquina_mamá

# Servidor web: por la red de casa si responde, si no por Tailscale
# (se prueba el puerto web: un ping a 192.168.100.14 puede contestar otro aparato en otra red)
if puerto_abierto "$SERVIDOR_IP_LOCAL" 8080; then
    URL="$SERVIDOR_WEB_LOCAL"
elif puerto_abierto "$SERVIDOR_HOST_TAILSCALE" 443; then
    URL="$SERVIDOR_WEB_TAILSCALE"
else
    error "Disculpe, se cayó el sistema, vuelva a intentarlo más tarde."
fi

CARPETA="$URL/Scripts/General/Tutoriales/"
listado=$(curl -fsSL "$CARPETA") && [[ -n "$listado" ]] || error "No se pudo conectar a $CARPETA"

encontrados=0
# Los .mkv que aparecen en los enlaces (href) del listado de la carpeta
while IFS= read -r video; do
    # En las computadoras que no son la de tu mamá solo se muestra el de KDE Connect
    if ! es_maquina_mamá && [[ "$video" != KDEConnect.mkv ]]; then
        continue
    fi
    emitir "VIDEO ${video%.mkv} $CARPETA$video"
    (( encontrados++ ))
done < <(grep -oP 'href="\K[^"]+\.mkv(?=")' <<< "$listado")

(( encontrados )) || error "No se encontraron videos en $CARPETA" 1
