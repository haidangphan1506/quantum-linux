import QtQuick
import qs.services
import qs.components

// Clima: estado, temperatura, sensación y máxima/mínima.
LockCard {
    implicitHeight: 220
    Component.onCompleted: Weather.refresh()
    // al bloquear y luego cada 30 minutos (Weather no consulta más seguido que eso)
    Timer { interval: 30 * 60 * 1000; repeat: true; running: parent.visible; onTriggered: Weather.refresh() }
    Connections { target: Shell; function onLockRequested() { Weather.refresh(); } }
    Column {
        anchors.centerIn: parent
        spacing: 6
        visible: Weather.ready
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.text; font.pixelSize: 20; color: Theme.fg }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14
            Txt { text: Math.round(Weather.temp) + "°C"; font.pixelSize: 64; font.weight: Font.Black; color: Theme.primary }
            Icon {
                id: wIcon
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.icon; size: 56; color: Theme.primary
                property real bob: 0
                SequentialAnimation on bob {
                    loops: Animation.Infinite
                    running: Settings.windows.animations !== "none"
                    NumberAnimation { to: -6; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 1600; easing.type: Easing.InOutSine }
                }
                transform: Translate { y: wIcon.bob }
            }
        }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Sensación de " + Math.round(Weather.feels) + "°C"; font.pixelSize: 17; color: Theme.fg }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Máx " + Math.round(Weather.high) + "°C  ·  Mín " + Math.round(Weather.low) + "°C"; font.pixelSize: 15; color: Theme.fgMuted }
    }
    Column {
        anchors.centerIn: parent
        spacing: 8
        visible: !Weather.ready
        Icon { anchors.horizontalCenter: parent.horizontalCenter; text: "cloud_off"; size: 48; color: Theme.fgMuted }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Sin datos del clima"; color: Theme.fgMuted }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Conéctate a internet"; font.pixelSize: Theme.textSmall; color: Theme.fgMuted }
    }
}
