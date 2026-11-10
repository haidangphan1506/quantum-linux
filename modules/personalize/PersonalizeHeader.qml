// Encabezado de página: título, ayuda e interruptor de opciones avanzadas.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

RowLayout {
    id: head
    required property var host
    Layout.fillWidth: true
    Layout.margins: 28
    Layout.bottomMargin: 14
    spacing: 16
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Txt { text: head.host.page.t; font.pixelSize: Theme.textTitle + 6; font.weight: Font.Bold }
        Txt { Layout.fillWidth: true; text: head.host.page.h; color: Theme.fgMuted }
    }
    // interruptor de opciones avanzadas
    Rectangle {
        implicitWidth: advRow.implicitWidth + 24
        implicitHeight: 44
        radius: 22
        color: Settings.ui.advanced ? Theme.alpha(Theme.primary, 0.14) : Theme.surfaceContainer
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.08)
        RowLayout {
            id: advRow
            anchors.centerIn: parent
            spacing: 10
            Icon { text: "tune"; size: 19; color: Settings.ui.advanced ? Theme.primary : Theme.fg }
            Txt { text: I18n.t("Opciones avanzadas"); font.weight: Font.DemiBold }
            Toggle {
                implicitWidth: 44; implicitHeight: 26
                checked: Settings.ui.advanced
                onToggled: c => Settings.setUi("advanced", c)
            }
        }
    }
}
