import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.services
import qs.components
import "../notifications"

// Centro de control estilo macOS: módulos de vidrio sueltos (sin marco común) en una
// rejilla de 4 columnas — Wi-Fi, Bluetooth, música, Concentración, pantalla, sonido y
// accesos rápidos. Las páginas de Wi-Fi y Bluetooth siguen dentro de un panel de vidrio.
PanelWindow {
    id: win

    readonly property bool open: Shell.controlCenterOpen
    property real progress: 0
    visible: open || progress > 0.001
    onOpenChanged: {
        anim.to = open ? 1 : 0;
        anim.duration = open ? 380 : 180;
        anim.easing.type = open ? Easing.OutBack : Easing.InCubic;
        anim.restart();
    }
    NumberAnimation { id: anim; target: win; property: "progress"; easing.overshoot: 1.1 }
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-panel"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    // Ocupa toda la pantalla (transparente) para cerrarse al hacer clic fuera del panel
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    MouseArea {
        anchors.fill: parent
        enabled: win.open
        onClicked: Shell.controlCenterOpen = false
    }

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property bool wifiPage: Shell.wifiPage
    readonly property bool btPage: Shell.btPage
    readonly property bool subPage: wifiPage || btPage
    readonly property real contentHeight: wifiPage ? wifiPageLayout.implicitHeight : btPage ? btPageLayout.implicitHeight : grid.implicitHeight

    // Medidas de la rejilla: celda cuadrada y separación
    readonly property int cell: 76
    readonly property int gap: 12
    readonly property int wide: cell * 2 + gap          // módulo de 2 columnas
    readonly property int full: cell * 4 + gap * 3     // ancho total

    // Colores: módulo de vidrio y botón activado (blanco con icono de acento, como macOS)
    readonly property color modBg: Theme.glassPanel
    readonly property color modBorder: Theme.glassBorder
    readonly property color onBg: Qt.rgba(1, 1, 1, 0.94)
    readonly property color onFg: "#007aff"

    // ---------------------------------------------------------------- contenido
    Item {
        id: panel
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 10
        width: win.subPage ? 400 : win.full
        height: Math.min(win.contentHeight + (win.subPage ? 36 : 0), parent.height - 16)
        focus: true

        MouseArea { anchors.fill: parent }  // los clics dentro no cierran el panel
        Keys.onEscapePressed: {
            if (win.wifiPage)
                Shell.wifiPage = false;
            else if (win.btPage)
                Shell.btPage = false;
            else
                Shell.controlCenterOpen = false;
        }

        opacity: Math.min(1, win.progress * 1.4)
        scale: 0.95 + 0.05 * win.progress
        transformOrigin: Item.TopRight
        transform: Translate { x: (1 - win.progress) * 40 }

        // fondo de vidrio solo para las páginas de Wi-Fi / Bluetooth
        Card {
            anchors.fill: parent
            visible: win.subPage
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: win.subPage ? 18 : 0
            contentHeight: win.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // ------------------------------------------------ página principal
            ColumnLayout {
                id: grid
                width: win.full
                visible: !win.subPage
                spacing: win.gap

                // Filas 1-2: Wi-Fi + Bluetooth / Luz nocturna  |  Música
                RowLayout {
                    spacing: win.gap
                    ColumnLayout {
                        spacing: win.gap
                        CcPill {
                            icon: Net.icon
                            title: "Wi-Fi"
                            subtitle: Net.label
                            on: Net.wifiEnabled
                            onIconClicked: Net.toggleWifi()
                            onClicked: Shell.openWifi()
                        }
                        RowLayout {
                            spacing: win.gap
                            CcCircle {
                                icon: Bt.icon
                                on: Bt.enabled
                                onClicked: Bt.toggle()
                                onRightClicked: Shell.openBluetooth()
                            }
                            CcCircle {
                                icon: "nightlight"
                                on: Settings.display.nightLight
                                onClicked: Shell.toggleNightLight()
                                onRightClicked: Shell.personalizePage("display")
                            }
                        }
                    }
                    // Música
                    CcModule {
                        implicitWidth: win.wide
                        implicitHeight: win.wide
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 2
                            Rectangle {
                                implicitWidth: 52
                                implicitHeight: 52
                                radius: 12
                                color: Theme.glassTile
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: win.player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !(win.player?.trackArtUrl)
                                    text: "music_note"
                                    color: Theme.fgMuted
                                }
                            }
                            Item { Layout.fillHeight: true }
                            Txt {
                                Layout.fillWidth: true
                                text: win.player ? (win.player.trackTitle || I18n.t("Sin título")) : I18n.t("Sin reproducción")
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Txt {
                                Layout.fillWidth: true
                                visible: win.player !== null
                                text: win.player?.trackArtist || win.player?.identity || ""
                                color: Theme.fgMuted
                                font.pixelSize: Theme.textSmall
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                opacity: win.player ? 1 : 0.4
                                Repeater {
                                    model: [
                                        { i: "fast_rewind", f: () => win.player?.previous() },
                                        { i: win.player?.isPlaying ? "pause" : "play_arrow", f: () => win.player?.togglePlaying() },
                                        { i: "fast_forward", f: () => win.player?.next() }
                                    ]
                                    Icon {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: modelData.i
                                        size: 28
                                        fill: 1
                                        color: Theme.fg
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: win.player !== null
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: parent.modelData.f()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Fila 3: Concentración (No molestar) + modo juego + mosaico
                RowLayout {
                    spacing: win.gap
                    CcPill {
                        icon: Settings.notifications.dnd ? "do_not_disturb_on" : "dark_mode"
                        title: I18n.t("Concentración")
                        subtitle: Settings.notifications.dnd ? I18n.t("Activado") : ""
                        on: Settings.notifications.dnd
                        onIconClicked: Settings.set("notifications", "dnd", !Settings.notifications.dnd)
                        onClicked: Settings.set("notifications", "dnd", !Settings.notifications.dnd)
                    }
                    CcCircle {
                        icon: "sports_esports"
                        on: Shell.gameMode
                        onClicked: Shell.setGameMode(!Shell.gameMode)
                    }
                    CcCircle {
                        icon: "grid_view"
                        on: Settings.windows.tiling
                        onClicked: Settings.set("windows", "tiling", !Settings.windows.tiling)
                    }
                }

                // Pantalla
                CcSliderModule {
                    visible: Brightness.available
                    title: I18n.t("Pantalla")
                    leftIcon: "light_mode"
                    rightIcon: "brightness_high"
                    value: Brightness.value
                    onMoved: v => Brightness.set(v)
                }

                // Sonido
                CcSliderModule {
                    title: I18n.t("Volumen")
                    leftIcon: Audio.muted ? "volume_off" : "volume_down"
                    rightIcon: "volume_up"
                    value: Audio.muted ? 0 : Audio.volume
                    onMoved: v => Audio.setVolume(v)
                    onLeftClicked: Audio.toggleMute()
                }

                // Fila de accesos: modo oscuro, energía, ajustes, apagar
                RowLayout {
                    spacing: win.gap
                    CcCircle {
                        icon: "contrast"
                        on: Theme.dark
                        onClicked: Settings.set("appearance", "mode", Theme.dark ? "light" : "dark")
                        onRightClicked: Shell.personalizePage("appearance")
                    }
                    CcCircle {
                        id: power
                        readonly property var profiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                        readonly property int current: profiles.indexOf(PowerProfiles.profile)
                        icon: current < 0 ? "battery_unknown" : ["eco", "balance", "bolt"][current]
                        on: PowerProfiles.profile === PowerProfile.Performance
                        opacity: current < 0 ? 0.5 : 1
                        onClicked: {
                            let next = (current + 1) % 3;
                            if (profiles[next] === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile)
                                next = 0;
                            PowerProfiles.profile = profiles[next];
                        }
                    }
                    CcCircle {
                        icon: "settings"
                        onClicked: { Shell.closeAll(); Shell.personalize(); }
                    }
                    CcCircle {
                        icon: "power_settings_new"
                        onClicked: Shell.toggleSession()
                    }
                }

                // Notificaciones: solo si hay alguna, en su propio módulo
                CcModule {
                    Layout.fillWidth: true
                    visible: Notifs.count > 0
                    implicitHeight: notifCol.implicitHeight + 28
                    ColumnLayout {
                        id: notifCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Txt { Layout.fillWidth: true; text: I18n.t("Notificaciones"); font.weight: Font.DemiBold }
                            Txt {
                                text: I18n.t("Borrar todo")
                                color: Theme.primary
                                font.weight: Font.DemiBold
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Notifs.clearAll()
                                }
                            }
                        }
                        Repeater {
                            model: Notifs.list
                            NotifCard {
                                required property var modelData
                                Layout.fillWidth: true
                                notif: modelData
                            }
                        }
                    }
                }
            }

            // Página de redes Wi-Fi
            ColumnLayout {
                id: wifiPageLayout
                width: flick.width
                visible: win.wifiPage
                spacing: 14

                WifiView {}
            }

            // Página de dispositivos Bluetooth
            ColumnLayout {
                id: btPageLayout
                width: flick.width
                visible: win.btPage
                spacing: 14

                BtView {}
            }
        }
    }
}
