// Abrir algo en una ventana de terminal sin depender de konsole. Quién decide qué terminal usar
// es Common/Terminal.sh (konsole si está; si no $TERMINAL, xdg-terminal-exec, kgx,
// gnome-terminal, alacritty, kitty o xterm), así la ventana y Logica/Minecraft.sh usan la misma.

#pragma once

#include <QString>
#include <QStringList>

namespace terminal {

// La terminal que se usaría, o vacío si no hay ninguna instalada
QString disponible(const QString &base);

// Argumentos para «bash» que abren comando en una terminal. esperar: el proceso queda vivo
// hasta que se cierra la ventana (konsole --nofork), para vigilarlo por su pid.
QStringList argumentos(const QString &base, const QStringList &comando, bool esperar = false);

// Mensaje para cuando no hay ninguna terminal
QString sinTerminal();

}
