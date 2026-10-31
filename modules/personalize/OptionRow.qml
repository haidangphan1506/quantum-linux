import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Fila: título y ayuda a la izquierda, el control a la derecha.
RowLayout {
    id: root

    property string title: ""
    property string help: ""
    property string icon: ""
    property bool advanced: false
    default property alias control: holder.data

    visible: !advanced || Settings.ui.advanced
    Layout.fillWidth: true
    spacing: 14

    Rectangle {
        visible: root.icon !== ""
        implicitWidth: 38; implicitHeight: 38; radius: 12
        color: Theme.alpha(Theme.primary, 0.12)
        Icon { anchors.centerIn: parent; text: root.icon; size: 20; color: Theme.primary }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Txt { Layout.fillWidth: true; text: root.title; font.weight: Font.DemiBold }
        Txt {
            visible: root.help !== ""
            Layout.fillWidth: true
            text: root.help
            color: Theme.fgMuted
            font.pixelSize: Theme.textSmall
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }
    Item {
        id: holder
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
