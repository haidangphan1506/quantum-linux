import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Fila con flecha › que abre otra página (como las de General en macOS).
// `value`: texto gris a la derecha (p. ej. el estado actual).
OptionRow {
    id: root

    property string value: ""
    property int badge: 0
    signal clicked

    MouseArea {
        parent: root
        z: -1
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -8
            anchors.rightMargin: -8
            radius: 6
            color: parent.pressed ? Theme.alpha(Theme.fg, 0.08) : parent.containsMouse ? Theme.alpha(Theme.fg, 0.04) : "transparent"
        }
    }

    RowLayout {
        spacing: 8
        Txt { visible: root.value !== ""; text: root.value; color: Theme.fgMuted }
        Rectangle {
            visible: root.badge > 0
            implicitWidth: Math.max(20, badgeT.implicitWidth + 10); implicitHeight: 20; radius: 10
            color: "#FF3B30"
            Txt { id: badgeT; anchors.centerIn: parent; text: String(root.badge); color: "white"; font.pixelSize: Theme.textSmall - 1; font.weight: Font.Bold }
        }
        Icon { text: "chevron_right"; size: 18; color: Theme.fgMuted }
    }
}
