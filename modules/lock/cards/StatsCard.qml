import QtQuick
import QtQuick.Effects
import qs.services
import qs.components

// Uso del sistema: CPU (con temperatura), RAM y disco, como «gotas» que se llenan.
LockCard {
    id: card
    implicitHeight: 190
    Component.onCompleted: SysInfo.active = true
    Component.onDestruction: SysInfo.active = false
    Row {
        anchors.centerIn: parent
        spacing: 18
        Repeater {
            model: [
                { i: "memory", v: SysInfo.cpu, c: Theme.primaryContainer, t: SysInfo.temp > 0 ? Math.round(SysInfo.temp) + "°C" : "" },
                { i: "memory_alt", v: SysInfo.ram, c: Theme.tertiary, t: "" },
                { i: "hard_drive", v: SysInfo.disk, c: Theme.secondaryContainer, t: "" },
            ]
            Item {
                id: blob
                required property var modelData
                required property int index
                width: Math.min(118, (card.width - 44 - 36) / 3); height: width
                // forma de fondo
                Rectangle {
                    id: shape
                    anchors.fill: parent
                    radius: width * 0.34
                    color: Qt.rgba(blob.modelData.c.r, blob.modelData.c.g, blob.modelData.c.b, 0.28)
                }
                // líquido con olas (un cuadrado redondeado gigante que gira), recortado a la forma
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: shapeMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                    Rectangle {
                        property real level: Math.max(0.06, blob.modelData.v)
                        Behavior on level { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                        width: blob.width * 2.4; height: width
                        radius: width * 0.42
                        x: (blob.width - width) / 2
                        y: blob.height * (1 - level) - 6
                        color: blob.modelData.c
                        opacity: 0.9
                        RotationAnimation on rotation {
                            loops: Animation.Infinite
                            running: Settings.windows.animations !== "none"
                            from: 0; to: 360
                            duration: 7000 + blob.index * 1300
                        }
                    }
                }
                Item {
                    id: shapeMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: width * 0.34; color: "white" }
                }
                Column {
                    anchors.centerIn: parent
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; text: blob.modelData.i; size: 22; color: "white" }
                    Txt { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(blob.modelData.v * 100) + "%"; font.pixelSize: 30; font.weight: Font.Black; color: "white" }
                }
                Rectangle {
                    visible: blob.modelData.t !== ""
                    anchors.right: parent.right; anchors.top: parent.top
                    anchors.rightMargin: -10; anchors.topMargin: -10
                    width: tt.implicitWidth + 16; height: 30; radius: 15
                    color: Theme.surfaceHighest
                    Txt { id: tt; anchors.centerIn: parent; text: blob.modelData.t; font.weight: Font.Bold; color: Theme.fg }
                }
            }
        }
    }
}
