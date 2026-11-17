import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Barra de menús como en macOS Tahoe: forma de la barra, «Controles de la barra de
// menús» (qué se muestra) y «Opciones del reloj».
ColumnLayout {
    id: page
    spacing: 16

    readonly property bool single: Settings.layout.style === "single"
    readonly property bool usable: !Serp.on && !single

    Group {
        visible: !page.usable
        OptionRow {
            title: Serp.on ? I18n.t("Serpantium usa su propia barra de arriba.") : I18n.t("Con «Una sola barra» no hay barra de menús.")
            PillButton { text: I18n.t("Escritorio y Dock…"); implicitHeight: 28; onClicked: Shell.settingsGo("desktop") }
        }
    }

    Group {
        visible: page.usable
        OptionRow {
            title: I18n.t("Forma de la barra de menús")
            Segmented {
                options: [{ v: false, t: I18n.t("De borde a borde") }, { v: true, t: I18n.t("Flotante") }]
                value: Settings.layout.topBar.floating
                onPicked: v => Settings.setPath("layout.topBar.floating", v)
            }
        }
    }

    Group {
        visible: page.usable
        title: I18n.t("Controles de la barra de menús")
        help: I18n.t("Elige qué aparece a la derecha de la barra de menús.")
        OptionRow {
            title: I18n.t("App activa"); help: I18n.t("El nombre y el menú de la app que estás usando, a la izquierda.")
            icon: "web_asset"; iconColor: "#8E8E93"
            Toggle { checked: Settings.layout.topBar.showApp; onToggled: c => Settings.setPath("layout.topBar.showApp", c) }
        }
        OptionRow {
            title: "Spotlight"
            icon: "search"; iconColor: "#8E8E93"
            Toggle { checked: Settings.layout.topBar.showSpotlight; onToggled: c => Settings.setPath("layout.topBar.showSpotlight", c) }
        }
        OptionRow {
            title: I18n.t("Monitor del sistema"); help: I18n.t("Temperatura, CPU y RAM en tiempo real.")
            icon: "monitoring"; iconColor: "#34C759"
            Toggle { checked: Settings.layout.topBar.showSysMon; onToggled: c => Settings.setPath("layout.topBar.showSysMon", c) }
        }
        OptionRow {
            title: I18n.t("Uso de Claude Code"); help: I18n.t("Tokens de la ventana de 5 h y de los últimos 7 días.")
            icon: "token"; iconColor: "#D97757"
            Toggle { checked: Settings.layout.topBar.showClaude; onToggled: c => Settings.setPath("layout.topBar.showClaude", c) }
        }
        OptionRow {
            title: I18n.t("Íconos de apps en segundo plano"); help: I18n.t("Discord, Steam, Bluetooth…")
            icon: "more_horiz"; iconColor: "#8E8E93"
            Toggle { checked: Settings.dock.showTray; onToggled: c => Settings.set("dock", "showTray", c) }
        }
    }

    Group {
        title: I18n.t("Opciones del reloj")
        OptionRow {
            title: I18n.t("Mostrar la fecha")
            Choice {
                options: [{ v: true, t: I18n.t("Siempre") }, { v: false, t: I18n.t("Nunca") }]
                value: Settings.clock.showDate
                onPicked: v => Settings.set("clock", "showDate", v)
            }
        }
        OptionRow {
            dim: !Settings.clock.showDate
            title: I18n.t("Mostrar el día de la semana")
            Toggle { checked: Settings.clock.showWeekday; onToggled: c => Settings.set("clock", "showWeekday", c) }
        }
        OptionRow {
            title: I18n.t("Usar el formato de 24 horas")
            Toggle { checked: Settings.clock.format24h; onToggled: c => Settings.set("clock", "format24h", c) }
        }
        OptionRow {
            title: I18n.t("Mostrar los segundos")
            Toggle { checked: Settings.clock.showSeconds; onToggled: c => Settings.set("clock", "showSeconds", c) }
        }
    }
}
