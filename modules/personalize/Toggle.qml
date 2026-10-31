import QtQuick
import qs.services
import qs.components

// Interruptor.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 52
    implicitHeight: 30
    radius: height / 2
    color: checked ? Theme.primary : Theme.surfaceHighest
    border.width: checked ? 0 : 2
    border.color: Theme.outline
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 5 : 7
        width: root.checked ? parent.height - 8 : parent.height - 14
        height: width
        radius: width / 2
        color: root.checked ? Theme.primaryFg : Theme.outline
        Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }
        Behavior on width { NumberAnimation { duration: Theme.animFast } }
        Icon {
            anchors.centerIn: parent
            visible: root.checked
            text: "check"
            size: parent.width - 7
            color: Theme.primary
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
