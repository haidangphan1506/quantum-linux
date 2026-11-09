import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Papelera al estilo macOS: ícono lleno si hay algo en la papelera. Clic: abrirla.
DockButton {
    id: root

    tip: I18n.t("Papelera")
    // ~/.local/share/Trash/files (o XDG_DATA_HOME); se revisa cada 5 s (solo un ls | head -1)
    property bool full: false

    onClicked: Quickshell.execDetached(["gio", "open", "trash:///"])

    Process {
        id: check
        running: true
        command: ["sh", "-c", "ls -A \"${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files\" 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.full = text.trim() !== ""
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: check.running = true
    }

    AppIcon {
        anchors.centerIn: parent
        name: root.full ? "user-trash-full" : "user-trash"
        fallback: "user-trash"
        glyph: "delete"
        size: Math.round(38 * Theme.dockScale)
    }
}
