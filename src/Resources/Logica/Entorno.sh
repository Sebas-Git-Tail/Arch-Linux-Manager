#!/bin/bash
# Lógica sin interfaz: averigua en qué computadora está, si el servidor responde y qué
# programas hay. Con eso la ventana principal decide qué secciones y opciones mostrar
# (lo que antes decidían Arch-Linux-Manager.sh y los menús Lista-*.sh).
#
# Uso: Entorno.sh [--refrescar]
#      Entorno.sh --equipo pc|instituto|mama|krocante|otra|auto   (guarda el equipo y sale)
#   --refrescar  vuelve a hacer ping aunque el estado guardado tenga menos de 2 minutos
#
# Eventos (stdout, uno por línea):
#   MAQUINA pc|instituto|mama|krocante|otra
#   MAQUINA_ORIGEN manual|mac       elegida en la ventana (Equipo.conf) o adivinada por la MAC
#   SERVIDOR SI|NO
#   PROGRAMA <nombre> SI|NO        (prismlauncher, steam, waydroid, adb)
#   RESTAURACION SI|NO             hay servidor y esta PC todavía no hizo ningún respaldo
#   NOTIFICACIONES SI|NO           es la PC de Krocante y responde la máquina destino

emitir() { printf '%s\n' "$*"; }

# Si no viene de la ventana, Common está al lado de esta carpeta (para usarlo desde la terminal)
COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Servidor.sh"   # IPs del servidor y responde()
source "$COMMON/Equipo.sh"     # equipo_actual, equipo_elegido, guardar_equipo

# Elegir el equipo a mano (botón «Este equipo…» de la ventana)
if [[ "${1:-}" == --equipo ]]; then
    if guardar_equipo "${2:-}"; then
        emitir "LISTO Equipo guardado."
        exit 0
    fi
    emitir "ERROR Equipo desconocido: ${2:-}"
    exit 2
fi

# Computadora: la elegida a mano en la ventana o, si no hay, la que dice la MAC
maquina=$(equipo_actual)
emitir "MAQUINA $maquina"
if equipo_elegido >/dev/null; then
    emitir "MAQUINA_ORIGEN manual"
else
    emitir "MAQUINA_ORIGEN mac"
fi

# Servidor: si el estado se guardó hace menos de 2 minutos se reutiliza (así abrir la
# ventana seguido no espera a los pings); si no, se hace ping por casa y por Tailscale
estado="$HOME/.config/Manager/Estado_Server.conf"
if [[ "${1:-}" != --refrescar && -f "$estado" && -n "$(find "$estado" -mmin -2)" ]]; then
    servidor=$(<"$estado")
else
    if elegir_destino; then
        servidor=SI
    else
        servidor=NO
    fi
    mkdir -p "$(dirname "$estado")"
    echo "$servidor" > "$estado"
fi
emitir "SERVIDOR $servidor"

# Programas de los que dependen algunas opciones
for programa in prismlauncher steam waydroid adb; do
    if command -v "$programa" &>/dev/null; then
        emitir "PROGRAMA $programa SI"
    else
        emitir "PROGRAMA $programa NO"
    fi
done

# Restauración: solo si hay servidor y esta computadora todavía no hizo ningún respaldo
# (Respaldos.conf lo crea Respaldo.sh después del primer respaldo)
if [[ "$servidor" == SI && ! -s "$HOME/.config/Manager/Respaldos.conf" ]]; then
    emitir "RESTAURACION SI"
else
    emitir "RESTAURACION NO"
fi

# Notificaciones: solo en la compu de Krocante, si el paquete trae la configuración y si
# responde la máquina destino (por Tailscale)
destino_notif=""
if [[ -r "$COMMON/Notificaciones.conf" ]]; then
    destino_notif=$(source "$COMMON/Notificaciones.conf" && printf '%s' "${NOTIF_DESTINO#*@}")
fi
if [[ "$maquina" == krocante && -n "$destino_notif" ]] && responde "$destino_notif"; then
    emitir "NOTIFICACIONES SI"
else
    emitir "NOTIFICACIONES NO"
fi
