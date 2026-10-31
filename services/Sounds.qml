pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Sonidos del sistema (creados para Quantum, en assets/sounds). Se reproducen con
// pw-play (PipeWire). Se activan, ajustan o apagan en Personalizar → Sonidos.
Singleton {
    id: root

    readonly property bool enabled: Settings.sounds.enabled
    readonly property real volume: Settings.sounds.volume
    readonly property string dir: Quickshell.shellDir + "/assets/sounds/"

    // Estilos de sonidos (hechos para Quantum, branding/sounds): «quantum» es el original
    readonly property var packs: [
        { id: "quantum", name: "Quantum", desc: "Campanas de cristal suaves. El de siempre.", icon: "blur_on" },
        { id: "cristal", name: "Cristal", desc: "Campanitas brillantes y claras.", icon: "diamond" },
        { id: "zen", name: "Zen", desc: "Kalimba y madera: tranquilo y suave.", icon: "spa" },
        { id: "espacial", name: "Espacial", desc: "Sintetizadores con eco, como en el espacio.", icon: "rocket_launch" },
        { id: "minimo", name: "Mínimo", desc: "Toques cortitos que casi no se notan.", icon: "radio_button_unchecked" },
        { id: "burbujas", name: "Burbujas", desc: "Burbujas de agua, divertido.", icon: "bubble_chart" },
        { id: "piano", name: "Piano", desc: "Notas de piano.", icon: "piano" },
        { id: "synthwave", name: "Synthwave", desc: "Ochentero y con energía.", icon: "graphic_eq" },
    ]
    function file(pack: string, name: string): string {
        return dir + (pack && pack !== "quantum" ? pack + "/" : "") + name + ".oga";
    }

    // Vista previa de un estilo (bienvenida, Personalizar): una sola a la vez. Tocar el
    // mismo estilo otra vez la detiene; tocar otro corta la anterior y empieza la nueva.
    property string previewing: ""
    property string _pending: ""
    function preview(pack: string): void {
        if (previewing === pack && previewProc.running) { _pending = ""; previewProc.signal(15); return; }
        _pending = pack;
        if (previewProc.running) previewProc.signal(15);      // al terminar arranca la pendiente
        else _startPending();
    }
    function _startPending(): void {
        if (!_pending) return;
        previewing = _pending;
        previewProc.command = ["pw-play", "--volume", String(Math.max(0.3, Math.min(1, volume))), file(_pending, "preview")];
        _pending = "";
        previewProc.running = true;
    }
    function stopPreview(): void { _pending = ""; if (previewProc.running) previewProc.signal(15); }
    Process {
        id: previewProc
        onExited: { root.previewing = ""; root._startPending(); }
    }

    // name: startup | volume | toggle-on | toggle-off | click | notification | lock | unlock | error | screenshot
    function play(name: string): void {
        if (!enabled && name !== "test") return;
        if (name === "test") name = "notification";
        if (name === "startup" && !Settings.sounds.startup) return;
        // no apilar el mismo sonido muchas veces (p. ej. al mover el volumen)
        const now = Date.now();
        if (now - (_last[name] ?? 0) < 70) return;
        _last[name] = now;
        Quickshell.execDetached(["pw-play", "--volume", String(Math.max(0, Math.min(1, volume))),
                                 file(Settings.sounds.pack, name)]);
    }
    property var _last: ({})

}
