import QtQuick
import Quickshell
import qs.services
import qs.components

// Files al lado de la papelera (como macOS): abre la carpeta personal en el gestor de archivos.
DockButton {
    tip: I18n.t("Archivos")
    flat: true
    onClicked: Quickshell.execDetached(["xdg-open", Quickshell.env("HOME")])

    AppIcon {
        anchors.centerIn: parent
        name: "system-file-manager"
        fallback: "folder"
        glyph: "folder"
        size: Math.round(38 * Theme.dockScale)
    }
}
