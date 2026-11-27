#include "PaginaRespaldo.h"
#include "Tema.h"
#include "ui_PaginaRespaldo.h"

#include <QButtonGroup>
#include <QComboBox>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QPushButton>
#include <QRadioButton>
#include <QStandardPaths>
#include <QToolButton>
#include <QTreeWidgetItem>
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
            "borra del respaldo, pero lo que un respaldo borra o cambia en el servidor queda 30 días "
            "en una copia anterior, y lo podés traer de vuelta desde «Restaurar». No se copian .ssh, "
            "la caché, Steam, los juegos ni lo demás que excluye Rsync_Filtro.conf."));
        armarRestaurar();
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

    ui->historial->header()->setSectionResizeMode(QHeaderView::ResizeToContents);
    ui->historial->header()->setStretchLastSection(true);
    cargarHistorial();
}

// Últimos respaldos de este tipo, del más nuevo al más viejo. Los anota Respaldo.sh en
// ~/.local/share/Arch-Linux-Manager/historial-respaldos.tsv:
//   fecha  tipo  resultado  segundos  transferido  mensaje
void PaginaRespaldo::cargarHistorial()
{
    ui->historial->clear();
    const QString ruta = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                         + QStringLiteral("/Arch-Linux-Manager/historial-respaldos.tsv");
    QFile archivo(ruta);
    QList<QStringList> filas;
    if (archivo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!archivo.atEnd()) {
            const QStringList campos = QString::fromUtf8(archivo.readLine()).chopped(1).split(u'\t');
            // En Respaldo-Linux se ven también las restauraciones (se hacen desde esta página)
            if (campos.size() >= 6 && (campos.at(1) == tipo || (tipo == u"linux" && campos.at(1) == u"restauracion")))
                filas.prepend(campos);
        }
    }
    static const QMap<QString, QString> resultados{
        {QStringLiteral("ok"), QStringLiteral("✓ Bien")},
        {QStringLiteral("error"), QStringLiteral("✗ Error")},
        {QStringLiteral("cancelado"), QStringLiteral("– Cancelado")},
    };
    for (const QStringList &campos : std::as_const(filas).mid(0, 20)) {
        const QDateTime fecha = QDateTime::fromString(campos.at(0), Qt::ISODate);
        const int segundos = campos.at(3).toInt();
        const QString duracion = segundos >= 3600 ? tr("%1 h %2 min").arg(segundos / 3600).arg(segundos % 3600 / 60)
                               : segundos >= 60   ? tr("%1 min %2 s").arg(segundos / 60).arg(segundos % 60)
                                                  : tr("%1 s").arg(segundos);
        QString resultado = resultados.value(campos.at(2), campos.at(2));
        if (tipo == u"linux" && campos.at(1) == u"restauracion")
            resultado += tr(" (restauración)");
        auto *item = new QTreeWidgetItem(ui->historial, {
            fecha.isValid() ? QLocale().toString(fecha.toLocalTime(), QLocale::ShortFormat) : campos.at(0),
            resultado, duracion, campos.at(4), campos.at(5)});
        item->setToolTip(4, campos.at(5));
    }
    ui->grupoHistorial->setVisible(!filas.isEmpty());
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
    if (!ocupada())
        return;
    const auto grupo = static_cast<pid_t>(proceso->processId());
    cancelar();
    // Si a los 3 s sigue vivo (rsync o ssh colgados), se corta todo el grupo
    if (!proceso->waitForFinished(3000)) {
        ::kill(-grupo, SIGKILL);
        proceso->waitForFinished(2000);
    }
}

void PaginaRespaldo::habilitarFormulario(bool habilitado)
{
    ui->grupoContrasena->setEnabled(habilitado);
    ui->botonEmpezar->setEnabled(habilitado);
    ui->botonCancelar->setEnabled(!habilitado);
    if (grupoRestaurar)
        grupoRestaurar->setEnabled(habilitado);
}

// «Restaurar» de Respaldo-Linux: traer todo o una carpeta o archivo, desde la copia actual o
// desde una copia anterior (lo que un respaldo de esa fecha borró o reemplazó en el servidor).
// Nunca borra nada de esta PC (Respaldo.sh restaura sin --delete y guarda lo que reemplaza).
void PaginaRespaldo::armarRestaurar()
{
    grupoRestaurar = new QGroupBox(tr("Restaurar desde el servidor"), this);
    auto *formulario = new QFormLayout(grupoRestaurar);

    auto *explicacion = new QLabel(tr("Trae archivos del respaldo a tu carpeta personal. No borra nada de esta PC: "
                                      "si un archivo ya existe se reemplaza por el del servidor, y el que tenías "
                                      "queda guardado en ~/.local/share/Arch-Linux-Manager/antes-de-restaurar."), grupoRestaurar);
    explicacion->setWordWrap(true);
    explicacion->setProperty("secundario", true);
    formulario->addRow(explicacion);

    // Qué: todo o una carpeta/archivo (relativo a tu carpeta personal; se puede escribir o elegir)
    auto *que = new QWidget(grupoRestaurar);
    auto *filaQue = new QHBoxLayout(que);
    filaQue->setContentsMargins(0, 0, 0, 0);
    radioTodo = new QRadioButton(tr("Todo"), que);
    radioSolo = new QRadioButton(tr("Solo:"), que);
    radioTodo->setChecked(true);
    auto *grupoRadios = new QButtonGroup(que);
    grupoRadios->addButton(radioTodo);
    grupoRadios->addButton(radioSolo);
    editRuta = new QLineEdit(que);
    editRuta->setPlaceholderText(tr("Documentos/Facturas o Imágenes/foto.jpg"));
    editRuta->setToolTip(tr("Carpeta o archivo dentro de tu carpeta personal, tal como estaba cuando se respaldó"));
    editRuta->setEnabled(false);
    botonElegir = new QToolButton(que);
    botonElegir->setText(tr("Elegir…"));
    botonElegir->setPopupMode(QToolButton::InstantPopup);
    botonElegir->setEnabled(false);
    auto *menuElegir = new QMenu(botonElegir);
    menuElegir->addAction(tr("Una carpeta…"), this, [this] { elegirRuta(true); });
    menuElegir->addAction(tr("Un archivo…"), this, [this] { elegirRuta(false); });
    botonElegir->setMenu(menuElegir);
    filaQue->addWidget(radioTodo);
    filaQue->addWidget(radioSolo);
    filaQue->addWidget(editRuta, 1);
    filaQue->addWidget(botonElegir);
    connect(radioSolo, &QRadioButton::toggled, this, [this](bool solo) {
        editRuta->setEnabled(solo);
        botonElegir->setEnabled(solo);
        if (solo)
            editRuta->setFocus();
    });
    formulario->addRow(tr("Qué traer:"), que);

    // Desde: la copia actual o una anterior (se buscan con la contraseña)
    auto *desde = new QWidget(grupoRestaurar);
    auto *filaDesde = new QHBoxLayout(desde);
    filaDesde->setContentsMargins(0, 0, 0, 0);
    comboDesde = new QComboBox(desde);
    comboDesde->addItem(tr("La copia actual (el último respaldo)"), QStringLiteral("actual"));
    comboDesde->setSizeAdjustPolicy(QComboBox::AdjustToContents);
    botonBuscarAnteriores = new QPushButton(tr("Buscar copias anteriores"), desde);
    botonBuscarAnteriores->setToolTip(tr("Cada respaldo guarda 30 días lo que borró o cambió en el servidor. "
                                         "Usa la contraseña de arriba."));
    filaDesde->addWidget(comboDesde, 1);
    filaDesde->addWidget(botonBuscarAnteriores);
    formulario->addRow(tr("Desde:"), desde);

    botonRestaurar = new QPushButton(QIcon::fromTheme(QStringLiteral("document-revert")), tr("Restaurar…"), grupoRestaurar);
    auto *filaBoton = new QHBoxLayout;
    filaBoton->addStretch();
    filaBoton->addWidget(botonRestaurar);
    formulario->addRow(filaBoton);

    connect(botonBuscarAnteriores, &QPushButton::clicked, this, &PaginaRespaldo::buscarAnteriores);
    connect(botonRestaurar, &QPushButton::clicked, this, &PaginaRespaldo::restaurarElegido);

    // Debajo de los botones del respaldo
    auto *principal = qobject_cast<QBoxLayout *>(layout());
    principal->insertWidget(principal->indexOf(ui->etiquetaEstado), grupoRestaurar);
}

// Elegir en esta PC la carpeta o el archivo a traer (tiene que estar dentro de tu carpeta personal).
// Si ya no existe acá (se borró), se escribe a mano.
void PaginaRespaldo::elegirRuta(bool carpeta)
{
    const QString inicio = QDir::home().filePath(editRuta->text().trimmed());
    const QString elegida = carpeta
        ? QFileDialog::getExistingDirectory(this, tr("Carpeta a restaurar"), inicio)
        : QFileDialog::getOpenFileName(this, tr("Archivo a restaurar"), inicio);
    if (elegida.isEmpty())
        return;
    const QString relativa = QDir::home().relativeFilePath(elegida);
    if (relativa.isEmpty() || relativa == u"." || relativa.startsWith(QStringLiteral("..")) || QDir::isAbsolutePath(relativa)) {
        QMessageBox::warning(this, windowTitle(), tr("Tiene que ser algo dentro de tu carpeta personal (%1).").arg(QDir::homePath()));
        return;
    }
    editRuta->setText(relativa);
}

// La contraseña escrita (o un aviso si falta)
bool PaginaRespaldo::tomarContrasena()
{
    contrasena = ui->editContrasena->text();
    if (contrasena.isEmpty()) {
        tema::mostrarEstado(ui->etiquetaEstado, tr("Escribí la contraseña SSH del servidor."));
        ui->editContrasena->setFocus();
        return false;
    }
    return true;
}

void PaginaRespaldo::buscarAnteriores()
{
    if (ocupada() || !tomarContrasena())
        return;
    // Se vuelven a llenar: queda solo «la copia actual»
    while (comboDesde->count() > 1)
        comboDesde->removeItem(1);
    iniciar(Operacion::Anteriores, {QStringLiteral("anteriores")});
}

void PaginaRespaldo::restaurarElegido()
{
    if (ocupada() || !tomarContrasena())
        return;
    QString ruta;
    if (radioSolo->isChecked()) {
        ruta = editRuta->text().trimmed();
        // Una ruta completa de esta PC se pasa a relativa a la carpeta personal
        if (QDir::isAbsolutePath(ruta))
            ruta = QDir::home().relativeFilePath(ruta);
        while (ruta.startsWith(QStringLiteral("./")))
            ruta.remove(0, 2);
        while (ruta.endsWith(u'/'))
            ruta.chop(1);
        if (ruta.isEmpty() || ruta == u"." || ruta.startsWith(QStringLiteral("..")) || ruta.contains(QStringLiteral("/../"))) {
            tema::mostrarEstado(ui->etiquetaEstado, tr("Escribí la carpeta o el archivo a traer (dentro de tu carpeta personal), o elegí «Todo»."),
                                tema::Estado::Error);
            editRuta->setFocus();
            return;
        }
    }
    const QString desde = comboDesde->currentData().toString();
    const QString queTraer = ruta.isEmpty() ? tr("todo tu respaldo") : tr("«%1»").arg(ruta);
    const QString deDonde = desde == u"actual" ? tr("la copia actual (el último respaldo)")
                                                : comboDesde->currentText();
    if (QMessageBox::warning(this, tr("Restaurar"),
            tr("Se va a traer %1 desde %2 a tu carpeta personal (%3).\n\n"
               "• No se borra nada de esta PC.\n"
               "• Los archivos que ya existan con el mismo nombre se reemplazan por los del servidor; "
               "la versión que tenías queda guardada en ~/.local/share/Arch-Linux-Manager/antes-de-restaurar.\n\n"
               "¿Continuar?").arg(queTraer, deDonde, QDir::homePath()),
            QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes)
        return;

    QStringList argumentos{QStringLiteral("restauracion"), QStringLiteral("--desde"), desde};
    if (!ruta.isEmpty())
        argumentos << QStringLiteral("--ruta") << ruta;
    iniciar(Operacion::Restauracion, argumentos);
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
        if (!tomarContrasena())
            return;
        // La restauración reemplaza archivos de tu carpeta personal: se confirma antes
        if (tipo == u"restauracion"
            && QMessageBox::question(this, windowTitle(),
                   tr("Los archivos de tu carpeta personal que también estén en el respaldo se "
                      "van a reemplazar por la versión del servidor (la que tenías queda guardada en "
                      "~/.local/share/Arch-Linux-Manager/antes-de-restaurar). No se borra nada. ¿Continuar?")) != QMessageBox::Yes)
            return;
    }
    QStringList argumentos{tipo};
    if (forzar)
        argumentos << QStringLiteral("--forzar");
    iniciar(tipo == u"restauracion" ? Operacion::Restauracion : Operacion::Respaldo, argumentos);
}

// Corre Respaldo.sh con esos argumentos y la contraseña por la entrada estándar
void PaginaRespaldo::iniciar(Operacion cual, const QStringList &argumentosScript)
{
    operacion = cual;
    // No queda escrita en la ventana. Buscar las copias anteriores es solo una consulta: ahí se
    // deja, así se puede restaurar enseguida sin volver a escribirla
    if (cual != Operacion::Anteriores)
        ui->editContrasena->clear();

    cancelado = false;
    encendidos.clear();
    mensajeFinal.clear();
    ui->registro->clear();
    ui->etiquetaArchivo->clear();
    ui->barraProgreso->setValue(0);
    ui->barraProgreso->show();
    tema::mostrarEstado(ui->etiquetaEstado, tr("Buscando el servidor..."));
    habilitarFormulario(false);

    // Un QProcess nuevo por respaldo; se borra solo al terminar
    proceso = new QProcess(this);
    connect(proceso, &QProcess::readyReadStandardOutput, this, &PaginaRespaldo::leerSalida);
    connect(proceso, &QProcess::finished, this, &PaginaRespaldo::terminoProceso);
    proceso->setProcessChannelMode(QProcess::MergedChannels);
    // Respaldo.sh, rsync y sshpass en su propio grupo: Cancelar los corta a todos juntos
    proceso->setChildProcessModifier([] { setpgid(0, 0); });

    proceso->start(QStringLiteral("bash"), QStringList{scriptRespaldo} + argumentosScript);

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
    tema::mostrarEstado(ui->etiquetaEstado, tr("Cancelando..."));
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
        tema::mostrarEstado(ui->etiquetaEstado, resto + QStringLiteral("..."));
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
    } else if (evento == u"ANTERIOR" && comboDesde) {
        // ANTERIOR AAAA-MM-DD_HH-MM n: una copia anterior (la más nueva arriba, debajo de la actual)
        const QString fecha = resto.section(u' ', 0, 0);
        const int archivos = resto.section(u' ', 1, 1).toInt();
        const QDateTime cuando = QDateTime::fromString(fecha, QStringLiteral("yyyy-MM-dd_HH-mm"));
        comboDesde->insertItem(1, tr("Copia anterior del %1 (%n archivo(s) que ese respaldo borró o cambió)", nullptr, archivos)
                                      .arg(cuando.isValid() ? QLocale().toString(cuando, QLocale::ShortFormat) : fecha),
                               fecha);
    } else if (evento == u"ANTERIORES" || evento == u"GUARDADOS") {
        // (los explica el AVISO que viene con cada uno)
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
        tema::mostrarEstado(ui->etiquetaEstado, tr("Respaldo cancelado."));
    } else if (cancelado || estado == QProcess::CrashExit) {
        tema::mostrarEstado(ui->etiquetaEstado, operacion == Operacion::Restauracion ? tr("Restauración cancelada.")
                                              : operacion == Operacion::Anteriores ? tr("Búsqueda cancelada.")
                                                                                    : tr("Respaldo cancelado."));
    } else if (codigo == 0) {
        ui->barraProgreso->setValue(100);
        tema::mostrarEstado(ui->etiquetaEstado, mensajeFinal, tema::Estado::Ok);
        if (operacion == Operacion::Anteriores) {
            ui->barraProgreso->hide();
            if (comboDesde->count() > 1)
                comboDesde->setCurrentIndex(1);     // la más nueva, para no tener que buscarla
        } else {
            emit respaldoTerminado();
        }
    } else if (codigo == 6) {
        ui->barraProgreso->hide();
        tema::mostrarEstado(ui->etiquetaEstado, mensajeFinal, tema::Estado::Error);
        QMessageBox::critical(this, windowTitle(), mensajeFinal);
    } else if (codigo == 3) {
        ui->barraProgreso->hide();
        tema::mostrarEstado(ui->etiquetaEstado, tr("Contraseña incorrecta, volvé a escribirla."), tema::Estado::Error);
        ui->editContrasena->setFocus();
    } else {
        const QString falla = operacion == Operacion::Restauracion ? tr("La restauración falló.")
                            : operacion == Operacion::Anteriores ? tr("No se pudieron buscar las copias anteriores.")
                                                                  : tr("El respaldo falló.");
        tema::mostrarEstado(ui->etiquetaEstado, (mensajeFinal.isEmpty() ? falla : mensajeFinal), tema::Estado::Error);
    }
    contrasena.clear();    // ya no hace falta en memoria
    cargarHistorial();
}
