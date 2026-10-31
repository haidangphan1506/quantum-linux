import QtQuick
import qs.services

// Ícono de Material Symbols Rounded (por ligadura: text: "wifi").
Text {
    id: root

    property real fill: 0
    property int size: 20

    font.family: Theme.iconFont
    font.pixelSize: size
    font.variableAxes: ({ "FILL": fill, "opsz": Math.min(48, Math.max(20, size)), "wght": 450 })
    color: Theme.fg
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter

    Behavior on fill { NumberAnimation { duration: Theme.anim } }
}
