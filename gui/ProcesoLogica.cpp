#include "ProcesoLogica.h"

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

void ProcesoLogica::iniciar(const QString &script, const QStringList &argumentos, const QByteArray &entrada)
{
    if (ocupado())
        return;
    cancelado = false;
    proceso.start(QStringLiteral("bash"), QStringList{script} + argumentos);
    if (!entrada.isEmpty())
        proceso.write(entrada);
    proceso.closeWriteChannel();
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
    cancelar();
    proceso.waitForFinished(3000);
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
