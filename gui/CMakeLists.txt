# Ventana Qt de Arch-Linux-Manager. Se compila con:
#   cmake -B build -S . -G Ninja && cmake --build build
# El PKGBUILD la compila e instala sola (queda en /usr/bin/Arch-Linux-Manager-Qt).
# Los .ui se editan con Qt Designer (/usr/lib/qt6/bin/designer).

cmake_minimum_required(VERSION 3.21)
project(ArchLinuxManager LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# moc y uic automáticos: cada .ui de Qt Designer se convierte solo en ui_<Nombre>.h
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)

# Network tiene que buscarse antes de comun
find_package(Qt6 REQUIRED COMPONENTS Widgets Network)

# Versión del programa: la pasa el PKGBUILD (-DVERSION_PROGRAMA=$pkgver-$pkgrel); la usa el actualizador
set(VERSION_PROGRAMA "0.0.0" CACHE STRING "Versión del programa (pkgver-pkgrel)")

# Código compartido con Android-Manager y Windows-Manager (repo comun-qt, traído con git subtree a
# ../comun): el diálogo de pistas de audio, subtítulos y calidad de Descargar Vídeos.
set(COMUN_DESCARGAS ON)
set(COMUN_APPS_WIDGETS ON)   # actualizarse sola e instalar las otras apps (comun/apps)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../comun ${CMAKE_CURRENT_BINARY_DIR}/comun)

add_executable(Arch-Linux-Manager-Qt
    main.cpp
    Acciones.cpp Acciones.h
    VentanaPrincipal.cpp VentanaPrincipal.h VentanaPrincipal.ui
    PaginaDescargas.cpp PaginaDescargas.h PaginaDescargas.ui
    PaginaRespaldo.cpp PaginaRespaldo.h PaginaRespaldo.ui
    PaginaSteam.cpp PaginaSteam.h PaginaSteam.ui
    PaginaAndroid.cpp PaginaAndroid.h PaginaAndroid.ui
    PaginaMinecraft.cpp PaginaMinecraft.h PaginaMinecraft.ui
    AsistenteMinecraft.cpp AsistenteMinecraft.h
    PaginaTutoriales.cpp PaginaTutoriales.h PaginaTutoriales.ui
    PaginaNotificacion.cpp PaginaNotificacion.h PaginaNotificacion.ui
    PaginaAUR.cpp PaginaAUR.h
    ProcesoLogica.cpp ProcesoLogica.h
)
target_link_libraries(Arch-Linux-Manager-Qt PRIVATE Qt6::Widgets comun_descargas comun_apps_widgets comun_ui)
target_compile_definitions(Arch-Linux-Manager-Qt PRIVATE VERSION_PROGRAMA="${VERSION_PROGRAMA}")
comun_novedades(Arch-Linux-Manager-Qt ${CMAKE_CURRENT_SOURCE_DIR}/../NOVEDADES.md)   # qué cambió en cada versión

install(TARGETS Arch-Linux-Manager-Qt RUNTIME DESTINATION bin)
