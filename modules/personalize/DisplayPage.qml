import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.services
import qs.components

// Pantalla: luz nocturna (temperatura de color) y ajustes de imagen (brillo por software,
// contraste, gamma y saturación). Los aplica quantum-display con la curva de color de la
// tarjeta de video (gratis en rendimiento); la saturación usa un filtro de Wayfire.
ColumnLayout {
    id: page

    spacing: 16
    readonly property var d: Settings.display

    // Color aproximado de una luz de `k` kelvin (para las vistas previas)
    function kelvinColor(k: real): color {
        const t = k / 100;
        const r = t <= 66 ? 1 : Math.min(1, 1.2929 * Math.pow(t - 60, -0.1332));
        const g = t <= 66 ? Math.min(1, Math.max(0, 0.3901 * Math.log(t) - 0.6318)) : Math.min(1, 1.1298 * Math.pow(t - 60, -0.0755));
        const b = t >= 66 ? 1 : t <= 19 ? 0 : Math.min(1, Math.max(0, 0.5432 * Math.log(t - 10) - 1.1962));
        return Qt.rgba(r, g, b, 1);
    }
    function pct(v: real): string { return Math.round(v * 100) + " %"; }

    // Escena de muestra: un paisaje simple con colores puros, para ver cada ajuste
    component Scene: Item {
        id: sc
        property real warm: 0          // 0..1 cuánto tiñe la luz nocturna
        property color tint: "white"
        clip: true
        Item {
            id: art
            anchors.fill: parent
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "#4FD8FF" }
                    GradientStop { position: 0.55; color: "#6A5CFF" }
                    GradientStop { position: 1; color: "#B14DFF" }
                }
            }
            Rectangle { x: parent.width * 0.68; y: parent.height * 0.16; width: parent.height * 0.26; height: width; radius: width / 2; color: "#FFE37A" }
            Rectangle {
                y: parent.height * 0.62; width: parent.width; height: parent.height * 0.38
                gradient: Gradient { GradientStop { position: 0; color: "#2ECC8F" } GradientStop { position: 1; color: "#147A5A" } }
            }
            Row {
                x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 12; spacing: 6
                Repeater { model: ["#FF5C5C", "#FFB547", "#FFE37A", "#4ADE80", "#38BDF8", "#A78BFA", "#FFFFFF", "#000000"]
                    Rectangle { required property string modelData; width: 18; height: 18; radius: 5; color: modelData; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3) } }
            }
        }
        MultiEffect {
            anchors.fill: art; source: art
            brightness: (page.d.brightness - 1) * 0.9
            contrast: (page.d.contrast - 1)
            saturation: page.d.saturation - 1
        }
        // la luz nocturna quita azul: un velo naranja que se nota más mientras más cálida
        Rectangle { anchors.fill: parent; color: Qt.rgba(1, sc.tint.g * 0.62, sc.tint.b * 0.25, 1); opacity: sc.warm * 0.55 }
    }

    // ---------------------------------------------------------------- luz nocturna
    Group {
        title: "Luz nocturna"
        help: "Pone la pantalla más cálida (menos luz azul) para cuidar tu vista de noche y dormir mejor."
        icon: "nightlight"

        // vista previa: de día y con la luz nocturna
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: [{ t: "Normal", w: 0 }, { t: "Con luz nocturna", w: 1 }]
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1          // las dos del mismo ancho
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 120
                        radius: 14; color: "transparent"; clip: true
                        border.width: modelData.w && page.d.nightLight ? 2 : 1
                        border.color: modelData.w && page.d.nightLight ? Theme.primary : Theme.alpha(Theme.fg, 0.1)
                        Scene {
                            anchors.fill: parent; anchors.margins: 1
                            warm: parent.parent.modelData.w * (6500 - page.d.temperature) / 4000
                            tint: page.kelvinColor(page.d.temperature)
                        }
                    }
                    Txt { text: modelData.t; font.pixelSize: Theme.textSmall; color: Theme.fgMuted }
                }
            }
        }

        OptionRow {
            title: "Activar luz nocturna"
            help: page.d.nightMode === "manual" ? "Se queda así hasta que la apagues." : "Se enciende y apaga sola según lo que elijas abajo."
            Toggle { checked: page.d.nightLight; onToggled: v => Settings.set("display", "nightLight", v) }
        }
        OptionRow {
            title: "Cuándo"
            Segmented {
                options: [{ v: "manual", t: "Manual", i: "touch_app" }, { v: "sunset", t: "Al atardecer", i: "wb_twilight" }, { v: "schedule", t: "En un horario", i: "schedule" }]
                value: page.d.nightMode
                onPicked: v => Settings.set("display", "nightMode", v)
            }
        }
        // horario: dos horas que se cambian de a 30 min
        OptionRow {
            visible: page.d.nightMode === "schedule"
            title: "Horario"
            help: "Se enciende a la primera hora y se apaga a la segunda."
            Row {
                spacing: 10
                Repeater {
                    model: [{ k: "nightFrom", t: "Desde" }, { k: "nightTo", t: "Hasta" }]
                    Rectangle {
                        id: tp
                        required property var modelData
                        readonly property string val: page.d[modelData.k]
                        function shift(min) {
                            const p = val.split(":").map(Number);
                            const m = ((p[0] * 60 + p[1] + min) % 1440 + 1440) % 1440;
                            Settings.set("display", modelData.k, String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"));
                        }
                        width: 150; height: 44; radius: 22; color: Theme.surfaceHigh
                        Row {
                            anchors.centerIn: parent; spacing: 4
                            IconButton { icon: "remove"; width: 30; height: 30; iconSize: 18; onClicked: tp.shift(-30) }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Txt { anchors.horizontalCenter: parent.horizontalCenter; text: tp.modelData.t; font.pixelSize: 10; color: Theme.fgMuted }
                                Txt { anchors.horizontalCenter: parent.horizontalCenter; text: tp.val; font.weight: Font.Bold }
                            }
                            IconButton { icon: "add"; width: 30; height: 30; iconSize: 18; onClicked: tp.shift(30) }
                        }
                    }
                }
            }
        }
        OptionRow {
            visible: page.d.nightMode === "sunset"
            title: "Según tu ubicación"
            help: "Usa la misma ubicación que el clima. Se enciende al atardecer y se apaga al amanecer."
            icon: "location_on"
        }
        OptionRow {
            title: "Calidez"
            help: page.d.temperature <= 3200 ? "Muy cálida: ideal para leer de noche." : page.d.temperature <= 4500 ? "Cálida: cómoda y sin cansar la vista." : "Suave: casi no se nota."
            Slider {
                Layout.preferredWidth: 300
                from: 2500; to: 6000; step: 100; live: true
                value: page.d.temperature
                text: value + " K"
                onMoved: v => Settings.set("display", "temperature", Math.round(v))
            }
        }
    }

    // ---------------------------------------------------------------- imagen
    Group {
        title: "Imagen"
        help: "Ajusta cómo se ve la pantalla, ideal en laptops que no traen botones para esto. Funciona en todas tus pantallas."
        icon: "tune"

        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 150
            radius: 14; color: "transparent"; clip: true
            border.width: 1; border.color: Theme.alpha(Theme.fg, 0.1)
            Scene { anchors.fill: parent; anchors.margins: 1 }
            Rectangle {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                width: lbl.implicitWidth + 20; height: 26; radius: 13; color: Qt.rgba(0, 0, 0, 0.45)
                Txt { id: lbl; anchors.centerIn: parent; text: "Vista previa"; color: "white"; font.pixelSize: Theme.textSmall }
            }
        }

        OptionRow {
            title: "Brillo extra"
            help: "Oscurece la imagen por software. Útil en monitores externos sin control de brillo."
            icon: "brightness_medium"
            Slider { Layout.preferredWidth: 300; from: 0.3; to: 1; step: 0.01; live: true; value: page.d.brightness; text: page.pct(value); onMoved: v => Settings.set("display", "brightness", v) }
        }
        OptionRow {
            title: "Contraste"
            icon: "contrast"
            Slider { Layout.preferredWidth: 300; from: 0.5; to: 1.5; step: 0.01; live: true; value: page.d.contrast; text: page.pct(value); onMoved: v => Settings.set("display", "contrast", v) }
        }
        OptionRow {
            title: "Gamma"
            help: "Aclara u oscurece los tonos medios sin tocar el blanco ni el negro."
            icon: "exposure"
            Slider { Layout.preferredWidth: 300; from: 0.5; to: 2; step: 0.05; live: true; value: page.d.gamma; text: value.toFixed(2); onMoved: v => Settings.set("display", "gamma", v) }
        }
        OptionRow {
            title: "Saturación"
            help: page.d.saturation !== 1 ? "Usa un filtro: el Modo juego lo apaga para no perder FPS." : "Qué tan vivos se ven los colores."
            icon: "palette"
            Slider { Layout.preferredWidth: 300; from: 0; to: 2; step: 0.05; live: true; value: page.d.saturation; text: page.pct(value); onMoved: v => Settings.set("display", "saturation", v) }
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            PillButton {
                icon: "restart_alt"; text: "Restablecer imagen"
                onClicked: Settings.setMany({ display: { brightness: 1, contrast: 1, gamma: 1, saturation: 1 } })
            }
        }
    }
}
