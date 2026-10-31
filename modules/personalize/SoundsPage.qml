import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Sonidos del sistema: activar, volumen y escuchar cada uno.
ColumnLayout {
    id: page

    spacing: 16

    // Estilos de sonidos: tocar uno lo elige y lo hace sonar; el botón ▶ solo lo escucha
    Group {
        title: "Estilo de sonidos"
        help: "Siete estilos hechos para Quantum. Toca ▶ para escuchar cada uno."
        icon: "library_music"
        GridLayout {
            Layout.fillWidth: true
            columns: page.width > 760 ? 4 : 2
            columnSpacing: 12; rowSpacing: 12
            Repeater {
                model: Sounds.packs
                Rectangle {
                    id: sp
                    required property var modelData
                    readonly property bool on: Settings.sounds.pack === modelData.id
                    readonly property bool playing: Sounds.previewing === modelData.id
                    Layout.fillWidth: true
                    implicitHeight: 72
                    radius: Theme.radius
                    color: on ? Theme.alpha(Theme.primary, 0.16) : spa.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
                    border.width: on ? 2 : 0; border.color: Theme.primary
                    MouseArea {
                        id: spa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { Settings.setMany({ sounds: { enabled: true, pack: sp.modelData.id } }); if (!sp.playing) Sounds.preview(sp.modelData.id); }
                    }
                    Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; text: sp.modelData.icon; size: 22; fill: 1; color: Theme.primary }
                    Txt { x: 46; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 100; text: sp.modelData.name; font.weight: Font.DemiBold }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40; radius: 20
                        color: sp.playing ? Theme.primary : pa.containsMouse ? Theme.alpha(Theme.fg, 0.12) : Theme.alpha(Theme.fg, 0.06)
                        Icon { anchors.centerIn: parent; text: sp.playing ? "stop" : "play_arrow"; size: 22; fill: 1; color: sp.playing ? Theme.primaryFg : Theme.fg }
                        MouseArea { id: pa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Sounds.preview(sp.modelData.id) }
                    }
                }
            }
        }
    }

    Group {
        title: "Sonidos del sistema"
        help: "Sonidos suaves creados para Quantum: al iniciar sesión, cambiar el volumen, tocar la barra rápida y más."
        icon: "music_note"
        OptionRow {
            title: "Activar sonidos"
            Toggle { checked: Settings.sounds.enabled; onToggled: c => Settings.set("sounds", "enabled", c) }
        }
        OptionRow {
            title: "Volumen de los sonidos"
            help: "Independiente del volumen de tu música y tus juegos."
            enabled: Settings.sounds.enabled
            opacity: enabled ? 1 : 0.5
            Slider {
                implicitWidth: 240
                from: 0.1; to: 1; step: 0.05
                value: Settings.sounds.volume
                text: Math.round(_shown * 100) + " %"
                onMoved: v => { Settings.set("sounds", "volume", v); Sounds.play("volume"); }
            }
        }
        OptionRow {
            title: "Sonido al iniciar sesión"
            enabled: Settings.sounds.enabled
            opacity: enabled ? 1 : 0.5
            Toggle { checked: Settings.sounds.startup; onToggled: c => Settings.set("sounds", "startup", c) }
        }
    }

    Group {
        title: "Escúchalos"
        icon: "graphic_eq"
        Flow {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: [
                    { s: "startup", t: "Inicio", i: "power_settings_new" },
                    { s: "volume", t: "Volumen", i: "volume_up" },
                    { s: "toggle-on", t: "Activar", i: "toggle_on" },
                    { s: "toggle-off", t: "Desactivar", i: "toggle_off" },
                    { s: "notification", t: "Notificación", i: "notifications" },
                    { s: "lock", t: "Bloquear", i: "lock" },
                    { s: "unlock", t: "Desbloquear", i: "lock_open" },
                    { s: "error", t: "Error", i: "error" },
                    { s: "screenshot", t: "Captura", i: "screenshot_region" },
                ]
                PillButton {
                    required property var modelData
                    text: modelData.t
                    icon: modelData.i
                    enabled_: Settings.sounds.enabled
                    onClicked: Sounds.play(modelData.s)
                }
            }
        }
    }
}
