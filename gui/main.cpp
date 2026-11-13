// Arch-Linux-Manager-Qt: la ventana del Manager. Solo es la interfaz; la lógica está en
// Bash (Resources/Logica).
//
// Uso: Arch-Linux-Manager-Qt [--base CARPETA]
//      Arch-Linux-Manager-Qt --notificacion < mensaje   (lo usa Mostrar-Notificacion.sh)
// La carpeta Resources se busca en este orden: --base, la variable BASE (la exporta
// Arch-Linux-Manager.sh) y la instalación del paquete. Para probar sin instalar:
//   Arch-Linux-Manager-Qt --base ~/Escritorio/Manager/src/Resources

#include "VentanaPrincipal.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIcon>
#include <QMessageBox>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("Arch-Linux-Manager"));
    // Mismo nombre que el .desktop, así KDE le pone el ícono y el atajo del Manager
    QApplication::setDesktopFileName(QStringLiteral("Arch-Linux-Manager"));

    QCommandLineParser opciones;
    opciones.setApplicationDescription(QStringLiteral("Conjunto de herramientas para Arch Linux"));
    opciones.addHelpOption();
    QCommandLineOption opcionBase(QStringLiteral("base"),
        QStringLiteral("Carpeta Resources (scripts y lógica)."), QStringLiteral("carpeta"));
    opciones.addOption(opcionBase);
    QCommandLineOption opcionNotificacion(QStringLiteral("notificacion"),
        QStringLiteral("Muestra el mensaje que llega por la entrada estándar y sale."));
    opciones.addOption(opcionNotificacion);
    opciones.process(app);

    // Notificación recibida de otra computadora (Mostrar-Notificacion.sh): solo el mensaje
    if (opciones.isSet(opcionNotificacion)) {
        QFile entrada;
        if (!entrada.open(stdin, QIODevice::ReadOnly))
            return 1;
        const QString mensaje = QString::fromUtf8(entrada.read(4000)).trimmed();
        if (mensaje.isEmpty())
            return 1;
        QMessageBox caja(QMessageBox::Information, QStringLiteral("Notificación"), mensaje);
        caja.setWindowIcon(QIcon::fromTheme(QStringLiteral("preferences-desktop-notification")));
        caja.exec();
        return 0;
    }

    QString base = opciones.value(opcionBase);
    if (base.isEmpty())
        base = qEnvironmentVariable("BASE");
    if (base.isEmpty())
        base = QStringLiteral("/usr/share/Arch-Linux-Manager/Resources");
    base = QDir(base).absolutePath();

    // Las mismas variables que exporta Arch-Linux-Manager.sh: así las heredan todos los
    // scripts que lance la ventana, aunque se la abra directo con --base
    const QDir carpeta(base);
    qputenv("BASE", base.toUtf8());
    qputenv("COMMON", carpeta.filePath(QStringLiteral("Common")).toUtf8());
    qputenv("LOGICA", carpeta.filePath(QStringLiteral("Logica")).toUtf8());
    qputenv("GENERAL", carpeta.filePath(QStringLiteral("General")).toUtf8());
    qputenv("SEBASTIAN", carpeta.filePath(QStringLiteral("Sebastian")).toUtf8());

    const QString logo = QDir(base).filePath(QStringLiteral("Logo.png"));
    if (QFileInfo::exists(logo))
        QApplication::setWindowIcon(QIcon(logo));

    VentanaPrincipal ventana(base);
    ventana.show();
    return app.exec();
}
