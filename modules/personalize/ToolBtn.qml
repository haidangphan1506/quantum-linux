import QtQuick
import qs.services
import qs.components

// Botón pequeño de la barra de herramientas de Ajustes del Sistema
Rectangle {
    id: tb
    property string icon
    property bool enabled_: true
    property bool danger: false
    signal clicked
    implicitWidth: 28
    implicitHeight: 28
    radius: 7
    color: tbArea.containsMouse && enabled_ ? Theme.alpha(Theme.fg, 0.08) : "transparent"
    opacity: enabled_ ? 1 : 0.35
    Icon { anchors.centerIn: parent; text: tb.icon; size: 20; color: tb.danger ? Theme.error : Theme.fg }
    MouseArea {
        id: tbArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: tb.enabled_
        onClicked: tb.clicked()
    }
}
