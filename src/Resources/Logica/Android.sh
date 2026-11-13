#!/bin/bash
# Lógica sin interfaz de Android: celulares por adb y Waydroid (antes: Apps-FOSS.sh,
# Debloat-Clave.sh y Cerrar-Waydroid.sh).
#
# Uso: Android.sh dispositivos
#      Android.sh apps-foss [--serial S]
#      Android.sh debloat   [--serial S] [--nivel basico|intermedio|extremo] [--usuario U]
#      Android.sh cerrar-waydroid
# --serial elige el celular cuando hay más de uno conectado (los de «dispositivos»).
# --usuario elige a qué usuario de Android se le quitan las apps: el principal (0), el
#   segundo espacio, las apps duales, el perfil de trabajo... No hay una lista fija: se le
#   preguntan al celular (los informa «dispositivos»). Acepta uno (10), varios separados
#   por comas (0,10) o «todos».
# debloat sin --nivel o sin --usuario, desde una terminal (por ejemplo Termux), los pregunta
# (si el celular tiene un solo usuario, se usa ese sin preguntar).
#
# Eventos (stdout, uno por línea):
#   DISPOSITIVO <serial> <marca> <modelo>   celular conectado y autorizado
#   USUARIO <serial> <id> <nombre>          usuario de Android de ese celular (van después
#                                           de su DISPOSITIVO)
#   NOAUTORIZADO <serial>                   conectado, falta aceptar la depuración USB
#   AVISO <texto>
#   MARCA <marca>                           (debloat) marca detectada
#   PROGRESO <n> <total>                    avance (apps o paquetes)
#   INSTALADA <paquete> / DESINSTALADO <paquete> <usuario>
#   FALLO <paquete> [motivo]
#   LISTO <texto>                           terminó
#   ERROR <texto>                           no se pudo (termina)
#
# Código de salida: 0 bien, 1 falló algo, 2 error de uso o sin celular.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-2}"; }

comando="${1:-}"; shift || true
serial="" nivel="" usuario=""
while (( $# )); do
    case "$1" in
        --serial)  [[ $# -ge 2 ]] || error "Falta el serial después de --serial"; serial=$2; shift ;;
        --nivel)   [[ $# -ge 2 ]] || error "Falta el nivel después de --nivel"; nivel=$2; shift ;;
        --usuario) [[ $# -ge 2 ]] || error "Falta el usuario después de --usuario"; usuario=$2; shift ;;
        *)         error "Opción desconocida: $1" ;;
    esac
    shift
done

# adb para el celular elegido (sin --serial, adb usa el único conectado).
# La entrada va a /dev/null porque «adb shell» se traga todo lo que haya en la entrada
# estándar: dentro de un «while read» se comía el resto de las líneas (al listar los
# dispositivos, con dos celulares conectados solo aparecía el primero)
adb_cel() {
    if [[ -n "$serial" ]]; then adb -s "$serial" "$@" </dev/null; else adb "$@" </dev/null; fi
}

hay_celular() {
    adb_cel get-state &>/dev/null \
        || error "No hay ningún celular conectado por adb (o falta autorizar la depuración USB, o hay más de uno y no se eligió cuál)."
}

# Usuarios de Android del celular, uno por línea («id nombre»), tal como los informa el
# propio celular con «pm list users»: el principal (0) y los que tenga (segundo espacio,
# apps duales, perfil de trabajo...). Por eso el script no trae ninguna lista de usuarios.
listar_usuarios() {
    local linea
    while IFS= read -r linea; do
        # «UserInfo{10:Segundo espacio:410} running» -> «10 Segundo espacio»
        if [[ "$linea" =~ UserInfo\{([0-9]+):(.*):[0-9a-fA-F]+\} ]]; then
            printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        fi
    done < <(adb_cel shell pm list users 2>/dev/null | tr -d '\r')
}

case "$comando" in
dispositivos)
    while read -r s estado _; do
        case "$estado" in
            device)
                serial=$s
                marca=$(adb_cel shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
                modelo=$(adb_cel shell getprop ro.product.model 2>/dev/null | tr -d '\r')
                emitir "DISPOSITIVO $s ${marca:-?} ${modelo:-?}"
                # Sus usuarios: el debloat deja elegir a cuál quitarle las apps
                while IFS= read -r de_android; do
                    emitir "USUARIO $s $de_android"
                done < <(listar_usuarios)
                ;;
            unauthorized)
                emitir "NOAUTORIZADO $s" ;;
        esac
    done < <(adb devices 2>/dev/null | tail -n +2)
    ;;

apps-foss)
    # Apps libres a instalar: Fossify Camera y SD Maid SE
    paquetes=(org.fossify.camera eu.darken.sdmse)
    hay_celular
    temporal=$(mktemp -d)
    trap 'rm -rf "$temporal"' EXIT
    fallidas=0
    for i in "${!paquetes[@]}"; do
        paquete="${paquetes[$i]}"
        emitir "PROGRESO $i ${#paquetes[@]}"
        emitir "AVISO Instalando $paquete..."
        # La API de F-Droid indica qué versión recomienda (las viejas se borran del repositorio)
        version=$(curl -fsSL "https://f-droid.org/api/v1/packages/$paquete" | grep -o '"suggestedVersionCode": *[0-9]*' | grep -o '[0-9]*$')
        apk="${paquete}_${version}.apk"
        if [[ -z "$version" ]]; then
            emitir "FALLO $paquete no se encontró en F-Droid"; (( fallidas++ ))
        elif ! curl -fsSL "https://f-droid.org/repo/$apk" -o "$temporal/$apk"; then
            emitir "FALLO $paquete no se pudo descargar"; (( fallidas++ ))
        elif ! salida=$(adb_cel install -r "$temporal/$apk" 2>&1); then
            emitir "FALLO $paquete $(tail -n1 <<< "$salida")"; (( fallidas++ ))
        else
            emitir "INSTALADA $paquete"
        fi
    done
    emitir "PROGRESO ${#paquetes[@]} ${#paquetes[@]}"
    (( fallidas == 0 )) || error "No se pudieron instalar $fallidas app(s)." 1
    emitir "LISTO Apps instaladas."
    ;;

debloat)
    # Detecta dónde corre: en la PC (o Termux) pregunta la marca por adb; en la terminal
    # propia del celular (Toybox) la lee directo
    if [[ "$(uname -o)" == "GNU/Linux" || "$(uname -o)" == "Android" ]]; then
        hay_celular
        marca=$(adb_cel shell getprop ro.product.brand | tr -d '\r')
    else
        marca=$(getprop ro.product.brand)
    fi
    # Las listas están en minúscula y Redmi/POCO usan las de Xiaomi
    marca=${marca,,}
    marca=${marca//[^a-z0-9_]/}   # solo caracteres válidos en un nombre de variable
    case "$marca" in
        redmi|poco) marca="xiaomi" ;;
    esac
    [[ -n "$marca" ]] || error "No se pudo leer la marca del celular."
    emitir "MARCA $marca"

    # Nivel: por argumento; si no vino y hay terminal, se pregunta
    if [[ -z "$nivel" && -t 0 ]]; then
        read -rp "Escriba el nivel de debloteo que quiera ejecutar (Basico/Intermedio/Extremo): " nivel
    fi
    source "$(dirname "$(realpath "$0")")/Debloat-listas.sh"
    case "${nivel,,}" in
        basico)     lista_marca="recommended_$marca"; lista_comun=recommended ;;
        intermedio) lista_marca="advanced_$marca";    lista_comun=advanced ;;
        extremo)    lista_marca="expert_$marca";      lista_comun=expert ;;
        *)          error "Nivel inválido: usá basico, intermedio o extremo." ;;
    esac

    # La lista de la marca (si la marca no tiene, queda vacía) más la común a todas
    paquetes=()
    if declare -p "$lista_marca" &>/dev/null; then
        declare -n de_la_marca="$lista_marca"
        paquetes+=("${de_la_marca[@]}")
    fi
    declare -n comunes="$lista_comun"
    paquetes+=("${comunes[@]}")

    # Usuarios de Android del celular: se detectan en el momento (antes eran siempre el 0 y el 10)
    mapfile -t usuarios < <(listar_usuarios)
    (( ${#usuarios[@]} )) || error "No se pudieron detectar los usuarios de Android del celular."
    ids=("${usuarios[@]%% *}")
    declare -A nombre_de=()
    for de_android in "${usuarios[@]}"; do
        nombre_de[${de_android%% *}]=${de_android#* }
    done

    # Usuario: por argumento. Si no vino: con un solo usuario no hay nada que elegir; con
    # varios, si hay terminal, se muestran y se pregunta
    if [[ -z "$usuario" ]]; then
        if (( ${#ids[@]} == 1 )); then
            usuario=${ids[0]}
        elif [[ -t 0 ]]; then
            printf 'Usuarios de Android de este celular:\n' >&2
            printf '  %s\n' "${usuarios[@]}" >&2
            read -rp "Escriba el usuario al que quiera quitarle las apps (el número; varios separados por comas, o «todos»): " usuario
        fi
    fi
    elegidos=()
    if [[ "${usuario,,}" == todos ]]; then
        elegidos=("${ids[@]}")
    else
        IFS=', ' read -ra pedidos <<< "$usuario"
        for pedido in "${pedidos[@]}"; do
            [[ " ${ids[*]} " == *" $pedido "* ]] || error "El celular no tiene el usuario «$pedido» (tiene: ${ids[*]})."
            [[ " ${elegidos[*]} " == *" $pedido "* ]] || elegidos+=("$pedido")
        done
    fi
    (( ${#elegidos[@]} )) || error "Falta elegir el usuario de Android: usá --usuario con uno de los del celular (${ids[*]}) o «todos»."

    # Se desinstalan solo para los usuarios elegidos, sin borrarlas del sistema: un
    # restablecimiento de fábrica las devuelve
    declare -A quitadas=() sin_permiso=()
    for id_usuario in "${elegidos[@]}"; do
        quitadas[$id_usuario]=0
        emitir "AVISO Se quitan las apps del usuario $id_usuario (${nombre_de[$id_usuario]})."
    done
    for i in "${!paquetes[@]}"; do
        paquete="${paquetes[$i]}"
        emitir "PROGRESO $i ${#paquetes[@]}"
        for id_usuario in "${elegidos[@]}"; do
            [[ -z "${sin_permiso[$id_usuario]:-}" ]] || continue
            resultado=$(adb_cel shell pm uninstall --user "$id_usuario" "$paquete" 2>&1 | tr -d '\r')
            if [[ "$resultado" == Success* ]]; then
                emitir "DESINSTALADO $paquete $id_usuario"
                (( quitadas[$id_usuario]++ ))
            elif [[ "$resultado" == *SecurityException* ]]; then
                # Android no deja que adb toque a ese usuario (pasa con algunos perfiles de
                # trabajo): se avisa una sola vez y no se sigue probando con él
                sin_permiso[$id_usuario]=1
                emitir "FALLO usuario $id_usuario: Android no permite modificarlo por adb"
            fi
        done
    done
    emitir "PROGRESO ${#paquetes[@]} ${#paquetes[@]}"

    # Resumen: cuántas se quitaron de cada usuario (y a cuáles no se pudo entrar)
    resumen="" bloqueados=""
    for id_usuario in "${elegidos[@]}"; do
        if [[ -n "${sin_permiso[$id_usuario]:-}" ]]; then
            bloqueados+="$id_usuario, "
        else
            resumen+="${quitadas[$id_usuario]} del usuario $id_usuario, "
        fi
    done
    resumen=${resumen%, }
    [[ -z "$bloqueados" ]] \
        || error "Android no permite quitar apps por adb en el usuario ${bloqueados%, }.${resumen:+ Apps quitadas: $resumen.}" 1
    emitir "LISTO Debloat $nivel terminado. Apps quitadas: $resumen (de las ${#paquetes[@]} de la lista; las demás no estaban instaladas)."
    ;;

cerrar-waydroid)
    # Termina la sesión de Android y detiene el contenedor (este paso pide permisos)
    waydroid session stop &>/dev/null
    pkexec waydroid container stop || error "No se pudo detener el contenedor de Waydroid." 1
    emitir "LISTO Waydroid cerrado."
    ;;

*)
    error "Uso: Android.sh dispositivos | apps-foss | debloat | cerrar-waydroid [--serial S] [--nivel N] [--usuario U]"
    ;;
esac
