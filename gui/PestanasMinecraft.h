// Pestañas del servidor elegido en el Panel de Minecraft (desde la 4.15.0):
//   Jugadores  quién entró, ops, lista blanca, baneados y expulsar (Minecraft.sh jugadores-lista / jugador)
//   Opciones   server.properties con explicación de cada opción, MOTD con colores, apagado automático y extras
//              (Geyser, BlueMap, ícono)  (opciones-servidor / propiedades-cambiar / extra / icono)
//   Respaldos  mundos guardados, jars, plugins y mods reemplazados: restaurar o guardar el mundo ahora
// Solo consultan por su cuenta; lo que cambia algo lo piden con la señal accion(), que corre el panel con su
// barra, su «Cancelar» y sus avisos (y al terminar les pide refrescar()).

#pragma once

#include "ProcesoLogica.h"

#include <QHash>
#include <QWidget>

class QCheckBox;
class QComboBox;
class QLabel;
class QLineEdit;
class QPushButton;
class QSpinBox;
class QTreeWidget;
class QFormLayout;

class PestanaServidor : public QWidget
{
    Q_OBJECT

public:
    PestanaServidor(const QString &script, QWidget *parent = nullptr);
    ~PestanaServidor() override;
    // El servidor elegido en la lista (vacío: ninguno). Si cambió algo, vuelve a consultar.
    void elegir(const QString &servidor, bool encendido, const QString &tipo);
    void ponerOcupado(bool ocupado);   // el panel está corriendo una acción
    virtual void refrescar() = 0;

signals:
    void accion(const QStringList &argumentos, const QString &estado, const QByteArray &entrada);

protected:
    virtual void actualizarBotones() = 0;
    QString etiqueta() const;   // «26.3 SMP-1 (Amigos)»
    QString script, servidor, tipo;
    bool encendido = false, ocupado = false;
    ProcesoLogica consulta;
};

class PestanaJugadores : public PestanaServidor
{
    Q_OBJECT

public:
    explicit PestanaJugadores(const QString &script, QWidget *parent = nullptr);
    void refrescar() override;

protected:
    void actualizarBotones() override;

private:
    void evento(const QString &palabra, const QString &resto);
    void hacer(const QString &accionJugador, const QString &nombre, bool pedirMotivo = false);
    QString elegido() const;

    QLabel *estado;
    QTreeWidget *lista;
    QCheckBox *checkBlanca;
    QPushButton *botonOp, *botonBlanca, *botonBan, *botonExpulsar, *botonAgregarBlanca, *botonAgregarOp;
    QLineEdit *editNombre;
    bool consolaComandos = false;
};

class PestanaOpciones : public PestanaServidor
{
    Q_OBJECT

public:
    explicit PestanaOpciones(const QString &script, QWidget *parent = nullptr);
    void refrescar() override;

protected:
    void actualizarBotones() override;

private:
    void evento(const QString &palabra, const QString &resto);
    void armar();       // el formulario, con lo que contestó opciones-servidor
    void guardar();
    void cambiarIcono();
    void verMotd();
    QString valorDe(const QString &clave) const;
    QString motd() const;

    struct Opcion { QString clave, tipo, parametros, etiqueta, ayuda, valor; };
    QList<Opcion> opciones;
    QHash<QString, QWidget *> campos;
    QHash<QString, QString> iniciales;   // lo que mostraba cada campo al cargar
    QString motdInicial;
    QHash<QString, QString> ajustes;
    bool tieneIcono = false;
    QWidget *contenido;
    QFormLayout *formulario;
    QLineEdit *motd1, *motd2;
    QLabel *vistaMotd;
    QSpinBox *spinVacio;
    QCheckBox *checkApagarPc;
    QPushButton *botonGuardar, *botonGeyser, *botonBluemap, *botonIcono;
    QLabel *estado;
    bool cargando = false;
};

class PestanaRespaldos : public PestanaServidor
{
    Q_OBJECT

public:
    explicit PestanaRespaldos(const QString &script, QWidget *parent = nullptr);
    void refrescar() override;

protected:
    void actualizarBotones() override;

private:
    void restaurar();
    QTreeWidget *lista;
    QPushButton *botonGuardar, *botonRestaurar;
    QLabel *estado;
};
