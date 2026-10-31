import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Zona del sistema: bandeja, actualizaciones, estado, hora, notificaciones y apagado.
// La usan la barra superior y, en el modo «una sola barra», la barra de tareas.
RowLayout {
    id: root

    required property var window
    property bool compact: false
    spacing: 4

    Tray { window: root.window; visible: Settings.dock.showTray }
    // actualizaciones disponibles
    Rectangle {
        visible: Updates.count > 0 && Settings.dock.showUpdates
        implicitWidth: updRow.implicitWidth + 18
        implicitHeight: 34
        radius: 17
        color: updArea.containsMouse ? Theme.alpha(Theme.primary, 0.28) : Theme.alpha(Theme.primary, 0.16)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        RowLayout {
            id: updRow
            anchors.centerIn: parent
            spacing: 6
            Icon { text: "system_update_alt"; size: 18; fill: 1; color: Theme.primary }
            Txt { text: Updates.count; font.weight: Font.Bold; color: Theme.primary }
        }
        MouseArea {
            id: updArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Updates.update()
        }
    }
    // «Más tarde» en el aviso de reinicio: queda este botón para reiniciar cuando quieras
    Rectangle {
        visible: Updates.rebootNeeded && !Updates.rebootAsk
        implicitWidth: rbRow.implicitWidth + 22
        implicitHeight: 34
        radius: 17
        color: rbArea.containsMouse ? Theme.alpha(Theme.primary, 0.28) : Theme.alpha(Theme.primary, 0.16)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        RowLayout {
            id: rbRow
            anchors.centerIn: parent
            spacing: 6
            Icon { text: "restart_alt"; size: 18; fill: 1; color: Theme.primary }
            Txt { text: "Reiniciar"; font.weight: Font.Bold; color: Theme.primary }
        }
        MouseArea {
            id: rbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Updates.rebootAsk = true
        }
    }
    Status {}
    Clock { compact: root.compact }
    IconButton {
        icon: Notifs.count > 0 ? "notifications_unread" : Settings.notifications.dnd ? "notifications_off" : "notifications"
        onClicked: Shell.toggleControlCenter()
    }
    IconButton {
        icon: "power_settings_new"
        onClicked: Shell.toggleSession()
    }
}
