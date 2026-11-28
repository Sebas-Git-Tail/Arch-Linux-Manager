#!/bin/bash
# Se incluye con source (después de Equipo.sh). Las apps del AUR que el Manager instala y
# actualiza sin yay ni paru: baja el PKGBUILD del AUR y lo arma con makepkg (para eso hacen
# falta fakeroot y debugedit, que General/AUR-instalar.sh instala si no están).
#
# Quién ve cada una (pedido de Sebastián, 19/11/2026):
#   pc, instituto    todas (Playit solo acá: el túnel de los servidores de Minecraft)
#   mama, krocante   solo Claude
#   otra             todas menos Claude y Playit
# PSeInt se agregó el 28/11/2026, solo para el instituto, con el perfil de lenguaje de Sebastián.

# paquete|nombre|descripción|equipos (separados por comas)
AUR_APPS=(
    "claude-desktop|Claude|App de escritorio de Claude: chat, Cowork y Claude Code.|pc,instituto,mama,krocante"
    "equibop-bin|Equibop|Discord con Equicord (temas y complementos).|pc,instituto,otra"
    "heroic-games-launcher-bin|Heroic Games Launcher|Juegos de Epic, GOG y Amazon.|pc,instituto,otra"
    "lcl-gui-bin|Linux Command Library|Referencia de comandos de Linux y machetes.|pc,instituto,otra"
    "pseint-bin|PSeInt|Pseudocódigo y diagramas de flujo para aprender a programar, con las opciones del lenguaje ya configuradas.|instituto"
    "playit-bin|Playit|Túnel para que se pueda entrar desde afuera a tus servidores de Minecraft.|pc,instituto"
)

AUR_URL="https://aur.archlinux.org"

# Imprime las líneas de AUR_APPS que corresponden a este equipo
aur_apps_del_equipo() {
    local equipo linea
    equipo=$(equipo_actual)
    for linea in "${AUR_APPS[@]}"; do
        [[ ",${linea##*|}," == *",$equipo,"* ]] && printf '%s\n' "$linea"
    done
}

# Verdadero si el paquete es una de las apps de este equipo (solo esas se pueden instalar)
aur_permitido() {
    local linea
    while IFS= read -r linea; do
        [[ "${linea%%|*}" == "$1" ]] && return 0
    done < <(aur_apps_del_equipo)
    return 1
}

# Nombre para mostrar de un paquete
aur_nombre() {
    local linea resto
    for linea in "${AUR_APPS[@]}"; do
        if [[ "${linea%%|*}" == "$1" ]]; then
            resto=${linea#*|}
            printf '%s\n' "${resto%%|*}"
            return 0
        fi
    done
    printf '%s\n' "$1"
}

# Lo que hace falta después de instalar o actualizar una app, además de pacman. Lo llama
# General/AUR-instalar.sh como el usuario (no root), así que solo toca su carpeta personal.
aur_despues_de_instalar() {
    case "$1" in
        pseint-bin) aur_pseint_preparar ;;
    esac
}

# Opciones del lenguaje de PSeInt (Configurar > Opciones del Lenguaje), las de Sebastián
# (captura Pseint.png del 28/11/2026, iguales a su ~/.pseint/config de octubre). Mismo orden
# que el diálogo; 1 = marcada.
PSEINT_PERFIL=(
    force_init_vars=1           # No permitir utilizar variables o posiciones de arreglos sin inicializar
    force_define_vars=1         # Obligar a definir los tipos de variables
    force_semicolon=0           # Controlar el uso de ; al final de sentencias secuenciales
    allow_concatenation=1       # Permitir concatenar variables de texto con el operador +
    enable_string_functions=1   # Habilitar funciones para el manejo de cadenas
    word_operators=1            # Permitir las palabras Y, O, NO y MOD para &&, |, ~ y %
    base_zero_arrays=0          # Utilizar índices en arreglos y cadenas en base 0
    allow_dinamyc_dimensions=1  # Permitir utilizar variables para dimensionar arreglos
    allow_resize_arrays=1       # Permitir redimensionar arreglos
    overload_equal=1            # Permitir asignar con el signo igual (=)
    enable_user_functions=1     # Permitir definir funciones/subprocesos
    lazy_syntax=1               # Utilizar sintaxis flexible
    coloquial_conditions=1      # Permitir condiciones en lenguaje coloquial
    integer_only_switch=0       # Limitar la estructura Según a variables de control numéricas
    deduce_negative_for_step=1  # Permitir omitir el paso -1 en ciclos Para
    use_nassi_shneiderman=0     # Usar diagramas de Nassi-Shneiderman
    use_alternative_io_shapes=0 # Usar formas alternativas para Leer y Escribir en el diagrama
    allow_accents=1             # Permitir utilizar acentos en nombres de variables
    prefer_algoritmo=0          # Preferir las palabras clave «Algoritmo» y «FinAlgoritmo»
    prefer_funcion=0            # Preferir las palabras clave «Función» y «FinFunción»
    allow_repeat_while=1        # Permitir la variación «Repetir … Mientras Que…»
    allow_for_each=1            # Habilitar estructura «Para Cada…»
    prefer_repeat_while=0       # Preferir «Repetir … Mientras Que…»
    protect_for_counter=0       # Proteger contador del Para
)
PSEINT_DIR="${PSEINT_DIR:-/opt/pseint}"   # donde lo instala pseint-bin

# Prepara PSeInt para el usuario:
#  - Si todavía no tiene configuración (~/.pseint/config), la crea con PSEINT_PERFIL. Si ya
#    tiene, no se toca (puede haberla cambiado). PSeInt completa el resto del archivo al cerrar.
#    Tiene que llevar «version=» (si no, PSeInt la toma por una configuración vieja y carga un
#    perfil de la lista) y profile:source=custom.
#  - pseint-bin deja un acceso directo que no abre (Exec=/opt/pseint, que es una carpeta) y un
#    ícono .icns que KDE no muestra: se tapa con uno propio en ~/.local/share/applications
#    (con TryExec, así desaparece del menú si se desinstala PSeInt). Si ese archivo existe y no
#    es del Manager, no se toca.
aur_pseint_preparar() {
    local config="$HOME/.pseint/config" version opcion
    local acceso="${XDG_DATA_HOME:-$HOME/.local/share}/applications/pseint.desktop"
    if [[ ! -e "$config" ]]; then
        version=$(tr -dc '0-9' < "$PSEINT_DIR/version" 2>/dev/null)
        [[ "$version" =~ ^20[0-9]{6}$ ]] || version=20250314
        mkdir -p "$(dirname "$config")" || return 1
        {
            echo "# Opciones del lenguaje puestas por Arch-Linux-Manager (PSeInt agrega el resto al cerrar)"
            echo "version=$version"
            # Lo que PSeInt pone solo cuando arranca sin configuración (versión 0), que con
            # «version=» ya no hace: la fuente que trae y los operadores Unicode
            echo "wx_font_name=Inconsolata"
            echo "term_font_name=Inconsolata"
            echo "unicode_opers=1"
            echo "profile=<Personalizado>"
            echo "profile:source=custom"
            for opcion in "${PSEINT_PERFIL[@]}"; do echo "profile:$opcion"; done
        } > "$config" || return 1
        echo "PSeInt: se configuraron las opciones del lenguaje."
    fi
    if [[ ! -e "$acceso" ]] || grep -q '^X-Arch-Linux-Manager=' "$acceso"; then
        mkdir -p "$(dirname "$acceso")" || return 1
        cat > "$acceso" <<EOF || return 1
[Desktop Entry]
Type=Application
Name=PSeInt
GenericName=Intérprete de pseudocódigo
Comment=Pseudocódigo y diagramas de flujo para aprender a programar
Exec=$PSEINT_DIR/wxPSeInt %F
TryExec=$PSEINT_DIR/wxPSeInt
Path=$PSEINT_DIR
Icon=$PSEINT_DIR/imgs/icon128.png
Terminal=false
Categories=Development;Education;
X-Arch-Linux-Manager=pseint-bin trae un acceso directo que no abre
EOF
    fi
}

# Versión instalada («4.4212.0-1») o nada si no está
aur_instalada() {
    pacman -Q "$1" 2>/dev/null | awk '{print $2}'
}

# Versiones del AUR de los paquetes dados: una línea «paquete<TAB>versión» por cada uno que exista.
# Una sola consulta a la API (RPC v5). Para las pruebas, AUR_RPC_FALSA es un .json con la respuesta.
aur_versiones() {
    local json url p
    if [[ -n "${AUR_RPC_FALSA:-}" ]]; then
        json=$(<"$AUR_RPC_FALSA") || return 1
    else
        url="$AUR_URL/rpc/v5/info?"
        for p; do url+="arg[]=$p&"; done
        json=$(curl -fsS -m 15 --globoff "${url%&}") || return 1
    fi
    python3 -c '
import json, re, sys
try:
    datos = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)
if not isinstance(datos, dict) or datos.get("type") != "multiinfo":
    sys.exit(1)
pedidos = set(sys.argv[2:])
for r in datos.get("results", []):
    nombre, version = str(r.get("Name", "")), str(r.get("Version", ""))
    # Solo lo que se pidió y con una versión con forma de versión de Arch
    if nombre in pedidos and re.fullmatch(r"[0-9A-Za-z.+_:~-]+", version):
        print(nombre + "\t" + version)
' "$json" "$@"
}
