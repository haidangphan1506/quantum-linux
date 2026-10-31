import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Tarjeta grande para elegir con un dibujo (estilos, distribución, esquinas…).
Rectangle {
    id: root

    property string title: ""
    property string help: ""
    property bool selected: false
    property int previewHeight: 110
    default property alias preview: art.data
    signal clicked

    Layout.fillWidth: true
    implicitHeight: previewHeight + labels.implicitHeight + 34
    radius: Theme.radiusLarge
    color: area.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
    border.width: selected ? 2 : 1
    border.color: selected ? Theme.primary : Theme.alpha(Theme.fg, 0.06)
    scale: area.pressed ? 0.97 : area.containsMouse ? 1.015 : 1
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Item {
        id: art
        x: 12; y: 12
        width: parent.width - 24
        height: root.previewHeight
    }

    ColumnLayout {
        id: labels
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: art.bottom
        anchors.margins: 12
        anchors.topMargin: 10
        spacing: 1
        Txt { Layout.fillWidth: true; text: root.title; font.weight: Font.Bold }
        Txt {
            visible: root.help !== ""
            Layout.fillWidth: true
            text: root.help
            color: Theme.fgMuted
            font.pixelSize: Theme.textSmall
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            maximumLineCount: 2
        }
    }

    // marca de elegido
    Rectangle {
        visible: root.selected
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        width: 26; height: 26; radius: 13
        color: Theme.primary
        Icon { anchors.centerIn: parent; text: "check"; size: 18; color: Theme.primaryFg }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
