# shellcheck shell=bash
# Se incluye con source. Dice en qué computadora está corriendo el Manager.
#
# Primero mira ~/.config/Manager/Equipo.conf (una palabra: pc, instituto, mama, krocante u otra),
# que se elige desde la ventana (botón «Este equipo…» abajo). Así, cambiar de placa de red o
# instalar en una PC nueva no obliga a publicar una versión nueva del paquete.
# Si ese archivo no existe, se adivina como antes, por la MAC de la placa de red (Common/MAC.sh).
# Elegir el equipo a mano es para depurar y solo vale en las computadoras de Sebastián (PC e
# instituto, reconocidas por la MAC real): en las demás se ignora Equipo.conf y no se puede guardar.

EQUIPOS_VALIDOS=(pc instituto mama krocante otra)
EQUIPO_CONF="$HOME/.config/Manager/Equipo.conf"

source "${COMMON:-$(dirname "${BASH_SOURCE[0]}")}/MAC.sh"   # MAC_*, tiene_mac

# Verdadero si la placa de red es de una computadora de Sebastián (no mira Equipo.conf)
puede_elegir_equipo() {
    tiene_mac "$MAC_PC" || tiene_mac "$MAC_INSTITUTO"
}

# Imprime el equipo elegido a mano, o nada si no hay uno válido (o no se puede elegir)
equipo_elegido() {
    local e=""
    puede_elegir_equipo || return 1
    [[ -s "$EQUIPO_CONF" ]] && IFS= read -r e < "$EQUIPO_CONF"
    e="${e//[[:space:]]/}"
    for valido in "${EQUIPOS_VALIDOS[@]}"; do
        [[ "$e" == "$valido" ]] && { printf '%s\n' "$e"; return 0; }
    done
    return 1
}

# Imprime el equipo según la MAC (otra si no coincide ninguna)
equipo_por_mac() {
    if tiene_mac "$MAC_PC"; then echo pc
    elif tiene_mac "$MAC_INSTITUTO"; then echo instituto
    elif tiene_mac "$MAC_MAMA"; then echo mama
    elif tiene_mac "$MAC_KROCANTE"; then echo krocante
    else echo otra
    fi
}

# El equipo actual (se calcula una sola vez por script)
equipo_actual() {
    if [[ -z "${_EQUIPO_ACTUAL:-}" ]]; then
        _EQUIPO_ACTUAL=$(equipo_elegido) || _EQUIPO_ACTUAL=$(equipo_por_mac)
    fi
    printf '%s\n' "$_EQUIPO_ACTUAL"
}

# Guarda el equipo elegido a mano («auto» borra la elección y vuelve a usar la MAC)
guardar_equipo() {
    puede_elegir_equipo || return 1
    if [[ "$1" == auto ]]; then
        rm -f "$EQUIPO_CONF"
        return 0
    fi
    for valido in "${EQUIPOS_VALIDOS[@]}"; do
        if [[ "$1" == "$valido" ]]; then
            mkdir -p "$(dirname "$EQUIPO_CONF")"
            printf '%s\n' "$1" > "$EQUIPO_CONF"
            return 0
        fi
    done
    return 1
}

# Las de siempre, ahora a partir de equipo_actual (las usan Respaldo.sh y Tutoriales.sh)
es_maquina_pc()        { [[ "$(equipo_actual)" == pc ]]; }
es_maquina_instituto() { [[ "$(equipo_actual)" == instituto ]]; }
es_maquina_mamá()      { [[ "$(equipo_actual)" == mama ]]; }
es_maquina_krocante()  { [[ "$(equipo_actual)" == krocante ]]; }
