#!/bin/bash
# Lógica sin interfaz de los respaldos y la restauración con rsync al servidor (antes:
# Respaldo-Linux.sh, Restauración-Linux.sh, Respaldo-trabajo-Carina.sh y
# Minecraft/Respaldo.sh, con Ping.sh, Contraseña.sh, Rsync_Progreso.sh y Contador_Respaldos.sh).
#
# Uso: Respaldo.sh TIPO [opciones]  < contraseña
#   TIPO      linux        tu carpeta personal → servidor (según la PC)
#             restauracion servidor → tu carpeta personal (no borra nada que no esté en el respaldo)
#             carina       trabajo de Carina (partición de Windows) → servidor
#             minecraft    servidores de Minecraft → servidor
#             anteriores   lista las copias anteriores del respaldo de esta PC (eventos ANTERIOR)
#   --forzar        (minecraft) respalda aunque haya servidores encendidos
#   --ruta RUTA     (restauracion) trae solo esa carpeta o archivo, relativa a tu carpeta personal
#                   (ej.: Documentos/Facturas). Sin --ruta se trae todo.
#   --desde FECHA   (restauracion) trae desde la copia anterior AAAA-MM-DD_HH-MM (las de
#                   «anteriores») en vez de la copia actual. «actual» es lo mismo que no ponerla.
#
# Copias anteriores (desde la 4.17.0): el respaldo sigue siendo una copia espejo (así la
# restauración y las versiones viejas siguen andando), pero lo que se borra o se pisa en el
# servidor no se pierde: rsync lo mueve a una carpeta HERMANA del destino,
# <destino>.anteriores/AAAA-MM-DD_HH-MM/ (por ejemplo sebastian/Linux.anteriores/2026-11-26_18-30/),
# que --delete no toca porque está afuera del destino. Al terminar se borran las de más de 30 días.
# La restauración nunca borra nada en esta PC: sin --delete, y lo que reemplaza queda guardado en
# ~/.local/share/Arch-Linux-Manager/antes-de-restaurar/<fecha>/.
# La contraseña SSH se lee de la primera línea de la entrada estándar: así nunca aparece
# en la lista de procesos ni en el historial.
#
# Eventos (stdout, uno por línea):
#   AVISO <texto>         información para mostrar
#   DESTINO <texto>       de dónde a dónde se copia
#   ETAPA <texto>         empieza una copia (Carina tiene dos)
#   ARCHIVO <ruta>        archivo que se está copiando
#   PROGRESO <0-100>      avance de la copia actual (solo cuando cambia)
#   ENCENDIDOS <lista>    (minecraft) servidores encendidos; termina con código 4
#   CONTADOR <n>          cantidad de respaldos hechos (después de uno exitoso)
#   ANTERIORES <n>        archivos que este respaldo borró o reemplazó en el servidor y quedaron
#                         en «anteriores» (después de uno exitoso)
#   ANTERIOR <fecha> <n>  (anteriores) una copia anterior y cuántos archivos tiene
#   GUARDADOS <n> <ruta>  (restauracion) archivos de esta PC que se reemplazaron y dónde quedaron
#   LISTO <texto>         terminó bien
#   ERROR <texto>         no se pudo (termina)
#
# Código de salida: 0 bien, 1 rsync falló, 2 error (uso, servidor, montaje),
# 3 contraseña incorrecta, 4 hay servidores de Minecraft encendidos (usar --forzar),
# 6 la huella del servidor no coincide (otro equipo contestó en su lugar).
#
# Historial: cada intento (bien, con error o cancelado) se anota en
# ~/.local/share/Arch-Linux-Manager/historial-respaldos.tsv, una línea por respaldo:
#   fecha (ISO)  tipo  resultado (ok|error|cancelado)  segundos  transferido  mensaje
# La ventana muestra los últimos en la página de cada respaldo.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { ultimo_mensaje="$1"; emitir "ERROR $1"; exit "${2:-2}"; }

tipo="${1:-}"
shift || true
forzar=no ruta="" desde=actual
while (( $# )); do
    case "$1" in
        --forzar) forzar=si ;;
        --ruta)   [[ $# -ge 2 ]] || error "Falta la carpeta o el archivo después de --ruta"; ruta=$2; shift ;;
        --desde)  [[ $# -ge 2 ]] || error "Falta la fecha después de --desde"; desde=$2; shift ;;
        *)        error "Opción desconocida: $1" ;;
    esac
    shift
done
case "$tipo" in
    linux|restauracion|carina|minecraft|anteriores) ;;
    *) error "Uso: Respaldo.sh linux|restauracion|carina|minecraft|anteriores [--forzar] [--ruta RUTA] [--desde FECHA]" ;;
esac
# La fecha de una copia anterior tiene un formato fijo (es el nombre de su carpeta en el servidor)
[[ "$desde" == actual || "$desde" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}$ ]] \
    || error "Fecha inválida: «$desde» (tiene que ser AAAA-MM-DD_HH-MM o «actual»)."
# La ruta a restaurar: relativa a tu carpeta personal, sin «..» (nunca sale de ahí)
if [[ -n "$ruta" ]]; then
    [[ "$tipo" == restauracion ]] || error "--ruta es solo para la restauración."
    ruta="${ruta#./}"
    while [[ "$ruta" == */ ]]; do ruta="${ruta%/}"; done
    if [[ -z "$ruta" || "$ruta" == /* || "$ruta" == *$'\n'* || "/$ruta/" == */../* || "/$ruta/" == */./* ]]; then
        error "Ruta inválida: «$ruta» (tiene que ser una carpeta o un archivo dentro de tu carpeta personal, sin «..»)."
    fi
fi

# --- Historial -----------------------------------------------------------------------------
HISTORIAL="${XDG_DATA_HOME:-$HOME/.local/share}/Arch-Linux-Manager/historial-respaldos.tsv"
inicio=$(date +%s)
ultimo_mensaje=""
transferido=""
cancelado=no
anotar_historial() {
    local codigo=$1 resultado
    # Minecraft con servidores encendidos (4) no es un intento: la ventana pregunta y repite.
    # Listar las copias anteriores tampoco es un respaldo.
    (( codigo == 4 )) && return
    [[ "$tipo" == anteriores ]] && return
    if [[ "$cancelado" == si ]]; then resultado=cancelado
    elif (( codigo == 0 )); then resultado=ok
    else resultado=error
    fi
    mkdir -p "$(dirname "$HISTORIAL")" 2>/dev/null || return
    # Sin tabuladores ni saltos de línea dentro de los campos
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$tipo" "$resultado" \
        "$(( $(date +%s) - inicio ))" "${transferido//[$'\t\n']/ }" "${ultimo_mensaje//[$'\t\n']/ }" >> "$HISTORIAL"
    # Solo los últimos 200
    if (( $(wc -l < "$HISTORIAL") > 200 )); then
        tail -n 200 "$HISTORIAL" > "$HISTORIAL.tmp" && mv -f "$HISTORIAL.tmp" "$HISTORIAL"
    fi
}
trap 'anotar_historial $?' EXIT
# Cancelar desde la ventana manda SIGTERM a todo el grupo
trap 'cancelado=si; ultimo_mensaje="Cancelado"; exit 130' TERM INT

# Si no viene de la ventana, Common está al lado de esta carpeta (para usarlo desde la terminal)
COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Servidor.sh"   # usuario, carpeta de respaldos, IPs, SSH_HUELLAS_SERVIDOR y responde()
source "$COMMON/Equipo.sh"     # es_maquina_... (elegido a mano o por la MAC)

# Contraseña SSH del servidor: se pide siempre (nada de claves SSH) y no se guarda en ningún
# lado, ni siquiera como hash. La comprueba el propio servidor más abajo, antes de copiar nada.
IFS= read -r password || password=""
[[ -n "$password" ]] || error "Contraseña incorrecta." 3

# Servidor: por la red de casa o, si no responde, por Tailscale
elegir_destino || error "No se encontró el servidor de Respaldos/Restauración (ni en la red de casa ni por Tailscale)."
[[ "$DESTINO" == "$SERVIDOR_IP_TAILSCALE" ]] && emitir "AVISO Conectando por Tailscale ($DESTINO)."

SERVIDOR="$SERVIDOR_USUARIO@$DESTINO"

# Solo contraseña: PubkeyAuthentication=no evita que ssh pruebe claves (si una tiene frase,
# sshpass se queda esperando para siempre). Un solo intento: si el servidor vuelve a pedir
# la contraseña, sshpass corta y devuelve 5.
# SSH_HUELLAS_SERVIDOR (Common/Servidor.sh): solo acepta al servidor si su huella coincide con
# Common/known_hosts. Antes se aceptaba cualquiera la primera vez, y desde una red
# ajena otro equipo podía hacerse pasar por el servidor y quedarse con la contraseña.
SSH_OPCIONES="-o PubkeyAuthentication=no -o PreferredAuthentications=password $SSH_HUELLAS_SERVIDOR -o ConnectTimeout=10"

# Se prueba la contraseña contra el servidor (sshpass devuelve 5 si es incorrecta)
# shellcheck disable=SC2086
salida_ssh=$(SSHPASS="$password" sshpass -e ssh $SSH_OPCIONES "$SERVIDOR" true 2>&1)
case $? in
    0) ;;
    5) error "Contraseña incorrecta." 3 ;;
    *) if [[ "$salida_ssh" == *"Host key verification failed"* || "$salida_ssh" == *"REMOTE HOST IDENTIFICATION HAS CHANGED"* ]]; then
           error "La huella del servidor ($DESTINO) no es la esperada: no se mandó la contraseña. Si reinstalaste el servidor, hay que actualizar Common/known_hosts (Scripts/actualizar-huellas-ssh.sh) y publicar una versión nueva." 6
       fi
       error "No se pudo conectar con el servidor ($DESTINO). Revisá la conexión y volvé a intentarlo." 1 ;;
esac

# Copia con rsync emitiendo ETAPA/ARCHIVO/PROGRESO. Devuelve el código de rsync.
# Uso: copiar "Etapa" [opciones de rsync...] ORIGEN DESTINO
copiar() {
    local etapa="$1"; shift
    local linea ultimo="" archivo=""
    emitir "ETAPA $etapa"

    # SSH_OPCIONES: solo contraseña y, la primera vez, acepta la huella del servidor (ver arriba).
    # --info=progress2: el porcentaje es de la copia completa; name1: nombre de cada archivo.
    # stdbuf -o0: sin esto tr junta la salida en bloques y el avance llega a saltos.
    while IFS= read -r linea; do
        if [[ "$linea" =~ ([0-9]+)%\  ]]; then
            if [[ "${BASH_REMATCH[1]}" != "$ultimo" ]]; then
                ultimo="${BASH_REMATCH[1]}"
                emitir "PROGRESO $ultimo"
            fi
        elif [[ "$linea" == rsync:* || "$linea" == "rsync error"* || "$linea" == *"Permission denied"* ]]; then
            # Archivos que no se pudieron copiar y errores de conexión
            emitir "AVISO $linea"
        elif [[ "$linea" =~ ^sent\ ([^ ]+)\ bytes\ +received\ ([^ ]+)\ bytes ]]; then
            # Resumen de rsync: para el historial
            if [[ "$tipo" == restauracion ]]; then
                transferido="${BASH_REMATCH[2]} recibidos"
            else
                transferido="${BASH_REMATCH[1]} enviados"
            fi
        elif [[ -n "$linea" && "$linea" != "sending incremental file list" \
                && "$linea" != "receiving incremental file list" \
                && "$linea" != "created directory "* \
                && "$linea" != "sent "* && "$linea" != "total size"* \
                && "$linea" != "./" && "$linea" != "$archivo" ]]; then
            archivo="$linea"
            emitir "ARCHIVO $archivo"
        fi
    # pipefail: el código que importa es el de rsync, no el de tr
    done < <(set -o pipefail
             SSHPASS="$password" rsync -ah --info=progress2,name1,stats1 \
                 -e "sshpass -e ssh $SSH_OPCIONES" \
                 "$@" 2>&1 | stdbuf -o0 tr '\r' '\n')
    wait $!
}

# Suma uno al contador de respaldos y marca que esta PC ya tiene uno (con Respaldos.conf
# no vacío, la ventana deja de ofrecer «Restauración-Linux»)
contar() {
    local archivo="$1" contador
    mkdir -p "$HOME/.config/Manager"
    echo "first-run=no" > "$HOME/.config/Manager/Respaldos.conf"
    contador=$(cat "$archivo" 2>/dev/null)
    [[ "$contador" =~ ^[0-9]+$ ]] || contador=0
    contador=$(( contador + 1 ))
    echo "$contador" > "$archivo"
    emitir "CONTADOR $contador"
}

# --- Copias anteriores ------------------------------------------------------------------------
# Una carpeta por respaldo, con la fecha y hora en que empezó (si hay dos en el mismo minuto, comparten)
FECHA_ANTERIORES=$(date +%Y-%m-%d_%H-%M)

# Opciones de rsync para que lo que se borra o se pisa en el destino vaya a la carpeta hermana
# <destino>.anteriores/<fecha>/. En rsync un --backup-dir relativo es relativo al destino.
# Deja las opciones en el arreglo ANTERIORES_RSYNC. Uso: anteriores_rsync NOMBRE_DESTINO [SUBCARPETA]
# NOMBRE_DESTINO es la última carpeta del destino; con SUBCARPETA el destino es NOMBRE/SUBCARPETA
# (S.I.Ap va adentro del trabajo de Carina) y sus copias van a NOMBRE.anteriores/<fecha>/SUBCARPETA.
anteriores_rsync() {
    if [[ -n "${2:-}" ]]; then
        ANTERIORES_RSYNC=(--backup "--backup-dir=../../$1.anteriores/$FECHA_ANTERIORES/$2")
    else
        ANTERIORES_RSYNC=(--backup "--backup-dir=../$1.anteriores/$FECHA_ANTERIORES")
    fi
}

# Después de un respaldo: cuenta lo que quedó en la copia anterior de hoy y borra las de más de
# 30 días. Corre en el servidor con la misma contraseña (sin permisos nuevos). Solo borra carpetas
# con nombre de fecha dentro de <destino>.anteriores. El guion va por la entrada estándar de
# «bash -s» (el usuario del servidor usa fish) y las rutas van con printf %q (las lee bash).
# Uso: revisar_anteriores RUTA_DE_LA_CARPETA_ANTERIORES
revisar_anteriores() {
    local carpeta="$1" salida n
    # shellcheck disable=SC2086
    salida=$(SSHPASS="$password" sshpass -e ssh $SSH_OPCIONES "$SERVIDOR" bash -s 2>/dev/null <<EOF
carpeta=$(printf '%q' "$carpeta")
fecha=$(printf '%q' "$FECHA_ANTERIORES")
n=0
[[ -d "\$carpeta/\$fecha" ]] && n=\$(find "\$carpeta/\$fecha" \( -type f -o -type l \) | wc -l)
limite=\$(date -d '30 days ago' +%Y-%m-%d_%H-%M)
for vieja in "\$carpeta"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]; do
    [[ -d "\$vieja" && "\${vieja##*/}" < "\$limite" ]] && rm -rf -- "\$vieja"
done
echo "ANTERIORES \$n"
EOF
)
    n=$(sed -n 's/^ANTERIORES \([0-9]\+\)$/\1/p' <<< "$salida" | tail -n1)
    if [[ -z "$n" ]]; then
        emitir "AVISO No se pudo revisar la carpeta de copias anteriores en el servidor."
        return
    fi
    emitir "ANTERIORES $n"
    if (( n > 0 )); then
        emitir "AVISO $n archivo(s) que este respaldo borró o reemplazó en el servidor quedaron en $carpeta/$FECHA_ANTERIORES (se guardan 30 días)."
        anteriores_mensaje=" $n archivo(s) borrados o cambiados quedaron en «anteriores»."
    else
        emitir "AVISO No se borró ni se reemplazó nada en el servidor."
    fi
}
anteriores_mensaje=""

# Carpeta del respaldo de esta PC en el servidor (la misma para respaldar y restaurar)
carpeta_linux() {
    local usuario
    usuario=$(whoami)
    if es_maquina_krocante; then
        carpeta="Krocante";            emitir "AVISO MAC Krocante detectada"
    elif es_maquina_instituto; then
        carpeta="$usuario/Instituto";  emitir "AVISO MAC Instituto detectada"
    else
        carpeta="$usuario/Linux";      emitir "AVISO Ninguna MAC detectada"
    fi
}

case "$tipo" in
linux)
    carpeta_linux
    # Caché del perfil de LibreWolf: no se respalda
    excluir_navegador=()
    if source "$COMMON/Detectar-perfil-del-navegador.sh" >/dev/null 2>&1 && [[ -n "${PERFIL_LIBREWOLF:-}" ]]; then
        excluir_navegador=(--exclude=".config/librewolf/librewolf/$PERFIL_LIBREWOLF/storage/")
    fi
    emitir "DESTINO $HOME → $DESTINO:$SERVIDOR_RESPALDOS/$carpeta"
    # --delete borra en el servidor lo que ya no está acá (lo borrado y lo pisado va a
    # <carpeta>.anteriores/<fecha>); el filtro dice qué no copiar
    anteriores_rsync "${carpeta##*/}"
    copiar "Respaldando" --delete "${ANTERIORES_RSYNC[@]}" \
        --filter="merge $COMMON/Rsync_Filtro.conf" \
        "${excluir_navegador[@]}" \
        "$HOME/" "$SERVIDOR:$SERVIDOR_RESPALDOS/$carpeta/" || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    contar "$HOME/.config/Manager/Contador_Respaldos.conf"
    revisar_anteriores "$SERVIDOR_RESPALDOS/$carpeta.anteriores"
    ultimo_mensaje="Respaldo completado.$anteriores_mensaje"
    emitir "LISTO $ultimo_mensaje"
    ;;

anteriores)
    # Copias anteriores del respaldo de esta PC (las carpetas con fecha de <carpeta>.anteriores),
    # de la más vieja a la más nueva, con cuántos archivos tiene cada una
    carpeta_linux
    # shellcheck disable=SC2086
    salida=$(SSHPASS="$password" sshpass -e ssh $SSH_OPCIONES "$SERVIDOR" bash -s 2>/dev/null <<EOF
carpeta=$(printf '%q' "$SERVIDOR_RESPALDOS/$carpeta.anteriores")
for copia in "\$carpeta"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]; do
    [[ -d "\$copia" ]] && printf 'ANTERIOR %s %s\n' "\${copia##*/}" "\$(find "\$copia" \( -type f -o -type l \) | wc -l)"
done
echo FIN
EOF
)
    grep -q '^FIN$' <<< "$salida" || error "No se pudo consultar las copias anteriores en el servidor." 1
    cantidad=0
    while read -r palabra fecha archivos; do
        if [[ "$palabra" == ANTERIOR && "$fecha" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}$ && "$archivos" =~ ^[0-9]+$ ]]; then
            emitir "ANTERIOR $fecha $archivos"
            (( cantidad++ ))
        fi
    done <<< "$salida"
    if (( cantidad == 0 )); then
        emitir "LISTO Todavía no hay copias anteriores (aparecen cuando un respaldo borra o cambia algo en el servidor)."
    else
        emitir "LISTO $cantidad copia(s) anterior(es)."
    fi
    ;;

restauracion)
    carpeta_linux
    # De dónde: la copia actual o una anterior (lo que un respaldo de esa fecha borró o reemplazó)
    if [[ "$desde" == actual ]]; then
        origen="$SERVIDOR_RESPALDOS/$carpeta"
    else
        origen="$SERVIDOR_RESPALDOS/$carpeta.anteriores/$desde"
    fi
    # Lo que se reemplaza en esta PC no se pierde: queda en antes-de-restaurar/<fecha> (afuera de lo
    # que se trae, así una restauración no se trae las copias de otra)
    GUARDADO_REL=".local/share/Arch-Linux-Manager/antes-de-restaurar"
    guardado="$HOME/$GUARDADO_REL/$(date +%Y-%m-%d_%H-%M-%S)"
    proteger=(--backup "--backup-dir=$guardado" "--exclude=/$GUARDADO_REL/")
    # Sin --delete: no borra nada de esta PC, aunque no esté en el respaldo
    if [[ -z "$ruta" ]]; then
        emitir "DESTINO $DESTINO:$origen → $HOME"
        copiar "Restaurando" "${proteger[@]}" "$SERVIDOR:$origen/" "$HOME/"
    else
        emitir "DESTINO $DESTINO:$origen/$ruta → $HOME/$ruta"
        # --relative con «/./»: recrea la ruta desde ese punto (sirve igual para carpetas y archivos)
        copiar "Restaurando $ruta" --relative "${proteger[@]}" "$SERVIDOR:$origen/./$ruta" "$HOME/"
    fi
    codigo_rsync=$?
    # Lo que se reemplazó acá (si no se reemplazó nada, la carpeta ni se crea)
    if [[ -d "$guardado" ]]; then
        guardados=$(find "$guardado" \( -type f -o -type l \) | wc -l)
        emitir "GUARDADOS $guardados $guardado"
        emitir "AVISO $guardados archivo(s) de esta PC se reemplazaron: la versión que tenías quedó en $guardado"
    fi
    if (( codigo_rsync == 23 )) && [[ -n "$ruta" ]]; then
        error "No se encontró «$ruta» en esa copia del respaldo (revisá el nombre: mayúsculas, tildes y espacios cuentan)." 1
    fi
    (( codigo_rsync == 0 )) || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    ultimo_mensaje="Restauración completada."
    [[ -n "$ruta" ]] && ultimo_mensaje="Restauración de $ruta completada."
    if [[ "$desde" != actual ]]; then
        hora="${desde#*_}"
        ultimo_mensaje+=" Se trajo desde la copia anterior del ${desde%_*} a las ${hora/-/:}."
    fi
    emitir "LISTO $ultimo_mensaje"
    ;;

carina)
    # Partición de Windows de Carina: si no está montada, se monta (pkexec pide permiso
    # con su propia ventana; un solo pedido para crear la carpeta y montar)
    # (RESPALDO_CARINA_ORIGEN: solo para las pruebas, una carpeta común en vez de la partición)
    ORIGEN="${RESPALDO_CARINA_ORIGEN:-/run/media/carina/EC288BDE288BA5E4}"
    if [[ -z "${RESPALDO_CARINA_ORIGEN:-}" ]] && ! mountpoint -q "$ORIGEN"; then
        emitir "AVISO Montando la partición de Windows..."
        pkexec sh -c 'mkdir -p "$1" && mount -t ntfs /dev/sda5 "$1"' _ "$ORIGEN" \
            || error "No se pudo montar la partición de Windows."
    fi
    RUTA="$SERVIDOR_RESPALDOS/carina/Windows"
    emitir "DESTINO Windows de Carina → $DESTINO:$RUTA"
    # 1) La carpeta de usuario de Carina en Windows  2) La carpeta del programa S.I.Ap
    # S.I.Ap va adentro de «Trabajo de Carina»: la primera copia no la toca (--exclude), si no su
    # --delete la borraba y la segunda la volvía a copiar entera (y ahora iría toda a «anteriores»).
    # Las dos dejan lo borrado o pisado en la misma copia anterior: Trabajo de Carina.anteriores/<fecha>/
    anteriores_rsync "Trabajo de Carina"
    copiar "Respaldando el trabajo de Carina" --delete "${ANTERIORES_RSYNC[@]}" --exclude=/S.I.Ap/ \
        "$ORIGEN/Usuarios/Carina/" "$SERVIDOR:$RUTA/Trabajo de Carina/" \
        || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    anteriores_rsync "Trabajo de Carina" S.I.Ap
    copiar "Respaldando S.I.Ap" --delete "${ANTERIORES_RSYNC[@]}" \
        "$ORIGEN/Program Files (x86)/S.I.Ap/" "$SERVIDOR:$RUTA/Trabajo de Carina/S.I.Ap/" \
        || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    contar "$HOME/.config/Manager/Contador_Respaldos_Carina.conf"
    revisar_anteriores "$RUTA/Trabajo de Carina.anteriores"
    ultimo_mensaje="Listo, que tenga un lindo día.$anteriores_mensaje"
    emitir "LISTO $ultimo_mensaje"
    ;;

minecraft)
    source "$(dirname "$(realpath "$0")")/Minecraft-comun.sh"   # MINECRAFT_DIR, listar_servidores_paper, pid_servidor...
    # Con un servidor encendido el mundo puede quedar a medio guardar en la copia
    if [[ "$forzar" == no ]]; then
        encendidos=()
        while IFS= read -r servidor; do
            [[ -n "$(pid_servidor "$(carpeta_servidor "$servidor")")" ]] && encendidos+=("$(nombre_visible "$servidor")")
        done < <(listar_servidores_paper)
        if (( ${#encendidos[@]} > 0 )); then
            emitir "ENCENDIDOS ${encendidos[*]}"
            exit 4
        fi
    fi
    emitir "DESTINO $MINECRAFT_DIR → $DESTINO:$SERVIDOR_RESPALDOS/sebastian/Minecraft"
    # No copia lo que Paper vuelve a descargar solo (cache, libraries, versions) ni los logs.
    # Lo borrado o pisado va a sebastian/Minecraft.anteriores/<fecha>
    anteriores_rsync Minecraft
    copiar "Respaldando Minecraft" --delete "${ANTERIORES_RSYNC[@]}" \
        --exclude="cache/" --exclude="libraries/" --exclude="versions/" --exclude="logs/" \
        "$MINECRAFT_DIR/" "$SERVIDOR:$SERVIDOR_RESPALDOS/sebastian/Minecraft/" \
        || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    revisar_anteriores "$SERVIDOR_RESPALDOS/sebastian/Minecraft.anteriores"
    ultimo_mensaje="Respaldo de Minecraft completado.$anteriores_mensaje"
    emitir "LISTO $ultimo_mensaje"
    ;;
esac
