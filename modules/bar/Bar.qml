import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Barra superior: app activa | bandeja, estado, hora y apagado. Flotante (secciones
// sueltas) o pegada (franja completa), según Personalizar. Con el modo «una sola
// barra» no se muestra: todo va en la barra de tareas (Dock.qml).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: bar

        required property ShellScreen modelData

        readonly property bool floating: Settings.layout.topBar.floating

        screen: modelData
        visible: Settings.layout.style !== "single"
        WlrLayershell.namespace: "quantum-bar"
        anchors { top: true; left: true; right: true }
        implicitHeight: floating ? 54 : 46
        exclusiveZone: implicitHeight
        color: "transparent"

        // franja completa (modo pegada)
        Rectangle {
            anchors.fill: parent
            visible: !bar.floating
            color: Theme.alpha(Theme.surface, Theme.glassOpacity("bar"))
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.alpha(Theme.fg, 0.08) }
        }

        component Section: Card {
            radius: height / 2
            color: bar.floating ? Theme.alpha(Theme.surface, Theme.glassOpacity("bar")) : "transparent"
            border.width: bar.floating ? 1 : 0
            implicitHeight: 42
            implicitWidth: row.implicitWidth + 12
            default property alias content: row.data
            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: 4
            }
        }

        // Izquierda: la app activa (o el logo si no hay ninguna)
        Section {
            id: activeApp
            readonly property var win: Wm.active && !Wm.active.minimized ? Wm.active : null
            visible: Settings.layout.topBar.showApp
            anchors.left: parent.left
            anchors.leftMargin: bar.floating ? 10 : 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: bar.floating ? 3 : 0
            Item {
                implicitWidth: 26
                implicitHeight: 26
                Image {
                    anchors.fill: parent
                    visible: !activeApp.win
                    source: Quickshell.shellDir + "/assets/quantum-mark.svg"
                    sourceSize: Qt.size(52, 52)
                }
                AppIcon {
                    anchors.fill: parent
                    visible: !!activeApp.win
                    size: 22
                    name: activeApp.win ? Wm.iconFor(activeApp.win.appId) : ""
                }
            }
            Txt {
                Layout.leftMargin: 4
                Layout.rightMargin: 6
                Layout.maximumWidth: bar.width * 0.3 - 40
                text: activeApp.win ? Wm.nameFor(activeApp.win.appId) : "Quantum"
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
        }

        // Derecha: bandeja, estado, hora, notificaciones y apagado
        Section {
            anchors.right: parent.right
            anchors.rightMargin: bar.floating ? 10 : 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: bar.floating ? 3 : 0
            SystemArea { window: bar; compact: bar.width < 1300 }
        }
    }
}
