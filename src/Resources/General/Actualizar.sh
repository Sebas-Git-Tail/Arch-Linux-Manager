#!/bin/bash
# Actualiza todo el sistema con pacman. -Syyuu: refresca las bases de datos aunque estén al día
# y actualiza, permitiendo bajar de versión si hace falta.
# La ventana principal lo abre dentro de konsole (pacman puede hacer preguntas, como
# conflictos o qué paquete elegir, y en una terminal se contestan).
# Al final actualiza también las apps del AUR de este equipo que ya estén instaladas y tengan
# versión nueva (Logica/AUR.sh y General/AUR-instalar.sh); no instala apps nuevas.

COMANDO=(pacman -Syyuu)

# pkexec pide la contraseña en una ventana; si no está, sudo la pide en la terminal
if command -v pkexec &>/dev/null; then
    pkexec "${COMANDO[@]}"
else
    sudo "${COMANDO[@]}"
fi
estado=$?

# Apps del AUR (Claude, Equibop...): solo si pacman terminó bien
if (( estado == 0 )); then
    RECURSOS="$(dirname "$(realpath "$0")")/.."
    export COMMON="${COMMON:-$RECURSOS/Common}"
    echo
    echo "Buscando versiones nuevas de las apps del AUR…"
    salida=$(bash "${LOGICA:-$RECURSOS/Logica}/AUR.sh" pendientes)
    codigo=$?
    pendientes=$(sed -n 's/^PENDIENTE //p' <<< "$salida")
    if (( codigo != 0 )); then
        echo "No se pudo consultar el AUR (¿sin conexión?): las apps del AUR quedan como estaban."
    elif [[ -n "$pendientes" ]]; then
        # shellcheck disable=SC2086  # un paquete por palabra
        bash "${GENERAL:-$RECURSOS/General}/AUR-instalar.sh" --sin-pausa $pendientes || estado=$?
    else
        echo "Las apps del AUR están al día."
    fi
fi

echo
if (( estado == 0 )); then
    echo "Actualización terminada."
else
    echo "La actualización terminó con errores (código $estado)."
fi
read -rp "Presioná Enter para cerrar..."
