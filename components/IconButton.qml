import QtQuick
import qs.services

// Botón redondo con un ícono y efecto al pasar el mouse.
Rectangle {
    id: root

    property alias icon: ic.text
    property alias iconSize: ic.size
    property alias iconColor: ic.color
    property bool active: false
    property string tooltip: ""
    signal clicked
    signal rightClicked

    implicitWidth: 36
    implicitHeight: 36
    radius: height / 2
    color: active ? Theme.primary : area.containsMouse ? Theme.alpha(Theme.fg, 0.10) : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Icon {
        id: ic
        anchors.centerIn: parent
        color: root.active ? Theme.primaryFg : Theme.fg
        fill: root.active ? 1 : 0
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}
