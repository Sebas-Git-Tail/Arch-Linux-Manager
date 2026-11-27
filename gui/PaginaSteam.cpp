#include "PaginaSteam.h"
#include "Tema.h"
#include "ui_PaginaSteam.h"

#include <QDesktopServices>
#include <QDir>
#include <QMessageBox>
#include <QUrl>

PaginaSteam::PaginaSteam(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaSteam),
      script(QDir(logica).filePath(QStringLiteral("Steam-Proton.sh")))
{
    ui->setupUi(this);
    ui->barraProgreso->hide();

    connect(ui->botonInstalarUltima, &QPushButton::clicked, this, [this] { instalar(urlUltima); });
    connect(ui->botonInstalarUrl, &QPushButton::clicked, this, [this] { instalar(ui->editUrl->text().trimmed()); });
    connect(ui->editUrl, &QLineEdit::returnPressed, this, [this] { instalar(ui->editUrl->text().trimmed()); });
    connect(ui->botonVersiones, &QPushButton::clicked, this, [] {
        QDesktopServices::openUrl(QUrl(QStringLiteral("https://github.com/GloriousEggroll/proton-ge-custom/releases")));
    });
    connect(ui->botonCancelar, &QPushButton::clicked, &proceso, &ProcesoLogica::cancelar);
    connect(&proceso, &ProcesoLogica::evento, this, &PaginaSteam::procesarEvento);
    connect(&proceso, &ProcesoLogica::terminado, this, &PaginaSteam::terminoProceso);
}

PaginaSteam::~PaginaSteam()
{
    delete ui;
}

// La primera vez que se abre la página se consulta qué hay (no al abrir el programa,
// así no se llama a GitHub si no se usa)
void PaginaSteam::showEvent(QShowEvent *evento)
{
    QWidget::showEvent(evento);
    if (!consultado) {
        consultado = true;
        consultar();
    }
}

void PaginaSteam::habilitar(bool habilitado)
{
    ui->botonInstalarUltima->setEnabled(habilitado && !urlUltima.isEmpty());
    ui->grupoOtra->setEnabled(habilitado);
    ui->botonCancelar->setEnabled(!habilitado && paso == Paso::Instalar);
}

void PaginaSteam::consultar()
{
    instaladas.clear();
    ui->etiquetaInstalada->setText(tr("consultando…"));
    ui->etiquetaUltima->setText(tr("consultando…"));
    paso = Paso::Instaladas;
    habilitar(false);
    proceso.iniciar(script, {QStringLiteral("instaladas")});
}

void PaginaSteam::instalar(const QString &url, bool sinSuma)
{
    if (url.isEmpty() || proceso.ocupado())
        return;
    // Una URL de otra arquitectura no le sirve a Steam: se avisa antes (una sola vez)
    if (!sinSuma && !arquitectura.isEmpty() && !url.endsWith(QStringLiteral("-%1.tar.gz").arg(arquitectura))
        && QMessageBox::warning(this, windowTitle(),
               tr("Esa URL no es para %1 (la arquitectura de esta computadora) y Steam no va a poder "
                  "usarla. ¿Continuar igual?").arg(arquitectura),
               QMessageBox::Yes | QMessageBox::No) != QMessageBox::Yes)
        return;

    mensajeFinal.clear();
    ui->registro->clear();
    ui->barraProgreso->setValue(0);
    ui->barraProgreso->show();
    paso = Paso::Instalar;
    urlInstalando = url;
    habilitar(false);
    QStringList argumentos{QStringLiteral("instalar"), url};
    if (sinSuma)
        argumentos << QStringLiteral("--sin-suma");
    proceso.iniciar(script, argumentos);
}

void PaginaSteam::procesarEvento(const QString &palabra, const QString &resto)
{
    if (palabra == u"ARQUITECTURA") {
        arquitectura = resto;
    } else if (palabra == u"INSTALADA") {
        instaladas << resto;
    } else if (palabra == u"ULTIMA") {
        // ULTIMA versión url
        const qsizetype espacio = resto.indexOf(u' ');
        const QString version = resto.left(espacio);
        urlUltima = resto.mid(espacio + 1);
        const bool alDia = instaladas.contains(version);
        ui->etiquetaUltima->setText(alDia ? tr("%1 (ya está instalada ✓)").arg(version) : version);
    } else if (palabra == u"ETAPA") {
        tema::mostrarEstado(ui->etiquetaEstado, resto + QStringLiteral("…"));
    } else if (palabra == u"PROGRESO") {
        ui->barraProgreso->setValue(resto.toInt());
    } else if (palabra == u"LISTO" || palabra == u"ERROR") {
        mensajeFinal = resto;
        if (palabra == u"ERROR")
            ui->registro->appendPlainText(QStringLiteral("✗ ") + resto);
    } else {
        ui->registro->appendPlainText(palabra == u"AVISO" ? resto : palabra + u' ' + resto);
    }
}

void PaginaSteam::terminoProceso(int codigo, bool cancelado)
{
    const Paso terminado = paso;
    paso = Paso::Nada;

    switch (terminado) {
    case Paso::Instaladas:
        ui->etiquetaInstalada->setText(instaladas.isEmpty() ? tr("ninguna") : instaladas.join(QStringLiteral(", ")));
        // Después de ver lo instalado se pregunta la última versión
        paso = Paso::Ultima;
        proceso.iniciar(script, {QStringLiteral("ultima")});
        return;
    case Paso::Ultima:
        if (codigo != 0) {
            urlUltima.clear();
            ui->etiquetaUltima->setText(tr("no se pudo consultar (¿sin conexión?)"));
        }
        break;
    case Paso::Instalar:
        if (cancelado) {
            tema::mostrarEstado(ui->etiquetaEstado, tr("Instalación cancelada."));
        } else if (codigo == 3) {
            // La versión no publica suma SHA-512: no se instaló nada. Solo con un sí explícito
            // se instala igual (sin poder comprobar que la descarga esté bien)
            tema::mostrarEstado(ui->etiquetaEstado, mensajeFinal, tema::Estado::Error);
            habilitar(true);
            if (QMessageBox::warning(this, windowTitle(),
                    tr("Esta versión de GE-Proton no publica su suma SHA-512, así que no hay forma de comprobar "
                       "que la descarga esté completa y sea la que publicó GE-Proton.\n\n"
                       "Lo más seguro es elegir otra versión (botón «Ver versiones»). ¿Instalarla igual, sin verificar?"),
                    QMessageBox::Yes | QMessageBox::No, QMessageBox::No) == QMessageBox::Yes)
                instalar(urlInstalando, true);
            return;
        } else if (codigo == 0) {
            ui->barraProgreso->setValue(100);
            tema::mostrarEstado(ui->etiquetaEstado, tr("%1 instalado. Recordá elegirlo en los ajustes de compatibilidad de Steam.")
                                            .arg(mensajeFinal), tema::Estado::Ok);
            habilitar(true);
            consultar();    // para que se vea la versión nueva
            return;
        } else {
            tema::mostrarEstado(ui->etiquetaEstado, (mensajeFinal.isEmpty() ? tr("No se pudo instalar.") : mensajeFinal), tema::Estado::Error);
        }
        break;
    case Paso::Nada:
        break;
    }
    habilitar(true);
}
