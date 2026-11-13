#include "PaginaTutoriales.h"
#include "ui_PaginaTutoriales.h"

#include <QDir>
#include <QMessageBox>

constexpr int RolUrl = Qt::UserRole;

PaginaTutoriales::PaginaTutoriales(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaTutoriales),
      script(QDir(logica).filePath(QStringLiteral("Tutoriales.sh")))
{
    ui->setupUi(this);

    connect(ui->botonActualizar, &QPushButton::clicked, this, &PaginaTutoriales::listar);
    connect(ui->botonVer, &QPushButton::clicked, this, &PaginaTutoriales::ver);
    connect(ui->listaVideos, &QListWidget::itemDoubleClicked, this, &PaginaTutoriales::ver);
    connect(ui->listaVideos, &QListWidget::currentItemChanged, this,
            [this](QListWidgetItem *item) { ui->botonVer->setEnabled(item); });

    connect(&proceso, &ProcesoLogica::evento, this, [this](const QString &palabra, const QString &resto) {
        if (palabra == u"VIDEO") {
            // VIDEO nombre url (la url es lo último; el nombre puede tener espacios)
            const qsizetype espacio = resto.lastIndexOf(u' ');
            auto *item = new QListWidgetItem(QIcon::fromTheme(QStringLiteral("video-x-generic")),
                                             resto.left(espacio), ui->listaVideos);
            item->setData(RolUrl, resto.mid(espacio + 1));
        } else if (palabra == u"ERROR") {
            error = resto;
        }
    });
    connect(&proceso, &ProcesoLogica::terminado, this, [this](int codigo, bool) {
        ui->botonActualizar->setEnabled(true);
        if (codigo == 0) {
            ui->etiquetaEstado->setText(ui->listaVideos->count() == 1 ? tr("1 video.")
                                                                      : tr("%1 videos.").arg(ui->listaVideos->count()));
            ui->listaVideos->setCurrentRow(0);
        } else {
            ui->etiquetaEstado->setText(QStringLiteral("✗ ") + (error.isEmpty() ? tr("No se pudo listar los videos.") : error));
        }
    });
}

PaginaTutoriales::~PaginaTutoriales()
{
    delete ui;
}

// La primera vez que se abre la página se pide la lista al servidor
void PaginaTutoriales::showEvent(QShowEvent *evento)
{
    QWidget::showEvent(evento);
    if (!listado) {
        listado = true;
        listar();
    }
}

void PaginaTutoriales::listar()
{
    if (proceso.ocupado())
        return;
    error.clear();
    ui->listaVideos->clear();
    ui->botonActualizar->setEnabled(false);
    ui->etiquetaEstado->setText(tr("Buscando videos en el servidor…"));
    proceso.iniciar(script, {});
}

void PaginaTutoriales::ver()
{
    const QListWidgetItem *item = ui->listaVideos->currentItem();
    if (!item)
        return;
    if (QProcess::startDetached(QStringLiteral("mpv"), {item->data(RolUrl).toString()}))
        ui->etiquetaEstado->setText(tr("Abriendo %1 en mpv…").arg(item->text()));
    else
        QMessageBox::warning(this, windowTitle(), tr("No se pudo abrir mpv."));
}
