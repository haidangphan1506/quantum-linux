import QtQuick
import qs.services

// Fondo translúcido de los paneles del shell.
Rectangle {
    radius: Theme.radiusLarge
    color: Theme.alpha(Theme.surface, Theme.glassOpacity("panels"))
    border.width: 1
    border.color: Theme.alpha(Theme.fg, 0.08)
}
