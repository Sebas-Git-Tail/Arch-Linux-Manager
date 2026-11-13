// Ejecuta un script de Resources/Logica y avisa cada evento que imprime («PALABRA resto»,
// una línea por evento). Lo usan las páginas para no repetir el manejo del proceso:
// grupo de procesos propio (Cancelar corta también a los hijos, como rsync o adb),
// entrada estándar opcional (contraseñas) y lectura línea por línea.

#pragma once

#include <QObject>
#include <QProcess>

class ProcesoLogica : public QObject
{
    Q_OBJECT

public:
    explicit ProcesoLogica(QObject *parent = nullptr);

    // script: ruta completa del .sh; entrada: lo que se le escribe por stdin (puede ir vacío)
    void iniciar(const QString &script, const QStringList &argumentos, const QByteArray &entrada = {});
    void cancelar();
    void cancelarYEsperar();
    bool ocupado() const;

signals:
    void evento(const QString &palabra, const QString &resto);
    void terminado(int codigo, bool cancelado);

private:
    void leer();

    QProcess proceso;
    bool cancelado = false;
};
