#include "PaginaMinecraft.h"
#include "ui_PaginaMinecraft.h"

#include <QDir>
#include <QMessageBox>
#include <QTimer>

// Roles de cada fila de la lista de servidores
constexpr int RolNombre = Qt::UserRole;          // «Paper 26.2/SMP-1»
constexpr int RolEncendido = Qt::UserRole + 1;

PaginaMinecraft::PaginaMinecraft(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaMinecraft),
      script(QDir(logica).filePath(QStringLiteral("Minecraft.sh")))
{
    ui->setupUi(this);
    ui->barraProgreso->hide();

    connect(ui->listaServidores, &QListWidget::currentItemChanged, this, &PaginaMinecraft::actualizarBotones);
    connect(ui->listaServidores, &QListWidget::itemChanged, this, [this](QListWidgetItem *item) {
        const QString nombre = item->data(RolNombre).toString();
        if (item->checkState() == Qt::Checked)
            marcados.insert(nombre);
        else
            marcados.remove(nombre);
    });
    connect(ui->botonIniciar, &QPushButton::clicked, this, &PaginaMinecraft::iniciar);
    connect(ui->botonReiniciar, &QPushButton::clicked, this, &PaginaMinecraft::reiniciar);
    connect(ui->botonActualizarLista, &QPushButton::clicked, this, &PaginaMinecraft::consultar);
    connect(ui->botonPaper, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPaper);
    connect(ui->botonPlugin, &QPushButton::clicked, this, &PaginaMinecraft::instalarPlugin);
    connect(ui->botonJugar, &QPushButton::clicked, this, &PaginaMinecraft::jugar);

    connect(&consulta, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoConsulta);
    connect(&consulta, &ProcesoLogica::terminado, this, &PaginaMinecraft::terminoConsulta);
    connect(&accion, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoAccion);
    connect(&accion, &ProcesoLogica::terminado, this, &PaginaMinecraft::terminoAccion);
}

PaginaMinecraft::~PaginaMinecraft()
{
    delete ui;
}

// Cada vez que se abre la página se actualiza la lista (un servidor pudo prenderse o apagarse)
void PaginaMinecraft::showEvent(QShowEvent *evento)
{
    QWidget::showEvent(evento);
    consultar();
}

void PaginaMinecraft::consultar()
{
    if (consulta.ocupado())
        return;
    const QSignalBlocker bloqueo(ui->listaServidores);
    ui->listaServidores->clear();
    paso = Paso::Servidores;
    consulta.iniciar(script, {QStringLiteral("servidores")});
}

void PaginaMinecraft::eventoConsulta(const QString &palabra, const QString &resto)
{
    if (palabra == u"SERVIDOR") {
        // SERVIDOR ENCENDIDO|APAGADO nombre
        const qsizetype espacio = resto.indexOf(u' ');
        const bool encendido = resto.left(espacio) == u"ENCENDIDO";
        const QString nombre = resto.mid(espacio + 1);
        // Como antes en Plugins.sh: la primera vez quedan marcados los SMP-1
        if (primeraVez && nombre.endsWith(QStringLiteral("/SMP-1")))
            marcados.insert(nombre);

        const QSignalBlocker bloqueo(ui->listaServidores);
        auto *item = new QListWidgetItem(
            (encendido ? QStringLiteral("🟢  ") : QStringLiteral("⚫  ")) + nombre
                + (encendido ? tr("  (encendido)") : QString()),
            ui->listaServidores);
        item->setData(RolNombre, nombre);
        item->setData(RolEncendido, encendido);
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(marcados.contains(nombre) ? Qt::Checked : Qt::Unchecked);
    } else if (palabra == u"VERSION") {
        ui->comboVersion->addItem(resto);
    } else if (palabra == u"INSTANCIA") {
        ui->comboInstancia->addItem(resto);
    }
}

// Las consultas van en cadena: servidores → versiones → instancias (las dos últimas solo
// la primera vez, no cambian mientras el programa está abierto)
void PaginaMinecraft::terminoConsulta()
{
    if (paso == Paso::Servidores && primeraVez) {
        paso = Paso::Versiones;
        consulta.iniciar(script, {QStringLiteral("versiones")});
        return;
    }
    if (paso == Paso::Versiones) {
        paso = Paso::Instancias;
        consulta.iniciar(script, {QStringLiteral("instancias")});
        return;
    }
    primeraVez = false;
    actualizarBotones();
}

QString PaginaMinecraft::servidorElegido(bool *encendido) const
{
    const QListWidgetItem *item = ui->listaServidores->currentItem();
    if (encendido)
        *encendido = item && item->data(RolEncendido).toBool();
    return item ? item->data(RolNombre).toString() : QString();
}

void PaginaMinecraft::actualizarBotones()
{
    bool encendido = false;
    const bool hay = !servidorElegido(&encendido).isEmpty();
    const bool libre = !accion.ocupado();
    ui->botonIniciar->setEnabled(libre && hay && !encendido);
    ui->botonReiniciar->setEnabled(libre && hay && encendido);
    ui->grupoPaper->setEnabled(libre && ui->comboVersion->count() > 0);
    ui->grupoPlugin->setEnabled(libre);
    ui->grupoPrism->setEnabled(libre && ui->comboInstancia->count() > 0);
}

void PaginaMinecraft::ejecutar(const QStringList &argumentos, const QString &estado)
{
    mensajeFinal.clear();
    ui->etiquetaEstado->setText(estado);
    ui->barraProgreso->setRange(0, 0);    // sin porcentaje: barra «ocupada»
    ui->barraProgreso->show();
    accion.iniciar(script, argumentos);
    actualizarBotones();
}

void PaginaMinecraft::iniciar()
{
    ejecutar({QStringLiteral("iniciar"), servidorElegido()}, tr("Iniciando %1…").arg(servidorElegido()));
}

void PaginaMinecraft::reiniciar()
{
    const QString servidor = servidorElegido();
    if (QMessageBox::question(this, windowTitle(),
            tr("Se va a detener %1 guardando los mundos (los jugadores se desconectan) y se va a "
               "volver a abrir. ¿Continuar?").arg(servidor)) != QMessageBox::Yes)
        return;
    ejecutar({QStringLiteral("reiniciar"), servidor}, tr("Reiniciando %1…").arg(servidor));
}

void PaginaMinecraft::actualizarPaper()
{
    const QString version = ui->comboVersion->currentText();
    const QString url = ui->editUrlPaper->text().trimmed();
    if (url.isEmpty()) {
        ui->etiquetaEstado->setText(tr("Pegá la URL del .jar de Paper."));
        return;
    }
    if (QMessageBox::question(this, windowTitle(),
            tr("Se va a reemplazar Paper.jar en todos los servidores apagados de %1 "
               "(los encendidos no se tocan). ¿Continuar?").arg(version)) != QMessageBox::Yes)
        return;
    ejecutar({QStringLiteral("paper"), version, url}, tr("Actualizando Paper…"));
}

void PaginaMinecraft::instalarPlugin()
{
    const QString url = ui->editUrlPlugin->text().trimmed();
    if (url.isEmpty()) {
        ui->etiquetaEstado->setText(tr("Pegá la URL del plugin de Modrinth."));
        return;
    }
    QStringList servidores;
    for (int i = 0; i < ui->listaServidores->count(); ++i) {
        const QListWidgetItem *item = ui->listaServidores->item(i);
        if (item->checkState() == Qt::Checked)
            servidores << item->data(RolNombre).toString();
    }
    if (servidores.isEmpty()) {
        ui->etiquetaEstado->setText(tr("Marcá al menos un servidor en la lista."));
        return;
    }
    ejecutar(QStringList{QStringLiteral("plugin"), url} + servidores, tr("Instalando el plugin…"));
}

void PaginaMinecraft::jugar()
{
    ejecutar({QStringLiteral("prism"), ui->comboInstancia->currentText()}, tr("Abriendo Prism Launcher…"));
}

void PaginaMinecraft::eventoAccion(const QString &palabra, const QString &resto)
{
    if (palabra == u"ETAPA") {
        ui->etiquetaEstado->setText(resto + QStringLiteral("…"));
    } else if (palabra == u"ESPERA") {
        // Reiniciar: hasta 2 minutos guardando mundos
        ui->barraProgreso->setRange(0, 120);
        ui->barraProgreso->setValue(resto.toInt());
    } else if (palabra == u"LISTO" || palabra == u"ERROR") {
        mensajeFinal = resto;
    } else {
        ui->registro->appendPlainText(palabra == u"AVISO" ? resto : palabra + u' ' + resto);
    }
}

void PaginaMinecraft::terminoAccion(int codigo, bool cancelado)
{
    ui->barraProgreso->hide();
    if (cancelado)
        ui->etiquetaEstado->setText(tr("Cancelado."));
    else if (codigo == 0)
        ui->etiquetaEstado->setText(QStringLiteral("✓ ") + mensajeFinal);
    else
        ui->etiquetaEstado->setText(QStringLiteral("✗ ") + (mensajeFinal.isEmpty() ? tr("No se pudo completar.") : mensajeFinal));
    if (!mensajeFinal.isEmpty())
        ui->registro->appendPlainText(mensajeFinal);
    actualizarBotones();

    // El servidor tarda unos segundos en arrancar java: la lista se actualiza después
    consultar();
    QTimer::singleShot(8000, this, &PaginaMinecraft::consultar);
}
