#!/bin/bash
# Lógica sin interfaz de Notificaciones (antes: General/Notificaciones.sh): manda un
# mensaje a la PC de Sebastian, que lo muestra con Mostrar-Notificacion.sh.
#
# Entra con una clave SSH que viene en el paquete (Common/Notificaciones.key, la arma
# ~/Repo/Scripts/generar-clave-notificaciones.sh y NO se sube a GitHub). En la PC de Sebastián esa
# clave está restringida (restrict, from=IP de Krocante, command=Mostrar-Notificacion.sh): solo
# sirve para mostrar una notificación. Antes viajaba la contraseña de la cuenta, ofuscada.
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
CLAVE="$COMMON/Notificaciones.key"
[[ -r "$CONF" && -r "$CLAVE" ]] || error "Falta la configuración de notificaciones ($CONF y Notificaciones.key)." 2
source "$CONF"                  # NOTIF_DESTINO (usuario@ip)
source "$COMMON/Servidor.sh"    # SSH_HUELLAS (huellas fijas de Common/known_hosts)

mensaje=$(head -c 1000)
[[ -n "${mensaje//[[:space:]]/}" ]] || error "No se escribió ningún mensaje." 2

# El comando que se ejecuta en la PC lo decide la PC (command= en authorized_keys), no este script.
# IdentitiesOnly: solo esta clave, no las del usuario. BatchMode: nunca pide contraseña.
# shellcheck disable=SC2086
printf '%s' "$mensaje" | ssh $SSH_HUELLAS -o HostKeyAlias=pc-sebastian \
        -i "$CLAVE" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
        "$NOTIF_DESTINO" 2>/dev/null
codigo=$?
case $codigo in
    0) emitir "LISTO Notificación enviada." ;;
    *) error "No se pudo enviar la notificación. ¿La PC de Sebastián está encendida?" ;;
esac
