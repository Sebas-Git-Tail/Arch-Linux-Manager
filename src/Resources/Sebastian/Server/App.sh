#!/bin/bash
# Publica una versión nueva de Arch-Linux-Manager en tu repositorio de pacman del servidor:
# por SSH compila el paquete, mueve el anterior a Legacy y agrega el nuevo con repo-add.
# La ventana principal (sección Servidor) lo abre dentro de konsole.

# Servidor: por la red de casa o, si no responde, por Tailscale
source "$COMMON/Servidor.sh"
if ! elegir_destino; then
    echo "No se encontró el servidor."
    read -rp "Presioná Enter para cerrar..."
    exit 1
fi

# El bloque REMOTO se ejecuta en el servidor con bash (funciona aunque el shell de tu
# usuario allá sea fish). set -e: si un paso falla, se corta ahí y el repositorio queda
# como estaba.
ssh "$SERVIDOR_USUARIO@$DESTINO" bash -s <<'REMOTO'
set -euo pipefail
shopt -s nullglob

REPO="$HOME/Repo"
cd "$REPO/Desarrollo/Manager"

echo ">> Compilando..."
PACKAGER="Sebas-Git-Tail" makepkg -sf --noconfirm

# El paquete recién compilado (sin el de depuración)
nuevo=""
for p in $(ls -t ./*.pkg.tar.zst); do
    [[ "$p" == *-debug-* ]] && continue
    nuevo="$p"; break
done
[[ -n "$nuevo" ]] || { echo "No se encontró el paquete compilado."; exit 1; }

echo ">> Publicando $(basename "$nuevo")..."
mkdir -p "$REPO/Legacy"
viejos=("$REPO"/*.pkg.tar.zst)
(( ${#viejos[@]} )) && mv "${viejos[@]}" "$REPO/Legacy/"
mv "$nuevo" "$REPO/"

cd "$REPO"
repo-add Arch-Linux-Manager.db.tar.zst "$(basename "$nuevo")"
REMOTO
estado=$?

echo
if (( estado == 0 )); then
    echo "Paquete publicado. Actualizá con: sudo pacman -Syu"
else
    echo "La publicación falló (código $estado). El repositorio no se modificó."
fi
read -rp "Presioná Enter para cerrar..."
