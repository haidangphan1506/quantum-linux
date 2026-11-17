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

    // Sin colors.json (quantum-theme) se usa la paleta por defecto del modo: oscura o clara
    function col(name: string, darkFallback: string, lightFallback: string): color {
        return c[name] ?? (dark ? darkFallback : lightFallback);
    }

    // Superficies: grises neutros como macOS (sin tinte violeta)
    readonly property color surface: col("surface", "#1c1c1e", "#f5f5f7")
    readonly property color surfaceLow: col("surface_container_low", "#232325", "#f0f0f2")
    readonly property color surfaceContainer: col("surface_container", "#2c2c2e", "#ebebed")
    readonly property color surfaceHigh: col("surface_container_high", "#3a3a3c", "#e5e5e7")
    readonly property color surfaceHighest: col("surface_container_highest", "#48484a", "#dcdcde")
    readonly property color fg: col("on_surface", "#f5f5f7", "#1d1d1f")
    readonly property color fgMuted: col("on_surface_variant", "#a1a1a6", "#6e6e73")
    readonly property color outline: col("outline", "#8e8e93", "#8e8e93")
    readonly property color outlineVariant: col("outline_variant", "#3a3a3c", "#d1d1d6")
    readonly property color scrim: col("scrim", "#000000", "#000000")

    // Acentos: sin colors.json salen del color de acento elegido en Personalizar
    // (Settings.appearance.accent), no del azul/violeta por defecto del proyecto.
    // Como macOS: lo activado se rellena con el acento y lleva texto blanco.
    readonly property color accent: Settings.appearance?.accent || "#007aff"
    readonly property color primary: c.primary ?? (dark ? Qt.lighter(accent, 1.18) : accent)
    readonly property color primaryFg: c.on_primary ?? "#ffffff"
    readonly property color primaryContainer: c.primary_container ?? accent
    readonly property color primaryContainerFg: c.on_primary_container ?? "#ffffff"
    readonly property color secondaryContainer: c.secondary_container ?? Qt.tint(surface, alpha(accent, 0.22))
    readonly property color secondaryContainerFg: c.on_secondary_container ?? fg
    readonly property color tertiary: col("tertiary", "#ffb340", "#c76a00")
    readonly property color error: col("error", "#ff6961", "#d70015")
    readonly property color success: col("success", "#30d158", "#248a3d")
    // Colores de sistema de macOS (semáforo de los medidores: verde / naranja / rojo) y azul
    readonly property color macGreen: dark ? "#30d158" : "#34c759"
    readonly property color macOrange: dark ? "#ff9f0a" : "#ff9500"
    readonly property color macRed: dark ? "#ff453a" : "#ff3b30"
    readonly property color macBlue: dark ? "#0a84ff" : "#007aff"
    // Popover de macOS (panel de la barra de menús): material casi opaco, borde fino y tarjetas
    // de fondo agrupado (como «controlBackground»)
    readonly property color popover: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.92) : Qt.rgba(0.96, 0.96, 0.97, 0.92)
    readonly property color popoverBorder: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color popoverCard: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.7)
    readonly property color popoverCardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color errorFg: col("on_error", "#ffffff", "#ffffff")

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
    readonly property real dockScale: Settings.dock?.size === "small" ? 0.66 : (Settings.dock?.size === "large" ? 0.92 : 0.78)
    readonly property real panelOpacity: Settings.appearance?.panelOpacity ?? 0.86
    // Vidrio estilo Control Center de macOS: fondo muy translúcido (con blur de Hyprland,
    // layer «quantum-panel») y casillas de vidrio claro encima
    readonly property color glassPanel: alpha(surface, dark ? 0.5 : 0.45)
    readonly property color glassTile: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.5)
    readonly property color glassTileHover: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.68)
    readonly property color glassBorder: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.55)
    // Efecto vidrio: opacidad de cada parte (bar, dock, panels); sin vidrio, casi opaca
    function glassOpacity(kind: string): real {
        return (Settings.appearance?.glass?.[kind] ?? true) ? panelOpacity : 0.97;
    }

    // Animaciones
    readonly property string animations: Shell.gameMode ? "none" : (Settings.windows?.animations ?? "normal")
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
