import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components

// Barra de tareas abajo, al estilo de Windows 11 con el toque de Quantum:
// Inicio y Buscar, apps fijadas y abiertas. Encima se dibujan el nombre de la app
// al pasar el mouse y el menú del clic derecho (en la misma superficie).
// Personalizar elige: flotante o pegada, apps centradas o a la izquierda, tamaño,
// ocultar automáticamente y el modo «una sola barra» (con bandeja, hora y apagado).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: dock

        required property ShellScreen modelData
        // se esconde con juegos o videos a pantalla completa
        readonly property bool shown: !(Wm.active?.fullscreen ?? false)

        // Aspecto (Personalizar)
        readonly property bool single: !Serp.on && Settings.layout.style === "single"
        readonly property bool floating: Serp.on || Settings.dock.floating
        readonly property bool full: single || !floating          // ocupa todo el ancho
        readonly property int barH: Math.round(56 * Theme.dockScale)
        readonly property int gap: floating ? 10 : 0
        readonly property bool alignLeft: !Serp.on && Settings.dock.align === "left"
        // Ocultar automáticamente: se asoma al llevar el mouse al borde de abajo
        readonly property bool autohide: Settings.dock.autohide
        property bool hovering: false
        readonly property bool revealed: !autohide || hovering || popup || Shell.launcherOpen

        // Estado del globo (nombre o lista de ventanas) y del menú contextual
        property var hoverGroup: null
        property Item hoverItem: null
        property var menuGroup: null
        property Item menuItem: null
        function closeMenu(): void { menuGroup = null; menuItem = null; }
        function scheduleHide(): void { hideTimer.restart(); }
        function cancelHide(): void { hideTimer.stop(); }

        screen: modelData
        visible: shown || card.opacity > 0.01
        WlrLayershell.namespace: "quantum-dock"
        WlrLayershell.layer: WlrLayer.Top
        anchors { bottom: true; left: true; right: true }
        // La ventana tiene SIEMPRE el mismo alto (cambiarlo hacía que la barra saltara
        // un instante hacia arriba al mostrar el globo). Lo transparente no se come
        // los clics: la máscara de abajo solo deja pasar el mouse a la barra, el globo
        // y el menú.
        readonly property bool popup: (hoverGroup !== null && hoverItem !== null) || menuGroup !== null
        implicitHeight: 360
        exclusiveZone: shown && !autohide ? barH + gap + (floating ? 4 : 0) : 0
        color: "transparent"
        mask: Region {
            item: dock.menuGroup !== null ? catcher : dock.revealed ? cardArea : peek
            Region { item: dock.popup && dock.menuGroup === null ? bubble : null }
        }

        // Zona de clics de la barra: la misma caja que la tarjeta pero SIN su animación.
        // La máscara no se recalcula cuando cambia un transform: si usara la tarjeta,
        // al desactivar «Ocultar automáticamente» quedaba calculada con la barra abajo,
        // fuera de la pantalla, y los clics no llegaban a las apps.
        Item {
            id: cardArea
            x: card.x
            y: card.y
            width: card.width
            height: card.height
        }

        // franja invisible de 3 px para asomar la barra oculta
        Item {
            id: peek
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            // al asomarse, se vuelve a esconder sola salvo que el mouse suba a la barra
            HoverHandler { onHoveredChanged: if (hovered) { dock.hovering = true; revealTimer.interval = 1500; revealTimer.restart(); } }
        }
        Timer {
            id: revealTimer
            interval: 700
            onTriggered: dock.hovering = false
        }

        // Para probar sin mouse: qs ipc call dock hover|menu <n>
        IpcHandler {
            target: "dock"
            enabled: dock.modelData === Quickshell.screens[0]
            function hover(i: int): void { const b = taskbar.buttonAt(i); dock.hoverItem = b; dock.hoverGroup = b?.g ?? null; }
            function menu(i: int): void { const b = taskbar.buttonAt(i); dock.menuItem = b; dock.menuGroup = b?.g ?? null; }
            function click(i: int): void { taskbar.buttonAt(i)?.clicked(); }
            function launch(i: int): void { taskbar.buttonAt(i)?.middleClicked(); }
            function clear(): void { dock.closeMenu(); dock.hoverGroup = null; dock.hoverItem = null; }
        }

        // Clic fuera del menú: lo cierra
        MouseArea {
            id: catcher
            anchors.fill: parent
            visible: dock.menuGroup !== null
            onClicked: dock.closeMenu()
        }

        Card {
            id: card
            anchors.bottom: parent.bottom
            anchors.bottomMargin: dock.gap
            x: dock.full ? dock.gap : (parent.width - width) / 2
            width: dock.full ? parent.width - 2 * dock.gap : row.implicitWidth + 16
            height: dock.barH
            radius: dock.floating ? Math.round(20 * Theme.dockScale) * Theme.radius / 16 : 0
            color: Theme.alpha(Theme.surface, Math.min(0.97, Theme.glassOpacity("dock") + 0.04))
            border.width: dock.floating ? 1 : 0
            opacity: dock.shown ? 1 : 0
            transform: Translate {
                y: dock.shown && dock.revealed ? 0 : dock.barH + dock.gap + 6
                Behavior on y { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
            Behavior on width { enabled: !dock.full; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) { revealTimer.stop(); dock.hovering = true; }
                    else { revealTimer.interval = 700; revealTimer.restart(); }
                }
            }

            // línea superior cuando está pegada
            Rectangle {
                visible: !dock.floating
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.alpha(Theme.fg, 0.08)
            }

            // brillo superior con los colores de Quantum
            Rectangle {
                visible: dock.floating
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * parent.radius
                height: 1
                opacity: 0.55
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.25; color: Theme.brandCyan }
                    GradientStop { position: 0.5; color: Theme.brandIndigo }
                    GradientStop { position: 0.75; color: Theme.brandViolet }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            RowLayout {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                x: !dock.full ? 8 : dock.alignLeft ? 8 : Math.max(8, (card.width - width) / 2)
                Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                spacing: 2

                DockButton {
                    visible: Settings.dock.showStart && !Serp.on
                    tip: "Inicio"
                    active: Shell.launcherOpen && !Shell.clipboardMode
                    onClicked: Shell.toggleLauncher(false)
                    Image {
                        anchors.centerIn: parent
                        width: Math.round(28 * Theme.dockScale); height: width
                        source: Quickshell.shellDir + "/assets/quantum-mark.svg"
                        sourceSize: Qt.size(56, 56)
                        rotation: parent.hovered ? 30 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutBack } }
                    }
                }
                DockButton {
                    visible: Settings.dock.showSearch && !Serp.on
                    tip: "Buscar"
                    onClicked: Shell.toggleLauncher(false)
                    Icon { anchors.centerIn: parent; text: "search"; size: Math.round(24 * Theme.dockScale); color: Theme.fg }
                }
                Rectangle {
                    visible: (Settings.dock.showStart || Settings.dock.showSearch) && !Serp.on
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    implicitWidth: 1
                    implicitHeight: 28
                    color: Theme.alpha(Theme.fg, 0.14)
                }
                Taskbar { id: taskbar; dock: dock }
            }

            // Modo «una sola barra»: bandeja, estado, hora y apagado a la derecha
            SystemArea {
                visible: dock.single
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                window: dock
                compact: dock.width < 1300
            }
        }

        // ------------------------------------------------ globo al pasar el mouse
        Card {
            id: bubble
            readonly property var g: dock.hoverGroup
            readonly property bool many: g !== null && g.wins.length > 1
            visible: g !== null && dock.menuGroup === null && dock.hoverItem !== null
            x: dock.hoverItem ? Math.max(8, Math.min(dock.width - width - 8,
                   dock.hoverItem.mapToItem(dock.contentItem, dock.hoverItem.width / 2, 0).x - width / 2)) : 0
            anchors.bottom: card.top
            anchors.bottomMargin: 8
            radius: Theme.radius
            color: Theme.alpha(Theme.surfaceHigh, 0.97)
            implicitWidth: bubbleCol.implicitWidth + 20
            implicitHeight: bubbleCol.implicitHeight + 16
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

            ColumnLayout {
                id: bubbleCol
                anchors.centerIn: parent
                spacing: 2
                Txt {
                    visible: !bubble.many
                    text: bubble.g ? (bubble.g.wins.length === 1 && bubble.g.wins[0].title ? bubble.g.wins[0].title : bubble.g.name) : ""
                    font.weight: Font.DemiBold
                    Layout.maximumWidth: 320
                    elide: Text.ElideRight
                }
                // varias ventanas: lista para elegir una, como en Windows
                Repeater {
                    model: bubble.many ? bubble.g.wins : []
                    Rectangle {
                        id: winRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitWidth: Math.min(340, winTitle.implicitWidth + 60)
                        implicitHeight: 36
                        radius: Theme.radiusSmall
                        color: winArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            AppIcon { size: 18; name: Wm.iconFor(winRow.modelData.appId) }
                            Txt {
                                id: winTitle
                                Layout.fillWidth: true
                                text: winRow.modelData.title || bubble.g.name
                                elide: Text.ElideRight
                                font.weight: winRow.modelData.activated ? Font.Bold : Font.Normal
                            }
                        }
                        MouseArea {
                            id: winArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hideTimer.stop()
                            onExited: hideTimer.restart()
                            onClicked: { winRow.modelData.activate(); dock.hoverGroup = null; }
                        }
                    }
                }
            }
            HoverHandler {
                onHoveredChanged: hovered ? hideTimer.stop() : hideTimer.restart()
            }
        }
        Timer {
            id: hideTimer
            interval: 220
            onTriggered: { dock.hoverGroup = null; dock.hoverItem = null; }
        }

        // ------------------------------------------------------ menú (clic derecho)
        Card {
            id: menu
            readonly property var g: dock.menuGroup
            visible: g !== null && dock.menuItem !== null
            x: dock.menuItem ? Math.max(8, Math.min(dock.width - width - 8,
                   dock.menuItem.mapToItem(dock.contentItem, dock.menuItem.width / 2, 0).x - width / 2)) : 0
            anchors.bottom: card.top
            anchors.bottomMargin: 8
            radius: Theme.radius
            color: Theme.alpha(Theme.surfaceHigh, 0.98)
            implicitWidth: 240
            implicitHeight: menuCol.implicitHeight + 12

            ColumnLayout {
                id: menuCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 2

                RowLayout {
                    Layout.margins: 8
                    spacing: 10
                    AppIcon { size: 22; name: menu.g ? menu.g.icon : "" }
                    Txt { Layout.fillWidth: true; text: menu.g ? menu.g.name : ""; font.weight: Font.Bold; elide: Text.ElideRight }
                }
                Repeater {
                    model: menu.g ? [
                        { icon: "add", text: "Nueva ventana", show: !!menu.g.entry, run: () => Apps.launch(menu.g.entry) },
                        { icon: menu.g.pinned ? "keep_off" : "keep", text: menu.g.pinned ? "Quitar de la barra" : "Fijar en la barra",
                          show: !!menu.g.entry, run: () => Wm.togglePin(menu.g.id) },
                        { icon: "close", text: menu.g.wins.length > 1 ? "Cerrar todas las ventanas" : "Cerrar ventana",
                          show: menu.g.wins.length > 0, run: () => menu.g.wins.forEach(w => w.close()) },
                    ].filter(o => o.show) : []
                    Rectangle {
                        id: opt
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Theme.radiusSmall
                        color: optArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            spacing: 12
                            Icon { text: opt.modelData.icon; size: 20; color: Theme.fg }
                            Txt { Layout.fillWidth: true; text: opt.modelData.text }
                        }
                        MouseArea {
                            id: optArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { opt.modelData.run(); dock.closeMenu(); }
                        }
                    }
                }
            }
        }
    }
}
