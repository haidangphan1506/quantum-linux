pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Colores (Material 3) que escribe quantum-theme, tipografía y medidas comunes.
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quantum"

    property var c: ({})
    readonly property bool dark: (c.mode ?? (Settings.appearance?.mode ?? "dark")) !== "light"

    function col(name: string, fallback: string): color {
        return c[name] ?? fallback;
    }

    // Superficies
    readonly property color surface: col("surface", "#13121c")
    readonly property color surfaceLow: col("surface_container_low", "#1b1a24")
    readonly property color surfaceContainer: col("surface_container", "#1f1f28")
    readonly property color surfaceHigh: col("surface_container_high", "#2a2933")
    readonly property color surfaceHighest: col("surface_container_highest", "#35343e")
    readonly property color fg: col("on_surface", "#e4e0ee")
    readonly property color fgMuted: col("on_surface_variant", "#c8c4d4")
    readonly property color outline: col("outline", "#928f9e")
    readonly property color outlineVariant: col("outline_variant", "#474553")
    readonly property color scrim: col("scrim", "#000000")

    // Acentos
    readonly property color primary: col("primary", "#c5c0ff")
    readonly property color primaryFg: col("on_primary", "#2a1a9a")
    readonly property color primaryContainer: col("primary_container", "#6a5cff")
    readonly property color primaryContainerFg: col("on_primary_container", "#ffffff")
    readonly property color secondaryContainer: col("secondary_container", "#433f6f")
    readonly property color secondaryContainerFg: col("on_secondary_container", "#e3dfff")
    readonly property color tertiary: col("tertiary", "#ffb68b")
    readonly property color error: col("error", "#ffb4ab")
    readonly property color errorFg: col("on_error", "#690005")

    // Degradado de la marca (celeste → índigo → violeta)
    readonly property color brandCyan: "#4FD8FF"
    readonly property color brandIndigo: "#6A5CFF"
    readonly property color brandViolet: "#B14DFF"

    // Tipografía
    // Serpantium usa letra monoespaciada en todo el escritorio
    readonly property bool serp: Settings.ui.shell === "serpantium"
    readonly property string font: serp ? "JetBrains Mono" : "Inter"
    readonly property string iconFont: "Material Symbols Rounded"
    readonly property real textScale: Settings.appearance?.textScale ?? 1.0
    readonly property int textSmall: Math.round(12 * textScale)
    readonly property int textNormal: Math.round(14 * textScale)
    readonly property int textLarge: Math.round(17 * textScale)
    readonly property int textTitle: Math.round(22 * textScale)

    // Formas
    readonly property string corners: Settings.windows?.corners ?? "soft"
    readonly property int radiusSmall: corners === "sharp" ? 6 : (corners === "round" ? 14 : 10)
    readonly property int radius: corners === "sharp" ? 10 : (corners === "round" ? 20 : 16)
    readonly property int radiusLarge: corners === "sharp" ? 14 : (corners === "round" ? 28 : 24)
    readonly property int gap: 10
    // Tamaño de la barra de tareas (Personalizar): pequeño / mediano / grande
    readonly property real dockScale: Settings.dock?.size === "small" ? 0.86 : (Settings.dock?.size === "large" ? 1.18 : 1.0)
    readonly property real panelOpacity: Settings.appearance?.panelOpacity ?? 0.86
    // Efecto vidrio: opacidad de cada parte (bar, dock, panels); sin vidrio, casi opaca
    function glassOpacity(kind: string): real {
        return (Settings.appearance?.glass?.[kind] ?? true) ? panelOpacity : 0.97;
    }

    // Animaciones
    readonly property string animations: Settings.windows?.animations ?? "normal"
    readonly property real animMult: animations === "none" ? 0 : (animations === "fast" ? 0.7 : (animations === "smooth" ? 1.4 : 1.0))
    readonly property int animFast: Math.round(120 * animMult)
    readonly property int anim: Math.round(200 * animMult)
    readonly property int animSlow: Math.round(340 * animMult)

    function alpha(base: color, a: real): color {
        return Qt.rgba(base.r, base.g, base.b, a);
    }

    FileView {
        path: root.stateDir + "/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.c = JSON.parse(text());
            } catch (e) {
                console.warn("Theme: colors.json inválido:", e);
            }
        }
    }
}
