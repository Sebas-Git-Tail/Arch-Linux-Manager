#!/usr/bin/env python3
"""Consultas para el panel de Minecraft (lo usa Logica/Minecraft.sh; no descarga nada, solo informa).

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

Para las pruebas: MINECRAFT_API_FALSA=<carpeta> lee las respuestas de archivos de esa carpeta en vez de
ir a internet (ver tests/correr.sh).
"""
import hashlib
import json
import os
import re
import sys
import urllib.parse
import urllib.request

AGENTE = "Sebas-Git-Tail/Arch-Linux-Manager (github.com/Sebas-Git-Tail/Arch-Linux-Manager)"
MODRINTH = "https://api.modrinth.com/v2"
CARGADORES = ["paper", "spigot", "bukkit", "purpur", "folia"]
FALSA = os.environ.get("MINECRAFT_API_FALSA")


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


def plugins(version_mc, rutas):
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
                           {"hashes": hashes, "algorithm": "sha1", "loaders": CARGADORES, "game_versions": [version_mc]})
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
        if proyecto:
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


def buscar(version_mc, texto):
    texto = texto.strip()
    m = re.search(r"modrinth\.com/(?:plugin|mod|project)/([A-Za-z0-9_.-]+)", texto)
    candidatos = []
    if m:
        candidatos = [m.group(1)]
    else:
        # Nombre o slug: primero tal cual (slug), después la búsqueda
        if re.fullmatch(r"[A-Za-z0-9_.-]+", texto):
            candidatos.append(texto.lower())
        facetas = json.dumps([["project_type:plugin"], [f"versions:{version_mc}"]])
        try:
            r = pedir(f"{MODRINTH}/search?limit=5&query={urllib.parse.quote(texto)}&facets={urllib.parse.quote(facetas)}")
            candidatos += [h["slug"] for h in r.get("hits", [])]
        except OSError:
            pass
    for slug in candidatos:
        try:
            proyecto = pedir(f"{MODRINTH}/project/{urllib.parse.quote(slug)}")
            versiones = pedir(f"{MODRINTH}/project/{urllib.parse.quote(slug)}/version?loaders="
                              + urllib.parse.quote(json.dumps(CARGADORES))
                              + "&game_versions=" + urllib.parse.quote(json.dumps([version_mc])))
        except OSError:
            continue
        if not versiones:
            continue
        v = versiones[0]
        principal = archivo_principal(v)
        if not principal:
            continue
        print("ENCONTRADO " + "\t".join(limpiar(x) for x in (proyecto["slug"], proyecto.get("title", slug), v["version_number"],
              principal["url"], principal["hashes"].get("sha512", ""), principal["filename"])))
        return 0
    return 1


def main(args):
    if len(args) >= 2 and args[0] == "paper":
        return paper(args[1])
    if len(args) >= 2 and args[0] == "plugins":
        return plugins(args[1], args[2:])
    if len(args) >= 3 and args[0] == "buscar":
        return buscar(args[1], " ".join(args[2:]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, KeyError) as e:
        print(f"ERROR {e}", file=sys.stderr)
        sys.exit(1)
