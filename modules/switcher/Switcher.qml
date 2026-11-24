import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.services
import qs.components

// Cambiar de ventana (như Cmd+Tab của macOS), solo ventanas del escritorio actual.
//   Alt+Tab: abre con la ventana anterior (orden de uso reciente) seleccionada
//   mantener Alt + Tab: siguiente     ·  Alt soltado: ir a la seleccionada
//   ←/→, ratón (hover + clic), Enter = ir, Esc = cancelar
// Las teclas las manda Hyprland (variable.lua) por IPC: switcher next | commit | cancel.
// Gesto de 3 dedos (hyprlands/misc.lua): switcher swipe <id> <seq> <pasos+1000> … swipeEnd <id> <seq> <pasos+1000> <ir>
//   Cada mensaje es un proceso `qs ipc` aparte y pueden llegar desordenados: seq descarta los viejos,
//   los pasos son absolutos (no +1/-1) y el fin trae la posición final, así que el resultado no depende del orden.
Scope {
    id: root

    property bool open: false
    property var wins: []          // HyprlandToplevel, más reciente primero
    property int index: 0

    // Modo "elegir pareja": tras ajustar una ventana a media pantalla (hyprlands/snap.lua) y haber 2+ ventanas más,
    // se elige cuál ocupa la otra mitad. side = mitad que ocupará la elegida (left|right|top|bottom).
    property bool pickMode: false
    property string pickAnchor: ""
    property string pickSide: ""

    function addr(t: var): string {
        const a = t?.address ?? "";
        return a === "" ? "" : (a.startsWith("0x") ? a : "0x" + a);
    }

    function collect(): var {
        const ws = Hyprland.focusedMonitor?.activeWorkspace ?? Hyprland.focusedWorkspace;
        const id = ws?.id ?? 1;
        // la activa SIEMPRE primero (dato en vivo); el resto por uso reciente (focusHistoryID)
        const act = Hyprland.activeToplevel;
        const rank = t => t === act ? -1 : (t.lastIpcObject?.focusHistoryID ?? 99);
        return Hyprland.toplevels.values
            .filter(t => t.wayland && t.workspace && t.workspace.id === id && !(pickMode && addr(t) === pickAnchor))
            .slice()
            .sort((a, b) => rank(a) - rank(b));
    }

    function next(step: int): void {
        if (!open) {
            Hyprland.refreshToplevels();
            const list = collect();
            if (list.length === 0) return;
            wins = list;
            index = list.length > 1 ? (step > 0 ? 1 : list.length - 1) : 0;
            Shell.closeAll();
            stepped = false;
            openedAt = Date.now();
            open = true;
            resort.restart();
            return;
        }
        stepped = true;
        if (wins.length > 0) index = (index + step + wins.length) % wins.length;
    }
    function pick(anchor: string, side: string): void {
        if (open) return;
        pickAnchor = anchor;
        pickSide = side;
        pickMode = true;
        Hyprland.refreshToplevels();
        const list = collect();
        if (list.length === 0) { pickMode = false; return; }
        wins = list;
        index = 0;
        Shell.closeAll();
        stepped = false;
        openedAt = Date.now();
        open = true;
        resort.restart();
    }
    function commit(): void {
        if (!open) return;
        const t = wins[index];
        open = false;
        gActive = false;
        if (pickMode) {
            pickMode = false;
            const p = addr(t);
            if (p !== "" && /^0x[0-9a-fA-F]+$/.test(pickAnchor) && /^(left|right|top|bottom)$/.test(pickSide))
                Quickshell.execDetached(["hyprctl", "eval", `cael_snap_pair('${pickAnchor}','${p}','${pickSide}')`]);
            return;
        }
        // Al cerrarse la capa (teclado Exclusive) Hyprland devuelve el foco a la ventana anterior:
        // enfocar DESPUÉS, si no la elegida pierde el foco y hay que pulsar Tab otra vez.
        pending = t?.wayland ?? null;
        if (pending) focusLater.restart();
    }
    property var pending: null
    Timer {
        id: focusLater
        interval: 80
        onTriggered: {
            // Alt+Tab: el cursor salta a la ventana elegida
            if (root.pending) Wm.focus(root.pending, true);
            root.pending = null;
        }
    }
    function cancel(): void { open = false; gActive = false; pickMode = false; }
    property double openedAt: 0

    // ---------------------------------------------------------------- gesto de 3 dedos
    property string gId: ""         // gesto actual
    property int gSeq: 0            // último mensaje aplicado
    property int gSteps: 0          // pasos desde la ventana anterior (+ derecha, − izquierda)
    property bool gActive: false
    property var gEnded: []         // gestos ya terminados: se ignora lo que llegue tarde
    property int gPendingEnd: 0     // 1 = ir, -1 = cancelar, cuando termine de reordenar
    function applySteps(): void {
        const n = wins.length;
        index = n > 1 ? (((1 + gSteps) % n) + n) % n : 0;
    }
    function swipe(gid: string, seq: int, steps: int): bool {
        if (gEnded.indexOf(gid) >= 0) return false;
        if (gid !== gId) { gId = gid; gSeq = 0; }
        if (seq <= gSeq) return false;
        gSeq = seq;
        gSteps = steps - 1000;
        if (!open) next(1);
        if (!open) return false;
        gActive = true;
        applySteps();
        return true;
    }
    function swipeEnd(gid: string, seq: int, steps: int, go: bool): void {
        if (gEnded.indexOf(gid) >= 0) return;
        swipe(gid, seq, steps);
        gEnded = [gid].concat(gEnded).slice(0, 8);
        if (!open) { gActive = false; return; }
        // el orden por uso reciente aún no llegó (refreshToplevels es asíncrono): esperar a resort
        if (resort.running) { gPendingEnd = go ? 1 : -1; return; }
        gActive = false;
        go ? commit() : cancel();
    }

    // focusHistoryID llega con refreshToplevels (asíncrono): reordenar poco después de abrir,
    // si el usuario aún no se movió
    property bool stepped: false
    Timer {
        id: resort
        interval: 150
        onTriggered: {
            if (!root.open) return;
            if (root.stepped && !root.gActive) return;
            const list = root.collect();
            if (list.length > 0) {
                root.wins = list;
                if (root.gActive) root.applySteps();
                else root.index = (list.length > 1 && !root.pickMode) ? 1 : 0;
            }
            if (root.gPendingEnd !== 0) {
                const go = root.gPendingEnd > 0;
                root.gPendingEnd = 0;
                root.gActive = false;
                go ? root.commit() : root.cancel();
            }
        }
    }

    IpcHandler {
        target: "switcher"
        function next(): void { root.next(1); }
        function prev(): void { root.next(-1); }
        function commit(): void { root.commit(); }
        function cancel(): void { root.cancel(); }
        function pick(anchor: string, side: string): void { root.pick(anchor, side); }
        function swipe(gid: string, seq: int, steps: int): void { root.swipe(gid, seq, steps); }
        function swipeEnd(gid: string, seq: int, steps: int, go: bool): void { root.swipeEnd(gid, seq, steps, go); }
        function status(): string {
            return `open=${root.open} index=${root.index} active=${Hyprland.activeToplevel?.title ?? "-"} wins=`
                + root.wins.map(t => `${t.wayland?.appId}(${t.lastIpcObject?.focusHistoryID})`).join(",");
        }
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-switcher"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore

            readonly property int n: root.wins.length
            // miniaturas: alto fijo, ancho según la ventana; si no caben, se achican
            readonly property real maxRow: width - 160
            readonly property real baseH: 170
            readonly property real gap: 18
            readonly property real natW: root.wins.reduce((s, t) => {
                const sz = t.lastIpcObject?.size ?? [16, 10];
                return s + baseH * sz[0] / Math.max(1, sz[1]);
            }, 0) + gap * Math.max(0, n - 1)
            readonly property real k: Math.min(1, maxRow / Math.max(1, natW))
            readonly property real thumbH: Math.round(baseH * k)

            // clic fuera: cancelar
            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) root.cancel();
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.commit();
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) root.next(1);
                    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) root.next(-1);
                    e.accepted = true;
                }
                // respaldo: si Alt se suelta y el aviso de Hyprland no llegó
                Keys.onReleased: e => { if (e.key === Qt.Key_Alt) root.commit(); }
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: row.width + 40
                height: row.height + 40 + 34
                radius: 22
                color: Theme.glassPanel
                border.width: 1
                border.color: Theme.alpha(Theme.fg, 0.14)
                scale: 0.94
                opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1; }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 110 } }

                MouseArea { anchors.fill: parent }   // no cancelar al hacer clic dentro

                Row {
                    id: row
                    x: 20
                    y: 20
                    spacing: win.gap

                    Repeater {
                        model: root.wins

                        Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var sz: modelData.lastIpcObject?.size ?? [16, 10]
                            readonly property bool sel: index === root.index
                            width: Math.round(win.thumbH * sz[0] / Math.max(1, sz[1]))
                            height: win.thumbH

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -5
                                radius: 15
                                color: cell.sel ? Theme.alpha(Theme.primary, 0.18) : "transparent"
                                border.width: cell.sel ? 3 : 0
                                border.color: Theme.primary
                            }
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 10
                                color: Theme.alpha(Theme.surfaceHigh ?? Theme.surface, 0.9)
                                scale: cell.sel ? 1 : 0.96
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                ScreencopyView {
                                    id: shot
                                    anchors.fill: parent
                                    captureSource: cell.modelData.wayland
                                    live: true
                                }
                                AppIcon {
                                    visible: !shot.hasContent
                                    anchors.centerIn: parent
                                    size: 48     // fijo (tamaños ligados al marco hacían explotar la memoria)
                                    name: Wm.iconFor(cell.modelData.wayland?.appId ?? "", cell.modelData.wayland?.title ?? "")
                                }
                            }
                            // icono de la app en la esquina, como macOS
                            AppIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.bottom
                                size: 36
                                name: Wm.iconFor(cell.modelData.wayland?.appId ?? "", cell.modelData.wayland?.title ?? "")
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // solo si el ratón se mueve de verdad: al abrirse (y con la animación) la
                                // miniatura bajo el cursor quieto recibía "entered" y robaba la selección
                                onPositionChanged: {
                                    if (root.gActive || Date.now() - root.openedAt < 300 || cell.sel) return;
                                    root.stepped = true;
                                    root.index = cell.index;
                                }
                                onClicked: { root.index = cell.index; root.commit(); }
                            }
                        }
                    }
                }

                // título de la seleccionada
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    width: Math.min(implicitWidth, panel.width - 40)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    readonly property var t: root.wins[root.index]
                    text: (root.pickMode ? "Chọn cửa sổ ghép cùng · " : "") + (t ? (t.title || Wm.nameFor(t.wayland?.appId ?? "", t.wayland?.title ?? "")) : "")
                }
            }
        }
    }
}
