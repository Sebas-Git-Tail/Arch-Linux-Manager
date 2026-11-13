#!/bin/bash
# Respaldo del celular: se ejecuta en el propio celular (por ejemplo desde Termux) y copia el
# almacenamiento interno al servidor con rsync, sin las carpetas de datos de las apps.


DESTINO_LOCAL="192.168.100.14"
DESTINO_TAILSCALE="100.101.213.44"
DESTINO=""

# Si hay internet, toma las IPs actuales de servidor.json (las mismas que usan los Manager).
# Sin python en Termux: se leen con sed. Si no se puede, quedan las de arriba.
if config=$(curl -fsS -m 3 https://bodrio.seb-dev.fyi/recursos/servidor.json 2>/dev/null); then
    ip=$(printf '%s' "$config" | sed -n 's/.*"ip_local": *"\([0-9.]*\)".*/\1/p')
    [ -n "$ip" ] && DESTINO_LOCAL="$ip"
    ip=$(printf '%s' "$config" | sed -n 's/.*"ip_tailscale": *"\([0-9.]*\)".*/\1/p')
    [ -n "$ip" ] && DESTINO_TAILSCALE="$ip"
fi

# Elige la IP del servidor: la de casa o, si no responde, la de Tailscale
if ping -c1 -W1 "$DESTINO_LOCAL" >/dev/null 2>&1; then
    DESTINO="$DESTINO_LOCAL"
elif ping -c1 -W1 "$DESTINO_TAILSCALE" >/dev/null 2>&1; then
    DESTINO="$DESTINO_TAILSCALE"
else
    echo "No se encontró el servidor de respaldo."
    exit 1
fi

# La carpeta de destino lleva el modelo del celular
Modelo=$(getprop ro.product.model)
Ruta="/home/sebastian/Respaldos/sebastian/$Modelo/"

echo "Respaldo hacia $Ruta"

# Copia /sdcard (sin Android/obb ni Android/data) y borra en el servidor lo que ya no esté en el celular
rsync -avh --progress \
--exclude Android/obb \
--exclude Android/data \
--delete /sdcard/ \
sebastian@$DESTINO:"$Ruta"
