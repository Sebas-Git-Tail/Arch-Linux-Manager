// Página de un respaldo (Respaldo-Linux, Restauración, trabajo de Carina o Minecraft).
// Es la misma página con distintos tipos, porque todos usan Logica/Respaldo.sh. Solo es
// la interfaz: le pasa la contraseña por la entrada estándar y lee su avance, una línea
// por evento (AVISO, DESTINO, ETAPA, ARCHIVO, PROGRESO, ENCENDIDOS, CONTADOR, LISTO, ERROR).

#pragma once

#include <QProcess>
#include <QWidget>

class QComboBox;
class QGroupBox;
class QLineEdit;
class QPushButton;
class QRadioButton;
class QToolButton;
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
    // Lo que está corriendo: un respaldo, una restauración o la búsqueda de copias anteriores
    enum class Operacion { Respaldo, Restauracion, Anteriores };

    void iniciar(Operacion cual, const QStringList &argumentosScript);
    bool tomarContrasena();
    // «Restaurar desde el servidor» (solo en Respaldo-Linux): todo o una carpeta/archivo, desde la
    // copia actual o desde una anterior
    void armarRestaurar();
    void elegirRuta(bool carpeta);
    void buscarAnteriores();
    void restaurarElegido();
    void procesarEvento(const QString &linea);
    void anotar(const QString &texto);
    void habilitarFormulario(bool habilitado);
    void cargarHistorial();

    Ui::PaginaRespaldo *ui;
    QString tipo;
    QString scriptRespaldo;
    QProcess *proceso = nullptr;   // el respaldo en curso (uno nuevo por cada vez)
    QString contrasena;            // se guarda solo mientras dura el respaldo
    QString encendidos;            // servidores de Minecraft encendidos (código 4)
    QString mensajeFinal;
    bool cancelado = false;
    Operacion operacion = Operacion::Respaldo;

    QGroupBox *grupoRestaurar = nullptr;
    QRadioButton *radioTodo = nullptr;
    QRadioButton *radioSolo = nullptr;
    QLineEdit *editRuta = nullptr;
    QToolButton *botonElegir = nullptr;
    QComboBox *comboDesde = nullptr;          // «actual» o la fecha de una copia anterior
    QPushButton *botonBuscarAnteriores = nullptr;
    QPushButton *botonRestaurar = nullptr;
};
