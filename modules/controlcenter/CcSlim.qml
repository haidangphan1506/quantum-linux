import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Item {
    id: s
    property real value: 0
    signal moved(real v)
    implicitHeight: 20
    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 8
        radius: 4
        color: Qt.rgba(0, 0, 0, 0.18)   // rãnh tối nhẹ để thanh trắng nổi rõ
        Rectangle {
            width: Math.max(track.height, track.width * Math.min(1, Math.max(0, s.value)))
            height: parent.height
            radius: parent.radius
            color: "white"
            Behavior on width { enabled: !sa.pressed; NumberAnimation { duration: Theme.animFast } }
        }
    }
    MouseArea {
        id: sa
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function emit(x: real): void { s.moved(Math.min(1, Math.max(0, x / width))); }
        onPressed: e => emit(e.x)
        onPositionChanged: e => { if (pressed) emit(e.x); }
        onWheel: e => s.moved(Math.min(1, Math.max(0, s.value + (e.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
