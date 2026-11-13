
1. El debloteo de Android debe permitir elegir usuario, por ejemplo el 0, 10, 999, etc, se tienen que detectar automáticamente y no ser predefinidos.
2. El descargador de vídeos debe permitir embebir subtítulos y descargar las distintas fuentes de audio que ofrezca YouTube.
3. Cuando termines, cambia la versión del pkgbuild y compila, luego subila al repositorio correspondiente y move las versiones viejas a la carpeta legacy. (Ahora: `~/Repo/Scripts/publicar-paquete.sh Arch-Linux-Manager` lo hace todo; las viejas quedan en `~/Repo/Legacy/Arch-Linux-Manager/`.)