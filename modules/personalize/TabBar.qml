import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Pestañas a todo el ancho (estilo macOS): [{ v: valor, t: "Texto" }]; la elegida en una pastilla blanca.
Rectangle {
    id: root
    property var options: []
    property var value
    signal picked(var v)

    Layout.fillWidth: true
    implicitHeight: 28
    radius: 7
    color: Theme.alpha(Theme.fg, Theme.dark ? 0.1 : 0.07)

    Row {
        anchors.fill: parent
        anchors.margins: 2
        Repeater {
            model: root.options
            Rectangle {
                id: tb
                required property var modelData
                readonly property bool on: root.value === modelData.v
                width: parent.width / Math.max(1, root.options.length); height: parent.height
                radius: 5
                color: on ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : "white") : "transparent"
                border.width: on && !Theme.dark ? 1 : 0
                border.color: Qt.rgba(0, 0, 0, 0.06)
                Txt { anchors.centerIn: parent; text: tb.modelData.t; font.weight: tb.on ? Font.DemiBold : Font.Normal }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.picked(tb.modelData.v) }
            }
        }
    }
}
