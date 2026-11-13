# PKGBUILD de Arch-Linux-Manager: le dice a makepkg cómo armar el paquete (.pkg.tar.zst)
# que después se instala con pacman. Se construye con: makepkg -si
# Maintainer: Sebas-Git-Tail

# Datos del paquete: nombre, versión del programa (pkgver) y número de compilación
# de esa misma versión (pkgrel)
pkgname=Arch-Linux-Manager
pkgver=4.2.0
pkgrel=1
pkgdesc="A useful set of GUI scripts for Arch Linux"
# Ya no es «any»: la ventana Qt (gui/) se compila para cada procesador
arch=('x86_64' 'aarch64')
# Página del proyecto (tu servidor, por Tailscale) y licencia
url="https://archlinux.tail0dedb3.ts.net"
license=('LGPL-2.0-or-later')

# Programas que pacman instala sí o sí junto con el paquete
depends=(
    'bash'
    # ventana Qt del Manager (Arch-Linux-Manager-Qt)
    'qt6-base'
    # descarga de música y videos
    'yt-dlp'
    # lee la lista de subtítulos y pistas de audio que informa yt-dlp (Logica/Descargar.sh)
    'python'
    # respaldos y restauraciones
    'rsync'
    # le pasa la contraseña a ssh sin tener que escribirla
    'sshpass'
    # lo usa yt-dlp para incrustar la carátula y los datos en el audio
    'python-mutagen'
    # reproducir videos (tutoriales y descargas)
    'mpv'
    # terminal para Actualizar Arch, App, Playit y los servidores de Minecraft
    'konsole'
    # descargas
    'curl'
    'wget'
    # comprobar que los .jar de Paper y plugins no estén dañados
    'unzip'
    # ping, xdg-open, carpetas del usuario (Música, Vídeos...), ssh y pkexec
    'iputils'
    'xdg-utils'
    'xdg-user-dirs'
    'openssh'
    'polkit'
)

# Solo para compilar la ventana Qt (no hacen falta para usar el programa)
makedepends=('cmake' 'ninja')

# Opcional: sin Tailscale los respaldos solo funcionan dentro de la red de casa
optdepends=(
    'tailscale: Para los respaldos fuera de la red local'
    'android-tools: Sección Android (Celular: Apps FOSS y Debloat)'
    'waydroid: Opción Cerrar-Waydroid'
    'steam: Opción Steam Proton'
    'prismlauncher: Menú de Minecraft'
)

# Nombre que este paquete «provee» para pacman
provides=(Arch-Linux-Manager)

# Archivos que makepkg copia a src/ antes de empaquetar (nombre::ruta de origen)
source=(
    "Arch-Linux-Manager.sh::$startdir/Arch-Linux-Manager.sh"
    "Arch-Linux-Manager.desktop::$startdir/Arch-Linux-Manager.desktop"
)

# SKIP = no se verifica la suma de comprobación (son archivos locales)
sha256sums=('SKIP' 'SKIP')

# Compila la ventana Qt (los .ui de Qt Designer los convierte CMake solo).
# La compilación queda en src/build-gui, que «makepkg -c» también borra.
build() {
    cmake -B "$srcdir/build-gui" -S "$startdir/gui" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "$srcdir/build-gui"
}

# Arma, dentro de $pkgdir (una raíz falsa), las carpetas y archivos que van a quedar
# instalados en el sistema
package() {
    # Ventana Qt: /usr/bin/Arch-Linux-Manager-Qt (la abre Arch-Linux-Manager.sh)
    DESTDIR="$pkgdir" cmake --install "$srcdir/build-gui"

    # Carpeta de la app: /usr/share/Arch-Linux-Manager
    local appdir="$pkgdir/usr/share/Arch-Linux-Manager"

    # Directorios
    install -dm755 "$pkgdir/usr/bin"
    install -dm755 "$appdir"
    install -dm755 "$pkgdir/usr/share/applications"

    # Programa principal
    install -Dm755 "$srcdir/Arch-Linux-Manager.sh" \
        "$appdir/Arch-Linux-Manager.sh"

    # Todos los scripts, librerías y recursos locales
    # Ojo: Resources se toma de src/, que es la carpeta de trabajo de makepkg.
    # «makepkg -c» y «makepkg -C» borran src/, y con ella Resources.
    cp -a "$startdir/src/Resources" "$appdir/"

    # Acceso al programa
    # Crea el comando /usr/bin/Arch-Linux-Manager: un mini script que ejecuta el programa principal
    cat > "$pkgdir/usr/bin/Arch-Linux-Manager" <<'EOF'
#!/bin/bash
exec /usr/share/Arch-Linux-Manager/Arch-Linux-Manager.sh "$@"
EOF

    # Le da permiso de ejecución al comando
    chmod 755 "$pkgdir/usr/bin/Arch-Linux-Manager"

    # Menú de KDE Plasma
    # El .desktop es lo que hace que aparezca en el menú de aplicaciones
    install -Dm644 "$srcdir/Arch-Linux-Manager.desktop" \
        "$pkgdir/usr/share/applications/Arch-Linux-Manager.desktop"
}
