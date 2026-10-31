pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Serpantium: la segunda forma de Quantum Shell (se elige en la bienvenida o en
// Personalizar → Estilos). Barra de píldoras arriba, paneles que bajan desde ella,
// letra monoespaciada y tonos rosados. Inspirado en Serpantinum de ilyamiro.
Singleton {
    id: root

    readonly property bool on: Settings.ui.shell === "serpantium"

    // Colores (fijos: así Serpantium siempre se ve como Serpantium)
    readonly property color bg: "#17111A"
    readonly property color card: "#1F171D"
    readonly property color cardHi: "#2A2027"
    readonly property color pill: Qt.rgba(0.11, 0.08, 0.10, 0.88)
    readonly property color line: Qt.rgba(1, 1, 1, 0.07)
    readonly property color pink: "#F4A7C9"
    readonly property color pinkSoft: Qt.rgba(0.96, 0.65, 0.79, 0.16)
    readonly property color pinkFg: "#3A1028"
    readonly property color fg: "#F3E7ED"
    readonly property color muted: "#A3919B"
    readonly property string font: "JetBrains Mono"
    readonly property string wallpaper: (Quickshell.env("QUANTUM_WALLPAPERS") || "/usr/share/backgrounds/quantum") + "/serpantium.jpg"

    // «viernes 30 de octubre» → «Viernes 30 de octubre»
    function cap(t: string): string { return t.length ? t.charAt(0).toUpperCase() + t.slice(1) : t; }

    // Panel abierto bajo la barra: "" | "media" | "clock" | "control"
    property string panel: ""
    function toggle(name: string): void {
        panel = panel === name ? "" : name;
        if (panel !== "") {
            Shell.launcherOpen = false;
            Shell.sessionOpen = false;
        }
    }

    // Elegir la forma del shell. Serpantium trae su fondo rosado y sus colores, salvo que
    // keepLook diga que la persona ya eligió los suyos (paso 2 de la bienvenida): entonces
    // se respetan. Al volver a Caelestial se recupera lo que tenías antes.
    function choose(id: string, keepLook: bool): void {
        if (id === Settings.ui.shell) return;
        const a = Settings.appearance;
        // todo en una sola escritura: dos seguidas se pisaban al recargar el archivo
        if (id === "serpantium") {
            Settings.ui.before = { wallpaper: a.wallpaper, accent: a.accent, dynamicColors: a.dynamicColors, mode: a.mode };
            Settings.setMany(keepLook ? { ui: { shell: id } }
                : { appearance: { mode: "dark", dynamicColors: false, accent: "#F4A7C9", wallpaper: root.wallpaper }, ui: { shell: id } });
        } else {
            const b = Settings.ui.before ?? {};
            Settings.setMany({ appearance: { wallpaper: b.wallpaper ?? "quantum:live", accent: b.accent ?? Settings.defaults.appearance.accent,
                                             dynamicColors: b.dynamicColors ?? false, mode: b.mode ?? "dark" },
                               ui: { shell: id } });
        }
        panel = "";
    }
}
