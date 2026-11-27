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
    bool maquinaElegida = false;                 // elegida a mano (Equipo.conf) y no por la MAC
    bool puedeElegirEquipo = false;              // botón «Este equipo…» (solo PC de Sebastián, por la MAC)

    bool tiene(const QString &programa) const { return programas.contains(programa); }
    bool esSebastian() const { return maquina == u"pc" || maquina == u"instituto"; }
};

enum class TipoAccion {
    Pagina,     // página Qt dentro de la ventana (destino = nombre de la página)
    Terminal,   // script de Resources que necesita terminal, p. ej. por sudo (destino), o un
                // programa (destino vacío y el programa en argumentos). Se abre con konsole o, si
                // no está, con otra terminal (Common/Terminal.sh)
    Programa,   // otro programa (destino = ejecutable, con sus argumentos)
    Logica,     // script de Logica/ sin página: se ejecuta y su LISTO/ERROR se ve abajo
};

struct Accion
{
    QString seccion;
    QString icono;          // nombre de comun/ui/iconos (tema::icono)
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
    QString icono;          // nombre de comun/ui/iconos
    QString titulo;
};

QList<Seccion> secciones();
QList<Accion> acciones();
