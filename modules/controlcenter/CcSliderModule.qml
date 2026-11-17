import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

CcModule {
    id: sm
    property string title
    property string leftIcon
    property string rightIcon
    property real value: 0
    signal moved(real v)
    signal leftClicked
    implicitWidth: 340
    implicitHeight: 84
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 6
        Txt { text: sm.title; font.weight: Font.DemiBold }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Icon {
                text: sm.leftIcon
                size: 18
                color: Theme.fgMuted
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sm.leftClicked() }
            }
            CcSlim {
                Layout.fillWidth: true
                value: sm.value
                onMoved: v => sm.moved(v)
            }
            Icon { text: sm.rightIcon; size: 20; color: Theme.fgMuted }
        }
    }
}
