import QtQuick
import qs.services

// Deslizador grueso con ícono, al estilo de los ajustes rápidos de Android.
Item {
    id: root

    property real value: 0
    property string icon: ""
    signal moved(real value)
    signal iconClicked

    implicitHeight: 44

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Theme.surfaceHighest

        Rectangle {
            width: Math.max(parent.height, parent.width * root.value)
            height: parent.height
            radius: height / 2
            color: Theme.primary
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: Theme.animFast } }
        }

        Icon {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            size: 20
            fill: 1
            color: Theme.primaryFg

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.iconClicked()
            }
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.value * 100) + "%"
            font.pixelSize: Theme.textSmall
            color: root.value > 0.85 ? Theme.primaryFg : Theme.fgMuted
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.leftMargin: 40
        cursorShape: Qt.PointingHandCursor
        function update(x) { root.moved(Math.max(0, Math.min(1, (x + 40) / root.width))); }
        onPressed: e => update(e.x)
        onPositionChanged: e => { if (pressed) update(e.x); }
        onWheel: e => root.moved(Math.max(0, Math.min(1, root.value + (e.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
