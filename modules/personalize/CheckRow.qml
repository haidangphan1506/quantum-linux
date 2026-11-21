import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Casilla redonda + texto + interruptor opcional (estilo macOS)
RowLayout {
    id: cr
    property string label: ""
    property bool on: false
    property bool withSwitch: true
    signal changed(bool v)
    Layout.fillWidth: true
    Layout.leftMargin: 4
    spacing: 10
    Rectangle {
        implicitWidth: 18; implicitHeight: 18; radius: 9
        color: cr.on ? Theme.accent : "transparent"
        border.width: 1; border.color: cr.on ? Theme.accent : Theme.alpha(Theme.fg, 0.3)
        Icon { anchors.centerIn: parent; visible: cr.on; text: "check"; size: 13; color: "white" }
        TapHandler { onTapped: cr.changed(!cr.on) }
    }
    Txt { Layout.fillWidth: true; text: cr.label }
    Toggle { visible: cr.withSwitch; checked: cr.on; onToggled: c => cr.changed(c) }
}
