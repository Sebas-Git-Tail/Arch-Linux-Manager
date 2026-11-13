// Página «Panel de Minecraft»: servidores Paper (iniciar, reiniciar, actualizar Paper,
// instalar plugins) y Prism Launcher. Solo es la interfaz; la lógica está en
// Logica/Minecraft.sh. El respaldo de Minecraft tiene su propia página (PaginaRespaldo).

#pragma once

#include "ProcesoLogica.h"

#include <QSet>
#include <QWidget>

namespace Ui { class PaginaMinecraft; }

class PaginaMinecraft : public QWidget
{
    Q_OBJECT

public:
    PaginaMinecraft(const QString &logica, QWidget *parent = nullptr);
    ~PaginaMinecraft() override;

    bool ocupada() const { return accion.ocupado(); }
    void cancelarYEsperar() { accion.cancelarYEsperar(); }

protected:
    void showEvent(QShowEvent *evento) override;

private:
    void consultar();          // servidores, después versiones y después instancias
    void ejecutar(const QStringList &argumentos, const QString &estado);
    void iniciar();
    void reiniciar();
    void actualizarPaper();
    void instalarPlugin();
    void jugar();
    void eventoConsulta(const QString &palabra, const QString &resto);
    void eventoAccion(const QString &palabra, const QString &resto);
    void terminoConsulta();
    void terminoAccion(int codigo, bool cancelado);
    void actualizarBotones();
    QString servidorElegido(bool *encendido = nullptr) const;

    Ui::PaginaMinecraft *ui;
    QString script;
    ProcesoLogica consulta;    // listas (no se cancela al cerrar: es rápida)
    ProcesoLogica accion;      // iniciar, reiniciar, Paper, plugins, Prism
    enum class Paso { Servidores, Versiones, Instancias } paso = Paso::Servidores;
    QSet<QString> marcados;    // servidores marcados para plugins (se conservan al actualizar)
    bool primeraVez = true;
    QString mensajeFinal;
};
