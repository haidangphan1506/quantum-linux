import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Escritorio y Dock como en Ajustes del Sistema de macOS: Dock (tamaño, ampliación,
// posición, doble clic en la barra de título, ocultar, animar,
// indicadores), la barra de tareas de Quantum, el navegador predeterminado y Ventanas.
ColumnLayout {
    id: page
    spacing: 16

    readonly property bool single: Settings.layout.style === "single"
    readonly property var sizes: ["small", "medium", "large"]

    // ------------------------------------------------------------- Dock
    Group {
        title: Serp.on && Settings.ui.serpApps !== "dock" ? I18n.t("Dock (no se usa con Serpantium)") : I18n.t("Dock")
        OptionRow {
            title: I18n.t("Tamaño")
            Slider {
                implicitWidth: 240
                from: 0; to: 2; step: 1; ticks: 3
                value: Math.max(0, page.sizes.indexOf(Settings.dock.size))
                minText: I18n.t("Pequeño"); maxText: I18n.t("Grande")
                onMoved: v => Settings.set("dock", "size", page.sizes[Math.round(v)])
            }
        }
        OptionRow {
            title: I18n.t("Ampliación")
            RowLayout {
                spacing: 12
                Slider {
                    visible: Settings.dock.magnify
                    implicitWidth: 200
                    from: 0.15; to: 1; step: 0.05; live: true
                    value: Settings.dock.magnifyAmount
                    minText: I18n.t("Mín."); maxText: I18n.t("Máx.")
                    onMoved: v => Settings.set("dock", "magnifyAmount", v)
                }
                Toggle { checked: Settings.dock.magnify; onToggled: c => Settings.set("dock", "magnify", c) }
            }
        }
        OptionRow {
            title: I18n.t("Posición en la pantalla")
            Segmented {
                options: [{ v: "left", t: I18n.t("Izquierda") }, { v: "bottom", t: I18n.t("Abajo") }, { v: "right", t: I18n.t("Derecha") }, { v: "top", t: I18n.t("Arriba") }]
                value: Settings.dock.position
                onPicked: v => Settings.set("dock", "position", v)
            }
        }
        OptionRow {
            title: I18n.t("Doble clic en la barra de título de una ventana para")
            Choice {
                options: [{ v: "fill", t: I18n.t("Llenar") }, { v: "minimize", t: I18n.t("Minimizar") }, { v: "none", t: I18n.t("No hacer nada") }]
                value: Settings.windows.doubleClick
                onPicked: v => Settings.set("windows", "doubleClick", v)
            }
        }
        OptionRow {
            title: I18n.t("Ocultar y mostrar el Dock automáticamente")
            Toggle { checked: Settings.dock.autohide; onToggled: c => Settings.set("dock", "autohide", c) }
        }
        OptionRow {
            title: I18n.t("Animar la apertura de aplicaciones")
            Toggle { checked: Settings.dock.animateOpen; onToggled: c => Settings.set("dock", "animateOpen", c) }
        }
        OptionRow {
            title: I18n.t("Mostrar indicadores de las apps abiertas")
            Toggle { checked: Settings.dock.showIndicators; onToggled: c => Settings.set("dock", "showIndicators", c) }
        }
    }

    // ------------------------------------------------- barra de tareas (Quantum)
    Group {
        title: I18n.t("Barra de tareas")
        help: Serp.on ? I18n.t("Serpantium: barra de píldoras arriba, paneles oscuros y tonos rosados.")
                      : I18n.t("Caelestial: barra de menús arriba, Dock y paneles de vidrio.")
        OptionRow {
            title: I18n.t("Estilo del escritorio")
            Segmented {
                options: [{ v: "caelestial", t: "Caelestial" }, { v: "serpantium", t: "Serpantium" }]
                value: Settings.ui.shell
                onPicked: v => Serp.choose(v, false)
            }
        }
        OptionRow {
            visible: Serp.on
            title: I18n.t("Tus apps")
            Segmented {
                options: [{ v: "bar", t: I18n.t("En la barra de arriba") }, { v: "dock", t: I18n.t("Dock abajo") }]
                value: Settings.ui.serpApps === "dock" ? "dock" : "bar"
                onPicked: v => Settings.setUi("serpApps", v)
            }
        }
        OptionRow {
            visible: !Serp.on
            title: I18n.t("Distribución")
            help: page.single ? I18n.t("Como en Windows: apps, bandeja y hora en una barra.") : I18n.t("Hora y estado arriba, apps abajo.")
            Segmented {
                options: [{ v: "split", t: I18n.t("Barra de menús + Dock") }, { v: "single", t: I18n.t("Una sola barra") }]
                value: Settings.layout.style
                onPicked: v => Settings.setPath("layout.style", v)
            }
        }
        OptionRow {
            visible: !Serp.on
            title: I18n.t("Forma")
            Segmented {
                options: [{ v: true, t: I18n.t("Flotante") }, { v: false, t: I18n.t("Pegada al borde") }]
                value: Settings.dock.floating
                onPicked: v => Settings.set("dock", "floating", v)
            }
        }
        OptionRow {
            visible: !Serp.on
            title: I18n.t("Posición de las apps")
            Segmented {
                options: [{ v: "center", t: I18n.t("Al centro") }, { v: "left", t: I18n.t("Al inicio") }]
                value: Settings.dock.align
                onPicked: v => Settings.set("dock", "align", v)
            }
        }
        OptionRow { visible: !Serp.on; title: I18n.t("Botón de Inicio (Launchpad)"); Toggle { checked: Settings.dock.showStart; onToggled: c => Settings.set("dock", "showStart", c) } }
        OptionRow { visible: !Serp.on; title: I18n.t("Botón de búsqueda"); Toggle { checked: Settings.dock.showSearch; onToggled: c => Settings.set("dock", "showSearch", c) } }
        OptionRow { visible: !Serp.on; title: I18n.t("Aviso de actualizaciones"); Toggle { checked: Settings.dock.showUpdates; onToggled: c => Settings.set("dock", "showUpdates", c) } }
    }

    // ------------------------------------------------- navegador predeterminado
    property string browser: ""
    readonly property var browsers: Apps.everything.filter(a => (a.categories ?? []).includes("WebBrowser")).map(a => ({ v: a.id + ".desktop", t: a.name }))
    Process {
        id: getBrowser
        running: true
        command: ["xdg-settings", "get", "default-web-browser"]
        stdout: StdioCollector { onStreamFinished: page.browser = text.trim() }
    }
    Process { id: setBrowser; onExited: getBrowser.running = true }
    Group {
        OptionRow {
            title: I18n.t("Navegador web predeterminado")
            Choice {
                options: page.browsers
                value: page.browser
                placeholder: page.browser.replace(/\.desktop$/, "") || "—"
                onPicked: v => { setBrowser.command = ["xdg-settings", "set", "default-web-browser", v]; setBrowser.running = true; }
            }
        }
    }

    // ------------------------------------------------------------ ventanas
    Group {
        title: I18n.t("Ventanas")
        OptionRow {
            title: I18n.t("Botones de las ventanas")
            help: I18n.t("Para las apps que dibujan su propia barra de título (GTK).")
            Segmented {
                options: [{ v: true, t: I18n.t("A la izquierda") }, { v: false, t: I18n.t("A la derecha") }]
                value: Settings.windows.buttonsLeft
                onPicked: v => Settings.set("windows", "buttonsLeft", v)
            }
        }
        OptionRow {
            title: I18n.t("Animaciones de las ventanas")
            help: I18n.t("Al abrir, cerrar y mover ventanas. Apágalas para que todo sea instantáneo.")
            Toggle {
                checked: Settings.windows.animations !== "none"
                onToggled: c => Settings.set("windows", "animations", c ? "smooth" : "none")
            }
        }
        OptionRow {
            advanced: true
            title: I18n.t("Grosor del borde")
            Slider {
                implicitWidth: 200
                from: 0; to: 4; step: 1; ticks: 5
                value: Settings.windows.borderSize
                text: Math.round(_shown) + " px"
                onMoved: v => Settings.set("windows", "borderSize", Math.round(v))
            }
        }
    }

    Group {
        title: I18n.t("Gestos y atajos")
        help: I18n.t("Se cambian en la configuración de Hyprland (~/.config/hypr).")
        OptionRow { title: I18n.t("Mission Control"); help: I18n.t("Deslizar hacia arriba con tres dedos"); icon: "view_quilt"; iconColor: "#8E8E93" }
        OptionRow { title: I18n.t("Launchpad"); help: I18n.t("Deslizar hacia abajo con tres dedos"); icon: "apps"; iconColor: "#8E8E93" }
        OptionRow { title: I18n.t("Cambiar de escritorio"); help: I18n.t("Deslizar a los lados con cuatro dedos"); icon: "swap_horiz"; iconColor: "#8E8E93" }
        OptionRow { title: I18n.t("Cambiar de ventana"); help: I18n.t("Deslizar a los lados con tres dedos"); icon: "tab"; iconColor: "#8E8E93" }
    }
}
