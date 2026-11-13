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
for s in "$RES"/Common/*.sh "$RES"/Logica/*.sh "$RES"/General/*.sh "$RES"/General/Android/*.sh "$RES"/Sebastian/Server/*.sh "$RAIZ"/Arch-Linux-Manager.sh; do
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

echo "Servidor.sh y servidor.json"
cache="$XDG_CACHE_HOME/Arch-Linux-Manager/servidor.json"
mkdir -p "$(dirname "$cache")"
valor() { bash -c "source \"\$COMMON/Servidor.sh\"; printf '%s' \"\$$1\""; }
igual "sin copia guardada quedan los de fábrica" "$(valor SERVIDOR_IP_LOCAL)" "192.168.100.14"
cat > "$cache" <<'EOF'
{"version": 1, "ip_local": "10.0.0.5", "ip_tailscale": "100.1.2.3", "usuario": "otro",
 "web_tailscale": "https://ejemplo.ts.net", "respaldos": "/srv/respaldos", "desconocido": "x"}
EOF
igual "servidor.json cambia la IP de casa" "$(valor SERVIDOR_IP_LOCAL)" "10.0.0.5"
igual "servidor.json cambia la IP de Tailscale" "$(valor SERVIDOR_IP_TAILSCALE)" "100.1.2.3"
igual "servidor.json cambia el usuario" "$(valor SERVIDOR_USUARIO)" "otro"
igual "servidor.json cambia la carpeta" "$(valor SERVIDOR_RESPALDOS)" "/srv/respaldos"
cat > "$cache" <<'EOF'
{"version": 1, "ip_local": "1.2.3.4; rm -rf ~", "usuario": "$(whoami)", "respaldos": "../../etc",
 "web_local": "javascript:alert(1)"}
EOF
igual "rechaza una IP con comandos" "$(valor SERVIDOR_IP_LOCAL)" "192.168.100.14"
igual "rechaza un usuario raro" "$(valor SERVIDOR_USUARIO)" "sebastian"
igual "rechaza una ruta relativa" "$(valor SERVIDOR_RESPALDOS)" "/home/sebastian/Respaldos"
igual "rechaza una URL rara" "$(valor SERVIDOR_WEB_LOCAL)" "http://192.168.100.14:8080"
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

echo
if (( fallas == 0 )); then
    echo "Todas bien ($pruebas pruebas)."
else
    echo "$fallas de $pruebas pruebas fallaron."
    exit 1
fi
