#include "AsistenteMinecraft.h"
#include "Tema.h"

#include <QButtonGroup>
#include <QCheckBox>
#include <QComboBox>
#include <QDialogButtonBox>
#include <QDir>
#include <QFileInfo>
#include <QFileDialog>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QLocale>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QRadioButton>
#include <QRegularExpression>
#include <QSpinBox>
#include <QStandardItemModel>
#include <QVBoxLayout>
#include <QVersionNumber>
#include <QWizardPage>

#include <functional>

namespace {

enum Paso { PasoBase, PasoSoftware, PasoModpack, PasoContenido, PasoConfiguracion, PasoResumen };

// Página con su «completa», «siguiente» y «al entrar» como funciones (así todo queda en el asistente)
class Pagina : public QWizardPage
{
public:
    std::function<bool()> completa;
    std::function<int()> siguiente;
    std::function<void()> alEntrar;
    bool isComplete() const override { return completa ? completa() : true; }
    int nextId() const override { return siguiente ? siguiente() : QWizardPage::nextId(); }
    void initializePage() override { if (alEntrar) alEntrar(); }
    void avisar() { emit completeChanged(); }
};

// Igual que nombre_ok de Minecraft.sh
bool nombreValido(const QString &texto)
{
    static const QRegularExpression re(QStringLiteral(R"(^[\p{L}\p{N}][\p{L}\p{N} ._()+\-]{0,39}$)"));
    return re.match(texto).hasMatch() && !texto.contains(QStringLiteral("..")) && !texto.endsWith(u' ')
        && !texto.endsWith(u'.');
}

QString menorDe(const QString &version)
{
    return version.section(u'.', 0, 1);
}

QString nombreSoftware(const QString &tipo)
{
    if (tipo == u"paper") return QStringLiteral("Paper");
    if (tipo == u"fabric") return QStringLiteral("Fabric");
    if (tipo == u"forge") return QStringLiteral("Forge");
    return QStringLiteral("Vanilla");
}

QString sinSaltos(QString texto)
{
    texto.replace(QRegularExpression(QStringLiteral("[\\r\\n\\t]+")), QStringLiteral(" "));
    return texto.trimmed();
}

} // namespace

AsistenteMinecraft::AsistenteMinecraft(const QString &script_, const QHash<QString, bool> &servidores, QWidget *parent)
    : QWizard(parent), script(script_), existentes(servidores)
{
    setWindowTitle(tr("Crear un servidor de Minecraft"));
    setWizardStyle(QWizard::ModernStyle);
    setOption(QWizard::NoBackButtonOnStartPage);
    setButtonText(QWizard::FinishButton, tr("Crear servidor"));
    setButtonText(QWizard::NextButton, tr("Siguiente"));
    setButtonText(QWizard::BackButton, tr("Atrás"));
    setButtonText(QWizard::CancelButton, tr("Cancelar"));
    resize(880, 760);

    // --- 1. Base -------------------------------------------------------------------------------------
    auto *base = new Pagina;
    base->setTitle(tr("Nuevo servidor"));
    base->setSubTitle(tr("Elegí en qué grupo va y cómo se llama. Después vas a poder elegir el software, la versión y el contenido."));
    comboGrupo = new QComboBox;
    comboGrupo->setEditable(true);
    comboGrupo->setInsertPolicy(QComboBox::NoInsert);
    comboGrupo->lineEdit()->setPlaceholderText(tr("Un grupo que ya tengas, o uno nuevo"));
    editNombre = new QLineEdit;
    editNombre->setPlaceholderText(tr("Por ejemplo: SMP-1, Hardcore, Creativo"));
    editNombre->setMaxLength(40);
    radioCero = new QRadioButton(tr("Desde cero: elijo el software (Vanilla, Paper, Fabric o Forge) y la versión"));
    radioModpack = new QRadioButton(tr("Desde un modpack de Modrinth (decide la versión y el cargador)"));
    radioCero->setChecked(true);
    etiquetaRuta = new QLabel;
    etiquetaRuta->setWordWrap(true);
    etiquetaRuta->setTextInteractionFlags(Qt::TextSelectableByMouse);
    auto *formBase = new QFormLayout;
    formBase->addRow(tr("Grupo:"), comboGrupo);
    formBase->addRow(tr("Nombre:"), editNombre);
    auto *capaBase = new QVBoxLayout(base);
    capaBase->addLayout(formBase);
    capaBase->addSpacing(8);
    capaBase->addWidget(radioCero);
    capaBase->addWidget(radioModpack);
    capaBase->addSpacing(8);
    capaBase->addWidget(etiquetaRuta);
    capaBase->addStretch();
    base->completa = [this] { return baseCompleta(); };
    base->siguiente = [this] { return despuesDeBase(); };
    connect(comboGrupo, &QComboBox::currentTextChanged, base, [this, base] { actualizarRuta(); base->avisar(); });
    connect(editNombre, &QLineEdit::textChanged, base, [this, base] { actualizarRuta(); base->avisar(); });
    setPage(PasoBase, base);

    // --- 2a. Software y versión -----------------------------------------------------------------------
    auto *soft = new Pagina;
    soft->setTitle(tr("Software y versión"));
    soft->setSubTitle(tr("Solo se ofrecen las versiones que existen para el software elegido."));
    grupoSoftware = new QButtonGroup(this);
    auto *capaSoft = new QVBoxLayout(soft);
    const QList<QPair<QString, QString>> opcionesSoft = {
        {QStringLiteral("paper"), tr("Paper — rápido y con plugins (recomendado para jugar con amigos)")},
        {QStringLiteral("vanilla"), tr("Vanilla — el oficial de Mojang, sin plugins ni mods")},
        {QStringLiteral("fabric"), tr("Fabric — con mods de Fabric (los que agregan cosas también los tienen que tener los jugadores)")},
        {QStringLiteral("forge"), tr("Forge — con mods de Forge")},
    };
    for (int i = 0; i < opcionesSoft.size(); ++i) {
        auto *radio = new QRadioButton(opcionesSoft.at(i).second);
        radio->setProperty("tipo", opcionesSoft.at(i).first);
        grupoSoftware->addButton(radio, i);
        capaSoft->addWidget(radio);
    }
    grupoSoftware->button(0)->setChecked(true);
    comboVersion = new QComboBox;
    estadoOpciones = new QLabel;
    estadoOpciones->setWordWrap(true);
    auto *formSoft = new QFormLayout;
    formSoft->addRow(tr("Versión de Minecraft:"), comboVersion);
    capaSoft->addSpacing(8);
    capaSoft->addLayout(formSoft);
    capaSoft->addWidget(estadoOpciones);
    capaSoft->addStretch();
    soft->completa = [this] { return softwareCompleto(); };
    soft->siguiente = [] { return int(PasoContenido); };
    connect(grupoSoftware, &QButtonGroup::idToggled, soft, [this, soft](int, bool marcado) {
        if (marcado) { llenarVersiones(); soft->avisar(); }
    });
    connect(comboVersion, &QComboBox::currentIndexChanged, soft, [this, soft] { actualizarRuta(); soft->avisar(); });
    setPage(PasoSoftware, soft);

    // --- 2b. Modpack ----------------------------------------------------------------------------------
    auto *pack = new Pagina;
    pack->setTitle(tr("Modpack de Modrinth"));
    pack->setSubTitle(tr("Solo aparecen los modpacks de Fabric o Forge que se pueden usar en un servidor. "
                         "La versión del modpack decide la versión de Minecraft y del cargador."));
    editBuscarModpack = new QLineEdit;
    editBuscarModpack->setPlaceholderText(tr("Buscar modpacks (vacío: los más populares)"));
    auto *botonBuscarPack = new QPushButton(tema::icono(QStringLiteral("buscar")), tr("Buscar"));
    listaModpacks = new QListWidget;
    listaModpacks->setWordWrap(true);
    listaModpacks->setMinimumHeight(260);
    comboVersionModpack = new QComboBox;
    estadoModpack = new QLabel;
    estadoModpack->setWordWrap(true);
    auto *filaBuscarPack = new QHBoxLayout;
    filaBuscarPack->addWidget(editBuscarModpack);
    filaBuscarPack->addWidget(botonBuscarPack);
    auto *formPack = new QFormLayout;
    formPack->addRow(tr("Versión del modpack:"), comboVersionModpack);
    auto *capaPack = new QVBoxLayout(pack);
    capaPack->addLayout(filaBuscarPack);
    capaPack->addWidget(listaModpacks, 1);
    capaPack->addLayout(formPack);
    capaPack->addWidget(estadoModpack);
    pack->completa = [this] { return softwareCompleto(); };
    pack->siguiente = [] { return int(PasoContenido); };
    pack->alEntrar = [this] { if (listaModpacks->count() == 0 && !busqueda.ocupado()) buscar(true); };
    connect(botonBuscarPack, &QPushButton::clicked, this, [this] { buscar(true); });
    connect(editBuscarModpack, &QLineEdit::returnPressed, this, [this] { buscar(true); });
    connect(listaModpacks, &QListWidget::currentItemChanged, this, &AsistenteMinecraft::elegirModpack);
    connect(comboVersionModpack, &QComboBox::currentIndexChanged, pack, [this, pack] { actualizarRuta(); pack->avisar(); });
    setPage(PasoModpack, pack);

    // --- 3. Contenido ---------------------------------------------------------------------------------
    auto *cont = new Pagina;
    cont->setTitle(tr("Contenido"));
    cont->setSubTitle(tr("Opcional: un mundo que ya tengas y los plugins o mods que quieras agregar."));
    auto *cajaMundo = new QGroupBox(tr("Mundo"));
    grupoMundo = new QButtonGroup(this);
    auto *radioNuevo = new QRadioButton(tr("Uno nuevo (se genera al iniciarlo por primera vez)"));
    auto *radioArchivo = new QRadioButton(tr("Uno que tengo (carpeta o .zip con level.dat):"));
    auto *radioServidor = new QRadioButton(tr("Una copia del de otro servidor (tiene que estar apagado):"));
    grupoMundo->addButton(radioNuevo, 0);
    grupoMundo->addButton(radioArchivo, 1);
    grupoMundo->addButton(radioServidor, 2);
    radioNuevo->setChecked(true);
    editMundo = new QLineEdit;
    editMundo->setReadOnly(true);
    auto *botonCarpetaMundo = new QPushButton(tema::icono(QStringLiteral("carpeta")), tr("Carpeta…"));
    auto *botonZipMundo = new QPushButton(tema::icono(QStringLiteral("abrir")), tr("Zip…"));
    comboMundoServidor = new QComboBox;
    QStringList rutas = existentes.keys();
    rutas.sort();
    for (const QString &r : rutas) {
        comboMundoServidor->addItem(QStringLiteral("%1 (%2)").arg(r.section(u'/', -1), r.section(u'/', 0, 0))
                                        + (existentes.value(r) ? tr(" — encendido") : QString()), r);
        if (existentes.value(r))   // encendido: no se puede copiar
            if (auto *m = qobject_cast<QStandardItemModel *>(comboMundoServidor->model()))
                m->item(comboMundoServidor->count() - 1)->setEnabled(false);
    }
    auto *filaArchivo = new QHBoxLayout;
    filaArchivo->addWidget(editMundo, 1);
    filaArchivo->addWidget(botonCarpetaMundo);
    filaArchivo->addWidget(botonZipMundo);
    auto *capaMundo = new QVBoxLayout(cajaMundo);
    capaMundo->addWidget(radioNuevo);
    capaMundo->addWidget(radioArchivo);
    capaMundo->addLayout(filaArchivo);
    capaMundo->addWidget(radioServidor);
    capaMundo->addWidget(comboMundoServidor);

    auto *cajaComp = new QGroupBox(tr("Plugins o mods"));
    etiquetaComplementos = new QLabel;
    etiquetaComplementos->setWordWrap(true);
    editBuscar = new QLineEdit;
    editBuscar->setPlaceholderText(tr("Buscar en Modrinth (nombre, por ejemplo Chunky)"));
    botonBuscar = new QPushButton(tema::icono(QStringLiteral("buscar")), tr("Buscar"));
    listaResultados = new QListWidget;
    listaResultados->setWordWrap(true);
    listaElegidos = new QListWidget;
    listaResultados->setMinimumHeight(170);
    listaElegidos->setMinimumHeight(170);
    botonAgregar = new QPushButton(tema::icono(QStringLiteral("agregar")), tr("Agregar →"));
    botonArchivo = new QPushButton(tema::icono(QStringLiteral("abrir")), tr("Un .jar del disco…"));
    botonQuitar = new QPushButton(tema::icono(QStringLiteral("borrar")), tr("Quitar"));
    estadoBusqueda = new QLabel;
    estadoBusqueda->setWordWrap(true);
    auto *filaBuscar = new QHBoxLayout;
    filaBuscar->addWidget(editBuscar, 1);
    filaBuscar->addWidget(botonBuscar);
    auto *colBotones = new QVBoxLayout;
    colBotones->addStretch();
    colBotones->addWidget(botonAgregar);
    colBotones->addWidget(botonArchivo);
    colBotones->addWidget(botonQuitar);
    colBotones->addStretch();
    auto *filaListas = new QHBoxLayout;
    filaListas->addWidget(listaResultados, 3);
    filaListas->addLayout(colBotones);
    filaListas->addWidget(listaElegidos, 2);
    auto *capaComp = new QVBoxLayout(cajaComp);
    capaComp->addWidget(etiquetaComplementos);
    capaComp->addLayout(filaBuscar);
    capaComp->addLayout(filaListas, 1);
    capaComp->addWidget(estadoBusqueda);
    auto *capaCont = new QVBoxLayout(cont);
    capaCont->addWidget(cajaMundo);
    capaCont->addWidget(cajaComp, 1);
    cont->completa = [this] {
        const int m = grupoMundo->checkedId();
        return (m == 0) || (m == 1 && !editMundo->text().isEmpty())
            || (m == 2 && comboMundoServidor->currentIndex() >= 0 && !existentes.value(comboMundoServidor->currentData().toString()));
    };
    cont->alEntrar = [this] { prepararContenido(); };
    connect(grupoMundo, &QButtonGroup::idToggled, cont, [cont] { cont->avisar(); });
    connect(comboMundoServidor, &QComboBox::currentIndexChanged, cont, [this, cont] {
        grupoMundo->button(2)->setChecked(true);
        cont->avisar();
    });
    connect(botonCarpetaMundo, &QPushButton::clicked, cont, [this, cont] { elegirMundo(true); cont->avisar(); });
    connect(botonZipMundo, &QPushButton::clicked, cont, [this, cont] { elegirMundo(false); cont->avisar(); });
    connect(botonBuscar, &QPushButton::clicked, this, [this] { buscar(false); });
    connect(editBuscar, &QLineEdit::returnPressed, this, [this] { buscar(false); });
    connect(botonAgregar, &QPushButton::clicked, this, &AsistenteMinecraft::agregarComplemento);
    connect(listaResultados, &QListWidget::itemDoubleClicked, this, &AsistenteMinecraft::agregarComplemento);
    connect(botonArchivo, &QPushButton::clicked, this, &AsistenteMinecraft::agregarArchivo);
    connect(botonQuitar, &QPushButton::clicked, this, [this] { delete listaElegidos->currentItem(); });
    setPage(PasoContenido, cont);

    // --- 4. Configuración -----------------------------------------------------------------------------
    auto *conf = new Pagina;
    conf->setTitle(tr("Configuración"));
    conf->setSubTitle(tr("Todo se puede cambiar después en server.properties (y la memoria, desde el panel)."));
    spinRam = new QSpinBox;
    spinRam->setRange(1, 64);
    spinRam->setValue(6);
    spinRam->setSuffix(tr(" GB"));
    editMotd = new QLineEdit;
    editMotd->setMaxLength(60);
    editMotd->setPlaceholderText(tr("El texto que se ve en la lista de servidores (si está vacío, el nombre)"));
    comboModo = new QComboBox;
    comboModo->addItem(tr("Supervivencia"), QStringLiteral("survival"));
    comboModo->addItem(tr("Creativo"), QStringLiteral("creative"));
    comboModo->addItem(tr("Aventura"), QStringLiteral("adventure"));
    comboModo->addItem(tr("Espectador"), QStringLiteral("spectator"));
    comboDificultad = new QComboBox;
    comboDificultad->addItem(tr("Pacífico"), QStringLiteral("peaceful"));
    comboDificultad->addItem(tr("Fácil"), QStringLiteral("easy"));
    comboDificultad->addItem(tr("Normal"), QStringLiteral("normal"));
    comboDificultad->addItem(tr("Difícil"), QStringLiteral("hard"));
    comboDificultad->setCurrentIndex(2);
    checkHardcore = new QCheckBox(tr("Hardcore (una sola vida, siempre en difícil)"));
    spinJugadores = new QSpinBox;
    spinJugadores->setRange(1, 500);
    spinJugadores->setValue(20);
    editSemilla = new QLineEdit;
    editSemilla->setMaxLength(64);
    editSemilla->setPlaceholderText(tr("Vacía: al azar"));
    spinDistancia = new QSpinBox;
    spinDistancia->setRange(2, 32);
    spinDistancia->setValue(10);
    spinDistancia->setSuffix(tr(" chunks"));
    checkWhitelist = new QCheckBox(tr("Lista blanca (solo entran los que agregues con «whitelist add»)"));
    checkPvp = new QCheckBox(tr("PvP (los jugadores se pueden lastimar entre ellos)"));
    checkPvp->setChecked(true);
    checkOnline = new QCheckBox(tr("Comprobar cuentas de Minecraft (online-mode; desmarcarlo deja entrar a cualquiera)"));
    checkOnline->setChecked(true);
    checkEula = new QCheckBox(tr("Acepto el EULA de Minecraft (lo pide Mojang para cualquier servidor)"));
    auto *linkEula = new QLabel(QStringLiteral("<a href=\"https://aka.ms/MinecraftEULA\">%1</a>").arg(tr("Leer el EULA")));
    linkEula->setOpenExternalLinks(true);
    auto *formConf = new QFormLayout;
    formConf->addRow(tr("Memoria máxima:"), spinRam);
    formConf->addRow(tr("Mensaje (MOTD):"), editMotd);
    formConf->addRow(tr("Modo de juego:"), comboModo);
    formConf->addRow(tr("Dificultad:"), comboDificultad);
    formConf->addRow(QString(), checkHardcore);
    formConf->addRow(tr("Jugadores (máximo):"), spinJugadores);
    formConf->addRow(tr("Semilla:"), editSemilla);
    formConf->addRow(tr("Distancia de visión:"), spinDistancia);
    formConf->addRow(QString(), checkPvp);
    formConf->addRow(QString(), checkWhitelist);
    formConf->addRow(QString(), checkOnline);
    auto *capaConf = new QVBoxLayout(conf);
    capaConf->addLayout(formConf);
    capaConf->addSpacing(10);
    auto *filaEula = new QHBoxLayout;
    filaEula->addWidget(checkEula);
    filaEula->addWidget(linkEula);
    filaEula->addStretch();
    capaConf->addLayout(filaEula);
    capaConf->addStretch();
    conf->completa = [this] { return configuracionCompleta(); };
    connect(checkEula, &QCheckBox::toggled, conf, [conf] { conf->avisar(); });
    connect(checkHardcore, &QCheckBox::toggled, this, [this](bool hc) {
        comboDificultad->setEnabled(!hc);
        if (hc) comboDificultad->setCurrentIndex(3);
    });
    setPage(PasoConfiguracion, conf);

    // --- 5. Resumen -----------------------------------------------------------------------------------
    auto *res = new Pagina;
    res->setTitle(tr("Resumen"));
    res->setSubTitle(tr("Revisá que esté todo bien. Al crear se baja todo lo necesario (puede tardar unos minutos); "
                        "si algo falla o lo cancelás, no queda nada a medias."));
    textoResumen = new QPlainTextEdit;
    textoResumen->setReadOnly(true);
    auto *capaRes = new QVBoxLayout(res);
    capaRes->addWidget(textoResumen);
    res->alEntrar = [this] { armarResumen(); };
    setPage(PasoResumen, res);

    // --- Consultas ------------------------------------------------------------------------------------
    connect(&opciones, &ProcesoLogica::evento, this, &AsistenteMinecraft::eventoOpciones);
    connect(&opciones, &ProcesoLogica::terminado, this, [this, soft](int codigo) {
        opcionesListas = codigo == 0 && !ordenVersiones.isEmpty();
        if (!opcionesListas)
            tema::mostrarEstado(estadoOpciones, tr("No se pudieron consultar las versiones de Minecraft (¿hay internet?). "
                                                   "Cerrá el asistente y probá de nuevo."), tema::Estado::Error);
        llenarVersiones();
        soft->avisar();
    });
    connect(&busqueda, &ProcesoLogica::evento, this, &AsistenteMinecraft::eventoBusqueda);
    connect(&busqueda, &ProcesoLogica::terminado, this, [this](int codigo) {
        QListWidget *lista = buscandoModpack ? listaModpacks : listaResultados;
        QLabel *estado = buscandoModpack ? estadoModpack : estadoBusqueda;
        if (codigo != 0)
            tema::mostrarEstado(estado, tr("No se pudo buscar en Modrinth (¿hay internet?)."), tema::Estado::Error);
        else if (lista->count() == 0)
            tema::mostrarEstado(estado, tr("No encontré nada que sirva para esta versión."), tema::Estado::Aviso);
        else
            tema::mostrarEstado(estado, buscandoModpack ? tr("Elegí un modpack y su versión.")
                                                        : tr("Doble clic (o «Agregar») para sumarlo. Las dependencias obligatorias se agregan solas al crear."));
    });
    connect(&versionesModpack, &ProcesoLogica::evento, this, &AsistenteMinecraft::eventoModpack);
    connect(&versionesModpack, &ProcesoLogica::terminado, this, [this, pack](int codigo) {
        if (codigo != 0 && comboVersionModpack->count() == 0 && estadoModpack->text().isEmpty())
            tema::mostrarEstado(estadoModpack, tr("No se pudieron consultar sus versiones."), tema::Estado::Error);
        else if (comboVersionModpack->count() > 0)
            tema::mostrarEstado(estadoModpack, tr("La versión elegida decide Minecraft y el cargador."));
        pack->avisar();
    });
    tema::mostrarEstado(estadoOpciones, tr("Consultando las versiones de Minecraft…"));
    opciones.iniciar(script, {QStringLiteral("opciones")});
    actualizarRuta();
}

AsistenteMinecraft::~AsistenteMinecraft()
{
    opciones.cancelarYEsperar();
    busqueda.cancelarYEsperar();
    versionesModpack.cancelarYEsperar();
}

// --- Datos ----------------------------------------------------------------------------------------------

bool AsistenteMinecraft::conModpack() const
{
    return radioModpack->isChecked();
}

QString AsistenteMinecraft::tipo() const
{
    if (conModpack()) {
        const int i = comboVersionModpack->currentIndex();
        return i >= 0 && i < versionesDelModpack.size() ? versionesDelModpack.at(i).cargador : QString();
    }
    const QAbstractButton *b = grupoSoftware->checkedButton();
    return b ? b->property("tipo").toString() : QString();
}

QString AsistenteMinecraft::version() const
{
    if (conModpack()) {
        const int i = comboVersionModpack->currentIndex();
        return i >= 0 && i < versionesDelModpack.size() ? versionesDelModpack.at(i).juego : QString();
    }
    return comboVersion->currentData().toString();
}

QString AsistenteMinecraft::titulo() const
{
    return QStringLiteral("%1 %2 (%3)").arg(version(), editNombre->text().trimmed(), comboGrupo->currentText().trimmed());
}

bool AsistenteMinecraft::baseCompleta() const
{
    return nombreValido(comboGrupo->currentText().trimmed()) && nombreValido(editNombre->text().trimmed());
}

int AsistenteMinecraft::despuesDeBase() const
{
    return conModpack() ? PasoModpack : PasoSoftware;
}

bool AsistenteMinecraft::softwareCompleto() const
{
    const QString v = version();
    if (tipo().isEmpty() || v.isEmpty())
        return false;
    const QString ruta = QStringLiteral("%1/%2/%3 %4").arg(comboGrupo->currentText().trimmed(), menorDe(v), v,
                                                           editNombre->text().trimmed());
    return !existentes.contains(ruta);
}

bool AsistenteMinecraft::configuracionCompleta() const
{
    return checkEula->isChecked();
}

void AsistenteMinecraft::actualizarRuta()
{
    const QString grupo = comboGrupo->currentText().trimmed();
    const QString nombre = editNombre->text().trimmed();
    const QString v = version();
    QString texto;
    if (!grupo.isEmpty() && !nombreValido(grupo))
        texto = tr("El grupo solo puede tener letras, números, espacios y . _ - ( ) + (hasta 40).");
    else if (!nombre.isEmpty() && !nombreValido(nombre))
        texto = tr("El nombre solo puede tener letras, números, espacios y . _ - ( ) + (hasta 40).");
    else if (!grupo.isEmpty() && !nombre.isEmpty()) {
        const QString ruta = v.isEmpty() ? QStringLiteral("%1/…/<versión> %2").arg(grupo, nombre)
                                         : QStringLiteral("%1/%2/%3 %4").arg(grupo, menorDe(v), v, nombre);
        if (!v.isEmpty() && existentes.contains(ruta)) {
            tema::mostrarEstado(etiquetaRuta, tr("Ya existe un servidor en Servidores/%1.").arg(ruta), tema::Estado::Error);
            tema::mostrarEstado(estadoOpciones, tr("Ya existe un servidor en Servidores/%1: cambiá el nombre o la versión.").arg(ruta),
                                tema::Estado::Error);
            return;
        }
        texto = tr("Va a quedar en Servidores/%1 y aparece solo en la lista del panel.").arg(ruta);
        if (opcionesListas)
            tema::mostrarEstado(estadoOpciones, texto);
    }
    tema::mostrarEstado(etiquetaRuta, texto, texto.startsWith(tr("El ")) ? tema::Estado::Error : tema::Estado::Neutro);
}

// --- Versiones -------------------------------------------------------------------------------------------

void AsistenteMinecraft::eventoOpciones(const QString &palabra, const QString &resto)
{
    if (palabra == u"VERSION") {
        const QString v = resto.section(u'\t', 0, 0);
        software.insert(v, resto.section(u'\t', 1).split(u',', Qt::SkipEmptyParts));
        ordenVersiones << v;
    } else if (palabra == u"GRUPO") {
        if (comboGrupo->findText(resto) < 0) {
            const QString escrito = comboGrupo->currentText();
            comboGrupo->addItem(resto);
            comboGrupo->setCurrentText(escrito);
        }
    } else if (palabra == u"JAVA") {
        javas << resto;
    } else if (palabra == u"AVISO") {
        tema::mostrarEstado(estadoOpciones, resto, tema::Estado::Aviso);
    }
}

void AsistenteMinecraft::llenarVersiones()
{
    const QAbstractButton *elegido = grupoSoftware->checkedButton();
    const QString t = elegido ? elegido->property("tipo").toString() : QString();
    // Software sin ninguna versión (p. ej. no se pudo consultar Fabric): se desactiva
    for (QAbstractButton *b : grupoSoftware->buttons()) {
        bool hay = false;
        for (const QString &v : std::as_const(ordenVersiones))
            hay = hay || software.value(v).contains(b->property("tipo").toString());
        b->setEnabled(!opcionesListas || hay);
    }
    const QString antes = comboVersion->currentData().toString();
    const QSignalBlocker bloqueo(comboVersion);
    comboVersion->clear();
    bool primera = true;
    for (const QString &v : std::as_const(ordenVersiones)) {
        if (!software.value(v).contains(t))
            continue;
        comboVersion->addItem(primera ? tr("%1 (la más nueva)").arg(v) : v, v);
        primera = false;
    }
    const int i = comboVersion->findData(antes);
    comboVersion->setCurrentIndex(i >= 0 ? i : 0);
    actualizarRuta();
}

// --- Modrinth ---------------------------------------------------------------------------------------------

void AsistenteMinecraft::buscar(bool modpack)
{
    busqueda.cancelarYEsperar();
    buscandoModpack = modpack;
    if (modpack) {
        listaModpacks->clear();
        tema::mostrarEstado(estadoModpack, tr("Buscando en Modrinth…"));
        busqueda.iniciar(script, {QStringLiteral("buscar-modrinth"), QStringLiteral("modpack"), QStringLiteral("fabric"),
                                  QString(), sinSaltos(editBuscarModpack->text())});
    } else {
        listaResultados->clear();
        tema::mostrarEstado(estadoBusqueda, tr("Buscando en Modrinth…"));
        busqueda.iniciar(script, {QStringLiteral("buscar-modrinth"), QStringLiteral("complemento"), tipo(), version(),
                                  sinSaltos(editBuscar->text())});
    }
}

void AsistenteMinecraft::eventoBusqueda(const QString &palabra, const QString &resto)
{
    if (palabra != u"RESULTADO")
        return;
    // RESULTADO slug<tab>nombre<tab>descripción<tab>descargas<tab>cargadores
    const QStringList c = resto.split(u'\t');
    if (c.size() < 5)
        return;
    const QString descargas = QLocale().toString(c.at(3).toLongLong());
    auto *item = new QListWidgetItem(QStringLiteral("%1 — %2\n%3 descargas · %4").arg(c.at(1), c.at(2), descargas, c.at(4)),
                                     buscandoModpack ? listaModpacks : listaResultados);
    item->setData(Qt::UserRole, c.at(0));
    item->setData(Qt::UserRole + 1, c.at(1));
}

void AsistenteMinecraft::elegirModpack()
{
    const QListWidgetItem *item = listaModpacks->currentItem();
    versionesModpack.cancelarYEsperar();
    comboVersionModpack->clear();
    versionesDelModpack.clear();
    if (!item)
        return;
    modpackElegido = item->data(Qt::UserRole + 1).toString();
    tema::mostrarEstado(estadoModpack, tr("Consultando las versiones de %1…").arg(modpackElegido));
    versionesModpack.iniciar(script, {QStringLiteral("modpack-versiones"), item->data(Qt::UserRole).toString()});
}

void AsistenteMinecraft::eventoModpack(const QString &palabra, const QString &resto)
{
    if (palabra == u"ERROR") {
        tema::mostrarEstado(estadoModpack, resto, tema::Estado::Error);
        return;
    }
    if (palabra != u"MODPACK")
        return;
    // MODPACK id<tab>nombre<tab>versión de Minecraft<tab>cargador<tab>url<tab>sha512<tab>archivo
    const QStringList c = resto.split(u'\t');
    if (c.size() < 7)
        return;
    versionesDelModpack.append({c.at(1), c.at(2), c.at(3), c.at(4), c.at(5)});
    comboVersionModpack->addItem(QStringLiteral("%1 · %2 %3").arg(c.at(1), nombreSoftware(c.at(3)), c.at(2)));
}

void AsistenteMinecraft::prepararContenido()
{
    const QString t = tipo();
    const QString v = version();
    const bool usa = t != u"vanilla";
    // Si cambió el software o la versión, lo elegido antes puede no servir: se vacía
    const QString clave = t + u'|' + v;
    if (listaElegidos->property("para").toString() != clave) {
        if (listaElegidos->count() > 0)
            tema::mostrarEstado(estadoBusqueda, tr("Cambiaste el software o la versión: elegí los plugins o mods de nuevo."),
                                tema::Estado::Aviso);
        listaElegidos->clear();
        listaResultados->clear();
        listaElegidos->setProperty("para", clave);
    }
    for (QWidget *w : {static_cast<QWidget *>(editBuscar), static_cast<QWidget *>(botonBuscar), static_cast<QWidget *>(botonAgregar),
                       static_cast<QWidget *>(botonArchivo), static_cast<QWidget *>(botonQuitar),
                       static_cast<QWidget *>(listaResultados), static_cast<QWidget *>(listaElegidos)})
        w->setEnabled(usa);
    if (t == u"paper")
        etiquetaComplementos->setText(tr("Plugins para Paper %1 (de Modrinth). Solo aparecen los que tienen versión para %1.").arg(v));
    else if (usa)
        etiquetaComplementos->setText((conModpack() ? tr("Mods además de los del modpack. ") : QString())
                                      + tr("Mods de %1 para %2 (de Modrinth). Solo aparecen los que funcionan en servidores y tienen versión para %2.")
                                            .arg(nombreSoftware(t), v));
    else
        etiquetaComplementos->setText(tr("Un servidor Vanilla no usa plugins ni mods. Para eso, volvé y elegí Paper (plugins) o Fabric/Forge (mods)."));
}

void AsistenteMinecraft::agregarComplemento()
{
    const QListWidgetItem *r = listaResultados->currentItem();
    if (!r)
        return;
    const QString linea = QStringLiteral("COMPLEMENTO=") + r->data(Qt::UserRole).toString();
    for (int i = 0; i < listaElegidos->count(); ++i)
        if (listaElegidos->item(i)->data(Qt::UserRole).toString() == linea)
            return;
    auto *item = new QListWidgetItem(r->data(Qt::UserRole + 1).toString(), listaElegidos);
    item->setData(Qt::UserRole, linea);
}

void AsistenteMinecraft::agregarArchivo()
{
    const QString archivo = QFileDialog::getOpenFileName(this, tr("Elegí un plugin o mod (.jar)"), QDir::homePath(),
                                                         tr("Plugins y mods (*.jar)"));
    if (archivo.isEmpty())
        return;
    auto *item = new QListWidgetItem(tr("%1 (del disco)").arg(QFileInfo(archivo).fileName()), listaElegidos);
    item->setData(Qt::UserRole, QStringLiteral("COMPLEMENTO_ARCHIVO=") + archivo);
    tema::mostrarEstado(estadoBusqueda, tr("Al crear se comprueba que el .jar sea %1.")
                                            .arg(tipo() == u"paper" ? tr("un plugin de Paper") : tr("un mod de %1").arg(nombreSoftware(tipo()))));
}

void AsistenteMinecraft::elegirMundo(bool carpeta)
{
    const QString ruta = carpeta
        ? QFileDialog::getExistingDirectory(this, tr("Elegí la carpeta del mundo (la que tiene level.dat)"), QDir::homePath())
        : QFileDialog::getOpenFileName(this, tr("Elegí el mundo comprimido"), QDir::homePath(), tr("Mundos (*.zip)"));
    if (ruta.isEmpty())
        return;
    editMundo->setText(ruta);
    grupoMundo->button(1)->setChecked(true);
}

// --- Resultado --------------------------------------------------------------------------------------------

void AsistenteMinecraft::armarResumen()
{
    QStringList l;
    const QString t = tipo();
    const QString v = version();
    l << tr("Servidor: %1").arg(titulo());
    l << tr("Carpeta: Servidores/%1/%2/%3 %4").arg(comboGrupo->currentText().trimmed(), menorDe(v), v, editNombre->text().trimmed());
    if (conModpack())
        l << tr("Modpack: %1 %2 (%3 %4)").arg(modpackElegido, versionesDelModpack.value(comboVersionModpack->currentIndex()).nombre,
                                              nombreSoftware(t), v);
    else
        l << tr("Software: %1 %2").arg(nombreSoftware(t), v);
    const int m = grupoMundo->checkedId();
    l << tr("Mundo: %1").arg(m == 1 ? editMundo->text() : m == 2 ? comboMundoServidor->currentText() : tr("uno nuevo"));
    QStringList comp;
    for (int i = 0; i < listaElegidos->count(); ++i)
        comp << listaElegidos->item(i)->text();
    l << (t == u"paper" ? tr("Plugins: %1") : tr("Mods: %1")).arg(comp.isEmpty() ? tr("ninguno") : comp.join(QStringLiteral(", ")));
    l << tr("Memoria: hasta %1 GB · %2 · %3%4 · hasta %5 jugadores")
             .arg(spinRam->value()).arg(comboModo->currentText(), comboDificultad->currentText(),
                  checkHardcore->isChecked() ? tr(" · hardcore") : QString()).arg(spinJugadores->value());
    l << tr("Semilla: %1 · Distancia: %2 chunks · PvP: %3 · Lista blanca: %4 · Comprobar cuentas: %5")
             .arg(editSemilla->text().isEmpty() ? tr("al azar") : editSemilla->text()).arg(spinDistancia->value())
             .arg(checkPvp->isChecked() ? tr("sí") : tr("no"), checkWhitelist->isChecked() ? tr("sí") : tr("no"),
                  checkOnline->isChecked() ? tr("sí") : tr("no"));
    l << QString() << tr("El Java lo elige solo según la versión (si falta el que pide, avisa qué instalar).");
    textoResumen->setPlainText(l.join(u'\n'));
}

QByteArray AsistenteMinecraft::configuracion() const
{
    QStringList l;
    auto poner = [&l](const QString &clave, const QString &valor) { l << clave + u'=' + sinSaltos(valor); };
    poner(QStringLiteral("GRUPO"), comboGrupo->currentText());
    poner(QStringLiteral("NOMBRE"), editNombre->text());
    poner(QStringLiteral("TIPO"), tipo());
    poner(QStringLiteral("VERSION"), version());
    poner(QStringLiteral("EULA"), checkEula->isChecked() ? QStringLiteral("true") : QStringLiteral("false"));
    if (conModpack()) {
        const VersionModpack vm = versionesDelModpack.value(comboVersionModpack->currentIndex());
        poner(QStringLiteral("MODPACK_URL"), vm.url);
        poner(QStringLiteral("MODPACK_SHA512"), vm.sha512);
    }
    poner(QStringLiteral("RAM"), QString::number(spinRam->value()) + u'G');
    if (!editMotd->text().trimmed().isEmpty())
        poner(QStringLiteral("MOTD"), editMotd->text());
    poner(QStringLiteral("MODO"), comboModo->currentData().toString());
    poner(QStringLiteral("DIFICULTAD"), comboDificultad->currentData().toString());
    auto si = [](bool b) { return b ? QStringLiteral("true") : QStringLiteral("false"); };
    poner(QStringLiteral("HARDCORE"), si(checkHardcore->isChecked()));
    poner(QStringLiteral("JUGADORES"), QString::number(spinJugadores->value()));
    poner(QStringLiteral("SEMILLA"), editSemilla->text());
    poner(QStringLiteral("DISTANCIA"), QString::number(spinDistancia->value()));
    poner(QStringLiteral("PVP"), si(checkPvp->isChecked()));
    poner(QStringLiteral("WHITELIST"), si(checkWhitelist->isChecked()));
    poner(QStringLiteral("ONLINE"), si(checkOnline->isChecked()));
    const int m = grupoMundo->checkedId();
    if (m == 1)
        poner(QStringLiteral("MUNDO"), editMundo->text());
    else if (m == 2)
        poner(QStringLiteral("MUNDO_SERVIDOR"), comboMundoServidor->currentData().toString());
    if (tipo() != u"vanilla")
        for (int i = 0; i < listaElegidos->count(); ++i)
            l << listaElegidos->item(i)->data(Qt::UserRole).toString();
    return (l.join(u'\n') + u'\n').toUtf8();
}

// --- Cambiar versión ------------------------------------------------------------------------------------

DialogoVersionMinecraft::DialogoVersionMinecraft(const QString &script, const QString &servidor, const QString &tipo,
                                                 const QString &version, QWidget *parent)
    : QDialog(parent), tipoActual(tipo), versionActual(version)
{
    setWindowTitle(tr("Cambiar versión de %1").arg(QStringLiteral("%1 (%2)").arg(servidor.section(u'/', -1), servidor.section(u'/', 0, 0))));
    resize(620, 420);
    auto *actual = new QLabel(tr("Ahora: %1 %2").arg(nombreSoftware(tipo), version));
    grupo = new QButtonGroup(this);
    auto *capa = new QVBoxLayout(this);
    capa->addWidget(actual);
    const QStringList tipos = {QStringLiteral("paper"), QStringLiteral("vanilla"), QStringLiteral("fabric"), QStringLiteral("forge")};
    for (int i = 0; i < tipos.size(); ++i) {
        auto *radio = new QRadioButton(nombreSoftware(tipos.at(i)));
        radio->setProperty("tipo", tipos.at(i));
        grupo->addButton(radio, i);
        capa->addWidget(radio);
        if (tipos.at(i) == tipo)
            radio->setChecked(true);
    }
    if (!grupo->checkedButton())
        grupo->button(0)->setChecked(true);
    comboVersion = new QComboBox;
    auto *form = new QFormLayout;
    form->addRow(tr("Versión de Minecraft:"), comboVersion);
    capa->addLayout(form);
    aviso = new QLabel;
    aviso->setWordWrap(true);
    capa->addWidget(aviso, 1);
    auto *botones = new QDialogButtonBox(QDialogButtonBox::Cancel);
    botonCambiar = botones->addButton(tr("Cambiar"), QDialogButtonBox::AcceptRole);
    tema::marcarPrimario(botonCambiar);
    botonCambiar->setEnabled(false);
    capa->addWidget(botones);
    connect(botones, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(botones, &QDialogButtonBox::rejected, this, &QDialog::reject);
    connect(grupo, &QButtonGroup::idToggled, this, [this](int, bool marcado) { if (marcado) llenar(); });
    connect(comboVersion, &QComboBox::currentIndexChanged, this, &DialogoVersionMinecraft::explicar);
    connect(&opciones, &ProcesoLogica::evento, this, [this](const QString &palabra, const QString &resto) {
        if (palabra != u"VERSION")
            return;
        const QString v = resto.section(u'\t', 0, 0);
        software.insert(v, resto.section(u'\t', 1).split(u',', Qt::SkipEmptyParts));
        orden << v;
    });
    connect(&opciones, &ProcesoLogica::terminado, this, [this](int codigo) {
        if (codigo != 0 || orden.isEmpty())
            tema::mostrarEstado(aviso, tr("No se pudieron consultar las versiones de Minecraft (¿hay internet?)."), tema::Estado::Error);
        llenar();
    });
    tema::mostrarEstado(aviso, tr("Consultando las versiones de Minecraft…"));
    opciones.iniciar(script, {QStringLiteral("opciones")});
}

DialogoVersionMinecraft::~DialogoVersionMinecraft()
{
    opciones.cancelarYEsperar();
}

QString DialogoVersionMinecraft::tipoElegido() const
{
    const QAbstractButton *b = grupo->checkedButton();
    return b ? b->property("tipo").toString() : QString();
}

void DialogoVersionMinecraft::llenar()
{
    const QString t = tipoElegido();
    for (QAbstractButton *b : grupo->buttons()) {
        bool hay = false;
        for (const QString &v : std::as_const(orden))
            hay = hay || software.value(v).contains(b->property("tipo").toString());
        b->setEnabled(orden.isEmpty() || hay);
    }
    const QString antes = comboVersion->currentData().toString();
    const QSignalBlocker bloqueo(comboVersion);
    comboVersion->clear();
    for (const QString &v : std::as_const(orden))
        if (software.value(v).contains(t))
            comboVersion->addItem(v == versionActual ? tr("%1 (la que tiene)").arg(v) : v, v);
    int i = comboVersion->findData(antes.isEmpty() ? versionActual : antes);
    comboVersion->setCurrentIndex(i >= 0 ? i : 0);
    explicar();
}

void DialogoVersionMinecraft::explicar()
{
    const QString t = tipoElegido();
    const QString v = comboVersion->currentData().toString();
    botonCambiar->setEnabled(!v.isEmpty());
    if (v.isEmpty())
        return;
    QStringList l;
    const bool usaba = tipoActual != u"vanilla", usa = t != u"vanilla";
    const QString claseAntes = tipoActual == u"paper" ? tr("plugins") : tr("mods");
    if (t == tipoActual && v == versionActual) {
        l << (t == u"fabric" || t == u"forge" ? tr("Actualiza el cargador de %1 al último recomendado para %2.").arg(nombreSoftware(t), v)
              : t == u"paper" ? tr("Baja la última compilación de Paper %1 (lo mismo que «Actualizar Paper»).").arg(v)
                              : tr("Vuelve a bajar el servidor oficial %1.").arg(v));
    } else {
        l << tr("Pasa de %1 %2 a %3 %4.").arg(nombreSoftware(tipoActual), versionActual, nombreSoftware(t), v);
        if (usaba && !usa)
            l << tr("Vanilla no usa plugins ni mods: los que tiene quedan guardados en Respaldos.");
        else if (usaba && usa)
            l << tr("Los %1 pasan a su versión para %2 %3 (el mismo proyecto en Modrinth, también de plugin a mod); "
                    "los que no tengan quedan en Respaldos. Las dependencias que falten se agregan solas.").arg(claseAntes, nombreSoftware(t), v);
        if (QVersionNumber::fromString(v) < QVersionNumber::fromString(versionActual))
            l << tr("Ojo: es una versión más vieja. Si el mundo ya se abrió en %1, no se va a poder (se comprueba antes de tocar nada).").arg(versionActual);
        if (v != versionActual)
            l << tr("Si la carpeta lleva la versión en el nombre («%1 …»), pasa a la de %2.").arg(versionActual, v);
    }
    l << tr("Antes se guarda el mundo en Respaldos; el jar anterior también queda ahí.");
    tema::mostrarEstado(aviso, l.join(QStringLiteral("\n\n")));
}

QByteArray DialogoVersionMinecraft::configuracion() const
{
    return QStringLiteral("TIPO=%1\nVERSION=%2\n").arg(tipoElegido(), comboVersion->currentData().toString()).toUtf8();
}

QString DialogoVersionMinecraft::descripcion() const
{
    return nombreSoftware(tipoElegido()) + u' ' + comboVersion->currentData().toString();
}
