import QtQuick
import qs.services
import qs.components

// Interruptor estilo macOS: pequeño, azul al activarse, perilla blanca.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 38
    implicitHeight: 22
    radius: height / 2
    color: checked ? "#007aff" : Theme.alpha(Theme.fg, 0.16)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 2 : 2
        width: parent.height - 4
        height: width
        radius: width / 2
        color: "white"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.08)
        Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
