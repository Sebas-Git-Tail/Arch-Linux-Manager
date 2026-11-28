#!/usr/bin/env bash
# Pruebas de los scripts de Arch-Linux-Manager (no tocan la red, el servidor ni tu carpeta personal:
# todo pasa en una carpeta temporal). Uso: tests/correr.sh
# Las corre también GitHub Actions en cada push (.github/workflows/compilar.yml).
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
RES="$RAIZ/src/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_DATA_HOME="$TMP/datos"
export COMMON="$RES/Common" LOGICA="$RES/Logica" SERVIDOR_SIN_RED=1
mkdir -p "$HOME"

fallas=0
pruebas=0
ok()   { pruebas=$((pruebas + 1)); printf '  ✓ %s\n' "$1"; }
mal()  { pruebas=$((pruebas + 1)); fallas=$((fallas + 1)); printf '  ✗ %s\n' "$1"; [[ -n "${2:-}" ]] && printf '      %s\n' "$2"; }
igual() { if [[ "$2" == "$3" ]]; then ok "$1"; else mal "$1" "esperaba «$3», dio «$2»"; fi; }

echo "Sintaxis"
for s in "$RES"/Common/*.sh "$RES"/Logica/*.sh "$RES"/General/*.sh "$RES"/General/Android/*.sh "$RAIZ"/Arch-Linux-Manager.sh; do
    if bash -n "$s" 2>/dev/null; then ok "bash -n $(basename "$s")"; else mal "bash -n $s"; fi
done
if command -v shellcheck &>/dev/null; then
    if salida=$(shellcheck -S error -x -P "$RES/Common:$RES/Logica" "$RES"/Common/*.sh "$RES"/Logica/*.sh 2>&1); then
        ok "shellcheck sin errores"
    else
        mal "shellcheck" "$(head -5 <<< "$salida")"
    fi
fi

echo "Equipo.sh"
export MANAGER_MAC_PRUEBA="58:11:22:a9:df:de"   # la PC de Sebastián (ver Common/MAC.sh)
elegir() { bash "$LOGICA/Entorno.sh" 2>/dev/null | sed -n 's/^ELEGIR_EQUIPO //p'; }
igual "en la PC de Sebastián se muestra «Este equipo…»" "$(elegir)" "SI"
equipo() { bash -c 'source "$COMMON/Equipo.sh"; equipo_actual'; }
origen() { bash "$LOGICA/Entorno.sh" 2>/dev/null | sed -n 's/^MAQUINA_ORIGEN //p'; }
igual "sin Equipo.conf se adivina por la MAC" "$(origen)" "mac"
bash "$LOGICA/Entorno.sh" --equipo krocante >/dev/null
igual "--equipo guarda la elección" "$(cat "$HOME/.config/Manager/Equipo.conf")" "krocante"
igual "equipo_actual usa lo elegido" "$(equipo)" "krocante"
igual "Entorno.sh informa que es manual" "$(origen)" "manual"
bash -c 'source "$COMMON/Equipo.sh"; es_maquina_krocante' && ok "es_maquina_krocante verdadero" || mal "es_maquina_krocante"
bash -c 'source "$COMMON/Equipo.sh"; es_maquina_pc' && mal "es_maquina_pc debería ser falso" || ok "es_maquina_pc falso"
if bash "$LOGICA/Entorno.sh" --equipo hackeo >/dev/null; then mal "--equipo acepta cualquier cosa"; else ok "--equipo rechaza un equipo desconocido"; fi
igual "un equipo desconocido no pisa el anterior" "$(cat "$HOME/.config/Manager/Equipo.conf")" "krocante"
echo "mamá rota" > "$HOME/.config/Manager/Equipo.conf"
[[ "$(equipo)" =~ ^(pc|instituto|mama|krocante|otra)$ ]] && ok "un Equipo.conf inválido vuelve a la MAC" || mal "Equipo.conf inválido"
bash "$LOGICA/Entorno.sh" --equipo auto >/dev/null
[[ ! -e "$HOME/.config/Manager/Equipo.conf" ]] && ok "--equipo auto borra la elección" || mal "--equipo auto"
bash "$LOGICA/Entorno.sh" --equipo krocante >/dev/null
MANAGER_MAC_PRUEBA="18:c0:4d:a2:fe:e0"   # la PC de mamá, con un Equipo.conf viejo
igual "en otra PC no se muestra «Este equipo…»" "$(elegir)" "NO"
igual "en otra PC se ignora Equipo.conf" "$(equipo)" "mama"
igual "en otra PC el origen es la MAC" "$(origen)" "mac"
if bash "$LOGICA/Entorno.sh" --equipo pc >/dev/null; then mal "--equipo funciona en otra PC"; else ok "--equipo se rechaza en otra PC"; fi
igual "en otra PC --equipo no toca Equipo.conf" "$(cat "$HOME/.config/Manager/Equipo.conf")" "krocante"
MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff"
igual "en una PC desconocida tampoco" "$(elegir)" "NO"
rm -f "$HOME/.config/Manager/Equipo.conf"
unset MANAGER_MAC_PRUEBA

echo "Servidor.sh y servidor.json"
cache="$XDG_CACHE_HOME/Arch-Linux-Manager/servidor.json"
mkdir -p "$(dirname "$cache")"
valor() { bash -c "source \"\$COMMON/Servidor.sh\"; printf '%s' \"\$$1\""; }
igual "sin copia guardada quedan los de fábrica" "$(valor SERVIDOR_IP_LOCAL)" "192.168.100.14"
cat > "$cache" <<'EOF'
{"version": 1, "ip_local": "10.0.0.5", "ip_tailscale": "100.1.2.3", "usuario": "otro",
 "web_tailscale": "https://ejemplo.ts.net", "respaldos": "/srv/respaldos", "desconocido": "x",
 "ip_minecraft": "10.0.0.7"}
EOF
igual "servidor.json cambia la IP de casa" "$(valor SERVIDOR_IP_LOCAL)" "10.0.0.5"
igual "servidor.json cambia la IP de Tailscale" "$(valor SERVIDOR_IP_TAILSCALE)" "100.1.2.3"
igual "servidor.json cambia el usuario" "$(valor SERVIDOR_USUARIO)" "otro"
igual "servidor.json cambia la carpeta" "$(valor SERVIDOR_RESPALDOS)" "/srv/respaldos"
igual "servidor.json cambia el servidor de Minecraft" "$(valor SERVIDOR_MINECRAFT)" "10.0.0.7"
cat > "$cache" <<'EOF'
{"version": 1, "ip_local": "1.2.3.4; rm -rf ~", "usuario": "$(whoami)", "respaldos": "../../etc",
 "web_local": "javascript:alert(1)", "ip_minecraft": "1.2.3.4 -o x"}
EOF
igual "rechaza una IP con comandos" "$(valor SERVIDOR_IP_LOCAL)" "192.168.100.14"
igual "rechaza un usuario raro" "$(valor SERVIDOR_USUARIO)" "sebastian"
igual "rechaza una ruta relativa" "$(valor SERVIDOR_RESPALDOS)" "/home/sebastian/Respaldos"
igual "rechaza una URL rara" "$(valor SERVIDOR_WEB_LOCAL)" "http://192.168.100.14:8080"
igual "rechaza una IP de Minecraft rara" "$(valor SERVIDOR_MINECRAFT)" "192.168.100.7"
echo '{"version": 2, "ip_local": "10.9.9.9"}' > "$cache"
igual "ignora otra versión del formato" "$(valor SERVIDOR_IP_LOCAL)" "192.168.100.14"
echo 'esto no es json' > "$cache"
igual "ignora un archivo roto" "$(valor SERVIDOR_IP_LOCAL)" "192.168.100.14"
rm -f "$cache"
[[ "$(valor SSH_HUELLAS_SERVIDOR)" == *"StrictHostKeyChecking=yes"*"HostKeyAlias=servidor-respaldos"* ]] \
    && ok "ssh exige la huella del servidor" || mal "SSH_HUELLAS_SERVIDOR"
grep -q 'StrictHostKeyChecking=accept-new' "$RES"/Logica/*.sh && mal "queda un accept-new en Logica/" || ok "ningún script acepta huellas nuevas"

echo "known_hosts"
for alias in servidor-respaldos pc-sebastian; do
    if ssh-keygen -F "$alias" -f "$COMMON/known_hosts" >/dev/null 2>&1; then ok "tiene la huella de $alias"; else mal "falta la huella de $alias"; fi
done

echo "Respaldo.sh"
salida=$(bash "$LOGICA/Respaldo.sh" cualquiera < /dev/null); codigo=$?
igual "tipo desconocido sale con 2" "$codigo" "2"
salida=$(echo "" | bash "$LOGICA/Respaldo.sh" linux); codigo=$?
igual "sin contraseña sale con 3" "$codigo" "3"
historial="$XDG_DATA_HOME/Arch-Linux-Manager/historial-respaldos.tsv"
if [[ -f "$historial" ]]; then
    # (con IFS=tab, read juntaría los campos vacíos: se separa con awk)
    campo() { tail -1 "$historial" | awk -F'\t' -v n="$1" '{print $n}'; }
    fecha=$(campo 1); tipo=$(campo 2); resultado=$(campo 3); segundos=$(campo 4); transferido=$(campo 5); mensaje=$(campo 6)
    igual "el historial anota el tipo" "$tipo" "linux"
    igual "el historial anota el resultado" "$resultado" "error"
    igual "el historial anota el mensaje" "$mensaje" "Contraseña incorrecta."
    [[ "$fecha" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] && ok "fecha ISO" || mal "fecha ISO" "$fecha"
    [[ "$segundos" =~ ^[0-9]+$ ]] && ok "duración en segundos" || mal "duración" "$segundos"
    : "$transferido"
else
    mal "Respaldo.sh no escribió el historial"
fi
for _ in $(seq 205); do echo "" | bash "$LOGICA/Respaldo.sh" linux >/dev/null; done 2>/dev/null
igual "el historial guarda solo los últimos 200" "$(wc -l < "$historial")" "200"

echo "Notificacion.sh"
dir="$TMP/common-vacio"; mkdir -p "$dir"; cp "$COMMON"/{Servidor.sh,known_hosts} "$dir/"
salida=$(echo hola | COMMON="$dir" bash "$LOGICA/Notificacion.sh"); codigo=$?
igual "sin clave ni configuración sale con 2" "$codigo" "2"
grep -q 'sshpass\|NOTIF_CLAVE\|desofuscar' "$LOGICA/Notificacion.sh" && mal "Notificacion.sh sigue usando contraseña" || ok "Notificacion.sh no usa contraseña"

echo "Minecraft.sh (servidores falsos en $TMP, API falsa: no toca la red)"
export MINECRAFT_VIGILAR=0    # (el apagado automático tiene su propia prueba, más abajo)
export MINECRAFT_DIR="$TMP/mc"
S="$MINECRAFT_DIR/Servidores"
mkdir -p "$S/26.3 SMP-1/plugins" "$S/26.3 SMP-1/world/region" "$S/26.3 SMP-1/world_nether" "$S/26.2 Forge" "$S/sin conf"
printf 'NOMBRE="26.3 SMP-1"\nTIPO=paper\nVERSION=26.3\nJAR="paper-26.3-244.jar"\nRAM=8G\n' > "$S/26.3 SMP-1/servidor.conf"
printf 'level-name=world\n' > "$S/26.3 SMP-1/server.properties"
echo datos > "$S/26.3 SMP-1/world/region/r.0.0.mca"
printf 'TIPO=forge\nVERSION=26.2\nRAM=6G\n' > "$S/26.2 Forge/servidor.conf"
MC() { bash "$LOGICA/Minecraft.sh" "$@" 2>&1; }
falso_java="$TMP/java-falso"; mkdir -p "$falso_java"
lista=$(MC servidores)
igual "lista solo las carpetas con servidor.conf" "$(grep -c '^SERVIDOR ' <<< "$lista")" "2"
igual "ordena por versión" "$(grep '^SERVIDOR ' <<< "$lista" | cut -f2 | tr '\n' '|')" "26.2 Forge|26.3 SMP-1|"
igual "informa tipo, versión, RAM y jar" "$(grep 'SMP-1' <<< "$lista" | cut -f3,4,7,8 | tr '\t' ' ')" "paper 26.3 8G paper-26.3-244.jar"
igual "Forge arranca con run.sh" "$(grep 'Forge' <<< "$lista" | cut -f8)" "run.sh"
MC iniciar "../../etc" > /dev/null; igual "rechaza un servidor que no existe" "$?" "2"
MC iniciar "sin conf" > /dev/null; igual "rechaza una carpeta sin servidor.conf" "$?" "2"
# servidor.conf con cosas raras: se ignoran (no se ejecuta nada)
printf 'JAR="$(touch %s/pwned).jar"\nRAM=8G; rm -rf ~\nTIPO=paper\nVERSION=26.3\n' "$TMP" > "$S/26.2 Forge/servidor.conf"
lista=$(MC servidores)
[[ -e "$TMP/pwned" ]] && mal "servidor.conf no se ejecuta" || ok "servidor.conf no se ejecuta"
igual "servidor.conf: ignora RAM y JAR raros" "$(grep 'Forge' <<< "$lista" | cut -f7,8 | tr '\t' ' ')" "8G run.sh"
printf 'TIPO=forge\nVERSION=26.2\nRAM=6G\n' > "$S/26.2 Forge/servidor.conf"
MC ram "26.3 SMP-1" 12G > /dev/null
igual "ram cambia servidor.conf" "$(grep '^RAM=' "$S/26.3 SMP-1/servidor.conf")" 'RAM="12G"'
MC ram "26.3 SMP-1" "12G; rm" > /dev/null; igual "ram rechaza valores raros" "$?" "2"
salida=$(MC reiniciar-mundo "26.3 SMP-1")
[[ ! -d "$S/26.3 SMP-1/world" && ! -d "$S/26.3 SMP-1/world_nether" ]] && ok "reiniciar-mundo borra el mundo y el nether" || mal "reiniciar-mundo borra el mundo" "$salida"
guardado=$(ls "$MINECRAFT_DIR/Respaldos/26.3 SMP-1/mundos/"*.tar.zst 2>/dev/null | head -1)
[[ -n "$guardado" ]] && tar --zstd -tf "$guardado" | grep -q 'world/region/r.0.0.mca' && ok "reiniciar-mundo guarda el mundo antes" || mal "reiniciar-mundo guarda el mundo antes"
# Plugins: un jar conocido en Modrinth, uno con versión nueva y uno desconocido (respuestas falsas)
FALSA="$TMP/api"; mkdir -p "$FALSA"; export MINECRAFT_API_FALSA="$FALSA"
for n in viejo actual raro; do (cd "$TMP" && mkdir -p j && echo "$n" > j/a.txt && rm -f "$S/26.3 SMP-1/plugins/$n.jar" && (cd j && python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.write('a.txt'); z.close()" "$S/26.3 SMP-1/plugins/$n.jar")); done
python3 - "$FALSA" "$S/26.3 SMP-1/plugins" <<'PY'
import hashlib, json, os, re, sys
falsa, plugins = sys.argv[1:3]
h = {n: hashlib.sha1(open(os.path.join(plugins, n + ".jar"), "rb").read()).hexdigest() for n in ("viejo", "actual", "raro")}
def guardar(url, datos):
    nombre = re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[:150] + ".json"
    json.dump(datos, open(os.path.join(falsa, nombre), "w"))
def version(vid, num, sha1):
    return {"id": vid, "project_id": "P" + vid[0], "version_number": num,
            "files": [{"primary": True, "url": "https://cdn.modrinth.com/x.jar", "filename": "nuevo.jar", "hashes": {"sha1": sha1, "sha512": "ab"}}]}
guardar("https://api.modrinth.com/v2/version_files", {h["viejo"]: version("v1", "1.0", h["viejo"]), h["actual"]: version("w1", "2.0", h["actual"])})
guardar("https://api.modrinth.com/v2/version_files/update", {h["viejo"]: version("v2", "1.5", "otro"), h["actual"]: version("w1", "2.0", h["actual"])})
guardar('https://api.modrinth.com/v2/projects?ids=%5B%22Pv%22%2C%20%22Pw%22%5D', [{"id": "Pv", "title": "Plugin Viejo"}, {"id": "Pw", "title": "Plugin Al Día"}])
PY
plug=$(MC plugins "26.3 SMP-1")
igual "plugin con versión nueva" "$(grep 'viejo.jar' <<< "$plug" | cut -f2,3,4,5 | tr '\t' '|')" "Plugin Viejo|1.0|1.5|NUEVA"
igual "plugin al día" "$(grep 'actual.jar' <<< "$plug" | cut -f5)" "AL_DIA"
igual "plugin que no está en Modrinth" "$(grep 'raro.jar' <<< "$plug" | cut -f5)" "DESCONOCIDO"
MC plugins-actualizar "26.3 SMP-1" "../../x.jar" > /dev/null; igual "plugins-actualizar rechaza rutas" "$?" "2"
unset MINECRAFT_API_FALSA
# Por grupo (desde la 4.13.0): Servidores/<grupo>/<versión>/<servidor>, con nombres repetidos entre grupos
mkdir -p "$S/Amigos/26.1/26.1.2 SMP-1/world" "$S/Primos/26.1/26.1.2 SMP-1" "$S/Primos/26.3" "$S/26.3 SMP-1/copia"
for g in Amigos Primos; do printf 'TIPO=paper\nVERSION=26.1.2\nJAR="Paper.jar"\nRAM=4G\n' > "$S/$g/26.1/26.1.2 SMP-1/servidor.conf"; done
printf 'TIPO=paper\n' > "$S/26.3 SMP-1/copia/servidor.conf"    # dentro de otro servidor: no cuenta
lista=$(MC servidores)
igual "por grupo: lista los dos SMP-1 con su ruta" "$(grep '26.1.2 SMP-1' <<< "$lista" | cut -f2 | tr '\n' '|')" "Amigos/26.1/26.1.2 SMP-1|Primos/26.1/26.1.2 SMP-1|"
igual "por grupo: no cuenta un servidor.conf dentro de otro servidor" "$(grep -c '^SERVIDOR ' <<< "$lista")" "4"
igual "por grupo: los mensajes dicen «servidor (grupo)»" "$(MC ram "Primos/26.1/26.1.2 SMP-1" 6G)" "LISTO 26.1.2 SMP-1 (Primos) va a usar hasta 6G de RAM (al iniciarlo de nuevo)."
igual "por grupo: cambia solo el de ese grupo" "$(grep -h '^RAM=' "$S/Amigos/26.1/26.1.2 SMP-1/servidor.conf" "$S/Primos/26.1/26.1.2 SMP-1/servidor.conf" | tr '\n' ' ')" 'RAM=4G RAM="6G" '
MC ram "26.1.2 SMP-1" 6G > /dev/null; igual "por grupo: sin el grupo no existe" "$?" "2"
MC ram "Amigos/../Primos/26.1/26.1.2 SMP-1" 6G > /dev/null; igual "por grupo: rechaza rutas con .." "$?" "2"
MC reiniciar-mundo "Amigos/26.1/26.1.2 SMP-1" > /dev/null
ls "$MINECRAFT_DIR/Respaldos/Amigos/26.1/26.1.2 SMP-1/mundos/"*.tar.zst &> /dev/null && ok "por grupo: el mundo va a Respaldos/<grupo>/<versión>/<servidor>" || mal "por grupo: respaldo del mundo"
rm -rf "$S/Amigos" "$S/Primos" "$S/26.3 SMP-1/copia"
# Consola compartida: un «java» falso que anota lo que recibe y se apaga con «stop», dentro de un tmux
# con socket propio de la prueba (no toca el de los servidores reales) y sin abrir terminales
MC comando "26.3 SMP-1" "say hola" > /dev/null; igual "comando rechaza un servidor apagado" "$?" "1"
MC comando "26.3 SMP-1" $'say a\nstop' > /dev/null; igual "comando rechaza saltos de línea" "$?" "2"
MC comando "26.3 SMP-1" "   " > /dev/null; igual "comando rechaza uno vacío" "$?" "2"
MC detener "26.3 SMP-1" "5; rm" > /dev/null; igual "detener rechaza segundos raros" "$?" "2"
if command -v tmux > /dev/null; then
    cat > "$falso_java/java" <<'SH'
#!/bin/bash
mkdir -p logs; echo "[INFO]: Done (args $*)" > logs/latest.log
while IFS= read -r l; do echo "[INFO]: recibido: $l" >> logs/latest.log; [[ $l == stop ]] && exit 0; done
SH
    chmod +x "$falso_java/java"
    touch "$S/26.3 SMP-1/paper-26.3-244.jar"
    export MINECRAFT_TMUX="prueba-manager-$$" MINECRAFT_SIN_TERMINAL=1
    PATH="$falso_java:$PATH" MC iniciar "26.3 SMP-1" > /dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q Done "$S/26.3 SMP-1/logs/latest.log" 2>/dev/null && break; sleep 0.3; done
    tmux -L "$MINECRAFT_TMUX" has-session -t "=mc-26_3_SMP-1" 2>/dev/null && ok "iniciar lo prende dentro de tmux (sesión mc-26_3_SMP-1)" || mal "iniciar en tmux"
    grep -q 'Done (args -Xms1G -Xmx12G -jar paper-26.3-244.jar nogui)' "$S/26.3 SMP-1/logs/latest.log" && ok "arranca java con la RAM y el jar" || mal "argumentos de java"
    MC comando "26.3 SMP-1" "/say hola \"amigos\" \$(id)" > /dev/null; sleep 0.5
    grep -qF 'recibido: say hola "amigos" $(id)' "$S/26.3 SMP-1/logs/latest.log" && ok "comando llega tal cual (sin «/» y sin interpretar)" || mal "comando llega tal cual"
    reg=$(timeout 2 bash "$LOGICA/Minecraft.sh" registro "26.3 SMP-1")
    igual "registro dice que acepta comandos" "$(head -1 <<< "$reg")" "CONSOLA COMANDOS"
    grep -q '^LINEA \[INFO\]: recibido: say hola' <<< "$reg" && ok "registro muestra las líneas" || mal "registro" "$reg"
    salida=$(MC detener "26.3 SMP-1" 2)
    grep -q 'recibido: say El servidor se apaga en 2 segundos.' "$S/26.3 SMP-1/logs/latest.log" && ok "detener avisa en el chat" || mal "detener avisa en el chat"
    grep -q 'recibido: stop' "$S/26.3 SMP-1/logs/latest.log" && ok "detener manda «stop»" || mal "detener manda stop"
    grep -q '^SERVIDOR APAGADO' <<< "$(MC servidores)" && ok "queda apagado" || mal "queda apagado" "$salida"
    # Cancelar mientras avisa: no se apaga y lo dice en el chat
    PATH="$falso_java:$PATH" MC iniciar "26.3 SMP-1" > /dev/null; sleep 1
    bash "$LOGICA/Minecraft.sh" detener "26.3 SMP-1" 30 > /dev/null & espera=$!
    sleep 1.5; kill -TERM "$espera"; wait "$espera" 2>/dev/null; sleep 0.5
    grep -q 'recibido: say Se canceló: el servidor no se apaga.' "$S/26.3 SMP-1/logs/latest.log" && ok "cancelar el aviso lo avisa" || mal "cancelar el aviso"
    grep -q '^SERVIDOR ENCENDIDO' <<< "$(MC servidores)" && ok "cancelar el aviso no lo apaga" || mal "cancelar el aviso no lo apaga"
    MC detener "26.3 SMP-1" > /dev/null
    tmux -L "$MINECRAFT_TMUX" kill-server 2>/dev/null
    unset MINECRAFT_TMUX MINECRAFT_SIN_TERMINAL
else
    echo "  (sin tmux: se saltean las pruebas de la consola compartida)"
fi
# jugadores: Server List Ping contra un servidor falso
puerto=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 - "$puerto" <<'PY2' &
import json, socket, sys
def varint(n):
    o = b""
    while True:
        b = n & 0x7F; n >>= 7
        o += bytes([b | (0x80 if n else 0)])
        if not n: return o
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", int(sys.argv[1]))); srv.listen(1); srv.settimeout(10)
c, _ = srv.accept(); c.recv(1024)
j = json.dumps({"players": {"online": 2, "max": 20, "sample": [{"name": "Steve"}, {"name": ".Alex"}]}}).encode()
cuerpo = varint(0) + varint(len(j)) + j
c.sendall(varint(len(cuerpo)) + cuerpo); c.close()
PY2
ping_falso=$!; sleep 0.5
igual "ping lee conectados, máximo y nombres" "$(python3 -I "$LOGICA/minecraft_api.py" ping "$puerto")" "$(printf 'JUGADORES 2\t20\tSteve,.Alex')"
wait "$ping_falso" 2>/dev/null
python3 -I "$LOGICA/minecraft_api.py" ping 99999 2>/dev/null; igual "ping rechaza un puerto fuera de rango" "$?" "1"
# Crear servidores (desde la 4.14.0): Mojang, PaperMC, Fabric y Modrinth falsos (archivos y file://), Java falso
echo "Minecraft.sh crear (APIs y Java falsos: no toca la red)"
FALSA="$TMP/api-crear"; mkdir -p "$FALSA" "$TMP/descargas"
export MINECRAFT_API_FALSA="$FALSA" MINECRAFT_FABRIC_META="file://$TMP/fabric" MINECRAFT_JVM_DIR="$TMP/jvm"
mkdir -p "$TMP/jvm/java-21-openjdk/bin" "$TMP/jvm/java-17-openjdk/bin"
printf '#!/bin/bash\necho "java21 $*" > "$PWD/java-usado.txt"\n' > "$TMP/jvm/java-21-openjdk/bin/java"
printf '#!/bin/bash\nexit 0\n' > "$TMP/jvm/java-17-openjdk/bin/java"
chmod +x "$TMP"/jvm/*/bin/java
PYTHONDONTWRITEBYTECODE=1 python3 - "$FALSA" "$TMP" "$LOGICA" <<'PY'
import gzip, hashlib, io, json, os, re, struct, sys, zipfile
falsa, tmp, logica = sys.argv[1:4]
sys.path.insert(0, logica)
import minecraft_api as m
def guardar(url, datos, ext=".json"):
    nombre = re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[:150] + ext
    with open(os.path.join(falsa, nombre), "w") as f:
        f.write(datos if ext == ".txt" else json.dumps(datos))
def jar(ruta, archivos):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with zipfile.ZipFile(ruta, "w") as z:
        for n, c in archivos.items():
            z.writestr(n, c)
    datos = open(ruta, "rb").read()
    return "file://" + ruta, hashlib.sha1(datos).hexdigest(), hashlib.sha256(datos).hexdigest(), hashlib.sha512(datos).hexdigest()
d = os.path.join(tmp, "descargas")
# Mojang: 26.3 (Java 21) y 26.1.2
u_srv, s1, _, _ = jar(f"{d}/server.jar", {"net/minecraft/Main.class": "x"})
guardar(m.MOJANG, {"versions": [
    {"id": "26.3", "type": "release", "url": "https://piston-meta.mojang.com/v1/packages/a/26.3.json"},
    {"id": "26.1.2", "type": "release", "url": "https://piston-meta.mojang.com/v1/packages/b/26.1.2.json"}]})
for v in ("26.3", "26.1.2"):
    guardar(f"https://piston-meta.mojang.com/v1/packages/{'a' if v == '26.3' else 'b'}/{v}.json",
            {"javaVersion": {"majorVersion": 21}, "downloads": {"server": {"url": u_srv, "sha1": s1}}})
# Paper 26.3
u_p, _, s256, _ = jar(f"{d}/paper-26.3-300.jar", {"io/papermc/Main.class": "x"})
guardar("https://fill.papermc.io/v3/projects/paper/versions/26.3/builds",
        [{"id": 300, "channel": "STABLE", "downloads": {"server:default": {"name": "paper-26.3-300.jar", "url": u_p, "checksums": {"sha256": s256}}}}])
# Fabric (el lanzador se baja de file://…/fabric/…)
fab = os.environ["MINECRAFT_FABRIC_META"]
guardar(f"{fab}/versions/loader/26.3", [{"loader": {"version": "0.20.1", "stable": True}}, {"loader": {"version": "0.19.0", "stable": True}}])
guardar(f"{fab}/versions/installer", [{"version": "1.1.2", "stable": True}])
for lv in ("0.20.1", "0.19.0"):
    jar(f"{tmp}/fabric/versions/loader/26.3/{lv}/1.1.2/server/jar", {"net/fabricmc/Launch.class": lv})
# Modrinth: «chunky» tiene Paper y Fabric (con Fabric API obligatoria); «solo-paper» no tiene Fabric; «sodium» es del cliente
def proyecto(slug, lado="optional", tipo="mod"):
    guardar(f"{m.MODRINTH}/project/{slug}", {"id": "id-" + slug, "slug": slug, "title": slug.capitalize(), "server_side": lado, "project_type": tipo})
def versiones(slug, tipo, lista):
    guardar(f"{m.MODRINTH}/project/{slug}/version?loaders=" + m.q(json.dumps(m.CARGADORES_TIPO[tipo])) + "&game_versions=" + m.q(json.dumps(["26.3"])), lista)
def version(archivo, contenido, deps=()):
    u, _, _, s512 = jar(f"{d}/{archivo}", contenido)
    return {"id": "v-" + archivo, "version_number": "1.0", "files": [{"primary": True, "url": u, "filename": archivo, "hashes": {"sha512": s512}}],
            "dependencies": [{"project_id": p, "dependency_type": "required"} for p in deps]}
for slug in ("chunky", "solo-paper", "fabric-api"):
    proyecto(slug)
guardar(f"{m.MODRINTH}/project/id-fabric-api", {"id": "id-fabric-api", "slug": "fabric-api", "title": "Fabric API", "server_side": "optional"})
proyecto("sodium", lado="unsupported")
versiones("chunky", "paper", [version("Chunky-Paper.jar", {"plugin.yml": "name: Chunky"})])
versiones("chunky", "fabric", [version("Chunky-Fabric.jar", {"fabric.mod.json": '{"id": "chunky"}'}, deps=["id-fabric-api"])])
versiones("fabric-api", "fabric", [version("fabric-api.jar", {"fabric.mod.json": '{"id": "fabric-api"}'})])
versiones("solo-paper", "paper", [version("SoloPaper.jar", {"plugin.yml": "name: S"})])
versiones("solo-paper", "fabric", [])
# Modpacks (.mrpack): uno bueno (Fabric 0.19.0, un mod de servidor, uno de cliente y config) y uno con una ruta peligrosa
u_mod, s1_mod, _, s512_mod = jar(f"{d}/lithium.jar", {"fabric.mod.json": "{}"})
def mrpack(ruta, archivos, deps):
    with zipfile.ZipFile(ruta, "w") as z:
        z.writestr("modrinth.index.json", json.dumps({"formatVersion": 1, "game": "minecraft", "versionId": "1", "name": "P",
                   "files": archivos, "dependencies": deps}))
        z.writestr("overrides/config/pack.txt", "de overrides")
        z.writestr("server-overrides/config/pack.txt", "de server-overrides")
        z.writestr("client-overrides/options.txt", "del cliente")
bueno = {"path": "mods/lithium.jar", "hashes": {"sha1": s1_mod, "sha512": s512_mod}, "downloads": [u_mod], "env": {"server": "required"}}
cliente = dict(bueno, path="mods/solo-cliente.jar", env={"server": "unsupported"})
mrpack(f"{d}/bueno.mrpack", [bueno, cliente], {"minecraft": "26.3", "fabric-loader": "0.19.0"})
mrpack(f"{d}/malo.mrpack", [dict(bueno, path="../../escapado.jar")], {"minecraft": "26.3", "fabric-loader": "0.19.0"})
mrpack(f"{d}/neoforge.mrpack", [bueno], {"minecraft": "26.3", "neoforge": "21.0"})
# Un mundo de 26.3 en un zip (level.dat con Data.Version.Name) y uno «del futuro»
def nbt_mundo(version):
    s = lambda t: struct.pack(">H", len(t.encode())) + t.encode()
    cuerpo = b"\x0a" + s("") + b"\x0a" + s("Data") + b"\x03" + s("SpawnX") + struct.pack(">i", 5) + b"\x0a" + s("Version") \
        + b"\x08" + s("Name") + s(version) + b"\x00" + b"\x00" + b"\x00"
    return gzip.compress(cuerpo)
for nombre, v in (("mundo", "26.3"), ("futuro", "27.1")):
    with zipfile.ZipFile(f"{d}/{nombre}.zip", "w") as z:
        z.writestr("MiMundo/level.dat", nbt_mundo(v))
        z.writestr("MiMundo/region/r.0.0.mca", "datos")
PY
C() { bash "$LOGICA/Minecraft.sh" crear 2>&1; }
dice() { grep -qF -- "$1" <<< "$2"; }    # (sin tubería: crear falla a propósito y pipefail lo tomaría como falla)
base='GRUPO=Amigos\nNOMBRE=Nuevo\nVERSION=26.3\nEULA=true\n'
salida=$(printf "${base}TIPO=paper\nRAM=6G\nMOTD=Servidor de Ñandú\nMODO=creative\nCOMPLEMENTO=chunky\nMUNDO=%s\n" "$TMP/descargas/mundo.zip" | C)
nuevo="$S/Amigos/26.3/26.3 Nuevo"
grep -q '^CREADO Amigos/26.3/26.3 Nuevo$' <<< "$salida" && ok "crear Paper: dice la ruta del servidor nuevo" || mal "crear Paper" "$(tail -3 <<< "$salida")"
grep -q $'^SERVIDOR APAGADO\tAmigos/26.3/26.3 Nuevo\tpaper\t26.3' <<< "$(MC servidores)" && ok "crear: aparece solo en la lista" || mal "crear: aparece en la lista"
igual "crear Paper: servidor.conf con jar, RAM y Java" "$(grep -E '^(TIPO|JAR|RAM|JAVA)=' "$nuevo/servidor.conf" | tr '\n' ' ')" 'TIPO=paper JAR="paper-26.3-300.jar" RAM=6G JAVA=21 '
[[ -f "$nuevo/plugins/Chunky-Paper.jar" && ! -e "$nuevo/plugins/Chunky-Fabric.jar" ]] && ok "crear Paper: baja la versión Paper del plugin" || mal "crear Paper: plugin"
[[ -f "$nuevo/world/level.dat" && -f "$nuevo/world/region/r.0.0.mca" ]] && ok "crear: copia el mundo del zip a world/" || mal "crear: mundo del zip"
grep -qx 'eula=true' "$nuevo/eula.txt" && grep -qx 'gamemode=creative' "$nuevo/server.properties" && grep -qx 'motd=Servidor de \\u00d1and\\u00fa' "$nuevo/server.properties" \
    && ok "crear: eula y server.properties (con acentos escapados)" || mal "crear: server.properties" "$(cat "$nuevo/server.properties")"
[[ ! -e "$MINECRAFT_DIR/.creando" ]] && ok "crear: no deja la carpeta temporal" || mal "crear: quedó .creando"
printf "${base}TIPO=paper\n" | C > /dev/null; igual "crear: rechaza un nombre que ya existe" "$?" "2"
printf 'GRUPO=Amigos\nNOMBRE=Otro\nVERSION=26.3\nTIPO=paper\n' | C > /dev/null; igual "crear: sin aceptar el EULA no crea" "$?" "2"
printf 'GRUPO=../x\nNOMBRE=Otro\nVERSION=26.3\nTIPO=paper\nEULA=true\n' | C > /dev/null; igual "crear: rechaza un grupo con /" "$?" "2"
dice 'Vanilla no usa plugins ni mods' "$(printf "${base/Nuevo/V}TIPO=vanilla\nCOMPLEMENTO=chunky\n" | C)" && ok "crear: Vanilla no acepta plugins ni mods" || mal "crear: Vanilla con plugins"
dice 'Los modpacks son para Fabric o Forge' "$(printf "${base/Nuevo/P}TIPO=paper\nMODPACK_ARCHIVO=%s\n" "$TMP/descargas/bueno.mrpack" | C)" && ok "crear: Paper no acepta modpacks" || mal "crear: Paper con modpack"
salida=$(printf "${base/Nuevo/F1}TIPO=fabric\nCOMPLEMENTO=solo-paper\n" | C)
grep -q 'no tiene versión para Fabric 26.3' <<< "$salida" && [[ ! -e "$S/Amigos/26.3/26.3 F1" ]] && ok "crear: no instala un plugin de Paper en Fabric (y no crea nada)" || mal "crear: plugin de Paper en Fabric" "$salida"
dice 'solo para el juego' "$(printf "${base/Nuevo/F2}TIPO=fabric\nCOMPLEMENTO=sodium\n" | C)" && ok "crear: rechaza mods solo de cliente" || mal "crear: mod de cliente"
salida=$(printf "${base/Nuevo/Fab}TIPO=fabric\nCOMPLEMENTO=chunky\n" | C); f="$S/Amigos/26.3/26.3 Fab"
[[ -f "$f/mods/Chunky-Fabric.jar" && -f "$f/mods/fabric-api.jar" ]] && ok "crear Fabric: el mod y su dependencia (Fabric API)" || mal "crear Fabric: mods" "$(tail -3 <<< "$salida")"
igual "crear Fabric: lanzador y server.jar" "$(grep '^JAR=' "$f/servidor.conf")|$( [[ -f "$f/server.jar" ]] && echo si)" 'JAR="fabric-server-mc.26.3-loader.0.20.1-launcher.1.1.2.jar"|si'
salida=$(printf "${base/Nuevo/Pack}TIPO=fabric\nMODPACK_ARCHIVO=%s\n" "$TMP/descargas/bueno.mrpack" | C); f="$S/Amigos/26.3/26.3 Pack"
igual "modpack: usa el cargador del pack" "$(grep '^LOADER=' "$f/servidor.conf" 2>/dev/null)" 'LOADER="0.19.0"'
[[ -f "$f/mods/lithium.jar" && ! -e "$f/mods/solo-cliente.jar" && ! -e "$f/options.txt" ]] && ok "modpack: solo lo del lado del servidor" || mal "modpack: archivos" "$(tail -3 <<< "$salida")"
igual "modpack: server-overrides pisa a overrides" "$(cat "$f/config/pack.txt" 2>/dev/null)" "de server-overrides"
sha=$(sha512sum "$TMP/descargas/bueno.mrpack" | cut -d' ' -f1)
salida=$(printf '%s\n' GRUPO=Amigos NOMBRE=Pack2 VERSION=26.3 EULA=true TIPO=fabric "MODPACK_URL=file://$TMP/descargas/bueno.mrpack" "MODPACK_SHA512=$sha" | C)
[[ -f "$S/Amigos/26.3/26.3 Pack2/mods/lithium.jar" ]] && ok "modpack de Modrinth: lo baja comprobando la suma" || mal "modpack por URL" "$(tail -2 <<< "$salida")"
dice 'Modpack de Modrinth raro' "$(printf '%s\n' GRUPO=Amigos NOMBRE=Pack3 VERSION=26.3 EULA=true TIPO=fabric "MODPACK_URL=http://x/y.mrpack" "MODPACK_SHA512=$sha" | C)" \
    && ok "modpack: solo por https" || mal "modpack por http"
salida=$(printf "${base/Nuevo/Malo}TIPO=fabric\nMODPACK_ARCHIVO=%s\n" "$TMP/descargas/malo.mrpack" | C)
grep -q 'peligros' <<< "$salida" && [[ ! -e "$S/Amigos/26.3/26.3 Malo" && ! -e "$TMP/escapado.jar" && ! -e "$MINECRAFT_DIR/escapado.jar" ]] \
    && ok "modpack: rechaza rutas que se salen de la carpeta (y no deja nada)" || mal "modpack peligroso" "$salida"
dice 'usa neoforge' "$(printf "${base/Nuevo/Neo}TIPO=fabric\nMODPACK_ARCHIVO=%s\n" "$TMP/descargas/neoforge.mrpack" | C)" && ok "modpack: rechaza uno de NeoForge en Fabric" || mal "modpack de NeoForge"
dice 'es de Minecraft 27.1' "$(printf "${base/Nuevo/Viejo}VERSION=26.1.2\nTIPO=vanilla\nMUNDO=%s\n" "$TMP/descargas/futuro.zip" | C)" && ok "crear: no abre un mundo más nuevo que la versión" || mal "crear: mundo del futuro"
printf "${base/Nuevo/Copia}TIPO=vanilla\nMUNDO_SERVIDOR=Amigos/26.3/26.3 Nuevo\n" | C > /dev/null
[[ -f "$S/Amigos/26.3/26.3 Copia/world/level.dat" ]] && ok "crear: copia el mundo de otro servidor" || mal "crear: mundo de otro servidor"
mkdir -p "$TMP/j"; (cd "$TMP/j" && echo x > plugin.yml && python3 -c "import zipfile; z=zipfile.ZipFile('p.jar','w'); z.write('plugin.yml'); z.close()")
dice 'no es un mod de Fabric' "$(printf "${base/Nuevo/F3}TIPO=fabric\nCOMPLEMENTO_ARCHIVO=%s\n" "$TMP/j/p.jar" | C)" && ok "crear: un .jar suelto tiene que ser del cargador" || mal "crear: jar suelto"
# Lo que ya había, con los tipos nuevos
dice 'no tiene versión para Fabric' "$(MC plugin solo-paper "Amigos/26.3/26.3 Fab")" && ok "plugin: en Fabric no instala un plugin de Paper" || mal "plugin en Fabric"
dice 'Vanilla: no usa plugins ni mods' "$(MC plugin chunky "Amigos/26.3/26.3 Copia")" && ok "plugin: en Vanilla no instala nada" || mal "plugin en Vanilla"
igual "plugins: en Fabric mira mods/" "$(MC plugins "Amigos/26.3/26.3 Fab" | tail -1)" "LISTO 2 mod(s) en 26.3 Fab (Amigos)."
if command -v tmux > /dev/null; then
    export MINECRAFT_TMUX="prueba-crear-$$" MINECRAFT_SIN_TERMINAL=1
    MC iniciar "Amigos/26.3/26.3 Fab" > /dev/null; sleep 1
    igual "iniciar usa el Java elegido al crearlo" "$(cat "$S/Amigos/26.3/26.3 Fab/java-usado.txt" 2>/dev/null)" "java21 -Xms1G -Xmx4G -jar fabric-server-mc.26.3-loader.0.20.1-launcher.1.1.2.jar nogui"
    tmux -L "$MINECRAFT_TMUX" kill-server 2>/dev/null
    unset MINECRAFT_TMUX MINECRAFT_SIN_TERMINAL
fi
# Administrar servidores (desde la 4.15.0): jugadores, opciones, respaldos, cambiar versión, pack, extras, apagado automático
echo "Minecraft.sh: jugadores, opciones, respaldos, cambiar, pack y apagado automático (todo falso)"
P1="$S/Amigos/26.3/26.3 Nuevo"     # Paper (de las pruebas de crear)
printf '[{"uuid":"u-steve","name":"Steve","expiresOn":"2026-12-20 10:00:00 -0300"},{"uuid":"u-alex","name":"Alex","expiresOn":"2026-12-01 10:00:00 -0300"}]' > "$P1/usercache.json"
printf '[{"uuid":"u-alex","name":"Alex","level":4,"bypassesPlayerLimit":false}]' > "$P1/ops.json"
lista=$(MC jugadores-lista "Amigos/26.3/26.3 Nuevo")
igual "jugadores: lista con op y última vez" "$(grep '^JUGADOR Alex' <<< "$lista" | cut -f4,5,6,8 | tr '\t' '|')" "4|0|0|2026-11-01"
grep -q '^LISTA_BLANCA false' <<< "$lista" && ok "jugadores: dice si hay lista blanca" || mal "jugadores: lista blanca" "$lista"
sed -i 's/^online-mode=.*/online-mode=false/' "$P1/server.properties"
MC jugador "Amigos/26.3/26.3 Nuevo" whitelist-add Notch > /dev/null
igual "jugador (apagado): UUID offline como Minecraft" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["uuid"])' "$P1/whitelist.json")" "b50ad385-829d-3141-a216-7e7d7539ba7f"
MC jugador "Amigos/26.3/26.3 Nuevo" ban Steve "por griefer" > /dev/null
igual "jugador: ban con motivo" "$(grep '^JUGADOR Steve' <<< "$(MC jugadores-lista "Amigos/26.3/26.3 Nuevo")" | cut -f6,7 | tr '\t' '|')" "1|por griefer"
MC jugador "Amigos/26.3/26.3 Nuevo" pardon Steve > /dev/null; MC jugador "Amigos/26.3/26.3 Nuevo" deop Alex > /dev/null
igual "jugador: pardon y deop" "$(cat "$P1/banned-players.json" "$P1/ops.json" | tr -d ' \n')" "[][]"
MC jugador "Amigos/26.3/26.3 Nuevo" op 'Steve;rm' > /dev/null; igual "jugador: rechaza nombres raros" "$?" "2"
dice 'nunca entró' "$(MC jugador "Amigos/26.3/26.3 Nuevo" op .Bedrock1)" && ok "jugador: uno de Bedrock que nunca entró pide el servidor prendido" || mal "jugador bedrock"
MC jugador "Amigos/26.3/26.3 Nuevo" lista-blanca-si > /dev/null
grep -qx 'white-list=true' "$P1/server.properties" && grep -qx 'enforce-whitelist=true' "$P1/server.properties" && ok "jugador: activar la lista blanca (apagado)" || mal "lista blanca"
# Opciones
op=$(MC opciones-servidor "Amigos/26.3/26.3 Nuevo")
igual "opciones: lee el MOTD (con escapes)" "$(grep '^OPCION motd' <<< "$op" | cut -f6)" "Servidor de Ñandú"
grep -q $'^AJUSTE APAGAR_VACIO\t10' <<< "$op" && ok "opciones: ajustes del Manager (apagado automático: 10 min)" || mal "opciones: ajustes" "$op"
printf 'motd=§aHola§r\\nlínea 2\ndifficulty=hard\npvp=false\n' | MC propiedades-cambiar "Amigos/26.3/26.3 Nuevo" > /dev/null
grep -qx 'motd=\\u00a7aHola\\u00a7r\\nl\\u00ednea 2' "$P1/server.properties" && grep -qx 'difficulty=hard' "$P1/server.properties" && grep -qx 'gamemode=creative' "$P1/server.properties" \
    && ok "opciones: guarda MOTD con colores y dos líneas, sin tocar lo demás" || mal "opciones: guardar" "$(cat "$P1/server.properties")"
igual "opciones: lee lo guardado" "$(MC opciones-servidor "Amigos/26.3/26.3 Nuevo" | grep '^OPCION motd' | cut -f6)" '§aHola§r\nlínea 2'
printf 'motd=Fih 🐔 ñ\n' | MC propiedades-cambiar "Amigos/26.3/26.3 Nuevo" > /dev/null
grep -qx 'motd=Fih \\ud83d\\udc14 \\u00f1' "$P1/server.properties" && ok "opciones: escribe emojis como Java (par sustituto)" || mal "opciones: emoji" "$(grep motd "$P1/server.properties")"
igual "opciones: lee el emoji de vuelta" "$(MC opciones-servidor "Amigos/26.3/26.3 Nuevo" | grep '^OPCION motd' | cut -f6)" "Fih 🐔 ñ"
mkdir -p "$TMP/utf8"; printf 'motd=Fih \xf0\x9f\x90\x94\n' > "$TMP/utf8/server.properties"
igual "opciones: lee un server.properties en UTF-8" "$(python3 -I "$LOGICA/minecraft_api.py" opciones-servidor "$TMP/utf8" 2>/dev/null | grep '^OPCION motd' | cut -f6)" "Fih 🐔"
printf 'server-port=1\n' | MC propiedades-cambiar "Amigos/26.3/26.3 Nuevo" > /dev/null; igual "opciones: no deja tocar claves fuera de la lista" "$?" "1"
printf 'max-players=9999\n' | MC propiedades-cambiar "Amigos/26.3/26.3 Nuevo" > /dev/null; igual "opciones: rechaza valores fuera de rango" "$?" "1"
igual "ajuste: minutos del apagado automático" "$(MC ajuste "Amigos/26.3/26.3 Nuevo" APAGAR_VACIO 5 >/dev/null; grep '^APAGAR_VACIO' "$P1/servidor.conf")" 'APAGAR_VACIO="5"'
MC ajuste "Amigos/26.3/26.3 Nuevo" APAGAR_VACIO 99999 > /dev/null; igual "ajuste: rechaza valores raros" "$?" "2"
printf 'APAGAR_PC=no\npvp=true\n' | MC propiedades-cambiar "Amigos/26.3/26.3 Nuevo" > /dev/null
grep -qE '^APAGAR_PC="?no' "$P1/servidor.conf" && grep -qx 'pvp=true' "$P1/server.properties" && ok "opciones: guarda ajustes del Manager y del servidor juntos" || mal "opciones + ajustes"
printf 'APAGAR_PC=quizas\n' | MC propiedades-cambiar "Amigos/26.3/26.3 Nuevo" > /dev/null; igual "opciones: rechaza ajustes raros" "$?" "2"
printf 'APAGAR_PC=si\n' | MC propiedades-cambiar "Amigos/26.3/26.3 Nuevo" > /dev/null
python3 -c 'import struct,sys,zlib; open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"+struct.pack(">I",13)+b"IHDR"+struct.pack(">II",64,64)+b"\x08\x06\x00\x00\x00")' "$TMP/i64.png"
python3 -c 'import struct,sys; open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"+struct.pack(">I",13)+b"IHDR"+struct.pack(">II",128,128)+b"\x08\x06\x00\x00\x00")' "$TMP/i128.png"
MC icono "Amigos/26.3/26.3 Nuevo" "$TMP/i64.png" > /dev/null && [[ -f "$P1/server-icon.png" ]] && ok "icono: copia un PNG de 64×64" || mal "icono"
MC icono "Amigos/26.3/26.3 Nuevo" "$TMP/i128.png" > /dev/null; igual "icono: rechaza otro tamaño" "$?" "2"
igual "servidores: décimo campo con la ruta del ícono" "$(MC servidores | grep $'\tAmigos/26.3/26.3 Nuevo\t' | cut -f10)" "$P1/server-icon.png"
MC abrir-carpeta ../../etc > /dev/null; igual "abrir-carpeta: solo servidores o respaldos" "$?" "2"
# Respaldos
MC respaldo-guardar "Amigos/26.3/26.3 Nuevo" > /dev/null
copia=$(ls "$MINECRAFT_DIR/Respaldos/Amigos/26.3/26.3 Nuevo/mundos/"*.tar.zst 2>/dev/null | head -1)
[[ -n "$copia" ]] && ok "respaldo-guardar: guarda el mundo" || mal "respaldo-guardar"
grep -q $'^RESPALDO mundo\t' <<< "$(MC respaldos "Amigos/26.3/26.3 Nuevo")" && ok "respaldos: los lista" || mal "respaldos: lista"
echo cambiado > "$P1/world/region/r.0.0.mca"
MC restaurar "Amigos/26.3/26.3 Nuevo" mundo "$(basename "$copia")" > /dev/null
igual "restaurar: vuelve el mundo guardado" "$(cat "$P1/world/region/r.0.0.mca")" "datos"
ls "$MINECRAFT_DIR/Respaldos/Amigos/26.3/26.3 Nuevo/mundos/"*antes-de-restaurar*.tar.zst &> /dev/null && ok "restaurar: guarda antes el mundo que había" || mal "restaurar: guarda el anterior"
mkdir -p "$TMP/malo/x"; echo pwn > "$TMP/malo/x/evil"; tar --zstd -cf "$MINECRAFT_DIR/Respaldos/Amigos/26.3/26.3 Nuevo/mundos/malo.tar.zst" -C "$TMP/malo" --transform 's|^x|world/../../escapado|' x
MC restaurar "Amigos/26.3/26.3 Nuevo" mundo malo.tar.zst > /dev/null
[[ $? -ne 0 && -f "$P1/world/level.dat" && ! -e "$S/Amigos/escapado" ]] && ok "restaurar: rechaza un respaldo con rutas que se salen (y no toca el mundo)" || mal "restaurar malicioso"
MC restaurar "Amigos/26.3/26.3 Nuevo" mundo "../../x.tar.zst" > /dev/null; igual "restaurar: rechaza rutas" "$?" "2"
# Cambiar: Paper 26.3 → Fabric 26.3 (Chunky pasa a su versión Fabric y se suma Fabric API) y una versión más vieja que el mundo
cp -r "$FALSA" "$TMP/api-cambiar"; export MINECRAFT_API_FALSA="$TMP/api-cambiar"
PYTHONDONTWRITEBYTECODE=1 python3 - "$TMP/api-cambiar" "$TMP" "$LOGICA" "$P1" <<'PY'
import hashlib, json, os, re, sys
falsa, tmp, logica, p1 = sys.argv[1:5]
sys.path.insert(0, logica)
import minecraft_api as m
def guardar(url, datos):
    json.dump(datos, open(os.path.join(falsa, re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[:150] + ".json"), "w"))
d = os.path.join(tmp, "descargas")
def ver(archivo, proyecto, deps=()):
    datos = open(os.path.join(d, archivo), "rb").read()
    return {"id": "v-" + archivo, "project_id": proyecto, "version_number": "1.0",
            "files": [{"primary": True, "url": "file://" + os.path.join(d, archivo), "filename": archivo,
                       "hashes": {"sha1": hashlib.sha1(datos).hexdigest(), "sha512": hashlib.sha512(datos).hexdigest()}}],
            "dependencies": [{"project_id": x, "dependency_type": "required"} for x in deps]}
s1 = lambda a: hashlib.sha1(open(os.path.join(d, a), "rb").read()).hexdigest()
guardar(f"{m.MODRINTH}/version_files", {s1("Chunky-Paper.jar"): ver("Chunky-Paper.jar", "id-chunky"),
                                        s1("Chunky-Fabric.jar"): ver("Chunky-Fabric.jar", "id-chunky", ["id-fabric-api"])})
guardar(f"{m.MODRINTH}/version_files/update", {s1("Chunky-Paper.jar"): ver("Chunky-Fabric.jar", "id-chunky")})
guardar(f"{m.MODRINTH}/projects?ids=" + m.q(json.dumps(["id-chunky"])), [{"id": "id-chunky", "title": "Chunky", "client_side": "unsupported"}])
PY
mkdir -p "$P1/world_nether/DIM-1/region"; echo nether > "$P1/world_nether/DIM-1/region/r.0.0.mca"
mkdir -p "$P1/world/dimensions/minecraft/overworld/data/minecraft"; echo ajustes > "$P1/world/dimensions/minecraft/overworld/data/minecraft/world_gen_settings.dat"
salida=$(printf 'TIPO=fabric\nVERSION=26.3\n' | MC cambiar "Amigos/26.3/26.3 Nuevo")
grep -q '^CREADO Amigos/26.3/26.3 Nuevo$' <<< "$salida" && grep -qE '^TIPO="?fabric' "$P1/servidor.conf" && ok "cambiar: Paper → Fabric" || mal "cambiar Paper → Fabric" "$(tail -3 <<< "$salida")"
[[ -f "$P1/mods/Chunky-Fabric.jar" && -f "$P1/mods/fabric-api.jar" && ! -d "$P1/plugins" ]] && ok "cambiar: el plugin pasa a su mod (y se suma la dependencia)" || mal "cambiar: complementos" "$(ls "$P1"/mods "$P1"/plugins 2>&1 | tr '\n' ' ')"
[[ -f "$P1/world/DIM-1/region/r.0.0.mca" && ! -e "$P1/world_nether" ]] && ok "cambiar: el nether de Paper vuelve adentro del mundo" || mal "cambiar: nether"
igual "cambiar: world_gen_settings.dat de Paper donde lo busca el juego" "$(cat "$P1/world/data/minecraft/world_gen_settings.dat" 2>/dev/null)" "ajustes"
ls "$MINECRAFT_DIR/Respaldos/Amigos/26.3/26.3 Nuevo/viejo/paper-26.3-300.jar" &> /dev/null && ok "cambiar: el jar de Paper queda en Respaldos" || mal "cambiar: jar viejo"
dice 'no se puede abrir en 26.1.2' "$(printf 'TIPO=fabric\nVERSION=26.1.2\n' | MC cambiar "Amigos/26.3/26.3 Nuevo")" && ok "cambiar: no baja la versión por debajo de la del mundo" || mal "cambiar: versión del mundo"
mkdir -p "$S/Amigos/26.1/26.1.2 Mover"; printf 'NOMBRE="26.1.2 Mover"\nTIPO=vanilla\nVERSION=26.1.2\nJAR="server.jar"\nRAM=2G\n' > "$S/Amigos/26.1/26.1.2 Mover/servidor.conf"
salida=$(printf 'TIPO=paper\nVERSION=26.3\n' | MC cambiar "Amigos/26.1/26.1.2 Mover")
[[ -f "$S/Amigos/26.3/26.3 Mover/servidor.conf" && ! -e "$S/Amigos/26.1/26.1.2 Mover" ]] && grep -q '^CREADO Amigos/26.3/26.3 Mover$' <<< "$salida" \
    && ok "cambiar: la carpeta pasa a la de la versión nueva" || mal "cambiar: mover carpeta" "$(tail -2 <<< "$salida")"
# Pack para jugadores
cp -r "$FALSA" "$TMP/api-pack"; export MINECRAFT_API_FALSA="$TMP/api-pack"
F="$S/Amigos/26.3/26.3 Fab"; (cd "$TMP/j" && echo '{}' > fabric.mod.json && python3 -c "import zipfile; z=zipfile.ZipFile('raro.jar','w'); z.write('fabric.mod.json'); z.close()"); cp "$TMP/j/raro.jar" "$F/mods/"
PYTHONDONTWRITEBYTECODE=1 python3 - "$TMP/api-pack" "$TMP" "$LOGICA" <<'PY'
import hashlib, json, os, re, sys
falsa, tmp, logica = sys.argv[1:4]
sys.path.insert(0, logica)
import minecraft_api as m
def guardar(url, datos):
    json.dump(datos, open(os.path.join(falsa, re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[:150] + ".json"), "w"))
d = os.path.join(tmp, "descargas")
def ver(archivo, proyecto):
    datos = open(os.path.join(d, archivo), "rb").read()
    return {"id": "v-" + archivo, "project_id": proyecto, "version_number": "1.0",
            "files": [{"primary": True, "url": "https://cdn.modrinth.com/" + archivo, "filename": archivo,
                       "hashes": {"sha1": hashlib.sha1(datos).hexdigest(), "sha512": hashlib.sha512(datos).hexdigest()}}]}
s1 = lambda a: hashlib.sha1(open(os.path.join(d, a), "rb").read()).hexdigest()
guardar(f"{m.MODRINTH}/version_files", {s1("Chunky-Fabric.jar"): ver("Chunky-Fabric.jar", "id-chunky"), s1("fabric-api.jar"): ver("fabric-api.jar", "id-fabric-api")})
guardar(f"{m.MODRINTH}/projects?ids=" + m.q(json.dumps(["id-chunky", "id-fabric-api"])),
        [{"id": "id-chunky", "client_side": "unsupported"}, {"id": "id-fabric-api", "client_side": "required"}])
PY
salida=$(MC pack-jugadores "Amigos/26.3/26.3 Fab" "$TMP/jugadores.mrpack")
indice=$(python3 -c 'import json,sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); i=json.loads(z.read("modrinth.index.json")); print(" ".join(sorted(f["path"] for f in i["files"])), i["dependencies"]["fabric-loader"], " ".join(n for n in z.namelist() if n.startswith("overrides")))' "$TMP/jugadores.mrpack" 2>&1)
igual "pack: lo del cliente con descarga, lo de servidor afuera, lo desconocido adentro" "$indice" "mods/fabric-api.jar 0.20.1 overrides/mods/raro.jar"
MC pack-jugadores "Amigos/26.3/26.3 Pack" "$TMP/pack2.mrpack" > /dev/null
igual "pack: si salió de un modpack, también lleva lo que es solo del cliente" "$(python3 -c 'import json,sys,zipfile; print(len(json.loads(zipfile.ZipFile(sys.argv[1]).read("modrinth.index.json"))["files"]))' "$TMP/pack2.mrpack")" "2"
dice 'no necesitan mods' "$(MC pack-jugadores "Amigos/26.3/26.3 Copia" "$TMP/x.mrpack")" && ok "pack: Vanilla no tiene pack" || mal "pack Vanilla"
# Extras: Geyser en Forge no; BlueMap en Fabric sí (con la marca para aceptar la descarga al iniciar)
PYTHONDONTWRITEBYTECODE=1 python3 - "$TMP/api-pack" "$TMP" "$LOGICA" <<'PY'
import hashlib, json, os, re, sys, zipfile
falsa, tmp, logica = sys.argv[1:4]
sys.path.insert(0, logica)
import minecraft_api as m
def guardar(url, datos):
    json.dump(datos, open(os.path.join(falsa, re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[:150] + ".json"), "w"))
r = os.path.join(tmp, "descargas", "BlueMap-Fabric.jar")
with zipfile.ZipFile(r, "w") as z: z.writestr("fabric.mod.json", "{}")
datos = open(r, "rb").read()
guardar(f"{m.MODRINTH}/project/bluemap", {"id": "id-bluemap", "slug": "bluemap", "title": "BlueMap", "server_side": "required"})
guardar(f"{m.MODRINTH}/project/bluemap/version?loaders=" + m.q(json.dumps(["fabric"])) + "&game_versions=" + m.q(json.dumps(["26.3"])),
        [{"id": "vb", "version_number": "5.0", "files": [{"primary": True, "url": "file://" + r, "filename": "BlueMap-Fabric.jar", "hashes": {"sha512": hashlib.sha512(datos).hexdigest()}}]}])
PY
MC extra "Amigos/26.3/26.3 Fab" bluemap > /dev/null
[[ -f "$F/mods/BlueMap-Fabric.jar" && -f "$F/.bluemap-aceptado" ]] && ok "extra: BlueMap (y la marca para aceptar su descarga)" || mal "extra bluemap"
mkdir -p "$F/config/bluemap"; echo 'accept-download: false' > "$F/config/bluemap/core.conf"
dice 'Vanilla' "$(MC extra "Amigos/26.3/26.3 Copia" geyser)" && ok "extra: Vanilla no lleva extras" || mal "extra vanilla"
export MINECRAFT_API_FALSA="$FALSA"
# Apagado automático: java falso que no se apaga solo, jugadores falsos, 1 «minuto» = 1 segundo
if command -v tmux > /dev/null; then
    printf '#!/bin/bash\nmkdir -p logs; echo "[INFO]: Done" > logs/latest.log\nwhile IFS= read -r l; do echo "[INFO]: recibido: $l" >> logs/latest.log; [[ $l == save-all* ]] && echo "[INFO]: Saved the game" >> logs/latest.log; [[ $l == stop ]] && exit 0; done\n' > "$TMP/jvm/java-21-openjdk/bin/java"
    export MINECRAFT_TMUX="prueba-vigilar-$$" MINECRAFT_SIN_TERMINAL=1 MINECRAFT_VIGILAR=1 MINECRAFT_VIGILAR_INTERVALO=1 MINECRAFT_VIGILAR_MINUTO=1
    export MINECRAFT_JUGADORES_FALSO="$TMP/conectados" MINECRAFT_APAGAR_PC_FALSO="$TMP/apagar-pc"
    echo 1 > "$TMP/conectados"
    MC ajuste "Amigos/26.3/26.3 Fab" APAGAR_VACIO 3 > /dev/null
    MC iniciar "Amigos/26.3/26.3 Fab" > /dev/null
    grep -q 'accept-download: true' "$F/config/bluemap/core.conf" && ok "iniciar: acepta la descarga de BlueMap" || mal "iniciar: BlueMap"
    sleep 5
    grep -q $'^SERVIDOR ENCENDIDO\tAmigos/26.3/26.3 Fab' <<< "$(MC servidores)" && ok "apagado automático: con jugadores sigue prendido" || mal "apagado automático: con jugadores"
    # Con el servidor prendido, los jugadores se administran con comandos y el mundo se guarda pausando el guardado
    MC jugador "Amigos/26.3/26.3 Fab" op Steve > /dev/null; sleep 0.5
    grep -q 'recibido: op Steve' "$F/logs/latest.log" && ok "jugador (prendido): lo manda como comando" || mal "jugador prendido"
    mkdir -p "$F/world"; echo x > "$F/world/level.dat"
    MC respaldo-guardar "Amigos/26.3/26.3 Fab" > /dev/null
    grep -q 'recibido: save-off' "$F/logs/latest.log" && grep -q 'recibido: save-on' "$F/logs/latest.log" && ok "respaldo-guardar (prendido): save-off, save-all y save-on" || mal "respaldo prendido"
    echo 'accept-download: false' > "$F/config/bluemap/core.conf"; sleep 2
    grep -q 'accept-download: true' "$F/config/bluemap/core.conf" && grep -q 'recibido: bluemap reload' "$F/logs/latest.log" \
        && ok "BlueMap: acepta la descarga cuando aparece su core.conf y lo recarga" || mal "BlueMap en el primer arranque"
    echo 0 > "$TMP/conectados"; sleep 2
    igual "apagado automático: la lista dice en cuánto se apaga" "$(MC servidores | grep 'Amigos/26.3/26.3 Fab' | cut -f9)" "1"
    for _ in $(seq 1 20); do grep -q $'^SERVIDOR APAGADO\tAmigos/26.3/26.3 Fab' <<< "$(MC servidores)" && break; sleep 0.5; done
    grep -q $'^SERVIDOR APAGADO\tAmigos/26.3/26.3 Fab' <<< "$(MC servidores)" && ok "apagado automático: sin jugadores se apaga" || mal "apagado automático: sin jugadores"
    sleep 1; grep -q 'apagar pc' "$TMP/apagar-pc" 2>/dev/null && ok "apagado automático: después pide apagar la PC" || mal "apagado automático: apagar la PC"
    tmux -L "$MINECRAFT_TMUX" kill-server 2>/dev/null
    unset MINECRAFT_TMUX MINECRAFT_SIN_TERMINAL MINECRAFT_VIGILAR_INTERVALO MINECRAFT_VIGILAR_MINUTO MINECRAFT_JUGADORES_FALSO MINECRAFT_APAGAR_PC_FALSO
    export MINECRAFT_VIGILAR=0
fi
unset MINECRAFT_API_FALSA MINECRAFT_FABRIC_META MINECRAFT_JVM_DIR
unset MINECRAFT_DIR

echo "AUR.sh (pacman y AUR falsos: no toca la red ni instala nada)"
falso="$TMP/bin"; mkdir -p "$falso"
cat > "$falso/pacman" <<'SH'
#!/bin/bash
# pacman -Q falso: Claude viejo y Heroic al día
case "$2" in
    claude-desktop) echo "claude-desktop 4.4212.0-1" ;;
    heroic-games-launcher-bin) echo "heroic-games-launcher-bin 2.22.4-1" ;;
    *) exit 1 ;;
esac
SH
chmod +x "$falso/pacman"
export AUR_RPC_FALSA="$TMP/aur.json"
cat > "$AUR_RPC_FALSA" <<'EOF2'
{"version":5,"type":"multiinfo","resultcount":5,"results":[
 {"Name":"claude-desktop","Version":"5.11492.5-1"},
 {"Name":"equibop-bin","Version":"3.3.4-1"},
 {"Name":"heroic-games-launcher-bin","Version":"2.22.4-1"},
 {"Name":"lcl-gui-bin","Version":"4.9.2-1; rm -rf ~"},
 {"Name":"otro-paquete","Version":"1.0-1"}]}
EOF2
AUR() { PATH="$falso:$PATH" bash "$LOGICA/AUR.sh" "$@"; }
apps() { AUR estado | sed -n 's/^APP \([^\t]*\).*/\1/p' | tr '\n' ' '; }
export MANAGER_MAC_PRUEBA="58:11:22:a9:df:de"
igual "la PC de Sebastián ve las 5 (sin PSeInt)" "$(apps)" "claude-desktop equibop-bin heroic-games-launcher-bin lcl-gui-bin playit-bin "
bash "$LOGICA/Entorno.sh" --equipo instituto >/dev/null
igual "el instituto ve las 5 y PSeInt" "$(apps)" "claude-desktop equibop-bin heroic-games-launcher-bin lcl-gui-bin pseint-bin playit-bin "
bash "$LOGICA/Entorno.sh" --equipo krocante >/dev/null
igual "la tía ve solo Claude" "$(apps)" "claude-desktop "
bash "$LOGICA/Entorno.sh" --equipo auto >/dev/null
MANAGER_MAC_PRUEBA="18:c0:4d:a2:fe:e0"
igual "mamá ve solo Claude" "$(apps)" "claude-desktop "
MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff"
igual "otra PC ve todas menos Claude, Playit y PSeInt" "$(apps)" "equibop-bin heroic-games-launcher-bin lcl-gui-bin "
MANAGER_MAC_PRUEBA="58:11:22:a9:df:de"
estado=$(AUR estado)
igual "informa la versión instalada" "$(grep -P '^APP claude-desktop\t' <<< "$estado" | cut -f4)" "4.4212.0-1"
igual "Claude tiene versión nueva" "$(grep -P '^AUR claude-desktop\t' <<< "$estado" | cut -f2,3 | tr '\t' ' ')" "5.11492.5-1 NUEVA"
igual "Heroic está al día" "$(grep -P '^AUR heroic' <<< "$estado" | cut -f3)" "AL_DIA"
igual "Equibop no está instalado" "$(grep -P '^AUR equibop' <<< "$estado" | cut -f3)" "NO_INSTALADA"
grep -q '^AUR lcl-gui-bin' <<< "$estado" && mal "acepta una versión con comandos" || ok "ignora una versión con comandos"
grep -q 'otro-paquete' <<< "$estado" && mal "muestra un paquete que no pidió" || ok "ignora paquetes que no pidió"
igual "pendientes: solo las instaladas con versión nueva" "$(AUR pendientes | tr '\n' ' ')" "PENDIENTE claude-desktop "
AUR pendientes > /dev/null; igual "pendientes sale con 0 aunque la última esté al día" "$?" "0"
AUR estado > /dev/null; igual "estado sale con 0" "$?" "0"
echo 'no es json' > "$AUR_RPC_FALSA"
AUR estado > /dev/null; igual "sin respuesta del AUR sale con 1" "$?" "1"
AUR cualquiera > /dev/null; igual "uso desconocido sale con 2" "$?" "2"
instalar() { PATH="$falso:$PATH" bash "$RES/General/AUR-instalar.sh" --sin-pausa "$@" < /dev/null > /dev/null 2>&1; }
instalar yay; igual "AUR-instalar rechaza un paquete que no es de la lista" "$?" "2"
MANAGER_MAC_PRUEBA="18:c0:4d:a2:fe:e0"
instalar equibop-bin; igual "en la PC de mamá rechaza Equibop" "$?" "2"
MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff"
instalar playit-bin; igual "en otra PC rechaza Playit" "$?" "2"
instalar; igual "AUR-instalar sin paquetes sale con 2" "$?" "2"
MANAGER_MAC_PRUEBA="18:c0:4d:a2:fe:e0"
instalar pseint-bin; igual "en la PC de mamá rechaza PSeInt" "$?" "2"
MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff"
instalar pseint-bin; igual "en otra PC rechaza PSeInt" "$?" "2"
MANAGER_MAC_PRUEBA="58:11:22:a9:df:de"
bash "$LOGICA/Entorno.sh" --equipo auto >/dev/null
instalar pseint-bin; igual "en la PC de Sebastián rechaza PSeInt (es solo del instituto)" "$?" "2"

echo "PSeInt: perfil del lenguaje y acceso directo (carpeta personal temporal)"
export PSEINT_DIR="$TMP/opt-pseint"; mkdir -p "$PSEINT_DIR"; echo "20250314" > "$PSEINT_DIR/version"
PS_CFG="$HOME/.pseint/config"; PS_DESK="$XDG_DATA_HOME/applications/pseint.desktop"
rm -rf "$HOME/.pseint" "$PS_DESK"
preparar() { bash -c 'source "$COMMON/Equipo.sh"; source "$COMMON/AUR.sh"; aur_pseint_preparar' > /dev/null; }
preparar
igual "crea ~/.pseint/config con la versión instalada" "$(grep '^version=' "$PS_CFG")" "version=20250314"
igual "perfil personalizado" "$(grep -E '^profile(:source)?=' "$PS_CFG" | tr '\n' ' ')" "profile=<Personalizado> profile:source=custom "
igual "la fuente de una instalación nueva (Inconsolata)" "$(grep -c -E '^(wx|term)_font_name=Inconsolata$' "$PS_CFG")" "2"
# Las 24 opciones de la captura Pseint.png, en el orden del diálogo
esperado="force_init_vars=1 force_define_vars=1 force_semicolon=0 allow_concatenation=1 enable_string_functions=1 word_operators=1 base_zero_arrays=0 allow_dinamyc_dimensions=1 allow_resize_arrays=1 overload_equal=1 enable_user_functions=1 lazy_syntax=1 coloquial_conditions=1 integer_only_switch=0 deduce_negative_for_step=1 use_nassi_shneiderman=0 use_alternative_io_shapes=0 allow_accents=1 prefer_algoritmo=0 prefer_funcion=0 allow_repeat_while=1 allow_for_each=1 prefer_repeat_while=0 protect_for_counter=0"
igual "las 24 opciones del lenguaje como en la captura" "$(sed -n 's/^profile:\([a-z_]*=[01]\)$/\1/p' "$PS_CFG" | tr '\n' ' ' | sed 's/ $//')" "$esperado"
grep -q '^Exec=.*/opt-pseint/wxPSeInt %F$' "$PS_DESK" && grep -q '^TryExec=' "$PS_DESK" && grep -q '^X-Arch-Linux-Manager=' "$PS_DESK" \
    && ok "pone un acceso directo que abre wxPSeInt (con TryExec)" || mal "acceso directo de PSeInt" "$(cat "$PS_DESK" 2>&1)"
echo "force_semicolon=1 cambiado por el usuario" >> "$PS_CFG"; antes=$(md5sum < "$PS_CFG")
sed -i 's/^Name=PSeInt$/Name=Viejo/' "$PS_DESK"
preparar
igual "no pisa una configuración que ya existe" "$(md5sum < "$PS_CFG")" "$antes"
igual "rehace su propio acceso directo" "$(grep '^Name=' "$PS_DESK")" "Name=PSeInt"
printf '[Desktop Entry]\nName=El mío\n' > "$PS_DESK"
preparar
igual "no toca un acceso directo que no es del Manager" "$(grep '^Name=' "$PS_DESK")" "Name=El mío"
rm -rf "$HOME/.pseint" "$PS_DESK"; echo "basura" > "$PSEINT_DIR/version"
preparar
igual "con una versión rara usa 20250314" "$(grep '^version=' "$PS_CFG")" "version=20250314"

# De punta a punta: AUR-instalar.sh con curl, makepkg, sudo y pacman falsos (no baja ni instala nada)
rm -rf "$HOME/.pseint" "$PS_DESK"
FI="$TMP/falsos-instalar"; mkdir -p "$FI/src/pseint-bin"
echo "pkgname=pseint-bin" > "$FI/src/pseint-bin/PKGBUILD"; tar -czf "$FI/pseint-bin.tar.gz" -C "$FI/src" pseint-bin
printf '#!/bin/bash\n# curl falso: el «snapshot» del AUR\nwhile (( $# )); do [[ "$1" == -o ]] && { cp "%s" "$2"; exit 0; }; shift; done; exit 1\n' "$FI/pseint-bin.tar.gz" > "$FI/curl"
cat > "$FI/makepkg" <<'SH'
#!/bin/bash
# makepkg falso: «arma» el paquete principal y el -debug
if [[ " $* " == *" --packagelist "* ]]; then
    printf '%s\n' "$PKGDEST/pseint-bin-20250314-2-x86_64.pkg.tar.zst" "$PKGDEST/pseint-bin-debug-20250314-2-x86_64.pkg.tar.zst"
else
    touch "$PKGDEST/pseint-bin-20250314-2-x86_64.pkg.tar.zst" "$PKGDEST/pseint-bin-debug-20250314-2-x86_64.pkg.tar.zst"
fi
SH
printf '#!/bin/bash\nexec "$@"\n' > "$FI/sudo"
printf '#!/bin/bash\n[[ "$1" == -U ]] && printf "%%s\\n" "$@" > "%s/instalados"\nexit 0\n' "$FI" > "$FI/pacman"
for h in fakeroot debugedit strip; do printf '#!/bin/bash\n' > "$FI/$h"; done
chmod +x "$FI"/*
MANAGER_MAC_PRUEBA="58:11:22:a9:df:de"
bash "$LOGICA/Entorno.sh" --equipo instituto >/dev/null
# En el instituto muestra el PKGBUILD y pregunta «¿Instalar PSeInt?»: se contesta que sí
printf 's\n' | PATH="$FI:$PATH" bash "$RES/General/AUR-instalar.sh" --sin-pausa pseint-bin > "$TMP/instalar.log" 2>&1
igual "instalar PSeInt en el instituto, de punta a punta, sale con 0" "$?" "0"
# (read -p no muestra la pregunta si la respuesta no viene de una terminal: se mira lo que se muestra antes)
grep -q "Es la primera vez que se instala desde el Manager" "$TMP/instalar.log" && grep -q "pkgname=pseint-bin" "$TMP/instalar.log" \
    && ok "en el instituto muestra el PKGBUILD antes de instalar" || mal "revisión en el instituto" "$(tail -5 "$TMP/instalar.log")"
grep -q 'pseint-bin-20250314' "$FI/instalados" && ! grep -q -- '-debug-' "$FI/instalados" \
    && ok "instala solo el paquete principal (no el -debug)" || mal "paquetes instalados" "$(cat "$FI/instalados" 2>&1)"
[[ -f "$PS_CFG" && -f "$PS_DESK" ]] && ok "después de instalar deja el perfil y el acceso directo" || mal "ajustes después de instalar" "$(tail -5 "$TMP/instalar.log")"
bash "$LOGICA/Entorno.sh" --equipo auto >/dev/null
unset MANAGER_MAC_PRUEBA AUR_RPC_FALSA PSEINT_DIR

echo "Terminal.sh (terminales falsas: no abre nada)"
FT="$TMP/terminales"; mkdir -p "$FT"
for t in xterm mi-terminal; do
    printf '#!/bin/bash\nprintf "%%s|" "$(basename "$0")" "$@" > "%s/abierta"\n' "$FT" > "$FT/$t"; chmod +x "$FT/$t"
done
TERM_SH() { PATH="$FT:$PATH" bash "$COMMON/Terminal.sh" "$@"; }
igual "elige la primera que está instalada" "$(TERMINAL_CANDIDATAS="no-existe xterm" TERM_SH --cual)" "xterm"
TERMINAL_CANDIDATAS="no-existe xterm" TERM_SH --titulo "Mi título" -- echo "hola mundo"
igual "xterm: título y comando con -e" "$(cat "$FT/abierta")" "xterm|-T|Mi título|-e|echo|hola mundo|"
TERMINAL_CANDIDATAS='$TERMINAL xterm' TERMINAL="mi-terminal --oscura" TERM_SH -- bash script.sh
igual "usa \$TERMINAL (con sus opciones) antes que las otras" "$(cat "$FT/abierta")" "mi-terminal|--oscura|-e|bash|script.sh|"
igual "\$TERMINAL que no existe se saltea" "$(TERMINAL_CANDIDATAS='$TERMINAL xterm' TERMINAL="no-existe" TERM_SH --cual)" "xterm"
TERMINAL_CANDIDATAS="no-existe" TERM_SH --cual > /dev/null 2>&1; igual "sin ninguna terminal sale con 127" "$?" "127"
TERMINAL_CANDIDATAS="xterm" TERM_SH > /dev/null 2>&1; igual "sin comando sale con 2" "$?" "2"
grep -q '"konsole"' "$RAIZ/gui/VentanaPrincipal.cpp" "$RAIZ/gui/PaginaAUR.cpp" "$RAIZ/gui/Acciones.cpp" \
    && mal "la ventana todavía llama a konsole directo" || ok "la ventana no llama a konsole directo"
grep -q 'setsid -f konsole' "$LOGICA/Minecraft.sh" && mal "Minecraft.sh todavía llama a konsole directo" || ok "Minecraft.sh usa Terminal.sh"
grep -q "^ *'konsole'$" "$RAIZ/PKGBUILD" && mal "konsole sigue en depends" || ok "konsole pasó a optdepends"
grep -rq 'SEBASTIAN' "$RAIZ/gui" "$RAIZ/Arch-Linux-Manager.sh" "$RES" && mal "queda la variable SEBASTIAN" || ok "ya no se exporta SEBASTIAN (la carpeta no existe)"

# wget falso para las descargas (no toca la red)
FW="$TMP/wget-falso"; mkdir -p "$FW"
cat > "$FW/wget" <<'SH'
#!/bin/bash
# wget falso: -O ARCHIVO URL. Con un archivo igual en $WGET_FIJOS lo copia; «falla» en la URL deja un
# archivo a medias y falla; si no, escribe «contenido URL»
salida="" url=""
while (( $# )); do case "$1" in -O) salida=$2; shift ;; --|-*) ;; *) url=$1 ;; esac; shift; done
echo "    0K .......... 50% 1M"
if [[ -n "${WGET_FIJOS:-}" && -f "$WGET_FIJOS/$(basename "$url")" ]]; then cp "$WGET_FIJOS/$(basename "$url")" "$salida"
elif [[ -n "${WGET_FIJOS:-}" || "$url" == *falla* ]]; then echo "a medias" > "$salida"; exit 4
else printf 'contenido %s\n' "$url" > "$salida"; fi
echo "   10K .......... 100% 1M"
SH
chmod +x "$FW/wget"

echo "Descargas-en-masa.sh (wget falso)"
D="$TMP/masa"; mkdir -p "$D"; echo viejo > "$D/a.txt"; echo viejo > "$D/p.tar.gz"
MASA() { PATH="$FW:$PATH" bash "$LOGICA/Descargas-en-masa.sh" --destino "$D" -- "$@"; }
salida=$(MASA "http://x/a.txt" "http://x/a.txt?v=2" "http://x/p.tar.gz" "http://x/sin-extension")
igual "no pisa el que ya estaba" "$(cat "$D/a.txt")" "viejo"
igual "el nuevo va a «nombre (2).ext»" "$(cat "$D/a (2).txt" 2>/dev/null)" "contenido http://x/a.txt"
igual "el siguiente a «nombre (3).ext»" "$(cat "$D/a (3).txt" 2>/dev/null)" "contenido http://x/a.txt?v=2"
[[ -f "$D/p (2).tar.gz" ]] && ok ".tar.gz queda junto: «p (2).tar.gz»" || mal ".tar.gz" "$(ls "$D")"
[[ -f "$D/sin-extension" ]] && ok "sin extensión" || mal "sin extensión"
grep -qx "LISTO $D/a (2).txt" <<< "$salida" && ok "LISTO dice el nombre final" || mal "LISTO con el nombre final" "$salida"
salida=$(MASA "http://x/a.txt?falla"); codigo=$?
igual "si falla sale con 1" "$codigo" "1"
igual "si falla no borra el archivo que ya estaba" "$(cat "$D/a.txt")" "viejo"
[[ ! -e "$D/a (4).txt" ]] && ok "si falla no deja el archivo a medias" || mal "deja el archivo a medias"
compgen -G "$D/.descarga-*" > /dev/null && mal "quedó un temporal .descarga-*" || ok "no quedan temporales"
igual "no deja archivos de más" "$(ls -A "$D" | wc -l)" "6"

echo "Descargar.sh (yt-dlp falso)"
FY="$TMP/ytdlp-falso"; mkdir -p "$FY"
cat > "$FY/yt-dlp" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$YTDLP_ARGS"
for a in "$@"; do [[ "$a" == -J ]] && { cat "$YTDLP_JSON"; exit 0; }; done
rutas="" destino="." url=""
while (( $# )); do
    case "$1" in --print-to-file) rutas=$3; shift 2 ;; -P) destino=$2; shift ;; --) url=$2; break ;; esac; shift
done
[[ "$url" == *falla* ]] && { echo "ERROR: [youtube] abc: Video no disponible"; exit 1; }
mkdir -p "$destino/Canal"; echo video > "$destino/Canal/Titulo.mkv"
echo "[download] Destination: $destino/Canal/Titulo.mkv"
echo "[download]  50.0% of 10.00MiB at 1.00MiB/s"
echo "[download] 100% of 10.00MiB"
echo "$destino/Canal/Titulo.mkv" >> "$rutas"
SH
chmod +x "$FY/yt-dlp"
export YTDLP_ARGS="$TMP/ytdlp-args" YTDLP_JSON="$TMP/ytdlp.json"
DESC() { PATH="$FY:$PATH" bash "$LOGICA/Descargar.sh" "$@"; }
DESC --destino "$TMP/videos" > /dev/null; igual "sin URL sale con 2" "$?" "2"
DESC --destino "$TMP/videos" --audios 'es;rm' -- http://v/1 > /dev/null; igual "rechaza un idioma raro" "$?" "2"
DESC --destino "$TMP/videos" --audio --calidad 720 -- http://v/1 > /dev/null; igual "--audio con --calidad sale con 2" "$?" "2"
DESC --destino "$TMP/videos" --vcodec mpeg -- http://v/1 > /dev/null; igual "rechaza un códec desconocido" "$?" "2"
salida=$(DESC --destino "$TMP/videos" -- http://v/1); codigo=$?
igual "baja y sale con 0" "$codigo" "0"
grep -qx "LISTO $TMP/videos/Canal/Titulo.mkv" <<< "$salida" && ok "LISTO con la ruta final" || mal "LISTO" "$salida"
grep -qx "PROGRESO 50" <<< "$salida" && ok "informa el progreso" || mal "progreso" "$salida"
grep -qx "ARCHIVO Titulo.mkv" <<< "$salida" && ok "informa el archivo" || mal "archivo" "$salida"
grep -qx -- "--remux-video" "$YTDLP_ARGS" && ok "los videos salen en MKV" || mal "MKV"
DESC --destino "$TMP/videos" --calidad 720 --vcodec av1 -- http://v/1 > /dev/null
grep -qxF 'bv[height<=720][vcodec^=av01]+ba/b[height<=720][vcodec^=av01]/bv[height<=720]+ba/b[height<=720]/bv*+ba/b' "$YTDLP_ARGS" \
    && ok "selector de calidad y códec" || mal "selector" "$(grep -A1 -x -- -f "$YTDLP_ARGS" | tail -1)"
DESC --destino "$TMP/musica" --audio -- http://v/1 > /dev/null
grep -qx -- "-x" "$YTDLP_ARGS" && ok "--audio extrae el audio" || mal "--audio"
salida=$(DESC --destino "$TMP/videos" -- http://v/falla); codigo=$?
igual "si falla sale con 1" "$codigo" "1"
grep -qx "FALLO \[youtube\] abc: Video no disponible" <<< "$salida" && ok "FALLO con el error de yt-dlp" || mal "FALLO" "$salida"
cat > "$YTDLP_JSON" <<'EOF'
{"formats": [{"vcodec": "none", "acodec": "opus", "language": "es", "language_preference": 10},
 {"vcodec": "none", "acodec": "mp4a.40.2", "language": "en"},
 {"vcodec": "av01.0.08M.08", "acodec": "none", "height": 1080},
 {"vcodec": "avc1.640028", "acodec": "none", "height": 720}],
 "subtitles": {"es": [{"name": "Español"}]},
 "automatic_captions": {"es": [{}], "en": [{"name": "English"}], "live_chat": [{}]}}
EOF
pistas=$(DESC --pistas -- http://v/1 | grep -v '^INICIO' | sort | tr '\n' '|')
igual "--pistas: audios, códecs, calidades y subtítulos" "$pistas" "ACODEC aac|ACODEC opus|AUDIO en OTRA|AUDIO es ORIGINAL|SUBTITULO en AUTO English|SUBTITULO es MANUAL Español|VIDEO 1080 av1|VIDEO 720 h264|"
unset YTDLP_ARGS YTDLP_JSON

echo "Steam-Proton.sh (GitHub falso)"
ARQ=$(uname -m)
SF="$TMP/steam-fijos"; mkdir -p "$SF/arma"
for v in 1 2 3; do
    mkdir -p "$SF/arma/GE-Proton10-$v"; echo "$v" > "$SF/arma/GE-Proton10-$v/version"
    tar -czf "$SF/GE-Proton10-$v-$ARQ.tar.gz" -C "$SF/arma" "GE-Proton10-$v"
done
(cd "$SF" && sha512sum "GE-Proton10-1-$ARQ.tar.gz" > "GE-Proton10-1-$ARQ.sha512sum")     # la 2 no publica suma
printf '%0128d  GE-Proton10-3-%s.tar.gz\n' 0 "$ARQ" > "$SF/GE-Proton10-3-$ARQ.sha512sum"     # la 3, una suma que no coincide
printf '{"assets": [{"browser_download_url": "https://github.com/x/GE-Proton10-1-aarch64.tar.gz"},\n {"browser_download_url": "https://github.com/x/GE-Proton10-1-%s.tar.gz"}]}\n' "$ARQ" > "$SF/api.json"
FC="$TMP/curl-steam"; mkdir -p "$FC"
cat > "$FC/curl" <<'SH'
#!/bin/bash
salida="" url="" formato=""
while (( $# )); do case "$1" in -o) salida=$2; shift ;; -m) shift ;; -w) formato=$2; shift ;; -*) ;; *) url=$1 ;; esac; shift; done
[[ -n "${CURL_SIN_RED:-}" ]] && exit 6
f="$WGET_FIJOS/$(basename "$url")"; [[ "$url" == *api.github.com* ]] && f="$WGET_FIJOS/api.json"
if [[ ! -f "$f" ]]; then [[ -n "$formato" ]] && { printf 404; exit 0; }; exit 22; fi
if [[ -n "$salida" ]]; then cp "$f" "$salida"; else cat "$f"; fi
[[ -n "$formato" ]] && printf 200
exit 0
SH
chmod +x "$FC/curl"
STEAM() { WGET_FIJOS="$SF" PATH="$FC:$FW:$PATH" bash "$LOGICA/Steam-Proton.sh" "$@"; }
URL1="https://github.com/x/GE-Proton10-1-$ARQ.tar.gz"
igual "ultima: la de esta arquitectura" "$(STEAM ultima | grep '^ULTIMA')" "ULTIMA GE-Proton10-1-$ARQ $URL1"
STEAM instalar "http://x/a.tar.gz" > /dev/null; igual "rechaza una URL que no es https" "$?" "2"
salida=$(STEAM instalar "$URL1"); codigo=$?
igual "instala con la suma correcta" "$codigo|$(grep '^LISTO' <<< "$salida")" "0|LISTO GE-Proton10-1"
grep -q 'Suma SHA-512 correcta' <<< "$salida" && ok "verifica la suma" || mal "verifica la suma" "$salida"
STEAMDIR="$HOME/.local/share/Steam/compatibilitytools.d"
igual "instaladas" "$(STEAM instaladas | grep '^INSTALADA')" "INSTALADA GE-Proton10-1"
salida=$(STEAM instalar "https://github.com/x/GE-Proton10-2-$ARQ.tar.gz"); codigo=$?
igual "sin suma SHA-512 no instala (código 3)" "$codigo" "3"
grep -qx "SIN_SUMA GE-Proton10-2-$ARQ.tar.gz" <<< "$salida" && ok "avisa SIN_SUMA" || mal "SIN_SUMA" "$salida"
[[ -d "$STEAMDIR/GE-Proton10-1" && ! -d "$STEAMDIR/GE-Proton10-2" ]] && ok "sin suma deja la instalada como estaba" || mal "sin suma tocó lo instalado"
salida=$(CURL_SIN_RED=1 STEAM instalar "$URL1"); codigo=$?
[[ $codigo == 1 ]] && ! grep -q '^SIN_SUMA' <<< "$salida" && ok "sin red al bajar la suma: error de red, no SIN_SUMA" || mal "sin red al bajar la suma" "$codigo $salida"
salida=$(STEAM instalar "https://github.com/x/GE-Proton10-2-$ARQ.tar.gz" --sin-suma); codigo=$?
[[ $codigo == 0 && -d "$STEAMDIR/GE-Proton10-2" && ! -d "$STEAMDIR/GE-Proton10-1" ]] && ok "con --sin-suma (confirmado) instala y quita la anterior" || mal "--sin-suma" "$salida"
salida=$(STEAM instalar "https://github.com/x/GE-Proton10-3-$ARQ.tar.gz"); codigo=$?
igual "suma que no coincide: sale con 1" "$codigo" "1"
[[ -d "$STEAMDIR/GE-Proton10-2" && ! -d "$STEAMDIR/GE-Proton10-3" ]] && ok "descarga dañada: no toca lo instalado" || mal "descarga dañada tocó lo instalado"

echo "Tutoriales.sh (sin red: puertos y curl falsos)"
FTU="$TMP/curl-tutoriales"; mkdir -p "$FTU"
cat > "$FTU/curl" <<'SH'
#!/bin/bash
[[ -n "${TUT_FALLA:-}" ]] && exit 7
echo '<a href="KDEConnect.mkv">K</a> <a href="Impresora.mkv">I</a> <a href="nota.txt">n</a>'
SH
chmod +x "$FTU/curl"
TUT() { PATH="$FTU:$PATH" bash "$LOGICA/Tutoriales.sh"; }
salida=$(SERVIDOR_PRUEBA_PUERTOS="" TUT); codigo=$?
igual "sin servidor sale con 2" "$codigo" "2"
grep -q '^ERROR No hay conexión con el servidor' <<< "$salida" && ok "sin servidor: mensaje claro" || mal "mensaje sin servidor" "$salida"
grep -q 'se cayó el sistema' "$LOGICA/Tutoriales.sh" && mal "queda «se cayó el sistema»" || ok "ya no dice «se cayó el sistema»"
export SERVIDOR_PRUEBA_PUERTOS="192.168.100.14:8080"
igual "otra PC: solo el de KDE Connect" "$(MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff" TUT | tr '\n' '|')" "VIDEO KDEConnect http://192.168.100.14:8080/Scripts/General/Tutoriales/KDEConnect.mkv|"
igual "PC de mamá: todos los videos" "$(MANAGER_MAC_PRUEBA="18:c0:4d:a2:fe:e0" TUT | cut -d' ' -f2 | tr '\n' ' ')" "KDEConnect Impresora "
salida=$(TUT_FALLA=1 TUT)
grep -q '^ERROR El servidor contestó, pero no se pudo leer' <<< "$salida" && ok "servidor sin lista: otro mensaje" || mal "servidor sin lista" "$salida"
igual "fuera de casa usa Tailscale" "$(SERVIDOR_PRUEBA_PUERTOS="archlinux.tail0dedb3.ts.net:443" MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff" TUT | head -1 | cut -d' ' -f3)" "https://archlinux.tail0dedb3.ts.net/Scripts/General/Tutoriales/KDEConnect.mkv"
unset SERVIDOR_PRUEBA_PUERTOS

echo "Acciones-servidor.sh (ssh falso)"
FS="$TMP/ssh-acciones"; mkdir -p "$FS"
cat > "$FS/ssh" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$SSH_ARGS"
case "$SSH_MODO" in
    ok) echo "Generando miniaturas..."; echo ""; echo "Listo: 3 miniaturas nuevas." ;;
    denegado) echo "sebastian@100.101.213.44: Permission denied (publickey)." >&2; exit 255 ;;
    caido) echo "ssh: connect to host x port 22: Connection refused" >&2; exit 255 ;;
    falla) echo "algo salió mal"; exit 3 ;;
esac
SH
printf '#!/bin/bash\ncat > "%s/portapapeles"\n' "$FS" > "$FS/wl-copy"; chmod +x "$FS/ssh" "$FS/wl-copy"
export SSH_ARGS="$TMP/ssh-args"
ACC() { PATH="$FS:$PATH" SERVIDOR_PRUEBA_PUERTOS="192.168.100.14:22" bash "$LOGICA/Acciones-servidor.sh" "$@"; }
ACC "rm -rf" > /dev/null; igual "acción desconocida sale con 2" "$?" "2"
salida=$(SSH_MODO=ok ACC miniaturas-bodrio); codigo=$?
igual "bien: sale con 0" "$codigo" "0"
igual "bien: LISTO con la última línea" "$(grep '^LISTO' <<< "$salida")" "LISTO Listo: 3 miniaturas nuevas."
grep -qx "LINEA Generando miniaturas..." <<< "$salida" && ok "va mostrando lo que dice el servidor" || mal "LINEA" "$salida"
[[ -f "$HOME/.ssh/arch-linux-manager-servidor" && -f "$HOME/.ssh/arch-linux-manager-servidor.pub" ]] && ok "crea la clave de este equipo" || mal "no creó la clave"
igual "manda solo el nombre de la acción" "$(tail -1 "$SSH_ARGS")" "miniaturas-bodrio"
grep -qx 'BatchMode=yes' "$SSH_ARGS" && grep -qx 'IdentitiesOnly=yes' "$SSH_ARGS" && ok "nunca pide contraseña y usa solo esa clave" || mal "opciones de ssh"
grep -qx 'HostKeyAlias=servidor-respaldos' "$SSH_ARGS" && ok "exige la huella del servidor" || mal "huella"
salida=$(SSH_MODO=denegado ACC descargas); codigo=$?
igual "sin autorizar sale con 2" "$codigo" "2"
grep -q 'todavía no está autorizado' <<< "$salida" && ok "sin autorizar: lo explica" || mal "sin autorizar" "$salida"
igual "sin autorizar: copia la clave pública" "$(cat "$FS/portapapeles" 2>/dev/null)" "$(cat "$HOME/.ssh/arch-linux-manager-servidor.pub")"
salida=$(SSH_MODO=caido ACC descargas); igual "servidor caído sale con 1" "$?|$(grep '^ERROR' <<< "$salida")" "1|ERROR No se pudo conectar con el servidor."
salida=$(SSH_MODO=falla ACC descargas); igual "la acción falla en el servidor" "$?|$(grep '^ERROR' <<< "$salida")" "1|ERROR El servidor no pudo terminar (código 3)."
PATH="$FS:$PATH" SERVIDOR_PRUEBA_PUERTOS="" bash "$LOGICA/Acciones-servidor.sh" descargas > /dev/null; igual "sin servidor sale con 1" "$?" "1"
unset SSH_ARGS

echo "Android.sh (adb falso)"
AD="$TMP/adb"; mkdir -p "$AD/bin"; export ADB_DIR="$AD"
cat > "$AD/bin/adb" <<'SH'
#!/bin/bash
# adb falso: un celular (CEL1, usuarios 0 y 10) y otro sin autorizar. Las apps de cada usuario están
# en $ADB_DIR/inst-<usuario> y todas las del sistema en $ADB_DIR/todos.
echo "$*" >> "$ADB_DIR/log"
[[ "$1" == -s ]] && shift 2
case "$1" in
    devices) printf 'List of devices attached\nCEL1\tdevice\nCEL2\tunauthorized\n\n'; exit 0 ;;
    get-state) echo device; exit 0 ;;
    shell) shift ;;
    *) exit 1 ;;
esac
reinstalar() {   # $1 usuario, $2 paquete
    if grep -qx "$2" "$ADB_DIR/todos"; then
        grep -qx "$2" "$ADB_DIR/inst-$1" || echo "$2" >> "$ADB_DIR/inst-$1"
        printf 'Package %s installed for user: %s\r\n' "$2" "$1"
    else
        printf 'Error: package %s does not exist\r\n' "$2"
    fi
}
case "$1 $2" in
    "getprop ro.product.brand") printf 'motorola\r\n' ;;
    "getprop ro.product.model") printf 'moto g\r\n' ;;
    "pm list")
        if [[ "$3" == users ]]; then printf 'Users:\r\n\tUserInfo{0:Dueño:c13} running\r\n\tUserInfo{10:Segundo espacio:410}\r\n'; exit 0; fi
        shift 3; lista="inst-$2"; [[ "$1" == -u ]] && lista=todos
        sed 's/^/package:/; s/$/\r/' "$ADB_DIR/$lista" ;;
    "pm uninstall")
        if grep -qx "$5" "$ADB_DIR/inst-$4"; then grep -vx "$5" "$ADB_DIR/inst-$4" > "$ADB_DIR/tmp"; mv "$ADB_DIR/tmp" "$ADB_DIR/inst-$4"; printf 'Success\r\n'
        else printf 'Failure [not installed for %s]\r\n' "$4"; fi ;;
    "cmd package")
        [[ -n "${ADB_VIEJO:-}" ]] && { echo "cmd: Can't find service: package"; exit 0; }
        reinstalar "$5" "$6" ;;
    "pm install-existing") reinstalar "$4" "$5" ;;
esac
SH
chmod +x "$AD/bin/adb"
P=$(bash -c 'source "$1"; printf "%s" "${recommended[0]}"' _ "$LOGICA/Debloat-listas.sh")
printf '%s\n' "$P" com.ejemplo.otra com.whatsapp > "$AD/todos"
printf '%s\n' "$P" com.whatsapp > "$AD/inst-0"
printf '%s\n' "$P" com.ejemplo.otra com.whatsapp > "$AD/inst-10"
AND() { PATH="$AD/bin:$PATH" bash "$LOGICA/Android.sh" "$@"; }
igual "dispositivos: celulares, usuarios y los sin autorizar" "$(AND dispositivos | tr '\n' '|')" "DISPOSITIVO CEL1 motorola moto g|USUARIO CEL1 0 Dueño|USUARIO CEL1 10 Segundo espacio|NOAUTORIZADO CEL2|"
salida=$(AND debloat --serial CEL1 --nivel basico --usuario 10)
grep -qx "DESINSTALADO $P 10" <<< "$salida" && ok "debloat quita la app del usuario elegido" || mal "debloat" "$(tail -2 <<< "$salida")"
grep -qx "$P" "$AD/inst-0" && ok "debloat no toca a los otros usuarios" || mal "debloat tocó al usuario 0"
igual "quitadas del usuario 10: la del debloat" "$(AND quitadas --serial CEL1 --usuario 10 | grep '^QUITADA' | tr '\n' '|')" "QUITADA $P 10 LISTA|"
igual "quitadas de todos: marca las que no son del debloat" "$(AND quitadas --serial CEL1 | grep '^QUITADA' | tr '\n' '|')" "QUITADA com.ejemplo.otra 0 OTRA|QUITADA $P 10 LISTA|"
AND quitadas --serial CEL1 --usuario 7 > /dev/null; igual "quitadas: usuario que no existe sale con 2" "$?" "2"
salida=$(AND reinstalar --serial CEL1 "10:$P"); codigo=$?
igual "reinstalar: vuelve a instalarla" "$codigo|$(grep '^REINSTALADA' <<< "$salida")" "0|REINSTALADA $P 10"
grep -q "shell cmd package install-existing --user 10 $P" "$AD/log" && ok "usa cmd package install-existing --user" || mal "comando de reinstalar"
igual "reinstalar: ya no figura como quitada" "$(AND quitadas --serial CEL1 --usuario 10 | grep -c '^QUITADA')" "0"
salida=$(ADB_VIEJO=1 AND reinstalar --serial CEL1 0:com.ejemplo.otra)
grep -qx "REINSTALADA com.ejemplo.otra 0" <<< "$salida" && grep -q "shell pm install-existing --user 0 com.ejemplo.otra" "$AD/log" \
    && ok "Android viejo: prueba con pm install-existing" || mal "pm install-existing" "$salida"
salida=$(AND reinstalar --serial CEL1 '10:com.x;reboot' 99:com.whatsapp 0:com.no.existe); codigo=$?
igual "reinstalar: rechaza lo raro y sale con 1" "$codigo|$(grep -c '^FALLO' <<< "$salida")" "1|3"
grep -q 'reboot' "$AD/log" && mal "un nombre raro llegó al celular" || ok "un nombre raro no llega al celular"
AND reinstalar --serial CEL1 > /dev/null; igual "reinstalar sin apps sale con 2" "$?" "2"
AND reinstalar --serial CEL1 --nivel x > /dev/null 2>&1; igual "opción desconocida sale con 2" "$?" "2"
unset ADB_DIR

echo "Respaldo.sh con un servidor falso (ssh y sshpass locales: copias anteriores y restaurar)"
if command -v rsync &> /dev/null; then
    FR="$TMP/respaldo-falso"; SRV="$TMP/srv"; HR="$TMP/home-respaldo"; mkdir -p "$FR" "$SRV" "$HR"
    cat > "$FR/sshpass" <<'SH'
#!/bin/bash
[[ "$1" == -e ]] && shift
[[ "${SSHPASS:-}" == "$RESPALDO_CLAVE" ]] || exit 5
exec "$@"
SH
    # ssh falso: corre el comando acá mismo (rsync --server, bash -s o true), como si fuera el servidor
    cat > "$FR/ssh" <<'SH'
#!/bin/bash
while (( $# )); do case "$1" in -o|-i|-p|-l|-F) shift 2 ;; -*) shift ;; *) shift; break ;; esac; done
exec bash -c "$*"
SH
    chmod +x "$FR/sshpass" "$FR/ssh"
    printf '{"version": 1, "respaldos": "%s"}\n' "$SRV" > "$cache"
    U=$(whoami); DL="$SRV/$U/Linux"; AN="$SRV/$U/Linux.anteriores"
    mkdir -p "$SRV/$U" "$SRV/sebastian" "$SRV/carina/Windows"    # (en el servidor ya existen)
    # (los cambios cambian el tamaño: rsync compara tamaño y hora, y todo pasa en el mismo segundo)
    RESP() { printf '%s\n' "${CLAVE:-clave}" | HOME="$HR" PATH="$FR:$PATH" RESPALDO_CLAVE=clave SERVIDOR_PRUEBA_PUERTOS="192.168.100.14:22" \
                 MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff" bash "$LOGICA/Respaldo.sh" "$@"; }
    CLAVE=otra RESP linux > /dev/null; igual "contraseña incorrecta sale con 3" "$?" "3"
    echo uno > "$HR/a.txt"; mkdir -p "$HR/dir"; echo b > "$HR/dir/b.txt"; echo c > "$HR/dir/c.txt"
    salida=$(RESP linux); codigo=$?
    igual "primer respaldo" "$codigo|$(cat "$DL/a.txt" 2>/dev/null)" "0|uno"
    grep -qx "ANTERIORES 0" <<< "$salida" && ok "primer respaldo: nada a «anteriores»" || mal "ANTERIORES 0" "$salida"
    echo segunda > "$HR/a.txt"; rm "$HR/dir/b.txt"
    salida=$(RESP linux)
    F=$(ls "$AN" 2>/dev/null | head -1)
    [[ "$F" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}$ ]] && ok "copia anterior con fecha, al lado del destino (Linux.anteriores/$F)" || mal "carpeta de anteriores" "$(ls -R "$SRV" | head)"
    igual "el espejo sigue como antes (borra y actualiza)" "$(cat "$DL/a.txt")|$([[ -e "$DL/dir/b.txt" ]] && echo está || echo borrado)" "segunda|borrado"
    igual "lo pisado quedó en anteriores" "$(cat "$AN/$F/a.txt" 2>/dev/null)" "uno"
    igual "lo borrado quedó en anteriores" "$(cat "$AN/$F/dir/b.txt" 2>/dev/null)" "b"
    [[ ! -e "$AN/$F/dir/c.txt" ]] && ok "lo que no cambió no va a anteriores" || mal "c.txt en anteriores"
    grep -qx "ANTERIORES 2" <<< "$salida" && ok "cuenta cuántos fueron a anteriores" || mal "ANTERIORES 2" "$(grep -i anterior <<< "$salida")"
    grep -q '^LISTO Respaldo completado. 2 archivo(s) borrados o cambiados quedaron en «anteriores».' <<< "$salida" && ok "el resumen lo dice" || mal "resumen" "$(grep LISTO <<< "$salida")"
    mkdir -p "$AN/2020-01-01_00-00" "$AN/otra-cosa"; echo x > "$AN/2020-01-01_00-00/viejo"; echo x > "$AN/otra-cosa/x"
    RESP linux > /dev/null
    [[ ! -e "$AN/2020-01-01_00-00" ]] && ok "borra las copias de más de 30 días" || mal "no borró la copia vieja"
    [[ -e "$AN/otra-cosa/x" && -e "$AN/$F/a.txt" ]] && ok "no borra lo que no es una copia vieja" || mal "borró de más"
    [[ ! -e "$DL/Linux.anteriores" && ! -e "$DL/.anteriores" ]] && ok "anteriores queda afuera de lo que limpia --delete" || mal "anteriores adentro del destino"
    lineas=$(wc -l < "$historial")
    igual "anteriores: lista las copias" "$(RESP anteriores | grep '^ANTERIOR ')" "ANTERIOR $F 2"
    igual "anteriores: no se anota en el historial" "$(wc -l < "$historial")" "$lineas"
    # Restaurar: nunca borra nada local y guarda lo que reemplaza
    echo local > "$HR/a.txt"; echo propio > "$HR/solo-aca.txt"
    salida=$(RESP restauracion --ruta dir/b.txt --desde "$F"); codigo=$?
    igual "restaurar un archivo desde una copia anterior" "$codigo|$(cat "$HR/dir/b.txt" 2>/dev/null)" "0|b"
    igual "restaurar un archivo no toca los demás" "$(cat "$HR/a.txt")" "local"
    rm -rf "$HR/dir"
    salida=$(RESP restauracion --ruta dir/ --desde actual); codigo=$?
    igual "restaurar una carpeta desde la copia actual" "$codigo|$(ls "$HR/dir" 2>/dev/null | tr '\n' ' ')" "0|c.txt "
    salida=$(RESP restauracion); codigo=$?
    igual "restaurar todo trae la versión del servidor" "$codigo|$(cat "$HR/a.txt")" "0|segunda"
    igual "restaurar no borra lo que solo está acá" "$(cat "$HR/solo-aca.txt" 2>/dev/null)" "propio"
    guardado=$(sed -n 's/^GUARDADOS 1 //p' <<< "$salida")
    igual "lo reemplazado queda en antes-de-restaurar" "$(cat "$guardado/a.txt" 2>/dev/null)" "local"
    [[ "$guardado" == "$HR/.local/share/Arch-Linux-Manager/antes-de-restaurar/"* ]] && ok "antes-de-restaurar en ~/.local/share" || mal "carpeta de guardados" "$guardado"
    echo real > "$DL/foto [1].jpg"; echo otra > "$DL/foto 1.jpg"
    salida=$(RESP restauracion --ruta "foto [1].jpg"); codigo=$?
    igual "restaurar un nombre con [ ] trae ese archivo y no otro" "$codigo|$(cat "$HR/foto [1].jpg" 2>/dev/null)|$([[ -e "$HR/foto 1.jpg" ]] && echo trajo-otro)" "0|real|"
    salida=$(RESP restauracion --ruta no-existe.txt); codigo=$?
    igual "restaurar algo que no está en el respaldo sale con 1" "$codigo" "1"
    grep -q 'No se encontró «no-existe.txt»' <<< "$salida" && ok "lo dice claro" || mal "mensaje de ruta inexistente" "$(grep ERROR <<< "$salida")"
    RESP restauracion --ruta ../etc > /dev/null; igual "rechaza rutas con .." "$?" "2"
    RESP restauracion --ruta /etc/passwd > /dev/null; igual "rechaza rutas absolutas" "$?" "2"
    RESP restauracion --desde ayer > /dev/null; igual "rechaza una fecha rara" "$?" "2"
    RESP linux --ruta a.txt > /dev/null; igual "--ruta solo para restaurar" "$?" "2"
    # Minecraft
    export MINECRAFT_DIR="$TMP/mc-respaldo"; mkdir -p "$MINECRAFT_DIR/Servidores"; echo v1 > "$MINECRAFT_DIR/Servidores/notas.txt"
    RESP minecraft > /dev/null; echo v22 > "$MINECRAFT_DIR/Servidores/notas.txt"; RESP minecraft > /dev/null
    MA="$SRV/sebastian/Minecraft.anteriores"
    igual "Minecraft: lo pisado va a Minecraft.anteriores" "$(cat "$MA"/*/Servidores/notas.txt 2>/dev/null)|$(cat "$SRV/sebastian/Minecraft/Servidores/notas.txt" 2>/dev/null)" "v1|v22"
    unset MINECRAFT_DIR
    # Carina (una carpeta en vez de la partición de Windows): S.I.Ap va adentro de «Trabajo de Carina»
    W="$TMP/windows"; mkdir -p "$W/Usuarios/Carina" "$W/Program Files (x86)/S.I.Ap"
    echo v1 > "$W/Usuarios/Carina/doc.txt"; echo v1 > "$W/Program Files (x86)/S.I.Ap/datos.db"; echo fijo > "$W/Program Files (x86)/S.I.Ap/fijo.txt"
    CAR() { RESPALDO_CARINA_ORIGEN="$W" RESP carina; }
    CAR > /dev/null; TC="$SRV/carina/Windows/Trabajo de Carina"
    igual "Carina: trabajo y S.I.Ap" "$(cat "$TC/doc.txt" "$TC/S.I.Ap/datos.db" 2>/dev/null | tr '\n' ' ')" "v1 v1 "
    echo v22 > "$W/Usuarios/Carina/doc.txt"; echo v22 > "$W/Program Files (x86)/S.I.Ap/datos.db"
    salida=$(CAR); CA="$SRV/carina/Windows/Trabajo de Carina.anteriores"
    igual "Carina: lo pisado de las dos copias va a la misma carpeta anterior" "$(cat "$CA"/*/doc.txt "$CA"/*/S.I.Ap/datos.db 2>/dev/null | tr '\n' ' ')" "v1 v1 "
    grep -qx "ANTERIORES 2" <<< "$salida" && ok "Carina: S.I.Ap ya no se borra y se copia entera cada vez" || mal "Carina: ANTERIORES" "$(grep -i anterior <<< "$salida"; ls -R "$CA" | head -20)"
    rm -f "$cache"
else
    echo "  (sin rsync: se saltean)"
fi

echo
if (( fallas == 0 )); then
    echo "Todas bien ($pruebas pruebas)."
else
    echo "$fallas de $pruebas pruebas fallaron."
    exit 1
fi
