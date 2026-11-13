#include "PaginaNotificacion.h"
#include "ui_PaginaNotificacion.h"

#include <QDir>

PaginaNotificacion::PaginaNotificacion(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaNotificacion),
      script(QDir(logica).filePath(QStringLiteral("Notificacion.sh")))
{
    ui->setupUi(this);

    connect(ui->botonEnviar, &QPushButton::clicked, this, &PaginaNotificacion::enviar);
    connect(&proceso, &ProcesoLogica::evento, this, [this](const QString &palabra, const QString &resto) {
        if (palabra == u"LISTO" || palabra == u"ERROR")
            mensajeFinal = resto;
    });
    connect(&proceso, &ProcesoLogica::terminado, this, [this](int codigo, bool) {
        ui->botonEnviar->setEnabled(true);
        if (codigo == 0) {
            ui->etiquetaEstado->setText(QStringLiteral("✓ ") + mensajeFinal);
            ui->editMensaje->clear();
        } else {
            ui->etiquetaEstado->setText(QStringLiteral("✗ ") + (mensajeFinal.isEmpty() ? tr("No se pudo enviar.") : mensajeFinal));
        }
    });
}

PaginaNotificacion::~PaginaNotificacion()
{
    delete ui;
}

void PaginaNotificacion::enviar()
{
    const QString mensaje = ui->editMensaje->toPlainText().trimmed();
    if (mensaje.isEmpty()) {
        ui->etiquetaEstado->setText(tr("No se escribió ningún mensaje."));
        return;
    }
    mensajeFinal.clear();
    ui->botonEnviar->setEnabled(false);
    ui->etiquetaEstado->setText(tr("Enviando…"));
    proceso.iniciar(script, {}, mensaje.left(1000).toUtf8());
}
