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
            readonly property bool focused: g.wins.some(w => w.activated && !w.minimized)
            property bool launching: false

            active: focused
            onRunningChanged: if (running) launching = false

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
                } else if (g.wins.length === 1) {
                    Wm.toggle(g.wins[0]);
                } else {
                    // varias ventanas: enfocar la siguiente
                    let idx = -1;
                    for (let i = 0; i < g.wins.length; i++) {
                        if (g.wins[i].activated) { idx = i; break; }
                    }
                    if (idx >= 0)
                        g.wins[(idx + 1) % g.wins.length].activate();
                    else
                        g.wins[0].activate();
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
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                size: Math.round(28 * Theme.dockScale)
                name: btn.g.icon
                opacity: btn.running && btn.g.wins.every(w => w.minimized) ? 0.6 : 1
                // rebote mientras la app abre
                SequentialAnimation on anchors.verticalCenterOffset {
                    running: btn.launching
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: -9; duration: 260; easing.type: Easing.OutQuad }
                    NumberAnimation { to: -2; duration: 300; easing.type: Easing.OutBounce }
                }
                scale: btn.hovered && !btn.pressed ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }
            }

            // Indicador: punto si está abierta, raya con degradado si está activa
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                visible: btn.running
                width: btn.focused ? 18 : btn.g.wins.length > 1 ? 10 : 6
                height: 3
                radius: 1.5
                color: Theme.fgMuted
                gradient: btn.focused ? brand : null
                Behavior on width { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                Gradient {
                    id: brand
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.brandCyan }
                    GradientStop { position: 0.5; color: Theme.brandIndigo }
                    GradientStop { position: 1; color: Theme.brandViolet }
                }
            }
        }
    }
}
