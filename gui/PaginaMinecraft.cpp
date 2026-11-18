#include "PaginaMinecraft.h"
#include "Tema.h"
#include "ui_PaginaMinecraft.h"

#include <QDate>
#include <QDir>
#include <QHeaderView>
#include <QInputDialog>
#include <QLocale>
#include <QMessageBox>
#include <QRegularExpression>
#include <QTimer>

// Datos de cada fila de la lista de servidores (en la columna 0)
constexpr int RolNombre = Qt::UserRole;          // «26.3 SMP-1»
constexpr int RolEncendido = Qt::UserRole + 1;
constexpr int RolRam = Qt::UserRole + 2;
constexpr int RolTipo = Qt::UserRole + 3;

PaginaMinecraft::PaginaMinecraft(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaMinecraft),
      script(QDir(logica).filePath(QStringLiteral("Minecraft.sh")))
{
    ui->setupUi(this);
    ui->barraProgreso->hide();
    ui->arbolServidores->header()->setSectionResizeMode(0, QHeaderView::Stretch);
    for (int c = 1; c < ui->arbolServidores->columnCount(); ++c)
        ui->arbolServidores->header()->setSectionResizeMode(c, QHeaderView::ResizeToContents);
    ui->arbolPlugins->header()->setSectionResizeMode(0, QHeaderView::Stretch);
    for (int c = 1; c < ui->arbolPlugins->columnCount(); ++c)
        ui->arbolPlugins->header()->setSectionResizeMode(c, QHeaderView::ResizeToContents);

    connect(ui->arbolServidores, &QTreeWidget::currentItemChanged, this, [this] {
        elegido = servidorElegido();
        actualizarBotones();
        if (elegido != pluginsDe)
            consultarPlugins();
    });
    connect(ui->arbolServidores, &QTreeWidget::itemChanged, this, [this](QTreeWidgetItem *item, int columna) {
        if (columna != 0)
            return;
        const QString nombre = item->data(0, RolNombre).toString();
        if (item->checkState(0) == Qt::Checked)
            marcados.insert(nombre);
        else
            marcados.remove(nombre);
    });
    connect(ui->botonIniciar, &QPushButton::clicked, this, &PaginaMinecraft::iniciar);
    connect(ui->botonDetener, &QPushButton::clicked, this, &PaginaMinecraft::detener);
    connect(ui->botonReiniciar, &QPushButton::clicked, this, &PaginaMinecraft::reiniciar);
    connect(ui->botonActualizarLista, &QPushButton::clicked, this, &PaginaMinecraft::consultar);
    connect(ui->botonPaper, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPaper);
    connect(ui->botonRam, &QPushButton::clicked, this, &PaginaMinecraft::cambiarRam);
    connect(ui->botonReiniciarMundo, &QPushButton::clicked, this, &PaginaMinecraft::reiniciarMundo);
    connect(ui->botonCarpeta, &QPushButton::clicked, this, &PaginaMinecraft::abrirCarpeta);
    connect(ui->botonBuscarPlugins, &QPushButton::clicked, this, &PaginaMinecraft::consultarPlugins);
    connect(ui->botonActualizarPlugins, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPlugins);
    connect(ui->botonPlugin, &QPushButton::clicked, this, &PaginaMinecraft::instalarPlugin);
    connect(ui->editPlugin, &QLineEdit::returnPressed, this, &PaginaMinecraft::instalarPlugin);
    connect(ui->botonJugar, &QPushButton::clicked, this, &PaginaMinecraft::jugar);

    connect(&consulta, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoConsulta);
    connect(&consulta, &ProcesoLogica::terminado, this, &PaginaMinecraft::terminoConsulta);
    connect(&plugins, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoPlugins);
    connect(&plugins, &ProcesoLogica::terminado, this, [this](int codigo, bool cancelado) {
        if (cancelado)
            return;
        if (ui->arbolPlugins->topLevelItemCount() == 0 && codigo == 0)
            ui->arbolPlugins->setHeaderLabels({tr("Plugin (no tiene)"), tr("Versión"), tr("Nueva"), tr("Estado")});
        ui->grupoPlugins->setTitle(pluginsNuevos > 0
            ? tr("Plugins de %1: %2 con versión nueva").arg(pluginsDe).arg(pluginsNuevos)
            : tr("Plugins de %1").arg(pluginsDe));
        actualizarBotones();
    });
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
    const QSignalBlocker bloqueo(ui->arbolServidores);
    ui->arbolServidores->clear();
    paso = Paso::Servidores;
    consulta.iniciar(script, {QStringLiteral("servidores")});
}

void PaginaMinecraft::eventoConsulta(const QString &palabra, const QString &resto)
{
    if (palabra == u"SERVIDOR") {
        // SERVIDOR estado<tab>nombre<tab>tipo<tab>versión<tab>tamaño<tab>último uso<tab>RAM<tab>jar
        const QStringList c = resto.split(u'\t');
        if (c.size() < 8)
            return;
        const bool encendido = c.at(0) == u"ENCENDIDO";
        const QString &nombre = c.at(1);
        QString ultimo = c.at(5);
        const QDate fecha = QDate::fromString(ultimo, Qt::ISODate);
        if (fecha.isValid())
            ultimo = fecha == QDate::currentDate() ? tr("hoy") : QLocale().toString(fecha, QLocale::ShortFormat);

        const QSignalBlocker bloqueo(ui->arbolServidores);
        auto *item = new QTreeWidgetItem(ui->arbolServidores);
        item->setText(0, nombre + (encendido ? tr("  (encendido)") : QString()));
        item->setIcon(0, tema::icono(QStringLiteral("punto"), encendido ? tema::colores().ok : tema::colores().texto3));
        item->setText(1, (c.at(2) == u"forge" ? QStringLiteral("Forge ") : QStringLiteral("Paper ")) + c.at(3));
        item->setText(2, c.at(4));
        item->setText(3, ultimo);
        item->setText(4, c.at(6));
        item->setToolTip(0, tr("Arranca con %1").arg(c.at(7)));
        item->setData(0, RolNombre, nombre);
        item->setData(0, RolEncendido, encendido);
        item->setData(0, RolRam, c.at(6));
        item->setData(0, RolTipo, c.at(2));
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(0, marcados.contains(nombre) ? Qt::Checked : Qt::Unchecked);
        if (nombre == elegido)
            ui->arbolServidores->setCurrentItem(item);
    } else if (palabra == u"INSTANCIA") {
        ui->comboInstancia->addItem(resto);
    }
}

// Después de los servidores, la primera vez, las instancias de Prism (no cambian mientras el
// programa está abierto)
void PaginaMinecraft::terminoConsulta()
{
    if (paso == Paso::Servidores && primeraVez) {
        paso = Paso::Instancias;
        consulta.iniciar(script, {QStringLiteral("instancias")});
        return;
    }
    primeraVez = false;
    actualizarBotones();
}

void PaginaMinecraft::consultarPlugins()
{
    plugins.cancelarYEsperar();
    ui->arbolPlugins->clear();
    ui->arbolPlugins->setHeaderLabels({tr("Plugin"), tr("Versión"), tr("Nueva"), tr("Estado")});
    pluginsNuevos = 0;
    pluginsDe = servidorElegido();
    if (pluginsDe.isEmpty()) {
        ui->grupoPlugins->setTitle(tr("Plugins del servidor elegido (se reconocen en Modrinth)"));
        actualizarBotones();
        return;
    }
    ui->grupoPlugins->setTitle(tr("Plugins de %1: consultando Modrinth…").arg(pluginsDe));
    plugins.iniciar(script, {QStringLiteral("plugins"), pluginsDe});
    actualizarBotones();
}

void PaginaMinecraft::eventoPlugins(const QString &palabra, const QString &resto)
{
    if (palabra != u"PLUGIN")
        return;
    // PLUGIN archivo<tab>nombre<tab>versión<tab>nueva<tab>estado<tab>…
    const QStringList c = resto.split(u'\t');
    if (c.size() < 5)
        return;
    auto *item = new QTreeWidgetItem(ui->arbolPlugins);
    item->setText(0, c.at(1));
    item->setToolTip(0, c.at(0));
    item->setText(1, c.at(2));
    const QString &estado = c.at(4);
    if (estado == u"NUEVA") {
        item->setText(2, c.at(3));
        item->setText(3, tr("Versión nueva"));
        item->setForeground(3, tema::colores().aviso);
        ++pluginsNuevos;
    } else if (estado == u"AL_DIA") {
        item->setText(3, tr("Al día"));
        item->setForeground(3, tema::colores().ok);
    } else if (estado == u"SIN_VERSION") {
        item->setText(3, tr("sin versión para esta versión de Minecraft"));
    } else {
        item->setText(3, tr("no está en Modrinth"));
    }
}

QString PaginaMinecraft::servidorElegido(bool *encendido) const
{
    const QTreeWidgetItem *item = ui->arbolServidores->currentItem();
    if (encendido)
        *encendido = item && item->data(0, RolEncendido).toBool();
    return item ? item->data(0, RolNombre).toString() : QString();
}

QStringList PaginaMinecraft::servidoresMarcados() const
{
    QStringList lista;
    for (int i = 0; i < ui->arbolServidores->topLevelItemCount(); ++i) {
        const QTreeWidgetItem *item = ui->arbolServidores->topLevelItem(i);
        if (item->checkState(0) == Qt::Checked)
            lista << item->data(0, RolNombre).toString();
    }
    return lista;
}

void PaginaMinecraft::actualizarBotones()
{
    bool encendido = false;
    const bool hay = !servidorElegido(&encendido).isEmpty();
    const bool libre = !accion.ocupado();
    ui->botonIniciar->setEnabled(libre && hay && !encendido);
    ui->botonDetener->setEnabled(libre && hay && encendido);
    ui->botonReiniciar->setEnabled(libre && hay && encendido);
    ui->botonPaper->setEnabled(libre);
    ui->botonRam->setEnabled(libre && hay);
    ui->botonReiniciarMundo->setEnabled(libre && hay && !encendido);
    ui->botonCarpeta->setEnabled(hay);
    ui->botonBuscarPlugins->setEnabled(libre && hay && !plugins.ocupado());
    ui->botonActualizarPlugins->setEnabled(libre && hay && !encendido && !plugins.ocupado() && pluginsNuevos > 0
                                           && pluginsDe == servidorElegido());
    ui->botonPlugin->setEnabled(libre);
    ui->grupoPrism->setEnabled(libre && ui->comboInstancia->count() > 0);
}

void PaginaMinecraft::ejecutar(const QStringList &argumentos, const QString &estado)
{
    mensajeFinal.clear();
    tema::mostrarEstado(ui->etiquetaEstado, estado);
    ui->barraProgreso->setRange(0, 0);    // sin porcentaje: barra «ocupada»
    ui->barraProgreso->show();
    accion.iniciar(script, argumentos);
    actualizarBotones();
}

void PaginaMinecraft::iniciar()
{
    ejecutar({QStringLiteral("iniciar"), servidorElegido()}, tr("Iniciando %1…").arg(servidorElegido()));
}

void PaginaMinecraft::detener()
{
    const QString servidor = servidorElegido();
    if (QMessageBox::question(this, windowTitle(),
            tr("Se va a apagar %1 guardando los mundos (los jugadores se desconectan). ¿Continuar?").arg(servidor))
        != QMessageBox::Yes)
        return;
    ejecutar({QStringLiteral("detener"), servidor}, tr("Deteniendo %1…").arg(servidor));
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
    QStringList servidores = servidoresMarcados();
    if (servidores.isEmpty() && !servidorElegido().isEmpty())
        servidores << servidorElegido();
    if (servidores.isEmpty()) {
        tema::mostrarEstado(ui->etiquetaEstado, tr("Marcá (o elegí) al menos un servidor."));
        return;
    }
    if (QMessageBox::question(this, windowTitle(),
            tr("Se va a bajar la última compilación estable de Paper (de la misma versión de Minecraft) para:\n\n%1\n\n"
               "Los encendidos no se tocan y el jar anterior queda en Respaldos. ¿Continuar?")
                .arg(servidores.join(QStringLiteral("\n")))) != QMessageBox::Yes)
        return;
    recargarPlugins = false;
    ejecutar(QStringList{QStringLiteral("paper")} + servidores, tr("Actualizando Paper…"));
}

void PaginaMinecraft::cambiarRam()
{
    const QString servidor = servidorElegido();
    const QTreeWidgetItem *item = ui->arbolServidores->currentItem();
    const QString actual = item ? item->data(0, RolRam).toString() : QStringLiteral("8G");
    bool ok = false;
    const int gb = QInputDialog::getInt(this, windowTitle(),
        tr("Memoria máxima para %1 (GB):").arg(servidor),
        QString(actual).remove(QRegularExpression(QStringLiteral("[^0-9]"))).toInt(), 1, 24, 1, &ok);
    if (!ok)
        return;
    ejecutar({QStringLiteral("ram"), servidor, QString::number(gb) + u'G'}, tr("Cambiando la RAM…"));
}

void PaginaMinecraft::reiniciarMundo()
{
    const QString servidor = servidorElegido();
    if (QMessageBox::warning(this, windowTitle(),
            tr("¿Reiniciar el mundo de %1?\n\nEl mundo actual (con el Nether y el End) se guarda comprimido en "
               "Respaldos/%1/mundos y se borra de la carpeta del servidor: al iniciarlo se genera uno nuevo.")
                .arg(servidor),
            QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes)
        return;
    ejecutar({QStringLiteral("reiniciar-mundo"), servidor}, tr("Reiniciando el mundo de %1…").arg(servidor));
}

void PaginaMinecraft::abrirCarpeta()
{
    ejecutar({QStringLiteral("carpeta"), servidorElegido()}, tr("Abriendo la carpeta…"));
}

void PaginaMinecraft::actualizarPlugins()
{
    const QString servidor = servidorElegido();
    if (QMessageBox::question(this, windowTitle(),
            tr("Se van a actualizar %n plugin(s) de %1. Los anteriores quedan en Respaldos/%1/plugins. ¿Continuar?",
               nullptr, pluginsNuevos).arg(servidor)) != QMessageBox::Yes)
        return;
    recargarPlugins = true;
    ejecutar({QStringLiteral("plugins-actualizar"), servidor}, tr("Actualizando plugins de %1…").arg(servidor));
}

void PaginaMinecraft::instalarPlugin()
{
    const QString texto = ui->editPlugin->text().trimmed();
    if (texto.isEmpty()) {
        tema::mostrarEstado(ui->etiquetaEstado, tr("Escribí el nombre del plugin en Modrinth (o pegá su URL)."));
        return;
    }
    QStringList servidores = servidoresMarcados();
    if (servidores.isEmpty() && !servidorElegido().isEmpty())
        servidores << servidorElegido();
    if (servidores.isEmpty()) {
        tema::mostrarEstado(ui->etiquetaEstado, tr("Marcá (o elegí) al menos un servidor."));
        return;
    }
    recargarPlugins = true;
    ejecutar(QStringList{QStringLiteral("plugin"), texto} + servidores, tr("Instalando «%1»…").arg(texto));
}

void PaginaMinecraft::jugar()
{
    ejecutar({QStringLiteral("prism"), ui->comboInstancia->currentText()}, tr("Abriendo Prism Launcher…"));
}

void PaginaMinecraft::eventoAccion(const QString &palabra, const QString &resto)
{
    if (palabra == u"ETAPA") {
        tema::mostrarEstado(ui->etiquetaEstado, resto + QStringLiteral("…"));
    } else if (palabra == u"ESPERA") {
        // Detener: hasta 2 minutos guardando mundos
        ui->barraProgreso->setRange(0, 120);
        ui->barraProgreso->setValue(resto.toInt());
    } else if (palabra == u"LISTO" || palabra == u"ERROR") {
        mensajeFinal = resto;
    } else if (palabra == u"AVISO") {
        ui->registro->appendPlainText(resto);
    }
}

void PaginaMinecraft::terminoAccion(int codigo, bool cancelado)
{
    ui->barraProgreso->hide();
    if (cancelado)
        tema::mostrarEstado(ui->etiquetaEstado, tr("Cancelado."));
    else if (codigo == 0)
        tema::mostrarEstado(ui->etiquetaEstado, mensajeFinal, tema::Estado::Ok);
    else
        tema::mostrarEstado(ui->etiquetaEstado, (mensajeFinal.isEmpty() ? tr("No se pudo completar.") : mensajeFinal), tema::Estado::Error);
    if (!mensajeFinal.isEmpty())
        ui->registro->appendPlainText(mensajeFinal);
    actualizarBotones();

    if (recargarPlugins) {
        recargarPlugins = false;
        consultarPlugins();
    }
    // El servidor tarda unos segundos en arrancar java: la lista se actualiza después
    consultar();
    QTimer::singleShot(8000, this, &PaginaMinecraft::consultar);
}
