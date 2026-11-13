// Página «Celular Android»: elegir el celular (hay que elegir cuando hay más de uno
// conectado), instalar las apps FOSS y hacer el debloat para el usuario de Android que se
// elija (los usuarios los detecta Logica/Android.sh en cada celular). Solo es la interfaz;
// la lógica está en Logica/Android.sh.

#pragma once

#include "ProcesoLogica.h"

#include <QHash>
#include <QList>
#include <QPair>
#include <QWidget>

namespace Ui { class PaginaAndroid; }

class PaginaAndroid : public QWidget
{
    Q_OBJECT

public:
    PaginaAndroid(const QString &logica, QWidget *parent = nullptr);
    ~PaginaAndroid() override;

    bool ocupada() const { return proceso.ocupado(); }
    void cancelarYEsperar() { proceso.cancelarYEsperar(); }

protected:
    void showEvent(QShowEvent *evento) override;

private:
    void buscarCelulares();
    void mostrarUsuarios();
    void instalarApps();
    void debloat();
    void ejecutar(const QStringList &argumentos, const QString &estado);
    void procesarEvento(const QString &palabra, const QString &resto);
    void terminoProceso(int codigo, bool cancelado);
    void habilitar(bool habilitado);

    Ui::PaginaAndroid *ui;
    QString script;
    ProcesoLogica proceso;
    bool buscando = false;
    QStringList noAutorizados;
    // Usuarios de Android de cada celular: serial -> lista de (id, nombre)
    QHash<QString, QList<QPair<QString, QString>>> usuarios;
    QString mensajeFinal;
};
