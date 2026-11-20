import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Botones de radio en fila (estilo macOS)
GridLayout {
    id: rg
    property bool vertical: false
    columns: vertical ? 1 : Math.max(1, options.length)
    rowSpacing: 8
    columnSpacing: 18
    property var options: []
    property var value
    signal picked(var v)
    Repeater {
        model: rg.options
        RowLayout {
            id: rb
            required property var modelData
            readonly property bool on: rg.value === modelData.v
            spacing: 6
            Rectangle {
                implicitWidth: 16; implicitHeight: 16; radius: 8
                color: rb.on ? Theme.accent : Theme.alpha(Theme.fg, 0.14)
                border.width: 0
                Rectangle { anchors.centerIn: parent; visible: rb.on; width: 6; height: 6; radius: 3; color: "white" }
            }
            Txt { text: rb.modelData.t }
            TapHandler { onTapped: rg.picked(rb.modelData.v) }
        }
    }
}
