pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Servidor de notificaciones: historial y ventanas emergentes.
Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values
    readonly property int count: list.length
    property list<Notification> popups: []
    readonly property bool dnd: Settings.notifications.dnd

    function dismissPopup(n: Notification): void {
        popups = popups.filter(p => p !== n);
    }

    function clearAll(): void {
        for (const n of list.slice())
            n.dismiss();
        popups = [];
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            if (!root.dnd || n.urgency === NotificationUrgency.Critical) {
                root.popups = [n, ...root.popups].slice(0, 5);
                Sounds.play("notification");
            }
            n.closed.connect(() => root.dismissPopup(n));
        }
    }
}
