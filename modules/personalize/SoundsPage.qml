import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services
import qs.components

// Sonido como en Ajustes del Sistema de macOS: «Efectos de sonido» (sonido de alerta,
// volumen de alertas, al iniciar, efectos de la interfaz, al cambiar el volumen) y
// «Salida y entrada» con pestañas, la lista de dispositivos y su volumen.
ColumnLayout {
    id: page
    spacing: 16

    // dispositivos de audio de verdad (no las apps que suenan)
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var inputs: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    property string tab: "output"
    readonly property real micVolume: Audio.source?.audio?.volume ?? 0

    Group {
        title: I18n.t("Efectos de sonido")
        OptionRow {
            title: I18n.t("Sonido de alerta")
            RowLayout {
                spacing: 6
                IconButton {
                    icon: Sounds.previewing === Settings.sounds.pack ? "stop" : "play_arrow"
                    iconSize: 18; implicitWidth: 28; implicitHeight: 28
                    onClicked: Sounds.preview(Settings.sounds.pack)
                }
                Choice {
                    options: Sounds.packs.map(p => ({ v: p.id, t: p.name }))
                    value: Settings.sounds.pack
                    onPicked: v => { Settings.setMany({ sounds: { enabled: true, pack: v } }); Sounds.preview(v); }
                }
            }
        }
        OptionRow {
            title: I18n.t("Volumen de alertas")
            Slider {
                implicitWidth: 240
                from: 0; to: 1; step: 0.02
                value: Settings.sounds.volume
                minIcon: "volume_mute"; maxIcon: "volume_up"
                onMoved: v => { Settings.set("sounds", "volume", v); Sounds.play("click"); }
            }
        }
        OptionRow {
            title: I18n.t("Reproducir sonido al iniciar sesión")
            Toggle { checked: Settings.sounds.startup; onToggled: c => Settings.set("sounds", "startup", c) }
        }
        OptionRow {
            title: I18n.t("Reproducir efectos de sonido de la interfaz")
            help: I18n.t("Notificaciones, bloqueo, errores y clics de la barra rápida.")
            Toggle { checked: Settings.sounds.enabled; onToggled: c => Settings.set("sounds", "enabled", c) }
        }
        OptionRow {
            title: I18n.t("Sonar al cambiar el volumen")
            Toggle { checked: Settings.sounds.volumeFeedback; onToggled: c => Settings.set("sounds", "volumeFeedback", c) }
        }
    }

    // ---------------------------------------------------- salida y entrada
    Txt { Layout.fillWidth: true; Layout.topMargin: 8; Layout.bottomMargin: -10; Layout.leftMargin: 4; text: I18n.t("Salida y entrada"); font.weight: Font.Bold }

    // pestañas a todo el ancho: la elegida en una pastilla blanca (como macOS)
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 7
        color: Theme.alpha(Theme.fg, Theme.dark ? 0.1 : 0.07)
        Row {
            anchors.fill: parent
            anchors.margins: 2
            Repeater {
                model: [{ v: "output", t: I18n.t("Salida") }, { v: "input", t: I18n.t("Entrada") }]
                Rectangle {
                    id: tb
                    required property var modelData
                    readonly property bool on: page.tab === modelData.v
                    width: parent.width / 2; height: parent.height
                    radius: 5
                    color: on ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : "white") : "transparent"
                    border.width: on && !Theme.dark ? 1 : 0
                    border.color: Qt.rgba(0, 0, 0, 0.06)
                    Txt { anchors.centerIn: parent; text: tb.modelData.t; font.weight: tb.on ? Font.DemiBold : Font.Normal }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.tab = tb.modelData.v }
                }
            }
        }
    }

    Group {
        Layout.topMargin: 0
        DeviceList {
            nodes: page.tab === "output" ? page.outputs : page.inputs
            current: page.tab === "output" ? Audio.sink : Audio.source
            onChosen: n => { if (page.tab === "output") Pipewire.preferredDefaultAudioSink = n; else Pipewire.preferredDefaultAudioSource = n; }
        }
    }

    Group {
        Layout.topMargin: 0
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Txt { Layout.fillWidth: true; text: page.tab === "output" ? I18n.t("Volumen de salida") : I18n.t("Volumen de entrada") }
                Slider {
                    visible: page.tab === "output"
                    implicitWidth: 260
                    from: 0; to: 1; step: 0.01; live: true
                    value: Audio.muted ? 0 : Audio.volume
                    minIcon: "volume_mute"; maxIcon: "volume_up"
                    onMoved: v => Audio.setVolume(v)
                }
                Slider {
                    visible: page.tab === "input"
                    implicitWidth: 260
                    from: 0; to: 1; step: 0.01; live: true
                    value: page.micVolume
                    minIcon: "mic_none"; maxIcon: "mic"
                    onMoved: v => { if (Audio.source?.audio) Audio.source.audio.volume = v; }
                }
            }
            // casilla «Silencio» debajo, a la derecha
            RowLayout {
                id: mute
                Layout.alignment: Qt.AlignRight
                readonly property bool on: page.tab === "output" ? Audio.muted : Audio.micMuted
                spacing: 6
                Rectangle {
                    implicitWidth: 16; implicitHeight: 16; radius: 4
                    color: mute.on ? Theme.accent : "transparent"
                    border.width: 1; border.color: mute.on ? Theme.accent : Theme.alpha(Theme.fg, 0.35)
                    Icon { anchors.centerIn: parent; visible: mute.on; text: "check"; size: 12; color: "white" }
                }
                Txt { text: I18n.t("Silencio") }
                TapHandler { onTapped: page.tab === "output" ? Audio.toggleMute() : Audio.toggleMic() }
            }
        }
    }
}
