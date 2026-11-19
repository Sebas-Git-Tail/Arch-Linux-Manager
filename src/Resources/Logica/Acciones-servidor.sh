#!/bin/bash
# Lógica sin interfaz de la sección Servidor: le pide al servidor que corra una de sus acciones
# (miniaturas de Bodrio, páginas de descargas, páginas del Instituto).
#
# Entra con una clave propia de este equipo (~/.ssh/arch-linux-manager-servidor, se crea sola la
# primera vez). En el servidor esa clave está limitada (restrict, command=acciones-servidor.sh): solo
# sirve para pedir las acciones de su lista, ni siquiera abre una terminal. Hasta que se autoriza en
# el servidor, la acción falla y la clave pública queda copiada en el portapapeles.
#
# Uso: Acciones-servidor.sh miniaturas-bodrio|descargas|indices-instituto
#
# Eventos: LINEA <texto> (lo que va diciendo el servidor) / LISTO <texto> / ERROR <texto>
# Código de salida: 0 bien, 1 falló, 2 error de uso o equipo sin autorizar.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-1}"; }

accion="${1:-}"
case "$accion" in
    miniaturas-bodrio|descargas|indices-instituto) ;;
    *) error "Acción desconocida: $accion" 2 ;;
esac

COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Servidor.sh"    # SERVIDOR_USUARIO, elegir_destino, SSH_HUELLAS_SERVIDOR

CLAVE="$HOME/.ssh/arch-linux-manager-servidor"
if [[ ! -f "$CLAVE" ]]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N "" -C "arch-linux-manager@$(cat /etc/hostname 2>/dev/null || echo equipo)" -f "$CLAVE" \
        || error "No se pudo crear la clave de este equipo."
fi

elegir_destino || error "No se encontró el servidor."

# El comando lo decide el servidor (command= en authorized_keys): lo que se manda es solo el nombre
# de la acción. IdentitiesOnly: solo esta clave. BatchMode: nunca pide contraseña.
salida=$(mktemp); trap 'rm -f "$salida" "$salida.err"' EXIT
# shellcheck disable=SC2086
ssh $SSH_HUELLAS_SERVIDOR -i "$CLAVE" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
        "$SERVIDOR_USUARIO@$DESTINO" "$accion" < /dev/null > >(tee "$salida" | sed -u 's/^/LINEA /') 2> "$salida.err"
codigo=$?
sleep 0.2      # que termine de escribir el tee
ultima=$(grep -v '^[[:space:]]*$' "$salida" | tail -1)

if (( codigo == 0 )); then
    emitir "LISTO ${ultima:-Listo.}"
elif (( codigo == 255 )) && grep -q "Permission denied" "$salida.err"; then
    # Para autorizarlo hace falta la clave pública: queda en el portapapeles si se puede
    if command -v wl-copy &>/dev/null; then wl-copy < "$CLAVE.pub" 2>/dev/null
    elif command -v xclip &>/dev/null; then xclip -selection clipboard < "$CLAVE.pub" 2>/dev/null
    fi
    error "Este equipo todavía no está autorizado en el servidor. Su clave pública ($CLAVE.pub) quedó copiada: autorizala en el servidor con autorizar-equipo.sh." 2
elif (( codigo == 255 )); then
    error "No se pudo conectar con el servidor."
else
    error "El servidor no pudo terminar (código $codigo)."
fi
