import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.services

// Bandeja del sistema (Steam, Discord, etc.).
RowLayout {
    id: root

    required property var window
    // blueman-applet solo está para aprobar las conexiones Bluetooth (agente): su ícono
    // repetiría el Bluetooth que ya está en la barra y en el Centro de control
    function hidden(i): bool { return [i.id, i.title, i.icon].some(s => String(s ?? "").toLowerCase().includes("blueman")); }
    readonly property var items: SystemTray.items.values.filter(i => !hidden(i))
    spacing: 2
    visible: items.length > 0

    Repeater {
        model: root.items

        MouseArea {
            id: item
            required property SystemTrayItem modelData

            implicitWidth: 30
            implicitHeight: 30
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            onClicked: e => {
                if (e.button === Qt.RightButton || modelData.onlyMenu) {
                    const p = item.mapToItem(null, 0, item.height + 8);
                    modelData.display(root.window, p.x, p.y);
                } else {
                    modelData.activate();
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: item.containsMouse ? Theme.alpha(Theme.fg, 0.1) : "transparent"
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: 18
                source: item.modelData.icon
            }
        }
    }

    Rectangle {
        Layout.leftMargin: 4
        Layout.rightMargin: 2
        implicitWidth: 1
        implicitHeight: 18
        color: Theme.outlineVariant
    }
}
