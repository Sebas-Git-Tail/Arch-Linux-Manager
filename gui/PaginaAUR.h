// Página «Apps del AUR»: las apps del AUR de esta computadora (Claude, Equibop, Heroic, Linux
// Command Library; cuáles según el equipo, ver Common/AUR.sh), con la versión instalada y la del
// AUR. Instalar y actualizar se hace en una terminal (konsole u otra, ver Terminal.h) con General/AUR-instalar.sh (makepkg pide la
// contraseña); al cerrarse la terminal se vuelven a consultar las versiones. Sin yay ni paru.

#pragma once

#include "ProcesoLogica.h"

#include <QList>
#include <QTimer>
#include <QWidget>

class QLabel;
class QPushButton;
class QVBoxLayout;

class PaginaAUR : public QWidget
{
    Q_OBJECT

public:
    // base: carpeta Resources (Logica/AUR.sh y General/AUR-instalar.sh)
    PaginaAUR(const QString &base, QWidget *parent = nullptr);

protected:
    void showEvent(QShowEvent *evento) override;

private:
    struct App {
        QString paquete, nombre, descripcion, instalada, ultima;
        enum class Estado { Consultando, NoInstalada, Nueva, AlDia, SinDatos } estado = Estado::Consultando;
        QLabel *etiquetaEstado = nullptr;
        QPushButton *boton = nullptr;
    };

    void consultar();
    void procesarEvento(const QString &palabra, const QString &resto);
    void terminoConsulta(int codigo, bool cancelado);
    void armarLista();
    void actualizarFila(App &app);
    void actualizarBotones();
    void instalar(const QStringList &paquetes);
    bool terminalAbierta() const { return pidTerminal > 0; }
    void vigilarTerminal();

    QString base;
    ProcesoLogica proceso;
    // La terminal se abre aparte (startDetached): cerrar el Manager no corta una instalación.
    // Se mira cada segundo si sigue abierta.
    qint64 pidTerminal = 0;
    QTimer relojTerminal;
    QList<App> lista;
    QString error;
    bool consultado = false;

    QVBoxLayout *layoutLista;
    QLabel *etiquetaEstado;
    QPushButton *botonTodas;
    QPushButton *botonBuscar;
};
