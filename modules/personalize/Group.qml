import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Tarjeta de una sección de opciones, con título, ayuda y contenido.
Rectangle {
    id: root

    property string title: ""
    property string help: ""
    property string icon: ""
    property bool advanced: false          // solo con «Opciones avanzadas»
    default property alias content: body.data

    visible: !advanced || Settings.ui.advanced
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 36
    radius: Theme.radiusLarge
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.alpha(Theme.fg, 0.06)

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        RowLayout {
            visible: root.title !== ""
            Layout.fillWidth: true
            spacing: 10
            Icon { visible: root.icon !== ""; text: root.icon; size: 20; fill: 1; color: Theme.primary }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    spacing: 8
                    Txt { text: root.title; font.pixelSize: Theme.textLarge; font.weight: Font.Bold }
                    Rectangle {
                        visible: root.advanced
                        implicitWidth: advT.implicitWidth + 14; implicitHeight: 20; radius: 10
                        color: Theme.alpha(Theme.primary, 0.16)
                        Txt { id: advT; anchors.centerIn: parent; text: "Avanzado"; font.pixelSize: Theme.textSmall - 1; font.weight: Font.Bold; color: Theme.primary }
                    }
                }
                Txt {
                    visible: root.help !== ""
                    Layout.fillWidth: true
                    text: root.help
                    color: Theme.fgMuted
                    font.pixelSize: Theme.textSmall + 1
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: 12
        }
    }
}
