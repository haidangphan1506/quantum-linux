import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Notificaciones como en Ajustes del Sistema de macOS: vistas previas, No molestar
// (Concentración) y «Notificaciones de apps»: cada app que alguna vez avisó, con su
// interruptor para permitir o silenciar sus avisos.
ColumnLayout {
    id: page
    spacing: 16

    readonly property var apps: (Settings.notifications.apps ?? []).slice().sort((a, b) => a.localeCompare(b))
    readonly property var muted: Settings.notifications.muted ?? []
    function iconFor(name: string): string {
        const hit = Apps.search(name)[0];
        return hit?.icon || "dialog-information";
    }
    function setAllowed(name: string, on: bool): void {
        const m = muted.filter(x => x !== name);
        if (!on) m.push(name);
        Settings.set("notifications", "muted", m);
    }

    PageHero {
        icon: "notifications"
        color: "#FF3B30"
        title: I18n.t("Notificaciones")
        text: I18n.t("Elige qué apps pueden avisarte y cómo se ven sus avisos.")
    }

    Group {
        title: I18n.t("Centro de notificaciones")
        OptionRow {
            title: I18n.t("Mostrar vistas previas")
            help: Settings.lock.showNotifContent ? I18n.t("El texto de los avisos se ve también con la pantalla bloqueada.")
                                                 : I18n.t("Con la pantalla bloqueada solo se ve qué app te avisó.")
            Choice {
                options: [{ v: true, t: I18n.t("Siempre") }, { v: false, t: I18n.t("Al desbloquear") }]
                value: Settings.lock.showNotifContent
                onPicked: v => Settings.setPath("lock.showNotifContent", v)
            }
        }
        OptionRow {
            title: I18n.t("No molestar")
            help: I18n.t("Los avisos llegan en silencio al centro de notificaciones. Los urgentes sí se muestran.")
            icon: "dark_mode"; iconColor: "#5856D6"
            Toggle { checked: Settings.notifications.dnd; onToggled: c => Settings.set("notifications", "dnd", c) }
        }
        OptionRow {
            title: I18n.t("Notificaciones guardadas")
            help: Notifs.count > 0 ? Notifs.count + " " + I18n.t("en el centro de notificaciones") : I18n.t("No hay notificaciones.")
            PillButton { text: I18n.t("Borrar todas"); implicitHeight: 28; enabled_: Notifs.count > 0; onClicked: if (Notifs.count > 0) Notifs.clearAll() }
        }
    }

    Group {
        title: I18n.t("Notificaciones de apps")
        help: page.apps.length === 0 ? "" : I18n.t("Apagado: la app no muestra avisos ni suena; sus avisos solo quedan en el centro de notificaciones.")
        OptionRow {
            visible: page.apps.length === 0
            title: I18n.t("Las apps aparecen aquí cuando te envían su primer aviso.")
        }
        // cada app: ícono, nombre y estado, con flecha ›; al pulsar se despliega su interruptor
        Repeater {
            model: page.apps
            ColumnLayout {
                id: appRow
                required property string modelData
                required property int index
                readonly property bool allowed: !page.muted.includes(modelData)
                property bool open: false
                Layout.fillWidth: true
                spacing: 0
                Rectangle { visible: appRow.index > 0; Layout.fillWidth: true; implicitHeight: 1; color: Theme.alpha(Theme.fg, 0.08) }
                NavRow {
                    title: appRow.modelData
                    help: appRow.allowed ? I18n.t("Avisos y sonidos") : I18n.t("Desactivadas")
                    appIcon: page.iconFor(appRow.modelData)
                    implicitHeight: 56
                    onClicked: appRow.open = !appRow.open
                }
                OptionRow {
                    visible: appRow.open
                    title: I18n.t("Permitir notificaciones")
                    Toggle { checked: appRow.allowed; onToggled: c => page.setAllowed(appRow.modelData, c) }
                }
            }
        }
    }
}
