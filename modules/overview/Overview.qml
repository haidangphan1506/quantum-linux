import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.services
import qs.components

// Mission Control (como macOS): vuốt 3 ngón lên (o IPC `overview toggle`).
//  - Arriba: los escritorios (workspaces) que tienen apps + el actual + «+» para uno nuevo.
//    Clic = ir a ese escritorio. Arrastrar una ventana encima = moverla allí.
//  - Centro: las ventanas del escritorio actual en cuadrícula, con vista en vivo.
//    Al abrir, cada ventana vuela desde su sitio real a su hueco (y vuelve al cerrar).
//    Clic = enfocar, botón ✕ = cerrar ventana.
//  - Esc, clic en el fondo o vuốt 3 ngón xuống: cerrar.
Scope {
    id: root

    property bool open: false
    property real p: open ? 1 : 0
    Behavior on p { NumberAnimation { duration: Math.max(1, Theme.animSlow); easing.type: Easing.OutCubic } }
    readonly property bool shown: open || p > 0.001

    // ventana activa al abrir (luego el overview tiene el foco del teclado)
    property string activeAddr: ""
    // ventana que debe quedar ENCIMA al cerrar (la elegida, o la activa si se cierra con
    // gesto/Esc): así al volver cada miniatura a su sitio el apilado coincide con el real
    property string targetAddr: ""

    function show(): void {
        if (open) return;
        activeAddr = addr(Hyprland.activeToplevel);
        targetAddr = activeAddr;
        leaveTo = 0;
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
        Shell.closeAll();
        open = true;
    }
    function hide(): void { open = false; }
    function toggle(): void { open ? hide() : show(); }

    function addr(t: var): string {
        const a = t?.address ?? "";
        return a === "" ? "" : (a.startsWith("0x") ? a : "0x" + a);
    }
    function dispatch(code: string): void { Quickshell.execDetached(["hyprctl", "dispatch", code]); }
    // Ir a otro escritorio: PRIMERO cerrar (soltar el foco del teclado) y luego cambiar.
    // Si se cambiaba con el overview abierto, al cerrarse Hyprland devolvía el foco a la
    // ventana anterior y con ella volvía al escritorio de antes.
    property int leaveTo: 0          // > 0: se cierra para ir a ese escritorio (sin «volar» de vuelta)
    function gotoWs(id: int): void {
        leaveTo = id;
        open = false;
        wsTimer.restart();
    }
    Timer {
        id: wsTimer
        interval: 60
        onTriggered: root.dispatch(`hl.dsp.focus({ workspace = ${root.leaveTo} })`)
    }

    // estado para Shell.swipe() y órdenes que llegan desde ahí
    Binding { target: Shell; property: "overviewOpen"; value: root.open }
    Connections {
        target: Shell
        function onOverviewRequest(fn: string): void { fn === "open" ? root.show() : root.hide(); }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        function go(id: int): void { if (root.open) root.gotoWs(id); }   // = clic en un escritorio
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win

            readonly property var mon: Hyprland.focusedMonitor
            readonly property var curWs: mon?.activeWorkspace ?? Hyprland.focusedWorkspace
            readonly property int curId: curWs?.id ?? 1

            screen: Quickshell.screens.find(s => s.name === mon?.name) ?? Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-overview"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore

            // ventanas reales (sin las minimizadas: viven en special:minimized, id < 0)
            readonly property var allWins: Hyprland.toplevels.values.filter(t => t.wayland && t.workspace && t.workspace.id > 0)
            readonly property var curWins: allWins.filter(t => t.workspace.id === curId)
                .slice().sort((a, b) => {
                    const pa = a.lastIpcObject?.at ?? [0, 0], pb = b.lastIpcObject?.at ?? [0, 0];
                    return (pa[1] - pb[1]) || (pa[0] - pb[0]);
                })
            readonly property var wsList: {
                const ids = new Set(allWins.map(t => t.workspace.id));
                ids.add(curId);
                return Array.from(ids).sort((a, b) => a - b);
            }
            readonly property real monW: width
            readonly property real monH: height

            // ---------------------------------------------------- cuadrícula
            readonly property real stripH: 150
            readonly property rect area: Qt.rect(70, stripH + 70, width - 140, height - stripH - 70 - 60)
            readonly property var slots: layout(curWins, area)

            function layout(list: var, a: rect): var {
                const n = list.length;
                if (n === 0) return [];
                const gap = 36, labelH = 30;
                const sizes = list.map(t => {
                    const s = t.lastIpcObject?.size ?? [monW * 0.75, monH * 0.75];
                    return { w: Math.max(80, s[0]), h: Math.max(60, s[1]) };
                });
                let best = null;
                for (let rows = 1; rows <= n; rows++) {
                    const cols = Math.ceil(n / rows);
                    const cw = (a.width - gap * (cols - 1)) / cols;
                    const ch = (a.height - gap * (rows - 1)) / rows - labelH;
                    if (cw < 40 || ch < 40) continue;
                    let total = 0;
                    const sc = sizes.map(s => Math.min(cw / s.w, ch / s.h, 0.8));
                    sc.forEach((k, i) => total += sizes[i].w * sizes[i].h * k * k);
                    if (!best || total > best.total) best = { rows, cols, cw, ch, sc, total };
                }
                if (!best) return [];
                const out = [];
                const rowH = best.ch + labelH;
                const usedH = best.rows * rowH + (best.rows - 1) * gap;
                let y0 = a.y + (a.height - usedH) / 2;
                for (let r = 0; r < best.rows; r++) {
                    const items = [];
                    for (let c = 0; c < best.cols; c++) {
                        const i = r * best.cols + c;
                        if (i < n) items.push(i);
                    }
                    const widths = items.map(i => sizes[i].w * best.sc[i]);
                    const rowW = widths.reduce((s, w) => s + w, 0) + gap * (items.length - 1);
                    let x = a.x + (a.width - rowW) / 2;
                    items.forEach((i, k) => {
                        const w = widths[k], h = sizes[i].h * best.sc[i];
                        out[i] = Qt.rect(x, y0 + (best.ch - h) / 2, w, h);
                        x += w + gap;
                    });
                    y0 += rowH + gap;
                }
                return out;
            }

            // ---------------------------------------------------- arrastrar a otro escritorio
            property var dragWin: null
            property point dragPos: Qt.point(0, 0)
            property int dropWs: -1
            function wsAt(pt: point): int {
                for (let i = 0; i < wsRep.count; i++) {
                    const it = wsRep.itemAt(i);
                    if (!it) continue;
                    const p = it.mapFromItem(win.contentItem, pt.x, pt.y);
                    if (p.x >= 0 && p.y >= 0 && p.x <= it.width && p.y <= it.height) return it.wsId;
                }
                return -1;
            }

            // fondo: oscurece (y Hyprland difumina la capa quantum-overview)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.5 * root.p)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.hide()
            }

            // ------------------------------------------------ franja de escritorios
            Row {
                id: strip
                anchors.horizontalCenter: parent.horizontalCenter
                y: 24 - (1 - root.p) * 60
                opacity: root.p
                spacing: 18

                Repeater {
                    id: wsRep
                    model: win.wsList

                    Item {
                        id: wsCard
                        required property int modelData
                        readonly property int wsId: modelData
                        readonly property bool current: wsId === win.curId
                        readonly property bool dropHot: win.dragWin !== null && win.dropWs === wsId
                        readonly property real thumbW: 190
                        readonly property real thumbH: thumbW * win.monH / Math.max(1, win.monW)
                        width: thumbW
                        height: thumbH + 26

                        ClippingRectangle {
                            id: thumb
                            width: wsCard.thumbW
                            height: wsCard.thumbH
                            radius: 10
                            color: Theme.alpha(Theme.surface, 0.9)
                            border.width: wsCard.current || wsCard.dropHot ? 2 : 1
                            border.color: wsCard.dropHot ? Theme.primary : wsCard.current ? Theme.alpha(Theme.primary, 0.9) : Theme.alpha(Theme.fg, 0.18)
                            scale: wsMouse.containsMouse || wsCard.dropHot ? 1.05 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                visible: Settings.appearance.wallpaper.startsWith("/")
                                source: visible ? Wallpaper.still(Settings.appearance.wallpaper) : ""
                                sourceSize: Qt.size(380, 240)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: 0.85
                            }
                            // ventanas en miniatura, en su posición real
                            Repeater {
                                model: win.allWins.filter(t => t.workspace.id === wsCard.wsId)
                                ClippingRectangle {
                                    required property var modelData
                                    readonly property bool isActive: root.addr(modelData) === root.activeAddr
                                    readonly property var at: modelData.lastIpcObject?.at ?? [0, 0]
                                    readonly property var sz: modelData.lastIpcObject?.size ?? [win.monW * 0.75, win.monH * 0.75]
                                    readonly property real k: thumb.width / Math.max(1, win.monW)
                                    x: (at[0] - (win.mon?.x ?? 0)) * k
                                    y: (at[1] - (win.mon?.y ?? 0)) * k
                                    width: sz[0] * k
                                    height: sz[1] * k
                                    radius: 4
                                    color: Theme.alpha(Theme.surface, 0.95)
                                    border.width: isActive ? 2 : 1
                                    border.color: isActive ? Theme.primary : Theme.alpha(Theme.fg, 0.2)
                                    ScreencopyView {
                                        id: mini
                                        anchors.fill: parent
                                        captureSource: modelData.wayland
                                        live: false
                                    }
                                    AppIcon {
                                        visible: !mini.hasContent
                                        anchors.centerIn: parent
                                        size: 22   // FIJO: un tamaño ligado al marco hacía explotar la memoria (IconImage)
                                        name: Wm.iconFor(modelData.wayland?.appId ?? "")
                                    }
                                }
                            }
                        }
                        Txt {
                            anchors.horizontalCenter: thumb.horizontalCenter
                            anchors.top: thumb.bottom
                            anchors.topMargin: 6
                            text: I18n.t("Escritorio") + " " + wsCard.wsId
                            font.pixelSize: 12
                            font.weight: wsCard.current ? Font.Bold : Font.Normal
                            color: "white"
                        }
                        MouseArea {
                            id: wsMouse
                            anchors.fill: thumb
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (wsCard.current) root.hide();
                                else root.gotoWs(wsCard.wsId);
                            }
                        }
                    }
                }

                // «+»: escritorio nuevo (el siguiente número libre)
                Item {
                    width: 70
                    height: 190 * win.monH / Math.max(1, win.monW) + 26
                    Rectangle {
                        id: plus
                        width: 70
                        height: parent.height - 26
                        radius: 10
                        color: plusMouse.containsMouse ? Theme.alpha(Theme.fg, 0.22) : Theme.alpha(Theme.fg, 0.1)
                        border.width: 1
                        border.color: Theme.alpha(Theme.fg, 0.18)
                        Icon { anchors.centerIn: parent; text: "add"; size: 28; color: "white" }
                    }
                    MouseArea {
                        id: plusMouse
                        anchors.fill: plus
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const next = Math.max(...win.wsList) + 1;
                            root.gotoWs(next);
                        }
                    }
                }
            }

            // ------------------------------------------------ ventanas del escritorio actual
            Txt {
                visible: win.curWins.length === 0
                anchors.centerIn: parent
                opacity: root.p * 0.8
                text: I18n.t("No hay ventanas en este escritorio")
                font.pixelSize: 18
                color: "white"
            }

            Repeater {
                model: win.curWins

                Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property var t: modelData
                    readonly property var at: t.lastIpcObject?.at ?? [win.width * 0.125, win.height * 0.125]
                    readonly property var sz: t.lastIpcObject?.size ?? [win.width * 0.75, win.height * 0.75]
                    // de su sitio real (p = 0) a su hueco en la cuadrícula (p = 1)
                    readonly property rect src: Qt.rect(at[0] - (win.mon?.x ?? 0), at[1] - (win.mon?.y ?? 0), sz[0], sz[1])
                    readonly property rect dst: win.slots[index] ?? src
                    readonly property bool dragging: win.dragWin === t
                    readonly property bool isActive: root.addr(t) === root.activeAddr
                    readonly property bool hot: tileMouse.containsMouse && !dragging
                    property point grabOff: Qt.point(0, 0)
                    readonly property real k: dragging ? 0.45 : 1

                    // al irse a otro escritorio, estas ventanas ya no se verán: se desvanecen en su hueco
                    readonly property real fp: root.leaveTo > 0 ? 1 : root.p
                    opacity: root.leaveTo > 0 ? root.p : 1
                    x: dragging ? win.dragPos.x - grabOff.x * k : src.x + (dst.x - src.x) * fp
                    y: dragging ? win.dragPos.y - grabOff.y * k : src.y + (dst.y - src.y) * fp
                    width: (src.width + (dst.width - src.width) * fp) * k
                    height: (src.height + (dst.height - src.height) * fp) * k
                    // apilado real: focusHistoryID 0 = la más reciente (encima); la ventana destino, la primera
                    z: dragging ? 1000 : root.addr(t) === root.targetAddr ? 500 : 100 - (t.lastIpcObject?.focusHistoryID ?? 99)

                    // borde: cửa sổ đang active = màu chủ đạo; hover = sáng và dày hơn
                    Rectangle {
                        id: frame
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: 16
                        color: "transparent"
                        border.width: tile.hot ? 4 : tile.isActive ? 3 : 0
                        border.color: tile.hot ? Qt.lighter(Theme.primary, 1.15) : Theme.primary
                        opacity: root.p
                        Behavior on border.width { NumberAnimation { duration: 120 } }
                    }
                    // vista en vivo con esquinas redondeadas (ClippingRectangle recorta también la captura)
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 12
                        color: Theme.alpha(Theme.surface, 0.9)
                        border.width: tile.isActive || tile.hot ? 0 : 1
                        border.color: Theme.alpha(Theme.fg, 0.15)
                        ScreencopyView {
                            id: shot
                            anchors.fill: parent
                            captureSource: tile.t.wayland
                            live: root.open
                        }
                        AppIcon {
                            visible: !shot.hasContent
                            anchors.centerIn: parent
                            size: Math.max(32, Math.min(96, Math.round(Math.min(tile.dst.width, tile.dst.height) * 0.35)))   // fijo durante la animación
                            name: Wm.iconFor(tile.t.wayland?.appId ?? "")
                        }
                    }

                    // nombre de la app debajo (como macOS al pasar el ratón)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 8
                        visible: !tile.dragging
                        opacity: root.p
                        radius: height / 2
                        color: tileMouse.containsMouse ? Theme.alpha(Theme.surface, 0.95) : "transparent"
                        implicitWidth: nameRow.implicitWidth + 18
                        implicitHeight: 24
                        Row {
                            id: nameRow
                            anchors.centerIn: parent
                            spacing: 6
                            AppIcon { size: 16; name: Wm.iconFor(tile.t.wayland?.appId ?? ""); anchors.verticalCenter: parent.verticalCenter }
                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tileMouse.containsMouse ? (tile.t.title || Wm.nameFor(tile.t.wayland?.appId ?? ""))
                                                              : Wm.nameFor(tile.t.wayland?.appId ?? "")
                                width: Math.min(implicitWidth, Math.max(120, tile.width - 30))
                                elide: Text.ElideRight
                                font.pixelSize: 12
                                color: tileMouse.containsMouse ? Theme.fg : "white"
                            }
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        property point start
                        onPressed: e => { start = Qt.point(e.x, e.y); }
                        onPositionChanged: e => {
                            if (!(e.buttons & Qt.LeftButton)) return;
                            const pt = mapToItem(win.contentItem, e.x, e.y);
                            if (!tile.dragging && Math.hypot(e.x - start.x, e.y - start.y) > 12) {
                                tile.grabOff = start;
                                win.dragWin = tile.t;
                            }
                            if (tile.dragging) {
                                win.dragPos = pt;
                                win.dropWs = win.wsAt(pt);
                            }
                        }
                        onReleased: e => {
                            if (!tile.dragging) return;
                            const ws = win.dropWs;
                            win.dragWin = null;
                            win.dropWs = -1;
                            if (ws > 0 && ws !== win.curId) {
                                root.dispatch(`hl.dsp.window.move({ workspace = ${ws}, follow = false, window = "address:${root.addr(tile.t)}" })`);
                                Qt.callLater(() => { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); });
                            }
                        }
                        onClicked: {
                            if (tile.dragging) return;
                            root.targetAddr = root.addr(tile.t);
                            Wm.focus(tile.t.wayland);
                            root.hide();
                        }
                    }

                    // ✕ cerrar ventana
                    Rectangle {
                        visible: tileMouse.containsMouse || closeMouse.containsMouse
                        x: -9; y: -9
                        width: 22; height: 22; radius: 11
                        color: closeMouse.containsMouse ? "#ff5f57" : Theme.alpha(Theme.surface, 0.95)
                        border.width: 1
                        border.color: Theme.alpha(Theme.fg, 0.25)
                        Icon { anchors.centerIn: parent; text: "close"; size: 14; color: closeMouse.containsMouse ? "white" : Theme.fg }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                tile.t.wayland?.close();
                                Qt.callLater(() => Hyprland.refreshToplevels());
                            }
                        }
                    }
                }
            }
        }
    }
}
