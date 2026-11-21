import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Velocidad de la red en la barra, en una línea: «↓ 1.2 M/s  ↑ 30 K/s».
// Clic: Ajustes del Sistema → Ancho de banda.
MouseArea {
    id: root

    implicitWidth: col.implicitWidth + 12
    implicitHeight: 24
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: Shell.personalizeOpen ? Shell.settingsGo("bandwidth") : Shell.personalizePage("bandwidth")

    Component.onCompleted: SysInfo.barUsers++
    Component.onDestruction: SysInfo.barUsers--

    // bytes/s → texto corto de ancho casi fijo: «850 K/s», «1.2 M/s», «12 M/s»
    function fmt(b: real): string {
        if (b >= 10485760) return Math.round(b / 1048576) + " M/s";
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " M/s";
        if (b >= 1024) return Math.round(b / 1024) + " K/s";
        return Math.round(b) + " B/s";
    }

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: root.containsMouse ? Theme.alpha(Theme.fg, 0.12) : "transparent"
    }

    RowLayout {
        id: col
        anchors.centerIn: parent
        spacing: 6

        Repeater {
            model: [
                { icon: "arrow_downward", value: SysInfo.netDown },
                { icon: "arrow_upward", value: SysInfo.netUp }
            ]
            RowLayout {
                required property var modelData
                spacing: 1
                Icon { text: modelData.icon; size: 14; color: Theme.fgMuted }
                Txt {
                    text: root.fmt(modelData.value)
                    font.pixelSize: 13
                    font.features: { "tnum": 1 }
                    horizontalAlignment: Text.AlignLeft
                    Layout.minimumWidth: 58
                }
            }
        }
    }
}
