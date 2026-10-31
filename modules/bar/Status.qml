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
            Icon {
                size: 18
                text: {
                    const p = root.battery?.percentage ?? 0;
                    if (root.battery?.state === UPowerDeviceState.Charging)
                        return "battery_charging_full";
                    const level = Math.min(6, Math.floor(p * 7));
                    return p > 0.95 ? "battery_full" : "battery_" + level + "_bar";
                }
            }
            Txt {
                text: Math.round((root.battery?.percentage ?? 0) * 100) + "%"
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
