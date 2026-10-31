import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// Notificaciones emergentes arriba a la derecha.
PanelWindow {
    id: win

    visible: Notifs.popups.length > 0 && !Shell.controlCenterOpen
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-notifications"
    anchors { top: true; right: true }
    margins { top: 8; right: 10 }
    implicitWidth: 400
    implicitHeight: column.implicitHeight
    color: "transparent"

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.popups

            NotifCard {
                id: card
                required property var modelData
                notif: modelData
                popup: true
                Layout.fillWidth: true

                // Se esconde sola (queda en el historial del centro de control).
                // La barrita de abajo muestra el tiempo que le queda; se pausa con el mouse encima.
                readonly property int life: card.notif.expireTimeout > 0 ? card.notif.expireTimeout : 6000
                property real remain: 1
                NumberAnimation on remain {
                    id: lifeAnim
                    from: 1
                    to: 0
                    duration: card.life
                    paused: hover.hovered || drag.active
                    onFinished: Notifs.dismissPopup(card.notif)
                }
                HoverHandler { id: hover }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: parent.radius
                    anchors.bottomMargin: 4
                    width: (parent.width - 2 * parent.radius) * card.remain
                    height: 3
                    radius: 1.5
                    opacity: 0.8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.brandCyan }
                        GradientStop { position: 0.5; color: Theme.brandIndigo }
                        GradientStop { position: 1; color: Theme.brandViolet }
                    }
                }

                // Arrastrar hacia la derecha la descarta
                DragHandler {
                    id: drag
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (!active) {
                            if (slide.x > 120) Notifs.dismissPopup(card.notif);
                            else slide.x = 0;
                        }
                    }
                    onTranslationChanged: if (active) slide.x = Math.max(0, translation.x)
                }

                // Entrada: llega desde la derecha con un rebote suave
                opacity: Math.max(0, 1 - slide.x / 300) * appear
                property real appear: 0
                scale: 0.9 + 0.1 * appear
                transformOrigin: Item.Right
                transform: Translate {
                    id: slide
                    x: 420
                    Behavior on x { enabled: !drag.active; NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                }
                Behavior on appear { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Component.onCompleted: { appear = 1; slide.x = 0; }
            }
        }
    }
}
