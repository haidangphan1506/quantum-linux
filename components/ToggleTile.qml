import QtQuick
import QtQuick.Layouts
import qs.services

// Botón grande del centro de control (Wi-Fi, Bluetooth, etc.).
Rectangle {
    id: root

    property string icon
    property string title
    property string subtitle
    property bool on: false
    property bool moreVisible: false   // muestra el botón de la derecha
    signal toggled
    signal more

    implicitHeight: 58
    radius: Theme.radius
    color: on ? Theme.primaryContainer : area.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh

    Behavior on color { ColorAnimation { duration: Theme.anim } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: root.moreVisible ? 44 : 12
        spacing: 12

        Icon {
            text: root.icon
            size: 22
            fill: root.on ? 1 : 0
            color: root.on ? Theme.primaryContainerFg : Theme.fg
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Txt {
                Layout.fillWidth: true
                text: root.title
                font.weight: Font.DemiBold
                color: root.on ? Theme.primaryContainerFg : Theme.fg
            }
            Txt {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                font.pixelSize: Theme.textSmall
                color: root.on ? Theme.alpha(Theme.primaryContainerFg, 0.8) : Theme.fgMuted
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => {
            if (e.button === Qt.RightButton) { Sounds.play("click"); root.more(); return; }
            Sounds.play(root.on ? "toggle-off" : "toggle-on");
            root.toggled();
        }
    }

    // Botón de la derecha (opcional): abre los detalles del tile
    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: root.moreVisible
        icon: "chevron_right"
        iconSize: 18
        onClicked: root.more()
    }
}
