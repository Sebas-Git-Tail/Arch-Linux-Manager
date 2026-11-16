// Página «Panel de Minecraft»: los servidores de Minecraft Servers/Servidores (iniciar, detener,
// reiniciar, Paper automático, RAM, reiniciar mundo), sus plugins (reconocidos en Modrinth, con
// actualización) y Prism Launcher. Solo es la interfaz; la lógica está en Logica/Minecraft.sh.
// El respaldo de Minecraft tiene su propia página (PaginaRespaldo).

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
    void consultar();          // servidores (y la primera vez, las instancias de Prism)
    void consultarPlugins();   // los del servidor elegido
    void ejecutar(const QStringList &argumentos, const QString &estado);
    void iniciar();
    void detener();
    void reiniciar();
    void actualizarPaper();
    void cambiarRam();
    void reiniciarMundo();
    void abrirCarpeta();
    void actualizarPlugins();
    void instalarPlugin();
    void jugar();
    void eventoConsulta(const QString &palabra, const QString &resto);
    void eventoPlugins(const QString &palabra, const QString &resto);
    void eventoAccion(const QString &palabra, const QString &resto);
    void terminoConsulta();
    void terminoAccion(int codigo, bool cancelado);
    void actualizarBotones();
    QString servidorElegido(bool *encendido = nullptr) const;
    QStringList servidoresMarcados() const;

    Ui::PaginaMinecraft *ui;
    QString script;
    ProcesoLogica consulta;    // lista de servidores e instancias (rápida)
    ProcesoLogica plugins;     // plugins del servidor elegido (consulta a Modrinth; se cancela al cambiar)
    ProcesoLogica accion;      // iniciar, detener, Paper, plugins, Prism...
    enum class Paso { Servidores, Instancias } paso = Paso::Servidores;
    QSet<QString> marcados;    // servidores marcados (se conservan al actualizar la lista)
    QString elegido;           // el servidor elegido (se conserva al actualizar la lista)
    QString pluginsDe;         // de qué servidor es la lista de plugins
    int pluginsNuevos = 0;
    bool primeraVez = true;
    bool recargarPlugins = false;
    QString mensajeFinal;
};
