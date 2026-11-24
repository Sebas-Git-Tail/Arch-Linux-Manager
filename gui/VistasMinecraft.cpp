#include "VistasMinecraft.h"
#include "Tema.h"

#include <QApplication>
#include <QFile>
#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QResizeEvent>
#include <QScrollBar>
#include <QTimer>

#include <algorithm>
#include <QToolButton>
#include <QVBoxLayout>

// --- Íconos pixel-art (16×16) ------------------------------------------------------------------------------

namespace {
struct Dibujo { const char *filas[16]; const char *colores; };

// «.» es transparente; colores: «letra#rrggbb» separados por espacios
const Dibujo vanilla = {{
    "GGGGGGGGGGGGGGGG", "GgGGGgGGGGgGGgGG", "GGgGGGGgGGGGgGGG", "gGGgGgGGgGgGGGgG",
    "DgDDgDDDgDDgDDgD", "DDDdDDeDDDdDDeDD", "DeDDDDDDdDDDDDDd", "DDdDDeDDDDeDDdDD",
    "dDDDDDDdDDDDDDDD", "DDeDdDDDDeDDdDDD", "DDDDDDeDDDDDDDeD", "DdDDDDDDdDDeDDDD",
    "DDDeDDdDDDDDDdDD", "DeDDDDDDDeDDDDDD", "DDDdDDeDDDDdDDeD", "DDDDDDDDDDDDDDDD"},
    "G#6aa84f g#4e8f3a D#866043 d#6b4a32 e#a07a55"};
const Dibujo papel = {{
    "................", "..............WW", "............WWWL", "..........WWWWLW",
    "........WWWWWLLW", "......WWWWWWLLW.", "....WWWWWWWLLLW.", "..WWWWWWWWLLLW..",
    "....WWWWWWLLLLW.", "......WWWLLLLLW.", "........WLLLLW..", "........WLLLW...",
    ".........WLLW...", ".........WLW....", "..........W.....", "................"},
    "W#f5f7fa L#8fb0d6"};
const Dibujo tela = {{
    "................", ".BBBBBBBBBBBBBB.", ".BCCCCCCCCCCCCB.", ".BCcCCCCCCCCcCB.",
    ".BCCcCCCCCCcCCB.", ".BCCCcCCCCcCCCB.", ".BCCCCcCCcCCCCB.", ".BCCCCCccCCCCCB.",
    ".BCCCCCccCCCCCB.", ".BCCCCcCCcCCCCB.", ".BCCCcCCCCcCCCB.", ".BCCcCCCCCCcCCB.",
    ".BCcCCCCCCCCcCB.", ".BCCCCCCCCCCCCB.", ".BBBBBBBBBBBBBB.", "................"},
    "B#38342a C#dbd0b4 c#a8996f"};
const Dibujo yunque = {{
    "................", "................", "................", "..AAAAAAAAAAAA..",
    ".AaaaaaaaaaaaaA.", ".AAAAAAAAAAAAAA.", "..kAAAAAAAAAAk..", "....kAAAAAAk....",
    ".....AAAAAA.....", ".....kAAAAk.....", "....AAAAAAAA....", "...AaaaaaaaaA...",
    "...AAAAAAAAAA...", "...kkkkkkkkkk...", "................", "................"},
    "A#5b6470 a#8a94a1 k#353a42"};

QPixmap pintar(const Dibujo &d, int lado)
{
    QHash<QChar, QColor> colores;
    for (const QString &c : QString::fromLatin1(d.colores).split(u' '))
        colores.insert(c.at(0), QColor(c.mid(1)));
    QImage imagen(16, 16, QImage::Format_ARGB32);
    imagen.fill(Qt::transparent);
    for (int y = 0; y < 16; ++y)
        for (int x = 0; x < 16; ++x) {
            const QChar c = QLatin1Char(d.filas[y][x]);
            if (colores.contains(c))
                imagen.setPixelColor(x, y, colores.value(c));
        }
    return QPixmap::fromImage(imagen.scaled(lado, lado, Qt::IgnoreAspectRatio, Qt::FastTransformation));
}
} // namespace

QPixmap iconoServidor(const QString &tipo, const QString &rutaIcono, bool encendido, int lado)
{
    QPixmap base;
    if (!rutaIcono.isEmpty() && QFile::exists(rutaIcono)) {
        QImage imagen(rutaIcono);
        if (!imagen.isNull())
            base = QPixmap::fromImage(imagen.scaled(lado, lado, Qt::KeepAspectRatio, Qt::FastTransformation));
    }
    if (base.isNull())
        base = pintar(tipo == u"paper" ? papel : tipo == u"fabric" ? tela : tipo == u"forge" ? yunque : vanilla, lado);
    if (!encendido)
        return base;
    // Encendido: un punto verde abajo a la derecha (como el de «jugando» de Prism)
    QPixmap con(base.size());
    con.fill(Qt::transparent);
    QPainter p(&con);
    p.setRenderHint(QPainter::Antialiasing);
    p.drawPixmap(0, 0, base);
    const int r = qMax(6, lado / 6);
    p.setPen(QPen(QColor(0x1b, 0x1d, 0x21), qMax(2, lado / 24)));
    p.setBrush(tema::colores().ok);
    p.drawEllipse(QPoint(lado - r - 1, lado - r - 1), r, r);
    return con;
}

QPushButton *botonAccion(const QString &icono, const QColor &color, const QString &texto, QWidget *padre)
{
    auto *b = new QPushButton(tema::icono(icono, color), texto, padre);
    b->setProperty("plano", true);
    b->setStyleSheet(QStringLiteral("text-align:left; padding:5px 10px;"));
    b->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    b->setIconSize(QSize(18, 18));
    return b;
}

// --- Mosaicos ------------------------------------------------------------------------------------------------

namespace {
constexpr int AnchoMosaico = 118, AltoMosaico = 104;
constexpr int RolRuta = Qt::UserRole;
}

ListaMosaicos::ListaMosaicos(QWidget *parent)
    : QListWidget(parent)
{
    setViewMode(QListView::IconMode);
    setFlow(QListView::LeftToRight);
    setWrapping(true);
    setResizeMode(QListView::Adjust);
    setMovement(QListView::Static);
    setUniformItemSizes(true);
    setWordWrap(true);
    setTextElideMode(Qt::ElideRight);
    setIconSize(QSize(48, 48));
    setGridSize(QSize(AnchoMosaico, AltoMosaico));
    setSpacing(0);
    setSelectionMode(QAbstractItemView::ExtendedSelection);
    setFrameShape(QFrame::NoFrame);
    setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
    viewport()->setAutoFillBackground(false);
    // El elegido con el acento de fondo, como en Prism
    QColor elegido = tema::colores().acento;
    elegido.setAlpha(90);
    setStyleSheet(QStringLiteral("QListWidget { background: transparent; border: none; }"
                                 "QListWidget::item { border-radius: 6px; padding: 4px; color: %1; }"
                                 "QListWidget::item:selected { background: %2; color: %1; }"
                                 "QListWidget::item:hover:!selected { background: %3; }")
                      .arg(tema::colores().texto.name(), elegido.name(QColor::HexArgb), tema::colores().superficie2.name()));
}

int ListaMosaicos::heightForWidth(int ancho) const
{
    const int porFila = qMax(1, (ancho - 4) / AnchoMosaico);
    const int filas = qMax(1, (count() + porFila - 1) / porFila);
    return filas * AltoMosaico + 6;
}

QSize ListaMosaicos::sizeHint() const
{
    return QSize(AnchoMosaico * 4, heightForWidth(width() > 0 ? width() : AnchoMosaico * 4));
}

void ListaMosaicos::resizeEvent(QResizeEvent *evento)
{
    QListWidget::resizeEvent(evento);
    if (evento->oldSize().width() != evento->size().width())
        updateGeometry();
}

// --- Grilla ----------------------------------------------------------------------------------------------------

GrillaServidores::GrillaServidores(QWidget *parent)
    : QScrollArea(parent)
{
    setWidgetResizable(true);
    setFrameShape(QFrame::NoFrame);
    contenido = new QWidget;
    capa = new QVBoxLayout(contenido);
    capa->setContentsMargins(4, 4, 4, 4);
    capa->setSpacing(2);
    capa->addStretch();
    setWidget(contenido);
}

void GrillaServidores::empezar()
{
    nueva.clear();
}

void GrillaServidores::agregar(const ServidorMc &s)
{
    nueva << s;
}

void GrillaServidores::terminar()
{
    lista = nueva;
    QStringList rutas;
    for (const ServidorMc &s : std::as_const(lista))
        rutas << s.ruta;
    // Lo elegido que ya no existe se olvida
    seleccion.erase(std::remove_if(seleccion.begin(), seleccion.end(), [&](const QString &r) { return !rutas.contains(r); }),
                    seleccion.end());
    if (!rutas.contains(actual))
        actual = seleccion.value(0);
    armar();
}

const ServidorMc *GrillaServidores::datos(const QString &ruta) const
{
    for (const ServidorMc &s : lista)
        if (s.ruta == ruta)
            return &s;
    return nullptr;
}

QString GrillaServidores::elegido() const
{
    return actual;
}

QStringList GrillaServidores::seleccionados() const
{
    return seleccion;
}

void GrillaServidores::elegir(const QString &ruta)
{
    actual = ruta;
    seleccion = ruta.isEmpty() ? QStringList() : QStringList{ruta};
    if (const ServidorMc *s = datos(ruta))
        abiertos.insert(s->grupo(), true);
    armar();
    emit cambioSeleccion();
}

void GrillaServidores::armar()
{
    const int barra = verticalScrollBar()->value();
    // Se vacía todo menos el estirador del final
    while (capa->count() > 1) {
        QLayoutItem *item = capa->takeAt(0);
        delete item->widget();
        delete item;
    }
    listas.clear();
    QStringList grupos;
    for (const ServidorMc &s : std::as_const(lista))
        if (!grupos.contains(s.grupo()))
            grupos << s.grupo();
    for (const QString &grupo : std::as_const(grupos)) {
        QList<const ServidorMc *> suyos;
        int prendidos = 0;
        for (const ServidorMc &s : std::as_const(lista))
            if (s.grupo() == grupo) {
                suyos << &s;
                prendidos += s.encendido ? 1 : 0;
            }
        // Cerrados salvo que el usuario lo haya abierto, o que tengan uno encendido o el elegido
        bool tieneElegido = false;
        for (const ServidorMc *s : std::as_const(suyos))
            tieneElegido = tieneElegido || s->ruta == actual;
        const bool abierto = abiertos.contains(grupo) ? abiertos.value(grupo) : (prendidos > 0 || tieneElegido || grupos.size() == 1);

        // Encabezado: flecha, nombre, línea y cuántos hay (como «No agrupado» en Prism)
        auto *encabezado = new QWidget;
        auto *filaEnc = new QHBoxLayout(encabezado);
        filaEnc->setContentsMargins(2, 6, 2, 0);
        auto *flecha = new QToolButton;
        flecha->setArrowType(abierto ? Qt::DownArrow : Qt::RightArrow);
        flecha->setAutoRaise(true);
        flecha->setText(grupo.isEmpty() ? tr("Sin grupo") : grupo);
        flecha->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
        QFont negrita = flecha->font();
        negrita.setBold(true);
        flecha->setFont(negrita);
        auto *linea = new QFrame;
        linea->setFrameShape(QFrame::HLine);
        linea->setStyleSheet(QStringLiteral("color:%1;").arg(tema::colores().borde.name()));
        auto *cuantos = new QLabel((suyos.size() == 1 ? tr("1 servidor") : tr("%1 servidores").arg(suyos.size()))
                                   + (prendidos == 0 ? QString() : prendidos == 1 ? tr(" · 1 encendido") : tr(" · %1 encendidos").arg(prendidos)));
        cuantos->setStyleSheet(QStringLiteral("color:%1;").arg((prendidos > 0 ? tema::colores().ok : tema::colores().texto3).name()));
        filaEnc->addWidget(flecha);
        filaEnc->addWidget(linea, 1);
        filaEnc->addWidget(cuantos);
        capa->insertWidget(capa->count() - 1, encabezado);

        auto *mosaicos = new ListaMosaicos;
        for (const ServidorMc *s : std::as_const(suyos)) {
            auto *item = new QListWidgetItem(QIcon(iconoServidor(s->tipo, s->icono, s->encendido, 48)), s->nombre(), mosaicos);
            item->setData(RolRuta, s->ruta);
            item->setToolTip(tr("%1\n%2 %3%4").arg(s->ruta, s->tipo.isEmpty() ? QString() : s->tipo.at(0).toUpper() + s->tipo.mid(1),
                                                     s->version, s->encendido ? tr(" · encendido") : QString()));
            item->setSelected(seleccion.contains(s->ruta));
            if (s->ruta == actual)
                mosaicos->setCurrentItem(item, QItemSelectionModel::NoUpdate);
        }
        mosaicos->setVisible(abierto);
        capa->insertWidget(capa->count() - 1, mosaicos);
        listas << mosaicos;

        connect(flecha, &QToolButton::clicked, this, [this, grupo, mosaicos, flecha] {
            const bool ahora = !mosaicos->isVisible();
            mosaicos->setVisible(ahora);
            flecha->setArrowType(ahora ? Qt::DownArrow : Qt::RightArrow);
            abiertos.insert(grupo, ahora);
        });
        // Un clic elige ese (y deja de lado los de otros grupos); con Ctrl o Shift se suman
        connect(mosaicos, &QListWidget::itemPressed, this, [this, mosaicos](QListWidgetItem *item) {
            const bool sumar = QApplication::keyboardModifiers() & (Qt::ControlModifier | Qt::ShiftModifier);
            if (!sumar)
                for (ListaMosaicos *otra : std::as_const(listas))
                    if (otra != mosaicos) {
                        const QSignalBlocker b(otra);
                        otra->clearSelection();
                    }
            actual = item->data(RolRuta).toString();
        });
        connect(mosaicos, &QListWidget::itemSelectionChanged, this, [this] {
            seleccion.clear();
            for (ListaMosaicos *l : std::as_const(listas))
                for (QListWidgetItem *i : l->selectedItems())
                    seleccion << i->data(RolRuta).toString();
            if (!seleccion.contains(actual))
                actual = seleccion.value(0);
            emit cambioSeleccion();
        });
        connect(mosaicos, &QListWidget::itemDoubleClicked, this, [this](QListWidgetItem *item) {
            emit abrir(item->data(RolRuta).toString());
        });
    }
    QTimer::singleShot(0, this, [this, barra] { verticalScrollBar()->setValue(barra); });
}
