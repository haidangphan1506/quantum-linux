import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Rectangle {
    id: p
    property string icon
    property string title
    property string subtitle
    property bool on: false
    signal iconClicked
    signal clicked
    implicitWidth: 164
    implicitHeight: 76
    radius: height / 2
    color: pa.containsMouse ? Theme.glassTileHover : Theme.glassPanel
    border.width: 1
    border.color: Theme.glassBorder
    Behavior on color { ColorAnimation { duration: Theme.anim } }
    MouseArea {
        id: pa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: p.clicked()
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 10
        Rectangle {
            implicitWidth: 44
            implicitHeight: 44
            radius: 22
            color: p.on ? Qt.rgba(1, 1, 1, 0.94) : Theme.glassTile
            Behavior on color { ColorAnimation { duration: Theme.anim } }
            Icon {
                anchors.centerIn: parent
                text: p.icon
                size: 24
                fill: p.on ? 1 : 0
                color: p.on ? "#007aff" : Theme.fg
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: p.iconClicked()
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Txt { Layout.fillWidth: true; text: p.title; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Txt {
                Layout.fillWidth: true
                visible: p.subtitle !== ""
                text: p.subtitle
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall
                elide: Text.ElideRight
            }
        }
    }
}
