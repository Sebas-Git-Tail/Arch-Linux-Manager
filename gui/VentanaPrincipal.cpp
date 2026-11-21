#include "VentanaPrincipal.h"
#include "Novedades.h"
#include "PanelApps.h"
#include "VentanaNovedades.h"
#include "Piezas.h"
#include "Tema.h"
#include "ui_VentanaPrincipal.h"

#include "PaginaDescargas.h"
#include "PaginaRespaldo.h"
#include "PaginaSteam.h"
#include "PaginaAndroid.h"
#include "PaginaAUR.h"
#include "PaginaMinecraft.h"
#include "PaginaNotificacion.h"
#include "PaginaTutoriales.h"
#include "ProcesoLogica.h"

#include <QCloseEvent>
#include <QDir>
#include <QActionGroup>
#include <QGridLayout>
#include <QLabel>
#include <QMenu>
#include <QMessageBox>
#include <QScrollArea>
#include <QTimer>

#include <algorithm>

VentanaPrincipal::VentanaPrincipal(const QString &base, QWidget *parent)
    : QWidget(parent), ui(new Ui::VentanaPrincipal), base(base)
{
    ui->setupUi(this);

    // Estilo común (comun/ui): título grande, menú lateral, íconos SVG y el estado como «chips»
    ui->etiquetaTitulo->setProperty("titulo", true);
    ui->botonVolver->hide();
    ui->botonVolver->setIcon(tema::icono(QStringLiteral("volver")));
    ui->botonVolver->setProperty("plano", true);
    ui->botonRefrescar->setIcon(tema::icono(QStringLiteral("actualizar")));
    ui->botonEquipo->setIcon(tema::icono(QStringLiteral("ajustes")));
    ui->listaSecciones->setProperty("lateral", true);
    ui->listaSecciones->setIconSize(QSize(18, 18));
    ui->listaSecciones->setSpacing(0);
    ui->etiquetaCargando->setProperty("secundario", true);
    ui->etiquetaEstado->setProperty("secundario", true);
    chipEquipo = new QLabel(this);
    chipServidor = new QLabel(this);
    tema::marcarChip(chipEquipo, tema::Estado::Neutro);
    chipEquipo->hide();
    chipServidor->hide();
    ui->layoutEstado->insertWidget(0, chipEquipo);
    ui->layoutEstado->insertWidget(1, chipServidor);
    ui->layoutEstado->setSpacing(8);
    ui->layoutEncabezado->addWidget(soporte::botonNovedades(this));   // novedades e informe de fallas
    ui->layoutEncabezado->addWidget(tema::botonModo(this));   // modo claro / oscuro (se recuerda)

    // Las páginas de herramientas se crean una sola vez (así una descarga sigue aunque
    // se cambie de sección). La clave es el «destino» de su acción en Acciones.cpp.
    const QString logica = QDir(base).filePath(QStringLiteral("Logica"));
    const auto agregarDescarga = [&](const QString &id, PaginaDescargas::Tipo tipo) {
        auto *pagina = new PaginaDescargas(tipo, logica, this);
        herramientas.insert(id, pagina);
        tareas << Tarea{[pagina] { return pagina->ocupada(); }, [pagina] { pagina->cancelarYEsperar(); }};
    };
    agregarDescarga(QStringLiteral("videos"), PaginaDescargas::Tipo::Videos);
    agregarDescarga(QStringLiteral("musica"), PaginaDescargas::Tipo::Musica);
    agregarDescarga(QStringLiteral("descargas-masa"), PaginaDescargas::Tipo::Archivos);

    // Respaldos: al terminar uno se vuelve a comprobar el entorno (con el primer respaldo
    // deja de ofrecerse Restauración-Linux)
    const auto agregarRespaldo = [&](const QString &id, const QString &tipo) {
        auto *pagina = new PaginaRespaldo(tipo, logica, this);
        connect(pagina, &PaginaRespaldo::respaldoTerminado, this, [this] { comprobarEntorno(); });
        herramientas.insert(id, pagina);
        tareas << Tarea{[pagina] { return pagina->ocupada(); }, [pagina] { pagina->cancelarYEsperar(); }};
    };
    agregarRespaldo(QStringLiteral("respaldo-linux"), QStringLiteral("linux"));
    agregarRespaldo(QStringLiteral("restauracion"), QStringLiteral("restauracion"));
    agregarRespaldo(QStringLiteral("respaldo-carina"), QStringLiteral("carina"));
    agregarRespaldo(QStringLiteral("respaldo-minecraft"), QStringLiteral("minecraft"));

    auto *steam = new PaginaSteam(logica, this);
    herramientas.insert(QStringLiteral("steam"), steam);
    tareas << Tarea{[steam] { return steam->ocupada(); }, [steam] { steam->cancelarYEsperar(); }};

    auto *minecraftPagina = new PaginaMinecraft(logica, this);
    herramientas.insert(QStringLiteral("minecraft"), minecraftPagina);
    tareas << Tarea{[minecraftPagina] { return minecraftPagina->ocupada(); }, [minecraftPagina] { minecraftPagina->cancelarYEsperar(); }};

    auto *android = new PaginaAndroid(logica, this);
    herramientas.insert(QStringLiteral("android"), android);
    tareas << Tarea{[android] { return android->ocupada(); }, [android] { android->cancelarYEsperar(); }};

    herramientas.insert(QStringLiteral("tutoriales"), new PaginaTutoriales(logica, this));
    herramientas.insert(QStringLiteral("notificaciones"), new PaginaNotificacion(logica, this));
    // Actualizar el Manager (paquete del repositorio de la casa) e instalar las otras apps (comun/apps)
    herramientas.insert(QStringLiteral("apps"), new apps::PanelApps(QStringLiteral("Arch-Linux-Manager"), this));
    // Apps del AUR (Claude, Equibop, Heroic, Linux Command Library), según el equipo
    herramientas.insert(QStringLiteral("aur"), new PaginaAUR(base, this));

    for (QWidget *pagina : std::as_const(herramientas))
        ui->paginas->addWidget(pagina);

    connect(ui->listaSecciones, &QListWidget::currentRowChanged, this, &VentanaPrincipal::cambiarSeccion);
    connect(ui->botonVolver, &QPushButton::clicked, this, &VentanaPrincipal::volver);
    connect(ui->botonRefrescar, &QPushButton::clicked, this, [this] { comprobarEntorno(true); });
    connect(&procesoEntorno, &QProcess::finished, this, &VentanaPrincipal::terminoEntorno);
    armarMenuEquipo();
    ui->botonEquipo->hide();    // se muestra si Entorno.sh dice ELEGIR_EQUIPO SI

    comprobarEntorno();
    // Una vez por día: si hay una versión nueva del Manager, pregunta y la instala (pkexec pacman -U)
    QTimer::singleShot(3000, this, [this] { apps::avisarActualizaciones(this, QStringLiteral("Arch-Linux-Manager")); });
    soporte::novedadesAlAbrir(this);    // la primera vez que se abre una versión nueva: qué cambió
}

VentanaPrincipal::~VentanaPrincipal()
{
    delete ui;
}

void VentanaPrincipal::closeEvent(QCloseEvent *evento)
{
    const bool ocupada = std::any_of(tareas.cbegin(), tareas.cend(), [](const Tarea &t) { return t.ocupada(); });
    if (ocupada) {
        if (QMessageBox::question(this, windowTitle(),
                tr("Hay una descarga o un respaldo en curso. ¿Cancelarlo y salir?")) != QMessageBox::Yes) {
            evento->ignore();
            return;
        }
        for (const Tarea &tarea : std::as_const(tareas)) {
            if (tarea.ocupada())
                tarea.cancelar();
        }
    }
    evento->accept();
}

// Variables para los scripts: las rutas ya las exportó main.cpp; se suma si el servidor responde
QProcessEnvironment VentanaPrincipal::entornoScripts() const
{
    QProcessEnvironment variables = QProcessEnvironment::systemEnvironment();
    variables.insert(QStringLiteral("SERVIDOR_ACTIVO"), entorno.servidor ? QStringLiteral("SI") : QStringLiteral("NO"));
    return variables;
}

void VentanaPrincipal::comprobarEntorno(bool refrescar)
{
    if (procesoEntorno.state() != QProcess::NotRunning)
        return;
    ui->botonRefrescar->setEnabled(false);
    tema::mostrarEstado(ui->etiquetaEstado, tr("Comprobando la computadora y el servidor…"));

    QStringList argumentos{QDir(base).filePath(QStringLiteral("Logica/Entorno.sh"))};
    if (refrescar)
        argumentos << QStringLiteral("--refrescar");
    procesoEntorno.setProcessEnvironment(entornoScripts());
    procesoEntorno.start(QStringLiteral("bash"), argumentos);
}

// Lee los eventos de Entorno.sh y arma las secciones
void VentanaPrincipal::terminoEntorno(int codigo, QProcess::ExitStatus estado)
{
    ui->botonRefrescar->setEnabled(true);
    if (estado != QProcess::NormalExit || codigo != 0) {
        tema::avisar(this, tr("No se pudo comprobar el entorno: %1")
                               .arg(QString::fromUtf8(procesoEntorno.readAllStandardError()).trimmed()),
                     tema::Estado::Error);
    }

    Entorno nuevo;
    const QStringList lineas = QString::fromUtf8(procesoEntorno.readAllStandardOutput()).split(u'\n');
    for (const QString &linea : lineas) {
        const QStringList partes = linea.trimmed().split(u' ');
        const QString evento = partes.value(0);
        if (evento == u"MAQUINA")
            nuevo.maquina = partes.value(1);
        else if (evento == u"SERVIDOR")
            nuevo.servidor = partes.value(1) == u"SI";
        else if (evento == u"PROGRAMA" && partes.value(2) == u"SI")
            nuevo.programas.insert(partes.value(1));
        else if (evento == u"RESTAURACION")
            nuevo.restauracion = partes.value(1) == u"SI";
        else if (evento == u"NOTIFICACIONES")
            nuevo.notificaciones = partes.value(1) == u"SI";
        else if (evento == u"MAQUINA_ORIGEN")
            nuevo.maquinaElegida = partes.value(1) == u"manual";
        else if (evento == u"ELEGIR_EQUIPO")
            nuevo.puedeElegirEquipo = partes.value(1) == u"SI";
    }
    entorno = nuevo;
    // En la PC y la del instituto, las apps muestran también las novedades que solo le afectan a Sebastián
    if (entorno.esSebastian() && !soporte::esDesarrollador()) {
        soporte::ponerDesarrollador(true);
        soporte::novedades()->recargar();
    }

    construirSecciones();
    mostrarEstado();
}

namespace {
// Equipos que entiende Common/Equipo.sh, en el orden del menú «Este equipo…»
const QList<QPair<QString, QString>> &equipos()
{
    static const QList<QPair<QString, QString>> lista{
        {QStringLiteral("pc"), QObject::tr("PC de Sebastián")},
        {QStringLiteral("instituto"), QObject::tr("PC del instituto")},
        {QStringLiteral("mama"), QObject::tr("PC de mamá")},
        {QStringLiteral("krocante"), QObject::tr("PC de Krocante")},
        {QStringLiteral("otra"), QObject::tr("Otra computadora")},
    };
    return lista;
}
}

void VentanaPrincipal::mostrarEstado()
{
    QString nombre = entorno.maquina;
    for (const auto &[id, texto] : equipos()) {
        if (id == entorno.maquina)
            nombre = texto;
    }
    ui->etiquetaEstado->clear();
    chipEquipo->setText(nombre);
    chipEquipo->setToolTip(entorno.maquinaElegida ? tr("Elegida a mano con «Este equipo…»")
                                                  : tr("Reconocida por la placa de red"));
    chipEquipo->show();
    chipServidor->setText(entorno.servidor ? tr("Servidor conectado") : tr("Servidor sin conexión"));
    chipServidor->setToolTip(entorno.servidor ? tr("Respaldos, tutoriales y descargas del servidor disponibles")
                                              : tr("Sin el servidor no se ven los respaldos ni los tutoriales"));
    tema::marcarChip(chipServidor, entorno.servidor ? tema::Estado::Ok : tema::Estado::Error);
    chipServidor->show();

    // «Este equipo…» es para depurar: solo en las computadoras de Sebastián
    ui->botonEquipo->setVisible(entorno.puedeElegirEquipo);

    // Marca en el menú lo que está elegido
    if (QMenu *menu = ui->botonEquipo->menu()) {
        const QString marcado = entorno.maquinaElegida ? entorno.maquina : QStringLiteral("auto");
        for (QAction *accion : menu->actions())
            accion->setChecked(accion->data().toString() == marcado);
    }
}

// Menú «Este equipo…»: elegir a mano qué computadora es (lo guarda Entorno.sh --equipo en
// ~/.config/Manager/Equipo.conf). «Automático» vuelve a adivinarlo por la MAC.
void VentanaPrincipal::armarMenuEquipo()
{
    auto *menu = new QMenu(ui->botonEquipo);
    auto *grupo = new QActionGroup(menu);
    const auto agregar = [&](const QString &id, const QString &texto) {
        QAction *accion = menu->addAction(texto);
        accion->setData(id);
        accion->setCheckable(true);
        grupo->addAction(accion);
        connect(accion, &QAction::triggered, this, [this, id] { elegirEquipo(id); });
    };
    agregar(QStringLiteral("auto"), tr("Automático (por la placa de red)"));
    menu->addSeparator();
    for (const auto &[id, texto] : equipos())
        agregar(id, texto);
    ui->botonEquipo->setMenu(menu);
}

void VentanaPrincipal::elegirEquipo(const QString &equipo)
{
    QProcess guardar;
    guardar.setProcessEnvironment(entornoScripts());
    guardar.start(QStringLiteral("bash"), {QDir(base).filePath(QStringLiteral("Logica/Entorno.sh")),
                                           QStringLiteral("--equipo"), equipo});
    if (!guardar.waitForFinished(5000) || guardar.exitCode() != 0) {
        avisar(tr("No se pudo guardar el equipo."), tema::Estado::Error);
        return;
    }
    comprobarEntorno();    // las secciones dependen del equipo
}

// Aviso flotante abajo de la ventana (se va solo)
void VentanaPrincipal::avisar(const QString &texto, tema::Estado estado)
{
    tema::avisar(this, texto, estado);
}

// Rearma el menú lateral y las páginas de tarjetas con el entorno actual. Si la
// sección que se estaba viendo sigue existiendo, se queda en esa.
void VentanaPrincipal::construirSecciones()
{
    const QString anterior = idsSecciones.value(ui->listaSecciones->currentRow());
    const bool enHerramienta = std::as_const(herramientas).values().contains(ui->paginas->currentWidget());

    const QSignalBlocker bloqueo(ui->listaSecciones);
    ui->listaSecciones->clear();
    for (QWidget *pagina : std::as_const(paginasSeccion)) {
        ui->paginas->removeWidget(pagina);
        pagina->deleteLater();
    }
    paginasSeccion.clear();
    idsSecciones.clear();

    const QList<Accion> todas = acciones();
    for (const Seccion &seccion : secciones()) {
        QList<Accion> visibles;
        for (const Accion &accion : todas) {
            if (accion.seccion == seccion.id && accion.visible(entorno))
                visibles << accion;
        }
        if (visibles.isEmpty())
            continue;    // una sección sin opciones no se muestra (como pasaba con los menús)

        QWidget *pagina = crearPaginaSeccion(visibles);
        pagina->setWindowTitle(seccion.titulo);
        ui->paginas->addWidget(pagina);
        paginasSeccion.insert(seccion.id, pagina);
        idsSecciones << seccion.id;

        auto *item = new QListWidgetItem(tema::icono(seccion.icono, tema::colores().texto2), seccion.titulo,
                                         ui->listaSecciones);
        item->setSizeHint(QSize(0, 38));
    }
    // Con una sola sección (p. ej. en una computadora ajena) el menú lateral no aporta nada
    ui->listaSecciones->setVisible(idsSecciones.size() > 1);

    const int fila = qMax(0, idsSecciones.indexOf(anterior));
    ui->listaSecciones->setCurrentRow(fila);
    if (!enHerramienta)
        cambiarSeccion(fila);
}

// Página con una tarjeta (ícono, título y descripción) por acción, en dos columnas
QWidget *VentanaPrincipal::crearPaginaSeccion(const QList<Accion> &lista)
{
    auto *contenido = new QWidget;
    contenido->setObjectName(QStringLiteral("contenidoSeccion"));
    auto *grilla = new QGridLayout(contenido);
    grilla->setContentsMargins(0, 4, 4, 0);
    grilla->setSpacing(10);

    for (qsizetype i = 0; i < lista.size(); ++i) {
        const Accion accion = lista.at(i);
        auto *tarjeta = new tema::TarjetaAccion(accion.icono, accion.titulo, accion.descripcion, contenido);
        connect(tarjeta, &tema::TarjetaAccion::clicked, this, [this, accion] { lanzar(accion); });
        grilla->addWidget(tarjeta, static_cast<int>(i / 2), static_cast<int>(i % 2));
    }
    grilla->setColumnStretch(0, 1);
    grilla->setColumnStretch(1, 1);
    grilla->setRowStretch(grilla->rowCount(), 1);

    auto *desplazable = new QScrollArea;
    desplazable->setWidget(contenido);
    desplazable->setWidgetResizable(true);
    desplazable->setFrameShape(QFrame::NoFrame);
    desplazable->setStyleSheet(QStringLiteral("QScrollArea, #contenidoSeccion { background: transparent; }"));
    return desplazable;
}

void VentanaPrincipal::cambiarSeccion(int fila)
{
    if (QWidget *pagina = paginasSeccion.value(idsSecciones.value(fila)))
        mostrarPagina(pagina, pagina->windowTitle(), false);
}

void VentanaPrincipal::volver()
{
    cambiarSeccion(ui->listaSecciones->currentRow());
}

void VentanaPrincipal::mostrarPagina(QWidget *pagina, const QString &titulo, bool conVolver)
{
    ui->paginas->setCurrentWidget(pagina);
    ui->etiquetaTitulo->setText(titulo);
    ui->botonVolver->setVisible(conVolver);
}

void VentanaPrincipal::lanzar(const Accion &accion)
{
    if (accion.tipo == TipoAccion::Pagina) {
        if (QWidget *pagina = herramientas.value(accion.destino))
            mostrarPagina(pagina, pagina->windowTitle(), true);
        return;
    }

    // Lógica sin página (p. ej. Cerrar Waydroid): corre en segundo plano y su resultado
    // (LISTO o ERROR) se ve en la barra de abajo
    if (accion.tipo == TipoAccion::Logica) {
        auto *proceso = new ProcesoLogica(this);
        auto *final = new QString;
        connect(proceso, &ProcesoLogica::evento, this, [final](const QString &palabra, const QString &resto) {
            if (palabra == u"LISTO" || palabra == u"ERROR")
                *final = resto;
        });
        connect(proceso, &ProcesoLogica::terminado, this, [this, proceso, final, accion](int codigo, bool) {
            if (codigo == 0)
                avisar(final->isEmpty() ? accion.titulo : *final, tema::Estado::Ok);
            else
                avisar(final->isEmpty() ? tr("No se pudo: %1").arg(accion.titulo) : *final, tema::Estado::Error);
            delete final;
            proceso->deleteLater();
        });
        avisar(tr("%1…").arg(accion.titulo));
        proceso->iniciar(QDir(base).filePath(accion.destino), accion.argumentos);
        return;
    }

    // Lo que necesita terminal (Actualizar Arch) y otros programas (Playit)
    QProcess proceso;
    proceso.setProcessEnvironment(entornoScripts());
    proceso.setWorkingDirectory(QDir::homePath());
    const QString ruta = QDir(base).filePath(accion.destino);
    switch (accion.tipo) {
    case TipoAccion::Terminal:
        proceso.setProgram(QStringLiteral("konsole"));
        proceso.setArguments({QStringLiteral("-e"), QStringLiteral("bash"), ruta});
        break;
    case TipoAccion::Programa:
        proceso.setProgram(accion.destino);
        proceso.setArguments(accion.argumentos);
        break;
    case TipoAccion::Pagina:
    case TipoAccion::Logica:
        break;
    }

    if (proceso.startDetached())
        avisar(tr("Abriendo %1…").arg(accion.titulo));
    else
        avisar(tr("No se pudo abrir %1.").arg(accion.titulo), tema::Estado::Error);
}
