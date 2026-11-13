#!/bin/bash
# Lógica sin interfaz de Notificaciones (antes: General/Notificaciones.sh): manda un
# mensaje a la PC de Sebastian, que lo muestra con Mostrar-Notificacion.sh.
#
# Entra con usuario y contraseña, sin que haga falta escribirla: viene ofuscada en
# Common/Notificaciones.conf (lo arma ~/Repo/Scripts/guardar-clave-notificaciones.sh y NO se
# sube a GitHub). Ofuscada no es cifrada: solo evita que se lea a simple vista.
# El mensaje viaja por la entrada estándar, nunca como parte de un comando.
#
# Uso: Notificacion.sh < mensaje
#
# Eventos: LISTO <texto> / ERROR <texto>
# Código de salida: 0 enviada, 1 no se pudo enviar, 2 falta la configuración o el mensaje.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-1}"; }

COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
CONF="$COMMON/Notificaciones.conf"
[[ -r "$CONF" ]] || error "Falta la configuración de notificaciones ($CONF)." 2
source "$CONF"     # NOTIF_DESTINO (usuario@ip), NOTIF_COMANDO y NOTIF_CLAVE (ofuscada)

# Deshace la ofuscación (XOR con una frase fija + base64)
desofuscar() {
    python3 -c 'import base64,sys
k=b"Arch-Linux-Manager/notificaciones"
d=base64.b64decode(sys.argv[1])
sys.stdout.write(bytes(c ^ k[i % len(k)] for i, c in enumerate(d)).decode())' "$1"
}

mensaje=$(head -c 1000)
[[ -n "${mensaje//[[:space:]]/}" ]] || error "No se escribió ningún mensaje." 2

SSHPASS=$(desofuscar "$NOTIF_CLAVE") || error "La contraseña guardada está dañada." 2
export SSHPASS

printf '%s' "$mensaje" | sshpass -e ssh \
        -o PubkeyAuthentication=no -o PreferredAuthentications=password \
        -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "$NOTIF_DESTINO" "$NOTIF_COMANDO"
codigo=$?
unset SSHPASS
case $codigo in
    0) emitir "LISTO Notificación enviada." ;;
    5) error "La contraseña de notificaciones ya no es la correcta: hay que volver a guardarla." ;;
    *) error "No se pudo enviar la notificación. ¿La PC de Sebastian está encendida?" ;;
esac
