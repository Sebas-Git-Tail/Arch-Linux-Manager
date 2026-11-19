#!/bin/bash
# Lógica sin interfaz de «Apps del AUR»: qué apps del AUR corresponden a este equipo, qué versión
# hay instalada y cuál hay en el AUR. Instalar lo hace General/AUR-instalar.sh en una terminal
# (makepkg pide la contraseña de sudo). La lista de apps y quién ve cada una: Common/AUR.sh.
#
# Uso: AUR.sh estado        las apps de este equipo con sus versiones
#      AUR.sh pendientes    las que están instaladas y tienen versión nueva (Actualizar Arch)
#
# Eventos (stdout, uno por línea; los campos van separados por tabulaciones):
#   APP <paquete> <nombre> <descripción> <instalada o vacío>     (primero todas, sin red)
#   AUR <paquete> <versión del AUR> NUEVA|AL_DIA|NO_INSTALADA      (después de consultar el AUR)
#   PENDIENTE <paquete>
#   ERROR <texto>
#
# Código de salida: 0 bien, 1 no se pudo consultar el AUR, 2 error de uso.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }

COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Equipo.sh"
source "$COMMON/AUR.sh"

paquetes=()
declare -A instalada=()
while IFS='|' read -r paquete nombre descripcion _; do
    paquetes+=("$paquete")
    instalada[$paquete]=$(aur_instalada "$paquete")
    [[ "${1:-}" == estado ]] && printf 'APP %s\t%s\t%s\t%s\n' "$paquete" "$nombre" "$descripcion" "${instalada[$paquete]}"
done < <(aur_apps_del_equipo)

case "${1:-}" in
estado)
    (( ${#paquetes[@]} )) || exit 0
    versiones=$(aur_versiones "${paquetes[@]}") || { emitir "ERROR No se pudo consultar el AUR (¿sin conexión?)."; exit 1; }
    while IFS=$'\t' read -r paquete version; do
        [[ -n "$paquete" ]] || continue
        actual=${instalada[$paquete]:-}
        if [[ -z "$actual" ]]; then
            estado=NO_INSTALADA
        elif (( $(vercmp "$version" "$actual") > 0 )); then
            estado=NUEVA
        else
            estado=AL_DIA
        fi
        printf 'AUR %s\t%s\t%s\n' "$paquete" "$version" "$estado"
    done <<< "$versiones"
    ;;

pendientes)
    # Solo las instaladas: Actualizar Arch no instala apps nuevas
    con_version=()
    for p in "${paquetes[@]}"; do
        [[ -n "${instalada[$p]}" ]] && con_version+=("$p")
    done
    (( ${#con_version[@]} )) || exit 0
    versiones=$(aur_versiones "${con_version[@]}") || { emitir "ERROR No se pudo consultar el AUR (¿sin conexión?)."; exit 1; }
    while IFS=$'\t' read -r paquete version; do
        [[ -n "$paquete" ]] || continue
        if (( $(vercmp "$version" "${instalada[$paquete]}") > 0 )); then
            emitir "PENDIENTE $paquete"
        fi
    done <<< "$versiones"
    ;;

*)
    emitir "ERROR Uso: AUR.sh estado | pendientes"
    exit 2
    ;;
esac
exit 0
