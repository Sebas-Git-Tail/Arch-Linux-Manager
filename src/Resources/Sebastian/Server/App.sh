#!/bin/bash
# Publica una versión nueva de Arch-Linux-Manager en tu repositorio de pacman del servidor:
# por SSH corre ~/Repo/Scripts/publicar-paquete.sh, que compila el paquete, deja el anterior en
# ~/Repo/Legacy/Arch-Linux-Manager y lo agrega con repo-add a ~/Repo/Paquetes.
# Antes hay que subir pkgver/pkgrel en el PKGBUILD. La ventana principal (sección Servidor)
# lo abre dentro de konsole.

# Servidor: por la red de casa o, si no responde, por Tailscale
source "$COMMON/Servidor.sh"
if ! elegir_destino; then
    echo "No se encontró el servidor."
    read -rp "Presioná Enter para cerrar..."
    exit 1
fi

# bash -s: funciona aunque el shell de tu usuario allá sea fish. SSH_HUELLAS_SERVIDOR: solo se
# conecta si del otro lado está de verdad el servidor (huella en Common/known_hosts).
# shellcheck disable=SC2086
ssh $SSH_HUELLAS_SERVIDOR "$SERVIDOR_USUARIO@$DESTINO" bash -s <<'REMOTO'
set -euo pipefail
"$HOME/Repo/Scripts/publicar-paquete.sh" Arch-Linux-Manager
REMOTO
estado=$?

echo
if (( estado == 0 )); then
    echo "Paquete publicado. Actualizá con: sudo pacman -Syu"
else
    echo "La publicación falló (código $estado). El repositorio no se modificó."
fi
read -rp "Presioná Enter para cerrar..."
