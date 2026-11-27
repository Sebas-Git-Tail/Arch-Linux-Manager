#!/bin/bash
# Instala o actualiza apps del AUR sin yay ni paru. Lo abre en una terminal (konsole u otra) la página «Apps del AUR»
# y también Actualizar.sh al final (con --sin-pausa). Para cada paquete:
#   1. baja del AUR la carpeta del paquete (PKGBUILD y lo que lo acompaña);
#   2. en las computadoras de Sebastián muestra qué cambió desde la última instalación y pregunta
#      (el AUR lo mantienen usuarios: así se ve si alguien metió algo raro);
#   3. lo arma e instala con makepkg -si (pide la contraseña de sudo) y borra lo descargado.
#
# Uso: AUR-instalar.sh [--sin-pausa] paquete...
# Solo acepta las apps de este equipo (Common/AUR.sh). Código de salida: 0 todas bien, 1 alguna
# falló, 2 error de uso.

set -uo pipefail

COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Equipo.sh"
source "$COMMON/AUR.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/Arch-Linux-Manager/aur"
# Copia de lo último que se instaló de cada paquete, para mostrar qué cambió la próxima vez
GUARDADOS="${XDG_DATA_HOME:-$HOME/.local/share}/Arch-Linux-Manager/aur"

pausa=1
if [[ "${1:-}" == --sin-pausa ]]; then
    pausa=0
    shift
fi

terminar() {
    echo
    echo "$1"
    (( pausa )) && read -rp "Presioná Enter para cerrar..."
    exit "$2"
}

(( EUID != 0 )) || terminar "No se puede usar como root (makepkg no lo permite)." 2
(( $# )) || terminar "No se eligió ninguna app." 2
for p; do
    aur_permitido "$p" || terminar "«$p» no es una de las apps del AUR de esta computadora." 2
done

# sudo pide la contraseña en la terminal (y makepkg también lo usa); si no está, pkexec
como_root() {
    if command -v sudo &>/dev/null; then sudo "$@"; else pkexec "$@"; fi
}

# Lo que makepkg necesita y no viene con Arch: fakeroot, debugedit (paquetes de depuración) y
# strip (está en binutils; casi siempre ya está instalado)
faltan=()
command -v fakeroot &>/dev/null || faltan+=(fakeroot)
command -v debugedit &>/dev/null || faltan+=(debugedit)
command -v strip &>/dev/null || faltan+=(binutils)
if (( ${#faltan[@]} )); then
    echo "Para armar paquetes del AUR hace falta instalar: ${faltan[*]}"
    como_root pacman -S --needed --noconfirm "${faltan[@]}" || terminar "No se pudo instalar ${faltan[*]}." 1
    echo
fi

# Muestra lo que cambió en la carpeta del paquete desde la última instalación (o todo, la
# primera vez) y pregunta. Verdadero si se acepta.
revisar() {
    local paquete=$1 carpeta=$2 anterior="$GUARDADOS/$1" respuesta pagina=(cat)
    command -v less &>/dev/null && pagina=(less -RFX)
    if [[ -d "$anterior" ]]; then
        if diff -rqN --exclude=.SRCINFO "$anterior" "$carpeta" >/dev/null; then
            echo "No cambió nada desde la última vez que lo instalaste."
        else
            echo "Cambios desde la última vez que lo instalaste (en verde lo nuevo):"
            diff -ruN --color=always --exclude=.SRCINFO "$anterior" "$carpeta" | "${pagina[@]}"
        fi
    else
        echo "Es la primera vez que se instala desde el Manager. Este es el PKGBUILD:"
        "${pagina[@]}" "$carpeta/PKGBUILD"
    fi
    echo
    read -rp "¿Instalar $(aur_nombre "$paquete")? [S/n] " respuesta
    [[ -z "$respuesta" || "$respuesta" =~ ^[sSyY] ]]
}

# Baja la carpeta del paquete del AUR (hasta 3 intentos: a veces llega cortada)
bajar() {
    local paquete=$1 intento
    for intento in 1 2 3; do
        rm -rf "${CACHE:?}/$paquete" "$CACHE/$paquete.tar.gz"
        if curl -fsSL --retry 2 -m 60 -o "$CACHE/$paquete.tar.gz" "$AUR_URL/cgit/aur.git/snapshot/$paquete.tar.gz" \
            && gzip -t "$CACHE/$paquete.tar.gz" 2>/dev/null \
            && tar -xzf "$CACHE/$paquete.tar.gz" -C "$CACHE" && [[ -f "$CACHE/$paquete/PKGBUILD" ]]; then
            return 0
        fi
        (( intento < 3 )) && sleep 2
    done
    return 1
}

mkdir -p "$CACHE" "$GUARDADOS"
bien=()
mal=()
for paquete in "$@"; do
    nombre=$(aur_nombre "$paquete")
    echo "════ $nombre ($paquete) ════"
    carpeta="$CACHE/$paquete"
    archivo="$CACHE/$paquete.tar.gz"
    rm -rf "$carpeta" "$archivo"

    echo "Bajando el paquete del AUR…"
    if ! bajar "$paquete"; then
        echo "✗ No se pudo bajar $paquete del AUR."
        mal+=("$nombre")
        rm -rf "$carpeta" "$archivo"
        echo
        continue
    fi

    if [[ "$(equipo_actual)" == pc || "$(equipo_actual)" == instituto ]] && ! revisar "$paquete" "$carpeta"; then
        echo "No se instaló $nombre."
        rm -rf "$carpeta" "$archivo"
        echo
        continue
    fi

    # makepkg -s instala las dependencias (todas están en los repositorios de Arch) y arma el
    # paquete; -c borra la carpeta de trabajo al terminar. No se usa -i porque instalaría también
    # el paquete -debug que arma makepkg: se instala solo el principal. PKGDEST y SRCDEST: todo
    # queda en la carpeta del paquete, aunque makepkg.conf diga otra cosa.
    armados=()
    if (cd "$carpeta" && PKGDEST="$carpeta" SRCDEST="$carpeta" makepkg -sc --noconfirm); then
        mapfile -t armados < <(cd "$carpeta" && PKGDEST="$carpeta" makepkg --packagelist 2>/dev/null \
                                   | grep -v -- "/$paquete-debug-" | while IFS= read -r f; do [[ -f "$f" ]] && echo "$f"; done)
    fi
    if (( ${#armados[@]} )) && echo "Instalando $nombre…" && como_root pacman -U --noconfirm "${armados[@]}"; then
        echo "✓ $nombre instalado."
        bien+=("$nombre")
        rm -rf "${GUARDADOS:?}/$paquete"
        tar -xzf "$archivo" -C "$GUARDADOS"
    else
        echo "✗ No se pudo armar o instalar $nombre."
        mal+=("$nombre")
    fi
    # Lo descargado (.deb, .tar.gz) y el paquete armado ya no hacen falta
    rm -rf "$carpeta" "$archivo"
    echo
done

unir() { local IFS=,; printf '%s' "$*" | sed 's/,/, /g'; }
resumen=""
(( ${#bien[@]} )) && resumen+="Listo: $(unir "${bien[@]}")."
(( ${#mal[@]} )) && resumen+="${resumen:+ }Fallaron: $(unir "${mal[@]}")."
[[ -n "$resumen" ]] || resumen="No se instaló nada."
if (( ${#mal[@]} )); then
    terminar "$resumen" 1
fi
terminar "$resumen" 0
