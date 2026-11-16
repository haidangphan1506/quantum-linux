import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Encabezado de algunas páginas de macOS (General, Notificaciones, Batería…):
// ícono grande en cuadro de color, título y una línea de descripción centrados.
ColumnLayout {
    id: root

    property string icon: ""
    property color color: "#8E8E93"
    property string title: ""
    property string text: ""

    Layout.fillWidth: true
    Layout.topMargin: 10
    Layout.bottomMargin: 4
    spacing: 6

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 64; implicitHeight: 64; radius: 16
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(root.color, 1.18) }
            GradientStop { position: 1; color: root.color }
        }
        Icon { anchors.centerIn: parent; text: root.icon; size: 40; fill: 1; color: "white" }
    }
    Txt {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        text: root.title
        font.pixelSize: Theme.textNormal + 6
        font.weight: Font.Bold
    }
    Txt {
        visible: root.text !== ""
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 480
        text: root.text
        color: Theme.fgMuted
        font.pixelSize: Theme.textSmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }
}
