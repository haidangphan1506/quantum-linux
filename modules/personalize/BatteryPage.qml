import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services
import qs.components

// Batería como en Ajustes del Sistema de macOS: nivel de las últimas 24 horas,
// «Modo de bajo consumo», modo de energía, salud de la batería y carga optimizada.
ColumnLayout {
    id: page
    spacing: 16

    readonly property var bat: UPower.displayDevice
    readonly property bool present: bat?.isLaptopBattery ?? false
    readonly property real pct: (bat?.percentage ?? 0) > 1 ? bat.percentage / 100 : (bat?.percentage ?? 0)
    readonly property bool charging: bat?.state === UPowerDeviceState.Charging
    readonly property bool full: bat?.state === UPowerDeviceState.FullyCharged

    property var history: []          // [{ t: segundos, v: 0..100, s: estado }]
    property var sys: ({})            // ciclos, capacidad de diseño y carga limitada (sysfs)

    function hm(sec: real): string {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    Component.onCompleted: { hist.running = true; sysProc.running = true; }
    Timer { interval: 120000; running: true; repeat: true; onTriggered: hist.running = true }

    Process {
        id: hist
        command: ["busctl", "--json=short", "call", "org.freedesktop.UPower", "/org/freedesktop/UPower/devices/battery_BAT0",
                  "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", "86400", "200"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const rows = JSON.parse(text).data[0];
                    page.history = rows.filter(r => r[1] > 0).map(r => ({ t: r[0], v: r[1], s: r[2] })).sort((a, b) => a.t - b.t);
                } catch (e) {}
            }
        }
    }
    Process {
        id: sysProc
        command: ["sh", "-c", `b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
echo "cycles=$(cat $b/cycle_count 2>/dev/null)"
echo "full=$(cat $b/energy_full 2>/dev/null || cat $b/charge_full 2>/dev/null)"
echo "design=$(cat $b/energy_full_design 2>/dev/null || cat $b/charge_full_design 2>/dev/null)"
c=$(ls /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode 2>/dev/null | head -1)
[ -n "$c" ] && echo "conservation=$(cat $c)" && echo "conservationPath=$c"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1).trim(); }
                page.sys = o;
            }
        }
    }
    Process { id: consProc; onExited: sysProc.running = true }

    // nivel por hora (24 barras): el último valor conocido de cada hora
    readonly property var hours: {
        const now = Date.now() / 1000;
        const out = [];
        let j = 0, last = null;
        for (let h = 23; h >= 0; h--) {
            const end = now - h * 3600;
            while (j < history.length && history[j].t <= end) { last = history[j]; j++; }
            out.push(last ? { v: last.v, c: last.s === 1 } : null);
        }
        return out;
    }

    Group {
        visible: !page.present
        OptionRow { title: I18n.t("Este equipo no tiene batería."); icon: "power"; iconColor: "#34C759" }
    }

    // ------------------------------------------------------------ estado
    Group {
        visible: page.present
        OptionRow {
            title: Math.round(page.pct * 100) + "%"
            help: page.full ? I18n.t("Cargada por completo")
                : page.charging ? I18n.t("Cargando") + (page.bat.timeToFull > 0 ? " · " + page.hm(page.bat.timeToFull) + " " + I18n.t("para cargarse") : "")
                : !UPower.onBattery ? I18n.t("Conectada, sin cargar")
                : I18n.t("Con batería") + (page.bat.timeToEmpty > 0 ? " · " + page.hm(page.bat.timeToEmpty) + " " + I18n.t("restantes") : "")
            icon: page.charging ? "battery_charging_full" : "battery_full"
            iconColor: page.pct < 0.2 && !page.charging ? "#FF3B30" : "#34C759"
            Txt { visible: (page.bat?.changeRate ?? 0) !== 0; text: Math.abs(page.bat.changeRate).toFixed(1) + " W"; color: Theme.fgMuted }
        }
    }

    // ------------------------------------------------------------ salud
    Group {
        visible: page.present
        help: I18n.t("La capacidad máxima mide cuánta carga aguanta la batería comparada con cuando era nueva.")
        OptionRow {
            id: healthRow
            readonly property real health: page.bat?.healthSupported && page.bat.healthPercentage > 0 ? page.bat.healthPercentage
                : Number(page.sys.design) > 0 ? Math.min(100, 100 * Number(page.sys.full) / Number(page.sys.design)) : 0
            title: I18n.t("Salud de la batería")
            help: health > 0 ? I18n.t("Capacidad máxima") + ": " + Math.round(health) + "%" : ""
            Txt { text: healthRow.health === 0 ? "—" : healthRow.health >= 80 ? I18n.t("Normal") : I18n.t("Servicio recomendado"); color: Theme.fgMuted }
        }
    }

    // ------------------------------------------------------------ energía
    Group {
        title: I18n.t("Modo de energía")
        help: I18n.t("Con el modo de bajo consumo el equipo gasta menos energía: la batería dura más y el ventilador hace menos ruido.")
        OptionRow {
            title: I18n.t("Modo de bajo consumo")
            Choice {
                options: [{ v: "never", t: I18n.t("Nunca") }, { v: "always", t: I18n.t("Siempre") },
                          { v: "battery", t: I18n.t("Solo con batería") }, { v: "adapter", t: I18n.t("Solo con el adaptador") }]
                value: Settings.power.lowPower
                onPicked: v => Settings.set("power", "lowPower", v)
            }
        }
        OptionRow {
            title: I18n.t("Modo de energía")
            help: HyprApply.lowActive ? I18n.t("Ahora manda el modo de bajo consumo.") : ""
            Segmented {
                options: [{ v: PowerProfile.PowerSaver, t: I18n.t("Ahorro") }, { v: PowerProfile.Balanced, t: I18n.t("Equilibrado") }]
                    .concat(PowerProfiles.hasPerformanceProfile ? [{ v: PowerProfile.Performance, t: I18n.t("Rendimiento") }] : [])
                value: PowerProfiles.profile
                onPicked: v => PowerProfiles.profile = v
            }
        }
    }

    // ------------------------------------------------------------ gráfico
    Group {
        visible: page.present
        // gráfico de las últimas 24 horas
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 12
            spacing: 6
            Txt { text: I18n.t("Nivel de batería · últimas 24 horas"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
            Item {
                Layout.fillWidth: true
                implicitHeight: 110
                // líneas guía de 0, 50 y 100 %
                Repeater {
                    model: [0, 50, 100]
                    Item {
                        required property int modelData
                        width: parent.width
                        y: (1 - modelData / 100) * 100
                        Rectangle { width: parent.width - 36; height: 1; color: Theme.alpha(Theme.fg, 0.1) }
                        Txt { x: parent.width - 30; y: -7; text: modelData + "%"; font.pixelSize: Theme.textSmall - 2; color: Theme.fgMuted }
                    }
                }
                Row {
                    width: parent.width - 36
                    height: 100
                    spacing: 3
                    Repeater {
                        model: page.hours
                        Item {
                            required property var modelData
                            width: (parent.width - 23 * 3) / 24
                            height: 100
                            Rectangle {
                                visible: !!modelData
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(2, (modelData?.v ?? 0))
                                radius: 2
                                color: modelData?.c ? "#30D158" : "#34C759"
                                opacity: modelData?.c ? 0.6 : 1
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 36
                Txt { text: I18n.t("Hace 24 h"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall - 1; Layout.fillWidth: true }
                Txt { text: I18n.t("Ahora"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall - 1 }
            }
        }
    }

    // ------------------------------------------------------------ salud
    Group {
        visible: page.present && (!!page.sys.cycles || !!page.sys.conservationPath)
        OptionRow {
            visible: !!page.sys.cycles
            title: I18n.t("Ciclos de carga")
            Txt { text: page.sys.cycles ?? ""; color: Theme.fgMuted }
        }
        OptionRow {
            visible: !!page.sys.conservationPath
            title: I18n.t("Carga optimizada")
            help: I18n.t("Deja de cargar antes del 100 % para que la batería envejezca más despacio (modo conservación de Lenovo). Pide tu contraseña.")
            Toggle {
                checked: page.sys.conservation === "1"
                onToggled: c => {
                    consProc.command = ["pkexec", "sh", "-c", "echo " + (c ? 1 : 0) + " > '" + page.sys.conservationPath + "'"];
                    consProc.running = true;
                }
            }
        }
    }
}
