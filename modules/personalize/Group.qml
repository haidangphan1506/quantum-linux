import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Sección estilo Ajustes del Sistema de macOS: título en negrita fuera del recuadro,
// las filas dentro de un recuadro gris redondeado (separadas por una línea fina, ver
// OptionRow) y la nota de ayuda debajo, en gris pequeño.
ColumnLayout {
    id: root

    property string title: ""
    property string help: ""
    property string icon: ""               // se mantiene por compatibilidad (no se dibuja)
    property bool advanced: false          // solo con «Avanzado»
    property bool shown: true              // para ocultar la sección según el estado
    property bool boxed: true              // false: sin recuadro (contenido suelto)
    default property alias content: body.data

    visible: shown && (!advanced || Settings.ui.advanced)
    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 6

    RowLayout {
        visible: root.title !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 8
        Txt { text: root.title; font.weight: Font.Bold }
        Rectangle {
            visible: root.advanced
            implicitWidth: advT.implicitWidth + 12; implicitHeight: 18; radius: 9
            color: Theme.alpha("#007aff", 0.14)
            Txt { id: advT; anchors.centerIn: parent; text: I18n.t("Avanzado"); font.pixelSize: Theme.textSmall - 1; font.weight: Font.DemiBold; color: "#007aff" }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + (root.boxed ? 8 : 0)
        radius: 10
        color: !root.boxed ? "transparent" : Theme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.03)
        border.width: root.boxed ? 1 : 0
        border.color: Theme.alpha(Theme.fg, 0.08)

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.boxed ? 14 : 0
            anchors.rightMargin: root.boxed ? 14 : 0
            anchors.topMargin: root.boxed ? 4 : 0
            spacing: 0
        }
    }

    Txt {
        visible: root.help !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        text: root.help
        color: Theme.fgMuted
        font.pixelSize: Theme.textSmall
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }
}
