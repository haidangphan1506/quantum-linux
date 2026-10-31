import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.services
import qs.components
import "../bar"

// Serpantium: barra de arriba hecha de píldoras. Cada píldora abre su panel debajo.
// Izquierda: buscar, personalizar, apps abiertas y música. Centro: hora y clima.
// Derecha: bandeja, red, Bluetooth, volumen, batería y apagar.
Scope {
    id: root

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false

    // Píldora: fondo oscuro, borde finito y resalte rosado si su panel está abierto
    component Pill: Rectangle {
        id: pill
        property string panel: ""
        property bool active: panel !== "" && Serp.panel === panel
        property alias hovered: ma.containsMouse
        default property alias content: row.data
        signal clicked()
        implicitWidth: row.implicitWidth + 20
        implicitHeight: 30
        radius: 9
        color: active ? Serp.cardHi : ma.containsMouse ? Serp.cardHi : Serp.pill
        border.width: 1
        border.color: active ? Serp.pink : Serp.line
        Behavior on color { ColorAnimation { duration: 140 } }
        // al apretar se hunde un poco y vuelve con rebote
        scale: ma.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: ma.pressed ? 70 : 260; easing.type: ma.pressed ? Easing.OutQuad : Easing.OutBack } }
        Row { id: row; anchors.centerIn: parent; spacing: 7 }
        // DEBAJO del contenido (z: -1): si quedaba encima se tragaba los clics de los
        // íconos de apps y de los botones de música
        MouseArea {
            id: ma
            z: -1
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (pill.panel !== "") Serp.toggle(pill.panel); pill.clicked(); }
        }
    }
    component SIcon: Icon { anchors.verticalCenter: parent.verticalCenter; size: 16; color: Serp.fg }
    component SText: Text {
        anchors.verticalCenter: parent.verticalCenter
        font.family: Serp.font; font.pixelSize: 12; color: Serp.fg
        elide: Text.ElideRight
    }

    PanelWindow {
        id: bar
        screen: Wm.screen
        WlrLayershell.namespace: "quantum-bar"
        WlrLayershell.layer: WlrLayer.Top
        anchors { top: true; left: true; right: true }
        implicitHeight: 42
        exclusiveZone: implicitHeight
        color: "transparent"

        // --------------------------------------------------------- izquierda
        Row {
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Pill { onClicked: Shell.toggleLauncher(false); SIcon { text: "search" } }
            Pill { onClicked: Shell.personalize(); SIcon { text: "tune" } }

            // apps abiertas y fijadas, como cuadritos (clic: enfocar / minimizar)
            Pill {
                visible: Wm.groups.length > 0 && Settings.ui.serpApps !== "dock"
                implicitWidth: Wm.groups.length * 24 + (Wm.groups.length - 1) * 7 + 14
                Repeater {
                    id: apps
                    model: Wm.groups
                    MouseArea {
                        id: app
                        required property var modelData
                        readonly property bool running: modelData.wins.length > 0
                        readonly property bool focused: modelData.wins.some(w => w.activated && !w.minimized)
                        width: 24; height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (app.running) Wm.toggle(app.modelData.wins[0]);
                            else if (app.modelData.entry) Apps.launch(app.modelData.entry);
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 6
                            color: app.focused ? Serp.pink : app.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 16
                            source: Quickshell.iconPath(app.modelData.icon, "application-x-executable")
                            opacity: app.running ? 1 : 0.5
                        }
                    }
                }
            }

            // música: carátula girando, título y controles
            Pill {
                panel: "media"
                visible: root.player !== null
                ClippingRectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10; color: "#0E0A0D"
                    border.width: 1; border.color: Serp.pink
                    RotationAnimation on rotation { running: root.player?.isPlaying ?? false; from: 0; to: 360; duration: 6000; loops: Animation.Infinite }
                    Image { anchors.fill: parent; source: root.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(40, 40) }
                    Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 3; color: Serp.bg }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    SText { anchors.verticalCenter: undefined; width: Math.min(150, implicitWidth); text: root.player?.trackTitle || "Sin título"; font.pixelSize: 11 }
                    SText { anchors.verticalCenter: undefined; width: Math.min(150, implicitWidth); text: root.player?.trackArtist || ""; font.pixelSize: 9; color: Serp.muted; visible: text !== "" }
                }
                Repeater {
                    model: [{ i: "skip_previous", f: () => root.player?.previous() },
                            { i: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow", f: () => root.player?.togglePlaying() },
                            { i: "skip_next", f: () => root.player?.next() }]
                    MouseArea {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 22
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData.f()
                        Icon { anchors.centerIn: parent; text: parent.modelData.i; size: 16; fill: 1; color: Serp.fg }
                    }
                }
            }
        }

        // --------------------------------------------------------- centro
        Row {
            anchors.centerIn: parent
            spacing: 6
            Pill {
                panel: "clock"
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    SText { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: undefined; text: Qt.formatTime(clock.date, "HH:mm:ss"); font.pixelSize: 12; font.weight: Font.Bold }
                    SText { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: undefined; text: Serp.cap(Qt.locale("es_ES").toString(clock.date, "dddd d 'de' MMM")); font.pixelSize: 9; color: Serp.muted }
                }
            }
            Pill {
                panel: "clock"
                visible: Weather.ready
                SIcon { text: Weather.icon; fill: 1 }
                SText { text: Math.round(Weather.temp) + "°C" }
            }
        }

        // --------------------------------------------------------- derecha
        Row {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Pill {
                visible: tray.visible
                implicitWidth: tray.implicitWidth + 8
                Tray { id: tray; window: bar; anchors.verticalCenter: parent.verticalCenter; scale: 0.85 }
            }
            Pill {
                panel: "control"
                SIcon { text: Net.icon; fill: 1; color: Net.online ? Serp.pink : Serp.muted }
                SText { width: Math.min(110, implicitWidth); text: Net.online ? Net.label : "Sin red" }
            }
            Pill {
                panel: "control"
                visible: Bt.available
                SIcon { text: Bt.icon; fill: 1; color: Bt.connected.length > 0 ? Serp.pink : Serp.fg }
                SText { visible: Bt.connected.length > 0; width: Math.min(100, implicitWidth); text: Bt.connected[0]?.name ?? "" }
            }
            Pill {
                panel: "control"
                SIcon { text: Audio.icon; fill: 1 }
                SText { text: Math.round(Audio.volume * 100) + "%" }
            }
            Pill {
                panel: "control"
                visible: root.hasBattery
                color: active ? Serp.cardHi : (root.battery?.percentage ?? 1) < 0.2 ? Qt.rgba(0.9, 0.3, 0.35, 0.35) : hovered ? Serp.cardHi : Serp.pill
                SIcon { text: root.battery?.state === UPowerDeviceState.Charging ? "battery_charging_full" : "battery_full"; fill: 1 }
                SText { text: Math.round((root.battery?.percentage ?? 0) * 100) + "%" }
            }
            Pill {
                visible: Updates.rebootNeeded && !Updates.rebootAsk
                onClicked: Updates.rebootAsk = true
                SIcon { text: "restart_alt"; color: Serp.pink }
                SText { text: "Reiniciar"; color: Serp.pink }
            }
            Pill {
                implicitWidth: 30
                onClicked: Shell.toggleSession()
                SIcon { text: "power_settings_new"; color: Serp.pink }
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }
}
