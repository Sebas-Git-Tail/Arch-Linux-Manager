#include "Terminal.h"

#include <QCoreApplication>
#include <QDir>
#include <QProcess>

namespace terminal {

static QString script(const QString &base)
{
    return QDir(base).filePath(QStringLiteral("Common/Terminal.sh"));
}

QString disponible(const QString &base)
{
    QProcess cual;
    cual.start(QStringLiteral("bash"), {script(base), QStringLiteral("--cual")});
    if (!cual.waitForFinished(3000) || cual.exitStatus() != QProcess::NormalExit || cual.exitCode() != 0) {
        cual.kill();
        return {};
    }
    return QString::fromUtf8(cual.readAllStandardOutput()).trimmed();
}

QStringList argumentos(const QString &base, const QStringList &comando, bool esperar)
{
    QStringList lista{script(base)};
    if (esperar)
        lista << QStringLiteral("--esperar");
    return lista << QStringLiteral("--") << comando;
}

QString sinTerminal()
{
    return QCoreApplication::translate("terminal",
        "No hay ninguna terminal instalada (konsole, xterm, alacritty, kitty, gnome-terminal…). "
        "Instalá una, por ejemplo konsole.");
}

}
