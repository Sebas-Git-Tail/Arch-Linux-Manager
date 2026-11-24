#include "PestanasMinecraft.h"
#include "Tema.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDir>
#include <QFileDialog>
#include <QFormLayout>
#include <QGridLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QImage>
#include <QInputDialog>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollArea>
#include <QSpinBox>
#include <QStandardPaths>
#include <QTreeWidget>
#include <QVBoxLayout>

// --- Base ---------------------------------------------------------------------------------------------------

PestanaServidor::PestanaServidor(const QString &script_, QWidget *parent)
    : QWidget(parent), script(script_)
{
}

PestanaServidor::~PestanaServidor()
{
    consulta.cancelarYEsperar();
}

void PestanaServidor::elegir(const QString &servidor_, bool encendido_, const QString &tipo_)
{
    const bool cambio = servidor_ != servidor || encendido_ != encendido || tipo_ != tipo;
    servidor = servidor_;
    encendido = encendido_;
    tipo = tipo_;
    if (cambio)
        refrescar();
}

void PestanaServidor::ponerOcupado(bool ocupado_)
{
    ocupado = ocupado_;
    actualizarBotones();
}

QString PestanaServidor::etiqueta() const
{
    const int barra = servidor.indexOf(u'/');
    return barra < 0 ? servidor : QStringLiteral("%1 (%2)").arg(servidor.section(u'/', -1), servidor.left(barra));
}

// --- Jugadores ----------------------------------------------------------------------------------------------

namespace {
constexpr int RolNombre = Qt::UserRole;
constexpr int RolOp = Qt::UserRole + 1;
constexpr int RolBlanca = Qt::UserRole + 2;
constexpr int RolBan = Qt::UserRole + 3;
constexpr int RolConectado = Qt::UserRole + 4;
}

PestanaJugadores::PestanaJugadores(const QString &script_, QWidget *parent)
    : PestanaServidor(script_, parent)
{
    estado = new QLabel;
    estado->setWordWrap(true);
    checkBlanca = new QCheckBox(tr("Lista blanca activada (solo entran los de la lista)"));
    lista = new QTreeWidget;
    lista->setRootIsDecorated(false);
    lista->setHeaderLabels({tr("Jugador"), tr("Conectado"), tr("Op"), tr("Lista blanca"), tr("Baneado"), tr("Última vez")});
    lista->header()->setSectionResizeMode(0, QHeaderView::Stretch);
    for (int c = 1; c < 6; ++c)
        lista->header()->setSectionResizeMode(c, QHeaderView::ResizeToContents);
    botonOp = new QPushButton(tr("Hacer op"));
    botonBlanca = new QPushButton(tr("A la lista blanca"));
    botonBan = new QPushButton(tr("Banear…"));
    botonExpulsar = new QPushButton(tr("Expulsar…"));
    tema::marcarPeligro(botonBan);
    editNombre = new QLineEdit;
    editNombre->setPlaceholderText(tr("Otro jugador (nombre exacto de Minecraft)"));
    editNombre->setMaxLength(17);
    botonAgregarBlanca = new QPushButton(tema::icono(QStringLiteral("agregar")), tr("Lista blanca"));
    botonAgregarOp = new QPushButton(tema::icono(QStringLiteral("agregar")), tr("Op"));

    auto *filaBotones = new QHBoxLayout;
    for (QPushButton *b : {botonOp, botonBlanca, botonBan, botonExpulsar})
        filaBotones->addWidget(b);
    filaBotones->addStretch();
    auto *filaAgregar = new QHBoxLayout;
    filaAgregar->addWidget(editNombre, 1);
    filaAgregar->addWidget(botonAgregarBlanca);
    filaAgregar->addWidget(botonAgregarOp);
    auto *capa = new QVBoxLayout(this);
    capa->addWidget(estado);
    capa->addWidget(checkBlanca);
    capa->addWidget(lista, 1);
    capa->addLayout(filaBotones);
    capa->addLayout(filaAgregar);

    connect(&consulta, &ProcesoLogica::evento, this, &PestanaJugadores::evento);
    connect(&consulta, &ProcesoLogica::terminado, this, [this] { actualizarBotones(); });
    connect(lista, &QTreeWidget::currentItemChanged, this, [this] { actualizarBotones(); });
    connect(botonOp, &QPushButton::clicked, this, [this] {
        const QTreeWidgetItem *i = lista->currentItem();
        if (i) hacer(i->data(0, RolOp).toBool() ? QStringLiteral("deop") : QStringLiteral("op"), elegido());
    });
    connect(botonBlanca, &QPushButton::clicked, this, [this] {
        const QTreeWidgetItem *i = lista->currentItem();
        if (i) hacer(i->data(0, RolBlanca).toBool() ? QStringLiteral("whitelist-remove") : QStringLiteral("whitelist-add"), elegido());
    });
    connect(botonBan, &QPushButton::clicked, this, [this] {
        const QTreeWidgetItem *i = lista->currentItem();
        if (!i) return;
        if (i->data(0, RolBan).toBool()) hacer(QStringLiteral("pardon"), elegido());
        else hacer(QStringLiteral("ban"), elegido(), true);
    });
    connect(botonExpulsar, &QPushButton::clicked, this, [this] { hacer(QStringLiteral("kick"), elegido(), true); });
    connect(botonAgregarBlanca, &QPushButton::clicked, this, [this] { hacer(QStringLiteral("whitelist-add"), editNombre->text().trimmed()); });
    connect(botonAgregarOp, &QPushButton::clicked, this, [this] { hacer(QStringLiteral("op"), editNombre->text().trimmed()); });
    connect(editNombre, &QLineEdit::textChanged, this, [this] { actualizarBotones(); });
    connect(checkBlanca, &QCheckBox::clicked, this, [this](bool activar) {
        emit accion({QStringLiteral("jugador"), servidor, activar ? QStringLiteral("lista-blanca-si") : QStringLiteral("lista-blanca-no")},
                    activar ? tr("Activando la lista blanca…") : tr("Desactivando la lista blanca…"), {});
    });
    actualizarBotones();
}

void PestanaJugadores::refrescar()
{
    consulta.cancelarYEsperar();
    lista->clear();
    consolaComandos = false;
    if (servidor.isEmpty()) {
        tema::mostrarEstado(estado, tr("Elegí un servidor para ver sus jugadores."));
        actualizarBotones();
        return;
    }
    tema::mostrarEstado(estado, tr("Consultando…"));
    consulta.iniciar(script, {QStringLiteral("jugadores-lista"), servidor});
    actualizarBotones();
}

void PestanaJugadores::evento(const QString &palabra, const QString &resto)
{
    if (palabra == u"CONSOLA") {
        consolaComandos = resto == u"COMANDOS";
        tema::mostrarEstado(estado, resto == u"APAGADO"
            ? tr("%1 está apagado: los cambios se guardan en sus archivos (los ve al prenderlo).").arg(etiqueta())
            : consolaComandos ? tr("%1 está prendido: los cambios se hacen con sus comandos, al instante.").arg(etiqueta())
                              : tr("%1 se prendió sin consola compartida: reinicialo desde el panel para administrar jugadores.").arg(etiqueta()),
            resto == u"SOLO_LECTURA" ? tema::Estado::Aviso : tema::Estado::Neutro);
    } else if (palabra == u"LISTA_BLANCA") {
        const QSignalBlocker b(checkBlanca);
        checkBlanca->setChecked(resto == u"true");
    } else if (palabra == u"JUGADOR") {
        // JUGADOR nombre<tab>uuid<tab>conectado<tab>nivel op<tab>lista blanca<tab>baneado<tab>motivo<tab>visto
        const QStringList c = resto.split(u'\t');
        if (c.size() < 8)
            return;
        auto *item = new QTreeWidgetItem(lista);
        const bool conectado = c.at(2) == u"1", op = !c.at(3).isEmpty(), blanca = c.at(4) == u"1", ban = c.at(5) == u"1";
        item->setText(0, c.at(0));
        item->setIcon(0, tema::icono(QStringLiteral("punto"), conectado ? tema::colores().ok : tema::colores().texto3));
        item->setToolTip(0, c.at(1).isEmpty() ? c.at(0) : tr("%1\nUUID: %2").arg(c.at(0), c.at(1)));
        item->setText(1, conectado ? tr("ahora") : QString());
        item->setText(2, op ? tr("sí (nivel %1)").arg(c.at(3)) : QString());
        item->setText(3, blanca ? tr("sí") : QString());
        item->setText(4, ban ? (c.at(6).isEmpty() ? tr("sí") : tr("sí: %1").arg(c.at(6))) : QString());
        item->setText(5, c.at(7));
        if (ban)
            item->setForeground(4, tema::colores().error);
        item->setData(0, RolNombre, c.at(0));
        item->setData(0, RolOp, op);
        item->setData(0, RolBlanca, blanca);
        item->setData(0, RolBan, ban);
        item->setData(0, RolConectado, conectado);
    }
}

QString PestanaJugadores::elegido() const
{
    const QTreeWidgetItem *i = lista->currentItem();
    return i ? i->data(0, RolNombre).toString() : QString();
}

void PestanaJugadores::hacer(const QString &accionJugador, const QString &nombre, bool pedirMotivo)
{
    static const QRegularExpression valido(QStringLiteral(R"(^\.?[A-Za-z0-9_]{1,16}$)"));
    if (!valido.match(nombre).hasMatch()) {
        tema::mostrarEstado(estado, tr("El nombre tiene que ser el de Minecraft: hasta 16 letras, números o _."), tema::Estado::Error);
        return;
    }
    QString motivo;
    if (pedirMotivo) {
        bool ok = false;
        motivo = QInputDialog::getText(this, accionJugador == u"ban" ? tr("Banear a %1").arg(nombre) : tr("Expulsar a %1").arg(nombre),
                                       tr("Motivo (opcional, lo ve el jugador):"), QLineEdit::Normal, QString(), &ok).trimmed();
        if (!ok)
            return;
        motivo.truncate(100);
    }
    const QHash<QString, QString> textos = {
        {QStringLiteral("op"), tr("Haciendo op a %1…")}, {QStringLiteral("deop"), tr("Quitándole op a %1…")},
        {QStringLiteral("whitelist-add"), tr("Agregando a %1 a la lista blanca…")}, {QStringLiteral("whitelist-remove"), tr("Sacando a %1 de la lista blanca…")},
        {QStringLiteral("ban"), tr("Baneando a %1…")}, {QStringLiteral("pardon"), tr("Perdonando a %1…")}, {QStringLiteral("kick"), tr("Expulsando a %1…")}};
    QStringList args{QStringLiteral("jugador"), servidor, accionJugador, nombre};
    if (!motivo.isEmpty())
        args << motivo;
    emit accion(args, textos.value(accionJugador).arg(nombre), {});
}

void PestanaJugadores::actualizarBotones()
{
    const QTreeWidgetItem *i = lista->currentItem();
    const bool hay = !servidor.isEmpty() && !consulta.ocupado();
    const bool puede = hay && !ocupado && (!encendido || consolaComandos);
    botonOp->setText(i && i->data(0, RolOp).toBool() ? tr("Quitar op") : tr("Hacer op"));
    botonBlanca->setText(i && i->data(0, RolBlanca).toBool() ? tr("Sacar de la lista blanca") : tr("A la lista blanca"));
    botonBan->setText(i && i->data(0, RolBan).toBool() ? tr("Perdonar") : tr("Banear…"));
    for (QPushButton *b : {botonOp, botonBlanca, botonBan})
        b->setEnabled(puede && i);
    botonExpulsar->setEnabled(puede && encendido && i && i->data(0, RolConectado).toBool());
    const bool nombre = !editNombre->text().trimmed().isEmpty();
    botonAgregarBlanca->setEnabled(puede && nombre);
    botonAgregarOp->setEnabled(puede && nombre);
    checkBlanca->setEnabled(puede);
}

// --- Opciones -----------------------------------------------------------------------------------------------

namespace {
// Colores y formatos de Minecraft (código después de «§»)
struct ColorMc { QChar codigo; const char *color; const char *nombre; };
const ColorMc coloresMc[] = {
    {u'0', "#000000", "Negro"}, {u'1', "#0000AA", "Azul oscuro"}, {u'2', "#00AA00", "Verde oscuro"}, {u'3', "#00AAAA", "Turquesa"},
    {u'4', "#AA0000", "Rojo oscuro"}, {u'5', "#AA00AA", "Violeta"}, {u'6', "#FFAA00", "Dorado"}, {u'7', "#AAAAAA", "Gris"},
    {u'8', "#555555", "Gris oscuro"}, {u'9', "#5555FF", "Azul"}, {u'a', "#55FF55", "Verde"}, {u'b', "#55FFFF", "Celeste"},
    {u'c', "#FF5555", "Rojo"}, {u'd', "#FF55FF", "Rosa"}, {u'e', "#FFFF55", "Amarillo"}, {u'f', "#FFFFFF", "Blanco"},
};

// El MOTD con códigos «§» a HTML, como lo muestra el juego
QString motdHtml(const QString &texto)
{
    QString html, color = QStringLiteral("#AAAAAA");
    bool negrita = false, cursiva = false, subrayado = false, tachado = false;
    QString tramo;
    auto cerrar = [&] {
        if (tramo.isEmpty()) return;
        QString estilo = QStringLiteral("color:%1;").arg(color);
        if (negrita) estilo += QStringLiteral("font-weight:bold;");
        if (cursiva) estilo += QStringLiteral("font-style:italic;");
        if (subrayado || tachado) estilo += QStringLiteral("text-decoration:%1;").arg(subrayado ? "underline" : "line-through");
        html += QStringLiteral("<span style=\"%1\">%2</span>").arg(estilo, tramo.toHtmlEscaped().replace(u' ', QStringLiteral("&nbsp;")));
        tramo.clear();
    };
    for (int i = 0; i < texto.size(); ++i) {
        if (texto.at(i) == u'\n') { cerrar(); html += QStringLiteral("<br>"); continue; }
        if (texto.at(i) == u'§' && i + 1 < texto.size()) {
            const QChar c = texto.at(++i).toLower();
            cerrar();
            bool esColor = false;
            for (const ColorMc &m : coloresMc)
                if (m.codigo == c) { color = QString::fromLatin1(m.color); esColor = true; }
            if (esColor) { negrita = cursiva = subrayado = tachado = false; }
            else if (c == u'l') negrita = true;
            else if (c == u'o') cursiva = true;
            else if (c == u'n') subrayado = true;
            else if (c == u'm') tachado = true;
            else if (c == u'r') { color = QStringLiteral("#AAAAAA"); negrita = cursiva = subrayado = tachado = false; }
            continue;
        }
        tramo += texto.at(i);
    }
    cerrar();
    return html;
}
} // namespace

// Lo que dice el campo, como texto (para comparar con lo que mostraba al cargar)
static QString valorCampo(QWidget *campo)
{
    if (auto *c = qobject_cast<QCheckBox *>(campo)) return c->isChecked() ? QStringLiteral("true") : QStringLiteral("false");
    if (auto *c = qobject_cast<QComboBox *>(campo)) return c->currentData().toString();
    if (auto *c = qobject_cast<QSpinBox *>(campo)) return QString::number(c->value());
    if (auto *c = qobject_cast<QLineEdit *>(campo)) return c->text().trimmed();
    return {};
}

PestanaOpciones::PestanaOpciones(const QString &script_, QWidget *parent)
    : PestanaServidor(script_, parent)
{
    estado = new QLabel;
    estado->setWordWrap(true);

    // MOTD con colores (dos líneas) y su vista previa
    auto *cajaMotd = new QGroupBox(tr("Mensaje de la lista de servidores (MOTD)"));
    motd1 = new QLineEdit;
    motd2 = new QLineEdit;
    motd1->setPlaceholderText(tr("Primera línea"));
    motd2->setPlaceholderText(tr("Segunda línea (opcional)"));
    vistaMotd = new QLabel;
    vistaMotd->setTextFormat(Qt::RichText);
    vistaMotd->setMinimumHeight(48);
    vistaMotd->setStyleSheet(QStringLiteral("background:#1f1f1f; border-radius:6px; padding:6px 10px; font-family:monospace;"));
    auto *paleta = new QGridLayout;
    int n = 0;
    for (const ColorMc &m : coloresMc) {
        auto *b = new QPushButton;
        b->setFixedSize(22, 22);
        b->setFocusPolicy(Qt::NoFocus);    // así el cursor sigue en la línea que se estaba escribiendo
        b->setToolTip(tr(m.nombre));
        b->setStyleSheet(QStringLiteral("background:%1; border:1px solid #777; border-radius:4px;").arg(QString::fromLatin1(m.color)));
        const QString codigo = QStringLiteral("§") + m.codigo;
        connect(b, &QPushButton::clicked, this, [this, codigo] {
            QLineEdit *linea = motd2->hasFocus() ? motd2 : motd1;
            linea->insert(codigo);
        });
        paleta->addWidget(b, 0, n++);
    }
    const QList<QPair<QString, QString>> formatos = {{QStringLiteral("l"), tr("N")}, {QStringLiteral("o"), tr("C")},
                                                     {QStringLiteral("n"), tr("S")}, {QStringLiteral("r"), tr("Normal")}};
    const QStringList ayudas = {tr("Negrita"), tr("Cursiva"), tr("Subrayado"), tr("Vuelve al color y formato normal")};
    for (int i = 0; i < formatos.size(); ++i) {
        auto *b = new QPushButton(formatos.at(i).second);
        b->setFocusPolicy(Qt::NoFocus);
        b->setToolTip(ayudas.at(i));
        const QString codigo = QStringLiteral("§") + formatos.at(i).first;
        connect(b, &QPushButton::clicked, this, [this, codigo] { (motd2->hasFocus() ? motd2 : motd1)->insert(codigo); });
        paleta->addWidget(b, 0, n++);
    }
    paleta->setColumnStretch(n, 1);
    auto *capaMotd = new QVBoxLayout(cajaMotd);
    capaMotd->addWidget(motd1);
    capaMotd->addWidget(motd2);
    capaMotd->addLayout(paleta);
    capaMotd->addWidget(vistaMotd);

    // Apagado automático
    auto *cajaAuto = new QGroupBox(tr("Apagado automático"));
    spinVacio = new QSpinBox;
    spinVacio->setRange(0, 720);
    spinVacio->setSuffix(tr(" min sin jugadores"));
    spinVacio->setSpecialValueText(tr("Nunca"));
    checkApagarPc = new QCheckBox(tr("Después, apagar también la PC (solo si se prendió por WOL y nadie la está usando)"));
    auto *formAuto = new QFormLayout(cajaAuto);
    formAuto->addRow(tr("Apagarlo a los:"), spinVacio);
    formAuto->addRow(QString(), checkApagarPc);

    // Opciones de server.properties (se arman con lo que dice el servidor)
    auto *cajaOpciones = new QGroupBox(tr("Opciones (server.properties)"));
    formulario = new QFormLayout(cajaOpciones);

    // Extras
    auto *cajaExtras = new QGroupBox(tr("Extras"));
    botonGeyser = new QPushButton(tr("Geyser + Floodgate (amigos con Bedrock)"));
    botonGeyser->setToolTip(tr("Que entren desde el celular o la consola (Bedrock) con su cuenta de Xbox, sin tener Java"));
    botonBluemap = new QPushButton(tr("BlueMap (mapa web)"));
    botonBluemap->setToolTip(tr("Un mapa 3D del mundo que se ve en el navegador (puerto 8100). Baja recursos del juego (acepta el EULA de Mojang)."));
    botonIcono = new QPushButton(tema::icono(QStringLiteral("abrir")), tr("Ícono…"));
    botonIcono->setToolTip(tr("La imagen que se ve en la lista de servidores (se achica sola a 64×64)"));
    auto *filaExtras = new QHBoxLayout(cajaExtras);
    filaExtras->addWidget(botonGeyser);
    filaExtras->addWidget(botonBluemap);
    filaExtras->addWidget(botonIcono);
    filaExtras->addStretch();

    contenido = new QWidget;
    auto *capaContenido = new QVBoxLayout(contenido);
    capaContenido->addWidget(cajaMotd);
    capaContenido->addWidget(cajaAuto);
    capaContenido->addWidget(cajaOpciones);
    capaContenido->addWidget(cajaExtras);
    capaContenido->addStretch();
    auto *scroll = new QScrollArea;
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    scroll->setWidget(contenido);
    botonGuardar = new QPushButton(tema::icono(QStringLiteral("listo")), tr("Guardar cambios"));
    tema::marcarPrimario(botonGuardar);
    auto *filaGuardar = new QHBoxLayout;
    filaGuardar->addWidget(estado, 1);
    filaGuardar->addWidget(botonGuardar);
    auto *capa = new QVBoxLayout(this);
    capa->addWidget(scroll, 1);
    capa->addLayout(filaGuardar);

    connect(&consulta, &ProcesoLogica::evento, this, &PestanaOpciones::evento);
    connect(&consulta, &ProcesoLogica::terminado, this, [this] { armar(); });
    connect(motd1, &QLineEdit::textChanged, this, [this] { verMotd(); actualizarBotones(); });
    connect(motd2, &QLineEdit::textChanged, this, [this] { verMotd(); actualizarBotones(); });
    connect(spinVacio, &QSpinBox::valueChanged, this, [this] { actualizarBotones(); });
    connect(checkApagarPc, &QCheckBox::toggled, this, [this] { actualizarBotones(); });
    connect(botonGuardar, &QPushButton::clicked, this, &PestanaOpciones::guardar);
    connect(botonGeyser, &QPushButton::clicked, this, [this] {
        emit accion({QStringLiteral("extra"), servidor, QStringLiteral("geyser")}, tr("Instalando Geyser y Floodgate…"), {});
    });
    connect(botonBluemap, &QPushButton::clicked, this, [this] {
        if (QMessageBox::question(this, tr("BlueMap"),
                tr("BlueMap baja recursos del juego de Minecraft para dibujar el mapa, y eso es aceptar el EULA de Mojang "
                   "(https://aka.ms/MinecraftEULA). ¿Instalarlo en %1?").arg(etiqueta())) != QMessageBox::Yes)
            return;
        emit accion({QStringLiteral("extra"), servidor, QStringLiteral("bluemap")}, tr("Instalando BlueMap…"), {});
    });
    connect(botonIcono, &QPushButton::clicked, this, &PestanaOpciones::cambiarIcono);
    verMotd();
    actualizarBotones();
}

void PestanaOpciones::refrescar()
{
    consulta.cancelarYEsperar();
    opciones.clear();
    ajustes.clear();
    tieneIcono = false;
    if (servidor.isEmpty()) {
        armar();
        tema::mostrarEstado(estado, tr("Elegí un servidor para ver sus opciones."));
        return;
    }
    cargando = true;
    tema::mostrarEstado(estado, tr("Consultando…"));
    consulta.iniciar(script, {QStringLiteral("opciones-servidor"), servidor});
    actualizarBotones();
}

void PestanaOpciones::evento(const QString &palabra, const QString &resto)
{
    const QStringList c = resto.split(u'\t');
    if (palabra == u"OPCION" && c.size() >= 6) {
        // El valor viene con \\ y \n escapados
        QString valor = c.at(5);
        QString limpio;
        for (int i = 0; i < valor.size(); ++i) {
            if (valor.at(i) == u'\\' && i + 1 < valor.size()) {
                limpio += valor.at(i + 1) == u'n' ? QChar(u'\n') : valor.at(i + 1);
                ++i;
            } else {
                limpio += valor.at(i);
            }
        }
        opciones.append({c.at(0), c.at(1), c.at(2), c.at(3), c.at(4), limpio});
    } else if (palabra == u"AJUSTE" && c.size() >= 2) {
        ajustes.insert(c.at(0), c.at(1));
    } else if (palabra == u"ICONO") {
        tieneIcono = resto == u"si";
    }
}

void PestanaOpciones::armar()
{
    cargando = true;
    while (formulario->rowCount() > 0)
        formulario->removeRow(0);
    campos.clear();
    iniciales.clear();
    for (const Opcion &o : std::as_const(opciones)) {
        if (o.clave == u"motd")
            continue;
        QWidget *campo = nullptr;
        if (o.tipo == u"bool") {
            auto *c = new QCheckBox;
            c->setChecked(o.valor == u"true");
            connect(c, &QCheckBox::toggled, this, [this] { actualizarBotones(); });
            campo = c;
        } else if (o.tipo == u"enum") {
            auto *c = new QComboBox;
            for (const QString &p : o.parametros.split(u','))
                c->addItem(p.section(u'=', 1), p.section(u'=', 0, 0));
            const int i = c->findData(o.valor);
            c->setCurrentIndex(i >= 0 ? i : 0);
            connect(c, &QComboBox::currentIndexChanged, this, [this] { actualizarBotones(); });
            campo = c;
        } else if (o.tipo == u"int") {
            auto *c = new QSpinBox;
            c->setRange(o.parametros.section(u':', 0, 0).toInt(), o.parametros.section(u':', 1).toInt());
            c->setValue(o.valor.toInt());
            connect(c, &QSpinBox::valueChanged, this, [this] { actualizarBotones(); });
            campo = c;
        } else {
            auto *c = new QLineEdit(o.valor);
            c->setMaxLength(o.parametros.toInt());
            connect(c, &QLineEdit::textChanged, this, [this] { actualizarBotones(); });
            campo = c;
        }
        campo->setToolTip(o.ayuda);
        auto *ayuda = new QLabel(o.ayuda);
        ayuda->setWordWrap(true);
        ayuda->setStyleSheet(QStringLiteral("color:%1;").arg(tema::colores().texto3.name()));
        auto *celda = new QWidget;
        auto *capa = new QVBoxLayout(celda);
        capa->setContentsMargins(0, 0, 0, 4);
        capa->setSpacing(1);
        capa->addWidget(campo, 0, Qt::AlignLeft);
        capa->addWidget(ayuda);
        formulario->addRow(o.etiqueta + u':', celda);
        campos.insert(o.clave, campo);
        iniciales.insert(o.clave, valorCampo(campo));
    }
    const QStringList lineasMotd = valorDe(QStringLiteral("motd")).split(u'\n');
    motd1->setText(lineasMotd.value(0));
    motd2->setText(lineasMotd.value(1));
    spinVacio->setValue(ajustes.value(QStringLiteral("APAGAR_VACIO"), QStringLiteral("10")).toInt());
    checkApagarPc->setChecked(ajustes.value(QStringLiteral("APAGAR_PC"), QStringLiteral("si")) == u"si");
    motdInicial = motd();
    cargando = false;
    if (!servidor.isEmpty())
        tema::mostrarEstado(estado, encendido ? tr("Está prendido: lo que cambies se aplica al reiniciarlo.")
                                              : tr("Pasá el mouse por cada opción para ver qué hace."));
    botonIcono->setText(tieneIcono ? tr("Cambiar ícono…") : tr("Ícono…"));
    verMotd();
    actualizarBotones();
}

QString PestanaOpciones::valorDe(const QString &clave) const
{
    for (const Opcion &o : opciones)
        if (o.clave == clave)
            return o.valor;
    return {};
}

QString PestanaOpciones::motd() const
{
    return motd2->text().isEmpty() ? motd1->text() : motd1->text() + u'\n' + motd2->text();
}

void PestanaOpciones::verMotd()
{
    const QString texto = motd();
    vistaMotd->setText(texto.isEmpty() ? QStringLiteral("<span style=\"color:#777\">%1</span>").arg(tr("(vacío: se ve «A Minecraft Server»)"))
                                       : motdHtml(texto));
}

void PestanaOpciones::guardar()
{
    QStringList lineas;
    if (motd() != motdInicial)
        lineas << QStringLiteral("motd=") + QString(motd()).replace(u'\n', QStringLiteral("\\n"));
    for (auto it = campos.cbegin(); it != campos.cend(); ++it) {
        const QString valor = valorCampo(it.value());
        if (valor != iniciales.value(it.key()))
            lineas << it.key() + u'=' + valor;
    }
    if (QString::number(spinVacio->value()) != ajustes.value(QStringLiteral("APAGAR_VACIO")))
        lineas << QStringLiteral("APAGAR_VACIO=") + QString::number(spinVacio->value());
    const QString pc = checkApagarPc->isChecked() ? QStringLiteral("si") : QStringLiteral("no");
    if (pc != ajustes.value(QStringLiteral("APAGAR_PC")))
        lineas << QStringLiteral("APAGAR_PC=") + pc;
    if (lineas.isEmpty())
        return;
    emit accion({QStringLiteral("propiedades-cambiar"), servidor}, tr("Guardando las opciones de %1…").arg(etiqueta()),
                (lineas.join(u'\n') + u'\n').toUtf8());
}

void PestanaOpciones::cambiarIcono()
{
    const QString archivo = QFileDialog::getOpenFileName(this, tr("Elegí una imagen para el ícono"), QDir::homePath(),
                                                         tr("Imágenes (*.png *.jpg *.jpeg *.webp *.bmp *.gif)"));
    if (archivo.isEmpty())
        return;
    QImage imagen(archivo);
    if (imagen.isNull()) {
        tema::mostrarEstado(estado, tr("No pude abrir esa imagen."), tema::Estado::Error);
        return;
    }
    // Recortada al centro (cuadrada) y a 64×64, que es lo que acepta Minecraft
    const int lado = qMin(imagen.width(), imagen.height());
    imagen = imagen.copy((imagen.width() - lado) / 2, (imagen.height() - lado) / 2, lado, lado)
                 .scaled(64, 64, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_ARGB32);
    const QString destino = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath(QStringLiteral("icono-minecraft.png"));
    if (!imagen.save(destino, "PNG")) {
        tema::mostrarEstado(estado, tr("No pude preparar el ícono."), tema::Estado::Error);
        return;
    }
    emit accion({QStringLiteral("icono"), servidor, destino}, tr("Cambiando el ícono de %1…").arg(etiqueta()), {});
}

void PestanaOpciones::actualizarBotones()
{
    const bool hay = !servidor.isEmpty() && !consulta.ocupado() && !opciones.isEmpty();
    contenido->setEnabled(hay);
    bool cambios = false;
    if (hay && !cargando) {
        cambios = motd() != motdInicial
               || QString::number(spinVacio->value()) != ajustes.value(QStringLiteral("APAGAR_VACIO"))
               || (checkApagarPc->isChecked() ? QStringLiteral("si") : QStringLiteral("no")) != ajustes.value(QStringLiteral("APAGAR_PC"));
        for (auto it = campos.cbegin(); !cambios && it != campos.cend(); ++it)
            cambios = valorCampo(it.value()) != iniciales.value(it.key());
    }
    botonGuardar->setEnabled(hay && !ocupado && cambios);
    // Extras: lo que es compatible con el software del servidor
    const bool usaComplementos = tipo == u"paper" || tipo == u"fabric" || tipo == u"forge";
    botonGeyser->setEnabled(hay && !ocupado && (tipo == u"paper" || tipo == u"fabric"));
    botonGeyser->setToolTip(tipo == u"forge" ? tr("Geyser no tiene versión para Forge (sí para Paper y Fabric)")
                            : tipo == u"vanilla" ? tr("Vanilla no usa plugins ni mods: pasalo a Paper o Fabric con «Cambiar versión»")
                                                 : tr("Que entren desde el celular o la consola (Bedrock) con su cuenta de Xbox, sin tener Java"));
    botonBluemap->setEnabled(hay && !ocupado && usaComplementos);
    botonIcono->setEnabled(hay && !ocupado);
}

// --- Respaldos ----------------------------------------------------------------------------------------------

PestanaRespaldos::PestanaRespaldos(const QString &script_, QWidget *parent)
    : PestanaServidor(script_, parent)
{
    estado = new QLabel;
    estado->setWordWrap(true);
    lista = new QTreeWidget;
    lista->setRootIsDecorated(false);
    lista->setHeaderLabels({tr("Qué"), tr("Archivo"), tr("Fecha"), tr("Tamaño")});
    lista->header()->setSectionResizeMode(1, QHeaderView::Stretch);
    for (int c : {0, 2, 3})
        lista->header()->setSectionResizeMode(c, QHeaderView::ResizeToContents);
    botonGuardar = new QPushButton(tema::icono(QStringLiteral("respaldo")), tr("Guardar el mundo ahora"));
    botonRestaurar = new QPushButton(tema::icono(QStringLiteral("restaurar")), tr("Restaurar…"));
    auto *fila = new QHBoxLayout;
    fila->addWidget(botonGuardar);
    fila->addWidget(botonRestaurar);
    fila->addStretch();
    auto *capa = new QVBoxLayout(this);
    capa->addWidget(estado);
    capa->addWidget(lista, 1);
    capa->addLayout(fila);
    connect(&consulta, &ProcesoLogica::evento, this, [this](const QString &palabra, const QString &resto) {
        // RESPALDO tipo<tab>archivo<tab>fecha<tab>tamaño
        const QStringList c = resto.split(u'\t');
        if (palabra != u"RESPALDO" || c.size() < 4)
            return;
        const QHash<QString, QString> nombres = {{QStringLiteral("mundo"), tr("Mundo")}, {QStringLiteral("jar"), tr("Servidor (jar)")},
                                                 {QStringLiteral("plugin"), tr("Plugin")}, {QStringLiteral("mod"), tr("Mod")}};
        auto *item = new QTreeWidgetItem(lista, {nombres.value(c.at(0), c.at(0)), c.at(1), c.at(2), c.at(3)});
        item->setData(0, Qt::UserRole, c.at(0));
    });
    connect(&consulta, &ProcesoLogica::terminado, this, [this] {
        if (!servidor.isEmpty())
            tema::mostrarEstado(estado, lista->topLevelItemCount() == 0
                ? tr("%1 todavía no tiene respaldos. Se guardan solos al reiniciar el mundo, cambiar de versión o actualizar Paper y plugins.").arg(etiqueta())
                : tr("Lo que se reemplazó o se guardó de %1 (en Minecraft Servers/Respaldos). Restaurar guarda antes lo que hay.").arg(etiqueta()));
        actualizarBotones();
    });
    connect(lista, &QTreeWidget::currentItemChanged, this, [this] { actualizarBotones(); });
    connect(botonGuardar, &QPushButton::clicked, this, [this] {
        emit accion({QStringLiteral("respaldo-guardar"), servidor}, tr("Guardando el mundo de %1…").arg(etiqueta()), {});
    });
    connect(botonRestaurar, &QPushButton::clicked, this, &PestanaRespaldos::restaurar);
    actualizarBotones();
}

void PestanaRespaldos::refrescar()
{
    consulta.cancelarYEsperar();
    lista->clear();
    if (servidor.isEmpty()) {
        tema::mostrarEstado(estado, tr("Elegí un servidor para ver sus respaldos."));
        actualizarBotones();
        return;
    }
    consulta.iniciar(script, {QStringLiteral("respaldos"), servidor});
    actualizarBotones();
}

void PestanaRespaldos::restaurar()
{
    const QTreeWidgetItem *i = lista->currentItem();
    if (!i)
        return;
    const QString tipoRespaldo = i->data(0, Qt::UserRole).toString();
    const QString texto = tipoRespaldo == u"mundo"
        ? tr("¿Volver el mundo de %1 a «%2»? El mundo que tiene ahora se guarda antes en Respaldos.").arg(etiqueta(), i->text(1))
        : tipoRespaldo == u"jar" ? tr("¿Volver %1 a «%2»? El jar que usa ahora queda en Respaldos.").arg(etiqueta(), i->text(1))
                                 : tr("¿Devolver «%1» a %2?").arg(i->text(1), etiqueta());
    if (QMessageBox::question(this, tr("Restaurar"), texto) != QMessageBox::Yes)
        return;
    emit accion({QStringLiteral("restaurar"), servidor, tipoRespaldo, i->text(1)}, tr("Restaurando %1…").arg(i->text(1)), {});
}

void PestanaRespaldos::actualizarBotones()
{
    const bool hay = !servidor.isEmpty() && !consulta.ocupado();
    botonGuardar->setEnabled(hay && !ocupado);
    botonRestaurar->setEnabled(hay && !ocupado && !encendido && lista->currentItem());
    botonRestaurar->setToolTip(encendido ? tr("Detenelo antes de restaurar") : QString());
}
