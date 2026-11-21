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

    readonly property var sizes: ["small", "medium", "large"]

    // ------------------------------------------------------------- Dock
    Group {
        title: I18n.t("Dock")
        // Tamaño y Ampliación lado a lado, con el título encima (como macOS)
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 28
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2
                Txt { text: I18n.t("Tamaño") }
                Slider {
                    Layout.fillWidth: true
                    from: 0; to: 2; step: 1; ticks: 3
                    value: Math.max(0, page.sizes.indexOf(Settings.dock.size))
                    minText: I18n.t("Pequeño"); maxText: I18n.t("Grande")
                    onMoved: v => Settings.set("dock", "size", page.sizes[Math.round(v)])
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2
                Txt { text: I18n.t("Ampliación") }
                Slider {
                    Layout.fillWidth: true
                    from: 0; to: 1; step: 0.05; live: true
                    value: Settings.dock.magnify ? Settings.dock.magnifyAmount : 0
                    minText: I18n.t("No"); maxText: I18n.t("Grande")
                    onMoved: v => {
                        if (v < 0.05) Settings.set("dock", "magnify", false);
                        else Settings.setMany({ dock: { magnify: true, magnifyAmount: Math.max(0.15, v) } });
                    }
                }
            }
        }
        OptionRow {
            title: I18n.t("Posición en la pantalla")
            Choice {
                options: [{ v: "left", t: I18n.t("Izquierda") }, { v: "bottom", t: I18n.t("Abajo") }, { v: "right", t: I18n.t("Derecha") }, { v: "top", t: I18n.t("Arriba") }]
                value: Settings.dock.position
                onPicked: v => Settings.set("dock", "position", v)
            }
        }
        // como macOS: «Minimizar ventanas con» Efecto genio / Efecto de escala.
        // Lo aplica hyprlands/minimize.lua (lee settings.json en cada minimizado) con modules/effects/GenieFx.qml
        OptionRow {
            title: I18n.t("Minimizar ventanas con")
            Choice {
                options: [{ v: "genie", t: I18n.t("Efecto genio") }, { v: "scale", t: I18n.t("Efecto de escala") }]
                value: Settings.dock.minimizeEffect === "scale" ? "scale" : "genie"
                onPicked: v => Settings.set("dock", "minimizeEffect", v)
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
        OptionRow {
            title: I18n.t("Forma")
            Segmented {
                options: [{ v: true, t: I18n.t("Flotante") }, { v: false, t: I18n.t("Pegada al borde") }]
                value: Settings.dock.floating
                onPicked: v => Settings.set("dock", "floating", v)
            }
        }
        OptionRow {
            title: I18n.t("Posición de las apps")
            Segmented {
                options: [{ v: "center", t: I18n.t("Al centro") }, { v: "left", t: I18n.t("Al inicio") }]
                value: Settings.dock.align
                onPicked: v => Settings.set("dock", "align", v)
            }
        }
        OptionRow { title: I18n.t("Botón de Inicio (Launchpad)"); Toggle { checked: Settings.dock.showStart; onToggled: c => Settings.set("dock", "showStart", c) } }
        OptionRow { title: I18n.t("Botón de búsqueda"); Toggle { checked: Settings.dock.showSearch; onToggled: c => Settings.set("dock", "showSearch", c) } }
        OptionRow { title: I18n.t("Carpeta Descargas junto a la papelera"); Toggle { checked: Settings.dock.showDownloads; onToggled: c => Settings.set("dock", "showDownloads", c) } }
        OptionRow { title: I18n.t("Aviso de actualizaciones"); Toggle { checked: Settings.dock.showUpdates; onToggled: c => Settings.set("dock", "showUpdates", c) } }
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
