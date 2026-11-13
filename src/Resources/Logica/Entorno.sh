#!/bin/bash
# Lógica sin interfaz: averigua en qué computadora está, si el servidor responde y qué
# programas hay. Con eso la ventana principal decide qué secciones y opciones mostrar
# (lo que antes decidían Arch-Linux-Manager.sh y los menús Lista-*.sh).
#
# Uso: Entorno.sh [--refrescar]
#   --refrescar  vuelve a hacer ping aunque el estado guardado tenga menos de 2 minutos
#
# Eventos (stdout, uno por línea):
#   MAQUINA pc|instituto|mama|krocante|otra
#   SERVIDOR SI|NO
#   PROGRAMA <nombre> SI|NO        (prismlauncher, steam, waydroid, adb)
#   RESTAURACION SI|NO             hay servidor y esta PC todavía no hizo ningún respaldo
#   NOTIFICACIONES SI|NO           es la PC de Krocante y responde la máquina destino

emitir() { printf '%s\n' "$*"; }

# Si no viene de la ventana, Common está al lado de esta carpeta (para usarlo desde la terminal)
COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Servidor.sh"   # IPs del servidor y responde()
source "$COMMON/MAC.sh"        # es_maquina_...

# Computadora (por la MAC de la placa de red)
if es_maquina_pc; then
    maquina=pc
elif es_maquina_instituto; then
    maquina=instituto
elif es_maquina_mamá; then
    maquina=mama
elif es_maquina_krocante; then
    maquina=krocante
else
    maquina=otra
fi
emitir "MAQUINA $maquina"

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

# Notificaciones: solo en la compu de Krocante y si responde la máquina destino (por Tailscale)
if [[ "$maquina" == krocante ]] && responde "fd7a:115c:a1e0::1d01:d5d1"; then
    emitir "NOTIFICACIONES SI"
else
    emitir "NOTIFICACIONES NO"
fi
