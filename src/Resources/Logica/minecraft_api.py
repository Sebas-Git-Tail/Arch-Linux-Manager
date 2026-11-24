#!/usr/bin/env python3
"""Consultas para el panel de Minecraft (lo usa Logica/Minecraft.sh). Solo informa, salvo lo de crear
servidores (mrpack, bajar-modrinth, propiedades, mundo), que escribe en la carpeta que se le da.

  minecraft_api.py paper VERSION
      La última compilación ESTABLE de Paper para esa versión (API Fill v3 de PaperMC):
      «PAPER <build> <nombre.jar> <sha256> <url>»
  minecraft_api.py plugins VERSION ARCHIVO.jar...
      Por cada plugin: qué es y si hay una versión nueva para esa versión de Minecraft. Se reconoce
      por el hash del archivo en Modrinth; Floodgate (que no está en Modrinth) en GeyserMC.
      «PLUGIN <archivo>\t<nombre>\t<versión actual>\t<versión nueva>\t<estado>\t<url>\t<sha512|sha256:…>\t<archivo nuevo>»
      estado: AL_DIA, NUEVA, SIN_VERSION (no hay para esta versión de Minecraft) o DESCONOCIDO
  minecraft_api.py buscar VERSION TEXTO
      Un plugin de Modrinth por nombre, slug o URL (modrinth.com/plugin/<slug>), compatible con la versión:
      «ENCONTRADO <slug>\t<nombre>\t<versión>\t<url>\t<sha512>\t<archivo>» o nada
  minecraft_api.py complementos TIPO VERSION TEXTO...
      Plugins (paper) o mods (fabric/forge) de Modrinth con sus dependencias obligatorias (ver complementos()).
  Para crear servidores (Minecraft.sh crear y el asistente):
      opciones                          versiones y qué software hay para cada una («VERSION <v>\t<software,…>»)
      vanilla|fabric|forge VERSION [X]  qué bajar para ese software (ver cada función)
      buscar-modrinth complemento|modpack TIPO VERSION TEXTO     proyectos que sirven («RESULTADO …»)
      modpack-versiones SLUG            versiones usables de un modpack («MODPACK …»)
      mrpack ARCHIVO DESTINO TIPO VERSION   instala un .mrpack en la carpeta (comprueba sumas, rutas y compatibilidad)
      bajar-modrinth URL SHA512 DESTINO      baja un archivo de cdn.modrinth.com comprobando la suma
      propiedades ARCHIVO clave=valor...     escribe server.properties
      mundo ORIGEN DESTINO              copia un mundo (carpeta o .zip con level.dat) a DESTINO/world
  minecraft_api.py ping PUERTO
      Quién está conectado al servidor de este equipo (Server List Ping a 127.0.0.1, no usa internet ni
      escribe nada en la consola del servidor): «JUGADORES <conectados>\t<máximo>\t<nombre,nombre…>»

Para las pruebas: MINECRAFT_API_FALSA=<carpeta> lee las respuestas de archivos de esa carpeta en vez de
ir a internet (ver tests/correr.sh).
"""
import hashlib
import json
import os
import re
import socket
import struct
import sys
import urllib.parse
import urllib.request
import zipfile

AGENTE = "Sebas-Git-Tail/Arch-Linux-Manager (github.com/Sebas-Git-Tail/Arch-Linux-Manager)"
MODRINTH = "https://api.modrinth.com/v2"
CARGADORES = ["paper", "spigot", "bukkit", "purpur", "folia"]
FALSA = os.environ.get("MINECRAFT_API_FALSA")

# IPv4 primero: en casa el IPv6 no sale a internet y Python (a diferencia de curl) espera a que falle
# antes de probar IPv4 (con Fabric y Forge eran 7 segundos por pedido)
_getaddrinfo = socket.getaddrinfo


def _ipv4_primero(*args, **kwargs):
    return sorted(_getaddrinfo(*args, **kwargs), key=lambda r: r[0] != socket.AF_INET)


socket.getaddrinfo = _ipv4_primero


def pedir(url, datos=None):
    """GET (o POST con JSON) y devuelve el JSON. Con MINECRAFT_API_FALSA, lo lee de un archivo."""
    if FALSA:
        nombre = re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[:150] + ".json"
        ruta = os.path.join(FALSA, nombre)
        if not os.path.exists(ruta):
            raise OSError(f"respuesta falsa no encontrada: {nombre}")
        with open(ruta, encoding="utf-8") as f:
            return json.load(f)
    cuerpo = json.dumps(datos).encode() if datos is not None else None
    pedido = urllib.request.Request(url, data=cuerpo, headers={"User-Agent": AGENTE, "Content-Type": "application/json"})
    with urllib.request.urlopen(pedido, timeout=25) as r:
        return json.load(r)


def limpiar(texto):
    """Sin tabuladores ni saltos de línea (el formato de salida los usa como separadores)."""
    return re.sub(r"[\t\r\n]+", " ", str(texto)).strip()


def paper(version):
    builds = pedir(f"https://fill.papermc.io/v3/projects/paper/versions/{urllib.parse.quote(version)}/builds")
    estables = [b for b in builds if b.get("channel") == "STABLE"]
    if not estables:
        return 1
    b = max(estables, key=lambda x: x.get("id", 0))
    d = b["downloads"]["server:default"]
    print(f"PAPER {b['id']} {d['name']} {d['checksums']['sha256']} {d['url']}")
    return 0


def archivo_principal(version):
    archivos = version.get("files") or []
    return next((f for f in archivos if f.get("primary")), archivos[0] if archivos else None)


def plugins(version_mc, rutas, cargadores=None):
    """cargadores: los de Modrinth que sirven (por defecto los de Paper; para mods, ["fabric"] o ["forge"])."""
    cargadores = cargadores or CARGADORES
    sha1 = {}
    for ruta in rutas:
        with open(ruta, "rb") as f:
            sha1[ruta] = hashlib.sha1(f.read()).hexdigest()
    hashes = list(set(sha1.values()))
    actuales, nuevas = {}, {}
    if hashes:
        try:
            actuales = pedir(f"{MODRINTH}/version_files", {"hashes": hashes, "algorithm": "sha1"})
            nuevas = pedir(f"{MODRINTH}/version_files/update",
                           {"hashes": hashes, "algorithm": "sha1", "loaders": cargadores, "game_versions": [version_mc]})
        except OSError as e:
            print(f"AVISO No se pudo consultar Modrinth: {e}", file=sys.stderr)
    # Nombres de los proyectos (un solo pedido)
    ids = sorted({v["project_id"] for v in actuales.values()})
    titulos = {}
    if ids:
        try:
            for p in pedir(f"{MODRINTH}/projects?ids=" + urllib.parse.quote(json.dumps(ids))):
                titulos[p["id"]] = p.get("title") or p.get("slug")
        except OSError:
            pass
    for ruta in rutas:
        archivo = os.path.basename(ruta)
        h = sha1[ruta]
        actual = actuales.get(h)
        if actual:
            nombre = titulos.get(actual["project_id"], archivo)
            nueva = nuevas.get(h)
            if not nueva:
                estado, ver_nueva, url, suma, nuevo_archivo = "SIN_VERSION", "", "", "", ""
            else:
                principal = archivo_principal(nueva)
                igual = principal and principal["hashes"].get("sha1") == h
                estado = "AL_DIA" if (igual or nueva["id"] == actual["id"]) else "NUEVA"
                ver_nueva = nueva["version_number"]
                url = principal["url"] if principal else ""
                suma = principal["hashes"].get("sha512", "") if principal else ""
                nuevo_archivo = principal["filename"] if principal else ""
            print("PLUGIN " + "\t".join(limpiar(x) for x in
                  (archivo, nombre, actual["version_number"], ver_nueva, estado, url, suma, nuevo_archivo)))
            continue
        # No está en Modrinth: Floodgate y Geyser se publican en GeyserMC
        proyecto = "floodgate" if "floodgate" in archivo.lower() else "geyser" if "geyser" in archivo.lower() else None
        if proyecto and cargadores == CARGADORES:    # (lo de GeyserMC que se baja es la versión para Paper)
            try:
                ultimo = pedir(f"https://download.geysermc.org/v2/projects/{proyecto}/versions/latest/builds/latest")
                d = ultimo["downloads"]["spigot"]
                with open(ruta, "rb") as f:
                    sha256 = hashlib.sha256(f.read()).hexdigest()
                estado = "AL_DIA" if sha256 == d["sha256"] else "NUEVA"
                url = (f"https://download.geysermc.org/v2/projects/{proyecto}/versions/{ultimo['version']}"
                       f"/builds/{ultimo['build']}/downloads/spigot")
                nombre = "Floodgate" if proyecto == "floodgate" else "Geyser"
                print("PLUGIN " + "\t".join(limpiar(x) for x in
                      (archivo, nombre + " (GeyserMC)", "?", f"{ultimo['version']}-b{ultimo['build']}", estado,
                       url, "sha256:" + d["sha256"], archivo)))
                continue
            except (OSError, KeyError, ValueError) as e:
                print(f"AVISO No se pudo consultar GeyserMC: {e}", file=sys.stderr)
        print("PLUGIN " + "\t".join((limpiar(archivo), limpiar(archivo), "?", "", "DESCONOCIDO", "", "", "")))
    return 0


# --- Tipos de servidor y compatibilidades -----------------------------------------------------------
# Qué complementos acepta cada tipo (lo mismo que admite() de Minecraft-comun.sh):
#   paper: plugins (cargadores de Paper)   fabric / forge: mods de ese cargador   vanilla: nada
CARGADORES_TIPO = {"paper": CARGADORES, "fabric": ["fabric"], "forge": ["forge"]}
CLASE_TIPO = {"paper": "plugin", "fabric": "mod", "forge": "mod"}
MOJANG = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
# (en las pruebas, con MINECRAFT_API_FALSA, se puede apuntar a una carpeta: el lanzador se baja de ahí)
FABRIC = (os.environ.get("MINECRAFT_FABRIC_META") if FALSA else None) or "https://meta.fabricmc.net/v2"
FORGE_PROMOS = "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json"
FORGE_MAVEN = "https://maven.minecraftforge.net/net/minecraftforge/forge"
VERSION_RE = re.compile(r"[0-9]+\.[0-9]+(\.[0-9]+)?")
# De dónde puede bajar archivos un modpack (los mismos que acepta el launcher de Modrinth)
DOMINIOS_MRPACK = ("cdn.modrinth.com", "github.com", "raw.githubusercontent.com", "gitlab.com")


def q(texto):
    return urllib.parse.quote(str(texto), safe="")


def pedir_texto(url):
    """GET de texto plano (p. ej. un .sha1 de Maven). Con MINECRAFT_API_FALSA, de un archivo .txt."""
    if FALSA:
        nombre = re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[:150] + ".txt"
        ruta = os.path.join(FALSA, nombre)
        if not os.path.exists(ruta):
            raise OSError(f"respuesta falsa no encontrada: {nombre}")
        with open(ruta, encoding="utf-8") as f:
            return f.read().strip()
    pedido = urllib.request.Request(url, headers={"User-Agent": AGENTE})
    with urllib.request.urlopen(pedido, timeout=25) as r:
        return r.read(4096).decode("utf-8", "replace").strip()


def url_permitida(url, dominios=None):
    """https (y, solo en las pruebas, file://). Con dominios, además tiene que ser de uno de ellos."""
    p = urllib.parse.urlparse(url)
    if FALSA and p.scheme == "file":
        return True
    return p.scheme == "https" and (dominios is None or p.hostname in dominios)


def bajar(url, destino, hashes):
    """Baja url a destino comprobando las sumas que haya (sha512 y/o sha1). Sin sumas no baja nada."""
    if not hashes:
        raise ValueError("sin suma para comprobar")
    pedido = urllib.request.Request(url, headers={"User-Agent": AGENTE})
    tmp = destino + ".parcial"
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    h = {alg: hashlib.new(alg) for alg in hashes}
    with urllib.request.urlopen(pedido, timeout=60) as r, open(tmp, "wb") as f:
        while True:
            parte = r.read(1 << 16)
            if not parte:
                break
            f.write(parte)
            for x in h.values():
                x.update(parte)
    for alg, esperado in hashes.items():
        if h[alg].hexdigest() != esperado.lower():
            os.remove(tmp)
            raise ValueError(f"la suma de {os.path.basename(destino)} no coincide")
    os.replace(tmp, destino)


def ruta_segura(base, relativa):
    """base/relativa solo si queda adentro de base (nada de «..», rutas absolutas ni barras invertidas)."""
    if not relativa or "\\" in relativa or relativa.startswith("/") or "\x00" in relativa:
        return None
    partes = [x for x in relativa.split("/") if x not in ("", ".")]
    if not partes or ".." in partes:
        return None
    destino = os.path.realpath(os.path.join(base, *partes))
    return destino if destino.startswith(os.path.realpath(base) + os.sep) else None


def opciones():
    """Versiones (releases de Mojang, la más nueva primero) y qué software hay para cada una.
    Las cuatro consultas van en paralelo (cada una puede tardar unos segundos)."""
    from concurrent.futures import ThreadPoolExecutor
    urls = {"mojang": MOJANG, "paper": "https://fill.papermc.io/v3/projects/paper",
            "fabric": f"{FABRIC}/versions/game", "forge": FORGE_PROMOS}
    with ThreadPoolExecutor(4) as hilos:
        futuros = {k: hilos.submit(pedir, u) for k, u in urls.items()}
    respuestas, fallas = {}, {}
    for k, f in futuros.items():
        try:
            respuestas[k] = f.result()
        except (OSError, ValueError) as e:
            fallas[k] = e
    if "mojang" not in respuestas:
        raise OSError(f"no se pudo consultar Mojang: {fallas['mojang']}")
    releases = [v["id"] for v in respuestas["mojang"]["versions"] if v.get("type") == "release" and VERSION_RE.fullmatch(v["id"])]
    hay = {r: ["vanilla"] for r in releases}
    try:
        for lista in respuestas["paper"]["versions"].values():
            for v in lista:
                if v in hay and "paper" not in hay[v]:
                    hay[v].append("paper")
    except (KeyError, AttributeError, TypeError) as e:
        print(f"AVISO No se pudo consultar PaperMC ({limpiar(fallas.get('paper', e))}): Paper no aparece.")
    try:
        for v in respuestas["fabric"]:
            if v.get("stable") and v.get("version") in hay:
                hay[v["version"]].append("fabric")
    except (KeyError, AttributeError, TypeError) as e:
        print(f"AVISO No se pudo consultar Fabric ({limpiar(fallas.get('fabric', e))}): Fabric no aparece.")
    try:
        for clave in respuestas["forge"]["promos"]:
            v = clave.rsplit("-", 1)[0]
            if v in hay and "forge" not in hay[v]:
                hay[v].append("forge")
    except (KeyError, AttributeError, TypeError) as e:
        print(f"AVISO No se pudo consultar Forge ({limpiar(fallas.get('forge', e))}): Forge no aparece.")
    for r in releases:
        print(f"VERSION {r}\t{','.join(hay[r])}")
    return 0


def vanilla(version):
    """El server.jar oficial y qué Java pide: «VANILLA <url> <sha1> <java>»."""
    man = pedir(MOJANG)
    v = next((x for x in man["versions"] if x["id"] == version), None)
    if not v:
        print(f"ERROR Mojang no tiene la versión {version}.")
        return 1
    datos = pedir(v["url"])
    servidor = (datos.get("downloads") or {}).get("server")
    if not servidor:
        print(f"ERROR La versión {version} no tiene servidor oficial.")
        return 1
    java = int((datos.get("javaVersion") or {}).get("majorVersion", 8))
    print(f"VANILLA {servidor['url']} {servidor['sha1']} {java}")
    return 0


def fabric(version, loader=""):
    """El lanzador de servidor de Fabric: «FABRIC <loader> <archivo.jar> <url>» (el último loader estable)."""
    cargadores = pedir(f"{FABRIC}/versions/loader/{q(version)}")
    if not cargadores:
        print(f"ERROR Fabric no tiene loader para {version}.")
        return 1
    if loader:
        elegido = next((c for c in cargadores if c["loader"]["version"] == loader), None)
        if not elegido:
            print(f"ERROR Fabric no tiene el loader {loader} para {version}.")
            return 1
    else:
        elegido = next((c for c in cargadores if c["loader"].get("stable")), cargadores[0])
    lv = elegido["loader"]["version"]
    instaladores = pedir(f"{FABRIC}/versions/installer")
    iv = next((i for i in instaladores if i.get("stable")), instaladores[0])["version"]
    if not all(re.fullmatch(r"[0-9A-Za-z.+\-]+", x) for x in (lv, iv)):
        print("ERROR Respuesta rara de Fabric.")
        return 1
    print(f"FABRIC {lv} fabric-server-mc.{version}-loader.{lv}-launcher.{iv}.jar "
          f"{FABRIC}/versions/loader/{q(version)}/{q(lv)}/{q(iv)}/server/jar")
    return 0


def forge(version, forge_ver=""):
    """El instalador de Forge: «FORGE <versión de forge> <url> <sha1>» (la recomendada, o la última)."""
    if not forge_ver:
        promos = pedir(FORGE_PROMOS)["promos"]
        forge_ver = promos.get(f"{version}-recommended") or promos.get(f"{version}-latest") or ""
    if not re.fullmatch(r"[0-9][0-9A-Za-z.\-]*", forge_ver):
        print(f"ERROR Forge no tiene versión para {version}.")
        return 1
    # Los Forge viejos (≤1.9) llevan la versión de Minecraft también al final
    for completo in (f"{version}-{forge_ver}", f"{version}-{forge_ver}-{version}"):
        url = f"{FORGE_MAVEN}/{completo}/forge-{completo}-installer.jar"
        try:
            sha1 = pedir_texto(url + ".sha1").split()[0]
        except (OSError, IndexError):
            continue
        if re.fullmatch(r"[0-9a-f]{40}", sha1):
            print(f"FORGE {forge_ver} {url} {sha1}")
            return 0
    print(f"ERROR No encontré el instalador de Forge {forge_ver} para {version}.")
    return 1


def proyecto_de(texto, clase, version_mc, cargadores):
    """Un proyecto de Modrinth por URL, slug o nombre (buscando entre los compatibles); None si no hay."""
    texto = texto.strip()
    m = re.search(r"modrinth\.com/(?:plugin|mod|modpack|project|datapack)/([A-Za-z0-9_.-]+)", texto)
    candidatos = []
    if m:
        candidatos = [m.group(1)]
    else:
        if re.fullmatch(r"[A-Za-z0-9_.-]+", texto):
            candidatos.append(texto.lower())
        facetas = [[f"project_type:{clase}"]]
        if version_mc:
            facetas.append([f"versions:{version_mc}"])
        if clase == "mod":
            facetas.append([f"categories:{c}" for c in cargadores])
        try:
            r = pedir(f"{MODRINTH}/search?limit=5&query={q(texto)}&facets={q(json.dumps(facetas))}")
            candidatos += [h["slug"] for h in r.get("hits", [])]
        except OSError:
            pass
    for slug in candidatos:
        try:
            return pedir(f"{MODRINTH}/project/{q(slug)}")
        except OSError:
            continue
    return None


def complementos(tipo, version_mc, textos):
    """Plugins o mods para un servidor, con sus dependencias obligatorias. Por cada archivo a instalar:
    «COMPLEMENTO <slug>\t<nombre>\t<versión>\t<url>\t<sha512>\t<archivo>\t<motivo>»; si algo no sirve:
    «NO_SIRVE <texto>\t<por qué>»."""
    if tipo not in CARGADORES_TIPO:
        for t in textos:
            print("NO_SIRVE " + "\t".join(limpiar(x) for x in (t, f"un servidor {tipo.capitalize()} no usa plugins ni mods")))
        return 1
    cargadores, clase = CARGADORES_TIPO[tipo], CLASE_TIPO[tipo]
    cola = [(t, "pedido", None) for t in textos]
    vistos, problemas = set(), 0
    while cola:
        texto, motivo, pid = cola.pop(0)
        proyecto = None
        if pid:
            try:
                proyecto = pedir(f"{MODRINTH}/project/{q(pid)}")
            except OSError:
                pass
        else:
            proyecto = proyecto_de(texto, clase, version_mc, cargadores)
        if not proyecto:
            print("NO_SIRVE " + "\t".join(limpiar(x) for x in (texto, f"no está en Modrinth como {clase} para {version_mc}")))
            problemas += 1
            continue
        if proyecto["id"] in vistos:
            continue
        vistos.add(proyecto["id"])
        titulo = proyecto.get("title") or proyecto["slug"]
        if proyecto.get("server_side") == "unsupported":
            print("NO_SIRVE " + "\t".join(limpiar(x) for x in (titulo, "es solo para el juego (cliente), no para servidores")))
            problemas += 1
            continue
        try:
            versiones = pedir(f"{MODRINTH}/project/{q(proyecto['slug'])}/version?loaders=" + q(json.dumps(cargadores))
                              + "&game_versions=" + q(json.dumps([version_mc])))
        except OSError:
            versiones = []
        principal = archivo_principal(versiones[0]) if versiones else None
        if not principal or not principal["filename"].endswith(".jar"):
            que = "Paper" if tipo == "paper" else tipo.capitalize()
            print("NO_SIRVE " + "\t".join(limpiar(x) for x in (titulo, f"no tiene versión para {que} {version_mc}")))
            problemas += 1
            continue
        v = versiones[0]
        print("COMPLEMENTO " + "\t".join(limpiar(x) for x in (
            proyecto["slug"], titulo, v["version_number"], principal["url"], principal["hashes"].get("sha512", ""),
            principal["filename"], motivo)))
        for dep in v.get("dependencies") or []:
            if dep.get("dependency_type") == "required" and dep.get("project_id"):
                cola.append((dep["project_id"], f"lo necesita {titulo}", dep["project_id"]))
    return 1 if problemas else 0


def buscar(version_mc, texto):
    """(Compatibilidad) el primer plugin para Paper: «ENCONTRADO …» como antes."""
    import io
    import contextlib
    salida = io.StringIO()
    with contextlib.redirect_stdout(salida):
        complementos("paper", version_mc, [texto])
    for linea in salida.getvalue().splitlines():
        if linea.startswith("COMPLEMENTO "):
            print("ENCONTRADO " + "\t".join(linea[len("COMPLEMENTO "):].split("\t")[:6]))
            return 0
    return 1


def modrinth_buscar(clase, tipo, version_mc, texto):
    """Para el asistente: hasta 10 proyectos que sirven.
    clase «complemento»: plugins (Paper) o mods (Fabric/Forge) de esa versión; «modpack»: modpacks de Fabric o Forge.
    «RESULTADO <slug>\t<nombre>\t<descripción>\t<descargas>\t<cargadores>»"""
    if clase == "modpack":
        facetas = [["project_type:modpack"], ["categories:fabric", "categories:forge"],
                   ["server_side:required", "server_side:optional"]]
        if version_mc:
            facetas.append([f"versions:{version_mc}"])
    else:
        if tipo not in CARGADORES_TIPO:
            return 1
        facetas = [[f"project_type:{CLASE_TIPO[tipo]}"], [f"versions:{version_mc}"],
                   [f"categories:{c}" for c in CARGADORES_TIPO[tipo]], ["server_side:required", "server_side:optional"]]
    r = pedir(f"{MODRINTH}/search?limit=10&index=relevance&query={q(texto)}&facets={q(json.dumps(facetas))}")
    for h in r.get("hits", []):
        cargadores = [c for c in h.get("categories", []) if c in ("fabric", "forge", "paper", "spigot", "bukkit", "purpur", "folia")]
        print("RESULTADO " + "\t".join(limpiar(x) for x in (h["slug"], h.get("title", h["slug"]),
              (h.get("description") or "")[:160], h.get("downloads", 0), ",".join(cargadores))))
    return 0


def modpack_versiones(slug):
    """Versiones de un modpack que se pueden usar (Fabric o Forge, con .mrpack):
    «MODPACK <id>\t<nombre>\t<versión de Minecraft>\t<cargador>\t<url>\t<sha512>\t<archivo>»"""
    proyecto = pedir(f"{MODRINTH}/project/{q(slug)}")
    if proyecto.get("project_type") != "modpack":
        print(f"ERROR «{limpiar(slug)}» no es un modpack.")
        return 1
    if proyecto.get("server_side") == "unsupported":
        print(f"ERROR {limpiar(proyecto.get('title', slug))} es solo para el juego, no para servidores.")
        return 1
    n = 0
    for v in pedir(f"{MODRINTH}/project/{q(slug)}/version"):
        cargador = next((c for c in v.get("loaders", []) if c in ("fabric", "forge")), None)
        principal = archivo_principal(v)
        juego = [g for g in v.get("game_versions", []) if VERSION_RE.fullmatch(g)]
        if not cargador or not principal or not principal["filename"].endswith(".mrpack") or len(juego) != 1:
            continue
        print("MODPACK " + "\t".join(limpiar(x) for x in (v["id"], v["version_number"], juego[0], cargador,
              principal["url"], principal["hashes"].get("sha512", ""), principal["filename"])))
        n += 1
        if n >= 30:
            break
    if not n:
        print(f"ERROR {limpiar(proyecto.get('title', slug))} no tiene versiones de Fabric o Forge para servidor.")
        return 1
    return 0


def mrpack(archivo, destino, tipo, version_mc):
    """Instala un modpack de Modrinth (.mrpack) en la carpeta del servidor: baja los archivos del lado del
    servidor (comprobando las sumas y de dónde vienen) y copia overrides/ y server-overrides/.
    Comprueba que sea para esa versión de Minecraft y ese cargador. Dice «LOADER <versión>» y «ETAPA …»."""
    import zipfile
    with zipfile.ZipFile(archivo) as z:
        indice = json.loads(z.read("modrinth.index.json"))
        if indice.get("game") != "minecraft" or indice.get("formatVersion") != 1:
            print("ERROR El archivo no es un modpack de Modrinth válido.")
            return 1
        dep = indice.get("dependencies") or {}
        if dep.get("minecraft") != version_mc:
            print(f"ERROR El modpack es para Minecraft {limpiar(dep.get('minecraft'))}, no {version_mc}.")
            return 1
        clave = {"fabric": "fabric-loader", "forge": "forge"}.get(tipo)
        otros = [k for k in ("fabric-loader", "forge", "neoforge", "quilt-loader") if k in dep and k != clave]
        if not clave or clave not in dep or otros:
            usa = ", ".join(k for k in dep if k != "minecraft") or "ningún cargador"
            print(f"ERROR El modpack usa {limpiar(usa)}: no se puede armar como servidor {tipo.capitalize()}.")
            return 1
        print(f"LOADER {limpiar(dep[clave])}")
        archivos = [f for f in indice.get("files", []) if (f.get("env") or {}).get("server") != "unsupported"]
        for i, f in enumerate(archivos, 1):
            ruta = ruta_segura(destino, f.get("path", ""))
            hashes = {k: v for k, v in (f.get("hashes") or {}).items() if k in ("sha1", "sha512")}
            urls = [u for u in f.get("downloads", []) if url_permitida(u, DOMINIOS_MRPACK)]
            if not ruta or "sha512" not in hashes or not urls:
                print(f"ERROR Archivo peligroso o sin suma en el modpack: {limpiar(f.get('path'))}")
                return 1
            print(f"ETAPA Bajando el modpack ({i}/{len(archivos)}): {limpiar(os.path.basename(ruta))}", flush=True)
            for n, u in enumerate(urls):
                try:
                    bajar(u, ruta, hashes)
                    break
                except (OSError, ValueError) as e:
                    if n == len(urls) - 1:
                        print(f"ERROR No se pudo bajar {limpiar(f.get('path'))}: {limpiar(e)}")
                        return 1
        # overrides/ primero y server-overrides/ encima (lo del cliente no)
        for prefijo in ("overrides/", "server-overrides/"):
            for info in z.infolist():
                if not info.filename.startswith(prefijo) or info.is_dir():
                    continue
                ruta = ruta_segura(destino, info.filename[len(prefijo):])
                if not ruta or (info.external_attr >> 16) & 0o170000 == 0o120000:    # nada de enlaces
                    print(f"ERROR Ruta peligrosa en el modpack: {limpiar(info.filename)}")
                    return 1
                os.makedirs(os.path.dirname(ruta), exist_ok=True)
                with z.open(info) as origen, open(ruta, "wb") as salida:
                    salida.write(origen.read())
    print(f"AVISO Modpack: {len(archivos)} archivos del lado del servidor.")
    return 0


def bajar_modrinth(url, sha512, destino):
    """Baja un archivo de Modrinth (el .mrpack elegido en el asistente) comprobando la suma."""
    if not url_permitida(url, ("cdn.modrinth.com",)) or not re.fullmatch(r"[0-9a-f]{128}", sha512):
        print("ERROR Dirección o suma rara.")
        return 1
    bajar(url, destino, {"sha512": sha512})
    return 0


def propiedades(archivo, pares):
    """Escribe server.properties (clave=valor), con los caracteres raros escapados como Java."""
    def escapar(texto, clave=False):
        salida = ""
        for c in texto:
            if c in "\\":
                salida += "\\\\"
            elif c in "=:#!" or (clave and c == " "):
                salida += "\\" + c
            elif ord(c) < 0x20 or ord(c) > 0x7E:
                salida += "\\u%04x" % ord(c)
            else:
                salida += c
        return salida
    lineas = ["#Minecraft server properties (armado por Arch-Linux-Manager)"]
    for par in pares:
        clave, _, valor = par.partition("=")
        if not re.fullmatch(r"[a-z0-9.\-]+", clave):
            raise ValueError(f"clave rara: {clave}")
        lineas.append(f"{escapar(clave, True)}={escapar(valor)}")
    with open(archivo, "w", encoding="ascii") as f:
        f.write("\n".join(lineas) + "\n")
    return 0


# --- Mundos ---------------------------------------------------------------------------------------
def nbt_version(ruta_level_dat):
    """Data.Version.Name de un level.dat (NBT comprimido con gzip), o "" si no tiene (mundos viejos)."""
    import gzip
    with gzip.open(ruta_level_dat, "rb") as f:
        datos = f.read(8 << 20)
    pos = 0

    def leer(n):
        nonlocal pos
        trozo = datos[pos:pos + n]
        if len(trozo) < n:
            raise ValueError("level.dat cortado")
        pos += n
        return trozo

    def texto():
        return leer(struct.unpack(">H", leer(2))[0]).decode("utf-8", "replace")

    def valor(t, camino):
        # Devuelve el valor si es parte de Data.Version.Name; si no, lo saltea
        if t in (1, 2, 3, 4, 5, 6):
            leer({1: 1, 2: 2, 3: 4, 4: 8, 5: 4, 6: 8}[t])
        elif t in (7, 11, 12):
            n = struct.unpack(">i", leer(4))[0]
            leer(n * {7: 1, 11: 4, 12: 8}[t])
        elif t == 8:
            s = texto()
            return s if camino == ["", "Data", "Version", "Name"] else None
        elif t == 9:
            sub, n = leer(1)[0], struct.unpack(">i", leer(4))[0]
            for _ in range(n):
                valor(sub, camino + ["[]"])
        elif t == 10:
            while True:
                st = leer(1)[0]
                if st == 0:
                    return None
                nombre = texto()
                r = valor(st, camino + [nombre])
                if r is not None:
                    return r
        else:
            raise ValueError(f"tipo NBT desconocido {t}")
        return None

    t = leer(1)[0]
    texto()
    return valor(t, [""]) or ""


def mundo(origen, destino):
    """Prepara un mundo existente (carpeta o .zip con level.dat) en destino/world (formato del juego normal:
    si viene de Paper, el nether y el end van adentro como DIM-1 y DIM1). «MUNDO <versión o ?>»."""
    import shutil
    import zipfile
    tmp = None
    if os.path.isfile(origen) and zipfile.is_zipfile(origen):
        tmp = os.path.join(destino, ".mundo-zip")
        with zipfile.ZipFile(origen) as z:
            total = 0
            for info in z.infolist():
                total += info.file_size
                if total > 50 << 30:
                    print("ERROR El zip es demasiado grande (más de 50 GB descomprimido).")
                    return 1
                ruta = ruta_segura(tmp, info.filename)
                if not ruta or (info.external_attr >> 16) & 0o170000 == 0o120000:
                    print(f"ERROR Ruta peligrosa en el zip: {limpiar(info.filename)}")
                    return 1
                if info.is_dir():
                    os.makedirs(ruta, exist_ok=True)
                    continue
                os.makedirs(os.path.dirname(ruta), exist_ok=True)
                with z.open(info) as a, open(ruta, "wb") as b:
                    shutil.copyfileobj(a, b)
        origen = tmp
    if not os.path.isdir(origen):
        print("ERROR El mundo tiene que ser una carpeta o un .zip.")
        return 1
    # La carpeta con level.dat (puede venir uno o dos niveles adentro, como en los zip)
    base = None
    for raiz, carpetas, archivos in os.walk(origen):
        if "level.dat" in archivos:
            base = raiz
            break
        if raiz[len(origen):].count(os.sep) >= 2:
            carpetas.clear()
    if not base:
        print("ERROR No encontré un mundo de Minecraft (falta level.dat).")
        return 1
    try:
        version = nbt_version(os.path.join(base, "level.dat")) or "?"
    except (OSError, ValueError, EOFError):
        version = "?"
    final = os.path.join(destino, "world")
    shutil.copytree(base, final, symlinks=False, ignore=shutil.ignore_patterns("session.lock", "uid.dat"))
    # Paper guarda el nether y el end aparte (world_nether/DIM-1, world_the_end/DIM1)
    padre, nombre = os.path.dirname(base), os.path.basename(base)
    for sufijo, dim in (("_nether", "DIM-1"), ("_the_end", "DIM1")):
        aparte = os.path.join(padre, nombre + sufijo, dim)
        if os.path.isdir(aparte) and not os.path.exists(os.path.join(final, dim)):
            shutil.copytree(aparte, os.path.join(final, dim), symlinks=False)
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"MUNDO {limpiar(version)}")
    return 0


def varint(n):
    n &= 0xFFFFFFFF
    salida = b""
    while True:
        b = n & 0x7F
        n >>= 7
        salida += bytes([b | (0x80 if n else 0)])
        if not n:
            return salida


def leer_varint(s):
    n = 0
    for i in range(5):
        b = s.recv(1)
        if not b:
            raise OSError("el servidor cortó la conexión")
        n |= (b[0] & 0x7F) << (7 * i)
        if not b[0] & 0x80:
            return n
    raise ValueError("varint demasiado largo")


def ping(puerto):
    """Server List Ping (el de la lista de servidores del juego) al servidor local."""
    puerto = int(puerto)
    if not 0 < puerto < 65536:
        raise ValueError("puerto fuera de rango")
    with socket.create_connection(("127.0.0.1", puerto), timeout=4) as s:
        host = b"127.0.0.1"
        datos = varint(0) + varint(-1) + varint(len(host)) + host + struct.pack(">H", puerto) + varint(1)
        s.sendall(varint(len(datos)) + datos + varint(1) + varint(0))
        largo = leer_varint(s)
        if largo > 1 << 20:
            raise ValueError("respuesta demasiado grande")
        cuerpo = b""
        while len(cuerpo) < largo:
            parte = s.recv(largo - len(cuerpo))
            if not parte:
                raise OSError("respuesta incompleta")
            cuerpo += parte
    # paquete 0: varint id + varint largo + JSON
    i = 0
    while cuerpo[i] & 0x80:
        i += 1
    i += 1
    while cuerpo[i] & 0x80:
        i += 1
    i += 1
    estado = json.loads(cuerpo[i:].decode("utf-8", "replace"))
    jugadores = estado.get("players") or {}
    nombres = [limpiar(j.get("name", "")).replace(",", " ") for j in jugadores.get("sample") or []]
    nombres = [n for n in nombres if n and n != "Anonymous Player"]
    print(f"JUGADORES {int(jugadores.get('online', 0))}\t{int(jugadores.get('max', 0))}\t{','.join(nombres)}")
    return 0


def main(args):
    if len(args) >= 2 and args[0] == "paper":
        return paper(args[1])
    if len(args) >= 2 and args[0] == "plugins":
        # plugins VERSION [--tipo=fabric|forge|paper] ARCHIVO...
        if len(args) >= 3 and args[2].startswith("--tipo="):
            return plugins(args[1], args[3:], CARGADORES_TIPO.get(args[2][7:]))
        return plugins(args[1], args[2:])
    if len(args) >= 3 and args[0] == "buscar":
        return buscar(args[1], " ".join(args[2:]))
    if len(args) >= 4 and args[0] == "complementos":
        return complementos(args[1], args[2], args[3:])
    if args == ["opciones"]:
        return opciones()
    if len(args) == 2 and args[0] == "vanilla":
        return vanilla(args[1])
    if len(args) in (2, 3) and args[0] in ("fabric", "forge"):
        return (fabric if args[0] == "fabric" else forge)(args[1], args[2] if len(args) == 3 else "")
    if len(args) == 5 and args[0] == "buscar-modrinth":
        return modrinth_buscar(args[1], args[2], args[3], args[4])
    if len(args) == 2 and args[0] == "modpack-versiones":
        return modpack_versiones(args[1])
    if len(args) == 5 and args[0] == "mrpack":
        return mrpack(args[1], args[2], args[3], args[4])
    if len(args) == 4 and args[0] == "bajar-modrinth":
        return bajar_modrinth(args[1], args[2], args[3])
    if len(args) >= 2 and args[0] == "propiedades":
        return propiedades(args[1], args[2:])
    if len(args) == 3 and args[0] == "mundo":
        return mundo(args[1], args[2])
    if len(args) == 2 and args[0] == "ping":
        return ping(args[1])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, KeyError, TypeError, IndexError, StopIteration, zipfile.BadZipFile) as e:
        print(f"ERROR {limpiar(e)}", file=sys.stderr)
        sys.exit(1)
