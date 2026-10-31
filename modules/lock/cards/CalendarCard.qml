import QtQuick
import Quickshell
import qs.services
import qs.components

// Calendario del mes con el día de hoy resaltado.
LockCard {
    id: card
    implicitHeight: 300
    SystemClock { id: clk; precision: SystemClock.Hours }
    readonly property date today: clk.date
    readonly property int first: (new Date(today.getFullYear(), today.getMonth(), 1).getDay() + 6) % 7   // lunes = 0
    readonly property int days: new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
    Txt {
        id: head
        text: card.today.toLocaleDateString(Qt.locale(), "MMMM yyyy")
        font.pixelSize: 18; font.weight: Font.Bold; color: Theme.fg
        font.capitalization: Font.Capitalize
    }
    Grid {
        y: head.height + 14
        columns: 7
        readonly property real cell: (card.width - 44) / 7
        Repeater {
            model: ["L", "M", "M", "J", "V", "S", "D"]
            Txt { required property string modelData; width: parent.cell; height: 28; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.fgMuted; font.weight: Font.DemiBold }
        }
        Repeater {
            model: card.first + card.days
            Item {
                required property int index
                readonly property int day: index - card.first + 1
                width: parent.cell; height: 32
                Rectangle {
                    anchors.centerIn: parent
                    width: 30; height: 30; radius: 15
                    visible: parent.day === card.today.getDate()
                    color: "transparent"
                    border.width: 2; border.color: Theme.primary
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: Settings.windows.animations !== "none"
                        NumberAnimation { from: 1; to: 1.6; duration: 1600; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 400 }
                    }
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: Settings.windows.animations !== "none"
                        NumberAnimation { from: 0.8; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 400 }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 30; height: 30; radius: 15
                    visible: parent.day === card.today.getDate()
                    color: Theme.primary
                }
                Txt {
                    anchors.centerIn: parent
                    visible: parent.day > 0
                    text: parent.day
                    color: parent.day === card.today.getDate() ? Theme.primaryFg : Theme.fg
                    font.weight: parent.day === card.today.getDate() ? Font.Bold : Font.Normal
                }
            }
        }
    }
}
