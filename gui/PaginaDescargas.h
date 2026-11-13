// Páginas «Descargar Vídeos», «Descargar Música» y «Descargas en masa»: es la misma página
// con tres modos, porque sus scripts (Logica/Descargar.sh y Logica/Descargas-en-masa.sh)
// usan los mismos eventos. Solo es la interfaz: lanza el script con QProcess y lee su
// avance, una línea por evento (INICIO, ARCHIVO, PROGRESO, MINIATURA, LISTO, FALLO, AVISO, ERROR).
//
// En Vídeos, con «Elegir subtítulos y audio» la descarga tiene un paso previo: primero se
// le pregunta a Descargar.sh (--pistas) qué ofrece el video (eventos AUDIO y SUBTITULO),
// se elige en DialogoPistas y recién después se descarga.

#pragma once

#include "DialogoPistas.h"

#include <QHash>
#include <QProcess>
#include <QTemporaryDir>
#include <QWidget>

namespace Ui { class PaginaDescargas; }
class QListWidgetItem;

class PaginaDescargas : public QWidget
{
    Q_OBJECT

public:
    enum class Tipo { Videos, Musica, Archivos };

    // logica: carpeta Logica (donde están los scripts)
    PaginaDescargas(Tipo tipo, const QString &logica, QWidget *parent = nullptr);
    ~PaginaDescargas() override;

    // Para que la ventana principal pregunte antes de cerrarse a mitad de una descarga
    bool ocupada() const;
    void cancelarYEsperar();

private slots:
    void cambiarPlataforma(int indice);
    void elegirCarpeta();
    void descargar();
    void cancelar();
    void leerSalida();
    void leerErrores();
    void terminoProceso(int codigo, QProcess::ExitStatus estado);
    void actualizarAcciones();
    void reproducir();
    void abrirCarpeta();
    void moverAPapelera();

private:
    void procesarEvento(const QString &linea);
    void anotar(const QString &texto);
    void habilitarFormulario(bool habilitado);
    QString destino() const;
    void buscarPistas();
    void terminoPistas(int codigo, QProcess::ExitStatus estado);
    void iniciarDescarga(const QStringList &audios, const QStringList &subtitulos);
    void terminar(const QString &estado);

    Ui::PaginaDescargas *ui;
    Tipo tipo;
    QString scriptDescargar;
    QProcess proceso;
    QTemporaryDir miniaturas;      // las carátulas se usan como ícono en la lista
    QString miniaturaPendiente;    // MINIATURA llega justo antes de los LISTO
    QString archivoActual;
    int fallidas = 0;
    int listas = 0;
    bool cancelado = false;

    // Lo que se está descargando: se guarda porque con «Elegir subtítulos y audio» el
    // script se ejecuta dos veces (primero --pistas, después la descarga)
    QStringList urlsEnCurso;
    QString carpetaEnCurso;
    bool buscandoPistas = false;                     // está corriendo el paso previo (--pistas)
    // Lo que informó --pistas, por idioma (si varias URLs ofrecen el mismo, queda una vez)
    QHash<QString, PistaAudio> audiosOfrecidos;
    QHash<QString, Subtitulo> subtitulosOfrecidos;
};
