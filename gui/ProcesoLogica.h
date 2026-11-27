// Ejecuta un script de Resources/Logica y avisa cada evento que imprime («PALABRA resto»,
// una línea por evento). Lo usan las páginas para no repetir el manejo del proceso:
// grupo de procesos propio (Cancelar corta también a los hijos, como rsync o adb),
// entrada estándar opcional (contraseñas) y lectura línea por línea.
// Uno por vez: si ya hay algo corriendo, iniciar() no lo pisa ni lo encola, pero avisa
// (devuelve false, emite rechazado() y muestra un aviso en la ventana activa).

#pragma once

#include <QObject>
#include <QProcess>

class ProcesoLogica : public QObject
{
    Q_OBJECT

public:
    explicit ProcesoLogica(QObject *parent = nullptr);
    // Si todavía corre algo, corta todo el grupo sin avisar (la página ya se está borrando)
    ~ProcesoLogica() override;

    // script: ruta completa del .sh; entrada: lo que se le escribe por stdin (puede ir vacío).
    // Devuelve false si no se inició porque ya había otro corriendo.
    bool iniciar(const QString &script, const QStringList &argumentos, const QByteArray &entrada = {});
    // SIGTERM a todo el grupo (el script y sus hijos)
    void cancelar();
    // Cancela y espera hasta 3 s; si el grupo sigue vivo, SIGKILL (no queda nada colgado)
    void cancelarYEsperar();
    bool ocupado() const;

signals:
    void evento(const QString &palabra, const QString &resto);
    void terminado(int codigo, bool cancelado);
    // iniciar() no pudo arrancar porque ya había otro proceso corriendo
    void rechazado(const QString &motivo);

private:
    void leer();

    QProcess proceso;
    bool cancelado = false;
};
