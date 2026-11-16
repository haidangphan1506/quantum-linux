import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Lista de dispositivos de audio (Sonido → Salida / Entrada), como la tabla de macOS:
// nombre y tipo; el predeterminado va marcado. Clic para elegirlo.
ColumnLayout {
    id: dl

    property var nodes: []
    property var current: null
    signal chosen(var node)

    function nodeName(n: var): string { return n?.description || n?.nickname || n?.name || "?"; }
    function kind(n: var): string {
        const s = (n?.name ?? "") + " " + (n?.description ?? "");
        return /bluez|bluetooth/i.test(s) ? "Bluetooth" : /hdmi|displayport/i.test(s) ? "HDMI / DisplayPort" : /usb/i.test(s) ? "USB" : I18n.t("Integrado");
    }

    Layout.fillWidth: true
    spacing: 0

    Repeater {
        model: dl.nodes
        Item {
            id: dev
            required property var modelData
            required property int index
            readonly property bool on: dl.current === modelData
            Layout.fillWidth: true
            implicitHeight: 40
            Rectangle { visible: dev.index > 0; width: parent.width; height: 1; color: Theme.alpha(Theme.fg, 0.08) }
            Rectangle {
                anchors.fill: parent; anchors.topMargin: 3; anchors.bottomMargin: 3
                anchors.leftMargin: -8; anchors.rightMargin: -8
                radius: 6
                color: dev.on ? Theme.alpha("#007aff", 0.14) : devArea.containsMouse ? Theme.alpha(Theme.fg, 0.04) : "transparent"
            }
            RowLayout {
                anchors.fill: parent
                spacing: 10
                Txt { Layout.fillWidth: true; text: dl.nodeName(dev.modelData); elide: Text.ElideRight }
                Txt { text: dl.kind(dev.modelData); color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                Icon { text: "check"; size: 18; color: "#007aff"; opacity: dev.on ? 1 : 0 }
            }
            MouseArea {
                id: devArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dl.chosen(dev.modelData)
            }
        }
    }
    Txt {
        visible: dl.nodes.length === 0
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        text: I18n.t("No se encontraron dispositivos.")
        color: Theme.fgMuted
        font.pixelSize: Theme.textSmall
    }
}
