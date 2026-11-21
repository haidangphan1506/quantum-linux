import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// «System»: las filas que antes estaban en General (Acerca de, actualizaciones,
// almacenamiento, inicio, idioma, fecha y hora, apps). Pendiente de rediseñar.
ColumnLayout {
    id: page

    required property var host
    spacing: 14

    Component.onCompleted: Updates.check()

    function titleOf(id: string): string { return host.pages.find(p => p.id === id)?.t ?? id; }

    Group {
        NavRow { title: page.titleOf("about"); icon: "laptop_mac"; iconColor: "#8E8E93"; onClicked: page.host.go("about") }
        NavRow { title: page.titleOf("update"); icon: "settings_backup_restore"; iconColor: "#8E8E93"; badge: Updates.count; onClicked: page.host.go("update") }
        NavRow { title: page.titleOf("storage"); icon: "hard_drive"; iconColor: "#8E8E93"; onClicked: page.host.go("storage") }
    }
    Group {
        NavRow { title: page.titleOf("login"); icon: "list"; iconColor: "#8E8E93"; onClicked: page.host.go("login") }
    }
    Group {
        NavRow { title: page.titleOf("language"); icon: "language"; iconColor: "#007AFF"; onClicked: page.host.go("language") }
        NavRow { title: page.titleOf("datetime"); icon: "schedule"; iconColor: "#007AFF"; onClicked: page.host.go("datetime") }
    }
    Group {
        NavRow { title: page.titleOf("apps"); icon: "apps"; iconColor: "#FF9500"; onClicked: page.host.go("apps") }
    }
}
