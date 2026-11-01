import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Apps fijadas + abiertas, agrupadas por app como en Windows.
// Clic: abrir / enfocar / minimizar (o elegir ventana si hay varias).
// Clic central: nueva ventana. Clic derecho: menú.
RowLayout {
    id: root

    required property var dock
    spacing: 2
    function buttonAt(i: int): Item { return rep.itemAt(i); }
    // posición del mouse en coordenadas de esta fila (para la magnificación según la distancia)
    readonly property real pointerRow: dock.pointerX < 0 ? -1e6 : mapFromItem(dock.cardItem, dock.pointerX, 0).x

    // Arrastre para reordenar: índice que se arrastra, cuánto se movió y a qué posición caería
    property int dragFrom: -1
    property real dragDx: 0
    readonly property real slot: (rep.itemAt(0)?.width ?? 46) + spacing
    readonly property int dragTo: dragFrom < 0 ? -1 : Math.max(0, Math.min(rep.count - 1, dragFrom + Math.round(dragDx / slot)))

    Repeater {
        id: rep
        model: Wm.groups

        DockButton {
            id: btn
            required property var modelData
            required property int index
            readonly property var g: modelData
            readonly property bool running: g.wins.length > 0
            readonly property bool focused: g.wins.some(w => w.activated && !Wm.isMinimized(w))
            property bool launching: false

            active: focused
            flat: true
            // divisor entre las apps fijadas y las que solo estan abiertas (como macOS)
            readonly property bool firstUnpinned: index > 0 && !g.pinned && Wm.groups[index - 1].pinned
            Layout.leftMargin: firstUnpinned ? 12 : 0
            Rectangle {
                visible: btn.firstUnpinned
                x: -7; anchors.verticalCenter: parent.verticalCenter
                width: 1; height: Math.round(34 * Theme.dockScale)
                color: Theme.alpha(Theme.fg, 0.2)
            }
            // mientras la app abre, el puntero del mouse sobre el botón muestra la espera (como macOS)
            busy: launching
            // el rebote sigue hasta que haya una ventana visible (no solo una ventana oculta o en proceso de abrir)
            readonly property bool shown: g.wins.some(w => !Wm.isMinimized(w))
            onShownChanged: if (shown) launching = false

            // reordenar arrastrando: el que se arrastra sigue al mouse y los demás se corren
            draggable: true
            z: dragging ? 10 : 0
            onDragMoved: dx => { root.dragFrom = index; root.dragDx = dx; root.dock.closeMenu(); root.dock.hoverGroup = null; }
            onDropped: {
                const to = root.dragTo;
                root.dragFrom = -1; root.dragDx = 0;
                if (to !== index) Wm.moveGroup(g.id, to);
            }
            transform: Translate {
                x: {
                    if (root.dragFrom < 0) return 0;
                    if (btn.index === root.dragFrom) return root.dragDx;
                    const f = root.dragFrom, t = root.dragTo;
                    if (f < t && btn.index > f && btn.index <= t) return -root.slot;
                    if (f > t && btn.index < f && btn.index >= t) return root.slot;
                    return 0;
                }
                Behavior on x { enabled: !btn.dragging; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            }

            onClicked: {
                root.dock.closeMenu();
                if (!running) {
                    if (g.entry) {
                        if (btn.launching)
                            return;
                        launching = true;
                        launchTimer.restart();
                        Apps.launch(g.entry);
                    }
                } else {
                    Wm.activateGroup(g);
                }
            }
            onMiddleClicked: if (g.entry) {
                if (btn.launching)
                    return;
                launching = true;
                launchTimer.restart();
                Apps.launch(g.entry);
            }
            onRightClicked: { root.dock.hoverGroup = null; root.dock.menuItem = btn; root.dock.menuGroup = g; }
            onHoveredChanged: {
                if (hovered) {
                    root.dock.cancelHide();
                    root.dock.hoverItem = btn;
                    root.dock.hoverGroup = g;
                } else if (root.dock.hoverItem === btn) {
                    root.dock.scheduleHide();
                }
            }
            Timer { id: launchTimer; interval: 8000; onTriggered: btn.launching = false }

            AppIcon {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(8 * Theme.dockScale)
                size: Math.round(38 * Theme.dockScale)
                name: btn.g.icon
                opacity: btn.running && btn.g.wins.every(w => Wm.isMinimized(w)) ? 0.6 : 1
                // como macOS: el icono salta varias veces mientras la app abre, con una pausa entre saltos
                SequentialAnimation on anchors.bottomMargin {
                    running: btn.launching
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: Math.round(24 * Theme.dockScale); duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { to: Math.round(8 * Theme.dockScale); duration: 260; easing.type: Easing.OutBounce }
                    NumberAnimation { to: Math.round(16 * Theme.dockScale); duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { to: Math.round(8 * Theme.dockScale); duration: 200; easing.type: Easing.OutBounce }
                    PauseAnimation { duration: 500 }
                }
                // magnificación continua: cuanto más cerca del mouse, más grande (suavizado de Hermite),
                // así el icono crece y se achica mientras el mouse pasa de una app a otra
                readonly property real near: {
                    const d = Math.abs(btn.x + btn.width / 2 - root.pointerRow);
                    const t = Math.max(0, 1 - d / (Math.round(130 * Theme.dockScale)));
                    return t * t * (3 - 2 * t);
                }
                transformOrigin: Item.Bottom
                scale: (1 + 0.55 * near) * (btn.pressed ? 0.92 : 1)
                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            }

            // Indicador como en macOS: un punto bajo el icono si la app está abierta
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                // mientras abre (aún sin ventana) el punto parpadea suave, como el de macOS
                visible: btn.running || btn.launching
                width: 5; height: 5
                radius: 2.5
                color: btn.focused ? Theme.fg : Theme.alpha(Theme.fg, 0.55)
                SequentialAnimation on opacity {
                    running: btn.launching && !btn.running
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.15; duration: 450; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutQuad }
                }
            }
        }
    }

    // Ventanas minimizadas: a la derecha de un divisor, un icono por ventana (clic = restaurar)
    Rectangle {
        visible: Wm.minimizedItems.length > 0
        Layout.leftMargin: 6
        Layout.rightMargin: 4
        implicitWidth: 1
        implicitHeight: Math.round(34 * Theme.dockScale)
        color: Theme.alpha(Theme.fg, 0.2)
    }
    Repeater {
        model: Wm.minimizedItems

        DockButton {
            id: mbtn
            required property var modelData
            flat: true
            implicitWidth: Math.round(46 * Theme.dockScale)
            onClicked: { root.dock.closeMenu(); root.dock.hoverGroup = null; Wm.restore(modelData.win); }
            onHoveredChanged: {
                if (hovered) {
                    root.dock.cancelHide();
                    root.dock.hoverItem = mbtn;
                    root.dock.hoverGroup = { name: modelData.title || I18n.t("Ventana minimizada"), wins: [], entry: null, pinned: false, icon: modelData.icon };
                } else if (root.dock.hoverItem === mbtn) {
                    root.dock.scheduleHide();
                }
            }
            // miniatura de ventana con la insignia de la app, como en macOS
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(8 * Theme.dockScale)
                width: Math.round(38 * Theme.dockScale)
                height: Math.round(30 * Theme.dockScale)
                radius: 6
                color: Theme.alpha(Theme.fg, 0.1)
                border.width: 1
                border.color: Theme.alpha(Theme.fg, 0.25)
                AppIcon {
                    anchors.centerIn: parent
                    size: Math.round(22 * Theme.dockScale)
                    name: mbtn.modelData.icon
                }
            }
        }
    }
}
