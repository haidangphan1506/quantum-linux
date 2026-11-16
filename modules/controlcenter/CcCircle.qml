import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Rectangle {
    id: c
    property string icon
    property bool on: false
    property real iconSize: 30
    signal clicked
    signal rightClicked
    implicitWidth: 76
    implicitHeight: 76
    radius: width / 2
    color: on ? Qt.rgba(1, 1, 1, 0.94) : ca.containsMouse ? Theme.glassTileHover : Theme.glassPanel
    border.width: 1
    border.color: Theme.glassBorder
    scale: ca.pressed ? 0.94 : 1
    Behavior on color { ColorAnimation { duration: Theme.anim } }
    Behavior on scale { NumberAnimation { duration: 90 } }
    Icon {
        anchors.centerIn: parent
        text: c.icon
        size: c.iconSize
        fill: c.on ? 1 : 0
        color: c.on ? "#007aff" : Theme.fg
    }
    MouseArea {
        id: ca
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: e => e.button === Qt.RightButton ? c.rightClicked() : c.clicked()
    }
}
