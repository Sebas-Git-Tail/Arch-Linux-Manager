#include "PaginaAndroid.h"
#include "ui_PaginaAndroid.h"

#include <QDir>
#include <QMessageBox>

PaginaAndroid::PaginaAndroid(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaAndroid),
      script(QDir(logica).filePath(QStringLiteral("Android.sh")))
{
    ui->setupUi(this);
    ui->barraProgreso->hide();

    connect(ui->botonBuscar, &QPushButton::clicked, this, &PaginaAndroid::buscarCelulares);
    connect(ui->comboCelular, &QComboBox::currentIndexChanged, this, &PaginaAndroid::mostrarUsuarios);
    connect(ui->botonApps, &QPushButton::clicked, this, &PaginaAndroid::instalarApps);
    connect(ui->botonDebloat, &QPushButton::clicked, this, &PaginaAndroid::debloat);
    connect(ui->botonCancelar, &QPushButton::clicked, &proceso, &ProcesoLogica::cancelar);
    connect(&proceso, &ProcesoLogica::evento, this, &PaginaAndroid::procesarEvento);
    connect(&proceso, &ProcesoLogica::terminado, this, &PaginaAndroid::terminoProceso);
}

PaginaAndroid::~PaginaAndroid()
{
    delete ui;
}

// Cada vez que se abre la página se buscan los celulares (pueden haberse conectado o
// desconectado mientras tanto)
void PaginaAndroid::showEvent(QShowEvent *evento)
{
    QWidget::showEvent(evento);
    if (!proceso.ocupado())
        buscarCelulares();
}

void PaginaAndroid::habilitar(bool habilitado)
{
    const bool hayCelular = ui->comboCelular->count() > 0;
    ui->grupoCelular->setEnabled(habilitado);
    ui->grupoApps->setEnabled(habilitado && hayCelular);
    ui->grupoDebloat->setEnabled(habilitado && hayCelular);
    ui->botonCancelar->setEnabled(!habilitado && !buscando);
}

void PaginaAndroid::buscarCelulares()
{
    buscando = true;
    noAutorizados.clear();
    usuarios.clear();
    ui->comboCelular->clear();
    ui->etiquetaCelular->setText(tr("Buscando celulares…"));
    habilitar(false);
    proceso.iniciar(script, {QStringLiteral("dispositivos")});
}

// Llena el combo con los usuarios de Android del celular elegido (los informa
// «dispositivos» junto con cada celular: no hay una lista fija)
void PaginaAndroid::mostrarUsuarios()
{
    const QList<QPair<QString, QString>> delCelular = usuarios.value(ui->comboCelular->currentData().toString());
    ui->comboUsuario->clear();
    QStringList ids;
    for (const auto &[id, nombre] : delCelular) {
        ui->comboUsuario->addItem(nombre.isEmpty() ? id : QStringLiteral("%1 — %2").arg(id, nombre), id);
        ids << id;
    }
    // Con más de un usuario se ofrece también quitarles las apps a todos de una vez
    if (ids.size() > 1)
        ui->comboUsuario->addItem(tr("Todos (%1)").arg(ids.join(QStringLiteral(", "))), QStringLiteral("todos"));

    // Sin usuarios detectados no se puede hacer el debloat (no se adivina ninguno)
    const bool sinDetectar = ids.isEmpty() && !buscando && ui->comboCelular->count() > 0;
    ui->comboUsuario->setPlaceholderText(sinDetectar ? tr("No se pudieron detectar los usuarios de este celular") : QString());
    ui->botonDebloat->setEnabled(!ids.isEmpty());
}

void PaginaAndroid::ejecutar(const QStringList &argumentos, const QString &estado)
{
    mensajeFinal.clear();
    ui->registro->clear();
    ui->barraProgreso->setValue(0);
    ui->barraProgreso->show();
    ui->etiquetaEstado->setText(estado);
    habilitar(false);
    // El serial elegido va siempre: con dos celulares, adb sin --serial no sabe a cuál ir
    proceso.iniciar(script, argumentos + QStringList{QStringLiteral("--serial"), ui->comboCelular->currentData().toString()});
}

void PaginaAndroid::instalarApps()
{
    ejecutar({QStringLiteral("apps-foss")}, tr("Instalando apps…"));
}

void PaginaAndroid::debloat()
{
    QString nivel = QStringLiteral("basico"), nombre = ui->radioBasico->text();
    if (ui->radioIntermedio->isChecked()) {
        nivel = QStringLiteral("intermedio");
        nombre = ui->radioIntermedio->text();
    } else if (ui->radioExtremo->isChecked()) {
        nivel = QStringLiteral("extremo");
        nombre = ui->radioExtremo->text();
    }
    // Quita apps del celular: siempre se confirma, nombrando el celular, el nivel y el usuario
    if (QMessageBox::warning(this, windowTitle(),
            tr("Se van a quitar las apps del nivel «%1» del celular %2, para el usuario de Android «%3».\n¿Continuar?")
                .arg(nombre, ui->comboCelular->currentText(), ui->comboUsuario->currentText()),
            QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes)
        return;
    ejecutar({QStringLiteral("debloat"), QStringLiteral("--nivel"), nivel,
              QStringLiteral("--usuario"), ui->comboUsuario->currentData().toString()},
             tr("Quitando apps…"));
}

void PaginaAndroid::procesarEvento(const QString &palabra, const QString &resto)
{
    if (palabra == u"DISPOSITIVO") {
        // DISPOSITIVO serial marca modelo
        const QStringList partes = resto.split(u' ');
        const QString serial = partes.value(0);
        const QString nombre = QStringLiteral("%1 %2").arg(partes.value(1), QStringList(partes.mid(2)).join(u' '));
        ui->comboCelular->addItem(QIcon::fromTheme(QStringLiteral("smartphone")), nombre, serial);
    } else if (palabra == u"USUARIO") {
        // USUARIO serial id nombre (se muestran al terminar la búsqueda)
        const QStringList partes = resto.split(u' ');
        usuarios[partes.value(0)].append({partes.value(1), QStringList(partes.mid(2)).join(u' ')});
    } else if (palabra == u"NOAUTORIZADO") {
        noAutorizados << resto;
    } else if (palabra == u"MARCA") {
        ui->registro->appendPlainText(tr("Marca detectada: %1").arg(resto));
    } else if (palabra == u"PROGRESO") {
        // PROGRESO n total
        const QStringList partes = resto.split(u' ');
        ui->barraProgreso->setRange(0, qMax(1, partes.value(1).toInt()));
        ui->barraProgreso->setValue(partes.value(0).toInt());
    } else if (palabra == u"INSTALADA") {
        ui->registro->appendPlainText(tr("✓ Instalada: %1").arg(resto));
    } else if (palabra == u"DESINSTALADO") {
        // DESINSTALADO paquete usuario
        const QStringList partes = resto.split(u' ');
        ui->registro->appendPlainText(tr("Quitada del usuario %1: %2").arg(partes.value(1), partes.value(0)));
    } else if (palabra == u"FALLO") {
        ui->registro->appendPlainText(tr("✗ Falló: %1").arg(resto));
    } else if (palabra == u"LISTO" || palabra == u"ERROR") {
        mensajeFinal = resto;
    } else {
        ui->registro->appendPlainText(palabra == u"AVISO" ? resto : palabra + u' ' + resto);
    }
}

void PaginaAndroid::terminoProceso(int codigo, bool cancelado)
{
    if (buscando) {
        buscando = false;
        if (ui->comboCelular->count() == 0 && noAutorizados.isEmpty())
            ui->etiquetaCelular->setText(tr("No hay celulares conectados. Conectalo por USB (o por depuración inalámbrica) y tocá Buscar."));
        else if (!noAutorizados.isEmpty())
            ui->etiquetaCelular->setText(tr("Falta aceptar la depuración USB en: %1").arg(noAutorizados.join(QStringLiteral(", "))));
        else
            ui->etiquetaCelular->setText(ui->comboCelular->count() == 1 ? tr("1 celular conectado.")
                                                                         : tr("%1 celulares conectados: elegí cuál.").arg(ui->comboCelular->count()));
        mostrarUsuarios();
        habilitar(true);
        return;
    }

    habilitar(true);
    if (cancelado)
        ui->etiquetaEstado->setText(tr("Cancelado."));
    else if (codigo == 0)
        ui->etiquetaEstado->setText(QStringLiteral("✓ ") + mensajeFinal);
    else
        ui->etiquetaEstado->setText(QStringLiteral("✗ ") + (mensajeFinal.isEmpty() ? tr("No se pudo completar.") : mensajeFinal));
}
