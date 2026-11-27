#include "PaginaAndroid.h"
#include "Tema.h"
#include "ui_PaginaAndroid.h"

#include <QDir>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QMessageBox>
#include <QPushButton>
#include <QVBoxLayout>

PaginaAndroid::PaginaAndroid(const QString &logica, QWidget *parent)
    : QWidget(parent), ui(new Ui::PaginaAndroid),
      script(QDir(logica).filePath(QStringLiteral("Android.sh")))
{
    ui->setupUi(this);
    ui->barraProgreso->hide();

    // «Apps quitadas»: deshacer el debloat app por app, debajo del grupo del debloat
    grupoQuitadas = new QGroupBox(tr("Apps quitadas"), this);
    auto *layoutQuitadas = new QVBoxLayout(grupoQuitadas);
    auto *explicacion = new QLabel(tr("El debloat no borra las apps del celular: las desinstala para ese usuario. "
                                      "Acá se ven las que se pueden volver a instalar (del usuario elegido arriba) "
                                      "y se recuperan sin descargar nada."), grupoQuitadas);
    explicacion->setWordWrap(true);
    layoutQuitadas->addWidget(explicacion);
    listaQuitadas = new QListWidget(grupoQuitadas);
    listaQuitadas->setMaximumHeight(180);
    listaQuitadas->hide();
    layoutQuitadas->addWidget(listaQuitadas);
    auto *botonesQuitadas = new QHBoxLayout;
    botonVerQuitadas = new QPushButton(QIcon::fromTheme(QStringLiteral("view-list-details")), tr("Ver apps quitadas"), grupoQuitadas);
    botonReinstalar = new QPushButton(QIcon::fromTheme(QStringLiteral("edit-undo")), tr("Volver a instalar las marcadas"), grupoQuitadas);
    botonReinstalar->setEnabled(false);
    botonesQuitadas->addWidget(botonVerQuitadas);
    botonesQuitadas->addStretch();
    botonesQuitadas->addWidget(botonReinstalar);
    layoutQuitadas->addLayout(botonesQuitadas);
    ui->layoutPrincipal->insertWidget(ui->layoutPrincipal->indexOf(ui->grupoDebloat) + 1, grupoQuitadas);
    connect(botonVerQuitadas, &QPushButton::clicked, this, &PaginaAndroid::verQuitadas);
    connect(botonReinstalar, &QPushButton::clicked, this, &PaginaAndroid::reinstalar);
    connect(listaQuitadas, &QListWidget::itemChanged, this, &PaginaAndroid::actualizarBotonReinstalar);

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
    grupoQuitadas->setEnabled(habilitado && hayCelular);
    ui->botonCancelar->setEnabled(!habilitado && !buscando);
}

void PaginaAndroid::buscarCelulares()
{
    buscando = true;
    noAutorizados.clear();
    usuarios.clear();
    ui->comboCelular->clear();
    listaQuitadas->clear();      // eran del celular de antes
    listaQuitadas->hide();
    actualizarBotonReinstalar();
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
    tema::mostrarEstado(ui->etiquetaEstado, estado);
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

// Apps que siguen en el celular pero no están instaladas para el usuario elegido (o para
// cualquiera, con «Todos»): las que quitó el debloat
void PaginaAndroid::verQuitadas()
{
    listaQuitadas->clear();
    listaQuitadas->show();
    actualizarBotonReinstalar();
    QStringList argumentos{QStringLiteral("quitadas")};
    const QString usuario = ui->comboUsuario->currentData().toString();
    if (!usuario.isEmpty())
        argumentos << QStringLiteral("--usuario") << usuario;
    ejecutar(argumentos, tr("Buscando apps quitadas…"));
}

void PaginaAndroid::actualizarBotonReinstalar()
{
    int marcadas = 0;
    for (int i = 0; i < listaQuitadas->count(); ++i)
        marcadas += listaQuitadas->item(i)->checkState() == Qt::Checked;
    botonReinstalar->setEnabled(marcadas > 0);
    botonReinstalar->setText(marcadas > 1 ? tr("Volver a instalar las marcadas (%1)").arg(marcadas)
                                          : tr("Volver a instalar las marcadas"));
}

void PaginaAndroid::reinstalar()
{
    QStringList pedidos, nombres;
    for (int i = 0; i < listaQuitadas->count(); ++i) {
        const QListWidgetItem *item = listaQuitadas->item(i);
        if (item->checkState() == Qt::Checked) {
            pedidos << item->data(Qt::UserRole).toString();     // «usuario:paquete»
            nombres << item->text();
        }
    }
    if (pedidos.isEmpty())
        return;
    if (QMessageBox::question(this, windowTitle(),
            tr("Se van a volver a instalar estas apps en el celular %1:\n\n%2\n\n¿Continuar?")
                .arg(ui->comboCelular->currentText(), nombres.mid(0, 15).join(u'\n')
                                                      + (nombres.size() > 15 ? tr("\n… y %1 más").arg(nombres.size() - 15) : QString())))
        != QMessageBox::Yes)
        return;
    ejecutar(QStringList{QStringLiteral("reinstalar")} + pedidos, tr("Volviendo a instalar apps…"));
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
    } else if (palabra == u"QUITADA") {
        // QUITADA paquete usuario LISTA|OTRA (OTRA: no está en las listas del debloat; suele ser
        // una app de otro usuario o perfil que este nunca tuvo)
        const QStringList partes = resto.split(u' ');
        QString texto = partes.value(0);
        if (ui->comboUsuario->currentData().toString() == u"todos")
            texto += tr(" (usuario %1)").arg(partes.value(1));
        if (partes.value(2) != u"LISTA")
            texto += tr(" — no es del debloat");
        auto *item = new QListWidgetItem(texto);
        item->setData(Qt::UserRole, QStringLiteral("%1:%2").arg(partes.value(1), partes.value(0)));
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(Qt::Unchecked);
        if (partes.value(2) != u"LISTA")
            item->setToolTip(tr("No está en las listas del debloat: puede ser una app de otro usuario o perfil del celular."));
        // Las del debloat primero
        if (partes.value(2) == u"LISTA") {
            int fila = 0;
            while (fila < listaQuitadas->count() && listaQuitadas->item(fila)->toolTip().isEmpty())    // (las del debloat no tienen)
                ++fila;
            listaQuitadas->insertItem(fila, item);
        } else {
            listaQuitadas->addItem(item);
        }
    } else if (palabra == u"REINSTALADA") {
        // REINSTALADA paquete usuario: ya no está quitada
        const QStringList partes = resto.split(u' ');
        const QString clave = QStringLiteral("%1:%2").arg(partes.value(1), partes.value(0));
        for (int i = listaQuitadas->count() - 1; i >= 0; --i) {
            if (listaQuitadas->item(i)->data(Qt::UserRole).toString() == clave)
                delete listaQuitadas->takeItem(i);
        }
        ui->registro->appendPlainText(tr("✓ Instalada de nuevo para el usuario %1: %2").arg(partes.value(1), partes.value(0)));
        actualizarBotonReinstalar();
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
    if (listaQuitadas->count() == 0)
        listaQuitadas->hide();
    actualizarBotonReinstalar();
    if (cancelado)
        tema::mostrarEstado(ui->etiquetaEstado, tr("Cancelado."));
    else if (codigo == 0)
        tema::mostrarEstado(ui->etiquetaEstado, mensajeFinal, tema::Estado::Ok);
    else
        tema::mostrarEstado(ui->etiquetaEstado, (mensajeFinal.isEmpty() ? tr("No se pudo completar.") : mensajeFinal), tema::Estado::Error);
}
