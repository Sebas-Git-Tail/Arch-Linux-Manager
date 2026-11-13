# shellcheck shell=bash
# Se incluye con source. Datos del servidor en un solo lugar.
#
# Los valores de abajo son los de fábrica. Encima se cargan los de
# https://bodrio.seb-dev.fyi/recursos/servidor.json (los mismos que leen Android-Manager,
# Windows-Manager y Bodrio Supremo): si cambia una IP, se cambia en ese archivo del servidor y
# todos los programas lo toman solos, sin publicar versiones nuevas. Se descarga a lo sumo una vez
# por día y se guarda la última copia en ~/.cache/Arch-Linux-Manager/servidor.json, así que sin
# internet se sigue usando lo último que se bajó.
#
# Que alguien cambie ese archivo no alcanza para robar la contraseña de los respaldos: ssh solo
# acepta al servidor si su huella coincide con Common/known_hosts (ver SSH_HUELLAS_SERVIDOR).

# Usuario y carpeta de respaldos en el servidor
SERVIDOR_USUARIO="sebastian"
SERVIDOR_RESPALDOS="/home/sebastian/Respaldos"

# IPv4 por las que se conecta rsync/ssh
SERVIDOR_IP_LOCAL="192.168.100.14"
SERVIDOR_IP_TAILSCALE="100.101.213.44"

# Servidor web (tutoriales y archivos)
SERVIDOR_WEB_LOCAL="http://192.168.100.14:8080"
SERVIDOR_WEB_TAILSCALE="https://archlinux.tail0dedb3.ts.net"
SERVIDOR_HOST_TAILSCALE="archlinux.tail0dedb3.ts.net"

SERVIDOR_CONFIG_URL="${SERVIDOR_CONFIG_URL:-https://bodrio.seb-dev.fyi/recursos/servidor.json}"
SERVIDOR_CONFIG_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/Arch-Linux-Manager/servidor.json"

# Opciones de ssh para no aceptar a cualquier equipo: las huellas están en Common/known_hosts con
# un nombre fijo (HostKeyAlias), así siguen valiendo aunque cambie la IP.
_COMMON_SERVIDOR="${COMMON:-$(dirname "${BASH_SOURCE[0]}")}"
SSH_HUELLAS="-o UserKnownHostsFile=$_COMMON_SERVIDOR/known_hosts -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes -o UpdateHostKeys=no"
SSH_HUELLAS_SERVIDOR="$SSH_HUELLAS -o HostKeyAlias=servidor-respaldos"

# Baja servidor.json si la copia guardada tiene más de un día (3 segundos como máximo) y carga
# sus valores. Solo acepta los campos conocidos y con el formato esperado (IPs, URLs, rutas):
# lo demás se ignora. SERVIDOR_SIN_RED=1 no descarga nada (lo usan las pruebas).
cargar_config_servidor() {
    local cache="$SERVIDOR_CONFIG_CACHE" asignaciones
    command -v python3 &>/dev/null || return 0
    if [[ "${SERVIDOR_SIN_RED:-}" != 1 ]] && { [[ ! -s "$cache" ]] || [[ -n "$(find "$cache" -mmin +1440 2>/dev/null)" ]]; }; then
        mkdir -p "$(dirname "$cache")" 2>/dev/null
        if curl -fsS -m 3 "$SERVIDOR_CONFIG_URL" -o "$cache.tmp" 2>/dev/null \
                && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$cache.tmp" 2>/dev/null; then
            mv -f "$cache.tmp" "$cache"
        else
            rm -f "$cache.tmp"
            [[ -f "$cache" ]] && touch "$cache"    # no reintentar en cada script durante el día
        fi
    fi
    [[ -s "$cache" ]] || return 0
    asignaciones=$(python3 - "$cache" <<'PY' 2>/dev/null
import json, re, shlex, sys
try:
    datos = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
if not isinstance(datos, dict) or datos.get("version") != 1:
    sys.exit(0)
ip = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
url = re.compile(r"^https?://[A-Za-z0-9.\-]+(:\d+)?(/[A-Za-z0-9._~%/\-]*)?$")
host = re.compile(r"^[A-Za-z0-9.\-]+$")
ruta = re.compile(r"^/[A-Za-z0-9._/\-]+$")
usuario = re.compile(r"^[a-z_][a-z0-9_\-]*$")
campos = {
    "usuario": ("SERVIDOR_USUARIO", usuario),
    "respaldos": ("SERVIDOR_RESPALDOS", ruta),
    "ip_local": ("SERVIDOR_IP_LOCAL", ip),
    "ip_tailscale": ("SERVIDOR_IP_TAILSCALE", ip),
    "web_local": ("SERVIDOR_WEB_LOCAL", url),
    "web_tailscale": ("SERVIDOR_WEB_TAILSCALE", url),
    "host_tailscale": ("SERVIDOR_HOST_TAILSCALE", host),
}
for clave, (variable, formato) in campos.items():
    valor = datos.get(clave)
    if isinstance(valor, str) and formato.match(valor):
        print(f"{variable}={shlex.quote(valor)}")
PY
)
    [[ -n "$asignaciones" ]] && eval "$asignaciones"
    return 0
}
cargar_config_servidor

# Responde verdadero si la dirección contesta un ping (1 intento, 1 segundo)
responde() {
    ping -c1 -W1 "$1" &>/dev/null
}

# Verdadero si se puede abrir una conexión TCP a host:puerto (2 segundos como máximo)
puerto_abierto() {
    timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

# Deja en $DESTINO la IP por la que se llega al servidor: la de casa si su SSH contesta,
# si no la de Tailscale. Devuelve falso si no contesta ninguna.
# Se prueba el puerto de SSH de la misma IP que se va a usar: antes se hacía ping a la
# IPv6 pública del servidor, que contesta desde cualquier lugar, y fuera de casa se
# elegía igual la IP de casa (192.168.100.14) y la conexión fallaba.
elegir_destino() {
    if puerto_abierto "$SERVIDOR_IP_LOCAL" 22; then
        DESTINO="$SERVIDOR_IP_LOCAL"
    elif puerto_abierto "$SERVIDOR_IP_TAILSCALE" 22; then
        DESTINO="$SERVIDOR_IP_TAILSCALE"
    else
        return 1
    fi
}
