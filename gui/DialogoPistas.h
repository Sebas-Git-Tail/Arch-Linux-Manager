// Diálogo «Subtítulos y pistas de audio» de Descargar Vídeos: muestra lo que ofrecen los
// videos (lo detecta Logica/Descargar.sh --pistas, no hay listas fijas de idiomas) y deja
// marcar qué pistas de audio y qué subtítulos van dentro del archivo. Solo es la interfaz.

#pragma once

#include <QDialog>
#include <QList>
#include <QString>
#include <QStringList>

namespace Ui { class DialogoPistas; }

// Lo que informan los eventos AUDIO y SUBTITULO de Descargar.sh --pistas
struct PistaAudio
{
    QString idioma;             // código, p. ej. «es» o «en-US»
    bool original = false;      // es la pista original del video
};

struct Subtitulo
{
    QString idioma;             // código, p. ej. «es» o «en-orig»
    bool automatico = false;    // generado o traducido automáticamente
    QString nombre;             // cómo lo llama el sitio (puede venir vacío)
};

class DialogoPistas : public QDialog
{
    Q_OBJECT

public:
    DialogoPistas(const QList<PistaAudio> &audios, const QList<Subtitulo> &subtitulos, QWidget *parent = nullptr);
    ~DialogoPistas() override;

    // Los idiomas marcados, en el orden de cada lista (así se le pasan a Descargar.sh)
    QStringList audiosElegidos() const;
    QStringList subtitulosElegidos() const;

protected:
    void keyPressEvent(QKeyEvent *evento) override;

private:
    void filtrarSubtitulos();

    Ui::DialogoPistas *ui;
};
