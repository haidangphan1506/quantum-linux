import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Descargas junto a la papelera (como macOS): un stack con la carpeta de descargas
// (XDG_DOWNLOAD_DIR; si no está configurada, ~/Downloads). Clic = abanico con lo último descargado.
// Quitarlo (arrastrar afuera o menú) apaga la opción en Personalizar.
StackButton {
    id: root

    label: I18n.t("Descargas")
    onRemoveRequested: Settings.set("dock", "showDownloads", false)

    Process {
        running: true
        command: ["xdg-user-dir", "DOWNLOAD"]
        stdout: StdioCollector {
            onStreamFinished: {
                const home = Quickshell.env("HOME");
                const d = text.trim();
                root.path = d && d !== home ? d : home + "/Downloads";
            }
        }
    }
}
