// Catálogo de todo lo que ofrece el Manager: secciones del menú lateral y las acciones
// (tarjetas) de cada una, con la condición para mostrarlas en cada computadora.
// Reemplaza a los menús Lista-*.sh: para agregar una opción nueva se agrega acá.

#pragma once

#include <QList>
#include <QSet>
#include <QString>
#include <QStringList>

#include <functional>

// Lo que informa Logica/Entorno.sh
struct Entorno
{
    QString maquina = QStringLiteral("otra");   // pc, instituto, mama, krocante, otra
    bool servidor = false;
    QSet<QString> programas;                     // los que están instalados
    bool restauracion = false;
    bool notificaciones = false;

    bool tiene(const QString &programa) const { return programas.contains(programa); }
    bool esSebastian() const { return maquina == u"pc" || maquina == u"instituto"; }
};

enum class TipoAccion {
    Pagina,     // página Qt dentro de la ventana (destino = nombre de la página)
    Terminal,   // script que necesita terminal, p. ej. por sudo (se abre con konsole)
    Programa,   // otro programa (destino = ejecutable, con sus argumentos)
    Logica,     // script de Logica/ sin página: se ejecuta y su LISTO/ERROR se ve abajo
};

struct Accion
{
    QString seccion;
    QString icono;          // emoji, como en los menús de antes
    QString titulo;
    QString descripcion;
    TipoAccion tipo;
    QString destino;
    QStringList argumentos;
    std::function<bool(const Entorno &)> visible;
};

struct Seccion
{
    QString id;
    QString icono;
    QString titulo;
};

QList<Seccion> secciones();
QList<Accion> acciones();
