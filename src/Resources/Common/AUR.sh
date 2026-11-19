#!/bin/bash
# Se incluye con source (después de Equipo.sh). Las apps del AUR que el Manager instala y
# actualiza sin yay ni paru: baja el PKGBUILD del AUR y lo arma con makepkg (para eso hacen
# falta fakeroot y debugedit, que General/AUR-instalar.sh instala si no están).
#
# Quién ve cada una (pedido de Sebastián, 19/11/2026):
#   pc, instituto    todas (Playit solo acá: el túnel de los servidores de Minecraft)
#   mama, krocante   solo Claude
#   otra             todas menos Claude y Playit

# paquete|nombre|descripción|equipos (separados por comas)
AUR_APPS=(
    "claude-desktop|Claude|App de escritorio de Claude: chat, Cowork y Claude Code.|pc,instituto,mama,krocante"
    "equibop-bin|Equibop|Discord con Equicord (temas y complementos).|pc,instituto,otra"
    "heroic-games-launcher-bin|Heroic Games Launcher|Juegos de Epic, GOG y Amazon.|pc,instituto,otra"
    "lcl-gui-bin|Linux Command Library|Referencia de comandos de Linux y machetes.|pc,instituto,otra"
    "playit-bin|Playit|Túnel para que se pueda entrar desde afuera a tus servidores de Minecraft.|pc,instituto"
)

AUR_URL="https://aur.archlinux.org"

# Imprime las líneas de AUR_APPS que corresponden a este equipo
aur_apps_del_equipo() {
    local equipo linea
    equipo=$(equipo_actual)
    for linea in "${AUR_APPS[@]}"; do
        [[ ",${linea##*|}," == *",$equipo,"* ]] && printf '%s\n' "$linea"
    done
}

# Verdadero si el paquete es una de las apps de este equipo (solo esas se pueden instalar)
aur_permitido() {
    local linea
    while IFS= read -r linea; do
        [[ "${linea%%|*}" == "$1" ]] && return 0
    done < <(aur_apps_del_equipo)
    return 1
}

# Nombre para mostrar de un paquete
aur_nombre() {
    local linea resto
    for linea in "${AUR_APPS[@]}"; do
        if [[ "${linea%%|*}" == "$1" ]]; then
            resto=${linea#*|}
            printf '%s\n' "${resto%%|*}"
            return 0
        fi
    done
    printf '%s\n' "$1"
}

# Versión instalada («4.4212.0-1») o nada si no está
aur_instalada() {
    pacman -Q "$1" 2>/dev/null | awk '{print $2}'
}

# Versiones del AUR de los paquetes dados: una línea «paquete<TAB>versión» por cada uno que exista.
# Una sola consulta a la API (RPC v5). Para las pruebas, AUR_RPC_FALSA es un .json con la respuesta.
aur_versiones() {
    local json url p
    if [[ -n "${AUR_RPC_FALSA:-}" ]]; then
        json=$(<"$AUR_RPC_FALSA") || return 1
    else
        url="$AUR_URL/rpc/v5/info?"
        for p; do url+="arg[]=$p&"; done
        json=$(curl -fsS -m 15 --globoff "${url%&}") || return 1
    fi
    python3 -c '
import json, re, sys
try:
    datos = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)
if not isinstance(datos, dict) or datos.get("type") != "multiinfo":
    sys.exit(1)
pedidos = set(sys.argv[2:])
for r in datos.get("results", []):
    nombre, version = str(r.get("Name", "")), str(r.get("Version", ""))
    # Solo lo que se pidió y con una versión con forma de versión de Arch
    if nombre in pedidos and re.fullmatch(r"[0-9A-Za-z.+_:~-]+", version):
        print(nombre + "\t" + version)
' "$json" "$@"
}
