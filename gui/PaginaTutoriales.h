// Página «Tutoriales»: lista los videos del servidor (Logica/Tutoriales.sh) y reproduce el
// elegido con mpv, directo desde el servidor.

#pragma once

#include "ProcesoLogica.h"

#include <QWidget>

namespace Ui { class PaginaTutoriales; }

class PaginaTutoriales : public QWidget
{
    Q_OBJECT

public:
    PaginaTutoriales(const QString &logica, QWidget *parent = nullptr);
    ~PaginaTutoriales() override;

protected:
    void showEvent(QShowEvent *evento) override;

private:
    void listar();
    void ver();

    Ui::PaginaTutoriales *ui;
    QString script;
    ProcesoLogica proceso;
    QString error;
    bool listado = false;
};
