import QtQuick
import qs.services

// Fondo de cada tarjeta de la pantalla de bloqueo (vidrio oscuro redondeado).
Rectangle {
    default property alias content: inner.data
    radius: 28
    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.72)
    border.width: 1
    border.color: hover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.06)
    Behavior on border.color { ColorAnimation { duration: 200 } }
    scale: hover.hovered ? 1.015 : 1
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    HoverHandler { id: hover }
    clip: true
    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: 22
    }
}
