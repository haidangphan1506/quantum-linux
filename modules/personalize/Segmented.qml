import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Control segmentado de macOS: [{ v: valor, t: "Texto", i: "ícono" }].
// Fondo gris, la opción elegida en una pastilla blanca (gris claro en modo oscuro).
Rectangle {
    id: root

    property var options: []
    property var value
    signal picked(var value)

    implicitWidth: row.implicitWidth + 4
    implicitHeight: 28
    radius: 7
    color: Theme.alpha(Theme.fg, Theme.dark ? 0.1 : 0.07)

    Rectangle {
        readonly property Item target: {
            for (let i = 0; i < rep.count; i++)
                if (rep.itemAt(i)?.on) return rep.itemAt(i);
            return null;
        }
        visible: target !== null
        x: target ? target.x + row.x : 0
        y: 2
        width: target ? target.width : 0
        height: parent.height - 4
        radius: 5
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : "white"
        border.width: Theme.dark ? 0 : 1
        border.color: Qt.rgba(0, 0, 0, 0.06)
        Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }

    RowLayout {
        id: row
        x: 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        Repeater {
            id: rep
            model: root.options
            Item {
                id: opt
                required property var modelData
                readonly property bool on: root.value === modelData.v
                implicitWidth: lab.implicitWidth + 22
                implicitHeight: 24
                RowLayout {
                    id: lab
                    anchors.centerIn: parent
                    spacing: 5
                    Icon {
                        visible: !!opt.modelData.i
                        text: opt.modelData.i ?? ""
                        size: 15
                        fill: opt.on ? 1 : 0
                        color: Theme.fg
                    }
                    Txt {
                        text: opt.modelData.t
                        font.pixelSize: Theme.textSmall + 1
                        font.weight: opt.on ? Font.DemiBold : Font.Normal
                        color: Theme.fg
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!opt.on) root.picked(opt.modelData.v)
                }
            }
        }
    }
}
