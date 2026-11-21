import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services
import qs.components

// Red, Bluetooth, volumen y batería: un clic abre el centro de control.
Rectangle {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 34
    radius: height / 2
    color: area.containsMouse || Shell.controlCenterOpen ? Theme.alpha(Theme.fg, 0.10) : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        // Red: clic izquierdo abre el centro de control, clic derecho las redes
        Item {
            implicitWidth: 18
            implicitHeight: 18
            Icon { anchors.fill: parent; text: Net.icon; size: 18 }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: e => e.button === Qt.RightButton ? Shell.openWifi() : Shell.toggleControlCenter()
            }
        }
        Icon { text: Bt.icon; size: 18; visible: Bt.enabled }
        Icon { text: Audio.icon; size: 18 }
        Icon { text: "sports_esports"; size: 18; color: Theme.primary; visible: Shell.gameMode; fill: 1 }
        RowLayout {
            visible: root.hasBattery
            spacing: 2
            readonly property real pct: root.battery?.percentage ?? 0
            readonly property bool charging: root.battery?.state === UPowerDeviceState.Charging
            readonly property bool full: root.battery?.state === UPowerDeviceState.FullyCharged
            // modo de bajo consumo activo (como macOS: batería amarilla)
            readonly property bool lowPower: PowerProfiles.profile === PowerProfile.PowerSaver
            // verde: enchufado/cargando o lleno · amarillo: bajo consumo · rojo/ámbar: batería baja · resto: normal
            readonly property color tint: charging || full ? Theme.success
                : lowPower ? "#FFCC00"
                : pct <= 0.2 ? Theme.error
                : pct <= 0.4 ? Theme.tertiary
                : Theme.fg
            // modo de máximo rendimiento (Performance): ícono de velocidad junto a la batería
            Icon {
                visible: PowerProfiles.profile === PowerProfile.Performance
                size: 17
                fill: 1
                color: Theme.primary
                text: "speed"
            }
            Icon {
                size: 18
                fill: parent.charging ? 1 : 0
                color: parent.tint
                text: {
                    // cargando: mismo ícono con rayo, pero con el nivel real (20/30/50/60/80/90/full)
                    if (parent.charging) {
                        const lv = parent.pct;
                        const n = lv < 0.25 ? "20" : lv < 0.4 ? "30" : lv < 0.55 ? "50" : lv < 0.7 ? "60" : lv < 0.85 ? "80" : lv < 0.95 ? "90" : "full";
                        return "battery_charging_" + n;
                    }
                    if (parent.full || parent.pct > 0.95) return "battery_full";
                    return "battery_" + Math.min(6, Math.floor(parent.pct * 7)) + "_bar";
                }
            }
            Txt {
                color: parent.tint
                text: Math.round(parent.pct * 100) + "%"
                font.pixelSize: Theme.textSmall
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Shell.toggleControlCenter()
        onWheel: e => Audio.setVolume(Audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05))
    }
}
