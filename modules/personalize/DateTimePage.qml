import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// General → Fecha y hora (como en macOS): hora automática (NTP), zona horaria y
// formato de 24 horas. Los cambios del sistema piden la contraseña (polkit).
ColumnLayout {
    id: page
    spacing: 16

    property string tz: ""
    property bool ntp: true
    property bool synced: false
    property var zones: []

    function read(): void { show.running = true; }
    Component.onCompleted: { read(); list.running = true; }

    Process {
        id: show
        command: ["timedatectl", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=");
                    if (i < 0) continue;
                    const k = l.slice(0, i), v = l.slice(i + 1);
                    if (k === "Timezone") page.tz = v;
                    else if (k === "NTP") page.ntp = v === "yes";
                    else if (k === "NTPSynchronized") page.synced = v === "yes";
                }
            }
        }
    }
    Process {
        id: list
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: page.zones = text.split("\n").filter(z => z !== "").map(z => ({ v: z, t: z.replace(/_/g, " ") })) }
    }
    Process { id: setter; onExited: page.read() }
    function set(args: var): void { setter.command = ["timedatectl"].concat(args); setter.running = true; }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    Group {
        OptionRow {
            title: I18n.t("Ajustar fecha y hora automáticamente")
            help: page.ntp ? (page.synced ? I18n.t("Sincronizada por internet.") : I18n.t("Esperando la sincronización…")) : ""
            Toggle { checked: page.ntp; onToggled: c => page.set(["set-ntp", c ? "true" : "false"]) }
        }
        OptionRow {
            title: I18n.t("Fecha y hora")
            Txt {
                text: clock.date.toLocaleDateString(I18n.locale, I18n.longDate) + "   " + Qt.formatTime(clock.date, Settings.clock.format24h ? "HH:mm:ss" : "h:mm:ss AP")
                color: Theme.fgMuted
            }
        }
    }

    Group {
        OptionRow {
            title: I18n.t("Zona horaria")
            Choice {
                options: page.zones
                value: page.tz
                placeholder: page.tz || "—"
                onPicked: v => page.set(["set-timezone", v])
            }
        }
        OptionRow {
            title: I18n.t("Formato de 24 horas")
            Toggle { checked: Settings.clock.format24h; onToggled: c => Settings.set("clock", "format24h", c) }
        }
        NavRow {
            title: I18n.t("Reloj de la barra de menús")
            onClicked: Shell.settingsGo("menubar")
        }
    }
}
