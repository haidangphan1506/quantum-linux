import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Apps fijadas + abiertas, agrupadas por app como en Windows.
// Clic: abrir / enfocar / minimizar (o elegir ventana si hay varias).
// Clic central: nueva ventana. Clic derecho: menú.
// En el dock vertical (izquierda / derecha) las apps van en columna.
GridLayout {
    id: root

    required property var dock
    readonly property bool vertical: dock.vertical
    // hacia afuera del dock (el lado del borde): -1 = izquierda o arriba, +1 = derecha o abajo
    readonly property real outSign: dock.pos === "bottom" || dock.pos === "left" ? -1 : 1
    flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    // en vertical (TopToBottom) «rows» es cuántos elementos caben en la columna: todos los de la barra
    rows: vertical ? itemCount : 1
    columns: vertical ? 0 : itemCount
    rowSpacing: 2
    columnSpacing: 2
    function buttonAt(i: int): Item { return rep.itemAt(i); }
    // elementos de la fila: botones de apps + divisor y minimizadas (GridLayout necesita el conteo)
    readonly property int itemCount: Math.max(1, rep.count + (minRep.count > 0 ? minRep.count + 1 : 0))
    // posición del mouse a lo largo de la barra, en coordenadas de esta fila (para la magnificación según la distancia)
    readonly property real pointerRow: {
        if (dock.pointerPos < 0) return -1e6;
        const p = vertical ? mapFromItem(dock.cardItem, 0, dock.pointerPos) : mapFromItem(dock.cardItem, dock.pointerPos, 0);
        return vertical ? p.y : p.x;
    }

    // Arrastre para reordenar: índice que se arrastra, cuánto se movió a lo largo de la barra y a qué posición caería
    property int dragFrom: -1
    property real dragAlong: 0
    // Arrastrar una app fijada hacia afuera de la barra la quita de la barra (como macOS)
    property real dragCross: 0
    property bool dragPinned: false
    readonly property real dragOut: outSign * dragCross
    readonly property real unpinDist: Math.round(60 * Theme.dockScale)
    readonly property bool unpinning: dragFrom >= 0 && dragPinned && dragOut > unpinDist
    readonly property real slot: (rep.itemAt(0) ? (vertical ? rep.itemAt(0).height : rep.itemAt(0).width) : 46) + (vertical ? rowSpacing : columnSpacing)
    readonly property int dragTo: dragFrom < 0 ? -1 : Math.max(0, Math.min(rep.count - 1, dragFrom + Math.round(dragAlong / slot)))

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
            // posicion del icono para el efecto genie (solo el dock de la pantalla principal)
            property string regId: ""
            Component.onCompleted: if (root.dock.modelData === Quickshell.screens[0]) { regId = g.id; DockTargets.register(regId, btn); }
            Component.onDestruction: DockTargets.unregister(regId, btn)

            active: focused
            flat: true
            // divisor entre las apps fijadas y las que solo estan abiertas (como macOS)
            readonly property bool firstUnpinned: index > 0 && !g.pinned && Wm.groups[index - 1].pinned
            Layout.leftMargin: firstUnpinned && !root.vertical ? 12 : 0
            Layout.topMargin: firstUnpinned && root.vertical ? 12 : 0
            Rectangle {
                visible: btn.firstUnpinned
                x: root.vertical ? (btn.width - width) / 2 : -7
                y: root.vertical ? -7 : (btn.height - height) / 2
                width: root.vertical ? Math.round(34 * Theme.dockScale) : 1
                height: root.vertical ? 1 : Math.round(34 * Theme.dockScale)
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
            // al soltar fuera de la barra, una app fijada se quita; si no, se reordena
            opacity: btn.index === root.dragFrom && root.unpinning ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            onDragMoved: (dx, dy) => {
                root.dragFrom = index;
                root.dragAlong = root.vertical ? dy : dx;
                root.dragCross = root.vertical ? dx : dy;
                root.dragPinned = g.pinned;
                root.dock.closeMenu(); root.dock.hoverGroup = null;
            }
            onDropped: {
                const to = root.dragTo;
                const unpin = root.unpinning;
                root.dragFrom = -1; root.dragAlong = 0; root.dragCross = 0; root.dragPinned = false;
                if (unpin) Wm.togglePin(g.id);
                else if (to !== index) Wm.moveGroup(g.id, to);
            }
            transform: Translate {
                // desplazamiento a lo largo de la barra (reordenar)
                readonly property real along: {
                    if (root.dragFrom < 0) return 0;
                    if (btn.index === root.dragFrom) return root.dragAlong;
                    const f = root.dragFrom, t = root.dragTo;
                    if (f < t && btn.index > f && btn.index <= t) return -root.slot;
                    if (f > t && btn.index < f && btn.index >= t) return root.slot;
                    return 0;
                }
                // la app arrastrada sigue al mouse también hacia afuera (sin entrar a la barra)
                readonly property real cross: btn.index === root.dragFrom ? root.outSign * Math.max(0, Math.min(2 * root.unpinDist, root.dragOut)) : 0
                x: root.vertical ? cross : along
                y: root.vertical ? along : cross
                Behavior on x { enabled: !btn.dragging && !root.vertical; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !btn.dragging && root.vertical; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
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
                anchors.centerIn: parent
                size: Math.round(38 * Theme.dockScale)
                name: btn.g.icon
                opacity: btn.running && btn.g.wins.every(w => Wm.isMinimized(w)) ? 0.6 : 1
                // como macOS: el icono salta varias veces mientras la app abre, con una pausa entre saltos
                // (el salto se mueve hacia el lado del borde del dock)
                property real lift: 0
                transform: Translate {
                    x: root.dock.pos === "left" ? -icon.lift : root.dock.pos === "right" ? icon.lift : 0
                    y: root.dock.pos === "bottom" ? -icon.lift : root.dock.pos === "top" ? icon.lift : 0
                }
                SequentialAnimation on lift {
                    running: btn.launching
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: Math.round(16 * Theme.dockScale); duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 0; duration: 260; easing.type: Easing.OutBounce }
                    NumberAnimation { to: Math.round(8 * Theme.dockScale); duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 0; duration: 200; easing.type: Easing.OutBounce }
                    PauseAnimation { duration: 500 }
                }
                // magnificación continua: cuanto más cerca del mouse, más grande (suavizado de Hermite),
                // así el icono crece y se achica mientras el mouse pasa de una app a otra
                readonly property real near: {
                    const c = root.vertical ? btn.y + btn.height / 2 : btn.x + btn.width / 2;
                    const d = Math.abs(c - root.pointerRow);
                    const t = Math.max(0, 1 - d / (Math.round(130 * Theme.dockScale)));
                    return t * t * (3 - 2 * t);
                }
                transformOrigin: root.dock.edgeOrigin
                scale: (1 + 0.55 * near) * (btn.pressed ? 0.92 : 1)
                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            }

            // Indicador como en macOS: un punto en el borde del dock si la app está abierta
            Rectangle {
                anchors.bottom: root.dock.pos === "bottom" ? parent.bottom : undefined
                anchors.top: root.dock.pos === "top" ? parent.top : undefined
                anchors.left: root.dock.pos === "left" ? parent.left : undefined
                anchors.right: root.dock.pos === "right" ? parent.right : undefined
                anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
                anchors.margins: 2
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

    // Ventanas minimizadas: a la derecha (abajo, en vertical) de un divisor, un icono por ventana (clic = restaurar)
    Rectangle {
        visible: Wm.minimizedItems.length > 0
        Layout.leftMargin: root.vertical ? 0 : 6
        Layout.rightMargin: root.vertical ? 0 : 4
        Layout.topMargin: root.vertical ? 6 : 0
        Layout.bottomMargin: root.vertical ? 4 : 0
        implicitWidth: root.vertical ? Math.round(34 * Theme.dockScale) : 1
        implicitHeight: root.vertical ? 1 : Math.round(34 * Theme.dockScale)
        color: Theme.alpha(Theme.fg, 0.2)
    }
    Repeater {
        id: minRep
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
                anchors.centerIn: parent
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
