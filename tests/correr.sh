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
igual "la PC de Sebastián ve las 5" "$(apps)" "claude-desktop equibop-bin heroic-games-launcher-bin lcl-gui-bin playit-bin "
bash "$LOGICA/Entorno.sh" --equipo krocante >/dev/null
igual "la tía ve solo Claude" "$(apps)" "claude-desktop "
bash "$LOGICA/Entorno.sh" --equipo auto >/dev/null
MANAGER_MAC_PRUEBA="18:c0:4d:a2:fe:e0"
igual "mamá ve solo Claude" "$(apps)" "claude-desktop "
MANAGER_MAC_PRUEBA="aa:bb:cc:dd:ee:ff"
igual "otra PC ve todas menos Claude" "$(apps)" "equibop-bin heroic-games-launcher-bin lcl-gui-bin "
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
unset MANAGER_MAC_PRUEBA AUR_RPC_FALSA

echo
if (( fallas == 0 )); then
    echo "Todas bien ($pruebas pruebas)."
else
    echo "$fallas de $pruebas pruebas fallaron."
    exit 1
fi
