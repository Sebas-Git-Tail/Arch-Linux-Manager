// Piezas visuales del Panel de Minecraft con el estilo de Prism Launcher (desde la 4.16.0):
//   GrillaServidores   los servidores como mosaicos (ícono grande y nombre), agrupados por carpeta con
//                      encabezados plegables, selección múltiple con Ctrl/Shift
//   iconoServidor()    el server-icon.png del servidor o, si no tiene, un ícono pixel-art del software
//                      (Vanilla, Paper, Fabric, Forge), con un punto verde si está encendido
//   botonAccion()      botones planos con ícono, alineados a la izquierda (la columna de acciones de Prism)
// No saben nada de Minecraft.sh: los arma y los usa PaginaMinecraft.

#pragma once

#include <QHash>
#include <QListWidget>
#include <QPixmap>
#include <QPushButton>
#include <QScrollArea>

class QVBoxLayout;

QPixmap iconoServidor(const QString &tipo, const QString &rutaIcono, bool encendido, int lado = 64);
QPushButton *botonAccion(const QString &icono, const QColor &color, const QString &texto, QWidget *padre = nullptr);

// Un servidor tal como lo informa «Minecraft.sh servidores»
struct ServidorMc
{
    QString ruta, tipo, version, mundo, ultimo, ram, jar, apaga, icono;
    bool encendido = false;
    QString grupo() const { return ruta.contains(u'/') ? ruta.section(u'/', 0, 0) : QString(); }
    QString nombre() const { return ruta.section(u'/', -1); }
};

// Lista de mosaicos que se estira hacia abajo en vez de tener barra (la barra es la de toda la grilla)
class ListaMosaicos : public QListWidget
{
    Q_OBJECT

public:
    explicit ListaMosaicos(QWidget *parent = nullptr);
    bool hasHeightForWidth() const override { return true; }
    int heightForWidth(int ancho) const override;
    QSize sizeHint() const override;

protected:
    void resizeEvent(QResizeEvent *evento) override;
};

class GrillaServidores : public QScrollArea
{
    Q_OBJECT

public:
    explicit GrillaServidores(QWidget *parent = nullptr);
    void empezar();                          // antes de recargar
    void agregar(const ServidorMc &s);
    void terminar();                         // arma los grupos (conserva la selección y lo abierto)
    QString elegido() const;                 // el último tocado (vacío si no hay)
    QStringList seleccionados() const;
    void elegir(const QString &ruta);
    const ServidorMc *datos(const QString &ruta) const;
    QList<ServidorMc> todos() const { return lista; }

signals:
    void cambioSeleccion();
    void abrir(const QString &ruta);         // doble clic

private:
    void armar();
    QList<ServidorMc> lista, nueva;
    QHash<QString, bool> abiertos;           // grupos que el usuario abrió o cerró
    QList<ListaMosaicos *> listas;
    QStringList seleccion;
    QString actual;
    QWidget *contenido;
    QVBoxLayout *capa;
};
