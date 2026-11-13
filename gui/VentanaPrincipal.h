// Ventana principal del Manager: menú lateral con las secciones y, a la derecha, las
// tarjetas de cada sección o la página de una herramienta (Videos, Música...).
// Qué secciones y tarjetas se ven lo decide Acciones.cpp con lo que informa
// Logica/Entorno.sh (computadora, servidor y programas instalados).

#pragma once

#include "Acciones.h"

#include <QMap>
#include <QStringList>
#include <QProcess>
#include <QProcessEnvironment>
#include <QWidget>

#include <functional>

namespace Ui { class VentanaPrincipal; }

class VentanaPrincipal : public QWidget
{
    Q_OBJECT

public:
    // base: carpeta Resources (scripts, Logica, Logo.png)
    explicit VentanaPrincipal(const QString &base, QWidget *parent = nullptr);
    ~VentanaPrincipal() override;

protected:
    void closeEvent(QCloseEvent *evento) override;

private slots:
    void comprobarEntorno(bool refrescar = false);
    void terminoEntorno(int codigo, QProcess::ExitStatus estado);
    void cambiarSeccion(int fila);
    void volver();

private:
    void construirSecciones();
    QWidget *crearPaginaSeccion(const QList<Accion> &lista);
    void lanzar(const Accion &accion);
    void mostrarPagina(QWidget *pagina, const QString &titulo, bool conVolver);
    void avisar(const QString &texto);
    void mostrarEstado();
    void armarMenuEquipo();
    void elegirEquipo(const QString &equipo);
    QProcessEnvironment entornoScripts() const;

    Ui::VentanaPrincipal *ui;
    QString base;
    Entorno entorno;
    QProcess procesoEntorno;
    QMap<QString, QWidget *> herramientas;     // páginas Qt de las acciones (videos, musica...)

    // Páginas que pueden tener algo en curso (descargas, respaldos): al cerrar la
    // ventana se pregunta y se cancela
    struct Tarea
    {
        std::function<bool()> ocupada;
        std::function<void()> cancelar;
    };
    QList<Tarea> tareas;
    QMap<QString, QWidget *> paginasSeccion;   // id de sección -> su página de tarjetas
    QStringList idsSecciones;                  // en el orden del menú lateral
};
