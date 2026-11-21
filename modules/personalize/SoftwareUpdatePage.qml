import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// General → Actualización de software (como en macOS): estado, «Actualizar ahora»,
// la lista de paquetes nuevos y el aviso de reinicio pendiente.
ColumnLayout {
    id: page
    spacing: 16

    Component.onCompleted: { Updates.check(); Updates.checkReboot(); }

    Group {
        OptionRow {
            title: Updates.checking ? I18n.t("Buscando actualizaciones…")
                 : Updates.count > 0 ? Updates.count + " " + I18n.t("actualizaciones disponibles")
                 : I18n.t("El sistema está al día")
            help: Updates.count > 0 ? I18n.t("Se abre una terminal que instala todo de una vez (pacman / paru).")
                                    : I18n.t("Se revisa sola cada 3 días.")
            icon: Updates.count > 0 ? "system_update_alt" : "verified"
            iconColor: Updates.count > 0 ? "#FF9500" : "#34C759"
            RowLayout {
                spacing: 8
                PillButton { visible: Updates.count > 0; text: I18n.t("Actualizar ahora"); primary: true; implicitHeight: 30; onClicked: Updates.update() }
                PillButton { text: I18n.t("Buscar de nuevo"); implicitHeight: 30; enabled_: !Updates.checking; onClicked: Updates.check() }
            }
        }
        OptionRow {
            visible: Updates.rebootNeeded
            title: I18n.t("Reinicio pendiente")
            help: I18n.t("Se actualizó una parte del sistema que se usa al arrancar.") + (Updates.friendly() ? " (" + Updates.friendly() + ")" : "")
            icon: "restart_alt"
            iconColor: "#FF3B30"
            PillButton { text: I18n.t("Reiniciar…"); implicitHeight: 30; onClicked: Updates.reboot() }
        }
    }

    Group {
        visible: Updates.list.length > 0
        title: I18n.t("Paquetes")
        help: Updates.list.length > 40 ? I18n.t("Y") + " " + (Updates.list.length - 40) + " " + I18n.t("más.") : ""
        Repeater {
            model: Updates.list.slice(0, 40)
            OptionRow {
                required property var modelData
                title: modelData.name
                Txt {
                    text: modelData.from && modelData.to ? modelData.from + "  →  " + modelData.to : (modelData.to || "")
                    color: Theme.fgMuted
                    font.pixelSize: Theme.textSmall
                }
            }
        }
    }
}
