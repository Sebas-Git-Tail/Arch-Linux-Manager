#!/bin/bash
# Lado receptor de Logica/Notificacion.sh (corre en la PC de Sebastian).
# No se usa desde la ventana: lo ejecuta por SSH Logica/Notificacion.sh desde la PC de la tía,
# entrando con la clave Common/Notificaciones.key. En esta PC la clave está en
# ~/.ssh/authorized_keys con «restrict,from="<IPs de Krocante>",command="…/Mostrar-Notificacion.sh"»
# (lo instala ~/Repo/Scripts/generar-clave-notificaciones.sh): con ella no se puede hacer otra cosa.

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
