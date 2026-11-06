import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Efecto «genie» curvo al ocultar / mostrar una ventana por el dock (como el video dock_effects).
// Hyprland no deforma ventanas: aquí se captura la ventana (ScreencopyView de la pantalla, recortada)
// y se dibuja en franjas horizontales que se doblan hacia el dock; la de abajo llega primero.
// Lo llama minimize.lua con: qs -c caelestia ipc call genie play <addr> <x> <y> <w> <h> <dx> <dy> <modo> <ms>
//   modo: open (app nueva: sale de su icono) | restore (vuelve desde el final del dock)
//         | min (va al final del dock) | close (va a su icono y se cierra)
// Como en el video: el destino es el icono de la app en el dock (DockTargets); si no hay, el centro del dock.
// Coordenadas en píxeles lógicos de la pantalla principal.
PanelWindow {
    id: fx

    screen: Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quantum-genie"
    WlrLayershell.layer: WlrLayer.Overlay
    // toda la pantalla desde (0,0): sin esto el overlay queda debajo de la barra de arriba
    // y el efecto sale corrido hacia abajo respecto a la ventana
    exclusionMode: ExclusionMode.Ignore
    // sin área de entrada: el mouse pasa a través del overlay
    mask: Region {}
    // siempre visible: si el overlay se oculta, la captura de pantalla deja de llegar
    visible: true

    property bool running: false
    property bool pending: false
    property real p: 0          // 0 = ventana, 1 = dock
    property real x0: 0; property real y0: 0; property real w0: 100; property real h0: 100
    property real xd: 0; property real yd: 0; property real wd: 44
    property bool opening: false
    property string addr: ""
    property string mode: "min"
    property int dur: 340
    readonly property int nBands: 48

    // true: se captura la propia ventana (toplevel) aunque este oculta (opacidad 0): la app nunca
    // se ve a tamano completo antes del efecto. Solo para «open»; el resto captura la pantalla.
    property bool fromWin: false
    property var winSource: null     // toplevel de Wayland de la ventana (Hyprland.toplevels)

    // Captura: la ventana (toplevel) o la pantalla; se recorta la region con sourceRect
    ScreencopyView {
        id: cap
        x: -30000; y: 0
        width: fx.fromWin ? fx.w0 : fx.screen.width
        height: fx.fromWin ? fx.h0 : fx.screen.height
        captureSource: fx.fromWin ? fx.winSource : fx.screen
        live: fx.pending
        onHasContentChanged: if (fx.pending && hasContent) fx.begin()
    }

    Repeater {
        // las franjas solo existen durante el efecto
        model: fx.running ? fx.nBands : 0
        ShaderEffectSource {
            required property int index
            readonly property real v: (index + 0.5) / fx.nBands
            readonly property real s: Math.max(0, Math.min(1, (fx.p - (1 - v) * 0.35) / 0.65))
            readonly property real e: s * s * (3 - 2 * s)
            readonly property real yr0: fx.y0 + v * fx.h0
            readonly property real yRow: yr0 + (fx.yd - yr0) * e
            readonly property real cx0: fx.x0 + fx.w0 / 2
            readonly property real cxRow: cx0 + (fx.xd - cx0) * e
            readonly property real wRow: fx.w0 + (fx.wd - fx.w0) * e
            readonly property real hRow: fx.h0 / fx.nBands * (1 - 0.6 * e) + 1.5
            x: cxRow - wRow / 2
            y: yRow - hRow / 2
            width: wRow
            height: hRow
            opacity: 1 - Math.pow(s, 3)
            sourceItem: cap
            sourceRect: fx.fromWin
                ? Qt.rect(0, index * fx.h0 / fx.nBands, fx.w0, fx.h0 / fx.nBands)
                : Qt.rect(fx.x0, fx.y0 + index * fx.h0 / fx.nBands, fx.w0, fx.h0 / fx.nBands)
            live: true
        }
    }

    NumberAnimation {
        id: anim
        target: fx; property: "p"
        from: fx.opening ? 1 : 0
        to: fx.opening ? 0 : 1
        duration: fx.dur
        easing.type: Easing.Linear
        onFinished: fx.finish()
    }

    // Ocultar / mostrar la ventana real con hyprctl (la captura ya tiene el contenido)
    function winSet(value: string): void {
        Quickshell.execDetached(["hyprctl", "dispatch",
            `hl.dsp.window.set_prop({ prop = "opacity", value = "${value}", window = "address:${fx.addr}" })`]);
    }

    function begin(): void {
        if (!fx.pending) return;
        fx.pending = false;
        fx.winSet("0.00");          // la ventana real se oculta; el overlay la muestra
        fx.running = true;
        anim.start();
    }

    function finish(): void {
        fx.running = false;
        fx.p = 0;
        if (fx.mode === "open" || fx.mode === "restore") {
            fx.winSet("1.0");
        } else if (fx.mode === "close") {
            Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.window.close({ window = "address:${fx.addr}" })`]);
        }
        // «min»: minimize.lua mueve la ventana al workspace oculto al terminar
    }

    // Empieza un poco despues de pedir la captura (si el contenido ya estaba listo, no hay cambio que avise)
    Timer {
        id: beginT
        interval: 90
        onTriggered: fx.begin()
    }

    // Si la captura no llega, no se oculta nada: la ventana sigue visible como antes
    Timer {
        id: failT
        interval: 800
        onTriggered: if (fx.pending) {
            // sin captura: la ventana no puede quedarse oculta
            fx.pending = false;
            if (fx.fromWin) fx.winSet("1.0");
            console.log("GENIE sin captura; se omite el efecto");
        }
    }

    // Toplevel de Hyprland de una ventana (por address)
    function toplevelOf(addr: string): var {
        const key = addr.replace(/^0x/, "");
        return Hyprland.toplevels.values.find(t => (t.address ?? "").replace(/^0x/, "") === key) ?? null;
    }

    // Id del grupo del dock (id del .desktop) de una ventana de Hyprland
    function groupOf(addr: string): string {
        const appId = fx.toplevelOf(addr)?.wayland?.appId ?? "";
        return appId ? (Wm.entryFor(appId)?.id ?? appId) : "";
    }

    // min / restore: final del dock (ahi estan las minimizadas); open / close: el icono de la app
    function dockTarget(addr: string, mode: string): var {
        if (mode === "min" || mode === "restore")
            return DockTargets.endPoint() ?? DockTargets.appPoint(fx.groupOf(addr));
        return DockTargets.appPoint(fx.groupOf(addr)) ?? DockTargets.endPoint();
    }

    function play(addr: string, x: real, y: real, w: real, h: real, dx: real, dy: real, mode: string, ms: int): void {
        if (fx.running || fx.pending) return;
        fx.addr = addr.replace(/^address:/, "");
        fx.mode = mode;
        fx.opening = mode === "open" || mode === "restore";
        fx.x0 = x; fx.y0 = y; fx.w0 = w; fx.h0 = h;
        // destino: el icono de la app o el final del dock (DockTargets); si no, el que manda minimize.lua
        const t = fx.dockTarget(fx.addr, mode);
        if (t) { dx = t.x; dy = t.y; }
        fx.wd = Math.min(44, w);
        fx.xd = dx - fx.wd / 2;
        fx.yd = dy;
        fx.dur = ms > 0 ? ms : 340;
        fx.p = fx.opening ? 1 : 0;
        // «open»: captura de la ventana misma; si no se encuentra su toplevel, se usa la pantalla
        const top = mode === "open" ? fx.toplevelOf(fx.addr) : null;
        fx.winSource = top?.wayland ?? null;
        fx.fromWin = !!fx.winSource;
        fx.pending = true;
        cap.captureFrame();
        beginT.restart();
        failT.restart();
    }

    IpcHandler {
        target: "genie"
        function play(addr: string, x: real, y: real, w: real, h: real, dx: real, dy: real, mode: string, ms: int): void {
            fx.play(addr, x, y, w, h, dx, dy, mode, ms);
        }
    }
}
