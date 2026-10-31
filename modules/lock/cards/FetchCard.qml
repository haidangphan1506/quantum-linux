import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services
import qs.components

// Ficha del sistema estilo «fetch»: logo, datos y la paleta del tema.
LockCard {
    id: card
    implicitHeight: 290
    property string uptime: ""
    readonly property var battery: UPower.displayDevice
    FileView {
        path: "/proc/uptime"
        printErrors: false
        onLoaded: {
            const s = Math.floor(Number(text().split(" ")[0]));
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            card.uptime = (d ? d + (d === 1 ? " día, " : " días, ") : "") + (h ? h + " h " : "") + m + " min";
        }
    }
    Row {
        id: head
        spacing: 12
        Rectangle {
            width: 36; height: 36; radius: 10; color: Theme.primaryContainer
            Txt { anchors.centerIn: parent; text: ">"; font.family: "monospace"; font.pixelSize: 18; font.weight: Font.Bold; color: Theme.primaryContainerFg }
        }
        Txt { anchors.verticalCenter: parent.verticalCenter; text: "quantumfetch"; font.family: "monospace"; font.pixelSize: 18; color: Theme.fg }
    }
    Row {
        y: head.height + 22
        spacing: 22
        Image {
            width: 120; height: 120
            source: Quickshell.shellDir + "/assets/quantum-mark.svg"
            sourceSize: Qt.size(240, 240)
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Repeater {
                model: [
                    ["SO  ", "Quantum Linux 1.0"],
                    ["WM  ", "Wayfire"],
                    ["USER", Quickshell.env("USER") ?? ""],
                    ["UP  ", card.uptime],
                    (card.battery?.isLaptopBattery ? ["BAT ", Math.round(card.battery.percentage * 100) + "%"] : ["PC  ", "Escritorio"])
                ]
                Txt {
                    required property var modelData
                    width: card.width - 44 - 142
                    text: modelData[0] + ": " + modelData[1]
                    font.family: "monospace"; font.pixelSize: 16; color: Theme.fg
                    elide: Text.ElideRight
                }
            }
        }
    }
    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14
        Repeater {
            model: [Theme.surfaceHighest, Theme.primaryContainer, Theme.brandCyan, Theme.primary, Theme.secondaryContainer, Theme.brandViolet, Theme.tertiary, Theme.error]
            Rectangle { required property color modelData; width: 26; height: 26; radius: 13; color: modelData }
        }
    }
}
