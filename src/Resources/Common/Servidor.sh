# Se incluye con source. Datos del servidor en un solo lugar: si cambia una IP,
# se cambia acá y lo toman los scripts de Logica/ y App.sh.

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
