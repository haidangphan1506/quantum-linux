import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Deslizador estilo macOS: pista fina, perilla blanca y, opcionalmente, etiquetas en
// los extremos (minText / maxText, como «Lenta … Rápida») y el valor a la derecha (text).
// Avisa el valor al soltar (y mientras arrastra si `live`), redondeado a `step`.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real step: 0.01
    property real value: 0
    property bool live: false
    property string text: ""
    property string minText: ""
    property string maxText: ""
    property string minIcon: ""            // ícono pequeño a la izquierda / derecha de la pista (como el altavoz de macOS)
    property string maxIcon: ""
    property int ticks: 0                  // marcas debajo de la pista (como en macOS)
    signal moved(real value)

    property real _shown: value
    onValueChanged: if (!drag.pressed) _shown = value

    implicitWidth: 260
    implicitHeight: minText || maxText ? 40 : 28

    function snap(x) {
        const raw = from + Math.max(0, Math.min(1, x / track.width)) * (to - from);
        return Math.min(to, Math.max(from, Math.round(raw / step) * step));
    }

    Rectangle {
        id: track
        anchors.left: minIc.visible ? minIc.right : parent.left
        anchors.leftMargin: minIc.visible ? 8 : 9
        anchors.right: valueLabel.visible ? valueLabel.left : maxIc.visible ? maxIc.left : parent.right
        anchors.rightMargin: valueLabel.visible ? 12 : maxIc.visible ? 8 : 9
        y: 12
        height: 4
        radius: 2
        color: Theme.alpha(Theme.fg, 0.15)
        Rectangle {
            width: Math.max(4, parent.width * (root._shown - root.from) / (root.to - root.from))
            height: parent.height
            radius: 2
            color: Theme.primary
        }
        Repeater {
            model: root.ticks
            Rectangle {
                required property int index
                x: index * (track.width / Math.max(1, root.ticks - 1)) - 0.5
                y: 9
                width: 1; height: 5
                color: Theme.alpha(Theme.fg, 0.3)
            }
        }
        Rectangle {
            x: parent.width * (root._shown - root.from) / (root.to - root.from) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 9
            color: "white"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.18)
            scale: drag.pressed ? 1.1 : 1
            Behavior on scale { NumberAnimation { duration: Theme.animFast } }
        }
    }
    Icon {
        id: minIc
        visible: root.minIcon !== ""
        anchors.left: parent.left
        y: track.y + track.height / 2 - height / 2
        text: root.minIcon
        size: 16
        color: Theme.fgMuted
    }
    Icon {
        id: maxIc
        visible: root.maxIcon !== ""
        anchors.right: valueLabel.visible ? valueLabel.left : parent.right
        y: track.y + track.height / 2 - height / 2
        text: root.maxIcon
        size: 18
        color: Theme.fgMuted
    }
    Txt {
        visible: root.minText !== ""
        anchors.left: track.left
        anchors.leftMargin: -6
        anchors.top: track.bottom
        anchors.topMargin: 9
        text: root.minText
        font.pixelSize: Theme.textSmall - 1
        color: Theme.fgMuted
    }
    Txt {
        visible: root.maxText !== ""
        anchors.right: track.right
        anchors.rightMargin: -6
        anchors.top: track.bottom
        anchors.topMargin: 9
        text: root.maxText
        font.pixelSize: Theme.textSmall - 1
        color: Theme.fgMuted
    }
    Txt {
        id: valueLabel
        visible: root.text !== ""
        anchors.right: parent.right
        y: track.y + track.height / 2 - height / 2
        width: 52
        horizontalAlignment: Text.AlignRight
        text: root.text
        color: Theme.fgMuted
        font.pixelSize: Theme.textSmall + 1
    }
    MouseArea {
        id: drag
        anchors.left: track.left
        anchors.right: track.right
        anchors.top: parent.top
        height: 28
        anchors.leftMargin: -9
        anchors.rightMargin: -9
        cursorShape: Qt.PointingHandCursor
        onPressed: e => { root._shown = root.snap(e.x - 9); if (root.live) root.moved(root._shown); }
        onPositionChanged: e => { if (pressed) { root._shown = root.snap(e.x - 9); if (root.live) root.moved(root._shown); } }
        onReleased: root.moved(root._shown)
    }
}
