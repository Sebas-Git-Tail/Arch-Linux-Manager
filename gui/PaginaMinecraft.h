// Página «Panel de Minecraft», con el estilo de Prism Launcher (desde la 4.16.0):
//   Servidores   barra de arriba (crear, carpetas, actualizar, Paper, jugar con Prism), la grilla de servidores
//                por grupo (GrillaServidores) y a la derecha el elegido con su columna de acciones
//   Servidor     (doble clic o «Administrar») páginas a la izquierda: Consola, Plugins/Mods, Jugadores,
//                Opciones y Respaldos (las tres últimas en PestanasMinecraft), e Iniciar/Detener/Reiniciar abajo
//   Abajo        estado de la acción en curso (con Cancelar), avisos y el resumen del elegido
// Solo es la interfaz: la lógica está en Logica/Minecraft.sh (apagado automático incluido, en «vigilar»).

#pragma once

#include "ProcesoLogica.h"

#include <QStringList>
#include <QTimer>
#include <QWidget>

class GrillaServidores;
class QLabel;
class QLineEdit;
class QListWidget;
class QMenu;
class QPlainTextEdit;
class QProgressBar;
class QPushButton;
class QStackedWidget;
class QTreeWidget;
class PestanaServidor;
class PestanaJugadores;
class PestanaOpciones;
class PestanaRespaldos;

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
    QWidget *armarVistaServidores();
    QWidget *armarVistaServidor();
    QWidget *armarPaginaConsola();
    QWidget *armarPaginaPlugins();
    void abrirServidor(const QString &ruta);
    void volverALista();
    void mostrarElegido();       // el panel de la derecha, la barra de abajo y la vista del servidor
    void consultar();            // servidores (y la primera vez, las instancias de Prism)
    void consultarPlugins();     // los del servidor elegido
    void ejecutar(const QStringList &argumentos, const QString &estado, const QByteArray &entrada = {});
    void iniciar();
    void detener();
    void reiniciar();
    void actualizarPaper();
    void cambiarRam();
    void reiniciarMundo();
    void abrirCarpeta();
    void actualizarPlugins();
    void instalarPlugin(bool enSeleccionados);
    void crearServidor();
    void cambiarVersion();
    void packJugadores();
    void verConsola();           // registro en vivo del elegido (se corta al cambiar o al salir)
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
    void actualizarPestanas();
    QList<PestanaServidor *> pestanas() const;
    QString servidorElegido(bool *encendido = nullptr) const;
    QString tipoElegido() const;

    QString script;
    ProcesoLogica consulta;    // lista de servidores e instancias (rápida)
    ProcesoLogica plugins;     // plugins del servidor elegido (consulta a Modrinth; se cancela al cambiar)
    ProcesoLogica accion;      // iniciar, detener, Paper, plugins, Prism...
    ProcesoLogica registro;    // tail -F del registro del servidor elegido (mientras se ve la página)
    ProcesoLogica conectados;  // quién está conectado (cada 10 s)
    ProcesoLogica envio;       // comandos y «Abrir en una terminal» (rápidos, no bloquean lo demás)
    QTimer temporizadorJugadores;

    // Vistas
    QStackedWidget *vistas;
    GrillaServidores *grilla;
    // Barra de arriba
    QPushButton *botonCrear, *botonCarpetas, *botonActualizarLista, *botonPaper, *botonJugar;
    QMenu *menuJugar;
    // Panel de la derecha
    QLabel *iconoElegido, *nombreElegido, *tipoElegidoEtiqueta, *estadoElegido;
    QPushButton *botonIniciar, *botonDetener, *botonReiniciar, *botonAdministrar, *botonCarpeta, *botonCambiarVersion,
        *botonRam, *botonReiniciarMundo, *botonInstalarVarios;
    QWidget *accionesUno, *accionesVarios;
    QLabel *etiquetaVarios;
    // Vista del servidor
    QLabel *iconoCabecera, *tituloServidor, *estadoServidor, *tituloPagina;
    QListWidget *listaPaginas;
    QStackedWidget *paginas;
    QPushButton *botonIniciar2, *botonDetener2, *botonReiniciar2;
    // Consola
    QLabel *etiquetaJugadores;
    QPlainTextEdit *textoConsola;
    QLineEdit *editComando;
    QPushButton *botonEnviar, *botonTerminal;
    // Plugins/mods
    QTreeWidget *arbolPlugins;
    QLabel *estadoPlugins;
    QPushButton *botonBuscarPlugins, *botonActualizarPlugins, *botonPlugin, *botonPack, *botonCarpetaPlugins;
    // Abajo
    QLabel *etiquetaEstado, *resumen;
    QProgressBar *barraProgreso;
    QPushButton *botonCancelar, *botonAvisos;
    QPlainTextEdit *registroAvisos;
    int avisosSinVer = 0;

    PestanaJugadores *pestanaJugadores;
    PestanaOpciones *pestanaOpciones;
    PestanaRespaldos *pestanaRespaldos;

    enum class Consola { Nada, Apagado, SoloLectura, Comandos } consola = Consola::Nada;
    QString consolaDe;         // de qué servidor es el registro que se ve
    bool consolaEncendido = false;
    int jugadoresConectados = 0;
    QStringList historial;     // comandos enviados (flechas arriba/abajo)
    int posHistorial = 0;
    bool cancelable = false;   // la acción en curso es un aviso de apagado (se puede cancelar)
    bool creando = false;      // la acción en curso es crear o cambiar un servidor (se puede cancelar: no queda nada)
    bool pluginsSonMods = false;   // el servidor elegido es Fabric/Forge (mods/) y no Paper (plugins/)
    enum class Paso { Servidores, Instancias } paso = Paso::Servidores;
    QString pluginsDe;         // de qué servidor es la lista de plugins
    int pluginsNuevos = 0;
    bool primeraVez = true;
    bool recargarPlugins = false;
    QString mensajeFinal;
};
