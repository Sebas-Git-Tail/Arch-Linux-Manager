#!/bin/bash
# Abre un comando en una ventana de terminal, sin depender de konsole: usa la primera que haya de
# konsole, $TERMINAL, xdg-terminal-exec, kgx (Consola de GNOME), gnome-terminal, alacritty, kitty
# y xterm. Lo usan la ventana (Actualizar Arch, Apps del AUR, Playit) y Logica/Minecraft.sh.
#
# Uso: Terminal.sh [--esperar] [--titulo TEXTO] [--carpeta DIR] -- COMANDO [ARGUMENTOS...]
#      Terminal.sh --cual        dice qué terminal se usaría (sale con 1 si no hay ninguna)
#   --esperar   el proceso es la ventana misma hasta que se cierra (konsole --nofork,
#               gnome-terminal --wait): así la ventana del Manager sabe cuándo terminó.
#               Con $TERMINAL o xdg-terminal-exec depende de esa terminal.
#   --titulo    título de la pestaña o ventana (las que lo permiten)
#   --carpeta   carpeta en la que arranca el comando
# Reemplaza este proceso por el de la terminal (exec), así el pid es el de la terminal.
# Código de salida: 127 si no hay ninguna terminal, 2 error de uso.
# Pruebas: TERMINAL_CANDIDATAS cambia la lista de terminales a probar (separadas por espacios).

set -uo pipefail

esperar=no titulo="" carpeta="" cual=no
while (( $# )); do
    case "$1" in
        --esperar) esperar=si ;;
        --titulo)  [[ $# -ge 2 ]] || { echo "Falta el texto después de --titulo" >&2; exit 2; }; titulo=$2; shift ;;
        --carpeta) [[ $# -ge 2 ]] || { echo "Falta la carpeta después de --carpeta" >&2; exit 2; }; carpeta=$2; shift ;;
        --cual)    cual=si ;;
        --)        shift; break ;;
        *)         echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$cual" == si ]] || (( $# )) || { echo "Falta el comando a abrir en la terminal" >&2; exit 2; }

# La terminal que se usa: la primera de la lista que esté instalada. $TERMINAL (la que eligió el
# usuario, por ejemplo en sway o i3) va después de konsole porque el Manager es para KDE.
elegir() {
    local candidata primera
    for candidata in ${TERMINAL_CANDIDATAS:-konsole \$TERMINAL xdg-terminal-exec kgx gnome-terminal alacritty kitty xterm}; do
        if [[ "$candidata" == '$TERMINAL' ]]; then
            [[ -n "${TERMINAL:-}" ]] || continue
            read -r primera _ <<< "$TERMINAL"
            command -v "$primera" &>/dev/null && { printf '%s\n' '$TERMINAL'; return 0; }
        elif command -v "$candidata" &>/dev/null; then
            printf '%s\n' "$candidata"; return 0
        fi
    done
    return 1
}

if ! terminal=$(elegir); then
    echo "No se encontró ninguna terminal (konsole, xterm, alacritty, kitty, gnome-terminal...). Instalá una, por ejemplo: sudo pacman -S konsole" >&2
    exit 127
fi
if [[ "$cual" == si ]]; then
    if [[ "$terminal" == '$TERMINAL' ]]; then printf '%s\n' "$TERMINAL"; else printf '%s\n' "$terminal"; fi
    exit 0
fi

if [[ -n "$carpeta" ]]; then
    cd -- "$carpeta" || { echo "No existe la carpeta $carpeta" >&2; exit 2; }
fi

case "$terminal" in
    konsole)
        opciones=()
        [[ "$esperar" == si ]] && opciones+=(--nofork)
        [[ -n "$titulo" ]] && opciones+=(-p "tabtitle=$titulo")
        [[ -n "$carpeta" ]] && opciones+=(--workdir "$carpeta")
        exec konsole "${opciones[@]}" -e "$@" ;;
    '$TERMINAL')
        # La convención de casi todas las terminales (y de i3-sensible-terminal) es «-e comando»
        read -ra propia <<< "$TERMINAL"
        exec "${propia[@]}" -e "$@" ;;
    xdg-terminal-exec)
        exec xdg-terminal-exec "$@" ;;
    kgx)
        opciones=()
        [[ -n "$titulo" ]] && opciones+=(--title "$titulo")
        exec kgx "${opciones[@]}" -- "$@" ;;
    gnome-terminal)
        opciones=()
        [[ "$esperar" == si ]] && opciones+=(--wait)
        [[ -n "$titulo" ]] && opciones+=(--title "$titulo")
        exec gnome-terminal "${opciones[@]}" -- "$@" ;;
    alacritty)
        opciones=()
        [[ -n "$titulo" ]] && opciones+=(--title "$titulo")
        exec alacritty "${opciones[@]}" -e "$@" ;;
    kitty)
        opciones=()
        [[ -n "$titulo" ]] && opciones+=(--title "$titulo")
        exec kitty "${opciones[@]}" "$@" ;;
    xterm)
        opciones=()
        [[ -n "$titulo" ]] && opciones+=(-T "$titulo")
        exec xterm "${opciones[@]}" -e "$@" ;;
    *)
        # (TERMINAL_CANDIDATAS con una que no está en la lista de arriba: se prueba «-e»)
        exec "$terminal" -e "$@" ;;
esac
