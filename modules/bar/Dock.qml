import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components

// Barra de tareas con el toque de Quantum: Inicio y Buscar, apps fijadas y abiertas.
// Puede ir en cualquier borde (abajo, arriba, izquierda o derecha; Personalizar).
// Encima se dibujan el nombre de la app al pasar el mouse y el menú del clic derecho
// (en la misma superficie).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: dock

        required property ShellScreen modelData
        // se esconde con juegos o videos a pantalla completa
        readonly property bool shown: !(Wm.active?.fullscreen ?? false)

        // Borde donde está el dock (Personalizar)
        readonly property string pos: ["bottom", "top", "left", "right"].includes(Settings.dock.position) ? Settings.dock.position : "bottom"
        readonly property bool vertical: pos === "left" || pos === "right"

        // Aspecto (Personalizar)
        // «una sola barra» (bandeja y reloj dentro del dock) solo existe abajo
        readonly property bool single: !Serp.on && Settings.layout.style === "single" && pos === "bottom"
        readonly property bool floating: Serp.on || Settings.dock.floating
        readonly property bool full: single || !floating          // ocupa todo el borde
        // Como el dock de macOS: barra alta en forma de píldora, con iconos grandes
        readonly property int barH: Math.round(56 * Theme.dockScale)
        // posición del mouse sobre la barra (-1 fuera) a lo largo de la barra: los iconos crecen según la distancia
        readonly property real pointerPos: cardHover.hovered ? (vertical ? cardHover.point.position.y : cardHover.point.position.x) : -1
        readonly property Item cardItem: card
        readonly property int gap: floating ? 8 : 0
        // «A la izquierda» (en vertical: arriba): las apps se alinean al principio de la barra
        readonly property bool alignLeft: !Serp.on && Settings.dock.align === "left"
        // lado de la pantalla hacia el que se dibuja el icono al crecer (el lado del borde)
        readonly property int edgeOrigin: pos === "top" ? Item.Top : pos === "left" ? Item.Left : pos === "right" ? Item.Right : Item.Bottom
        // Ocultar automáticamente: se asoma al llevar el mouse al borde
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

        // Posición de un globo o menú junto a un icono: al lado del borde (vertical) o
        // encima / debajo de la barra (horizontal). Siempre dentro de la pantalla.
        function popupX(item: Item, w: real): real {
            if (vertical) return pos === "left" ? card.x + card.width + 8 : card.x - w - 8;
            const c = item.mapToItem(contentItem, item.width / 2, item.height / 2);
            return Math.max(8, Math.min(width - w - 8, c.x - w / 2));
        }
        function popupY(item: Item, h: real): real {
            if (!vertical) return pos === "top" ? card.y + card.height + 8 : card.y - h - 8;
            const c = item.mapToItem(contentItem, item.width / 2, item.height / 2);
            return Math.max(8, Math.min(height - h - 8, c.y - h / 2));
        }

        // Alto de la barra de arriba (el dock arriba/izquierda/derecha queda debajo de ella)
        readonly property int topInset: !Serp.on && (Settings.layout.style !== "single" || pos !== "bottom")
                                        ? (Settings.layout.topBar.floating ? 54 : 30) : 0
        // Punto de un item del dock en coordenadas de pantalla, como si el dock estuviera visible
        // (para el efecto genie: DockTargets). Se mide respecto a la tarjeta sin su transform.
        function screenPoint(item: Item, px: real, py: real): point {
            const q = item.mapToItem(card, px, py);
            const ox = pos === "right" ? dock.screen.width - dock.width : 0;
            const oy = pos === "bottom" ? dock.screen.height - dock.height : topInset;
            return Qt.point(ox + card.x + q.x, oy + card.y + q.y);
        }
        Component.onCompleted: if (modelData === Quickshell.screens[0]) { DockTargets.dock = dock; DockTargets.taskbar = taskbar; }
        Component.onDestruction: if (DockTargets.dock === dock) { DockTargets.dock = null; DockTargets.taskbar = null; }

        screen: modelData
        visible: shown || card.opacity > 0.01
        WlrLayershell.namespace: "quantum-dock"
        WlrLayershell.layer: WlrLayer.Top
        anchors {
            top: pos !== "bottom"
            bottom: pos !== "top"
            left: pos !== "right"
            right: pos !== "left"
        }
        // La ventana tiene SIEMPRE el mismo tamaño en el eje perpendicular al borde (cambiarlo
        // hacía que la barra saltara un instante al mostrar el globo). Lo transparente no se come
        // los clics: la máscara de abajo solo deja pasar el mouse a la barra, el globo y el menú.
        readonly property bool popup: (hoverGroup !== null && hoverItem !== null) || menuGroup !== null
        implicitWidth: vertical ? 360 : 0
        implicitHeight: vertical ? 0 : 360
        exclusiveZone: shown && !autohide ? barH + gap + (floating ? 4 : 0) : 0
        color: "transparent"
        mask: Region {
            item: dock.menuGroup !== null ? catcher : dock.revealed ? cardArea : peek
            Region { item: dock.popup && dock.menuGroup === null ? bubble : null }
        }

        // Zona de clics de la barra: la misma caja que la tarjeta pero SIN su animación.
        // La máscara no se recalcula cuando cambia un transform: si usara la tarjeta,
        // al desactivar «Ocultar automáticamente» quedaba calculada con la barra fuera de
        // la pantalla, y los clics no llegaban a las apps.
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
            x: dock.pos === "right" ? dock.width - 3 : 0
            y: dock.pos === "bottom" ? dock.height - 3 : 0
            width: dock.vertical ? 3 : dock.width
            height: dock.vertical ? dock.height : 3
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
            width: dock.vertical ? dock.barH : (dock.full ? parent.width - 2 * dock.gap : row.implicitWidth + 16)
            height: dock.vertical ? (dock.full ? parent.height - 2 * dock.gap : row.implicitHeight + 16) : dock.barH
            x: dock.vertical ? (dock.pos === "left" ? dock.gap : parent.width - width - dock.gap)
                             : (dock.full ? dock.gap : (parent.width - width) / 2)
            y: dock.vertical ? (dock.full ? dock.gap : (parent.height - height) / 2)
                             : (dock.pos === "top" ? dock.gap : parent.height - height - dock.gap)
            radius: dock.floating ? Math.min(width, height) / 2 : 0
            // Vidrio como Liquid Glass de macOS Tahoe: bastante transparente para que el blur
            // de Hyprland (layer quantum-dock) se vea detrás. Con el slider de opacidad se ajusta.
            color: Theme.alpha(Theme.surface, Math.max(0.25, Math.min(0.6, Theme.glassOpacity("dock") * 0.55)))
            border.width: dock.floating ? 1 : 0
            // borde de luz: un reflejo blanco fino alrededor del vidrio
            border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.6)
            // Ẩn/hiện al pasar el mouse: un valor 0..1 controla deslizar + opacidad + escala.
            // Hiện: bulle un poco (OutBack cuando flota). Ocultar: más rápido, acelerando (InCubic).
            property real reveal: dock.shown && dock.revealed ? 1 : 0
            // distancia que se desliza hacia su borde mientras está escondida
            readonly property real hideShift: (1 - reveal) * (dock.barH + dock.gap + 6)
            Behavior on reveal {
                NumberAnimation {
                    duration: dock.revealed ? Theme.animSlow : Theme.anim
                    easing.type: dock.revealed ? (dock.floating ? Easing.OutBack : Easing.OutCubic) : Easing.InCubic
                    easing.overshoot: 1.1
                }
            }
            opacity: (dock.shown ? 1 : 0) * Math.max(0, Math.min(1, 0.15 + reveal * 1.2))
            scale: dock.floating ? 0.94 + 0.06 * reveal : 1
            transformOrigin: dock.edgeOrigin
            transform: Translate {
                x: dock.pos === "left" ? -card.hideShift : dock.pos === "right" ? card.hideShift : 0
                y: dock.pos === "bottom" ? card.hideShift : dock.pos === "top" ? -card.hideShift : 0
            }
            Behavior on width { enabled: !dock.full; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: !dock.full; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

            HoverHandler {
                id: cardHover
                onHoveredChanged: {
                    if (hovered) { revealTimer.stop(); dock.hovering = true; }
                    else { revealTimer.interval = 250; revealTimer.restart(); }
                }
            }

            // línea del lado de adentro cuando está pegada
            Rectangle {
                visible: !dock.floating
                anchors.top: dock.pos === "bottom" ? parent.top : undefined
                anchors.bottom: dock.pos === "top" ? parent.bottom : undefined
                anchors.left: dock.pos === "right" ? parent.left : undefined
                anchors.right: dock.pos === "left" ? parent.right : undefined
                width: dock.vertical ? 1 : parent.width
                height: dock.vertical ? parent.height : 1
                color: Theme.alpha(Theme.fg, 0.08)
            }

            // brillo con los colores de Quantum (del lado de adentro)
            Rectangle {
                visible: dock.floating
                anchors.top: dock.pos === "bottom" ? parent.top : undefined
                anchors.bottom: dock.pos === "top" ? parent.bottom : undefined
                anchors.left: dock.pos === "right" ? parent.left : undefined
                anchors.right: dock.pos === "left" ? parent.right : undefined
                anchors.horizontalCenter: dock.vertical ? undefined : parent.horizontalCenter
                anchors.verticalCenter: dock.vertical ? parent.verticalCenter : undefined
                width: dock.vertical ? 1 : parent.width - 2 * parent.radius
                height: dock.vertical ? parent.height - 2 * parent.radius : 1
                opacity: 0.55
                gradient: Gradient {
                    orientation: dock.vertical ? Gradient.Vertical : Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.25; color: Theme.brandCyan }
                    GradientStop { position: 0.5; color: Theme.brandIndigo }
                    GradientStop { position: 0.75; color: Theme.brandViolet }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            // Apps en fila (horizontal) o en columna (vertical)
            readonly property bool startShown: Settings.dock.showStart && !Serp.on
            readonly property bool searchShown: Settings.dock.showSearch && !Serp.on
            readonly property bool dividerShown: (Settings.dock.showStart || Settings.dock.showSearch) && !Serp.on
            // elementos visibles de la fila (Inicio, Buscar, divisor y las apps): GridLayout necesita el conteo
            readonly property int itemCount: Math.max(1, (startShown ? 1 : 0) + (searchShown ? 1 : 0) + (dividerShown ? 1 : 0) + 1)
            GridLayout {
                id: row
                flow: dock.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                // en vertical (TopToBottom) «rows» es cuántos elementos caben en la columna: los visibles
                rows: dock.vertical ? card.itemCount : 1
                columns: dock.vertical ? 0 : card.itemCount
                x: dock.vertical
                    ? (card.width - width) / 2
                    : (!dock.full ? 8 : dock.alignLeft ? 8 : Math.max(8, (card.width - width) / 2))
                y: dock.vertical
                    ? (!dock.full ? 8 : dock.alignLeft ? 8 : Math.max(8, (card.height - height) / 2))
                    : (card.height - height) / 2
                Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                rowSpacing: 6
                columnSpacing: 6

                DockButton {
                    visible: Settings.dock.showStart && !Serp.on
                    tip: I18n.t("Inicio")
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
                    tip: I18n.t("Buscar")
                    onClicked: Shell.toggleLauncher(false)
                    Icon { anchors.centerIn: parent; text: "search"; size: Math.round(24 * Theme.dockScale); color: Theme.fg }
                }
                Rectangle {
                    visible: (Settings.dock.showStart || Settings.dock.showSearch) && !Serp.on
                    Layout.leftMargin: dock.vertical ? 0 : 4
                    Layout.rightMargin: dock.vertical ? 0 : 4
                    Layout.topMargin: dock.vertical ? 4 : 0
                    Layout.bottomMargin: dock.vertical ? 4 : 0
                    implicitWidth: dock.vertical ? 28 : 1
                    implicitHeight: dock.vertical ? 1 : 28
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
                        visible: g !== null && dock.menuGroup === null && dock.hoverItem !== null
            x: dock.hoverItem ? dock.popupX(dock.hoverItem, width) : 0
            y: dock.hoverItem ? dock.popupY(dock.hoverItem, height) : 0
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
                    // como macOS: solo el nombre de la app (las ventanas se listan en el menu)
                    text: bubble.g ? bubble.g.name : ""
                    font.weight: Font.DemiBold
                    Layout.maximumWidth: 320
                    elide: Text.ElideRight
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
            x: dock.menuItem ? dock.popupX(dock.menuItem, width) : 0
            y: dock.menuItem ? dock.popupY(dock.menuItem, height) : 0
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
                // ventanas de la app (como macOS): clic para llevarla al frente
                Repeater {
                    model: menu.g ? menu.g.wins : []
                    Rectangle {
                        id: wrow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Theme.radiusSmall
                        color: wArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                        Txt {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            text: (Wm.isMinimized(wrow.modelData) ? "◦ " : wrow.modelData.activated ? "✓ " : "   ") + (wrow.modelData.title || menu.g.name)
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: wArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Wm.focus(wrow.modelData); dock.closeMenu(); }
                        }
                    }
                }
                Rectangle {
                    visible: menu.g !== null && menu.g.wins.length > 0
                    Layout.fillWidth: true
                    Layout.margins: 4
                    implicitHeight: 1
                    color: Theme.alpha(Theme.fg, 0.12)
                }
                Repeater {
                    model: menu.g ? [
                        { icon: "add", text: I18n.t("Nueva ventana"), show: !!menu.g.entry, run: () => Apps.launch(menu.g.entry) },
                        { icon: menu.g.pinned ? "keep_off" : "keep", text: menu.g.pinned ? I18n.t("Quitar de la barra") : I18n.t("Fijar en la barra"),
                          show: !!menu.g.entry, run: () => Wm.togglePin(menu.g.id) },
                        { icon: "visibility_off", text: I18n.t("Ocultar"),
                          show: menu.g.wins.some(w => !Wm.isMinimized(w)), run: () => menu.g.wins.forEach(w => Wm.minimize(w)) },
                        { icon: "power_settings_new", text: I18n.t("Salir"),
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
