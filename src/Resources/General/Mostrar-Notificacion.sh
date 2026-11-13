#!/bin/bash
# Lado receptor de Logica/Notificacion.sh (corre en la PC de Sebastian).
# No se usa desde la ventana: lo ejecuta por SSH Logica/Notificacion.sh desde la PC de la tía,
# entrando con usuario y contraseña (guardada ofuscada en su paquete).
#
# Para que esa contraseña no sirva para nada más que esto, en la PC que recibe conviene
# agregar al final de /etc/ssh/sshd_config (con la IP de Tailscale de la PC de la tía):
#   Match User sebastian Address <IP-de-la-tía>
#       ForceCommand /usr/share/Arch-Linux-Manager/Resources/General/Mostrar-Notificacion.sh
#       PermitTTY no
#       AllowTcpForwarding no
#       X11Forwarding no
# y reiniciar sshd.

# Lee el mensaje de la entrada estándar (máximo 1000 caracteres) y lo muestra en la
# sesión gráfica. El texto se pasa por la entrada estándar, nunca se interpreta como código.

mensaje=$(head -c 1000)
[[ -z "$mensaje" ]] && exit 1

XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR
# sshd no trae WAYLAND_DISPLAY: se usa el socket de la sesión que exista (wayland-0,
# wayland-1...), sin el .lock
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        [[ -S "$socket" ]] && { WAYLAND_DISPLAY=$(basename "$socket"); break; }
    done
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# La muestra la ventana Qt del Manager (--notificacion lee el texto de la entrada estándar).
# setsid -f: la ventana queda abierta aunque se corte la conexión SSH
printf '%s' "$mensaje" | setsid -f Arch-Linux-Manager-Qt --notificacion &>/dev/null
