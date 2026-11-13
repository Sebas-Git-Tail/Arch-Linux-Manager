// Página de un respaldo (Respaldo-Linux, Restauración, trabajo de Carina o Minecraft).
// Es la misma página con distintos tipos, porque todos usan Logica/Respaldo.sh. Solo es
// la interfaz: le pasa la contraseña por la entrada estándar y lee su avance, una línea
// por evento (AVISO, DESTINO, ETAPA, ARCHIVO, PROGRESO, ENCENDIDOS, CONTADOR, LISTO, ERROR).

#pragma once

#include <QProcess>
#include <QWidget>

namespace Ui { class PaginaRespaldo; }

class PaginaRespaldo : public QWidget
{
    Q_OBJECT

public:
    // tipo: linux, restauracion, carina o minecraft (el argumento de Respaldo.sh)
    PaginaRespaldo(const QString &tipo, const QString &logica, QWidget *parent = nullptr);
    ~PaginaRespaldo() override;

    bool ocupada() const;
    void cancelarYEsperar();

signals:
    // Después de un respaldo exitoso (la ventana vuelve a comprobar qué ofrecer:
    // con el primer respaldo deja de aparecer Restauración-Linux)
    void respaldoTerminado();

private slots:
    void empezar(bool forzar = false);
    void cancelar();
    void leerSalida();
    void terminoProceso(int codigo, QProcess::ExitStatus estado);

private:
    void procesarEvento(const QString &linea);
    void anotar(const QString &texto);
    void habilitarFormulario(bool habilitado);

    Ui::PaginaRespaldo *ui;
    QString tipo;
    QString scriptRespaldo;
    QProcess *proceso = nullptr;   // el respaldo en curso (uno nuevo por cada vez)
    QString contrasena;            // se guarda solo mientras dura el respaldo
    QString encendidos;            // servidores de Minecraft encendidos (código 4)
    QString mensajeFinal;
    bool cancelado = false;
};
