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
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 8
        Txt { Layout.fillWidth: true; Layout.leftMargin: 4; text: I18n.t("Salida y entrada"); font.weight: Font.Bold }
        Segmented {
            Layout.alignment: Qt.AlignHCenter
            options: [{ v: "output", t: I18n.t("Salida") }, { v: "input", t: I18n.t("Entrada") }]
            value: page.tab
            onPicked: v => page.tab = v
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
        OptionRow {
            visible: page.tab === "output"
            title: I18n.t("Volumen de salida")
            RowLayout {
                spacing: 12
                Slider {
                    implicitWidth: 240
                    from: 0; to: 1; step: 0.01; live: true
                    value: Audio.muted ? 0 : Audio.volume
                    minIcon: "volume_mute"; maxIcon: "volume_up"
                    onMoved: v => Audio.setVolume(v)
                }
                Txt { text: I18n.t("Silencio"); color: Theme.fgMuted }
                Toggle { checked: Audio.muted; onToggled: Audio.toggleMute() }
            }
        }
        OptionRow {
            visible: page.tab === "input"
            title: I18n.t("Volumen de entrada")
            RowLayout {
                spacing: 12
                Slider {
                    implicitWidth: 240
                    from: 0; to: 1; step: 0.01; live: true
                    value: page.micVolume
                    minIcon: "mic_none"; maxIcon: "mic"
                    onMoved: v => { if (Audio.source?.audio) Audio.source.audio.volume = v; }
                }
                Txt { text: I18n.t("Silencio"); color: Theme.fgMuted }
                Toggle { checked: Audio.micMuted; onToggled: Audio.toggleMic() }
            }
        }
    }
}
