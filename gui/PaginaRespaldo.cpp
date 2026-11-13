#include "PaginaRespaldo.h"
#include "ui_PaginaRespaldo.h"

#include <QDir>
#include <QFileInfo>
#include <QFontMetrics>
#include <QMessageBox>

#include <csignal>
#include <unistd.h>

PaginaRespaldo::PaginaRespaldo(const QString &tipo, const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaRespaldo), tipo(tipo),
      scriptRespaldo(QDir(logica).filePath(QStringLiteral("Respaldo.sh")))
{
    ui->setupUi(this);

    // Título y explicación de cada tipo (lo que antes avisaban los kdialog)
    if (tipo == u"linux") {
        setWindowTitle(tr("Respaldo-Linux"));
        ui->etiquetaDescripcion->setText(tr(
            "Copia tu carpeta personal al servidor con rsync. Lo que borraste acá también se "
            "borra del respaldo. No se copian .ssh, la caché, Steam, los juegos ni lo demás que "
            "excluye Rsync_Filtro.conf."));
    } else if (tipo == u"restauracion") {
        setWindowTitle(tr("Restauración-Linux"));
        ui->etiquetaDescripcion->setText(tr(
            "Trae tu respaldo desde el servidor a tu carpeta personal. Reemplaza los archivos que "
            "tengan el mismo nombre, pero no borra los que no estén en el respaldo."));
        ui->botonEmpezar->setIcon(QIcon::fromTheme(QStringLiteral("document-revert")));
    } else if (tipo == u"carina") {
        setWindowTitle(tr("Respaldo del trabajo de Carina"));
        ui->etiquetaDescripcion->setText(tr(
            "Copia la carpeta de Carina y el programa S.I.Ap desde la partición de Windows al "
            "servidor. Si la partición no está montada, se monta (pide permiso)."));
    } else {
        setWindowTitle(tr("Respaldo de Minecraft"));
        ui->etiquetaDescripcion->setText(tr(
            "Copia los servidores de Minecraft al servidor de respaldos, sin cache, libraries, "
            "versions ni logs (Paper los vuelve a descargar). Conviene apagar los servidores antes."));
    }
    ui->barraProgreso->hide();

    connect(ui->botonEmpezar, &QPushButton::clicked, this, [this] { empezar(false); });
    connect(ui->editContrasena, &QLineEdit::returnPressed, this, [this] { empezar(false); });
    connect(ui->botonCancelar, &QPushButton::clicked, this, &PaginaRespaldo::cancelar);

    if (!QFileInfo(scriptRespaldo).isFile())
        anotar(tr("No se encontró %1").arg(scriptRespaldo));
}

PaginaRespaldo::~PaginaRespaldo()
{
    delete ui;
}

bool PaginaRespaldo::ocupada() const
{
    return proceso && proceso->state() != QProcess::NotRunning;
}

void PaginaRespaldo::cancelarYEsperar()
{
    cancelar();
    if (proceso)
        proceso->waitForFinished(3000);
}

void PaginaRespaldo::habilitarFormulario(bool habilitado)
{
    ui->grupoContrasena->setEnabled(habilitado);
    ui->botonEmpezar->setEnabled(habilitado);
    ui->botonCancelar->setEnabled(!habilitado);
}

void PaginaRespaldo::anotar(const QString &texto)
{
    ui->registro->appendPlainText(texto);
}

// forzar: respaldar Minecraft aunque haya servidores encendidos (después de preguntar)
void PaginaRespaldo::empezar(bool forzar)
{
    if (ocupada())
        return;
    if (!forzar) {
        contrasena = ui->editContrasena->text();
        if (contrasena.isEmpty()) {
            ui->etiquetaEstado->setText(tr("Escribí la contraseña SSH del servidor."));
            ui->editContrasena->setFocus();
            return;
        }
        // La restauración reemplaza archivos de tu carpeta personal: se confirma antes
        if (tipo == u"restauracion"
            && QMessageBox::question(this, windowTitle(),
                   tr("Los archivos de tu carpeta personal que también estén en el respaldo se "
                      "van a reemplazar por la versión del servidor. ¿Continuar?")) != QMessageBox::Yes)
            return;
    }
    ui->editContrasena->clear();    // no queda escrita en la ventana

    cancelado = false;
    encendidos.clear();
    mensajeFinal.clear();
    ui->registro->clear();
    ui->etiquetaArchivo->clear();
    ui->barraProgreso->setValue(0);
    ui->barraProgreso->show();
    ui->etiquetaEstado->setText(tr("Buscando el servidor..."));
    habilitarFormulario(false);

    // Un QProcess nuevo por respaldo; se borra solo al terminar
    proceso = new QProcess(this);
    connect(proceso, &QProcess::readyReadStandardOutput, this, &PaginaRespaldo::leerSalida);
    connect(proceso, &QProcess::finished, this, &PaginaRespaldo::terminoProceso);
    proceso->setProcessChannelMode(QProcess::MergedChannels);
    // Respaldo.sh, rsync y sshpass en su propio grupo: Cancelar los corta a todos juntos
    proceso->setChildProcessModifier([] { setpgid(0, 0); });

    QStringList argumentos{scriptRespaldo, tipo};
    if (forzar)
        argumentos << QStringLiteral("--forzar");
    proceso->start(QStringLiteral("bash"), argumentos);

    // La contraseña va por la entrada estándar: nunca aparece en la lista de procesos
    proceso->write(contrasena.toUtf8() + '\n');
    proceso->closeWriteChannel();
}

void PaginaRespaldo::cancelar()
{
    if (!proceso || proceso->state() == QProcess::NotRunning)
        return;
    cancelado = true;
    ::kill(-static_cast<pid_t>(proceso->processId()), SIGTERM);
    ui->etiquetaEstado->setText(tr("Cancelando..."));
}

void PaginaRespaldo::leerSalida()
{
    while (proceso && proceso->canReadLine())
        procesarEvento(QString::fromUtf8(proceso->readLine()).trimmed());
}

void PaginaRespaldo::procesarEvento(const QString &linea)
{
    const qsizetype espacio = linea.indexOf(u' ');
    const QString evento = linea.left(espacio);
    const QString resto = espacio < 0 ? QString() : linea.mid(espacio + 1);

    if (evento == u"ETAPA") {
        ui->etiquetaEstado->setText(resto + QStringLiteral("..."));
        ui->barraProgreso->setValue(0);
    } else if (evento == u"ARCHIVO") {
        // El nombre se recorta por el medio para que entre en una línea
        const QFontMetrics medidas(ui->etiquetaArchivo->font());
        ui->etiquetaArchivo->setText(medidas.elidedText(resto, Qt::ElideMiddle, ui->etiquetaArchivo->width()));
    } else if (evento == u"PROGRESO") {
        ui->barraProgreso->setValue(resto.toInt());
    } else if (evento == u"DESTINO") {
        anotar(resto);
    } else if (evento == u"AVISO") {
        anotar(resto);
    } else if (evento == u"ENCENDIDOS") {
        encendidos = resto;
    } else if (evento == u"CONTADOR") {
        const int n = resto.toInt();
        anotar(n == 1 ? tr("Hiciste 1 respaldo.") : tr("Hiciste %1 respaldos.").arg(n));
    } else if (evento == u"LISTO" || evento == u"ERROR") {
        mensajeFinal = resto;
    } else if (!linea.isEmpty()) {
        anotar(linea);    // cualquier otra salida (p. ej. errores de bash)
    }
}

void PaginaRespaldo::terminoProceso(int codigo, QProcess::ExitStatus estado)
{
    leerSalida();
    proceso->deleteLater();
    proceso = nullptr;
    habilitarFormulario(true);
    ui->etiquetaArchivo->clear();

    // Minecraft con servidores encendidos: se pregunta y, si se acepta, se repite forzando
    if (codigo == 4 && !cancelado) {
        if (QMessageBox::warning(this, windowTitle(),
                tr("Estos servidores están encendidos: %1\nConviene apagarlos antes de respaldar. "
                   "¿Continuar igual?").arg(encendidos),
                QMessageBox::Yes | QMessageBox::No) == QMessageBox::Yes) {
            empezar(true);
            return;
        }
        ui->etiquetaEstado->setText(tr("Respaldo cancelado."));
    } else if (cancelado || estado == QProcess::CrashExit) {
        ui->etiquetaEstado->setText(tr("Respaldo cancelado."));
    } else if (codigo == 0) {
        ui->barraProgreso->setValue(100);
        ui->etiquetaEstado->setText(QStringLiteral("✓ ") + mensajeFinal);
        emit respaldoTerminado();
    } else if (codigo == 3) {
        ui->barraProgreso->hide();
        ui->etiquetaEstado->setText(tr("✗ Contraseña incorrecta, volvé a escribirla."));
        ui->editContrasena->setFocus();
    } else {
        ui->etiquetaEstado->setText(QStringLiteral("✗ ") + (mensajeFinal.isEmpty() ? tr("El respaldo falló.") : mensajeFinal));
    }
    contrasena.clear();    // ya no hace falta en memoria
}
