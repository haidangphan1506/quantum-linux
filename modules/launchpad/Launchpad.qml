import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

// Launchpad (como macOS): vuốt 4 ngón lên (o IPC `launchpad toggle`).
//  - Pantalla completa, fondo difuminado (capa quantum-launchpad, blur en decorators.lua).
//  - Buscador pequeño arriba, cuadrícula de apps por páginas y puntos de página abajo.
//  - Cambiar de página: arrastrar, rueda / 2 ngón ngang, ← →, clic en los puntos.
//  - Clic = abrir app, clic derecho = menú (abrir / ocultar). Esc, clic en vacío o
//    vuốt 4 ngón xuống: cerrar.
Scope {
    id: root

    property bool open: false
    property real p: open ? 1 : 0
    Behavior on p { NumberAnimation { duration: Math.max(1, root.open ? Math.round(Theme.animSlow * 1.6) : Theme.anim); easing.type: Easing.OutCubic } }
    readonly property bool shown: open || p > 0.001

    function show(): void {
        if (open) return;
        Shell.closeAll();
        open = true;
    }
    function hide(): void { open = false; }
    function toggle(): void { open ? hide() : show(); }

    // estado para Shell.swipe() y órdenes que llegan desde ahí
    Binding { target: Shell; property: "launchpadOpen"; value: root.open }
    Connections {
        target: Shell
        function onLaunchpadRequest(fn: string): void { fn === "open" ? root.show() : root.hide(); }
    }

    IpcHandler {
        target: "launchpad"
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win

            readonly property var mon: Hyprland.focusedMonitor
            screen: Quickshell.screens.find(s => s.name === mon?.name) ?? Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-launchpad"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore

            readonly property string query: search.text.trim()
            readonly property var results: Apps.search(search.text)

            // pantalla completa (como el Launchpad de macOS) y cuadrícula de 7 x 5
            readonly property real topPad: 210                  // hasta donde empiezan las apps
            readonly property real gridW: Math.min(width - 160, 1400)
            readonly property real gridH: height - topPad - 110
            readonly property int cols: Math.max(4, Math.min(7, Math.floor(gridW / 150)))
            readonly property int rows: Math.max(3, Math.min(4, Math.floor(gridH / 140)))
            readonly property int perPage: cols * rows
            readonly property int pageCount: Math.max(1, Math.ceil(results.length / perPage))
            readonly property real cellW: gridW / cols
            readonly property real cellH: Math.min(gridH / rows, 170)

            // escritorios (workspaces) existentes, como los Spaces de macOS
            readonly property var wsIds: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id).sort((a, b) => a - b)
            readonly property int curWsId: (mon?.activeWorkspace ?? Hyprland.focusedWorkspace)?.id ?? 1
            property int leaveTo: 0
            function gotoWs(id: int): void {
                leaveTo = id;
                root.hide();
                wsTimer.restart();
            }
            Timer {
                id: wsTimer
                interval: 60
                onTriggered: Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = ${win.leaveTo} })`])
            }

            // selección con teclado (índice en results); -1 = ninguna
            property int sel: -1
            // modelo de las casillas: solo cambia si cambia el conjunto de apps o la búsqueda (no al reordenar),
            // así las casillas no se recrean y los demás íconos se deslizan a su nuevo sitio
            property var cellModel: []
            property string cellKey: "(init)"
            function syncCells(): void {
                const key = query + "|" + results.map(a => a.id).sort().join(",");
                if (key === cellKey) return;
                cellKey = key;
                cellModel = results;
            }
            // solo vuelve a la primera página si cambió la búsqueda (no al reordenar con arrastrar)
            property string lastQuery: ""
            onResultsChanged: {
                sel = query !== "" && results.length > 0 ? 0 : -1;
                if (query !== lastQuery) {
                    lastQuery = query;
                    pages.currentIndex = 0;
                } else if (pages.currentIndex > pageCount - 1) {
                    pages.currentIndex = Math.max(0, pageCount - 1);
                }
                syncCells();
            }
            onSelChanged: if (sel >= 0) pages.currentIndex = Math.floor(sel / perPage)

            function launch(app: var): void {
                if (!app) return;
                Apps.launch(app);
                root.hide();
            }

            function goPage(i: int): void {
                pages.currentIndex = Math.max(0, Math.min(pageCount - 1, i));
            }

            // arrastrar para reordenar (solo sin búsqueda: así la lista es la de todas las apps)
            property bool dragging: false
            property bool dragMoved: false
            property bool dropPending: false   // al terminar la animación hay que guardar el orden
            property var dragApp: null
            property int dragIdx: -1           // índice base (en results) de la app que se arrastra
            property int hoverIdx: -1          // casilla donde caerá ahora
            property int dragSlot0: -1         // casilla de origen
            property bool committed: false     // ya se guardó el orden; el ícono solo está aterrizando
            property point dragPos: Qt.point(0, 0)
            property int edgeDir: 0

            readonly property real gridLeft: (width - gridW) / 2
            readonly property real gridTop: topPad + Math.max(0, (gridH - rows * cellH) / 2)
            // posición de una casilla (slot global; cada página ocupa un ancho de pantalla)
            function cellX(slot: int): real {
                return Math.floor(slot / perPage) * width + gridLeft + ((slot % perPage) % cols) * cellW;
            }
            function cellY(slot: int): real {
                return gridTop + Math.floor((slot % perPage) / cols) * cellH;
            }
            // disposición por casillas: cada app tiene su casilla y puede haber huecos; con búsqueda, el orden de resultados
            function buildSlots(list: var): var {
                const n = Math.max(1, Math.ceil(list.length / perPage)) * perPage;
                const saved = Settings.apps.order ?? [];
                const arr = new Array(n).fill("");
                const rest = [];
                for (const a of list) {
                    const i = saved.indexOf(a.id);
                    if (i >= 0 && i < n && arr[i] === "") arr[i] = a.id;
                    else rest.push(a.id);
                }
                let k = 0;
                for (const id of rest) {
                    while (k < n && arr[k] !== "") k++;
                    if (k < n) arr[k] = id;
                }
                return arr;
            }
            readonly property var baseSlots: query === "" ? buildSlots(results) : null
            readonly property int slotCount: baseSlots ? baseSlots.length : results.length
            // mover id a la casilla «to»: si estaba ocupada, las dos apps cambian de sitio (las demás no se mueven)
            function previewSlots(base: var, id: string, to: int): var {
                const arr = base.slice();
                const from = arr.indexOf(id);
                if (from < 0 || to < 0 || to >= arr.length || from === to) return arr;
                arr[from] = arr[to];
                arr[to] = id;
                return arr;
            }
            readonly property var displaySlots: (dragging && !committed && baseSlots && dragApp) ? previewSlots(baseSlots, dragApp.id, hoverIdx) : baseSlots
            function slotOfId(id: string, fallback: int): int {
                const s = displaySlots;
                if (!s) {
                    const k = results.findIndex(a => a.id === id);
                    return k >= 0 ? k : fallback;
                }
                const i = s.indexOf(id);
                return i >= 0 ? i : fallback;
            }
            function commitSlots(): void {
                if (!baseSlots || !dragApp) return;
                const arr = previewSlots(baseSlots, dragApp.id, hoverIdx);
                while (arr.length && arr[arr.length - 1] === "") arr.pop();
                Apps.setOrder(arr);
            }

            function startDrag(gi: int, app: var): void {
                dragging = true;
                dragMoved = true;
                dragIdx = gi;
                dragSlot0 = slotOfId(app.id, gi);
                hoverIdx = dragSlot0;
                dragApp = app;
                ghostBody.x = 0;
                ghostBody.y = 0;
            }

            // índice de la casilla bajo el puntero (coordenadas de content), en la página actual
            function dropIndex(p: point): int {
                const pp = pages.mapFromItem(content, p.x, p.y);
                const col = Math.max(0, Math.min(cols - 1, Math.floor((pp.x - (pages.width - gridW) / 2) / cellW)));
                const topOff = Math.max(0, (pages.height - rows * cellH) / 2);
                const row = Math.max(0, Math.min(rows - 1, Math.floor((pp.y - topOff) / cellH)));
                return Math.max(0, Math.min(slotCount - 1, pages.currentIndex * perPage + row * cols + col));
            }

            // pasar de página mientras se arrastra: con el puntero en el borde (se repite cada rato) o sobre un punto de página
            readonly property real edgeZone: 120
            property int dotIdx: -1
            function flipPage(d: int): void {
                goPage(pages.currentIndex + d);
                if (dragging) hoverIdx = dropIndex(dragPos);
            }
            function updateEdge(): void {
                const pp = pages.mapFromItem(content, dragPos.x, dragPos.y);
                const dir = pp.x < edgeZone ? -1 : (pp.x > pages.width - edgeZone ? 1 : 0);
                if (dir !== edgeDir) {
                    edgeDir = dir;
                    if (dir !== 0) {
                        flipPage(dir);
                        edgeTimer.restart();
                    } else {
                        edgeTimer.stop();
                    }
                }
                const dp = dotsRow.mapFromItem(content, dragPos.x, dragPos.y);
                const di = (dotsRow.visible && dp.x >= 0 && dp.x <= dotsRow.width && dp.y >= -14 && dp.y <= dotsRow.height + 14)
                    ? Math.min(pageCount - 1, Math.floor(dp.x / 22)) : -1;
                if (di !== dotIdx) {
                    dotIdx = di;
                    if (di >= 0 && di !== pages.currentIndex) flipPage(di - pages.currentIndex);
                }
            }
            Timer {
                id: edgeTimer
                interval: 600
                repeat: true
                onTriggered: if (win.edgeDir !== 0) win.flipPage(win.edgeDir)
            }

            // soltar (commit) o cancelar: la app vuela a su casilla final (o a la original) y luego se guarda el orden
            function release(commit: bool): void {
                if (!dragging || settle.running) return;
                edgeTimer.stop();
                edgeDir = 0;
                let target = dragSlot0;
                if (commit && baseSlots && dragApp) {
                    // se guarda ya: las demás apps se corren para llenar el hueco y el ícono aterriza en su casilla final
                    const packed = previewSlots(baseSlots, dragApp.id, hoverIdx).filter(x => x !== "");
                    target = Math.max(0, packed.indexOf(dragApp.id));
                    committed = true;
                    Apps.setOrder(packed);
                } else {
                    hoverIdx = dragSlot0;
                }
                const tlX = dragPos.x - cellW / 2, tlY = dragPos.y - cellH / 2;
                // cellX es la posición en la tira de páginas; el ghost está en coordenadas de pantalla
                settleX.to = cellX(target) - pages.currentIndex * pages.width - tlX;
                settleY.to = cellY(target) - tlY;
                settle.restart();
            }
            ParallelAnimation {
                id: settle
                NumberAnimation { id: settleX; target: ghostBody; property: "x"; duration: Math.round(420 * Theme.animMult); easing.type: Easing.OutCubic }
                NumberAnimation { id: settleY; target: ghostBody; property: "y"; duration: Math.round(420 * Theme.animMult); easing.type: Easing.OutCubic }
                onFinished: {
                    win.endDrag();
                }
            }
            function endDrag(): void {
                settle.stop();
                dragging = false;
                dragApp = null;
                dragIdx = -1;
                hoverIdx = -1;
                dragSlot0 = -1;
                committed = false;
                dropPending = false;
                edgeDir = 0;
                dotIdx = -1;
                edgeTimer.stop();
                ghostBody.x = 0;
                ghostBody.y = 0;
            }

            // menú contextual
            property var ctxApp: null
            property point ctxPos: Qt.point(0, 0)

            Component.onCompleted: {
                syncCells();
                search.text = "";
                search.forceActiveFocus();
            }
            Connections {
                target: root
                function onOpenChanged(): void {
                    if (!root.open) return;
                    search.text = "";
                    Hyprland.refreshWorkspaces();
                    win.ctxApp = null;
                    pages.currentIndex = 0;
                    pages.positionViewAtBeginning();
                    search.forceActiveFocus();
                }
            }

            // fondo: oscurece toda la pantalla (y Hyprland difumina la capa)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.04, 0.04, 0.06, 0.5 * root.p)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }

            Item {
                id: content
                anchors.fill: parent
                focus: true
                Keys.forwardTo: [search]
                opacity: root.p
                // como macOS: al abrir, la cuadrícula «se aleja» desde un poco más grande
                scale: 1.12 - 0.12 * root.p
                transformOrigin: Item.Center

                // ------------------------------------------------ escritorios (Spaces)
                Row {
                    id: spaces
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 96
                    spacing: 16
                    Repeater {
                        model: win.wsIds
                        Item {
                            id: sp
                            required property int modelData
                            readonly property bool current: modelData === win.curWsId
                            width: 160
                            height: 90 + 24
                            Rectangle {
                                id: spThumb
                                width: parent.width
                                height: 90
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.1)
                                border.width: sp.current ? 2 : 1
                                border.color: sp.current ? Theme.macBlue : Qt.rgba(1, 1, 1, 0.25)
                                scale: spMouse.containsMouse ? 1.04 : 1
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    visible: Settings.appearance.wallpaper.startsWith("/")
                                    source: visible ? Wallpaper.still(Settings.appearance.wallpaper) : ""
                                    sourceSize: Qt.size(320, 200)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: 0.85
                                }
                            }
                            Txt {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                text: I18n.t("Escritorio") + " " + sp.modelData
                                color: "white"
                                font.weight: sp.current ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                id: spMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.gotoWs(sp.modelData)
                            }
                        }
                    }
                }

                // ------------------------------------------------ buscador
                Rectangle {
                    id: searchBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 48
                    width: 240
                    height: 30
                    radius: 8
                    color: Qt.rgba(1, 1, 1, search.activeFocus ? 0.2 : 0.14)
                    border.width: 1
                    border.color: search.activeFocus ? Theme.macBlue : Qt.rgba(1, 1, 1, 0.16)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    // anillo de foco azul de macOS: se ve que el campo está activo
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: parent.radius + 3
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.rgba(Theme.macBlue.r, Theme.macBlue.g, Theme.macBlue.b, 0.55)
                        opacity: search.activeFocus ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed: e => { search.forceActiveFocus(); e.accepted = false; }
                    }

                    Row {
                        anchors.centerIn: search.text === "" && search.preeditText === "" && !search.activeFocus ? parent : undefined
                        anchors.left: search.text === "" && search.preeditText === "" && !search.activeFocus ? undefined : parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Icon { text: "search"; size: 16; color: Qt.rgba(1, 1, 1, 0.7); anchors.verticalCenter: parent.verticalCenter }
                        Txt {
                            visible: search.text === "" && search.preeditText === ""
                            text: I18n.t("Buscar")
                            color: Qt.rgba(1, 1, 1, 0.55)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TextInput {
                        id: search
                        anchors.fill: parent
                        focus: true
                        activeFocusOnPress: true
                        selectByMouse: true
                        anchors.leftMargin: 32
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.font
                        font.pixelSize: Theme.textNormal
                        color: "white"
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.primaryFg
                        clip: true
                        // sin foco y vacío, el «Buscar» va centrado; con foco pasa a la izquierda y aparece el cursor
                        cursorDelegate: Rectangle { width: 1.5; color: "white"; visible: search.activeFocus && search.cursorVisible }

                        // IBeam al pasar por encima del campo
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            acceptedButtons: Qt.NoButton
                        }
                        Keys.onEscapePressed: {
                            if (win.dragging) win.release(false);
                            else if (win.ctxApp) win.ctxApp = null;
                            else if (search.text !== "") search.text = "";
                            else root.hide();
                        }
                        Keys.onReturnPressed: win.launch(win.results[Math.max(0, win.sel)])
                        Keys.onEnterPressed: win.launch(win.results[Math.max(0, win.sel)])
                        Keys.onPressed: e => {
                            const n = win.results.length;
                            const atEnd = search.cursorPosition === search.text.length;
                            if (e.key === Qt.Key_Right && atEnd) {
                                if (win.sel < 0) win.goPage(pages.currentIndex + 1);
                                else win.sel = Math.min(n - 1, win.sel + 1);
                            } else if (e.key === Qt.Key_Left && search.cursorPosition === 0) {
                                if (win.sel < 0) win.goPage(pages.currentIndex - 1);
                                else win.sel = Math.max(0, win.sel - 1);
                            } else if (e.key === Qt.Key_Down) {
                                win.sel = win.sel < 0 ? pages.currentIndex * win.perPage : Math.min(n - 1, win.sel + win.cols);
                            } else if (e.key === Qt.Key_Up) {
                                win.sel = Math.max(0, win.sel - win.cols);
                            } else if (e.key === Qt.Key_PageDown) {
                                win.goPage(pages.currentIndex + 1);
                            } else if (e.key === Qt.Key_PageUp) {
                                win.goPage(pages.currentIndex - 1);
                            } else return;
                            e.accepted = true;
                        }
                    }
                }

                // ------------------------------------------------ páginas
                ListView {
                    id: pages
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: win.topPad
                    height: win.gridH
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    highlightMoveDuration: Math.max(1, Math.round(480 * Theme.animMult))
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !win.dragging
                    clip: true
                    model: win.pageCount
                    currentIndex: 0

                    delegate: Item {
                        required property int index
                        width: pages.width
                        height: pages.height

                        // clic en un hueco vacío = cerrar (Flickable no deja pasar el clic al fondo)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.hide()
                        }
                    }

                    // rueda / desplazamiento con 2 dedos: una página por gesto
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        property real acc: 0
                        property bool locked: false
                        Timer { id: wheelReset; interval: 180; onTriggered: { parent.acc = 0; parent.locked = false; } }
                        onWheel: e => {
                            const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : e.angleDelta.y;
                            wheelReset.restart();
                            if (locked) return;
                            acc += d;
                            if (acc <= -120) { win.goPage(pages.currentIndex + 1); acc = 0; locked = true; }
                            else if (acc >= 120) { win.goPage(pages.currentIndex - 1); acc = 0; locked = true; }
                        }
                    }

                    // sin resultados
                    Txt {
                        anchors.centerIn: parent
                        visible: win.results.length === 0
                        text: I18n.t("No encontré nada con «") + search.text + "»"
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.pixelSize: Theme.textLarge
                    }
                }

                // ------------------------------------------------ apps: una capa; cada una tiene su casilla y
                // al arrastrar las demás se deslizan a su nueva casilla
                Item {
                    id: cellsLayer
                    x: -pages.contentX
                    width: content.width
                    height: content.height

                    Repeater {
                        model: win.cellModel

                        MouseArea {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property int gIndex: index
                            readonly property int local: gIndex % win.perPage
                            readonly property bool selected: win.sel >= 0 && !!win.results[win.sel] && win.results[win.sel].id === modelData.id
                            readonly property bool isDragged: win.dragging && !!win.dragApp && win.dragApp.id === modelData.id
                            readonly property int slot: win.slotOfId(modelData.id, gIndex)
                            // animación al abrir / cerrar: los íconos aparecen en cascada (de arriba a la izquierda
                            // hacia abajo a la derecha), creciendo desde pequeños; al cerrar vuelven a encogerse
                            readonly property real delay: Math.min(0.4, ((local % win.cols) + Math.floor(local / win.cols)) * 0.035)
                            readonly property real t: Math.max(0, Math.min(1, (root.p - delay) / (1 - delay)))

                            x: win.cellX(slot)
                            y: win.cellY(slot)
                            width: win.cellW
                            height: win.cellH
                            // la casilla inicial no se anima (si no, al recrearse tras soltar entrarían desde el borde)
                            property bool placed: false
                            Component.onCompleted: Qt.callLater(() => cell.placed = true)
                            Behavior on x { enabled: cell.placed; NumberAnimation { duration: Math.round(340 * Theme.animMult); easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: cell.placed; NumberAnimation { duration: Math.round(340 * Theme.animMult); easing.type: Easing.OutCubic } }

                            hoverEnabled: true
                            opacity: t * (isDragged ? 0 : 1)
                            scale: 0.7 + 0.3 * (1 - Math.pow(1 - t, 3))
                            transformOrigin: Item.Center
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: true

                            property point pressAt: Qt.point(0, 0)
                            onPressed: e => {
                                win.dragMoved = false;
                                pressAt = cell.mapToItem(content, e.x, e.y);
                            }
                            onPositionChanged: e => {
                                if (!(cell.pressedButtons & Qt.LeftButton) || win.query !== "" || win.ctxApp) return;
                                const p = cell.mapToItem(content, e.x, e.y);
                                if (!win.dragging) {
                                    if (Math.hypot(p.x - cell.pressAt.x, p.y - cell.pressAt.y) < 12) return;
                                    win.startDrag(cell.gIndex, cell.modelData);
                                }
                                win.dragPos = p;
                                win.hoverIdx = win.dropIndex(p);
                                win.updateEdge();
                            }
                            onReleased: win.release(true)
                            onCanceled: win.release(false)
                            onClicked: e => {
                                if (win.dragMoved) return;
                                if (e.button === Qt.RightButton) {
                                    win.ctxPos = cell.mapToItem(content, e.x, e.y);
                                    win.ctxApp = cell.modelData;
                                } else {
                                    win.launch(cell.modelData);
                                }
                            }

                            Rectangle {
                                anchors.centerIn: icon
                                width: icon.width + 22
                                height: icon.height + 22
                                radius: 22
                                color: Qt.rgba(1, 1, 1, cell.selected ? 0.22 : 0)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }

                            AppIcon {
                                id: icon
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: Math.max(4, (parent.height - 88 - 34) / 2)
                                size: 88
                                name: cell.modelData.icon ?? ""
                                scale: cell.pressed ? 0.9 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                            }
                            Txt {
                                anchors.top: icon.bottom
                                anchors.topMargin: 10
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 20
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData.name
                                color: "white"
                                font.pixelSize: Theme.textSmall + 1
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                style: Text.Raised
                                styleColor: Qt.rgba(0, 0, 0, 0.35)
                            }
                        }
                    }
                }

                // ------------------------------------------------ puntos de página
                Row {
                    id: dotsRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: pages.bottom
                    anchors.topMargin: 18
                    spacing: 4
                    visible: win.pageCount > 1
                    Repeater {
                        model: win.pageCount
                        MouseArea {
                            id: dot
                            required property int index
                            width: 18
                            height: 18
                            onClicked: win.goPage(dot.index)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: Qt.rgba(1, 1, 1, pages.currentIndex === dot.index ? 0.92 : 0.35)
                                Behavior on color { ColorAnimation { duration: Theme.anim } }
                            }
                        }
                    }
                }

                // app que se arrastra: sigue al puntero; al soltar, vuela a la casilla final
                Item {
                    id: ghost
                    visible: win.dragging && !!win.dragApp
                    width: win.cellW
                    height: win.cellH
                    z: 100
                    x: win.dragPos.x - width / 2
                    y: win.dragPos.y - height / 2
                    opacity: 0.92
                    Item {
                        id: ghostBody
                        width: parent.width
                        height: parent.height
                        scale: 1.08
                        transformOrigin: Item.Center
                        AppIcon {
                            id: gIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.max(4, (parent.height - 88 - 34) / 2)
                            size: 88
                            name: win.dragApp?.icon ?? ""
                        }
                        Txt {
                            anchors.top: gIcon.bottom
                            anchors.topMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 20
                            horizontalAlignment: Text.AlignHCenter
                            text: win.dragApp?.name ?? ""
                            color: "white"
                            font.pixelSize: Theme.textSmall + 1
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                // ------------------------------------------------ menú contextual
                MouseArea {
                    anchors.fill: parent
                    visible: !!win.ctxApp
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: win.ctxApp = null
                }
                Rectangle {
                    id: ctxMenu
                    visible: !!win.ctxApp
                    x: Math.max(8, Math.min(win.ctxPos.x, content.width - width - 8))
                    y: Math.max(8, Math.min(win.ctxPos.y, content.height - height - 8))
                    width: 230
                    height: ctxCol.implicitHeight + 12
                    radius: 10
                    color: Theme.alpha(Theme.surfaceHigh, 0.97)
                    border.width: 1
                    border.color: Theme.alpha(Theme.fg, 0.12)
                    ColumnLayout {
                        id: ctxCol
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 0
                        Repeater {
                            model: win.ctxApp ? [
                                { icon: "open_in_new", text: I18n.t("Abrir"), run: () => win.launch(win.ctxApp) },
                                { icon: "visibility_off", text: I18n.t("Ocultar del menú"), run: () => Apps.setVisible(win.ctxApp, false) }
                            ] : []
                            MouseArea {
                                id: opt
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                hoverEnabled: true
                                onClicked: { opt.modelData.run(); win.ctxApp = null; }
                                Rectangle { anchors.fill: parent; radius: 6; color: opt.containsMouse ? Theme.alpha(Theme.primary, 0.18) : "transparent" }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    spacing: 10
                                    Icon { text: opt.modelData.icon; size: 18 }
                                    Txt { text: opt.modelData.text; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
