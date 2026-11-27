#include "ProcesoLogica.h"
#include "Piezas.h"

#include <QApplication>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QWidget>

#include <csignal>
#include <unistd.h>

ProcesoLogica::ProcesoLogica(QObject *parent)
    : QObject(parent)
{
    // stdout y stderr juntos: los errores de bash también aparecen (como evento sin palabra conocida)
    proceso.setProcessChannelMode(QProcess::MergedChannels);
    proceso.setChildProcessModifier([] { setpgid(0, 0); });

    connect(&proceso, &QProcess::readyReadStandardOutput, this, &ProcesoLogica::leer);
    connect(&proceso, &QProcess::finished, this, [this](int codigo, QProcess::ExitStatus estado) {
        leer();
        emit terminado(estado == QProcess::NormalExit ? codigo : -1, cancelado);
    });
}

ProcesoLogica::~ProcesoLogica()
{
    // Sin esto, el QProcess emitía «finished» mientras se destruía y la página (con su interfaz ya
    // borrada) recibía «terminado»: se cerraba con una falla. Y solo mataba a bash, no a sus hijos.
    proceso.disconnect(this);
    if (ocupado()) {
        const auto grupo = static_cast<pid_t>(proceso.processId());
        ::kill(-grupo, SIGTERM);
        if (!proceso.waitForFinished(1000))
            ::kill(-grupo, SIGKILL);
        proceso.waitForFinished(1000);
    }
}

bool ProcesoLogica::iniciar(const QString &script, const QStringList &argumentos, const QByteArray &entrada)
{
    if (ocupado()) {
        // Antes se ignoraba en silencio y parecía que el botón no hacía nada
        const QString motivo = tr("Todavía hay una tarea en curso (%1): esperá a que termine o cancelala, y volvé a intentar.")
                                   .arg(QFileInfo(proceso.arguments().value(0)).completeBaseName());
        qWarning("ProcesoLogica: no se inicia %s %s: ya está corriendo %s", qPrintable(QFileInfo(script).fileName()),
                 qPrintable(argumentos.join(u' ')), qPrintable(proceso.arguments().join(u' ')));
        emit rechazado(motivo);
        if (QWidget *ventana = QApplication::activeWindow())
            tema::avisar(ventana, motivo, tema::Estado::Error);
        return false;
    }
    cancelado = false;
    proceso.start(QStringLiteral("bash"), QStringList{script} + argumentos);
    if (!entrada.isEmpty())
        proceso.write(entrada);
    proceso.closeWriteChannel();
    return true;
}

void ProcesoLogica::cancelar()
{
    if (!ocupado())
        return;
    cancelado = true;
    ::kill(-static_cast<pid_t>(proceso.processId()), SIGTERM);    // todo el grupo
}

void ProcesoLogica::cancelarYEsperar()
{
    if (!ocupado())
        return;
    const auto grupo = static_cast<pid_t>(proceso.processId());
    cancelar();
    // Hasta 3 s para que termine todo el grupo (el script y sus hijos, como rsync o adb)
    QElapsedTimer reloj;
    reloj.start();
    while (reloj.elapsed() < 3000 && ::kill(-grupo, 0) == 0) {
        if (ocupado())
            proceso.waitForFinished(100);
        else
            ::usleep(50 * 1000);
    }
    // Si algo del grupo sigue vivo (un hijo que ignora SIGTERM, adb colgado...), se lo corta
    if (::kill(-grupo, 0) == 0) {
        ::kill(-grupo, SIGKILL);
        proceso.waitForFinished(2000);
    }
}

bool ProcesoLogica::ocupado() const
{
    return proceso.state() != QProcess::NotRunning;
}

void ProcesoLogica::leer()
{
    while (proceso.canReadLine()) {
        const QString linea = QString::fromUtf8(proceso.readLine()).trimmed();
        if (linea.isEmpty())
            continue;
        const qsizetype espacio = linea.indexOf(u' ');
        emit evento(linea.left(espacio), espacio < 0 ? QString() : linea.mid(espacio + 1));
    }
}
