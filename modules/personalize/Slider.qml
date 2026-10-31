import QtQuick
import qs.services
import qs.components

// Deslizador con valor a la derecha. Avisa el valor al soltar (y mientras arrastra
// si `live` es verdadero), redondeado a `step`.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real step: 0.01
    property real value: 0
    property bool live: false
    property string text: ""
    signal moved(real value)

    property real _shown: value
    onValueChanged: if (!drag.pressed) _shown = value

    implicitWidth: 260
    implicitHeight: 32

    function snap(x) {
        const raw = from + Math.max(0, Math.min(1, x / track.width)) * (to - from);
        return Math.round(raw / step) * step;
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: valueLabel.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 8
        radius: 4
        color: Theme.surfaceHighest
        Rectangle {
            width: Math.max(8, parent.width * (root._shown - root.from) / (root.to - root.from))
            height: parent.height
            radius: 4
            color: Theme.primary
        }
        Rectangle {
            x: parent.width * (root._shown - root.from) / (root.to - root.from) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: drag.pressed ? 24 : 20
            height: width
            radius: width / 2
            color: Theme.primary
            border.width: 4
            border.color: Theme.surfaceContainer
            Behavior on width { NumberAnimation { duration: Theme.animFast } }
        }
    }
    Txt {
        id: valueLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 56
        horizontalAlignment: Text.AlignRight
        text: root.text
        font.weight: Font.DemiBold
        color: Theme.fgMuted
    }
    MouseArea {
        id: drag
        anchors.fill: track
        anchors.margins: -10
        cursorShape: Qt.PointingHandCursor
        onPressed: e => { root._shown = root.snap(e.x - 10); if (root.live) root.moved(root._shown); }
        onPositionChanged: e => { if (pressed) { root._shown = root.snap(e.x - 10); if (root.live) root.moved(root._shown); } }
        onReleased: root.moved(root._shown)
    }
}
