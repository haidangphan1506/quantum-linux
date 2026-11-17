import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components

// Después de capturar (Super + S / Print) aparece una miniatura en la esquina, como en macOS,
// con acciones: Marcar (abre el editor con círculo, flecha, resaltador, nota…), Copiar,
// Carpeta y Cerrar. Se va sola a los 8 s (no mientras el mouse está encima).
//   qs -c caelestia ipc call screenshot popup /ruta/captura.png
Scope {
    id: root

    property string path: ""
    property bool shown: false
    property string editing: ""            // ruta abierta en el editor ("" = ninguna)
    property real progress: 0
    property bool hovering: false          // el mouse está sobre la miniatura: no se oculta

    function show(p: string): void { path = p; shown = true; hideTimer.restart(); }
    function hide(): void { shown = false; }
    function edit(): void { editing = path; shown = false; }

    onShownChanged: { anim.to = shown ? 1 : 0; anim.duration = shown ? 420 : 220; anim.easing.type = shown ? Easing.OutBack : Easing.InCubic; anim.restart(); }
    NumberAnimation { id: anim; target: root; property: "progress"; easing.overshoot: 1.2 }
    Timer { id: hideTimer; interval: 8000; onTriggered: if (!root.hovering) root.hide(); else hideTimer.restart() }

    IpcHandler {
        target: "screenshot"
        function popup(file: string): void { root.show(file); }
        function edit(file: string): void { root.path = file; root.edit(); }
    }

    // ------------------------------------------------------------ miniatura
    LazyLoader {
        active: root.shown || root.progress > 0.001

        PanelWindow {
            id: win
            screen: Wm.screen
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-screenshot"
            exclusionMode: ExclusionMode.Ignore
            anchors { right: true; bottom: true }
            margins { right: 20; bottom: 20 }
            implicitWidth: 340
            implicitHeight: 234
            color: "transparent"

            Rectangle {
                id: card
                width: 320
                height: 214
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                radius: 14
                color: Theme.popover
                border.width: 1
                border.color: Theme.popoverBorder
                opacity: Math.min(1, root.progress)
                transform: Translate { x: (1 - root.progress) * 60 }

                HoverHandler { onHoveredChanged: { root.hovering = hovered; if (!hovered) hideTimer.restart(); } }

                // miniatura (clic = abrir el editor)
                Rectangle {
                    id: thumb
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 8
                    height: 152
                    radius: 8
                    color: Theme.alpha(Theme.fg, 0.08)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: root.path ? "file://" + root.path : ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(560, 300)
                        asynchronous: true
                        cache: false
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.edit() }
                }

                RowLayout {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 8
                    height: 36
                    spacing: 4

                    PillButton { text: I18n.t("Marcar"); icon: "draw"; primary: true; implicitHeight: 30; onClicked: root.edit() }
                    PillButton {
                        text: I18n.t("Copiar"); icon: "content_copy"; implicitHeight: 30
                        onClicked: { Quickshell.execDetached(["sh", "-c", "wl-copy < '" + root.path.replace(/'/g, "'\\''") + "'"]); root.hide(); }
                    }
                    Item { Layout.fillWidth: true }
                    IconButton { icon: "folder_open"; iconSize: 18; implicitWidth: 30; implicitHeight: 30; onClicked: { Quickshell.execDetached(["xdg-open", root.path.substring(0, root.path.lastIndexOf("/"))]); root.hide(); } }
                    IconButton { icon: "close"; iconSize: 18; implicitWidth: 30; implicitHeight: 30; onClicked: root.hide() }
                }
            }
        }
    }

    // ------------------------------------------------------------ editor
    LazyLoader {
        active: root.editing !== ""
        Annotator {
            path: root.editing
            onFinished: root.editing = ""
        }
    }
}
