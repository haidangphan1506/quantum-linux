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
        readonly property bool floating: Settings.dock.floating
        readonly property bool full: !floating          // ocupa todo el borde
        // Como el dock de macOS: barra alta en forma de píldora, con iconos grandes
        readonly property int barH: Math.round(64 * Theme.dockScale)
        // posición del mouse sobre la barra (-1 fuera) a lo largo de la barra: los iconos crecen según la distancia
        readonly property real pointerPos: cardHover.hovered ? (vertical ? cardHover.point.position.y : cardHover.point.position.x) : -1
        readonly property Item cardItem: card
        readonly property int gap: floating ? 8 : 0
        // «A la izquierda» (en vertical: arriba): las apps se alinean al principio de la barra
        readonly property bool alignLeft: Settings.dock.align === "left"
        // lado de la pantalla hacia el que se dibuja el icono al crecer (el lado del borde)
        readonly property int edgeOrigin: pos === "top" ? Item.Top : pos === "left" ? Item.Left : pos === "right" ? Item.Right : Item.Bottom
        // Ocultar automáticamente: se asoma al llevar el mouse al borde
        readonly property bool autohide: Settings.dock.autohide
        property bool hovering: false
        // también mientras se arrastra un icono (si no, al sacarlo de la barra para quitarlo se escondía)
        // también mientras se arrastra un icono (o un stack), con un stack abierto o mientras se suelta un archivo encima
        readonly property bool revealed: !autohide || hovering || popup || Shell.clipboardOpen || taskbar.dragFrom >= 0
                                         || stackDrag || stackOpen || dropping

        // ---- Stacks: archivos y carpetas fijados junto a la papelera (como macOS)
        property bool stackDrag: false
        readonly property bool stackOpen: stackPopup.visible
        function openStack(item: Item, path: string, title: string): void { closeMenu(); hoverGroup = null; stackPopup.openStack(item, path, title); }
        function openStackMenu(item: Item): void { closeMenu(); hoverGroup = null; stackPopup.openMenu(item); }
        function removeStack(path: string): void { Settings.setStacks((Settings.dock.stacks ?? []).filter(p => p !== path)); }

        // Soltar archivos o carpetas desde el gestor de archivos (Thunar, Nautilus…) sobre el dock: se fijan.
        // Se acepta como COPIA: con «mover» el gestor de archivos podría borrar el original.
        readonly property bool dropping: cardDrop.containsDrag || peekDrop.containsDrag || dropHold.running
        Timer { id: dropHold; interval: 600 }   // el hueco entre la franja del borde y la barra no la esconde
        function dropPaths(urls: var): var {
            const out = [];
            for (const u of urls ?? []) {
                let s = String(u);
                if (!s.startsWith("file://")) continue;
                s = s.slice(7);
                if (!s.startsWith("/")) s = s.slice(s.indexOf("/"));   // file://host/ruta
                try { s = decodeURIComponent(s); } catch (e) {}
                if (s.length > 1) s = s.replace(/\/+$/, "");
                if (s && !out.includes(s)) out.push(s);
            }
            return out;
        }
        function dropEnter(drag: var): void {
            if (!drag.hasUrls || dropPaths(drag.urls).length === 0) { drag.accepted = false; return; }
            drag.accept(Qt.CopyAction);
        }
        function dropDone(drop: var): void {
            dropHold.stop();
            const paths = dropPaths(drop.urls);
            if (paths.length === 0) { drop.accepted = false; return; }
            drop.accept(Qt.CopyAction);
            addStacks(paths);
        }
        function addStacks(paths: var): void {
            const list = (Settings.dock.stacks ?? []).slice();
            for (const p of paths)
                if (p && !list.includes(p) && p !== downloads.path) list.push(p);
            Settings.setStacks(list);
        }

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
        readonly property int topInset: Settings.layout.topBar.floating ? 54 : 30
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
        // Al activar / desactivar «Ocultar automáticamente» cambia la zona de trabajo: las ventanas
        // que estaban a pantalla completa se ajustan a la nueva (minimize.lua: cael_refit).
        property int lastZone: exclusiveZone
        onExclusiveZoneChanged: {
            if (modelData !== Quickshell.screens[0]) { lastZone = exclusiveZone; return; }
            refitTimer.delta = exclusiveZone - lastZone;
            refitTimer.side = pos;
            lastZone = exclusiveZone;
            if (refitTimer.delta !== 0) refitTimer.restart();
        }
        Timer {
            id: refitTimer
            property int delta: 0
            property string side: "bottom"
            interval: 350
            onTriggered: Quickshell.execDetached(["hyprctl", "eval", "cael_refit('" + side + "', " + delta + ")"])
        }
        color: "transparent"
        mask: Region {
            item: dock.menuGroup !== null ? catcher : dock.revealed ? cardArea : peek
            Region { item: dock.popup && dock.menuGroup === null ? bubble : null }
            // mientras se arrastra un archivo, también la franja del borde (para no perder el arrastre al asomarse)
            Region { item: dock.dropping ? peek : null }
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
            // un archivo arrastrado hasta el borde también asoma la barra
            DropArea {
                id: peekDrop
                anchors.fill: parent
                onEntered: drag => dock.dropEnter(drag)
                onExited: dropHold.restart()
                onDropped: drop => dock.dropDone(drop)
            }
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
            // stack de Descargas: abanico o menú del clic derecho; stackClose lo cierra
            function stack(): void { dock.openStack(downloads, downloads.path, downloads.label); }
            function stackMenu(): void { dock.openStackMenu(downloads); }
            function stackClose(): void { stackPopup.close(); }
            // fijar un archivo o carpeta como si se soltara sobre el dock
            function pin(path: string): void { dock.addStacks([path]); }
            function unpin(path: string): void { dock.removeStack(path); }
            // clic en el stack fijado número i (0 = el primero)
            function stackClick(i: int): void { stackRep.itemAt(i)?.clicked(); }
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
            width: dock.vertical ? dock.barH : (dock.full ? parent.width - 2 * dock.gap : row.implicitWidth + 12)
            height: dock.vertical ? (dock.full ? parent.height - 2 * dock.gap : row.implicitHeight + 16) : dock.barH
            x: dock.vertical ? (dock.pos === "left" ? dock.gap : parent.width - width - dock.gap)
                             : (dock.full ? dock.gap : (parent.width - width) / 2)
            y: dock.vertical ? (dock.full ? dock.gap : (parent.height - height) / 2)
                             : (dock.pos === "top" ? dock.gap : parent.height - height - dock.gap)
            // bo góc kiểu macOS: hình chữ nhật bo ~34% chiều cao (không phải viên thuốc)
            radius: dock.floating ? Math.round(dock.barH * 0.34) : 0
            // Vidrio como el dock de macOS: tinte NEUTRO (blanco, no el color del tema), muy
            // translucido; el blur de Hyprland (layer quantum-dock) hace el resto.
            color: Theme.dark ? Qt.rgba(0.82, 0.82, 0.86, 0.08) : Qt.rgba(1, 1, 1, 0.16)
            border.width: dock.floating ? 1 : 0
            // borde de luz: un reflejo blanco fino alrededor del vidrio
            border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.65)
            // reflejo interior: luz suave arriba que se desvanece abajo (como el vidrio de macOS)
            Rectangle {
                visible: dock.floating
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.06 : 0.12) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.02) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.04 : 0.08) }
                }
            }
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

            // Apps en fila (horizontal) o en columna (vertical)
            readonly property bool startShown: Settings.dock.showStart
            readonly property bool searchShown: Settings.dock.showSearch
            readonly property bool dividerShown: (Settings.dock.showStart || Settings.dock.showSearch)
            readonly property bool downloadsShown: Settings.dock.showDownloads
            readonly property bool dropSlotShown: cardDrop.containsDrag
            // elementos visibles de la fila (Inicio, Buscar, divisor, las apps, divisor, stacks, hueco al soltar,
            // descargas y papelera): GridLayout necesita el conteo
            readonly property int itemCount: Math.max(1, (startShown ? 1 : 0) + (searchShown ? 1 : 0) + (dividerShown ? 1 : 0) + 1 + 2
                                                         + stackRep.count + (dropSlotShown ? 1 : 0) + (downloadsShown ? 1 : 0))

            // soltar archivos o carpetas encima de la barra: se fijan junto a la papelera
            DropArea {
                id: cardDrop
                anchors.fill: parent
                onEntered: drag => dock.dropEnter(drag)
                onExited: dropHold.restart()
                onDropped: drop => dock.dropDone(drop)
            }
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
                    visible: Settings.dock.showStart
                    tip: "Launchpad"
                    active: Shell.launchpadOpen
                    // abre la cuadrícula de apps a pantalla completa (modules/launchpad); otro clic la cierra
                    onClicked: Shell.launchpadRequest(Shell.launchpadOpen ? "close" : "open")
                    // icono de Launchpad de macOS: cuadro gris con la cuadrícula de colores
                    Image {
                        anchors.centerIn: parent
                        width: Math.round(38 * Theme.dockScale); height: width
                        source: Quickshell.shellDir + "/assets/quantum-launchpad.svg"
                        sourceSize: Qt.size(128, 128)
                        smooth: true
                    }
                }
                DockButton {
                    visible: Settings.dock.showSearch
                    tip: I18n.t("Buscar")
                    onClicked: Shell.toggleSpotlight()
                    AppIcon { anchors.centerIn: parent; name: "system-search"; fallback: ""; glyph: "search"; size: Math.round(38 * Theme.dockScale) }
                }
                Rectangle {
                    visible: (Settings.dock.showStart || Settings.dock.showSearch)
                    Layout.leftMargin: dock.vertical ? 0 : 4
                    Layout.rightMargin: dock.vertical ? 0 : 4
                    Layout.topMargin: dock.vertical ? 4 : 0
                    Layout.bottomMargin: dock.vertical ? 4 : 0
                    implicitWidth: dock.vertical ? 28 : 1
                    implicitHeight: dock.vertical ? 1 : 28
                    color: Theme.alpha(Theme.fg, 0.14)
                }
                Taskbar { id: taskbar; dock: dock }
                // divisor y papelera al final, como en macOS (mismo estilo que el divisor de la barra de tareas)
                Rectangle {
                    Layout.leftMargin: dock.vertical ? 0 : 6
                    Layout.rightMargin: dock.vertical ? 0 : 4
                    Layout.topMargin: dock.vertical ? 6 : 0
                    Layout.bottomMargin: dock.vertical ? 4 : 0
                    implicitWidth: dock.vertical ? Math.round(34 * Theme.dockScale) : 1
                    implicitHeight: dock.vertical ? 1 : Math.round(34 * Theme.dockScale)
                    color: Theme.alpha(Theme.fg, 0.2)
                }
                // archivos y carpetas fijados (soltados desde el gestor de archivos)
                Repeater {
                    id: stackRep
                    model: Settings.dock.stacks ?? []
                    // dentro del delegado «dock: dock» se referiría a su propia propiedad (undefined):
                    // se pasa la ventana por aquí
                    readonly property var dockWindow: dock
                    StackButton {
                        required property var modelData
                        dock: stackRep.dockWindow
                        path: modelData
                        onRemoveRequested: dock.removeStack(modelData)
                    }
                }
                // hueco donde caerá lo que se está soltando
                Rectangle {
                    visible: card.dropSlotShown
                    implicitWidth: Math.round(50 * Theme.dockScale)
                    implicitHeight: Math.round(50 * Theme.dockScale)
                    radius: Theme.radiusSmall
                    color: Theme.alpha(Theme.primary, 0.15)
                    border.width: 2
                    border.color: Theme.alpha(Theme.primary, 0.7)
                    Icon { anchors.centerIn: parent; text: "add"; size: Math.round(26 * Theme.dockScale); color: Theme.primary }
                }
                // carpeta de descargas al lado de la papelera, como macOS (un stack más)
                DownloadsButton { id: downloads; dock: dock; visible: card.downloadsShown }
                TrashButton {}
            }
        }

        // abanico de un stack (y su menú del clic derecho): capa propia, más alta que el dock
        StackPopup { id: stackPopup; dock: dock }

        // ------------------------------------------------ globo al pasar el mouse
        Card {
            id: bubble
            readonly property var g: dock.hoverGroup
                        visible: g !== null && dock.menuGroup === null && dock.hoverItem !== null
            x: dock.hoverItem ? dock.popupX(dock.hoverItem, width) : 0
            y: dock.hoverItem ? dock.popupY(dock.hoverItem, height) : 0
            radius: Theme.radius
            color: Theme.glassPanel
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
            color: Theme.glassPanel
            implicitWidth: 240
            implicitHeight: menuCol.implicitHeight + 12

            ColumnLayout {
                id: menuCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 2

                // encabezado: clic = alternar 3/4 de pantalla <-> completa (si la app tiene ventanas)
                Rectangle {
                    id: head
                    readonly property bool hasWins: menu.g !== null && menu.g.wins.length > 0
                    Layout.fillWidth: true
                    implicitHeight: headRow.implicitHeight + 16
                    radius: Theme.radiusSmall
                    color: headArea.containsMouse && hasWins ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                    RowLayout {
                        id: headRow
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10
                        AppIcon { size: 22; name: menu.g ? menu.g.icon : "" }
                        Txt { Layout.fillWidth: true; text: menu.g ? menu.g.name : ""; font.weight: Font.Bold; elide: Text.ElideRight }
                    }
                    MouseArea {
                        id: headArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: head.hasWins ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (head.hasWins) Wm.toggleSizeGroup(menu.g);
                            dock.closeMenu();
                        }
                    }
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
