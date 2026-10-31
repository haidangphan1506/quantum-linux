import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Selector de una opción entre pocas: [{ v: valor, t: "Texto", i: "ícono" }]
Rectangle {
    id: root

    property var options: []
    property var value
    signal picked(var value)

    implicitWidth: row.implicitWidth + 8
    implicitHeight: 40
    radius: height / 2
    color: Theme.surfaceHigh

    // indicador que se desliza a la opción elegida
    Rectangle {
        readonly property Item target: {
            for (let i = 0; i < rep.count; i++)
                if (rep.itemAt(i)?.on) return rep.itemAt(i);
            return null;
        }
        visible: target !== null
        x: target ? target.x + row.x : 0
        y: 4
        width: target ? target.width : 0
        height: parent.height - 8
        radius: height / 2
        color: Theme.primaryContainer
        Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }

    RowLayout {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        Repeater {
            id: rep
            model: root.options
            Item {
                id: opt
                required property var modelData
                readonly property bool on: root.value === modelData.v
                implicitWidth: lab.implicitWidth + 28
                implicitHeight: 32
                RowLayout {
                    id: lab
                    anchors.centerIn: parent
                    spacing: 6
                    Icon {
                        visible: !!opt.modelData.i
                        text: opt.modelData.i ?? ""
                        size: 17
                        fill: opt.on ? 1 : 0
                        color: opt.on ? Theme.primaryContainerFg : Theme.fg
                    }
                    Txt {
                        text: opt.modelData.t
                        font.pixelSize: Theme.textSmall + 1
                        font.weight: Font.DemiBold
                        color: opt.on ? Theme.primaryContainerFg : Theme.fg
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
