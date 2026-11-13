# shellcheck shell=bash
# Se incluye con source (lo incluye Common/Equipo.sh). Reconoce cada computadora por la MAC de su
# placa de red. Solo se usa si no se eligió el equipo a mano (ver Equipo.sh).
# MAC PC
MAC_PC="58:11:22:a9:df:de"

# MAC Mamá
MAC_MAMA="18:c0:4d:a2:fe:e0"

# MAC Krocante
MAC_KROCANTE="80:ee:73:2d:43:29"

# MAC Instituto
MAC_INSTITUTO="5c:ba:ef:4c:0c:77"

# Buscar la MAC en todas las interfaces (evita asumir cuál es la "principal").
# También la MAC permanente (permaddr): si el wifi usa una MAC aleatoria por red,
# la dirección actual cambia y la computadora no se reconocería.
detectar_mac() {
    for iface in /sys/class/net/*/address; do
        cat "$iface"
    done
    ip -o link 2>/dev/null | grep -oE 'permaddr [0-9a-fA-F:]{17}' | cut -d' ' -f2
}

# Verdadero si la MAC está en alguna interfaz (-x: línea entera, -i: sin importar mayúsculas).
# La lista se guarda primero en una variable: con «detectar_mac | grep -q», grep corta
# apenas encuentra la MAC, detectar_mac recibe SIGPIPE y, en los scripts con
# «set -o pipefail» (como Logica/Respaldo.sh), la comprobación daba falso.
tiene_mac() {
    local macs
    macs=$(detectar_mac)
    grep -qix -- "$1" <<< "$macs"
}
