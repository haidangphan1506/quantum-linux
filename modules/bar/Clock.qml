import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

Item {
    property bool compact: false
    implicitWidth: row.implicitWidth + 20
    implicitHeight: 34

    SystemClock {
        id: clock
        precision: Settings.clock.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Txt {
            text: Qt.formatDateTime(clock.date, (Settings.clock.format24h ? "HH:mm" : "h:mm") + (Settings.clock.showSeconds ? ":ss" : "")
                + (Settings.clock.format24h ? "" : " AP"))
            font.pixelSize: Theme.textNormal + 1
            font.weight: Font.Bold
        }
        Txt {
            visible: !parent.parent.compact && Settings.clock.showDate
            text: clock.date.toLocaleDateString(Qt.locale(), "ddd d MMM")
            color: Theme.fgMuted
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Shell.toggleDashboard()
    }
}
