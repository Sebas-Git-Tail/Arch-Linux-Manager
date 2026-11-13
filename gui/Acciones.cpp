#include "Acciones.h"

#include <QObject>

QList<Seccion> secciones()
{
    return {
        {QStringLiteral("general"),   QStringLiteral("🏠"), QObject::tr("General")},
        {QStringLiteral("android"),   QStringLiteral("🤖"), QObject::tr("Android")},
        {QStringLiteral("minecraft"), QStringLiteral("⛏️"), QObject::tr("Minecraft")},
        {QStringLiteral("servidor"),  QStringLiteral("🖥️"), QObject::tr("Servidor")},
        {QStringLiteral("carina"),    QStringLiteral("💼"), QObject::tr("Trabajo de Carina")},
    };
}

QList<Accion> acciones()
{
    const auto siempre = [](const Entorno &) { return true; };
    const auto conServidor = [](const Entorno &e) { return e.servidor; };
    // Minecraft: tu PC o la del instituto, con Prism Launcher (antes: Lista-Sebastian.sh)
    const auto minecraft = [](const Entorno &e) { return e.esSebastian() && e.tiene(QStringLiteral("prismlauncher")); };

    return {
        // ── General (antes: Lista-General.sh) ──
        {QStringLiteral("general"), QStringLiteral("🔄"), QObject::tr("Actualizar Arch"),
         QObject::tr("Actualiza el sistema en una terminal (pide la contraseña de sudo)."),
         TipoAccion::Terminal, QStringLiteral("General/Actualizar.sh"), {}, siempre},
        {QStringLiteral("general"), QStringLiteral("💾"), QObject::tr("Respaldo-Linux"),
         QObject::tr("Copia tu carpeta personal al servidor."),
         TipoAccion::Pagina, QStringLiteral("respaldo-linux"), {}, conServidor},
        {QStringLiteral("general"), QStringLiteral("♻️"), QObject::tr("Restauración-Linux"),
         QObject::tr("Trae tu respaldo desde el servidor (solo si esta PC todavía no hizo ninguno)."),
         TipoAccion::Pagina, QStringLiteral("restauracion"), {},
         [](const Entorno &e) { return e.restauracion; }},
        {QStringLiteral("general"), QStringLiteral("▶️"), QObject::tr("Descargar Vídeos"),
         QObject::tr("YouTube y redes sociales con yt-dlp."),
         TipoAccion::Pagina, QStringLiteral("videos"), {}, siempre},
        {QStringLiteral("general"), QStringLiteral("🎵"), QObject::tr("Descargar Música"),
         QObject::tr("YouTube Music, ordenada en carpetas por artista."),
         TipoAccion::Pagina, QStringLiteral("musica"), {}, siempre},
        {QStringLiteral("general"), QStringLiteral("📽️"), QObject::tr("Tutoriales"),
         QObject::tr("Videos del servidor, reproducidos con mpv."),
         TipoAccion::Pagina, QStringLiteral("tutoriales"), {}, conServidor},
        {QStringLiteral("general"), QStringLiteral("🎮"), QObject::tr("Steam Proton"),
         QObject::tr("Instala la última versión de GE-Proton para Steam."),
         TipoAccion::Pagina, QStringLiteral("steam"), {},
         [](const Entorno &e) { return e.tiene(QStringLiteral("steam")); }},
        {QStringLiteral("general"), QStringLiteral("🔔"), QObject::tr("Notificaciones"),
         QObject::tr("Manda un mensaje que aparece como notificación en la PC de Sebastián."),
         TipoAccion::Pagina, QStringLiteral("notificaciones"), {},
         [](const Entorno &e) { return e.notificaciones; }},
        {QStringLiteral("general"), QStringLiteral("📦"), QObject::tr("Descargas en masa"),
         QObject::tr("Varios archivos a la vez con wget."),
         TipoAccion::Pagina, QStringLiteral("descargas-masa"), {},
         [](const Entorno &e) { return e.maquina == u"mama" || e.maquina == u"pc"; }},

        // ── Android (antes: Lista-Android.sh) ──
        {QStringLiteral("android"), QStringLiteral("🤖"), QObject::tr("Cerrar Waydroid"),
         QObject::tr("Detiene Waydroid (Android dentro de Linux)."),
         TipoAccion::Logica, QStringLiteral("Logica/Android.sh"), {QStringLiteral("cerrar-waydroid")},
         [](const Entorno &e) { return e.tiene(QStringLiteral("waydroid")); }},
        {QStringLiteral("android"), QStringLiteral("📱"), QObject::tr("Celular"),
         QObject::tr("Apps FOSS y debloat del celular conectado por adb."),
         TipoAccion::Pagina, QStringLiteral("android"), {},
         [](const Entorno &e) { return e.tiene(QStringLiteral("adb")); }},

        // ── Minecraft (antes: Lista-Minecraft.sh) ──
        {QStringLiteral("minecraft"), QStringLiteral("⛏️"), QObject::tr("Panel de Minecraft"),
         QObject::tr("Iniciar y reiniciar los servidores Paper, actualizar Paper, instalar plugins y jugar con Prism Launcher."),
         TipoAccion::Pagina, QStringLiteral("minecraft"), {}, minecraft},
        {QStringLiteral("minecraft"), QStringLiteral("💾"), QObject::tr("Respaldo"),
         QObject::tr("Copia los servidores de Minecraft al servidor de respaldos."),
         TipoAccion::Pagina, QStringLiteral("respaldo-minecraft"), {}, minecraft},
        {QStringLiteral("minecraft"), QStringLiteral("🌐"), QObject::tr("Playit"),
         QObject::tr("Abre el túnel para que se conecten desde afuera de tu red."),
         TipoAccion::Programa, QStringLiteral("konsole"),
         {QStringLiteral("-e"), QStringLiteral("/home/sebastian/Escritorio/Cosas/Minecraft Servers/playit-linux-amd64")},
         minecraft},

        // ── Servidor (antes: Lista-Server.sh) ──
        {QStringLiteral("servidor"), QStringLiteral("📦"), QObject::tr("App"),
         QObject::tr("Publica una versión nueva en tu repositorio de pacman del servidor (en una terminal)."),
         TipoAccion::Terminal, QStringLiteral("Sebastian/Server/App.sh"), {},
         [](const Entorno &e) { return e.esSebastian() && e.servidor; }},

        // ── Trabajo de Carina (antes: Lista-Mamá.sh) ──
        {QStringLiteral("carina"), QStringLiteral("💼"), QObject::tr("Respaldo del trabajo"),
         QObject::tr("Copia el trabajo de Carina desde Windows al servidor."),
         TipoAccion::Pagina, QStringLiteral("respaldo-carina"), {},
         [](const Entorno &e) { return e.maquina == u"mama" && e.servidor; }},
    };
}
