import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Botón con texto (y opcionalmente ícono). `primary` lo pinta con el acento.
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property bool primary: false
    property bool danger: false
    property bool enabled_: true
    signal clicked

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 40
    radius: height / 2
    opacity: enabled_ ? 1 : 0.45
    color: primary ? (area.containsMouse ? Qt.lighter(Theme.primaryContainer, 1.12) : Theme.primaryContainer)
         : danger && area.containsMouse ? Theme.alpha(Theme.error, 0.18)
         : area.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
    scale: area.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon {
            visible: root.icon !== ""
            text: root.icon
            size: 18
            color: root.primary ? Theme.primaryContainerFg : root.danger ? Theme.error : Theme.fg
        }
        Txt {
            text: root.text
            font.weight: Font.DemiBold
            color: root.primary ? Theme.primaryContainerFg : root.danger ? Theme.error : Theme.fg
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled_
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
