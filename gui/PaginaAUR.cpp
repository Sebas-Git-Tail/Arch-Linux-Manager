#include "PaginaAUR.h"
#include "Tema.h"
#include "Terminal.h"

#include <QDir>
#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QProcess>
#include <QPushButton>
#include <QScrollArea>
#include <QVBoxLayout>

#include <csignal>

namespace {

QLabel *nuevoIcono(QWidget *padre)
{
    auto *icono = new QLabel(padre);
    icono->setFixedSize(40, 40);
    icono->setAlignment(Qt::AlignCenter);
    const QColor a = tema::colores().acento;
    icono->setStyleSheet(QStringLiteral("background: rgba(%1, %2, %3, 0.16); border-radius: 8px;")
                             .arg(a.red()).arg(a.green()).arg(a.blue()));
    icono->setPixmap(tema::pixmap(QStringLiteral("paquete"), 22, a, padre->devicePixelRatioF()));
    return icono;
}

} // namespace

PaginaAUR::PaginaAUR(const QString &base, QWidget *parent)
    : QWidget(parent), base(base)
{
    setWindowTitle(tr("Apps del AUR"));

    auto *principal = new QVBoxLayout(this);
    principal->setSpacing(10);

    auto *descripcion = new QLabel(tr("Apps que no están en los repositorios de Arch. Se bajan del AUR y se "
                                      "arman en una terminal, que pide la contraseña de sudo. «Actualizar Arch» "
                                      "también actualiza las que ya están instaladas."), this);
    descripcion->setWordWrap(true);
    principal->addWidget(descripcion);

    auto *contenido = new QWidget;
    layoutLista = new QVBoxLayout(contenido);
    layoutLista->setContentsMargins(0, 0, 0, 0);
    layoutLista->setSpacing(8);
    layoutLista->addStretch();
    auto *desplazable = new QScrollArea(this);
    desplazable->setWidgetResizable(true);
    desplazable->setFrameShape(QFrame::NoFrame);
    desplazable->setWidget(contenido);
    desplazable->setStyleSheet(QStringLiteral("QScrollArea { background: transparent; } "
                                              "QScrollArea > QWidget > QWidget { background: transparent; }"));
    principal->addWidget(desplazable, 1);

    auto *botones = new QHBoxLayout;
    botonTodas = new QPushButton(tema::icono(QStringLiteral("actualizar")), tr("Actualizar todas"), this);
    tema::marcarPrimario(botonTodas);
    botonBuscar = new QPushButton(tema::icono(QStringLiteral("buscar")), tr("Buscar de nuevo"), this);
    botones->addWidget(botonTodas);
    botones->addWidget(botonBuscar);
    botones->addStretch();
    principal->addLayout(botones);

    etiquetaEstado = new QLabel(this);
    etiquetaEstado->setWordWrap(true);
    principal->addWidget(etiquetaEstado);

    connect(botonBuscar, &QPushButton::clicked, this, &PaginaAUR::consultar);
    connect(botonTodas, &QPushButton::clicked, this, [this] {
        QStringList paquetes;
        for (const App &app : std::as_const(lista))
            if (app.estado == App::Estado::Nueva)
                paquetes << app.paquete;
        instalar(paquetes);
    });
    connect(&proceso, &ProcesoLogica::evento, this, &PaginaAUR::procesarEvento);
    connect(&proceso, &ProcesoLogica::terminado, this, &PaginaAUR::terminoConsulta);
    relojTerminal.setInterval(1000);
    connect(&relojTerminal, &QTimer::timeout, this, &PaginaAUR::vigilarTerminal);
    actualizarBotones();
}

// La primera vez que se abre la página se consulta el AUR (no al abrir el programa)
void PaginaAUR::showEvent(QShowEvent *evento)
{
    QWidget::showEvent(evento);
    if (!consultado) {
        consultado = true;
        consultar();
    }
}

void PaginaAUR::consultar()
{
    if (proceso.ocupado() || terminalAbierta())
        return;
    lista.clear();
    error.clear();
    armarLista();
    tema::mostrarEstado(etiquetaEstado, tr("Consultando el AUR…"));
    proceso.iniciar(QDir(base).filePath(QStringLiteral("Logica/AUR.sh")), {QStringLiteral("estado")});
    actualizarBotones();
}

void PaginaAUR::procesarEvento(const QString &palabra, const QString &resto)
{
    const QStringList campos = resto.split(u'\t');
    if (palabra == u"APP" && campos.size() >= 4) {
        App app;
        app.paquete = campos.at(0);
        app.nombre = campos.at(1);
        app.descripcion = campos.at(2);
        app.instalada = campos.at(3);
        lista << app;
        armarLista();
    } else if (palabra == u"AUR" && campos.size() >= 3) {
        for (App &app : lista) {
            if (app.paquete != campos.at(0))
                continue;
            app.ultima = campos.at(1);
            const QString &estado = campos.at(2);
            app.estado = estado == u"NUEVA" ? App::Estado::Nueva
                       : estado == u"AL_DIA" ? App::Estado::AlDia
                                             : App::Estado::NoInstalada;
            actualizarFila(app);
        }
    } else if (palabra == u"ERROR") {
        error = resto;
    }
}

void PaginaAUR::terminoConsulta(int codigo, bool)
{
    // Las que el AUR no devolvió (o si no hubo conexión)
    int nuevas = 0;
    for (App &app : lista) {
        if (app.estado == App::Estado::Consultando) {
            app.estado = App::Estado::SinDatos;
            actualizarFila(app);
        }
        nuevas += app.estado == App::Estado::Nueva;
    }
    if (codigo != 0)
        tema::mostrarEstado(etiquetaEstado, error.isEmpty() ? tr("No se pudo consultar el AUR.") : error, tema::Estado::Error);
    else if (nuevas > 0)
        tema::mostrarEstado(etiquetaEstado, nuevas == 1 ? tr("Hay 1 app con versión nueva.")
                                                        : tr("Hay %1 apps con versión nueva.").arg(nuevas));
    else
        tema::mostrarEstado(etiquetaEstado, tr("Todo al día."), tema::Estado::Ok);
    actualizarBotones();
}

// Vuelve a armar las tarjetas a partir de «lista»
void PaginaAUR::armarLista()
{
    // Primero se olvidan los punteros: las tarjetas viejas se borran acá abajo
    for (App &app : lista) {
        app.etiquetaEstado = nullptr;
        app.boton = nullptr;
    }
    while (layoutLista->count() > 1) {    // el último es el estirador
        QLayoutItem *item = layoutLista->takeAt(0);
        delete item->widget();
        delete item;
    }
    QWidget *contenido = layoutLista->parentWidget();
    for (int i = 0; i < lista.size(); ++i) {
        App &app = lista[i];
        auto *caja = new QFrame(contenido);
        caja->setProperty("tarjeta", true);
        auto *fila = new QHBoxLayout(caja);
        fila->setContentsMargins(14, 12, 14, 12);
        fila->setSpacing(12);
        fila->addWidget(nuevoIcono(caja), 0, Qt::AlignTop);
        auto *textos = new QVBoxLayout;
        textos->setSpacing(2);
        auto *nombre = new QLabel(QStringLiteral("<b>%1</b>").arg(app.nombre.toHtmlEscaped()), caja);
        auto *descripcion = new QLabel(app.descripcion, caja);
        descripcion->setWordWrap(true);
        descripcion->setProperty("secundario", true);
        app.etiquetaEstado = new QLabel(caja);
        app.etiquetaEstado->setWordWrap(true);
        app.etiquetaEstado->setProperty("secundario", true);
        app.etiquetaEstado->setTextInteractionFlags(Qt::TextSelectableByMouse);
        textos->addWidget(nombre);
        textos->addWidget(descripcion);
        textos->addSpacing(2);
        textos->addWidget(app.etiquetaEstado);
        app.boton = new QPushButton(caja);
        fila->addLayout(textos, 1);
        fila->addWidget(app.boton, 0, Qt::AlignVCenter);
        const QString paquete = app.paquete;
        connect(app.boton, &QPushButton::clicked, this, [this, paquete] { instalar({paquete}); });
        layoutLista->insertWidget(i, caja);
        actualizarFila(app);
    }
}

void PaginaAUR::actualizarFila(App &app)
{
    if (!app.etiquetaEstado)
        return;
    const QString instalada = app.instalada.isEmpty() ? tr("no instalada") : tr("instalada %1").arg(app.instalada);
    QString texto, accion;
    switch (app.estado) {
    case App::Estado::Consultando:
        texto = tr("%1 · consultando el AUR…").arg(instalada);
        break;
    case App::Estado::NoInstalada:
        texto = tr("No instalada · en el AUR: %1").arg(app.ultima);
        accion = tr("Instalar");
        break;
    case App::Estado::Nueva:
        texto = tr("Instalada %1 · nueva: %2").arg(app.instalada, app.ultima);
        accion = tr("Actualizar");
        break;
    case App::Estado::AlDia:
        texto = tr("Instalada %1 ✓").arg(app.instalada);
        break;
    case App::Estado::SinDatos:
        texto = tr("%1 · no se pudo ver la versión del AUR").arg(instalada);
        break;
    }
    app.etiquetaEstado->setText(texto);
    app.boton->setText(accion.isEmpty() ? tr("Al día") : accion);
    app.boton->setProperty("accion", !accion.isEmpty());
    tema::marcarPrimario(app.boton, !accion.isEmpty());
    actualizarBotones();
}

void PaginaAUR::actualizarBotones()
{
    const bool libre = !proceso.ocupado() && !terminalAbierta();
    int nuevas = 0;
    for (const App &app : std::as_const(lista)) {
        nuevas += app.estado == App::Estado::Nueva;
        if (app.boton)
            app.boton->setEnabled(libre && app.boton->property("accion").toBool());
    }
    botonTodas->setText(nuevas > 1 ? tr("Actualizar todas (%1)").arg(nuevas) : tr("Actualizar todas"));
    botonTodas->setVisible(nuevas > 1);
    botonTodas->setEnabled(libre);
    botonBuscar->setEnabled(libre);
}

void PaginaAUR::instalar(const QStringList &paquetes)
{
    if (paquetes.isEmpty() || proceso.ocupado() || terminalAbierta())
        return;
    // En konsole o, si no está, en otra terminal (Common/Terminal.sh). --esperar (konsole --nofork):
    // el proceso es la ventana misma, así se sabe cuándo se cierra
    const QString cual = terminal::disponible(base);
    if (cual.isEmpty()) {
        tema::mostrarEstado(etiquetaEstado, terminal::sinTerminal(), tema::Estado::Error);
        return;
    }
    const QStringList comando = QStringList{QStringLiteral("bash"), QDir(base).filePath(QStringLiteral("General/AUR-instalar.sh"))}
                                + paquetes;
    if (!QProcess::startDetached(QStringLiteral("bash"), terminal::argumentos(base, comando, true), QDir::homePath(), &pidTerminal)
        || pidTerminal <= 0) {
        pidTerminal = 0;
        tema::mostrarEstado(etiquetaEstado, tr("No se pudo abrir la terminal (%1).").arg(cual), tema::Estado::Error);
        return;
    }
    relojTerminal.start();
    tema::mostrarEstado(etiquetaEstado, tr("Instalando en la terminal… Al cerrarla se vuelven a ver las versiones."));
    actualizarBotones();
}

void PaginaAUR::vigilarTerminal()
{
    if (pidTerminal > 0 && ::kill(static_cast<pid_t>(pidTerminal), 0) == 0)
        return;
    relojTerminal.stop();
    pidTerminal = 0;
    actualizarBotones();
    consultar();
}
