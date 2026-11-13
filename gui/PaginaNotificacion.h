// Página «Notificaciones»: manda un mensaje a la PC de Sebastián con Logica/Notificacion.sh
// (el mensaje va por la entrada estándar, nunca como argumento).

#pragma once

#include "ProcesoLogica.h"

#include <QWidget>

namespace Ui { class PaginaNotificacion; }

class PaginaNotificacion : public QWidget
{
    Q_OBJECT

public:
    PaginaNotificacion(const QString &logica, QWidget *parent = nullptr);
    ~PaginaNotificacion() override;

private:
    void enviar();

    Ui::PaginaNotificacion *ui;
    QString script;
    ProcesoLogica proceso;
    QString mensajeFinal;
};
