// Página «Panel de Minecraft»: los servidores de Minecraft Servers/Servidores (iniciar, detener,
// reiniciar, Paper automático, RAM, reiniciar mundo), la consola del elegido (registro en vivo,
// conectados y comandos; desde la 4.12.0 corren en tmux), sus plugins (reconocidos en Modrinth, con
// actualización) y Prism Launcher. Solo es la interfaz; la lógica está en Logica/Minecraft.sh.
// El respaldo de Minecraft tiene su propia página (PaginaRespaldo).

#pragma once

#include "ProcesoLogica.h"

#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QWidget>

class QTreeWidgetItem;

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
    void hideEvent(QHideEvent *evento) override;
    bool eventFilter(QObject *objeto, QEvent *evento) override;    // flechas = comandos anteriores

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
    void verConsola();             // registro en vivo del elegido (se corta al cambiar o al salir)
    void consultarJugadores();
    void enviarComando();
    void abrirTerminal();
    void eventoRegistro(const QString &palabra, const QString &resto);
    void eventoJugadores(const QString &palabra, const QString &resto);
    void detenerOReiniciar(bool reinicio);
    void eventoConsulta(const QString &palabra, const QString &resto);
    void eventoPlugins(const QString &palabra, const QString &resto);
    void eventoAccion(const QString &palabra, const QString &resto);
    void terminoConsulta();
    void terminoAccion(int codigo, bool cancelado);
    void actualizarBotones();
    QTreeWidgetItem *filaGrupo(const QString &grupo);
    QString servidorElegido(bool *encendido = nullptr) const;
    QStringList servidoresMarcados() const;

    Ui::PaginaMinecraft *ui;
    QString script;
    ProcesoLogica consulta;    // lista de servidores e instancias (rápida)
    ProcesoLogica plugins;     // plugins del servidor elegido (consulta a Modrinth; se cancela al cambiar)
    ProcesoLogica accion;      // iniciar, detener, Paper, plugins, Prism...
    ProcesoLogica registro;    // tail -F del registro del servidor elegido (mientras se ve la página)
    ProcesoLogica conectados;  // quién está conectado (cada 10 s)
    ProcesoLogica envio;       // comandos y «Abrir en una terminal» (rápidos, no bloquean lo demás)
    QTimer temporizadorJugadores;
    enum class Consola { Nada, Apagado, SoloLectura, Comandos } consola = Consola::Nada;
    QString consolaDe;         // de qué servidor es el registro que se ve
    bool consolaEncendido = false;
    int jugadoresConectados = 0;
    QStringList historial;     // comandos enviados (flechas arriba/abajo)
    int posHistorial = 0;
    bool cancelable = false;   // la acción en curso es un aviso de apagado (se puede cancelar)
    enum class Paso { Servidores, Instancias } paso = Paso::Servidores;
    QSet<QString> marcados;    // servidores marcados (se conservan al actualizar la lista)
    QString elegido;           // el servidor elegido (se conserva al actualizar la lista)
    QString pluginsDe;         // de qué servidor es la lista de plugins
    int pluginsNuevos = 0;
    bool primeraVez = true;
    bool recargarPlugins = false;
    QString mensajeFinal;
};
