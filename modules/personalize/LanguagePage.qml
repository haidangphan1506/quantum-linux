import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// General → Idioma y región (como en macOS): idioma preferido de Quantum, formato de
// fecha y hora de muestra e idioma del sistema (locale) y método de entrada.
ColumnLayout {
    id: page
    spacing: 16

    property string sysLang: ""
    Component.onCompleted: loc.running = true
    Process {
        id: loc
        command: ["sh", "-c", "localectl status | sed -n 's/.*LANG=//p' | head -1"]
        stdout: StdioCollector { onStreamFinished: page.sysLang = text.trim() }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    Group {
        title: I18n.t("Idiomas preferidos")
        help: I18n.t("El idioma de la barra, los menús, los paneles y esta ventana. Se aplica al instante.")
        Repeater {
            model: I18n.languages
            OptionRow {
                id: lr
                required property var modelData
                required property int index
                readonly property bool on: I18n.lang === modelData.v
                title: modelData.t
                help: on ? I18n.t("Principal") : ""
                MouseArea {
                    parent: lr
                    z: -1
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: I18n.setLang(lr.modelData.v)
                }
                Icon { visible: lr.on; text: "check"; size: 20; color: "#007aff" }
            }
        }
    }

    Group {
        title: I18n.t("Región")
        OptionRow {
            title: I18n.t("Formato de fecha")
            Txt { text: clock.date.toLocaleDateString(I18n.locale, I18n.dayMonth) + ", " + clock.date.getFullYear(); color: Theme.fgMuted }
        }
        OptionRow {
            title: I18n.t("Formato de hora")
            Segmented {
                options: [{ v: true, t: "24h" }, { v: false, t: "12h" }]
                value: Settings.clock.format24h
                onPicked: v => Settings.set("clock", "format24h", v)
            }
        }
        OptionRow {
            title: I18n.t("Primer día de la semana")
            Txt { text: I18n.t("Lunes"); color: Theme.fgMuted }
        }
    }

    Group {
        title: I18n.t("Sistema")
        help: I18n.t("El idioma de las apps lo pone el sistema (locale). Para escribir en vietnamita se usa Fcitx5 (cambia de método con su atajo, por defecto Ctrl + Mayús).")
        OptionRow {
            title: I18n.t("Idioma del sistema")
            Txt { text: page.sysLang || "—"; color: Theme.fgMuted }
        }
        OptionRow {
            title: I18n.t("Métodos de entrada")
            PillButton { text: I18n.t("Configurar Fcitx5…"); implicitHeight: 28; onClicked: Quickshell.execDetached(["fcitx5-configtool"]) }
        }
    }
}
