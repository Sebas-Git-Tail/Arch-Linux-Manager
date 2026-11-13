#include "VentanaPrincipal.h"
#include "ui_VentanaPrincipal.h"

#include "PaginaDescargas.h"
#include "PaginaRespaldo.h"
#include "PaginaSteam.h"
#include "PaginaAndroid.h"
#include "PaginaMinecraft.h"
#include "PaginaNotificacion.h"
#include "PaginaTutoriales.h"
#include "ProcesoLogica.h"

#include <QCloseEvent>
#include <QCommandLinkButton>
#include <QDir>
#include <QGridLayout>
#include <QMessageBox>
#include <QScrollArea>
#include <QTimer>

#include <algorithm>

VentanaPrincipal::VentanaPrincipal(const QString &base, QWidget *parent)
    : QWidget(parent), ui(new Ui::VentanaPrincipal), base(base)
{
    ui->setupUi(this);

    // Título de la página un poco más grande que el resto
    QFont fuente = ui->etiquetaTitulo->font();
    fuente.setPointSizeF(fuente.pointSizeF() * 1.4);
    fuente.setBold(true);
    ui->etiquetaTitulo->setFont(fuente);
    ui->botonVolver->hide();

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

    for (QWidget *pagina : std::as_const(herramientas))
        ui->paginas->addWidget(pagina);

    connect(ui->listaSecciones, &QListWidget::currentRowChanged, this, &VentanaPrincipal::cambiarSeccion);
    connect(ui->botonVolver, &QPushButton::clicked, this, &VentanaPrincipal::volver);
    connect(ui->botonRefrescar, &QPushButton::clicked, this, [this] { comprobarEntorno(true); });
    connect(&procesoEntorno, &QProcess::finished, this, &VentanaPrincipal::terminoEntorno);

    comprobarEntorno();
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
    ui->etiquetaEstado->setText(tr("Comprobando la computadora y el servidor…"));

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
        ui->etiquetaEstado->setText(tr("No se pudo comprobar el entorno: %1")
                                        .arg(QString::fromUtf8(procesoEntorno.readAllStandardError()).trimmed()));
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
    }
    entorno = nuevo;

    construirSecciones();
    mostrarEstado();
}

void VentanaPrincipal::mostrarEstado()
{
    static const QMap<QString, QString> nombres{
        {QStringLiteral("pc"), tr("PC de Sebastián")},
        {QStringLiteral("instituto"), tr("PC del instituto")},
        {QStringLiteral("mama"), tr("PC de mamá")},
        {QStringLiteral("krocante"), tr("PC de Krocante")},
        {QStringLiteral("otra"), tr("Otra computadora")},
    };
    ui->etiquetaEstado->setText(tr("%1 · Servidor: %2")
                                    .arg(nombres.value(entorno.maquina, entorno.maquina),
                                         entorno.servidor ? tr("activo ✓") : tr("sin conexión ✗")));
}

// Mensaje temporal en la barra de abajo (vuelve al estado a los 4 segundos)
void VentanaPrincipal::avisar(const QString &texto)
{
    ui->etiquetaEstado->setText(texto);
    QTimer::singleShot(4000, this, &VentanaPrincipal::mostrarEstado);
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

        auto *item = new QListWidgetItem(seccion.icono + QStringLiteral("  ") + seccion.titulo, ui->listaSecciones);
        item->setSizeHint(QSize(0, 40));
    }

    const int fila = qMax(0, idsSecciones.indexOf(anterior));
    ui->listaSecciones->setCurrentRow(fila);
    if (!enHerramienta)
        cambiarSeccion(fila);
}

// Página con una tarjeta (QCommandLinkButton: título y descripción) por acción
QWidget *VentanaPrincipal::crearPaginaSeccion(const QList<Accion> &lista)
{
    auto *contenido = new QWidget;
    auto *grilla = new QGridLayout(contenido);
    grilla->setSpacing(10);

    for (qsizetype i = 0; i < lista.size(); ++i) {
        const Accion accion = lista.at(i);
        auto *tarjeta = new QCommandLinkButton(accion.icono + QStringLiteral("  ") + accion.titulo,
                                               accion.descripcion, contenido);
        tarjeta->setIcon(QIcon());    // el ícono es el emoji del título
        tarjeta->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Minimum);
        connect(tarjeta, &QCommandLinkButton::clicked, this, [this, accion] { lanzar(accion); });
        grilla->addWidget(tarjeta, static_cast<int>(i / 2), static_cast<int>(i % 2));
    }
    grilla->setRowStretch(grilla->rowCount(), 1);

    auto *desplazable = new QScrollArea;
    desplazable->setWidget(contenido);
    desplazable->setWidgetResizable(true);
    desplazable->setFrameShape(QFrame::NoFrame);
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
            avisar(codigo == 0 ? QStringLiteral("✓ ") + (final->isEmpty() ? accion.titulo : *final)
                               : QStringLiteral("✗ ") + (final->isEmpty() ? tr("No se pudo: %1").arg(accion.titulo) : *final));
            delete final;
            proceso->deleteLater();
        });
        ui->etiquetaEstado->setText(tr("%1…").arg(accion.titulo));
        proceso->iniciar(QDir(base).filePath(accion.destino), accion.argumentos);
        return;
    }

    // Lo que necesita terminal (Actualizar Arch, App) y otros programas (Playit)
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
        QMessageBox::warning(this, windowTitle(), tr("No se pudo abrir %1.").arg(accion.titulo));
}
