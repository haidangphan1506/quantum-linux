// Barra de herramientas de la página (estilo Ajustes del Sistema de macOS):
// flechas atrás / adelante y el título en negrita. Sin botones a la derecha (Deshacer,
// Restablecer y Avanzado están al pie de la barra lateral); la línea inferior solo
// aparece cuando el contenido se desplaza por debajo.
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Rectangle {
    id: head
    required property var host
    Layout.fillWidth: true
    implicitHeight: 52
    color: "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 20
        spacing: 2

        ToolBtn { icon: "chevron_left"; enabled_: head.host.canBack; onClicked: head.host.back() }
        ToolBtn { icon: "chevron_right"; enabled_: head.host.histPos < head.host.history.length - 1; onClicked: head.host.forward() }
        Txt {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            text: head.host.page.ht ?? head.host.page.t
            font.pixelSize: Theme.textNormal + 3
            font.weight: Font.Bold
            elide: Text.ElideRight
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.alpha(Theme.fg, 0.1)
        opacity: head.host.scrolled ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }
}
