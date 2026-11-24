#include "PaginaMinecraft.h"
#include "AsistenteMinecraft.h"
#include "Tema.h"
#include "ui_PaginaMinecraft.h"

#include <QDate>
#include <QDir>
#include <QFontDatabase>
#include <QHeaderView>
#include <QInputDialog>
#include <QKeyEvent>
#include <QLocale>
#include <QMessageBox>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollBar>
#include <QTimer>
#include <QTreeWidgetItemIterator>

// Datos de cada fila de la lista de servidores (en la columna 0)
constexpr int RolNombre = Qt::UserRole;          // «Amigos/26.1/26.1.2 SMP-1» (vacío en las filas de grupo)
constexpr int RolEncendido = Qt::UserRole + 1;
constexpr int RolRam = Qt::UserRole + 2;
constexpr int RolTipo = Qt::UserRole + 3;

// Los servidores se identifican por su ruta dentro de Servidores/ (<grupo>/<versión>/<servidor>): en la
// lista van dentro de su grupo y en los mensajes se muestran como «26.1.2 SMP-1 (Amigos)».
static QString etiqueta(const QString &servidor)
{
    const int barra = servidor.indexOf(u'/');
    if (barra < 0)
        return servidor;
    return QStringLiteral("%1 (%2)").arg(servidor.section(u'/', -1), servidor.left(barra));
}

static QString nombreTipo(const QString &tipo)
{
    if (tipo == u"forge") return QStringLiteral("Forge");
    if (tipo == u"fabric") return QStringLiteral("Fabric");
    if (tipo == u"vanilla") return QStringLiteral("Vanilla");
    return QStringLiteral("Paper");
}

static QStringList etiquetas(const QStringList &servidores)
{
    QStringList lista;
    for (const QString &s : servidores)
        lista << etiqueta(s);
    return lista;
}

PaginaMinecraft::PaginaMinecraft(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaMinecraft),
      script(QDir(logica).filePath(QStringLiteral("Minecraft.sh")))
{
    ui->setupUi(this);
    ui->barraProgreso->hide();
    ui->botonCancelar->hide();
    ui->textoConsola->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    ui->editComando->installEventFilter(this);
    ui->editComando->setProperty("ayuda", ui->editComando->placeholderText());
    temporizadorJugadores.setInterval(10000);
    connect(&temporizadorJugadores, &QTimer::timeout, this, &PaginaMinecraft::consultarJugadores);
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
        if (elegido != consolaDe)
            verConsola();
    });
    connect(ui->arbolServidores, &QTreeWidget::itemChanged, this, [this](QTreeWidgetItem *item, int columna) {
        const QString nombre = item->data(0, RolNombre).toString();
        if (columna == 0 && item->childCount() > 0)
            clicEnCasilla = true;
        if (columna != 0 || nombre.isEmpty())
            return;
        if (item->checkState(0) == Qt::Checked)
            marcados.insert(nombre);
        else
            marcados.remove(nombre);
    });
    // Grupos desplegables: tocar la fila del grupo lo abre o lo cierra, y se recuerda al actualizar la lista
    // (si el clic fue en la casilla del grupo, solo se marca: itemChanged llega antes que itemClicked)
    connect(ui->arbolServidores, &QTreeWidget::itemPressed, this, [this] { clicEnCasilla = false; });
    connect(ui->arbolServidores, &QTreeWidget::itemClicked, this, [this](QTreeWidgetItem *item) {
        if (item->childCount() > 0 && !clicEnCasilla)
            item->setExpanded(!item->isExpanded());
    });
    connect(ui->arbolServidores, &QTreeWidget::itemExpanded, this, [this](QTreeWidgetItem *item) {
        gruposAbiertos.insert(item->text(0), true);
    });
    connect(ui->arbolServidores, &QTreeWidget::itemCollapsed, this, [this](QTreeWidgetItem *item) {
        gruposAbiertos.insert(item->text(0), false);
    });
    connect(ui->botonIniciar, &QPushButton::clicked, this, &PaginaMinecraft::iniciar);
    connect(ui->botonDetener, &QPushButton::clicked, this, &PaginaMinecraft::detener);
    connect(ui->botonReiniciar, &QPushButton::clicked, this, &PaginaMinecraft::reiniciar);
    connect(ui->botonActualizarLista, &QPushButton::clicked, this, &PaginaMinecraft::consultar);
    connect(ui->botonCrear, &QPushButton::clicked, this, &PaginaMinecraft::crearServidor);
    ui->botonCrear->setIcon(tema::icono(QStringLiteral("agregar")));
    connect(ui->botonPaper, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPaper);
    connect(ui->botonRam, &QPushButton::clicked, this, &PaginaMinecraft::cambiarRam);
    connect(ui->botonReiniciarMundo, &QPushButton::clicked, this, &PaginaMinecraft::reiniciarMundo);
    connect(ui->botonCarpeta, &QPushButton::clicked, this, &PaginaMinecraft::abrirCarpeta);
    connect(ui->botonBuscarPlugins, &QPushButton::clicked, this, &PaginaMinecraft::consultarPlugins);
    connect(ui->botonActualizarPlugins, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPlugins);
    connect(ui->botonPlugin, &QPushButton::clicked, this, &PaginaMinecraft::instalarPlugin);
    connect(ui->editPlugin, &QLineEdit::returnPressed, this, &PaginaMinecraft::instalarPlugin);
    connect(ui->botonJugar, &QPushButton::clicked, this, &PaginaMinecraft::jugar);
    connect(ui->botonEnviar, &QPushButton::clicked, this, &PaginaMinecraft::enviarComando);
    connect(ui->editComando, &QLineEdit::returnPressed, this, &PaginaMinecraft::enviarComando);
    connect(ui->botonTerminal, &QPushButton::clicked, this, &PaginaMinecraft::abrirTerminal);
    connect(ui->botonCancelar, &QPushButton::clicked, &accion, &ProcesoLogica::cancelar);

    connect(&consulta, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoConsulta);
    connect(&consulta, &ProcesoLogica::terminado, this, &PaginaMinecraft::terminoConsulta);
    connect(&plugins, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoPlugins);
    connect(&plugins, &ProcesoLogica::terminado, this, [this](int codigo, bool cancelado) {
        if (cancelado)
            return;
        const QString clase = pluginsSonMods ? tr("Mods") : tr("Plugins");
        if (ui->arbolPlugins->topLevelItemCount() == 0 && codigo == 0)
            ui->arbolPlugins->setHeaderLabels({pluginsSonMods ? tr("Mod (no tiene)") : tr("Plugin (no tiene)"), tr("Versión"), tr("Nueva"), tr("Estado")});
        ui->grupoPlugins->setTitle(pluginsNuevos > 0
            ? tr("%1 de %2: %3 con versión nueva").arg(clase, etiqueta(pluginsDe)).arg(pluginsNuevos)
            : tr("%1 de %2").arg(clase, etiqueta(pluginsDe)));
        ui->pestanasServidor->setTabText(ui->pestanasServidor->indexOf(ui->pestanaPlugins),
            pluginsNuevos > 0 ? tr("%1 (%2 con versión nueva)").arg(clase).arg(pluginsNuevos) : clase);
        actualizarBotones();
    });
    connect(&accion, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoAccion);
    connect(&accion, &ProcesoLogica::terminado, this, &PaginaMinecraft::terminoAccion);
    connect(&registro, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoRegistro);
    connect(&conectados, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoJugadores);
    connect(&envio, &ProcesoLogica::evento, this, [this](const QString &palabra, const QString &resto) {
        if (palabra == u"ERROR")
            tema::mostrarEstado(ui->etiquetaEstado, resto, tema::Estado::Error);
        else if (palabra == u"LISTO" && !resto.startsWith(u"Enviado"))
            tema::mostrarEstado(ui->etiquetaEstado, resto, tema::Estado::Ok);
    });
    connect(&envio, &ProcesoLogica::terminado, this, [this] { actualizarBotones(); });
}

PaginaMinecraft::~PaginaMinecraft()
{
    // tail -F no termina solo: se corta todo su grupo de procesos
    registro.cancelarYEsperar();
    conectados.cancelarYEsperar();
    envio.cancelarYEsperar();
    delete ui;
}

// Cada vez que se abre la página se actualiza la lista (un servidor pudo prenderse o apagarse)
void PaginaMinecraft::showEvent(QShowEvent *evento)
{
    QWidget::showEvent(evento);
    consultar();
    if (!registro.ocupado())
        verConsola();
    temporizadorJugadores.start();
}

// Fuera de la página no se sigue leyendo el registro ni preguntando quién está
void PaginaMinecraft::hideEvent(QHideEvent *evento)
{
    QWidget::hideEvent(evento);
    temporizadorJugadores.stop();
    registro.cancelar();
    conectados.cancelar();
    consolaDe.clear();
}

bool PaginaMinecraft::eventFilter(QObject *objeto, QEvent *evento)
{
    if (objeto == ui->editComando && evento->type() == QEvent::KeyPress && !historial.isEmpty()) {
        const int tecla = static_cast<QKeyEvent *>(evento)->key();
        if (tecla == Qt::Key_Up || tecla == Qt::Key_Down) {
            posHistorial = qBound(0, posHistorial + (tecla == Qt::Key_Up ? -1 : 1), int(historial.size()));
            ui->editComando->setText(posHistorial < historial.size() ? historial.at(posHistorial) : QString());
            return true;
        }
    }
    return QWidget::eventFilter(objeto, evento);
}

// --- Consola -----------------------------------------------------------------------------------

void PaginaMinecraft::verConsola()
{
    registro.cancelarYEsperar();
    ui->textoConsola->clear();
    consola = Consola::Nada;
    jugadoresConectados = 0;
    consolaDe = servidorElegido(&consolaEncendido);
    if (consolaDe.isEmpty()) {
        ui->etiquetaJugadores->setText(tr("Elegí un servidor para ver su consola."));
    } else if (isVisible()) {
        ui->etiquetaJugadores->setText(consolaEncendido ? tr("Consultando quién está conectado…")
                                                        : tr("%1 está apagado: se ve lo último que registró.").arg(etiqueta(consolaDe)));
        registro.iniciar(script, {QStringLiteral("registro"), consolaDe});
        consultarJugadores();
    }
    actualizarBotones();
}

void PaginaMinecraft::eventoRegistro(const QString &palabra, const QString &resto)
{
    if (palabra == u"LINEA") {
        QScrollBar *barra = ui->textoConsola->verticalScrollBar();
        const bool alFinal = barra->value() >= barra->maximum() - 4;    // si subió a leer, no se lo mueve
        ui->textoConsola->appendPlainText(resto);
        if (alFinal)
            barra->setValue(barra->maximum());
    } else if (palabra == u"CONSOLA") {
        consola = resto == u"COMANDOS" ? Consola::Comandos
                : resto == u"SOLO_LECTURA" ? Consola::SoloLectura : Consola::Apagado;
        actualizarBotones();
    }
}

void PaginaMinecraft::consultarJugadores()
{
    if (!isVisible() || consolaDe.isEmpty() || !consolaEncendido || conectados.ocupado())
        return;
    conectados.iniciar(script, {QStringLiteral("jugadores"), consolaDe});
}

void PaginaMinecraft::eventoJugadores(const QString &palabra, const QString &resto)
{
    if (palabra == u"AVISO") {
        ui->etiquetaJugadores->setText(resto);
        return;
    }
    if (palabra != u"JUGADORES")
        return;
    // JUGADORES conectados<tab>máximo<tab>nombre,nombre…
    const QStringList c = resto.split(u'\t');
    if (c.size() < 3)
        return;
    jugadoresConectados = c.at(0).toInt();
    const QStringList nombres = c.at(2).split(u',', Qt::SkipEmptyParts);
    if (jugadoresConectados == 0) {
        ui->etiquetaJugadores->setText(tr("Nadie conectado (entran hasta %1).").arg(c.at(1)));
        return;
    }
    QString lista = nombres.join(QStringLiteral(", "));
    if (nombres.size() < jugadoresConectados)
        lista += (lista.isEmpty() ? QString() : QStringLiteral(" ")) + tr("y %1 más").arg(jugadoresConectados - nombres.size());
    ui->etiquetaJugadores->setText(tr("Conectados (%1 de %2): %3").arg(jugadoresConectados).arg(c.at(1), lista));
}

void PaginaMinecraft::enviarComando()
{
    const QString texto = ui->editComando->text().trimmed();
    if (texto.isEmpty() || envio.ocupado() || consola != Consola::Comandos)
        return;
    if (historial.isEmpty() || historial.constLast() != texto)
        historial << texto;
    posHistorial = historial.size();
    ui->editComando->clear();
    envio.iniciar(script, {QStringLiteral("comando"), consolaDe, texto});
    actualizarBotones();
}

void PaginaMinecraft::abrirTerminal()
{
    if (envio.ocupado() || consolaDe.isEmpty())
        return;
    envio.iniciar(script, {QStringLiteral("terminal"), consolaDe});
    actualizarBotones();
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
        QTreeWidgetItem *grupo = filaGrupo(nombre.contains(u'/') ? nombre.section(u'/', 0, 0) : QString());
        auto *item = grupo ? new QTreeWidgetItem(grupo) : new QTreeWidgetItem(ui->arbolServidores);
        if (grupo && encendido)
            grupo->setIcon(0, tema::icono(QStringLiteral("punto"), tema::colores().ok));
        // Cerrados salvo que el usuario lo haya abierto, o que tenga uno encendido o el elegido
        if (grupo && !gruposAbiertos.contains(grupo->text(0)) && (encendido || nombre == elegido))
            grupo->setExpanded(true);
        item->setText(0, nombre.section(u'/', -1) + (encendido ? tr("  (encendido)") : QString()));
        item->setIcon(0, tema::icono(QStringLiteral("punto"), encendido ? tema::colores().ok : tema::colores().texto3));
        item->setText(1, nombreTipo(c.at(2)) + u' ' + c.at(3));
        item->setText(2, c.at(4));
        item->setText(3, ultimo);
        item->setText(4, c.at(6));
        item->setToolTip(0, tr("%1\nArranca con %2").arg(nombre, c.at(7)));
        item->setData(0, RolNombre, nombre);
        item->setData(0, RolEncendido, encendido);
        item->setData(0, RolRam, c.at(6));
        item->setData(0, RolTipo, c.at(2));
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(0, marcados.contains(nombre) ? Qt::Checked : Qt::Unchecked);
        if (grupo) {
            int prendidos = 0;
            for (int i = 0; i < grupo->childCount(); ++i)
                prendidos += grupo->child(i)->data(0, RolEncendido).toBool() ? 1 : 0;
            const int total = grupo->childCount();
            grupo->setText(1, (total == 1 ? tr("1 servidor") : tr("%1 servidores").arg(total))
                                  + (prendidos == 0 ? QString()
                                     : prendidos == 1 ? tr(" · 1 encendido") : tr(" · %1 encendidos").arg(prendidos)));
            grupo->setForeground(1, prendidos > 0 ? tema::colores().ok : tema::colores().texto3);
        }
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
    // Si el elegido se prendió o se apagó, la consola vuelve a empezar (cambia si acepta comandos)
    if (paso == Paso::Servidores && isVisible()) {
        bool encendido = false;
        const QString servidor = servidorElegido(&encendido);
        if (servidor != consolaDe || encendido != consolaEncendido)
            verConsola();
    }
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
    pluginsNuevos = 0;
    pluginsDe = servidorElegido();
    const QTreeWidgetItem *actual = ui->arbolServidores->currentItem();
    const QString tipo = actual ? actual->data(0, RolTipo).toString() : QString();
    pluginsSonMods = tipo == u"fabric" || tipo == u"forge";
    ui->arbolPlugins->setHeaderLabels({pluginsSonMods ? tr("Mod") : tr("Plugin"), tr("Versión"), tr("Nueva"), tr("Estado")});
    ui->pestanasServidor->setTabText(ui->pestanasServidor->indexOf(ui->pestanaPlugins), pluginsSonMods ? tr("Mods") : tr("Plugins"));
    if (pluginsDe.isEmpty()) {
        ui->grupoPlugins->setTitle(tr("Plugins o mods del servidor elegido (se reconocen en Modrinth)"));
        actualizarBotones();
        return;
    }
    ui->grupoPlugins->setTitle((pluginsSonMods ? tr("Mods de %1: consultando Modrinth…") : tr("Plugins de %1: consultando Modrinth…"))
                                   .arg(etiqueta(pluginsDe)));
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

// Fila del grupo (la primera carpeta de la ruta), creada la primera vez; sin grupo, nullptr
QTreeWidgetItem *PaginaMinecraft::filaGrupo(const QString &grupo)
{
    if (grupo.isEmpty())
        return nullptr;
    for (int i = 0; i < ui->arbolServidores->topLevelItemCount(); ++i) {
        QTreeWidgetItem *fila = ui->arbolServidores->topLevelItem(i);
        if (fila->data(0, RolNombre).toString().isEmpty() && fila->text(0) == grupo)
            return fila;
    }
    auto *fila = new QTreeWidgetItem(ui->arbolServidores);
    fila->setText(0, grupo);
    QFont negrita = fila->font(0);
    negrita.setBold(true);
    fila->setFont(0, negrita);
    fila->setIcon(0, tema::icono(QStringLiteral("punto"), tema::colores().texto3));
    fila->setToolTip(0, tr("Marcar el grupo marca todos sus servidores"));
    // No se elige (no es un servidor), pero se puede marcar entero
    fila->setFlags(Qt::ItemIsEnabled | Qt::ItemIsUserCheckable | Qt::ItemIsAutoTristate);
    fila->setCheckState(0, Qt::Unchecked);
    fila->setExpanded(gruposAbiertos.value(grupo, false));
    return fila;
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
    for (QTreeWidgetItemIterator it(ui->arbolServidores); *it; ++it) {
        const QString nombre = (*it)->data(0, RolNombre).toString();
        if (!nombre.isEmpty() && (*it)->checkState(0) == Qt::Checked)
            lista << nombre;
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
    ui->botonCrear->setEnabled(libre);
    ui->grupoPrism->setEnabled(libre && ui->comboInstancia->count() > 0);

    const bool comandos = consola == Consola::Comandos;
    ui->editComando->setEnabled(comandos);
    ui->botonEnviar->setEnabled(comandos && !envio.ocupado());
    ui->botonTerminal->setEnabled(comandos && !envio.ocupado());
    ui->editComando->setPlaceholderText(
        comandos ? ui->editComando->property("ayuda").toString()
        : consola == Consola::SoloLectura ? tr("Se prendió sin consola compartida: reinicialo desde el panel para mandarle comandos")
        : consola == Consola::Apagado ? tr("Apagado: no recibe comandos")
        : QString());
}

void PaginaMinecraft::ejecutar(const QStringList &argumentos, const QString &estado, const QByteArray &entrada)
{
    mensajeFinal.clear();
    tema::mostrarEstado(ui->etiquetaEstado, estado);
    ui->barraProgreso->setRange(0, 0);    // sin porcentaje: barra «ocupada»
    ui->barraProgreso->show();
    accion.iniciar(script, argumentos, entrada);
    ui->botonCancelar->setVisible(cancelable || creando);
    actualizarBotones();
}

void PaginaMinecraft::iniciar()
{
    ejecutar({QStringLiteral("iniciar"), servidorElegido()}, tr("Iniciando %1…").arg(etiqueta(servidorElegido())));
}

void PaginaMinecraft::detener()
{
    detenerOReiniciar(false);
}

void PaginaMinecraft::reiniciar()
{
    detenerOReiniciar(true);
}

// Si hay gente conectada (y se le pueden mandar comandos) ofrece avisar en el chat y esperar un minuto
void PaginaMinecraft::detenerOReiniciar(bool reinicio)
{
    const QString servidor = servidorElegido();
    int segundos = 0;
    if (jugadoresConectados > 0 && consola == Consola::Comandos && consolaDe == servidor) {
        QMessageBox caja(QMessageBox::Question, windowTitle(),
            (jugadoresConectados == 1 ? tr("Hay 1 jugador en %1.").arg(etiqueta(servidor))
                                      : tr("Hay %1 jugadores en %2.").arg(jugadoresConectados).arg(etiqueta(servidor)))
                + u' ' + (reinicio ? tr("Se va a reiniciar guardando los mundos.") : tr("Se va a apagar guardando los mundos.")),
            QMessageBox::Cancel, this);
        caja.setInformativeText(tr("Con el aviso, el chat cuenta los segundos y se puede cancelar mientras tanto."));
        QPushButton *avisar = caja.addButton(tr("Avisar y esperar 1 minuto"), QMessageBox::AcceptRole);
        QPushButton *ya = caja.addButton(reinicio ? tr("Reiniciar ya") : tr("Apagar ya"), QMessageBox::DestructiveRole);
        caja.setDefaultButton(avisar);
        caja.exec();
        if (caja.clickedButton() == avisar)
            segundos = 60;
        else if (caja.clickedButton() != ya)
            return;
    } else if (QMessageBox::question(this, windowTitle(),
                   reinicio ? tr("Se va a detener %1 guardando los mundos (los jugadores se desconectan) y se va a "
                                 "volver a abrir. ¿Continuar?").arg(etiqueta(servidor))
                            : tr("Se va a apagar %1 guardando los mundos (los jugadores se desconectan). ¿Continuar?")
                                  .arg(etiqueta(servidor))) != QMessageBox::Yes) {
        return;
    }
    cancelable = segundos > 0;
    ejecutar({reinicio ? QStringLiteral("reiniciar") : QStringLiteral("detener"), servidor, QString::number(segundos)},
             reinicio ? tr("Reiniciando %1…").arg(etiqueta(servidor)) : tr("Deteniendo %1…").arg(etiqueta(servidor)));
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
                .arg(etiquetas(servidores).join(QStringLiteral("\n")))) != QMessageBox::Yes)
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
        tr("Memoria máxima para %1 (GB):").arg(etiqueta(servidor)),
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
               "Respaldos/%2/mundos y se borra de la carpeta del servidor: al iniciarlo se genera uno nuevo.")
                .arg(etiqueta(servidor), servidor),
            QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes)
        return;
    ejecutar({QStringLiteral("reiniciar-mundo"), servidor}, tr("Reiniciando el mundo de %1…").arg(etiqueta(servidor)));
}

void PaginaMinecraft::abrirCarpeta()
{
    ejecutar({QStringLiteral("carpeta"), servidorElegido()}, tr("Abriendo la carpeta…"));
}

void PaginaMinecraft::actualizarPlugins()
{
    const QString servidor = servidorElegido();
    if (QMessageBox::question(this, windowTitle(),
            tr("Se van a actualizar %1 %2 de %3. Los anteriores quedan en Respaldos/%4/%5. ¿Continuar?")
               .arg(pluginsNuevos).arg(pluginsSonMods ? tr("mod(s)") : tr("plugin(s)"), etiqueta(servidor), servidor,
                    pluginsSonMods ? QStringLiteral("mods") : QStringLiteral("plugins"))) != QMessageBox::Yes)
        return;
    recargarPlugins = true;
    ejecutar({QStringLiteral("plugins-actualizar"), servidor},
             (pluginsSonMods ? tr("Actualizando mods de %1…") : tr("Actualizando plugins de %1…")).arg(etiqueta(servidor)));
}

void PaginaMinecraft::instalarPlugin()
{
    const QString texto = ui->editPlugin->text().trimmed();
    if (texto.isEmpty()) {
        tema::mostrarEstado(ui->etiquetaEstado, tr("Escribí el nombre del plugin o mod en Modrinth (o pegá su URL)."));
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
    } else if (palabra == u"CREADO") {
        // El servidor nuevo queda elegido y con su grupo abierto
        elegido = resto;
        if (resto.contains(u'/'))
            gruposAbiertos.insert(resto.section(u'/', 0, 0), true);
    }
}

void PaginaMinecraft::terminoAccion(int codigo, bool cancelado)
{
    ui->barraProgreso->hide();
    ui->botonCancelar->hide();
    if (cancelado && cancelable)
        tema::mostrarEstado(ui->etiquetaEstado, tr("Cancelado: el servidor sigue prendido (se avisó en el chat)."));
    else if (cancelado && creando)
        tema::mostrarEstado(ui->etiquetaEstado, tr("Cancelado: no se creó nada."));
    else if (cancelado)
        tema::mostrarEstado(ui->etiquetaEstado, tr("Cancelado."));
    else if (codigo == 0)
        tema::mostrarEstado(ui->etiquetaEstado, mensajeFinal, tema::Estado::Ok);
    else
        tema::mostrarEstado(ui->etiquetaEstado, (mensajeFinal.isEmpty() ? tr("No se pudo completar.") : mensajeFinal), tema::Estado::Error);
    if (!mensajeFinal.isEmpty())
        ui->registro->appendPlainText(mensajeFinal);
    cancelable = false;
    creando = false;
    actualizarBotones();

    if (recargarPlugins) {
        recargarPlugins = false;
        consultarPlugins();
    }
    // El servidor tarda unos segundos en arrancar java: la lista se actualiza después
    consultar();
    QTimer::singleShot(8000, this, &PaginaMinecraft::consultar);
}

// Asistente para un servidor nuevo: arma la configuración y «Minecraft.sh crear» la usa (por stdin)
void PaginaMinecraft::crearServidor()
{
    QHash<QString, bool> existentes;
    for (QTreeWidgetItemIterator it(ui->arbolServidores); *it; ++it) {
        const QString nombre = (*it)->data(0, RolNombre).toString();
        if (!nombre.isEmpty())
            existentes.insert(nombre, (*it)->data(0, RolEncendido).toBool());
    }
    AsistenteMinecraft asistente(script, existentes, this);
    if (asistente.exec() != QDialog::Accepted)
        return;
    creando = true;
    ejecutar({QStringLiteral("crear")}, tr("Creando %1…").arg(asistente.titulo()), asistente.configuracion());
}
