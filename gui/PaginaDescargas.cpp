#include "PaginaDescargas.h"

#include <algorithm>
#include "ui_PaginaDescargas.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QMessageBox>
#include <QStandardPaths>
#include <QUrl>

#include <csignal>
#include <unistd.h>

// Rol de cada fila de la lista donde se guarda la ruta del archivo
constexpr int RolRuta = Qt::UserRole;

PaginaDescargas::PaginaDescargas(Tipo tipo, const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaDescargas), tipo(tipo),
      scriptDescargar(QDir(logica).filePath(tipo == Tipo::Archivos ? QStringLiteral("Descargas-en-masa.sh")
                                                                   : QStringLiteral("Descargar.sh")))
{
    ui->setupUi(this);
    const bool musica = tipo == Tipo::Musica;

    // Lo que cambia entre los dos modos (lo demás es igual)
    if (musica) {
        setWindowTitle(tr("Descargar Música"));
        ui->grupoUrls->setTitle(tr("URLs de YouTube Music (una por línea)"));
        ui->editUrls->setPlaceholderText(QStringLiteral("https://music.youtube.com/watch?v=..."));
        ui->grupoDescargados->setTitle(tr("Canciones (en Música, una carpeta por artista)"));
        ui->listaVideos->setIconSize(QSize(54, 54));    // las carátulas son cuadradas
        ui->botonVer->setText(tr("Reproducir"));
    } else if (tipo == Tipo::Archivos) {
        setWindowTitle(tr("Descargas en masa"));
        ui->grupoUrls->setTitle(tr("URLs de los archivos (una por línea)"));
        ui->editUrls->setPlaceholderText(QStringLiteral("https://..."));
        ui->listaVideos->setIconSize(QSize(16, 16));
        ui->botonVer->setText(tr("Abrir"));
    } else {
        setWindowTitle(tr("Descargar Vídeos"));
    }
    const bool videos = tipo == Tipo::Videos;
    ui->etiquetaPlataforma->setVisible(videos);
    ui->comboPlataforma->setVisible(videos);
    ui->checkPlaylist->setVisible(musica);
    ui->checkPistas->setVisible(videos);
    ui->botonYoutubeMusic->setVisible(musica);
    ui->checkCookies->setVisible(tipo != Tipo::Archivos);

    // Carpeta elegible: redes sociales (YouTube va siempre a Vídeos/Yt-dlp) y archivos
    ui->editCarpeta->setText(QStandardPaths::writableLocation(
        tipo == Tipo::Archivos ? QStandardPaths::DownloadLocation : QStandardPaths::MoviesLocation));
    cambiarPlataforma(ui->comboPlataforma->currentIndex());

    // Las barras aparecen recién cuando empieza una descarga
    ui->barraArchivo->hide();
    ui->barraTotal->hide();

    connect(ui->comboPlataforma, &QComboBox::currentIndexChanged, this, &PaginaDescargas::cambiarPlataforma);
    connect(ui->botonElegirCarpeta, &QPushButton::clicked, this, &PaginaDescargas::elegirCarpeta);
    connect(ui->botonYoutubeMusic, &QPushButton::clicked, this,
            [] { QDesktopServices::openUrl(QUrl(QStringLiteral("https://music.youtube.com"))); });
    connect(ui->botonDescargar, &QPushButton::clicked, this, &PaginaDescargas::descargar);
    connect(ui->botonCancelar, &QPushButton::clicked, this, &PaginaDescargas::cancelar);
    connect(ui->listaVideos, &QListWidget::itemSelectionChanged, this, &PaginaDescargas::actualizarAcciones);
    connect(ui->listaVideos, &QListWidget::itemDoubleClicked, this, &PaginaDescargas::reproducir);
    connect(ui->botonVer, &QPushButton::clicked, this, &PaginaDescargas::reproducir);
    connect(ui->botonAbrirCarpeta, &QPushButton::clicked, this, &PaginaDescargas::abrirCarpeta);
    connect(ui->botonPapelera, &QPushButton::clicked, this, &PaginaDescargas::moverAPapelera);

    connect(&proceso, &QProcess::readyReadStandardOutput, this, &PaginaDescargas::leerSalida);
    connect(&proceso, &QProcess::readyReadStandardError, this, &PaginaDescargas::leerErrores);
    connect(&proceso, &QProcess::finished, this, &PaginaDescargas::terminoProceso);

    // Descargar.sh y yt-dlp en su propio grupo de procesos: así Cancelar los corta a
    // todos juntos (si no, yt-dlp seguiría bajando aunque se cierre bash)
    proceso.setChildProcessModifier([] { setpgid(0, 0); });

    if (!QFileInfo(scriptDescargar).isFile())
        anotar(tr("No se encontró %1").arg(scriptDescargar));
}

PaginaDescargas::~PaginaDescargas()
{
    delete ui;
}

bool PaginaDescargas::ocupada() const
{
    return proceso.state() != QProcess::NotRunning;
}

// Corta la descarga (bash y yt-dlp) y espera hasta 3 segundos a que termine
void PaginaDescargas::cancelarYEsperar()
{
    cancelar();
    proceso.waitForFinished(3000);
}

// Música va a la carpeta Música; YouTube a Vídeos/Yt-dlp; redes sociales a la elegida
QString PaginaDescargas::destino() const
{
    if (tipo == Tipo::Musica)
        return QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (tipo == Tipo::Archivos)
        return ui->editCarpeta->text().trimmed();
    if (ui->comboPlataforma->currentIndex() == 0)
        return QDir(QStandardPaths::writableLocation(QStandardPaths::MoviesLocation)).filePath(QStringLiteral("Yt-dlp"));
    return ui->editCarpeta->text().trimmed();
}

void PaginaDescargas::cambiarPlataforma(int indice)
{
    ui->filaCarpeta->setVisible(tipo == Tipo::Archivos || (tipo == Tipo::Videos && indice == 1));    // 1 = Redes sociales
}

void PaginaDescargas::elegirCarpeta()
{
    const QString carpeta = QFileDialog::getExistingDirectory(this, tr("Guardar en"), ui->editCarpeta->text());
    if (!carpeta.isEmpty())
        ui->editCarpeta->setText(carpeta);
}

void PaginaDescargas::habilitarFormulario(bool habilitado)
{
    ui->grupoUrls->setEnabled(habilitado);
    ui->comboPlataforma->setEnabled(habilitado);
    ui->checkPlaylist->setEnabled(habilitado);
    ui->checkPistas->setEnabled(habilitado);
    ui->checkCookies->setEnabled(habilitado);
    ui->filaCarpeta->setEnabled(habilitado);
    ui->botonDescargar->setEnabled(habilitado);
    ui->botonCancelar->setEnabled(!habilitado);
}

void PaginaDescargas::anotar(const QString &texto)
{
    ui->registro->appendPlainText(texto);
}

void PaginaDescargas::descargar()
{
    // Se quitan espacios y líneas vacías (lo mismo que hacía Pedir_URLs.sh)
    QStringList urls;
    for (const QString &linea : ui->editUrls->toPlainText().split(u'\n')) {
        if (!linea.trimmed().isEmpty())
            urls << linea.trimmed();
    }
    if (urls.isEmpty()) {
        ui->etiquetaEstado->setText(tr("No se ingresó ninguna URL."));
        return;
    }

    const QString carpeta = destino();
    if (carpeta.isEmpty()) {
        ui->etiquetaEstado->setText(tr("Elegí una carpeta de destino."));
        return;
    }

    urlsEnCurso = urls;
    carpetaEnCurso = carpeta;
    cancelado = false;
    habilitarFormulario(false);

    // En Vídeos, si se pidió, antes de descargar se averigua qué calidades, códecs,
    // subtítulos y pistas de audio ofrece el video para elegirlos
    if (tipo == Tipo::Videos && ui->checkPistas->isChecked())
        buscarPistas();
    else
        iniciarDescarga({});
}

// Paso previo de «Elegir calidad, audio y subtítulos»: Descargar.sh --pistas informa qué
// ofrece cada URL (eventos AUDIO, SUBTITULO, VIDEO y ACODEC). Al terminar, terminoPistas() abre el diálogo.
void PaginaDescargas::buscarPistas()
{
    QStringList argumentos{scriptDescargar, QStringLiteral("--pistas")};
    if (ui->checkCookies->isChecked())
        argumentos << QStringLiteral("--cookies");
    argumentos << QStringLiteral("--") << urlsEnCurso;

    buscandoPistas = true;
    fallidas = 0;
    audiosOfrecidos.clear();
    subtitulosOfrecidos.clear();
    formatosOfrecidos.clear();
    codecsAudioOfrecidos.clear();
    ui->barraArchivo->hide();
    ui->barraTotal->setRange(0, urlsEnCurso.size());
    ui->barraTotal->setValue(0);
    ui->barraTotal->show();
    ui->etiquetaEstado->setText(tr("Buscando calidades, subtítulos y pistas de audio…"));

    proceso.start(QStringLiteral("bash"), argumentos);
}

// Con lo que encontró --pistas se abre el diálogo y, si se acepta, se descarga con lo elegido
void PaginaDescargas::terminoPistas(int codigo, QProcess::ExitStatus estado)
{
    buscandoPistas = false;
    if (cancelado) {
        terminar(tr("Descarga cancelada."));
    } else if (estado == QProcess::CrashExit || codigo == 2 || fallidas == urlsEnCurso.size()) {
        // Si no se pudo consultar ninguna URL, tampoco se van a poder descargar
        terminar(tr("No se pudo descargar (ver los avisos abajo)."));
    } else if (audiosOfrecidos.size() < 2 && subtitulosOfrecidos.isEmpty() && formatosOfrecidos.isEmpty()) {
        anotar(tr("No hay calidades, subtítulos ni otras pistas de audio para elegir: se descarga como siempre."));
        iniciarDescarga({});
    } else {
        ui->barraTotal->setValue(ui->barraTotal->maximum());
        ui->etiquetaEstado->setText(tr("Elegí la calidad, los códecs y qué subtítulos y pistas de audio incluir."));
        DialogoPistas dialogo(audiosOfrecidos.values(), subtitulosOfrecidos.values(), formatosOfrecidos,
                              codecsAudioOfrecidos, this);
        if (dialogo.abrir() == QDialog::Accepted)
            iniciarDescarga(dialogo.eleccion());
        else
            terminar(tr("Descarga cancelada."));
    }
}

// Deja la página lista para otra descarga cuando no se llegó a descargar nada
void PaginaDescargas::terminar(const QString &estado)
{
    habilitarFormulario(true);
    ui->barraArchivo->hide();
    ui->barraTotal->hide();
    ui->etiquetaEstado->setText(estado);
}

// eleccion: lo elegido en el diálogo (vacío = descarga de siempre, en MKV)
void PaginaDescargas::iniciarDescarga(const Eleccion &eleccion)
{
    QStringList argumentos{scriptDescargar, QStringLiteral("--destino"), carpetaEnCurso};
    if (tipo != Tipo::Archivos)
        argumentos << QStringLiteral("--miniaturas") << miniaturas.path();
    if (tipo == Tipo::Musica) {
        argumentos << QStringLiteral("--audio");
        if (!ui->checkPlaylist->isChecked())
            argumentos << QStringLiteral("--sin-playlist");
    }
    if (ui->checkCookies->isChecked())
        argumentos << QStringLiteral("--cookies");
    if (!eleccion.audios.isEmpty())
        argumentos << QStringLiteral("--audios") << eleccion.audios.join(u',');
    if (!eleccion.subtitulos.isEmpty())
        argumentos << QStringLiteral("--subtitulos") << eleccion.subtitulos.join(u',');
    if (eleccion.calidad > 0)
        argumentos << QStringLiteral("--calidad") << QString::number(eleccion.calidad);
    if (!eleccion.vcodec.isEmpty())
        argumentos << QStringLiteral("--vcodec") << eleccion.vcodec;
    if (!eleccion.acodec.isEmpty())
        argumentos << QStringLiteral("--acodec") << eleccion.acodec;
    argumentos << QStringLiteral("--") << urlsEnCurso;

    fallidas = listas = 0;
    archivoActual.clear();
    miniaturaPendiente.clear();
    ui->barraArchivo->setValue(0);
    ui->barraTotal->setRange(0, urlsEnCurso.size());
    ui->barraTotal->setValue(0);
    ui->barraArchivo->show();
    ui->barraTotal->show();
    ui->etiquetaEstado->setText(tr("Preparando descarga..."));

    proceso.start(QStringLiteral("bash"), argumentos);
}

void PaginaDescargas::cancelar()
{
    if (proceso.state() == QProcess::NotRunning)
        return;
    cancelado = true;
    ::kill(-static_cast<pid_t>(proceso.processId()), SIGTERM);    // todo el grupo
    ui->etiquetaEstado->setText(tr("Cancelando..."));
}

void PaginaDescargas::leerSalida()
{
    while (proceso.canReadLine())
        procesarEvento(QString::fromUtf8(proceso.readLine()).trimmed());
}

void PaginaDescargas::leerErrores()
{
    const QString texto = QString::fromUtf8(proceso.readAllStandardError()).trimmed();
    if (!texto.isEmpty())
        anotar(texto);
}

// Un evento de Descargar.sh: PALABRA y el resto de la línea
void PaginaDescargas::procesarEvento(const QString &linea)
{
    const qsizetype espacio = linea.indexOf(u' ');
    const QString evento = linea.left(espacio);
    const QString resto = espacio < 0 ? QString() : linea.mid(espacio + 1);

    if (evento == u"INICIO") {
        // INICIO n total url
        const QStringList partes = resto.split(u' ');
        const int n = partes.value(0).toInt();
        ui->barraTotal->setValue(n - 1);
        ui->barraArchivo->setValue(0);
        ui->etiquetaEstado->setText(buscandoPistas
                ? tr("Buscando calidades, subtítulos y pistas de audio (URL %1 de %2)…").arg(n).arg(partes.value(1))
                : tr("URL %1 de %2: %3").arg(n).arg(partes.value(1), partes.value(2)));
    } else if (evento == u"AUDIO") {
        // AUDIO idioma ORIGINAL|OTRA
        const QString idioma = resto.section(u' ', 0, 0);
        PistaAudio &pista = audiosOfrecidos[idioma];
        pista.idioma = idioma;
        pista.original = pista.original || resto.section(u' ', 1, 1) == u"ORIGINAL";
    } else if (evento == u"SUBTITULO") {
        // SUBTITULO idioma MANUAL|AUTO nombre. Si una URL lo tiene manual y otra
        // automático, se muestra como manual (es el que usa yt-dlp cuando hay de los dos)
        const QString idioma = resto.section(u' ', 0, 0);
        const bool automatico = resto.section(u' ', 1, 1) == u"AUTO";
        const auto existente = subtitulosOfrecidos.constFind(idioma);
        if (existente == subtitulosOfrecidos.cend() || (existente->automatico && !automatico))
            subtitulosOfrecidos.insert(idioma, Subtitulo{idioma, automatico, resto.section(u' ', 2)});
    } else if (evento == u"VIDEO") {
        // VIDEO alto familia
        const FormatoVideo formato{resto.section(u' ', 0, 0).toInt(), resto.section(u' ', 1, 1)};
        const bool repetido = std::any_of(formatosOfrecidos.cbegin(), formatosOfrecidos.cend(), [&](const FormatoVideo &f) {
            return f.alto == formato.alto && f.familia == formato.familia;
        });
        if (formato.alto > 0 && !formato.familia.isEmpty() && !repetido)
            formatosOfrecidos << formato;
    } else if (evento == u"ACODEC") {
        if (!resto.isEmpty() && !codecsAudioOfrecidos.contains(resto))
            codecsAudioOfrecidos << resto;
    } else if (evento == u"ARCHIVO") {
        archivoActual = resto;
        ui->barraArchivo->setValue(0);
        ui->etiquetaEstado->setText(tr("Descargando %1").arg(archivoActual));
    } else if (evento == u"PROGRESO") {
        ui->barraArchivo->setValue(resto.toInt());
        if (resto.toInt() >= 100)
            ui->etiquetaEstado->setText(tr("Procesando %1 (metadatos y carátula)...").arg(archivoActual));
    } else if (evento == u"MINIATURA") {
        miniaturaPendiente = resto;
    } else if (evento == u"LISTO") {
        QFileInfo info(resto);
        // En Música se ve también el artista (la carpeta), como en «artista/título»
        const QString nombre = tipo == Tipo::Musica ? info.dir().dirName() + QStringLiteral(" — ") + info.completeBaseName()
                             : tipo == Tipo::Archivos ? info.fileName()
                                                      : info.completeBaseName();
        const QIcon icono = tipo == Tipo::Archivos ? QIcon::fromTheme(QStringLiteral("document-save"))
                                                   : QIcon(miniaturaPendiente);
        auto *item = new QListWidgetItem(icono, nombre, ui->listaVideos);
        item->setData(RolRuta, resto);
        item->setToolTip(resto);
        // Queda seleccionado el último, así los botones ya sirven sin tocar la lista
        ui->listaVideos->clearSelection();
        ui->listaVideos->setCurrentItem(item);
        item->setSelected(true);
        ++listas;
        ui->barraTotal->setValue(ui->barraTotal->value() + 1);
    } else if (evento == u"FALLO") {
        ++fallidas;
        anotar(tr("✗ Falló: %1").arg(resto));
        // Las mismas pistas que daba Musica.sh
        if (tipo == Tipo::Musica) {
            anotar(ui->checkCookies->isChecked()
                       ? tr("   Probablemente no estás usando un navegador válido o no iniciaste sesión con tu cuenta de Google en YouTube Music.")
                       : tr("   Probablemente se deba a la falta de cookies (probá con «Usar cookies del navegador»)."));
        }
        ui->barraTotal->setValue(ui->barraTotal->value() + 1);
    } else if (evento == u"AVISO") {
        anotar(resto);
    } else if (evento == u"ERROR") {
        QMessageBox::critical(this, windowTitle(), resto);
    }
}

void PaginaDescargas::terminoProceso(int codigo, QProcess::ExitStatus estado)
{
    leerSalida();
    // Si lo que terminó es el paso previo (--pistas), falta elegir y descargar
    if (buscandoPistas) {
        terminoPistas(codigo, estado);
        return;
    }
    habilitarFormulario(true);
    ui->barraTotal->setValue(ui->barraTotal->maximum());

    const bool musica = tipo == Tipo::Musica;
    if (cancelado) {
        ui->etiquetaEstado->setText(tr("Descarga cancelada."));
    } else if (estado == QProcess::CrashExit || codigo == 2) {
        ui->etiquetaEstado->setText(tr("No se pudo descargar (ver los avisos abajo)."));
    } else if (fallidas == 0) {
        if (tipo == Tipo::Archivos)
            ui->etiquetaEstado->setText(tr("Descargas completadas en %1.").arg(destino()));
        else if (listas == 1)
            ui->etiquetaEstado->setText(musica ? tr("Listo: 1 canción descargada.") : tr("Listo: 1 video descargado."));
        else
            ui->etiquetaEstado->setText((musica ? tr("Listo: %1 canciones descargadas.") : tr("Listo: %1 videos descargados."))
                                            .arg(listas));
    } else {
        ui->etiquetaEstado->setText(tr("Terminado con errores: %1 descargado(s), %2 URL(s) fallaron.")
                                        .arg(listas).arg(fallidas));
    }
}

void PaginaDescargas::actualizarAcciones()
{
    const bool hay = !ui->listaVideos->selectedItems().isEmpty();
    ui->botonVer->setEnabled(hay);
    ui->botonAbrirCarpeta->setEnabled(hay);
    ui->botonPapelera->setEnabled(hay);
}

// Reemplaza el «¿ver y luego borrarlo?» de antes: reproducir y borrar son botones separados.
// mpv reproduce tanto videos como canciones (las elegidas, en orden, como lista).
void PaginaDescargas::reproducir()
{
    QStringList rutas;
    for (const QListWidgetItem *item : ui->listaVideos->selectedItems())
        rutas << item->data(RolRuta).toString();
    // Archivos: se abren con el programa que tenga asignado KDE
    if (tipo == Tipo::Archivos) {
        for (const QString &ruta : std::as_const(rutas))
            QDesktopServices::openUrl(QUrl::fromLocalFile(ruta));
        return;
    }
    if (!rutas.isEmpty() && !QProcess::startDetached(QStringLiteral("mpv"), rutas))
        QMessageBox::warning(this, windowTitle(), tr("No se pudo abrir mpv."));
}

void PaginaDescargas::abrirCarpeta()
{
    if (const QListWidgetItem *item = ui->listaVideos->currentItem())
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(item->data(RolRuta).toString()).absolutePath()));
}

// A la papelera y no borrado definitivo: si fue un error, se puede recuperar
void PaginaDescargas::moverAPapelera()
{
    const QList<QListWidgetItem *> elegidos = ui->listaVideos->selectedItems();
    if (elegidos.isEmpty()
        || QMessageBox::question(this, windowTitle(),
               tr("¿Mover %n archivo(s) a la papelera?", nullptr, elegidos.size())) != QMessageBox::Yes)
        return;

    for (QListWidgetItem *item : elegidos) {
        QFile archivo(item->data(RolRuta).toString());
        if (archivo.moveToTrash() || !archivo.exists())
            delete item;
        else
            anotar(tr("No se pudo mover a la papelera: %1").arg(archivo.fileName()));
    }
}
