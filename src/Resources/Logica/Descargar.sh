#!/bin/bash
# Lógica de las descargas de Música y Videos con yt-dlp, SIN interfaz: no abre ninguna
# ventana. Recibe todo por argumentos y cuenta lo que pasa imprimiendo una línea por
# evento, así la puede usar cualquier interfaz (hoy, la ventana Qt).
#
# Uso: Descargar.sh [opciones] [--] URL...
#   --destino DIR     carpeta donde se guarda (obligatoria, salvo con --pistas)
#   --audio           extrae solo el audio (Música)
#   --sin-playlist    si la URL es de una canción dentro de una playlist, baja solo esa
#   --cookies         usa las cookies del navegador (LibreWolf, Firefox o Chromium)
#   --miniaturas DIR  deja las miniaturas en DIR (si no, se usan y se borran al terminar)
#   --pistas          no descarga nada: informa qué pistas de audio (idiomas) y qué
#                     subtítulos ofrece cada URL, para elegir antes de descargar
#                     (de una playlist se mira un solo video)
#   --audios LISTA    idiomas de las pistas de audio que se incluyen en el video, separados
#                     por comas y como los informa --pistas (ej.: es,en). Quedan todas
#                     dentro del archivo. Sin esta opción se baja solo la pista original.
#   --subtitulos LISTA  idiomas de los subtítulos que se incrustan en el video, separados
#                     por comas y como los informa --pistas (ej.: es,en-orig)
#   --calidad ALTO    altura máxima del video en píxeles (ej.: 1080). Sin esta opción, la mejor.
#   --vcodec FAMILIA  códec de video preferido: av1, vp9, h264, h265 o vp8
#   --acodec FAMILIA  códec de audio preferido: opus, aac, vorbis, mp3, ac3, eac3 o flac
#                     Si un video no tiene lo pedido, se baja lo más parecido (no falla).
#   Los videos siempre quedan en un contenedor MKV.
#
# Eventos (stdout, uno por línea: PALABRA y el resto de la línea):
#   AVISO <texto>           información para mostrar al usuario
#   INICIO <n> <total> <url> empieza la URL n de total
#   AUDIO <idioma> <ORIGINAL|OTRA>   (--pistas) pista de audio que ofrece la URL
#   SUBTITULO <idioma> <MANUAL|AUTO> <nombre>
#                           (--pistas) subtítulo que ofrece la URL. AUTO: generado o
#                           traducido automáticamente. El nombre puede faltar.
#   VIDEO <alto> <familia>  (--pistas) calidad y códec de video que ofrece la URL
#   ACODEC <familia>        (--pistas) códec de audio que ofrece la URL
#   ARCHIVO <nombre>        archivo que se está bajando
#   PROGRESO <0-100>        porcentaje del archivo actual (solo cuando cambia)
#   MINIATURA <ruta>        miniatura del último archivo terminado (sirve de ícono;
#                           solo con --miniaturas, porque si no se borra al terminar)
#   LISTO <ruta>            archivo terminado y guardado en <ruta>
#   FALLO <mensaje>         falló la URL actual (sigue con la siguiente)
#   ERROR <mensaje>         error que impide seguir (termina)
#
# Código de salida: 0 todo bien, 1 falló alguna URL, 2 error de uso o de configuración.

set -uo pipefail

emitir() { printf '%s\n' "$*"; }
error() { emitir "ERROR $*"; exit 2; }

destino="" audio=no playlist=si cookies=no miniaturas="" pistas=no audios="" subtitulos=""
calidad="" vcodec="" acodec=""
while (( $# )); do
    case "$1" in
        --destino)      [[ $# -ge 2 ]] || error "Falta la carpeta después de --destino"; destino=$2; shift ;;
        --audio)        audio=si ;;
        --sin-playlist) playlist=no ;;
        --cookies)      cookies=si ;;
        --miniaturas)   [[ $# -ge 2 ]] || error "Falta la carpeta después de --miniaturas"; miniaturas=$2; shift ;;
        --pistas)       pistas=si ;;
        --audios)       [[ $# -ge 2 ]] || error "Faltan los idiomas después de --audios"; audios=$2; shift ;;
        --subtitulos)   [[ $# -ge 2 ]] || error "Faltan los idiomas después de --subtitulos"; subtitulos=$2; shift ;;
        --calidad)      [[ $# -ge 2 ]] || error "Falta la altura después de --calidad"; calidad=$2; shift ;;
        --vcodec)       [[ $# -ge 2 ]] || error "Falta el códec después de --vcodec"; vcodec=$2; shift ;;
        --acodec)       [[ $# -ge 2 ]] || error "Falta el códec después de --acodec"; acodec=$2; shift ;;
        --)             shift; break ;;
        -*)             error "Opción desconocida: $1" ;;
        *)              break ;;
    esac
    shift
done
URLs=("$@")

(( ${#URLs[@]} )) || error "No se pasó ninguna URL"

# Los idiomas llegan separados por comas («es,en-US»). Tienen que ser códigos de idioma
# (letras, números y guiones) porque terminan dentro de opciones de yt-dlp
IFS=, read -ra lista_audios <<< "$audios"
IFS=, read -ra lista_subtitulos <<< "$subtitulos"
for idioma in "${lista_audios[@]}" "${lista_subtitulos[@]}"; do
    [[ "$idioma" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || error "Idioma inválido: «$idioma»"
done
if [[ "$audio" == si ]] && (( ${#lista_audios[@]} + ${#lista_subtitulos[@]} )); then
    error "--audios y --subtitulos son para videos: no se pueden usar con --audio"
fi
# Calidad y códecs: solo valores conocidos (terminan dentro del selector de formatos de yt-dlp)
[[ -z "$calidad" || "$calidad" =~ ^[1-9][0-9]{1,4}$ ]] || error "Calidad inválida: «$calidad» (tiene que ser una altura, ej.: 1080)"
case "$vcodec" in ""|av1|vp9|h264|h265|vp8) ;; *) error "Códec de video desconocido: «$vcodec»" ;; esac
case "$acodec" in ""|opus|aac|vorbis|mp3|ac3|eac3|flac) ;; *) error "Códec de audio desconocido: «$acodec»" ;; esac
if [[ "$audio" == si && -n "$calidad$vcodec$acodec" ]]; then
    error "--calidad, --vcodec y --acodec son para videos: no se pueden usar con --audio"
fi

if [[ "$pistas" == no ]]; then
    [[ -n "$destino" ]] || error "Falta --destino"
    mkdir -p "$destino" || error "No se pudo crear la carpeta $destino"
fi

# Carpeta temporal propia: el archivo de rutas y, si no se pidió otra, las miniaturas
TEMPORAL=$(mktemp -d)
trap 'rm -rf "$TEMPORAL"' EXIT
# MINIATURA solo se anuncia si la carpeta es del que llamó (la temporal se borra al salir)
anunciar_miniatura=si
[[ -n "$miniaturas" ]] || { miniaturas="$TEMPORAL/miniaturas"; anunciar_miniatura=no; }
mkdir -p "$miniaturas"
RUTAS="$TEMPORAL/rutas.txt"

# Navegador del que yt-dlp saca las cookies. Prioridad: LibreWolf, Firefox, Chromium.
navegador_cookies() {
    local nombre
    if command -v librewolf &>/dev/null; then
        # LibreWolf se usa como si fuera Firefox, indicando su carpeta de perfiles
        nombre="LibreWolf"
        Navegador="firefox:$HOME/.config/librewolf/librewolf/"
    elif command -v firefox &>/dev/null; then
        nombre="Firefox"
        Navegador="firefox"
    elif command -v chromium &>/dev/null; then
        nombre="Chromium"
        Navegador="chromium"
    else
        error "No se encontró un navegador válido para extraer cookies (LibreWolf, Firefox o Chromium). Tu navegador predeterminado es: $(xdg-settings get default-web-browser 2>/dev/null)"
    fi
    # Con --pistas no se anuncia: lo hace la descarga que viene después
    [[ "$pistas" == si ]] || emitir "AVISO El navegador para la extracción de cookies es $nombre"
}

# ── Solo consultar (--pistas): qué pistas de audio y subtítulos ofrece cada URL ──────────
# yt-dlp entrega la información del video en JSON; para leerla sin errores se usa este
# programita de Python (yt-dlp está hecho en Python, así que siempre está instalado).
# Escribe un evento AUDIO por cada idioma de audio y un SUBTITULO por cada subtítulo.
LEER_PISTAS='
import json, re, sys

def videos(informacion):
    # La respuesta es un video o, si la URL era una playlist, una lista de entradas
    if informacion.get("_type") == "playlist":
        for entrada in informacion.get("entries") or []:
            if entrada:
                yield from videos(entrada)
    else:
        yield informacion

# Los idiomas se pasan después por opciones de yt-dlp: solo valen códigos simples
valido = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*").fullmatch

# Familia de un códec como lo informa yt-dlp («avc1.640028» -> h264). None si no se conoce.
def familia_video(codec):
    c = (codec or "").lower()
    for prefijos, familia in ((("av01",), "av1"), (("vp09", "vp9"), "vp9"), (("avc1", "avc3", "h264"), "h264"),
                              (("hev1", "hvc1", "hevc", "h265"), "h265"), (("vp8",), "vp8")):
        if c.startswith(prefijos):
            return familia
    return None

def familia_audio(codec):
    c = (codec or "").lower()
    for prefijos, familia in ((("opus",), "opus"), (("mp4a", "aac"), "aac"), (("vorbis",), "vorbis"),
                              (("mp3",), "mp3"), (("ec-3", "eac3"), "eac3"), (("ac-3", "ac3"), "ac3"), (("flac",), "flac")):
        if c.startswith(prefijos):
            return familia
    return None

# Si yt-dlp falló no hay respuesta (o es «null»): el error lo informa el script
try:
    respuesta = json.load(sys.stdin)
except ValueError:
    respuesta = None
if not isinstance(respuesta, dict):
    sys.exit(1)

for video in videos(respuesta):
    # Pistas de audio: los idiomas de los formatos de solo audio. La original es la que
    # yt-dlp marca con la preferencia de idioma más alta (10)
    idiomas = {}
    for formato in video.get("formats") or []:
        idioma = formato.get("language")
        if idioma and valido(idioma) and formato.get("vcodec") == "none" and formato.get("acodec") != "none":
            original = (formato.get("language_preference") or 0) >= 10
            idiomas[idioma] = idiomas.get(idioma, False) or original
    for idioma, original in idiomas.items():
        print("AUDIO", idioma, "ORIGINAL" if original else "OTRA")

    # Calidades y códecs: de los formatos de solo video (se pueden juntar con cualquier audio) y
    # de los de solo audio. Si el sitio solo tiene formatos con video y audio juntos, esos.
    solo_video, con_audio, audios_vistos = [], [], []
    for formato in video.get("formats") or []:
        vcodec, acodec = formato.get("vcodec"), formato.get("acodec")
        if vcodec and vcodec != "none":
            familia, alto = familia_video(vcodec), formato.get("height")
            if familia and isinstance(alto, int) and alto > 0:
                lista = con_audio if acodec and acodec != "none" else solo_video
                if (alto, familia) not in lista:
                    lista.append((alto, familia))
        elif acodec and acodec != "none":
            familia = familia_audio(acodec)
            if familia and familia not in audios_vistos:
                audios_vistos.append(familia)
                print("ACODEC", familia)
    for alto, familia in solo_video or con_audio:
        print("VIDEO", alto, familia)

    # Subtítulos: los que subió el autor (MANUAL) y los automáticos (AUTO). Si de un idioma
    # hay de los dos, yt-dlp usa el manual: el automático no se ofrece.
    # live_chat es el chat de un directo, no un subtítulo.
    manuales = video.get("subtitles") or {}
    automaticos = video.get("automatic_captions") or {}
    for tipo, subtitulos in (("MANUAL", manuales), ("AUTO", automaticos)):
        for idioma, formatos in subtitulos.items():
            if idioma == "live_chat" or not valido(idioma) or (tipo == "AUTO" and idioma in manuales):
                continue
            nombre = next((f.get("name") for f in formatos or [] if f.get("name")), "")
            print("SUBTITULO", idioma, tipo, " ".join(str(nombre).split()))
'

if [[ "$pistas" == si ]]; then
    # -J: toda la información en JSON, sin descargar. De una playlist se mira un solo
    # video (el de la URL o el primero): alcanza para saber qué idiomas ofrece
    Consulta=(-J --no-warnings --no-playlist --playlist-items 1)
    if [[ "$cookies" == si ]]; then
        navegador_cookies
        Consulta+=(--cookies-from-browser "$Navegador")
    fi
    fallidas=0
    for i in "${!URLs[@]}"; do
        emitir "INICIO $((i + 1)) ${#URLs[@]} ${URLs[$i]}"
        # python3 -I: modo aislado (no carga módulos de la carpeta desde la que se lo llama)
        if ! yt-dlp "${Consulta[@]}" -- "${URLs[$i]}" 2> "$TEMPORAL/errores.txt" | python3 -I -c "$LEER_PISTAS"; then
            mensaje=$(grep '^ERROR: ' "$TEMPORAL/errores.txt" | tail -n1)
            mensaje=${mensaje#ERROR: }
            emitir "FALLO ${mensaje:-No se pudo consultar ${URLs[$i]}}"
            (( fallidas++ ))
        fi
    done
    (( fallidas == 0 ))
    exit
fi

# Opciones de yt-dlp (las mismas que usaban Música y Videos cuando eran con kdialog)
Parametros=(
    # descarga la miniatura (en $miniaturas, ver -o thumbnail: más abajo)
    --write-thumbnail
    # máxima calidad de audio
    --audio-quality 0
    # guarda título, artista, etc. dentro del archivo
    --embed-metadata
    # incrusta la miniatura como carátula
    --embed-thumbnail
    # prefiere formatos libres (opus, webm...)
    --prefer-free-formats
    # nombre: carpeta del artista (o del canal si no hay artista) / título.extensión
    -o "%(artist,uploader)s/%(title)s.%(ext)s"
    -o "thumbnail:$miniaturas/%(id)s.%(ext)s"
    # anota la ruta final en $RUTAS
    --print-to-file "after_move:filepath" "$RUTAS"
    # una línea por avance, para el porcentaje
    --newline
    --progress
    -P "$destino"
)
if [[ "$audio" == si ]]; then
    Parametros+=(-x)
else
    # Los videos siempre en MKV: une video y audio en MKV y pasa a MKV lo que venga en un solo archivo
    Parametros+=(--merge-output-format mkv --remux-video mkv)
fi
[[ "$playlist" == no ]] && Parametros+=(--no-playlist)
if [[ "$cookies" == si ]]; then
    navegador_cookies
    Parametros+=(--cookies-from-browser "$Navegador")
fi

# Subtítulos elegidos: quedan incrustados en el video (se activan desde el reproductor).
# Con --write-subs y --write-auto-subs sirven tanto los que subió el autor como los
# automáticos. Los archivos de subtítulos sueltos van a la carpeta temporal, que se borra
# al salir (si no, quedarían al lado del video).
if (( ${#lista_subtitulos[@]} )); then
    Parametros+=(
        --write-subs --write-auto-subs --embed-subs
        --sub-langs "$(IFS=,; printf '%s' "${lista_subtitulos[*]}")"
        -o "subtitle:$TEMPORAL/subtitulos/%(id)s.%(ext)s"
    )
fi

# ── Selector de formatos de yt-dlp ──────────────────────────────────────────────────────
# Filtros de calidad y códec elegidos (vacíos si no se eligió nada)
filtro_alto="" filtro_vcodec="" filtro_acodec=""
[[ -n "$calidad" ]] && filtro_alto="[height<=$calidad]"
case "$vcodec" in
    av1)  filtro_vcodec="[vcodec^=av01]" ;;
    vp9)  filtro_vcodec="[vcodec~='^vp0?9']" ;;
    h264) filtro_vcodec="[vcodec~='^(avc[13]|h264)']" ;;
    h265) filtro_vcodec="[vcodec~='^(hev1|hvc1|hevc|h265)']" ;;
    vp8)  filtro_vcodec="[vcodec^=vp8]" ;;
esac
case "$acodec" in
    opus)   filtro_acodec="[acodec=opus]" ;;
    aac)    filtro_acodec="[acodec~='^(mp4a|aac)']" ;;
    vorbis) filtro_acodec="[acodec=vorbis]" ;;
    mp3)    filtro_acodec="[acodec=mp3]" ;;
    ac3)    filtro_acodec="[acodec~='^ac-?3']" ;;
    eac3)   filtro_acodec="[acodec~='^(ec-?3|eac3)']" ;;
    flac)   filtro_acodec="[acodec=flac]" ;;
esac

# Alternativas con las pistas de audio elegidas, que van todas dentro del mismo archivo (se
# cambia de pista desde el reproductor):
#   VIDEO+ba[language=es]AUDIO+ba[language=en]AUDIO    el video + la mejor pista de cada idioma
# Un selector con «+» falla entero si al video le falta alguno de sus idiomas. Por eso van
# alternativas con menos idiomas, de más a menos (separadas por «/»): así cada video (en una
# playlist pueden ofrecer pistas distintas) se baja con todas las pedidas que tenga.
# Uso: con_idiomas VIDEO FILTRO_AUDIO  -> imprime las alternativas terminadas en «/»
con_idiomas() {
    local video=$1 faudio=$2 n=${#lista_audios[@]} cantidad mascara alternativa bits i
    if (( n <= 6 )); then
        # Todas las combinaciones de idiomas: cada número «mascara» es una combinación (el
        # bit i dice si entra el idioma i). Primero las que tienen más idiomas.
        for (( cantidad = n; cantidad >= 1; cantidad-- )); do
            for (( mascara = (1 << n) - 1; mascara >= 1; mascara-- )); do
                alternativa="$video" bits=0
                for (( i = 0; i < n; i++ )); do
                    if (( (mascara >> i) & 1 )); then
                        alternativa+="+ba[language=${lista_audios[$i]}]$faudio"
                        (( bits++ ))
                    fi
                done
                (( bits == cantidad )) && printf '%s/' "$alternativa"
            done
        done
    else
        # Con muchos idiomas las combinaciones son demasiadas (2^n): se prueba con todos
        # y, si no, con cada uno por separado
        alternativa="$video"
        for idioma in "${lista_audios[@]}"; do alternativa+="+ba[language=$idioma]$faudio"; done
        printf '%s/' "$alternativa"
        for idioma in "${lista_audios[@]}"; do printf '%s/' "$video+ba[language=$idioma]$faudio"; done
    fi
}

# De lo más parecido a lo pedido a lo menos: video solo con la calidad y códecs elegidos;
# después un archivo con video y audio juntos que cumpla (algunos sitios solo tienen esos); después
# solo la calidad (si el video no tiene ese códec); al final lo de siempre (bv*+ba/b).
# «bv» y no «bv*»: bv* acepta formatos que ya traen audio y entonces no se les puede sumar otro.
if [[ -n "$filtro_alto$filtro_vcodec$filtro_acodec" ]] || (( ${#lista_audios[@]} )); then
    selector=""
    pedido="bv$filtro_alto$filtro_vcodec"
    solo_alto="bv$filtro_alto"
    if (( ${#lista_audios[@]} )); then
        selector+=$(con_idiomas "$pedido" "$filtro_acodec")
        [[ -n "$filtro_vcodec$filtro_acodec" ]] && selector+=$(con_idiomas "$solo_alto" "")
        Parametros+=(--audio-multistreams)
    fi
    [[ -n "$filtro_acodec" ]] && selector+="$pedido+ba$filtro_acodec/"
    selector+="$pedido+ba/"
    [[ -n "$filtro_alto$filtro_vcodec" ]] && selector+="b$filtro_alto$filtro_vcodec/"
    [[ -n "$filtro_vcodec" ]] && selector+="$solo_alto+ba/"
    [[ -n "$filtro_alto" && -n "$filtro_vcodec" ]] && selector+="b$filtro_alto/"
    Parametros+=(-f "${selector}bv*+ba/b")
fi

# La miniatura más reciente (vacío si no hay)
ultima_miniatura() {
    ls -t "$miniaturas"/*.{jpg,png,webp} 2>/dev/null | head -n1
}

# Baja una URL emitiendo ARCHIVO/PROGRESO; deja el último error de yt-dlp en $mensaje
bajar() {
    local linea ultimo="" porcentaje
    mensaje=""
    : > "$RUTAS"
    while IFS= read -r linea; do
        if [[ $linea == "[download] Destination: "* ]]; then
            emitir "ARCHIVO $(basename "${linea#"[download] Destination: "}")"
            ultimo=""
        elif [[ $linea == "[download]"* && $linea =~ ([0-9]+)(\.[0-9]+)?% ]]; then
            porcentaje="${BASH_REMATCH[1]}"
            if [[ $porcentaje != "$ultimo" ]]; then    # solo cuando cambia el número
                ultimo=$porcentaje
                emitir "PROGRESO $porcentaje"
            fi
        elif [[ $linea == "ERROR: "* ]]; then
            mensaje="${linea#ERROR: }"
        fi
    done < <(yt-dlp "${Parametros[@]}" -- "$1" 2>&1)
    wait $!
}

fallidas=0
for i in "${!URLs[@]}"; do
    URL="${URLs[$i]}"
    emitir "INICIO $((i + 1)) ${#URLs[@]} $URL"

    bajar "$URL"; estado=$?

    # Lo que se llegó a bajar se informa aunque después algo haya fallado (playlists)
    if [[ -s "$RUTAS" ]]; then
        miniatura=$(ultima_miniatura)
        [[ -n "$miniatura" && "$anunciar_miniatura" == si ]] && emitir "MINIATURA $miniatura"
        while IFS= read -r ruta; do
            [[ -n "$ruta" ]] && emitir "LISTO $ruta"
        done < "$RUTAS"
    fi
    if [[ $estado -ne 0 || ! -s "$RUTAS" ]]; then
        emitir "FALLO ${mensaje:-yt-dlp terminó con código $estado}"
        (( fallidas++ ))
    fi
done

(( fallidas == 0 ))
