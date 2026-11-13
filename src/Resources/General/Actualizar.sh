#!/bin/bash
# Actualiza todo el sistema con pacman. -Syyuu: refresca las bases de datos aunque estén al día
# y actualiza, permitiendo bajar de versión si hace falta.
# La ventana principal lo abre dentro de konsole (pacman puede hacer preguntas, como
# conflictos o qué paquete elegir, y en una terminal se contestan).

COMANDO=(pacman -Syyuu)

# pkexec pide la contraseña en una ventana; si no está, sudo la pide en la terminal
if command -v pkexec &>/dev/null; then
    pkexec "${COMANDO[@]}"
else
    sudo "${COMANDO[@]}"
fi
estado=$?

echo
if (( estado == 0 )); then
    echo "Actualización terminada."
else
    echo "La actualización terminó con errores (código $estado)."
fi
read -rp "Presioná Enter para cerrar..."
