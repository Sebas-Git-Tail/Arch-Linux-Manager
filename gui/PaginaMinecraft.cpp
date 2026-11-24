#include "PaginaMinecraft.h"
#include "AsistenteMinecraft.h"
#include "PestanasMinecraft.h"
#include "Tema.h"
#include "VistasMinecraft.h"

#include <QDate>
#include <QDir>
#include <QFileDialog>
#include <QFontDatabase>
#include <QFrame>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QInputDialog>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QLocale>
#include <QMenu>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QProgressBar>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollBar>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QTreeWidget>
#include <QVBoxLayout>

// Los servidores se identifican por su ruta dentro de Servidores/ (<grupo>/<versión>/<servidor>) y en los
// mensajes se muestran como «26.1.2 SMP-1 (Amigos)».
static QString etiqueta(const QString &servidor)
{
    const int barra = servidor.indexOf(u'/');
    if (barra < 0)
        return servidor;
    return QStringLiteral("%1 (%2)").arg(servidor.section(u'/', -1), servidor.left(barra));
}

static QStringList etiquetas(const QStringList &servidores)
{
    QStringList lista;
    for (const QString &s : servidores)
        lista << etiqueta(s);
    return lista;
}

static QString nombreTipo(const QString &tipo)
{
    if (tipo == u"forge") return QStringLiteral("Forge");
    if (tipo == u"fabric") return QStringLiteral("Fabric");
    if (tipo == u"vanilla") return QStringLiteral("Vanilla");
    return QStringLiteral("Paper");
}

static QFrame *separador()
{
    auto *linea = new QFrame;
    linea->setFrameShape(QFrame::HLine);
    linea->setStyleSheet(QStringLiteral("color:%1;").arg(tema::colores().borde.name()));
    return linea;
}

// Páginas de la vista del servidor (el orden de la lista de la izquierda)
enum Pagina { PaginaConsola, PaginaPlugins, PaginaJugadores, PaginaOpciones, PaginaRespaldos };

PaginaMinecraft::PaginaMinecraft(const QString &logica, QWidget *parent)
    : QWidget(parent), script(QDir(logica).filePath(QStringLiteral("Minecraft.sh")))
{
    setWindowTitle(tr("Panel de Minecraft"));
    pestanaJugadores = new PestanaJugadores(script, this);
    pestanaOpciones = new PestanaOpciones(script, this);
    pestanaRespaldos = new PestanaRespaldos(script, this);

    vistas = new QStackedWidget;
    vistas->addWidget(armarVistaServidores());
    vistas->addWidget(armarVistaServidor());

    // Abajo: lo que está pasando (con Cancelar), los avisos y el resumen del elegido (como la barra de Prism)
    etiquetaEstado = new QLabel;
    etiquetaEstado->setWordWrap(true);
    barraProgreso = new QProgressBar;
    barraProgreso->setMaximumWidth(180);
    barraProgreso->setTextVisible(false);
    barraProgreso->hide();
    botonCancelar = new QPushButton(tr("Cancelar"));
    botonCancelar->hide();
    botonAvisos = new QPushButton(tema::icono(QStringLiteral("reporte")), tr("Avisos"));
    botonAvisos->setProperty("plano", true);
    botonAvisos->setCheckable(true);
    resumen = new QLabel;
    resumen->setStyleSheet(QStringLiteral("color:%1;").arg(tema::colores().texto3.name()));
    registroAvisos = new QPlainTextEdit;
    registroAvisos->setReadOnly(true);
    registroAvisos->setMaximumHeight(130);
    registroAvisos->setPlaceholderText(tr("Avisos y errores"));
    registroAvisos->hide();
    auto *barraAbajo = new QHBoxLayout;
    barraAbajo->addWidget(etiquetaEstado, 1);
    barraAbajo->addWidget(barraProgreso);
    barraAbajo->addWidget(botonCancelar);
    barraAbajo->addWidget(botonAvisos);
    barraAbajo->addWidget(resumen);

    auto *capa = new QVBoxLayout(this);
    capa->setContentsMargins(0, 0, 0, 0);
    capa->addWidget(vistas, 1);
    capa->addWidget(registroAvisos);
    capa->addWidget(separador());
    capa->addLayout(barraAbajo);

    temporizadorJugadores.setInterval(10000);
    connect(&temporizadorJugadores, &QTimer::timeout, this, &PaginaMinecraft::consultarJugadores);
    connect(botonCancelar, &QPushButton::clicked, &accion, &ProcesoLogica::cancelar);
    connect(botonAvisos, &QPushButton::toggled, this, [this](bool ver) {
        registroAvisos->setVisible(ver);
        avisosSinVer = 0;
        botonAvisos->setText(tr("Avisos"));
    });
    for (PestanaServidor *p : pestanas())
        connect(p, &PestanaServidor::accion, this, [this](const QStringList &argumentos, const QString &estado, const QByteArray &entrada) {
            if (!accion.ocupado())
                ejecutar(argumentos, estado, entrada);
        });

    connect(&consulta, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoConsulta);
    connect(&consulta, &ProcesoLogica::terminado, this, &PaginaMinecraft::terminoConsulta);
    connect(&plugins, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoPlugins);
    connect(&plugins, &ProcesoLogica::terminado, this, [this](int codigo, bool cancelado) {
        if (cancelado)
            return;
        const QString clase = pluginsSonMods ? tr("Mods") : tr("Plugins");
        if (arbolPlugins->topLevelItemCount() == 0 && codigo == 0)
            tema::mostrarEstado(estadoPlugins, pluginsSonMods ? tr("No tiene mods.") : tr("No tiene plugins."));
        else
            tema::mostrarEstado(estadoPlugins, pluginsNuevos > 0 ? tr("%1 con versión nueva en Modrinth.").arg(pluginsNuevos)
                                                                 : tr("Todos al día (los que están en Modrinth)."),
                                pluginsNuevos > 0 ? tema::Estado::Aviso : tema::Estado::Neutro);
        listaPaginas->item(PaginaPlugins)->setText(pluginsNuevos > 0 ? tr("%1 (%2)").arg(clase).arg(pluginsNuevos) : clase);
        if (paginas->currentIndex() == PaginaPlugins)
            tituloPagina->setText(clase);
        actualizarBotones();
    });
    connect(&accion, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoAccion);
    connect(&accion, &ProcesoLogica::terminado, this, &PaginaMinecraft::terminoAccion);
    connect(&registro, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoRegistro);
    connect(&conectados, &ProcesoLogica::evento, this, &PaginaMinecraft::eventoJugadores);
    connect(&envio, &ProcesoLogica::evento, this, [this](const QString &palabra, const QString &resto) {
        if (palabra == u"ERROR")
            tema::mostrarEstado(etiquetaEstado, resto, tema::Estado::Error);
        else if (palabra == u"LISTO" && !resto.startsWith(u"Enviado"))
            tema::mostrarEstado(etiquetaEstado, resto, tema::Estado::Ok);
    });
    connect(&envio, &ProcesoLogica::terminado, this, [this] { actualizarBotones(); });
    mostrarElegido();
}

PaginaMinecraft::~PaginaMinecraft()
{
    // tail -F no termina solo: se corta todo su grupo de procesos
    registro.cancelarYEsperar();
    conectados.cancelarYEsperar();
    envio.cancelarYEsperar();
}

// --- Vista «Servidores» (la ventana principal de Prism) ----------------------------------------------------------

QWidget *PaginaMinecraft::armarVistaServidores()
{
    const tema::Colores &c = tema::colores();
    auto *vista = new QWidget;

    // Barra de arriba
    botonCrear = botonAccion(QStringLiteral("agregar"), c.ok, tr("Crear servidor"));
    botonCarpetas = botonAccion(QStringLiteral("carpeta"), c.aviso, tr("Carpetas"));
    auto *menuCarpetas = new QMenu(botonCarpetas);
    menuCarpetas->addAction(tema::icono(QStringLiteral("carpeta")), tr("Servidores"), this, [this] {
        ejecutar({QStringLiteral("abrir-carpeta"), QStringLiteral("servidores")}, tr("Abriendo la carpeta…"));
    });
    menuCarpetas->addAction(tema::icono(QStringLiteral("respaldo")), tr("Respaldos"), this, [this] {
        ejecutar({QStringLiteral("abrir-carpeta"), QStringLiteral("respaldos")}, tr("Abriendo la carpeta…"));
    });
    botonCarpetas->setMenu(menuCarpetas);
    botonActualizarLista = botonAccion(QStringLiteral("sincronizar"), c.acento, tr("Actualizar"));
    botonPaper = botonAccion(QStringLiteral("descargar"), c.acento, tr("Actualizar Paper"));
    botonPaper->setToolTip(tr("La última compilación estable de Paper (de su misma versión) para los servidores elegidos"));
    botonJugar = botonAccion(QStringLiteral("juego"), c.ok, tr("Jugar"));
    botonJugar->setToolTip(tr("Abrir una instancia de Prism Launcher (entra sola al servidor de casa)"));
    menuJugar = new QMenu(botonJugar);
    botonJugar->setMenu(menuJugar);
    for (QPushButton *b : {botonCrear, botonCarpetas, botonActualizarLista, botonPaper, botonJugar})
        b->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    auto *barra = new QHBoxLayout;
    barra->setContentsMargins(0, 0, 0, 0);
    barra->addWidget(botonCrear);
    barra->addWidget(botonCarpetas);
    barra->addWidget(botonActualizarLista);
    barra->addWidget(botonPaper);
    barra->addStretch();
    barra->addWidget(botonJugar);

    grilla = new GrillaServidores;

    // A la derecha: el elegido y su columna de acciones
    auto *panel = new QWidget;
    panel->setFixedWidth(240);
    iconoElegido = new QLabel;
    iconoElegido->setAlignment(Qt::AlignCenter);
    iconoElegido->setMinimumHeight(72);
    nombreElegido = new QLabel;
    nombreElegido->setAlignment(Qt::AlignCenter);
    nombreElegido->setWordWrap(true);
    QFont grande = nombreElegido->font();
    grande.setBold(true);
    grande.setPointSizeF(grande.pointSizeF() * 1.15);
    nombreElegido->setFont(grande);
    tipoElegidoEtiqueta = new QLabel;
    tipoElegidoEtiqueta->setAlignment(Qt::AlignCenter);
    tipoElegidoEtiqueta->setWordWrap(true);
    tipoElegidoEtiqueta->setStyleSheet(QStringLiteral("color:%1;").arg(c.texto2.name()));
    estadoElegido = new QLabel;
    estadoElegido->setAlignment(Qt::AlignCenter);
    estadoElegido->setWordWrap(true);

    botonIniciar = botonAccion(QStringLiteral("reproducir"), c.ok, tr("Iniciar"));
    botonDetener = botonAccion(QStringLiteral("cerrar"), c.error, tr("Detener"));
    botonReiniciar = botonAccion(QStringLiteral("repetir"), c.aviso, tr("Reiniciar"));
    botonAdministrar = botonAccion(QStringLiteral("editar"), c.acento, tr("Administrar"));
    botonAdministrar->setToolTip(tr("Consola, plugins o mods, jugadores, opciones y respaldos (o doble clic en el servidor)"));
    botonCarpeta = botonAccion(QStringLiteral("carpeta"), c.aviso, tr("Carpeta"));
    botonCambiarVersion = botonAccion(QStringLiteral("actualizar"), c.acento, tr("Cambiar versión…"));
    botonRam = botonAccion(QStringLiteral("ajustes"), c.texto2, tr("Memoria…"));
    botonReiniciarMundo = botonAccion(QStringLiteral("borrar"), c.error, tr("Reiniciar mundo…"));
    accionesUno = new QWidget;
    auto *capaUno = new QVBoxLayout(accionesUno);
    capaUno->setContentsMargins(0, 0, 0, 0);
    capaUno->setSpacing(1);
    for (QPushButton *b : {botonIniciar, botonDetener, botonReiniciar})
        capaUno->addWidget(b);
    capaUno->addWidget(separador());
    for (QPushButton *b : {botonAdministrar, botonCarpeta, botonCambiarVersion, botonRam, botonReiniciarMundo})
        capaUno->addWidget(b);

    // Varios elegidos (Ctrl/Shift): lo que se puede hacer a todos juntos
    accionesVarios = new QWidget;
    etiquetaVarios = new QLabel;
    etiquetaVarios->setWordWrap(true);
    botonInstalarVarios = botonAccion(QStringLiteral("agregar"), c.ok, tr("Instalar plugin o mod…"));
    auto *botonPaperVarios = botonAccion(QStringLiteral("descargar"), c.acento, tr("Actualizar Paper"));
    auto *capaVarios = new QVBoxLayout(accionesVarios);
    capaVarios->setContentsMargins(0, 0, 0, 0);
    capaVarios->addWidget(etiquetaVarios);
    capaVarios->addWidget(separador());
    capaVarios->addWidget(botonPaperVarios);
    capaVarios->addWidget(botonInstalarVarios);

    auto *capaPanel = new QVBoxLayout(panel);
    capaPanel->setContentsMargins(8, 8, 4, 8);
    capaPanel->addWidget(iconoElegido);
    capaPanel->addWidget(nombreElegido);
    capaPanel->addWidget(tipoElegidoEtiqueta);
    capaPanel->addWidget(estadoElegido);
    capaPanel->addSpacing(6);
    capaPanel->addWidget(separador());
    capaPanel->addWidget(accionesUno);
    capaPanel->addWidget(accionesVarios);
    capaPanel->addStretch();

    auto *lineaVertical = new QFrame;
    lineaVertical->setFrameShape(QFrame::VLine);
    lineaVertical->setStyleSheet(QStringLiteral("color:%1;").arg(c.borde.name()));
    auto *cuerpo = new QHBoxLayout;
    cuerpo->setContentsMargins(0, 0, 0, 0);
    cuerpo->addWidget(grilla, 1);
    cuerpo->addWidget(lineaVertical);
    cuerpo->addWidget(panel);
    auto *capa = new QVBoxLayout(vista);
    capa->setContentsMargins(0, 0, 0, 0);
    capa->addLayout(barra);
    capa->addWidget(separador());
    capa->addLayout(cuerpo, 1);

    connect(botonCrear, &QPushButton::clicked, this, &PaginaMinecraft::crearServidor);
    connect(botonActualizarLista, &QPushButton::clicked, this, &PaginaMinecraft::consultar);
    connect(botonPaper, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPaper);
    connect(botonPaperVarios, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPaper);
    connect(botonInstalarVarios, &QPushButton::clicked, this, [this] { instalarPlugin(true); });
    connect(botonIniciar, &QPushButton::clicked, this, &PaginaMinecraft::iniciar);
    connect(botonDetener, &QPushButton::clicked, this, &PaginaMinecraft::detener);
    connect(botonReiniciar, &QPushButton::clicked, this, &PaginaMinecraft::reiniciar);
    connect(botonAdministrar, &QPushButton::clicked, this, [this] { abrirServidor(servidorElegido()); });
    connect(botonCarpeta, &QPushButton::clicked, this, &PaginaMinecraft::abrirCarpeta);
    connect(botonCambiarVersion, &QPushButton::clicked, this, &PaginaMinecraft::cambiarVersion);
    connect(botonRam, &QPushButton::clicked, this, &PaginaMinecraft::cambiarRam);
    connect(botonReiniciarMundo, &QPushButton::clicked, this, &PaginaMinecraft::reiniciarMundo);
    connect(grilla, &GrillaServidores::cambioSeleccion, this, [this] {
        mostrarElegido();
        actualizarPestanas();
        if (servidorElegido() != pluginsDe)
            consultarPlugins();
        if (servidorElegido() != consolaDe)
            verConsola();
    });
    connect(grilla, &GrillaServidores::abrir, this, &PaginaMinecraft::abrirServidor);
    return vista;
}

// --- Vista «Servidor» (la ventana «Editar» de Prism) ----------------------------------------------------------

QWidget *PaginaMinecraft::armarVistaServidor()
{
    const tema::Colores &c = tema::colores();
    auto *vista = new QWidget;
    auto *botonVolver = botonAccion(QStringLiteral("volver"), c.texto2, tr("Servidores"));
    botonVolver->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    iconoCabecera = new QLabel;
    tituloServidor = new QLabel;
    QFont grande = tituloServidor->font();
    grande.setBold(true);
    grande.setPointSizeF(grande.pointSizeF() * 1.15);
    tituloServidor->setFont(grande);
    estadoServidor = new QLabel;
    auto *cabecera = new QHBoxLayout;
    cabecera->addWidget(botonVolver);
    cabecera->addSpacing(8);
    cabecera->addWidget(iconoCabecera);
    cabecera->addWidget(tituloServidor);
    cabecera->addSpacing(10);
    cabecera->addWidget(estadoServidor, 1);

    // Páginas a la izquierda, con íconos de colores
    listaPaginas = new QListWidget;
    listaPaginas->setFixedWidth(180);
    listaPaginas->setIconSize(QSize(24, 24));
    listaPaginas->setFrameShape(QFrame::NoFrame);
    listaPaginas->setStyleSheet(QStringLiteral("QListWidget { background: transparent; border: none; }"
                                               "QListWidget::item { padding: 7px 6px; border-radius: 6px; }"));
    const QList<QPair<QString, QPair<QString, QColor>>> lista = {
        {tr("Consola"), {QStringLiteral("terminal"), c.texto2}}, {tr("Plugins"), {QStringLiteral("bloque"), c.error}},
        {tr("Jugadores"), {QStringLiteral("cuenta"), c.acento}}, {tr("Opciones"), {QStringLiteral("ajustes"), c.aviso}},
        {tr("Respaldos"), {QStringLiteral("respaldo"), c.ok}}};
    for (const auto &p : lista)
        new QListWidgetItem(tema::icono(p.second.first, p.second.second), p.first, listaPaginas);

    tituloPagina = new QLabel;
    QFont titulo = tituloPagina->font();
    titulo.setBold(true);
    titulo.setPointSizeF(titulo.pointSizeF() * 1.2);
    tituloPagina->setFont(titulo);
    paginas = new QStackedWidget;
    paginas->addWidget(armarPaginaConsola());
    paginas->addWidget(armarPaginaPlugins());
    paginas->addWidget(pestanaJugadores);
    paginas->addWidget(pestanaOpciones);
    paginas->addWidget(pestanaRespaldos);
    auto *derecha = new QVBoxLayout;
    derecha->addWidget(tituloPagina);
    derecha->addWidget(paginas, 1);

    // Abajo, como «Lanzar / Terminar / Cerrar» de Prism
    botonIniciar2 = botonAccion(QStringLiteral("reproducir"), c.ok, tr("Iniciar"));
    botonDetener2 = botonAccion(QStringLiteral("cerrar"), c.error, tr("Detener"));
    botonReiniciar2 = botonAccion(QStringLiteral("repetir"), c.aviso, tr("Reiniciar"));
    auto *botonCerrar = new QPushButton(tr("Volver a los servidores"));
    auto *pie = new QHBoxLayout;
    pie->addStretch();
    for (QPushButton *b : {botonIniciar2, botonDetener2, botonReiniciar2}) {
        b->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
        pie->addWidget(b);
    }
    pie->addSpacing(12);
    pie->addWidget(botonCerrar);
    derecha->addLayout(pie);

    auto *lineaVertical = new QFrame;
    lineaVertical->setFrameShape(QFrame::VLine);
    lineaVertical->setStyleSheet(QStringLiteral("color:%1;").arg(c.borde.name()));
    auto *cuerpo = new QHBoxLayout;
    cuerpo->addWidget(listaPaginas);
    cuerpo->addWidget(lineaVertical);
    cuerpo->addLayout(derecha, 1);
    auto *capa = new QVBoxLayout(vista);
    capa->setContentsMargins(0, 0, 0, 0);
    capa->addLayout(cabecera);
    capa->addWidget(separador());
    capa->addLayout(cuerpo, 1);

    connect(botonVolver, &QPushButton::clicked, this, &PaginaMinecraft::volverALista);
    connect(botonCerrar, &QPushButton::clicked, this, &PaginaMinecraft::volverALista);
    connect(botonIniciar2, &QPushButton::clicked, this, &PaginaMinecraft::iniciar);
    connect(botonDetener2, &QPushButton::clicked, this, &PaginaMinecraft::detener);
    connect(botonReiniciar2, &QPushButton::clicked, this, &PaginaMinecraft::reiniciar);
    connect(listaPaginas, &QListWidget::currentRowChanged, this, [this](int fila) {
        if (fila < 0)
            return;
        paginas->setCurrentIndex(fila);
        tituloPagina->setText(listaPaginas->item(fila)->text());
    });
    listaPaginas->setCurrentRow(PaginaConsola);
    return vista;
}

// Columna de acciones a la derecha de una tabla (como las páginas de Prism)
static QVBoxLayout *columnaAcciones(QHBoxLayout *fila, QWidget *principal)
{
    auto *columna = new QVBoxLayout;
    columna->setSpacing(1);
    fila->addWidget(principal, 1);
    auto *contenedor = new QWidget;
    contenedor->setFixedWidth(210);
    contenedor->setLayout(columna);
    fila->addWidget(contenedor);
    return columna;
}

QWidget *PaginaMinecraft::armarPaginaConsola()
{
    const tema::Colores &c = tema::colores();
    auto *pagina = new QWidget;
    etiquetaJugadores = new QLabel;
    etiquetaJugadores->setWordWrap(true);
    textoConsola = new QPlainTextEdit;
    textoConsola->setReadOnly(true);
    textoConsola->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    textoConsola->setMaximumBlockCount(5000);
    editComando = new QLineEdit;
    editComando->setPlaceholderText(tr("Comando (ej. say hola, time set day, list). Flechas: los anteriores"));
    editComando->setProperty("ayuda", editComando->placeholderText());
    editComando->installEventFilter(this);
    botonEnviar = new QPushButton(tema::icono(QStringLiteral("siguiente")), tr("Enviar"));
    botonTerminal = botonAccion(QStringLiteral("terminal"), c.texto2, tr("Abrir en una terminal"));
    botonTerminal->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    auto *arriba = new QHBoxLayout;
    arriba->addWidget(etiquetaJugadores, 1);
    arriba->addWidget(botonTerminal);
    auto *abajo = new QHBoxLayout;
    abajo->addWidget(editComando, 1);
    abajo->addWidget(botonEnviar);
    auto *capa = new QVBoxLayout(pagina);
    capa->setContentsMargins(0, 0, 0, 0);
    capa->addLayout(arriba);
    capa->addWidget(textoConsola, 1);
    capa->addLayout(abajo);
    connect(botonEnviar, &QPushButton::clicked, this, &PaginaMinecraft::enviarComando);
    connect(editComando, &QLineEdit::returnPressed, this, &PaginaMinecraft::enviarComando);
    connect(botonTerminal, &QPushButton::clicked, this, &PaginaMinecraft::abrirTerminal);
    return pagina;
}

QWidget *PaginaMinecraft::armarPaginaPlugins()
{
    const tema::Colores &c = tema::colores();
    auto *pagina = new QWidget;
    arbolPlugins = new QTreeWidget;
    arbolPlugins->setRootIsDecorated(false);
    arbolPlugins->setHeaderLabels({tr("Plugin"), tr("Versión"), tr("Nueva"), tr("Estado")});
    arbolPlugins->header()->setSectionResizeMode(0, QHeaderView::Stretch);
    for (int i = 1; i < 4; ++i)
        arbolPlugins->header()->setSectionResizeMode(i, QHeaderView::ResizeToContents);
    estadoPlugins = new QLabel;
    estadoPlugins->setWordWrap(true);
    auto *izquierda = new QWidget;
    auto *capaIzq = new QVBoxLayout(izquierda);
    capaIzq->setContentsMargins(0, 0, 0, 0);
    capaIzq->addWidget(arbolPlugins, 1);
    capaIzq->addWidget(estadoPlugins);
    botonPlugin = botonAccion(QStringLiteral("agregar"), c.ok, tr("Instalar…"));
    botonPlugin->setToolTip(tr("Un plugin (Paper) o mod (Fabric/Forge) de Modrinth por nombre o URL, con sus dependencias"));
    botonBuscarPlugins = botonAccion(QStringLiteral("buscar"), c.acento, tr("Ver versiones"));
    botonBuscarPlugins->setToolTip(tr("Consultar en Modrinth si hay versiones nuevas"));
    botonActualizarPlugins = botonAccion(QStringLiteral("descargar"), c.acento, tr("Actualizar"));
    botonActualizarPlugins->setToolTip(tr("Bajar las versiones nuevas (las anteriores quedan en Respaldos)"));
    botonPack = botonAccion(QStringLiteral("paquete"), c.aviso, tr("Pack para jugadores…"));
    botonPack->setToolTip(tr("Un .mrpack con los mods que necesitan los jugadores (se abre con Prism Launcher o la app de Modrinth)"));
    botonCarpetaPlugins = botonAccion(QStringLiteral("carpeta"), c.aviso, tr("Ver carpeta"));
    auto *fila = new QHBoxLayout(pagina);
    fila->setContentsMargins(0, 0, 0, 0);
    QVBoxLayout *columna = columnaAcciones(fila, izquierda);
    columna->addWidget(botonPlugin);
    columna->addWidget(separador());
    columna->addWidget(botonBuscarPlugins);
    columna->addWidget(botonActualizarPlugins);
    columna->addWidget(separador());
    columna->addWidget(botonPack);
    columna->addStretch();
    columna->addWidget(botonCarpetaPlugins);
    connect(botonPlugin, &QPushButton::clicked, this, [this] { instalarPlugin(false); });
    connect(botonBuscarPlugins, &QPushButton::clicked, this, &PaginaMinecraft::consultarPlugins);
    connect(botonActualizarPlugins, &QPushButton::clicked, this, &PaginaMinecraft::actualizarPlugins);
    connect(botonPack, &QPushButton::clicked, this, &PaginaMinecraft::packJugadores);
    connect(botonCarpetaPlugins, &QPushButton::clicked, this, &PaginaMinecraft::abrirCarpeta);
    return pagina;
}

void PaginaMinecraft::abrirServidor(const QString &ruta)
{
    if (ruta.isEmpty())
        return;
    if (grilla->elegido() != ruta)
        grilla->elegir(ruta);
    vistas->setCurrentIndex(1);
    mostrarElegido();
}

void PaginaMinecraft::volverALista()
{
    vistas->setCurrentIndex(0);
}

// El elegido en todos lados: panel de la derecha, cabecera de la vista del servidor y resumen de abajo
void PaginaMinecraft::mostrarElegido()
{
    const tema::Colores &c = tema::colores();
    const QStringList seleccionados = grilla->seleccionados();
    const ServidorMc *s = grilla->datos(servidorElegido());
    const bool varios = seleccionados.size() > 1;
    accionesUno->setVisible(s && !varios);
    accionesVarios->setVisible(varios);
    if (varios) {
        iconoElegido->setPixmap(tema::pixmap(QStringLiteral("servidor"), 56, c.texto2));
        nombreElegido->setText(tr("%1 servidores").arg(seleccionados.size()));
        tipoElegidoEtiqueta->setText(QString());
        estadoElegido->setText(QString());
        etiquetaVarios->setText(etiquetas(seleccionados).join(u'\n'));
    } else if (s) {
        iconoElegido->setPixmap(iconoServidor(s->tipo, s->icono, s->encendido, 64));
        nombreElegido->setText(s->nombre());
        tipoElegidoEtiqueta->setText(QStringLiteral("%1 %2 · %3").arg(nombreTipo(s->tipo), s->version,
                                                                       s->grupo().isEmpty() ? tr("sin grupo") : s->grupo()));
        const QString estado = !s->encendido ? tr("Apagado")
                               : s->apaga.isEmpty() ? tr("● Encendido")
                                                    : tr("● Encendido · sin jugadores, se apaga en %1 min").arg(s->apaga);
        tema::mostrarEstado(estadoElegido, estado, s->encendido ? tema::Estado::Ok : tema::Estado::Neutro);
    } else {
        iconoElegido->setPixmap(tema::pixmap(QStringLiteral("servidor"), 56, c.texto3));
        nombreElegido->setText(tr("Ningún servidor elegido"));
        tipoElegidoEtiqueta->setText(tr("Tocá uno de la lista (doble clic para administrarlo)."));
        estadoElegido->setText(QString());
    }
    if (s) {
        iconoCabecera->setPixmap(iconoServidor(s->tipo, s->icono, s->encendido, 32));
        tituloServidor->setText(etiqueta(s->ruta));
        tema::mostrarEstado(estadoServidor, QStringLiteral("%1 %2 · %3").arg(nombreTipo(s->tipo), s->version,
                                                                               s->encendido ? tr("encendido") : tr("apagado")),
                            s->encendido ? tema::Estado::Ok : tema::Estado::Neutro);
        resumen->setText(tr("%1: %2 %3 · mundo %4 · usado %5 · hasta %6 de RAM")
                             .arg(s->nombre(), nombreTipo(s->tipo), s->version, s->mundo, s->ultimo, s->ram));
    } else {
        resumen->setText(QString());
        if (vistas->currentIndex() == 1)
            volverALista();
    }
    actualizarBotones();
}

// --- Visibilidad --------------------------------------------------------------------------------------------

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
    if (objeto == editComando && evento->type() == QEvent::KeyPress && !historial.isEmpty()) {
        const int tecla = static_cast<QKeyEvent *>(evento)->key();
        if (tecla == Qt::Key_Up || tecla == Qt::Key_Down) {
            posHistorial = qBound(0, posHistorial + (tecla == Qt::Key_Up ? -1 : 1), int(historial.size()));
            editComando->setText(posHistorial < historial.size() ? historial.at(posHistorial) : QString());
            return true;
        }
    }
    return QWidget::eventFilter(objeto, evento);
}

// --- Consola -------------------------------------------------------------------------------------------------

void PaginaMinecraft::verConsola()
{
    registro.cancelarYEsperar();
    textoConsola->clear();
    consola = Consola::Nada;
    jugadoresConectados = 0;
    consolaDe = servidorElegido(&consolaEncendido);
    if (consolaDe.isEmpty()) {
        etiquetaJugadores->setText(tr("Elegí un servidor para ver su consola."));
    } else if (isVisible()) {
        etiquetaJugadores->setText(consolaEncendido ? tr("Consultando quién está conectado…")
                                                    : tr("%1 está apagado: se ve lo último que registró.").arg(etiqueta(consolaDe)));
        registro.iniciar(script, {QStringLiteral("registro"), consolaDe});
        consultarJugadores();
    }
    actualizarBotones();
}

void PaginaMinecraft::eventoRegistro(const QString &palabra, const QString &resto)
{
    if (palabra == u"LINEA") {
        QScrollBar *barra = textoConsola->verticalScrollBar();
        const bool alFinal = barra->value() >= barra->maximum() - 4;    // si subió a leer, no se lo mueve
        textoConsola->appendPlainText(resto);
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
        etiquetaJugadores->setText(resto);
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
        etiquetaJugadores->setText(tr("Nadie conectado (entran hasta %1).").arg(c.at(1)));
        return;
    }
    QString lista = nombres.join(QStringLiteral(", "));
    if (nombres.size() < jugadoresConectados)
        lista += (lista.isEmpty() ? QString() : QStringLiteral(" ")) + tr("y %1 más").arg(jugadoresConectados - nombres.size());
    etiquetaJugadores->setText(tr("Conectados (%1 de %2): %3").arg(jugadoresConectados).arg(c.at(1), lista));
}

void PaginaMinecraft::enviarComando()
{
    const QString texto = editComando->text().trimmed();
    if (texto.isEmpty() || envio.ocupado() || consola != Consola::Comandos)
        return;
    if (historial.isEmpty() || historial.constLast() != texto)
        historial << texto;
    posHistorial = historial.size();
    editComando->clear();
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

// --- Lista de servidores -------------------------------------------------------------------------------------

void PaginaMinecraft::consultar()
{
    if (consulta.ocupado())
        return;
    grilla->empezar();
    paso = Paso::Servidores;
    consulta.iniciar(script, {QStringLiteral("servidores")});
}

void PaginaMinecraft::eventoConsulta(const QString &palabra, const QString &resto)
{
    if (palabra == u"SERVIDOR") {
        // SERVIDOR estado<tab>nombre<tab>tipo<tab>versión<tab>tamaño<tab>último uso<tab>RAM<tab>jar[<tab>se apaga en<tab>ícono]
        const QStringList c = resto.split(u'\t');
        if (c.size() < 8)
            return;
        ServidorMc s;
        s.encendido = c.at(0) == u"ENCENDIDO";
        s.ruta = c.at(1);
        s.tipo = c.at(2);
        s.version = c.at(3);
        s.mundo = c.at(4);
        s.ultimo = c.at(5);
        const QDate fecha = QDate::fromString(s.ultimo, Qt::ISODate);
        if (fecha.isValid())
            s.ultimo = fecha == QDate::currentDate() ? tr("hoy") : QLocale().toString(fecha, QLocale::ShortFormat);
        else if (s.ultimo == u"-")
            s.ultimo = tr("nunca");
        s.ram = c.at(6);
        s.jar = c.at(7);
        s.apaga = c.value(8);
        s.icono = c.value(9);
        grilla->agregar(s);
    } else if (palabra == u"INSTANCIA") {
        menuJugar->addAction(tema::icono(QStringLiteral("juego")), resto, this, [this, resto] {
            ejecutar({QStringLiteral("prism"), resto}, tr("Abriendo %1 en Prism Launcher…").arg(resto));
        });
    }
}

// Después de los servidores, la primera vez, las instancias de Prism (no cambian mientras el
// programa está abierto)
void PaginaMinecraft::terminoConsulta()
{
    if (paso == Paso::Servidores) {
        grilla->terminar();
        mostrarElegido();
        // Si el elegido se prendió o se apagó, la consola vuelve a empezar (cambia si acepta comandos)
        if (isVisible()) {
            bool encendido = false;
            const QString servidor = servidorElegido(&encendido);
            if (servidor != consolaDe || encendido != consolaEncendido)
                verConsola();
        }
    }
    if (paso == Paso::Servidores && primeraVez) {
        paso = Paso::Instancias;
        consulta.iniciar(script, {QStringLiteral("instancias")});
        return;
    }
    primeraVez = false;
    actualizarPestanas();
    actualizarBotones();
}

QString PaginaMinecraft::servidorElegido(bool *encendido) const
{
    const QString ruta = grilla->elegido();
    if (encendido) {
        const ServidorMc *s = grilla->datos(ruta);
        *encendido = s && s->encendido;
    }
    return ruta;
}

QString PaginaMinecraft::tipoElegido() const
{
    const ServidorMc *s = grilla->datos(grilla->elegido());
    return s ? s->tipo : QString();
}

// --- Plugins / mods ------------------------------------------------------------------------------------------

void PaginaMinecraft::consultarPlugins()
{
    plugins.cancelarYEsperar();
    arbolPlugins->clear();
    pluginsNuevos = 0;
    pluginsDe = servidorElegido();
    const QString tipo = tipoElegido();
    pluginsSonMods = tipo == u"fabric" || tipo == u"forge";
    const QString clase = pluginsSonMods ? tr("Mods") : tr("Plugins");
    arbolPlugins->setHeaderLabels({pluginsSonMods ? tr("Mod") : tr("Plugin"), tr("Versión"), tr("Nueva"), tr("Estado")});
    listaPaginas->item(PaginaPlugins)->setText(clase);
    listaPaginas->item(PaginaPlugins)->setHidden(tipo == u"vanilla");
    if (paginas->currentIndex() == PaginaPlugins)
        tituloPagina->setText(clase);
    if (pluginsDe.isEmpty() || tipo == u"vanilla") {
        tema::mostrarEstado(estadoPlugins, tipo == u"vanilla" ? tr("Vanilla no usa plugins ni mods.") : QString());
        actualizarBotones();
        return;
    }
    tema::mostrarEstado(estadoPlugins, tr("Consultando Modrinth…"));
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
    auto *item = new QTreeWidgetItem(arbolPlugins);
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

// --- Botones -------------------------------------------------------------------------------------------------

void PaginaMinecraft::actualizarBotones()
{
    bool encendido = false;
    const bool hay = !servidorElegido(&encendido).isEmpty();
    const bool libre = !accion.ocupado();
    for (QPushButton *b : {botonIniciar, botonIniciar2})
        b->setEnabled(libre && hay && !encendido);
    for (QPushButton *b : {botonDetener, botonDetener2, botonReiniciar, botonReiniciar2})
        b->setEnabled(libre && hay && encendido);
    botonPaper->setEnabled(libre && hay);
    botonCrear->setEnabled(libre);
    botonJugar->setEnabled(libre && !menuJugar->isEmpty());
    botonCarpetas->setEnabled(libre);
    botonAdministrar->setEnabled(hay);
    botonCarpeta->setEnabled(hay);
    botonRam->setEnabled(libre && hay);
    botonReiniciarMundo->setEnabled(libre && hay && !encendido);
    botonCambiarVersion->setEnabled(libre && hay && !encendido);
    botonCambiarVersion->setToolTip(encendido ? tr("Detenelo antes de cambiar la versión")
                                              : tr("Otro software o versión (o actualizar el cargador de Fabric/Forge), guardando el mundo antes"));
    botonReiniciarMundo->setToolTip(encendido ? tr("Detenelo antes de reiniciar el mundo") : QString());
    botonInstalarVarios->setEnabled(libre);
    botonBuscarPlugins->setEnabled(libre && hay && !plugins.ocupado());
    botonActualizarPlugins->setEnabled(libre && hay && !encendido && !plugins.ocupado() && pluginsNuevos > 0
                                       && pluginsDe == servidorElegido());
    botonPlugin->setEnabled(libre && hay);
    botonPack->setVisible(pluginsSonMods);
    botonPack->setEnabled(libre && hay);
    botonCarpetaPlugins->setEnabled(hay);
    for (PestanaServidor *p : pestanas())
        p->ponerOcupado(!libre);

    const bool comandos = consola == Consola::Comandos;
    editComando->setEnabled(comandos);
    botonEnviar->setEnabled(comandos && !envio.ocupado());
    botonTerminal->setEnabled(comandos && !envio.ocupado());
    editComando->setPlaceholderText(
        comandos ? editComando->property("ayuda").toString()
        : consola == Consola::SoloLectura ? tr("Se prendió sin consola compartida: reinicialo desde el panel para mandarle comandos")
        : consola == Consola::Apagado ? tr("Apagado: no recibe comandos")
        : QString());
}

void PaginaMinecraft::ejecutar(const QStringList &argumentos, const QString &estado, const QByteArray &entrada)
{
    mensajeFinal.clear();
    tema::mostrarEstado(etiquetaEstado, estado);
    barraProgreso->setRange(0, 0);    // sin porcentaje: barra «ocupada»
    barraProgreso->show();
    accion.iniciar(script, argumentos, entrada);
    botonCancelar->setVisible(cancelable || creando);
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
    QStringList servidores = grilla->seleccionados();
    if (servidores.isEmpty()) {
        tema::mostrarEstado(etiquetaEstado, tr("Elegí al menos un servidor (con Ctrl o Shift se eligen varios)."));
        return;
    }
    if (QMessageBox::question(this, windowTitle(),
            tr("Se va a bajar la última compilación estable de Paper (de la misma versión de Minecraft) para:\n\n%1\n\n"
               "Los que no son Paper o están encendidos no se tocan, y el jar anterior queda en Respaldos. ¿Continuar?")
                .arg(etiquetas(servidores).join(QStringLiteral("\n")))) != QMessageBox::Yes)
        return;
    recargarPlugins = false;
    ejecutar(QStringList{QStringLiteral("paper")} + servidores, tr("Actualizando Paper…"));
}

void PaginaMinecraft::cambiarRam()
{
    const QString servidor = servidorElegido();
    const ServidorMc *s = grilla->datos(servidor);
    const QString actual = s ? s->ram : QStringLiteral("8G");
    bool ok = false;
    const int gb = QInputDialog::getInt(this, windowTitle(),
        tr("Memoria máxima para %1 (GB):").arg(etiqueta(servidor)),
        QString(actual).remove(QRegularExpression(QStringLiteral("[^0-9]"))).toInt(), 1, 24, 1, &ok);
    if (!ok)
        return;
    ejecutar({QStringLiteral("ram"), servidor, QString::number(gb) + u'G'}, tr("Cambiando la memoria…"));
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

// Un plugin o mod de Modrinth (o una URL): en el elegido, o en todos los elegidos (cada uno recibe el que le sirve)
void PaginaMinecraft::instalarPlugin(bool enSeleccionados)
{
    const QStringList servidores = enSeleccionados ? grilla->seleccionados() : QStringList{servidorElegido()};
    if (servidores.isEmpty() || servidores.first().isEmpty())
        return;
    bool ok = false;
    const QString texto = QInputDialog::getText(this, tr("Instalar un plugin o mod"),
        tr("Nombre en Modrinth (ej. Chunky) o su URL.\nSe instala en: %1\n(cada servidor recibe la versión que le sirve, "
           "con sus dependencias)").arg(etiquetas(servidores).join(QStringLiteral(", "))),
        QLineEdit::Normal, QString(), &ok).trimmed();
    if (!ok || texto.isEmpty())
        return;
    recargarPlugins = true;
    ejecutar(QStringList{QStringLiteral("plugin"), texto} + servidores, tr("Instalando «%1»…").arg(texto));
}

// --- Resultado de las acciones -------------------------------------------------------------------------------

void PaginaMinecraft::eventoAccion(const QString &palabra, const QString &resto)
{
    if (palabra == u"ETAPA") {
        tema::mostrarEstado(etiquetaEstado, resto + QStringLiteral("…"));
    } else if (palabra == u"ESPERA") {
        // Detener: hasta 2 minutos guardando mundos
        barraProgreso->setRange(0, 120);
        barraProgreso->setValue(resto.toInt());
    } else if (palabra == u"LISTO" || palabra == u"ERROR") {
        mensajeFinal = resto;
    } else if (palabra == u"AVISO") {
        registroAvisos->appendPlainText(resto);
        if (!registroAvisos->isVisible())
            botonAvisos->setText(tr("Avisos (%1)").arg(++avisosSinVer));
    } else if (palabra == u"CREADO") {
        // El servidor nuevo (o movido de carpeta) queda elegido
        grilla->elegir(resto);
    }
}

void PaginaMinecraft::terminoAccion(int codigo, bool cancelado)
{
    barraProgreso->hide();
    botonCancelar->hide();
    if (cancelado && cancelable)
        tema::mostrarEstado(etiquetaEstado, tr("Cancelado: el servidor sigue prendido (se avisó en el chat)."));
    else if (cancelado && creando)
        tema::mostrarEstado(etiquetaEstado, tr("Cancelado: no se creó nada."));
    else if (cancelado)
        tema::mostrarEstado(etiquetaEstado, tr("Cancelado."));
    else if (codigo == 0)
        tema::mostrarEstado(etiquetaEstado, mensajeFinal, tema::Estado::Ok);
    else
        tema::mostrarEstado(etiquetaEstado, (mensajeFinal.isEmpty() ? tr("No se pudo completar.") : mensajeFinal), tema::Estado::Error);
    if (!mensajeFinal.isEmpty())
        registroAvisos->appendPlainText(mensajeFinal);
    cancelable = false;
    creando = false;
    actualizarBotones();
    for (PestanaServidor *p : pestanas())
        p->refrescar();
    if (recargarPlugins) {
        recargarPlugins = false;
        consultarPlugins();
    }
    // El servidor tarda unos segundos en arrancar java: la lista se actualiza después
    consultar();
    QTimer::singleShot(8000, this, &PaginaMinecraft::consultar);
}

// --- Crear, cambiar versión, pack ------------------------------------------------------------------------------

// Asistente para un servidor nuevo: arma la configuración y «Minecraft.sh crear» la usa (por stdin)
void PaginaMinecraft::crearServidor()
{
    QHash<QString, bool> existentes;
    for (const ServidorMc &s : grilla->todos())
        existentes.insert(s.ruta, s.encendido);
    AsistenteMinecraft asistente(script, existentes, this);
    if (asistente.exec() != QDialog::Accepted)
        return;
    creando = true;
    ejecutar({QStringLiteral("crear")}, tr("Creando %1…").arg(asistente.titulo()), asistente.configuracion());
}

QList<PestanaServidor *> PaginaMinecraft::pestanas() const
{
    return {pestanaJugadores, pestanaOpciones, pestanaRespaldos};
}

// El servidor elegido, su estado y su tipo, para las pestañas (cada una vuelve a consultar si cambió)
void PaginaMinecraft::actualizarPestanas()
{
    bool encendido = false;
    const QString servidor = servidorElegido(&encendido);
    for (PestanaServidor *p : pestanas())
        p->elegir(servidor, encendido, tipoElegido());
}

void PaginaMinecraft::cambiarVersion()
{
    const ServidorMc *s = grilla->datos(servidorElegido());
    if (!s)
        return;
    const QString servidor = s->ruta;
    DialogoVersionMinecraft dialogo(script, servidor, s->tipo, s->version, this);
    if (dialogo.exec() != QDialog::Accepted)
        return;
    recargarPlugins = true;
    creando = true;    // (se puede cancelar: el mundo ya quedó guardado antes de tocar nada)
    ejecutar({QStringLiteral("cambiar"), servidor}, tr("Pasando %1 a %2…").arg(etiqueta(servidor), dialogo.descripcion()),
             dialogo.configuracion());
}

void PaginaMinecraft::packJugadores()
{
    const QString servidor = servidorElegido();
    if (servidor.isEmpty())
        return;
    const QString carpeta = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    const QString sugerido = QDir(carpeta.isEmpty() ? QDir::homePath() : carpeta)
                                 .filePath(servidor.section(u'/', -1) + QStringLiteral(" - para jugadores.mrpack"));
    QString destino = QFileDialog::getSaveFileName(this, tr("Guardar el pack para jugadores"), sugerido, tr("Modpack de Modrinth (*.mrpack)"));
    if (destino.isEmpty())
        return;
    if (!destino.endsWith(QStringLiteral(".mrpack")))
        destino += QStringLiteral(".mrpack");
    ejecutar({QStringLiteral("pack-jugadores"), servidor, destino}, tr("Armando el pack para jugadores de %1…").arg(etiqueta(servidor)));
}
