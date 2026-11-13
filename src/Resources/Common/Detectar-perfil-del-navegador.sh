#!/bin/bash
# Se incluye con source desde Respaldo-Linux.sh. Averigua la carpeta del perfil de LibreWolf
# (para no respaldar su caché) y la deja en $PERFIL_LIBREWOLF.

# Lee profiles.ini y devuelve el perfil marcado como Default en la sección [Install...]
detectar_perfil_librewolf() {
    local archivo="$HOME/.config/librewolf/librewolf/profiles.ini"

    # Si el archivo no existe o no se puede leer, falla
    [[ -r "$archivo" ]] || return 1

    # awk entra en la sección [Install...], busca la línea Default= y muestra lo que está después del =
    awk -F= '
        /^\[Install/ { instalacion=1; next }
        /^\[/ { instalacion=0 }
        instalacion && /^Default=/ {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$archivo"
}

# Guarda el perfil y lo muestra por la terminal (o avisa si no lo encontró)
if PERFIL_LIBREWOLF=$(detectar_perfil_librewolf); then
    printf 'Perfil detectado: %s\n' "$PERFIL_LIBREWOLF"
else
    printf 'No se pudo detectar el perfil de LibreWolf.\n' >&2
fi
