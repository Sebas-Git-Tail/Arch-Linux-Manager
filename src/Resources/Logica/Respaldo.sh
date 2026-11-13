#!/bin/bash
# Lógica sin interfaz de los respaldos y la restauración con rsync al servidor (antes:
# Respaldo-Linux.sh, Restauración-Linux.sh, Respaldo-trabajo-Carina.sh y
# Minecraft/Respaldo.sh, con Ping.sh, Contraseña.sh, Rsync_Progreso.sh y Contador_Respaldos.sh).
#
# Uso: Respaldo.sh TIPO [--forzar]  < contraseña
#   TIPO      linux        tu carpeta personal → servidor (según la PC)
#             restauracion servidor → tu carpeta personal (no borra nada que no esté en el respaldo)
#             carina       trabajo de Carina (partición de Windows) → servidor
#             minecraft    servidores de Minecraft → servidor
#   --forzar  (minecraft) respalda aunque haya servidores encendidos
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
#   LISTO <texto>         terminó bien
#   ERROR <texto>         no se pudo (termina)
#
# Código de salida: 0 bien, 1 rsync falló, 2 error (uso, servidor, montaje),
# 3 contraseña incorrecta, 4 hay servidores de Minecraft encendidos (usar --forzar).

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $1"; exit "${2:-2}"; }

tipo="${1:-}"
forzar=no
[[ "${2:-}" == --forzar ]] && forzar=si
case "$tipo" in
    linux|restauracion|carina|minecraft) ;;
    *) error "Uso: Respaldo.sh linux|restauracion|carina|minecraft [--forzar]" ;;
esac

# Si no viene de la ventana, Common está al lado de esta carpeta (para usarlo desde la terminal)
COMMON="${COMMON:-$(dirname "$(realpath "$0")")/../Common}"
source "$COMMON/Servidor.sh"   # usuario, carpeta de respaldos, IPs y responde()
source "$COMMON/MAC.sh"        # es_maquina_...

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
SSH_OPCIONES="-o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Se prueba la contraseña contra el servidor (sshpass devuelve 5 si es incorrecta)
SSHPASS="$password" sshpass -e ssh $SSH_OPCIONES "$SERVIDOR" true 2>/dev/null
case $? in
    0) ;;
    5) error "Contraseña incorrecta." 3 ;;
    *) error "No se pudo conectar con el servidor ($DESTINO). Revisá la conexión y volvé a intentarlo." 1 ;;
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
             SSHPASS="$password" rsync -ah --info=progress2,name1 \
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
    # --delete borra en el servidor lo que ya no está acá; el filtro dice qué no copiar
    copiar "Respaldando" --delete \
        --filter="merge $COMMON/Rsync_Filtro.conf" \
        "${excluir_navegador[@]}" \
        "$HOME/" "$SERVIDOR:$SERVIDOR_RESPALDOS/$carpeta/" || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    contar "$HOME/.config/Manager/Contador_Respaldos.conf"
    emitir "LISTO Respaldo completado."
    ;;

restauracion)
    carpeta_linux
    emitir "DESTINO $DESTINO:$SERVIDOR_RESPALDOS/$carpeta → $HOME"
    # Sin --delete: no borra archivos que no estén en el respaldo
    copiar "Restaurando" "$SERVIDOR:$SERVIDOR_RESPALDOS/$carpeta/" "$HOME/" \
        || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    emitir "LISTO Restauración completada."
    ;;

carina)
    # Partición de Windows de Carina: si no está montada, se monta (pkexec pide permiso
    # con su propia ventana; un solo pedido para crear la carpeta y montar)
    ORIGEN="/run/media/carina/EC288BDE288BA5E4"
    if ! mountpoint -q "$ORIGEN"; then
        emitir "AVISO Montando la partición de Windows..."
        pkexec sh -c 'mkdir -p "$1" && mount -t ntfs /dev/sda5 "$1"' _ "$ORIGEN" \
            || error "No se pudo montar la partición de Windows."
    fi
    RUTA="$SERVIDOR_RESPALDOS/carina/Windows"
    emitir "DESTINO Windows de Carina → $DESTINO:$RUTA"
    # 1) La carpeta de usuario de Carina en Windows  2) La carpeta del programa S.I.Ap
    copiar "Respaldando el trabajo de Carina" --delete \
        "$ORIGEN/Usuarios/Carina/" "$SERVIDOR:$RUTA/Trabajo de Carina/" \
        || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    copiar "Respaldando S.I.Ap" --delete \
        "$ORIGEN/Program Files (x86)/S.I.Ap/" "$SERVIDOR:$RUTA/Trabajo de Carina/S.I.Ap/" \
        || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    contar "$HOME/.config/Manager/Contador_Respaldos_Carina.conf"
    emitir "LISTO Listo, que tenga un lindo día."
    ;;

minecraft)
    source "$(dirname "$(realpath "$0")")/Minecraft-comun.sh"   # MINECRAFT_DIR, listar_servidores_paper, pid_servidor...
    # Con un servidor encendido el mundo puede quedar a medio guardar en la copia
    if [[ "$forzar" == no ]]; then
        encendidos=()
        while IFS= read -r servidor; do
            [[ -n "$(pid_servidor "$(carpeta_servidor "$servidor")")" ]] && encendidos+=("$servidor")
        done < <(listar_servidores_paper)
        if (( ${#encendidos[@]} > 0 )); then
            emitir "ENCENDIDOS ${encendidos[*]}"
            exit 4
        fi
    fi
    emitir "DESTINO $MINECRAFT_DIR → $DESTINO:$SERVIDOR_RESPALDOS/sebastian/Minecraft"
    # No copia lo que Paper vuelve a descargar solo (cache, libraries, versions) ni los logs
    copiar "Respaldando Minecraft" --delete \
        --exclude="cache/" --exclude="libraries/" --exclude="versions/" --exclude="logs/" \
        "$MINECRAFT_DIR/" "$SERVIDOR:$SERVIDOR_RESPALDOS/sebastian/Minecraft/" \
        || error "rsync terminó con errores. Revisá la conexión con el servidor y volvé a intentarlo." 1
    emitir "LISTO Respaldo de Minecraft completado."
    ;;
esac
