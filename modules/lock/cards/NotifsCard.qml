import QtQuick
import qs.services
import qs.components

// Notificaciones agrupadas por app. Por privacidad, el contenido solo se muestra
// si se activa en Personalizar.
LockCard {
    id: card
    implicitHeight: 300
    readonly property var groups: {
        const map = {}, out = [];
        for (const n of Notifs.list) {
            const k = n.appName || "Sistema";
            if (!map[k]) { map[k] = { name: k, icon: n.appIcon, items: [] }; out.push(map[k]); }
            map[k].items.push(n);
        }
        return out;
    }
    Txt {
        id: head
        text: Notifs.count === 0 ? "Sin notificaciones" : Notifs.count === 1 ? "1 notificación" : Notifs.count + " notificaciones"
        font.family: "monospace"; font.pixelSize: 16; color: Theme.fgMuted
    }
    Column {
        y: head.height + 14
        width: parent.width
        spacing: 10
        Repeater {
            model: card.groups.slice(0, 6)
            Rectangle {
                id: g
                required property var modelData
                width: parent.width
                height: col.implicitHeight + 22
                radius: 18
                color: Qt.rgba(1, 1, 1, 0.05)
                AppIcon {
                    x: 12; y: 12
                    size: 38
                    name: g.modelData.icon || "dialog-information"
                }
                Column {
                    id: col
                    x: 62; y: 11
                    width: parent.width - 74
                    spacing: 3
                    Row {
                        width: parent.width
                        Txt { width: parent.width - cnt.width; text: g.modelData.name; font.weight: Font.DemiBold; color: Theme.fg; elide: Text.ElideRight }
                        Rectangle {
                            id: cnt
                            visible: g.modelData.items.length > 1
                            width: visible ? cntT.implicitWidth + 16 : 0; height: 22; radius: 11
                            color: Theme.surfaceHighest
                            Txt { id: cntT; anchors.centerIn: parent; text: g.modelData.items.length; font.pixelSize: Theme.textSmall; color: Theme.fg }
                        }
                    }
                    Repeater {
                        model: Settings.lock.showNotifContent ? g.modelData.items.slice(0, 3) : [g.modelData.items[0]]
                        Txt {
                            required property var modelData
                            width: col.width
                            text: Settings.lock.showNotifContent ? (modelData.summary + "  " + (modelData.body || "")).replace(/<[^>]+>/g, "")
                                                                 : (g.modelData.items.length === 1 ? "Notificación nueva" : "Notificaciones nuevas")
                            color: Theme.fgMuted; font.pixelSize: Theme.textSmall + 1
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
