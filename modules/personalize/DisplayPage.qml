import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Pantallas como en Ajustes del Sistema de macOS: cada pantalla con «Texto más grande
// … Más espacio» (escala, con «¿Mantener estos ajustes?» y vuelta atrás en 15 s), brillo,
// Night Shift (horario y calidez) y ajustes de color. Lo aplica HyprApply en Hyprland.
ColumnLayout {
    id: page
    spacing: 22

    readonly property var d: Settings.display
    property var monitors: []
    property string sel: ""
    readonly property var mon: monitors.find(m => m.name === sel) ?? monitors[0] ?? null

    function load(): void { mons.running = true; }
    Component.onCompleted: load()
    Process {
        id: mons
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.monitors = JSON.parse(text);
                    if (!page.monitors.some(m => m.name === page.sel)) page.sel = page.monitors.find(m => m.focused)?.name ?? page.monitors[0]?.name ?? "";
                } catch (e) {}
            }
        }
    }

    // escalas que dan un tamaño entero (Hyprland no acepta otras)
    readonly property var scales: {
        if (!mon) return [];
        const w = mon.width, h = mon.height;
        return [2, 1.75, 1.6, 1.5, 1.25, 1].filter(s => Number.isInteger(w / s) && Number.isInteger(h / s));
    }

    // ---------------------------------------- confirmar la escala (como macOS)
    property real prevScale: 0
    property real newScale: 0
    property int countdown: 0
    function tryScale(s: real): void {
        if (!mon || s === mon.scale) return;
        prevScale = mon.scale;
        newScale = s;
        HyprApply.applyScale(mon.name, s);
        countdown = 15;
        tick.restart();
        reloadT.restart();
    }
    function keep(): void {
        tick.stop();
        countdown = 0;
        const sc = Object.assign({}, d.scales ?? {});
        sc[mon.name] = newScale;
        Settings.set("display", "scales", sc);
    }
    function revert(): void {
        tick.stop();
        countdown = 0;
        HyprApply.applyScale(mon.name, prevScale);
        reloadT.restart();
    }
    Timer { id: tick; interval: 1000; repeat: true; onTriggered: { page.countdown--; if (page.countdown <= 0) page.revert(); } }
    Timer { id: reloadT; interval: 700; onTriggered: page.load() }

    // ----------------------------------------------------------- pantallas
    // Cada pantalla como miniatura con su nombre debajo; la elegida va en negrita (como macOS)
    Row {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        spacing: 28
        Repeater {
            model: page.monitors
            Column {
                id: mt
                required property var modelData
                readonly property bool on: page.mon && page.mon.name === modelData.name
                readonly property real w: Math.max(90, Math.min(140, Math.round(modelData.width / 14)))
                spacing: 8
                Item {
                    width: mt.w; height: 96
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: mt.w; height: Math.round(mt.w * mt.modelData.height / mt.modelData.width)
                        radius: 5
                        color: "#1c1c1e"
                        border.width: mt.on ? 2 : 0
                        border.color: Theme.primary
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 3; radius: 3
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#64a8ff" }
                                GradientStop { position: 1; color: "#7b5cff" }
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.sel = mt.modelData.name }
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mt.modelData.description ? mt.modelData.description.split(" ").slice(0, 2).join(" ") : mt.modelData.name
                    font.weight: mt.on ? Font.Bold : Font.Normal
                }
            }
        }
    }

    // aviso «¿Mantener estos ajustes?»
    Group {
        visible: page.countdown > 0
        OptionRow {
            title: I18n.t("¿Mantener estos ajustes de pantalla?")
            help: I18n.t("Se vuelve a la escala anterior en") + " " + page.countdown + " s."
            icon: "help"; iconColor: "#FF9500"
            RowLayout {
                spacing: 8
                PillButton { text: I18n.t("Volver"); implicitHeight: 28; onClicked: page.revert() }
                PillButton { text: I18n.t("Mantener"); primary: true; implicitHeight: 28; onClicked: page.keep() }
            }
        }
    }

    // resoluciones (escalas) como lista; la elegida resaltada en gris
    Group {
        visible: page.scales.length > 1
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            spacing: 0
            Repeater {
                model: page.scales.slice().reverse()
                Rectangle {
                    id: rs
                    required property real modelData
                    readonly property bool on: page.mon && Math.abs(page.mon.scale - modelData) < 0.01
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 6
                    color: on ? Theme.alpha(Theme.fg, 0.1) : "transparent"
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        text: page.mon ? Math.round(page.mon.width / rs.modelData) + " × " + Math.round(page.mon.height / rs.modelData) + (rs.modelData === 1 ? " (" + I18n.t("Nativa") + ")" : "") : ""
                        font.weight: rs.on ? Font.DemiBold : Font.Normal
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.tryScale(rs.modelData) }
                }
            }
        }
    }

    Group {
        OptionRow {
            visible: Brightness.available
            title: I18n.t("Brillo")
            Slider {
                implicitWidth: 260
                from: 0.05; to: 1; step: 0.01; live: true
                value: Brightness.value
                minIcon: "brightness_low"; maxIcon: "brightness_high"
                onMoved: v => Brightness.set(v)
            }
        }
        OptionRow {
            title: I18n.t("Frecuencia de actualización")
            Txt { text: page.mon ? Math.round(page.mon.refreshRate) + " Hz" : "—"; color: Theme.fgMuted }
        }
    }

    // ------------------------------------------------------------ Night Shift
    Group {
        title: "Night Shift"
        help: I18n.t("Night Shift pone los colores de la pantalla más cálidos por la noche. Puede ayudarte a dormir mejor.")
        OptionRow {
            title: I18n.t("Programar")
            Choice {
                options: [{ v: "off", t: I18n.t("Desactivado") }, { v: "schedule", t: I18n.t("Personalizado") }]
                value: page.d.nightLight && page.d.nightMode === "schedule" ? "schedule" : "off"
                onPicked: v => Settings.setMany({ display: v === "schedule" ? { nightLight: true, nightMode: "schedule" } : { nightLight: false, nightMode: "manual" } })
            }
        }
        OptionRow {
            visible: page.d.nightLight && page.d.nightMode === "schedule"
            title: I18n.t("Desde")
            RowLayout {
                spacing: 8
                Choice {
                    options: ["18:00", "19:00", "20:00", "21:00", "22:00", "23:00"].map(t => ({ v: t, t: t }))
                    value: page.d.nightFrom
                    onPicked: v => Settings.set("display", "nightFrom", v)
                }
                Txt { text: I18n.t("hasta"); color: Theme.fgMuted }
                Choice {
                    options: ["05:00", "06:00", "07:00", "08:00", "09:00"].map(t => ({ v: t, t: t }))
                    value: page.d.nightTo
                    onPicked: v => Settings.set("display", "nightTo", v)
                }
            }
        }
        OptionRow {
            visible: !(page.d.nightLight && page.d.nightMode === "schedule")
            title: I18n.t("Activar ahora")
            help: I18n.t("Se queda encendido hasta que lo apagues.")
            Toggle { checked: page.d.nightLight; onToggled: c => Settings.setMany({ display: { nightLight: c, nightMode: "manual" } }) }
        }
        OptionRow {
            title: I18n.t("Temperatura del color")
            help: HyprApply.nightNow ? I18n.t("Night Shift está encendido ahora.") : ""
            Slider {
                implicitWidth: 260
                from: 0; to: 1; step: 0.02
                value: (6000 - page.d.temperature) / 3300
                minText: I18n.t("Menos cálido"); maxText: I18n.t("Más cálido")
                onMoved: v => Settings.set("display", "temperature", Math.round(6000 - v * 3300))
            }
        }
    }

    // ------------------------------------------------------------ color
    Group {
        title: I18n.t("Ajustes de color")
        help: I18n.t("Corrigen la imagen por software, útil en monitores sin botones. Se aplican a todas las pantallas.")
        OptionRow {
            title: I18n.t("Atenuar por software")
            Slider { implicitWidth: 240; from: 0.3; to: 1; step: 0.01; value: page.d.brightness; text: Math.round(_shown * 100) + "%"; onMoved: v => Settings.set("display", "brightness", v) }
        }
        OptionRow {
            title: I18n.t("Contraste")
            Slider { implicitWidth: 240; from: 0.5; to: 1.5; step: 0.01; value: page.d.contrast; text: Math.round(_shown * 100) + "%"; onMoved: v => Settings.set("display", "contrast", v) }
        }
        OptionRow {
            title: "Gamma"
            Slider { implicitWidth: 240; from: 0.5; to: 2; step: 0.01; value: page.d.gamma; text: _shown.toFixed(2); onMoved: v => Settings.set("display", "gamma", v) }
        }
        OptionRow {
            title: I18n.t("Saturación")
            Slider { implicitWidth: 240; from: 0; to: 2; step: 0.01; value: page.d.saturation; text: Math.round(_shown * 100) + "%"; onMoved: v => Settings.set("display", "saturation", v) }
        }
        OptionRow {
            visible: !HyprApply.imageNeutral
            title: ""
            PillButton {
                text: I18n.t("Restablecer")
                implicitHeight: 28
                onClicked: Settings.setMany({ display: { brightness: 1, contrast: 1, gamma: 1, saturation: 1 } })
            }
        }
    }
}
