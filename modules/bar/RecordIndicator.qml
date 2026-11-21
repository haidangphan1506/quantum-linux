import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Chỉ báo «đang quay màn hình»: chấm đỏ nhấp nháy + thời gian. Bấm để dừng và lưu video.
Item {
    id: root

    visible: ScreenRecord.active
    implicitWidth: visible ? row.implicitWidth + 14 : 0
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: area.containsMouse ? Theme.alpha(Theme.error, 0.28) : Theme.alpha(Theme.error, 0.16)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon {
            id: dot
            text: "fiber_manual_record"
            size: 14
            fill: 1
            color: Theme.error
            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
            }
        }
        Txt {
            text: ScreenRecord.label
            color: Theme.error
            font.pixelSize: Theme.textSmall
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ScreenRecord.stop()
    }
}
