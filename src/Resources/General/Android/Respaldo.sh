#!/bin/bash
# Respaldo del celular: se ejecuta en el propio celular (por ejemplo desde Termux) y copia el
# almacenamiento interno al servidor con rsync, sin las carpetas de datos de las apps.


# Este script corre solo en el celular (sin el resto del Manager), así que no puede usar
# Common/Servidor.sh. Los valores de abajo son los de fábrica (los mismos que Servidor.sh) y,
# si hay internet, se reemplazan por los de servidor.json. Sin python en Termux: se leen con sed.
DESTINO_LOCAL="192.168.100.14"
DESTINO_TAILSCALE="100.101.213.44"
USUARIO="sebastian"
RESPALDOS="/home/sebastian/Respaldos"
DESTINO=""

campo() {   # $1 = clave, $2 = caracteres válidos
    printf '%s' "$config" | sed -n "s#.*\"$1\": *\"\([$2]*\)\".*#\\1#p" | head -n1
}
if config=$(curl -fsS -m 3 https://bodrio.seb-dev.fyi/recursos/servidor.json 2>/dev/null); then
    v=$(campo ip_local '0-9.');            [ -n "$v" ] && DESTINO_LOCAL="$v"
    v=$(campo ip_tailscale '0-9.');        [ -n "$v" ] && DESTINO_TAILSCALE="$v"
    v=$(campo usuario 'a-z0-9_-');         [ -n "$v" ] && USUARIO="$v"
    v=$(campo respaldos 'A-Za-z0-9._/-');  [ -n "$v" ] && RESPALDOS="$v"
fi

# Elige la IP del servidor: la de casa si su SSH contesta o, si no, la de Tailscale.
# Se prueba el puerto 22 y no un ping: fuera de casa otro aparato puede tener la misma IP.
ssh_abierto() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/22" 2>/dev/null; }
if ssh_abierto "$DESTINO_LOCAL"; then
    DESTINO="$DESTINO_LOCAL"
elif ssh_abierto "$DESTINO_TAILSCALE"; then
    DESTINO="$DESTINO_TAILSCALE"
else
    echo "No se encontró el servidor de respaldo."
    exit 1
fi

# La carpeta de destino lleva el modelo del celular
Modelo=$(getprop ro.product.model)
Ruta="$RESPALDOS/sebastian/$Modelo/"

echo "Respaldo hacia $Ruta"

# Copia /sdcard (sin Android/obb ni Android/data) y borra en el servidor lo que ya no esté en el celular
rsync -avh --progress \
--exclude Android/obb \
--exclude Android/data \
--delete /sdcard/ \
"$USUARIO@$DESTINO:$Ruta"
