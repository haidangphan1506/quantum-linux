import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.services
import qs.components
import "../notifications"

// Centro de control: ajustes rápidos, volumen, brillo, música y notificaciones.
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
    readonly property string user: Quickshell.env("USER") ?? ""
    // El centro de control tiene dos páginas: los ajustes rápidos y la lista
    // de redes Wi-Fi (Shell.wifiPage).
    readonly property bool wifiPage: Shell.wifiPage
    readonly property bool btPage: Shell.btPage
    readonly property real contentHeight: wifiPage ? wifiPageLayout.implicitHeight : btPage ? btPageLayout.implicitHeight : layout.implicitHeight

    Card {
        id: panel
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 10
        width: 420
        height: Math.min(win.contentHeight + 36, parent.height - 16)
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

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 18
            contentHeight: win.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: layout
                width: flick.width
                visible: !win.wifiPage && !win.btPage
                spacing: 14

                // Encabezado: saludo y accesos
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: !win.wifiPage

                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 21
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.brandCyan }
                            GradientStop { position: 1; color: Theme.brandViolet }
                        }
                        Txt {
                            anchors.centerIn: parent
                            text: win.user.charAt(0).toUpperCase()
                            color: "white"
                            font.pixelSize: Theme.textLarge
                            font.weight: Font.Bold
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        // fillWidth: sin esto el layout usa el ancho del texto como mínimo y,
                        // con textos largos (p. ej. en vietnamita), empuja todo el panel fuera del borde.
                        Txt { Layout.fillWidth: true; text: I18n.t("Hola, ") + win.user; font.weight: Font.DemiBold; font.pixelSize: Theme.textLarge }
                        Txt { Layout.fillWidth: true; text: "Quantum Linux"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                    }
                    IconButton {
                        icon: "settings"
                        onClicked: { Shell.closeAll(); Shell.personalize(); }
                    }
                    IconButton { icon: "wallpaper"; onClicked: Shell.toggleWallpapers() }
                    IconButton { icon: "lock"; onClicked: Shell.lock() }
                    IconButton { icon: "power_settings_new"; onClicked: Shell.toggleSession() }
                }

                // Volumen y brillo
                QSlider {
                    Layout.fillWidth: true
                    icon: Audio.icon
                    value: Audio.muted ? 0 : Audio.volume
                    onMoved: v => Audio.setVolume(v)
                    onIconClicked: Audio.toggleMute()
                }
                QSlider {
                    Layout.fillWidth: true
                    visible: Brightness.available
                    icon: "brightness_6"
                    value: Brightness.value
                    onMoved: v => Brightness.set(v)
                }

                // Ajustes rápidos
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8

                    ToggleTile {
                        Layout.fillWidth: true
                        icon: Net.icon
                        title: "Wi-Fi"
                        subtitle: Net.label
                        on: Net.wifiEnabled
                        onToggled: Net.toggleWifi()
                        // botón visible para elegir red (el clic derecho también sirve)
                        moreVisible: true
                        onMore: Shell.openWifi()
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        icon: Bt.icon
                        title: "Bluetooth"
                        subtitle: Bt.label
                        on: Bt.enabled
                        onToggled: Bt.toggle()
                        // botón visible para ver/emparejar dispositivos (el clic derecho también sirve)
                        moreVisible: true
                        onMore: Shell.openBluetooth()
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        icon: Settings.notifications.dnd ? "do_not_disturb_on" : "do_not_disturb_off"
                        title: I18n.t("No molestar")
                        subtitle: Settings.notifications.dnd ? I18n.t("Activado") : I18n.t("Desactivado")
                        on: Settings.notifications.dnd
                        onToggled: Settings.set("notifications", "dnd", !Settings.notifications.dnd)
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        icon: "dark_mode"
                        title: I18n.t("Modo oscuro")
                        subtitle: Settings.appearance.mode === "auto" ? I18n.t("Automático") + " · " + (Theme.dark ? I18n.t("Activado") : I18n.t("Desactivado"))
                                : Theme.dark ? I18n.t("Activado") : I18n.t("Desactivado")
                        on: Theme.dark
                        onToggled: Settings.set("appearance", "mode", Theme.dark ? "light" : "dark")
                        // clic derecho / flecha: elegir Oscuro, Claro o Automático
                        moreVisible: true
                        onMore: Shell.personalizePage("colors")
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        icon: "nightlight"
                        title: I18n.t("Luz nocturna")
                        subtitle: !Settings.display.nightLight ? I18n.t("Desactivada")
                            : Settings.display.nightMode === "sunset" ? I18n.t("Al atardecer")
                            : Settings.display.nightMode === "schedule" ? Settings.display.nightFrom + " a " + Settings.display.nightTo
                            : I18n.t("Activada")
                        on: Settings.display.nightLight
                        onToggled: Shell.toggleNightLight()
                        moreVisible: true
                        onMore: Shell.personalizePage("display")
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        icon: "sports_esports"
                        title: I18n.t("Modo juego")
                        subtitle: Shell.gameMode ? I18n.t("Máximo rendimiento") : I18n.t("Desactivado")
                        on: Shell.gameMode
                        onToggled: Shell.setGameMode(!Shell.gameMode)
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        icon: "grid_view"
                        title: I18n.t("Mosaico")
                        subtitle: Settings.windows.tiling ? I18n.t("Ventanas ordenadas") : I18n.t("Ventanas libres")
                        on: Settings.windows.tiling
                        onToggled: Settings.set("windows", "tiling", !Settings.windows.tiling)
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        icon: "palette"
                        title: I18n.t("Colores del fondo")
                        subtitle: Settings.appearance.dynamicColors ? I18n.t("Activado") : I18n.t("Colores Quantum")
                        on: Settings.appearance.dynamicColors
                        onToggled: Settings.set("appearance", "dynamicColors", !Settings.appearance.dynamicColors)
                    }
                    ToggleTile {
                        Layout.fillWidth: true
                        Layout.columnSpan: 2          // queda sola en su fila: que ocupe todo el ancho
                        readonly property var profiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                        readonly property var names: [I18n.t("Ahorro"), I18n.t("Equilibrado"), I18n.t("Rendimiento")]
                        readonly property int current: profiles.indexOf(PowerProfiles.profile)
                        icon: current < 0 ? "battery_unknown" : ["eco", "balance", "bolt"][current]
                        title: I18n.t("Energía")
                        subtitle: current < 0 ? I18n.t("No disponible") : names[current]
                        on: PowerProfiles.profile === PowerProfile.Performance
                        opacity: current < 0 ? 0.5 : 1
                        onToggled: {
                            let next = (current + 1) % 3;
                            if (profiles[next] === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile)
                                next = 0;
                            PowerProfiles.profile = profiles[next];
                        }
                    }
                }

                // Música
                Rectangle {
                    Layout.fillWidth: true
                    visible: win.player !== null
                    implicitHeight: 76
                    radius: Theme.radius
                    color: Theme.surfaceHigh
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        Rectangle {
                            implicitWidth: 56
                            implicitHeight: 56
                            radius: 12
                            color: Theme.surfaceHighest
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
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Txt { Layout.fillWidth: true; text: win.player?.trackTitle || I18n.t("Sin título"); font.weight: Font.DemiBold }
                            Txt { Layout.fillWidth: true; text: win.player?.trackArtist || win.player?.identity || ""; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                        }
                        IconButton { icon: "skip_previous"; onClicked: win.player.previous() }
                        IconButton {
                            icon: win.player?.isPlaying ? "pause" : "play_arrow"
                            active: true
                            onClicked: win.player.togglePlaying()
                        }
                        IconButton { icon: "skip_next"; onClicked: win.player.next() }
                    }
                }

                // Notificaciones
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Txt {
                        Layout.fillWidth: true
                        text: I18n.t("Notificaciones")
                        font.weight: Font.Bold
                        font.pixelSize: Theme.textLarge
                    }
                    Txt {
                        visible: Notifs.count > 0
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

                // Historial (pocas notificaciones: el desplazamiento lo da el panel)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: Notifs.list
                        NotifCard {
                            required property var modelData
                            Layout.fillWidth: true
                            notif: modelData
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 10
                        visible: Notifs.count === 0
                        spacing: 6
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "notifications_paused"
                            size: 30
                            color: Theme.fgMuted
                        }
                        Txt {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.t("Todo al día")
                            color: Theme.fgMuted
                        }
                    }
                }
            }

            // Página de redes Wi-Fi
            ColumnLayout {
                id: wifiPageLayout
                width: flick.width
                visible: win.wifiPage
                y: win.wifiPage ? 0 : layout.implicitHeight
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
