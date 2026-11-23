#include "Acciones.h"

#include <QObject>

QList<Seccion> secciones()
{
    return {
        {QStringLiteral("general"),   QStringLiteral("inicio"), QObject::tr("General")},
        {QStringLiteral("android"),   QStringLiteral("android"), QObject::tr("Android")},
        {QStringLiteral("minecraft"), QStringLiteral("bloque"), QObject::tr("Minecraft")},
        {QStringLiteral("servidor"),  QStringLiteral("servidor"), QObject::tr("Servidor")},
        {QStringLiteral("carina"),    QStringLiteral("maletin"), QObject::tr("Trabajo de Carina")},
    };
}

QList<Accion> acciones()
{
    const auto siempre = [](const Entorno &) { return true; };
    const auto conServidor = [](const Entorno &e) { return e.servidor; };
    // Minecraft: tu PC o la del instituto, con Prism Launcher (antes: Lista-Sebastian.sh)
    const auto minecraft = [](const Entorno &e) { return e.esSebastian() && e.tiene(QStringLiteral("prismlauncher")); };
    // Sección Servidor: solo tus equipos (además, el servidor solo acepta las claves que autorizaste)
    const auto soloSebastian = [](const Entorno &e) { return e.esSebastian() && e.servidor; };

    return {
        // ── General (antes: Lista-General.sh) ──
        {QStringLiteral("general"), QStringLiteral("actualizar"), QObject::tr("Actualizar Arch"),
         QObject::tr("Actualiza el sistema en una terminal (pide la contraseña de sudo)."),
         TipoAccion::Terminal, QStringLiteral("General/Actualizar.sh"), {}, siempre},
        {QStringLiteral("general"), QStringLiteral("paquete"), QObject::tr("Apps y actualizaciones"),
         QObject::tr("Actualiza el Manager e instala los otros programas de Sebastián."),
         TipoAccion::Pagina, QStringLiteral("apps"), {}, siempre},
        // Cuáles apps ve cada equipo lo decide Common/AUR.sh (en todos hay al menos una)
        {QStringLiteral("general"), QStringLiteral("apps"), QObject::tr("Apps del AUR"),
         QObject::tr("Instala y actualiza apps que no están en los repositorios de Arch."),
         TipoAccion::Pagina, QStringLiteral("aur"), {}, siempre},
        {QStringLiteral("general"), QStringLiteral("respaldo"), QObject::tr("Respaldo-Linux"),
         QObject::tr("Copia tu carpeta personal al servidor."),
         TipoAccion::Pagina, QStringLiteral("respaldo-linux"), {}, conServidor},
        {QStringLiteral("general"), QStringLiteral("restaurar"), QObject::tr("Restauración-Linux"),
         QObject::tr("Trae tu respaldo desde el servidor (solo si esta PC todavía no hizo ninguno)."),
         TipoAccion::Pagina, QStringLiteral("restauracion"), {},
         [](const Entorno &e) { return e.restauracion; }},
        {QStringLiteral("general"), QStringLiteral("video"), QObject::tr("Descargar Vídeos"),
         QObject::tr("YouTube y redes sociales con yt-dlp."),
         TipoAccion::Pagina, QStringLiteral("videos"), {}, siempre},
        {QStringLiteral("general"), QStringLiteral("musica"), QObject::tr("Descargar Música"),
         QObject::tr("YouTube Music, ordenada en carpetas por artista."),
         TipoAccion::Pagina, QStringLiteral("musica"), {}, siempre},
        {QStringLiteral("general"), QStringLiteral("libro"), QObject::tr("Tutoriales"),
         QObject::tr("Videos del servidor, reproducidos con mpv."),
         TipoAccion::Pagina, QStringLiteral("tutoriales"), {}, conServidor},
        {QStringLiteral("general"), QStringLiteral("juego"), QObject::tr("Steam Proton"),
         QObject::tr("Instala la última versión de GE-Proton para Steam."),
         TipoAccion::Pagina, QStringLiteral("steam"), {},
         [](const Entorno &e) { return e.tiene(QStringLiteral("steam")); }},
        {QStringLiteral("general"), QStringLiteral("campana"), QObject::tr("Notificaciones"),
         QObject::tr("Manda un mensaje que aparece como notificación en la PC de Sebastián."),
         TipoAccion::Pagina, QStringLiteral("notificaciones"), {},
         [](const Entorno &e) { return e.notificaciones; }},
        {QStringLiteral("general"), QStringLiteral("descargar"), QObject::tr("Descargas en masa"),
         QObject::tr("Varios archivos a la vez con wget."),
         TipoAccion::Pagina, QStringLiteral("descargas-masa"), {},
         [](const Entorno &e) { return e.maquina == u"mama" || e.maquina == u"pc"; }},

        // ── Android (antes: Lista-Android.sh) ──
        {QStringLiteral("android"), QStringLiteral("cerrar"), QObject::tr("Cerrar Waydroid"),
         QObject::tr("Detiene Waydroid (Android dentro de Linux)."),
         TipoAccion::Logica, QStringLiteral("Logica/Android.sh"), {QStringLiteral("cerrar-waydroid")},
         [](const Entorno &e) { return e.tiene(QStringLiteral("waydroid")); }},
        {QStringLiteral("android"), QStringLiteral("celular"), QObject::tr("Celular"),
         QObject::tr("Apps FOSS y debloat del celular conectado por adb."),
         TipoAccion::Pagina, QStringLiteral("android"), {},
         [](const Entorno &e) { return e.tiene(QStringLiteral("adb")); }},

        // ── Minecraft (antes: Lista-Minecraft.sh) ──
        {QStringLiteral("minecraft"), QStringLiteral("bloque"), QObject::tr("Panel de Minecraft"),
         QObject::tr("Iniciar los servidores, ver su consola y mandarles comandos, actualizar Paper y plugins, y jugar con Prism Launcher."),
         TipoAccion::Pagina, QStringLiteral("minecraft"), {}, minecraft},
        {QStringLiteral("minecraft"), QStringLiteral("respaldo"), QObject::tr("Respaldo"),
         QObject::tr("Copia los servidores de Minecraft al servidor de respaldos."),
         TipoAccion::Pagina, QStringLiteral("respaldo-minecraft"), {}, minecraft},
        {QStringLiteral("minecraft"), QStringLiteral("globo"), QObject::tr("Playit"),
         QObject::tr("Abre el túnel para que se conecten desde afuera de tu red."),
         TipoAccion::Programa, QStringLiteral("konsole"),
         // playit-bin (AUR) queda en /usr/bin/playit; antes era un binario suelto en Minecraft Servers
         {QStringLiteral("-e"), QStringLiteral("playit")},
         minecraft},

        // ── Servidor: acciones que corren en el servidor con la clave limitada de este equipo ──
        // (Logica/Acciones-servidor.sh → ~/Repo/Scripts/acciones-servidor.sh del servidor)
        {QStringLiteral("servidor"), QStringLiteral("video"), QObject::tr("Miniaturas de Bodrio"),
         QObject::tr("Crea en el servidor las miniaturas que falten de los videos de Bodrio."),
         TipoAccion::Logica, QStringLiteral("Logica/Acciones-servidor.sh"), {QStringLiteral("miniaturas-bodrio")}, soloSebastian},
        {QStringLiteral("servidor"), QStringLiteral("descargar"), QObject::tr("Páginas de descargas"),
         QObject::tr("Rehace las páginas de Música, Android y Minecraft del sitio con lo que haya en esas carpetas."),
         TipoAccion::Logica, QStringLiteral("Logica/Acciones-servidor.sh"), {QStringLiteral("descargas")}, soloSebastian},
        {QStringLiteral("servidor"), QStringLiteral("libro"), QObject::tr("Páginas del Instituto"),
         QObject::tr("Rehace el índice de cada carpeta del Instituto en el sitio."),
         TipoAccion::Logica, QStringLiteral("Logica/Acciones-servidor.sh"), {QStringLiteral("indices-instituto")}, soloSebastian},

        // ── Trabajo de Carina (antes: Lista-Mamá.sh) ──
        {QStringLiteral("carina"), QStringLiteral("maletin"), QObject::tr("Respaldo del trabajo"),
         QObject::tr("Copia el trabajo de Carina desde Windows al servidor."),
         TipoAccion::Pagina, QStringLiteral("respaldo-carina"), {},
         [](const Entorno &e) { return e.maquina == u"mama" && e.servidor; }},
    };
}
