// Asistente «Crear servidor» del Panel de Minecraft (desde la 4.14.0). Guía paso a paso:
//   1. grupo, nombre y si empieza de cero o desde un modpack de Modrinth
//   2. software (Vanilla, Paper, Fabric, Forge) y versión — o el modpack y su versión (que deciden las dos cosas)
//   3. contenido: un mundo existente (carpeta, .zip o el de otro servidor) y plugins (Paper) o mods (Fabric/Forge)
//   4. configuración: memoria, modo, dificultad, jugadores, etc. y aceptar el EULA de Minecraft
//   5. resumen
// Solo arma la configuración: la creación la hace «Minecraft.sh crear» (la corre el panel con configuracion()
// por stdin, igual que las demás acciones). Las listas salen de «opciones», «buscar-modrinth» y
// «modpack-versiones»: solo se ofrece lo que es compatible con el software y la versión elegidos, y el
// script vuelve a comprobar todo al crear.

#pragma once

#include "ProcesoLogica.h"

#include <QHash>
#include <QStringList>
#include <QWizard>

class QButtonGroup;
class QCheckBox;
class QComboBox;
class QLabel;
class QLineEdit;
class QListWidget;
class QPlainTextEdit;
class QRadioButton;
class QSpinBox;
class QPushButton;

class AsistenteMinecraft : public QWizard
{
    Q_OBJECT

public:
    // servidores: los que ya existen (ruta → encendido), para copiar su mundo
    AsistenteMinecraft(const QString &script, const QHash<QString, bool> &servidores, QWidget *parent = nullptr);
    ~AsistenteMinecraft() override;

    QByteArray configuracion() const;   // CLAVE=valor por línea, para «Minecraft.sh crear»
    QString titulo() const;             // «26.3 SMP-1 (Amigos)»

    // Lo usan las páginas (ver AsistenteMinecraft.cpp)
    bool baseCompleta() const;
    bool softwareCompleto() const;
    bool configuracionCompleta() const;
    int despuesDeBase() const;
    void armarResumen();
    void prepararContenido();

private:
    void eventoOpciones(const QString &palabra, const QString &resto);
    void llenarVersiones();
    void buscar(bool modpack);
    void eventoBusqueda(const QString &palabra, const QString &resto);
    void elegirModpack();
    void eventoModpack(const QString &palabra, const QString &resto);
    void agregarComplemento();
    void agregarArchivo();
    void elegirMundo(bool carpeta);
    QString tipo() const;          // vanilla|paper|fabric|forge (del modpack si hay)
    QString version() const;
    bool conModpack() const;
    void actualizarRuta();

    QString script;
    QHash<QString, bool> existentes;
    ProcesoLogica opciones, busqueda, versionesModpack;
    QHash<QString, QStringList> software;    // versión → software disponible
    QStringList ordenVersiones;
    QStringList javas;
    bool opcionesListas = false;
    bool buscandoModpack = false;

    // 1. Base
    QComboBox *comboGrupo;
    QLineEdit *editNombre;
    QRadioButton *radioCero, *radioModpack;
    QLabel *etiquetaRuta;
    // 2a. Software y versión
    QButtonGroup *grupoSoftware;
    QComboBox *comboVersion;
    QLabel *estadoOpciones;
    // 2b. Modpack
    QLineEdit *editBuscarModpack;
    QListWidget *listaModpacks;
    QComboBox *comboVersionModpack;
    QLabel *estadoModpack;
    struct VersionModpack { QString nombre, juego, cargador, url, sha512; };
    QList<VersionModpack> versionesDelModpack;
    QString modpackElegido;    // título
    // 3. Contenido
    QButtonGroup *grupoMundo;
    QLineEdit *editMundo;
    QComboBox *comboMundoServidor;
    QLabel *etiquetaComplementos;
    QLineEdit *editBuscar;
    QPushButton *botonBuscar, *botonAgregar, *botonArchivo, *botonQuitar;
    QListWidget *listaResultados, *listaElegidos;
    QLabel *estadoBusqueda;
    // 4. Configuración
    QSpinBox *spinRam, *spinJugadores, *spinDistancia;
    QLineEdit *editMotd, *editSemilla;
    QComboBox *comboModo, *comboDificultad;
    QCheckBox *checkHardcore, *checkWhitelist, *checkOnline, *checkPvp, *checkEula;
    // 5. Resumen
    QPlainTextEdit *textoResumen;
};
