#include "DialogoPistas.h"
#include "ui_DialogoPistas.h"

#include <QKeyEvent>
#include <QLocale>
#include <QPushButton>

#include <algorithm>

// Dato de cada fila: el código de idioma (lo que después recibe Descargar.sh)
constexpr int RolIdioma = Qt::UserRole;
// Subtítulos automáticos que no se ven de entrada (traducciones a otros idiomas)
constexpr int RolSecundario = Qt::UserRole + 1;

namespace {

// Idioma de un código como «es-419» o «en-orig» (lo que va antes del primer guion)
QLocale::Language idiomaDe(const QString &codigo)
{
    return QLocale::codeToLanguage(codigo.section(u'-', 0, 0));
}

// Nombre para mostrar de un código de idioma: «Spanish (Latin America)» para es-419.
// Qt solo trae los nombres en inglés (los mismos que usa yt-dlp para los subtítulos).
// Devuelve vacío si no conoce el código.
QString nombreIdioma(const QString &codigo)
{
    const QLocale::Language idioma = idiomaDe(codigo);
    if (idioma == QLocale::AnyLanguage)
        return {};
    QString nombre = QLocale::languageToString(idioma);
    // Lo que sigue al idioma puede ser una escritura (zh-Hans) o un país o región (pt-BR)
    const QStringList resto = codigo.split(u'-').mid(1);
    for (const QString &parte : resto) {
        if (const QLocale::Script escritura = QLocale::codeToScript(parte); escritura != QLocale::AnyScript)
            nombre += QStringLiteral(" (%1)").arg(QLocale::scriptToString(escritura));
        else if (const QLocale::Territory territorio = QLocale::codeToTerritory(parte); territorio != QLocale::AnyTerritory)
            nombre += QStringLiteral(" (%1)").arg(QLocale::territoryToString(territorio));
    }
    return nombre;
}

// Fila con casilla para marcar. La lista se arma ya ordenada.
struct Fila
{
    int grupo;          // para ordenar: primero los grupos más chicos
    QString texto;
    QString idioma;
    QString ayuda;
    bool secundario;
};

void llenar(QListWidget *lista, QList<Fila> filas)
{
    std::stable_sort(filas.begin(), filas.end(), [](const Fila &a, const Fila &b) {
        return a.grupo != b.grupo ? a.grupo < b.grupo : QString::localeAwareCompare(a.texto, b.texto) < 0;
    });
    for (const Fila &fila : std::as_const(filas)) {
        auto *item = new QListWidgetItem(fila.texto, lista);
        item->setFlags(Qt::ItemIsEnabled | Qt::ItemIsUserCheckable);
        item->setCheckState(Qt::Unchecked);
        item->setData(RolIdioma, fila.idioma);
        item->setData(RolSecundario, fila.secundario);
        item->setToolTip(fila.ayuda);
    }

    // Un clic en cualquier parte de la fila marca o desmarca, no solo en la casilla. Si el
    // clic fue en la casilla, Qt ya la cambió: por eso se compara con el estado que tenía
    // al apretar el botón (guardado en la propia lista).
    QObject::connect(lista, &QListWidget::itemPressed, lista, [lista](QListWidgetItem *item) {
        lista->setProperty("estadoAlApretar", static_cast<int>(item->checkState()));
    });
    QObject::connect(lista, &QListWidget::itemClicked, lista, [lista](QListWidgetItem *item) {
        if (static_cast<int>(item->checkState()) == lista->property("estadoAlApretar").toInt())
            item->setCheckState(item->checkState() == Qt::Checked ? Qt::Unchecked : Qt::Checked);
    });
}

QStringList marcados(const QListWidget *lista)
{
    QStringList idiomas;
    for (int i = 0; i < lista->count(); ++i) {
        if (lista->item(i)->checkState() == Qt::Checked)
            idiomas << lista->item(i)->data(RolIdioma).toString();
    }
    return idiomas;
}

} // namespace

DialogoPistas::DialogoPistas(const QList<PistaAudio> &audios, const QList<Subtitulo> &subtitulos, QWidget *parent)
    : QDialog(parent), ui(new Ui::DialogoPistas)
{
    ui->setupUi(this);
    ui->botones->button(QDialogButtonBox::Ok)->setText(tr("Descargar"));
    ui->botones->button(QDialogButtonBox::Cancel)->setText(tr("Cancelar"));
    connect(ui->botones, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(ui->botones, &QDialogButtonBox::rejected, this, &QDialog::reject);

    // Idioma en que está el sistema: sus pistas y subtítulos van arriba en las listas
    const QLocale::Language idiomaSistema = QLocale::system().language();
    const auto delSistema = [idiomaSistema](const QString &codigo) {
        return idiomaSistema != QLocale::C && idiomaDe(codigo) == idiomaSistema;
    };

    // ── Pistas de audio: primero la original, después las del idioma del sistema y después
    // el resto por nombre. En ese orden quedan en el archivo (la primera marcada es la que
    // suena por defecto) ──
    QList<Fila> filasAudio;
    for (const PistaAudio &audio : audios) {
        const QString nombre = nombreIdioma(audio.idioma);
        QString texto = nombre.isEmpty() ? audio.idioma : QStringLiteral("%1 [%2]").arg(nombre, audio.idioma);
        if (audio.original)
            texto += tr(" — original");
        else if (audio.idioma.endsWith(QLatin1String("-desc")))
            texto += tr(" — audiodescripción");
        filasAudio << Fila{audio.original ? 0 : delSistema(audio.idioma) ? 1 : 2, texto, audio.idioma, {}, false};
    }
    if (filasAudio.size() > 1) {
        llenar(ui->listaAudios, filasAudio);
        // Marca todas o, si ya lo están, las desmarca
        connect(ui->botonTodosAudios, &QPushButton::clicked, this, [this] {
            const bool marcar = marcados(ui->listaAudios).size() < ui->listaAudios->count();
            for (int i = 0; i < ui->listaAudios->count(); ++i)
                ui->listaAudios->item(i)->setCheckState(marcar ? Qt::Checked : Qt::Unchecked);
        });
    } else {
        // Con una sola pista no hay nada que elegir
        ui->etiquetaAudios->setText(tr("El video tiene una sola pista de audio: no hay otras para elegir."));
        ui->listaAudios->hide();
        ui->botonTodosAudios->hide();
    }

    // ── Subtítulos: primero los que subió el autor; después los automáticos, empezando por
    // los del idioma original y los traducidos al idioma del sistema. Las demás
    // traducciones automáticas (YouTube ofrece más de cien) quedan ocultas hasta que se
    // pidan con la casilla o se busquen con el filtro ──
    QList<Fila> filasSubtitulos;
    int secundarios = 0;
    for (const Subtitulo &subtitulo : subtitulos) {
        const QString nombre = subtitulo.nombre.isEmpty() ? nombreIdioma(subtitulo.idioma) : subtitulo.nombre;
        QString texto = nombre.isEmpty() ? subtitulo.idioma : QStringLiteral("%1 [%2]").arg(nombre, subtitulo.idioma);
        int grupo = 0;
        if (subtitulo.automatico) {
            texto += tr(" — automático");
            if (subtitulo.idioma.endsWith(QLatin1String("-orig")))
                grupo = 1;
            else if (delSistema(subtitulo.idioma))
                grupo = 2;
            else
                grupo = 3;
        }
        secundarios += grupo == 3;
        filasSubtitulos << Fila{grupo, texto, subtitulo.idioma, subtitulo.nombre, grupo == 3};
    }
    if (filasSubtitulos.isEmpty()) {
        ui->etiquetaSubtitulos->setText(tr("El video no ofrece subtítulos."));
        ui->editFiltro->hide();
        ui->listaSubtitulos->hide();
        ui->checkAutomaticos->hide();
    } else {
        llenar(ui->listaSubtitulos, filasSubtitulos);
        // El filtro solo hace falta cuando la lista es larga
        ui->editFiltro->setVisible(filasSubtitulos.size() > 8);
        ui->checkAutomaticos->setVisible(secundarios > 0);
        ui->checkAutomaticos->setText(tr("Mostrar todas las traducciones automáticas (%1 más)").arg(secundarios));
        connect(ui->editFiltro, &QLineEdit::textChanged, this, &DialogoPistas::filtrarSubtitulos);
        connect(ui->checkAutomaticos, &QCheckBox::toggled, this, &DialogoPistas::filtrarSubtitulos);
        filtrarSubtitulos();
    }
}

DialogoPistas::~DialogoPistas()
{
    delete ui;
}

// Enter mientras se escribe en el filtro no hace nada: sin esto QDialog lo toma como un
// clic en «Descargar» y la descarga empezaría antes de terminar de elegir
void DialogoPistas::keyPressEvent(QKeyEvent *evento)
{
    const bool enter = evento->key() == Qt::Key_Return || evento->key() == Qt::Key_Enter;
    if (enter && ui->editFiltro->hasFocus())
        return;
    QDialog::keyPressEvent(evento);
}

QStringList DialogoPistas::audiosElegidos() const
{
    return marcados(ui->listaAudios);
}

QStringList DialogoPistas::subtitulosElegidos() const
{
    return marcados(ui->listaSubtitulos);
}

// Muestra las filas que coinciden con el filtro. Las traducciones automáticas a otros
// idiomas solo se ven si se pidieron con la casilla, si se las busca por nombre o si ya
// están marcadas (para no perder de vista lo que se va a descargar).
void DialogoPistas::filtrarSubtitulos()
{
    const QString filtro = ui->editFiltro->text().trimmed();
    for (int i = 0; i < ui->listaSubtitulos->count(); ++i) {
        QListWidgetItem *item = ui->listaSubtitulos->item(i);
        const bool coincide = item->text().contains(filtro, Qt::CaseInsensitive);
        const bool oculto = item->data(RolSecundario).toBool() && filtro.isEmpty()
                            && !ui->checkAutomaticos->isChecked() && item->checkState() != Qt::Checked;
        item->setHidden(!coincide || oculto);
    }
}
