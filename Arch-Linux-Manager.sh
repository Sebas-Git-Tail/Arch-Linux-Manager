#!/bin/bash
# Arch-Linux-Manager: programa principal (es lo que ejecuta el comando Arch-Linux-Manager).
# Prepara las rutas y abre la ventana Qt. Qué computadora es y si el servidor responde lo
# averigua la ventana con Logica/Entorno.sh (antes lo hacía este script con los menús Lista-*).

# Carpeta donde quedan instalados todos los scripts (se puede cambiar para probar sin
# instalar: BASE=~/Escritorio/Manager/src/Resources Arch-Linux-Manager)
BASE="${BASE:-/usr/share/Arch-Linux-Manager/Resources}"

# Tabla con las carpetas que usan los demás scripts (nombre de variable -> ruta)
declare -A rutas=(
    [BASE]="$BASE"
    [COMMON]="$BASE/Common"
    # lógica sin interfaz (la llaman la ventana Qt y los scripts de la interfaz)
    [LOGICA]="$BASE/Logica"
    [GENERAL]="$BASE/General"
    [SEBASTIAN]="$BASE/Sebastian"
)

# Exporta cada una como variable de entorno ($COMMON, $LOGICA...) para que la vean la
# ventana y los scripts que lanza
for ruta in "${!rutas[@]}"; do
    export "$ruta=${rutas[$ruta]}"
done

exec Arch-Linux-Manager-Qt "$@"
