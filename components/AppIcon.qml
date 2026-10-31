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

    readonly property string path: {
        if (root.name.startsWith("/")) return "file://" + root.name;   // ruta absoluta (ej. assets/*.svg)
        const own = root.name ? Quickshell.iconPath(root.name, true) : "";
        return own || Quickshell.iconPath("application-x-executable", true);
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
        text: "apps"
        size: root.size
        color: Theme.fgMuted
    }
}
