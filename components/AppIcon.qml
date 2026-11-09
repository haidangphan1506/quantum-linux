import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

// Ícono de app con respaldo: si el tema no tiene el ícono, usa el genérico,
// y si tampoco existe, un ícono de Material Symbols (nunca el cuadro magenta).
Item {
    id: root

    property string name: ""
    property int size: 24
    // respaldo del tema si «name» no existe (vacío = sin respaldo: se ve el glifo)
    property string fallback: "application-x-executable"
    // glifo de Material Symbols si no hay ningún archivo de ícono
    property string glyph: "apps"

    readonly property string path: {
        const own = root.name ? Quickshell.iconPath(root.name, true) : "";
        return own || (root.fallback ? Quickshell.iconPath(root.fallback, true) : "");
    }

    implicitWidth: size
    implicitHeight: size

    IconImage {
        id: img
        anchors.fill: parent
        implicitSize: root.size
        source: root.path
        visible: root.path !== "" && status !== Image.Error
    }
    Icon {
        anchors.centerIn: parent
        visible: !img.visible
        text: root.glyph
        size: root.size
        color: Theme.fgMuted
    }
}
