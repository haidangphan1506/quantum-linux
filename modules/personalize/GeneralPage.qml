import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// «General» como en Ajustes del Sistema de macOS: encabezado con ícono grande y
// recuadros de filas con flecha que abren sus páginas.
ColumnLayout {
    id: page

    required property var host
    spacing: 14

    Component.onCompleted: Updates.check()

    function titleOf(id: string): string { return host.pages.find(p => p.id === id)?.t ?? id; }

    PageHero {
        icon: "settings"
        color: "#8E8E93"
        title: I18n.t("General")
        text: I18n.t("Gestiona la configuración general del equipo: actualizaciones, almacenamiento, idioma, fecha y hora y más.")
    }

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
