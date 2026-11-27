// Página «Steam Proton»: muestra la versión de GE-Proton instalada y la última, y la
// instala. Solo es la interfaz; la lógica está en Logica/Steam-Proton.sh.

#pragma once

#include "ProcesoLogica.h"

#include <QWidget>

namespace Ui { class PaginaSteam; }

class PaginaSteam : public QWidget
{
    Q_OBJECT

public:
    PaginaSteam(const QString &logica, QWidget *parent = nullptr);
    ~PaginaSteam() override;

    bool ocupada() const { return proceso.ocupado(); }
    void cancelarYEsperar() { proceso.cancelarYEsperar(); }

protected:
    void showEvent(QShowEvent *evento) override;

private:
    void consultar();                  // instaladas y después la última
    // sinSuma: instalar aunque la versión no publique suma SHA-512 (después de confirmarlo)
    void instalar(const QString &url, bool sinSuma = false);
    void procesarEvento(const QString &palabra, const QString &resto);
    void terminoProceso(int codigo, bool cancelado);
    void habilitar(bool habilitado);

    Ui::PaginaSteam *ui;
    QString script;
    ProcesoLogica proceso;
    enum class Paso { Nada, Instaladas, Ultima, Instalar } paso = Paso::Nada;
    QString arquitectura;
    QString urlUltima;
    QString urlInstalando;             // la que se está instalando (para repetir con --sin-suma)
    QStringList instaladas;
    QString mensajeFinal;
    bool consultado = false;
};
