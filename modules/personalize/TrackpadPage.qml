import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Trackpad como en Ajustes del Sistema de macOS: pestañas «Apuntar y hacer clic»,
// «Desplazarse y zoom» y «Más gestos». Se aplica al instante en Hyprland (HyprApply).
ColumnLayout {
    id: page
    spacing: 16

    readonly property var t: Settings.touchpad
    property string tab: "point"
    property bool hasTouchpad: true
    Process {
        running: true
        command: ["sh", "-c", "grep -qiE 'touchpad|trackpad' /proc/bus/input/devices"]
        onExited: code => page.hasTouchpad = code === 0 || !!Quickshell.env("QUANTUM_DEMO_TOUCHPAD")
    }

    Group {
        visible: !page.hasTouchpad
        OptionRow {
            title: I18n.t("No se encontró ningún trackpad.")
            help: I18n.t("Si conectas uno, sus opciones aparecen aquí.")
            icon: "touchpad_mouse"; iconColor: "#8E8E93"
        }
    }

    Segmented {
        visible: page.hasTouchpad
        Layout.alignment: Qt.AlignHCenter
        options: [{ v: "point", t: I18n.t("Apuntar y hacer clic") }, { v: "scroll", t: I18n.t("Desplazarse y zoom") }, { v: "gestures", t: I18n.t("Más gestos") }]
        value: page.tab
        onPicked: v => page.tab = v
    }

    // ------------------------------------------------- apuntar y hacer clic
    Group {
        visible: page.hasTouchpad && page.tab === "point"
        Layout.topMargin: 0
        OptionRow {
            title: I18n.t("Velocidad del puntero")
            Slider {
                implicitWidth: 260
                from: -1; to: 1; step: 0.05; live: true; ticks: 9
                value: page.t.speed
                minText: I18n.t("Lenta"); maxText: I18n.t("Rápida")
                onMoved: v => Settings.set("touchpad", "speed", v)
            }
        }
        OptionRow {
            title: I18n.t("Clic secundario")
            Choice {
                options: [{ v: "clickfinger", t: I18n.t("Clic con dos dedos") }, { v: "button-areas", t: I18n.t("Clic en la esquina inferior derecha") }]
                value: page.t.clickMethod
                onPicked: v => Settings.set("touchpad", "clickMethod", v)
            }
        }
        OptionRow {
            title: I18n.t("Tocar para hacer clic")
            help: I18n.t("Toca con un dedo para hacer clic.")
            Toggle { checked: page.t.tapToClick; onToggled: c => Settings.set("touchpad", "tapToClick", c) }
        }
        OptionRow {
            title: I18n.t("Desactivar mientras escribes")
            help: I18n.t("Evita mover el puntero sin querer con la palma.")
            Toggle { checked: page.t.disableWhileTyping; onToggled: c => Settings.set("touchpad", "disableWhileTyping", c) }
        }
    }

    // ------------------------------------------------- desplazarse y zoom
    Group {
        visible: page.hasTouchpad && page.tab === "scroll"
        Layout.topMargin: 0
        OptionRow {
            title: I18n.t("Desplazamiento natural")
            help: I18n.t("El contenido sigue el movimiento de los dedos.")
            Toggle { checked: page.t.natural; onToggled: c => Settings.set("touchpad", "natural", c) }
        }
        OptionRow {
            title: I18n.t("Velocidad de desplazamiento")
            Slider {
                implicitWidth: 260
                from: 0.25; to: 3; step: 0.05; live: true
                value: page.t.scrollSpeed
                minText: I18n.t("Lenta"); maxText: I18n.t("Rápida")
                onMoved: v => Settings.set("touchpad", "scrollSpeed", v)
            }
        }
        OptionRow {
            title: I18n.t("Ampliar o reducir")
            help: I18n.t("Pellizca con dos dedos (en las apps que lo admiten).")
            Txt { text: I18n.t("Siempre activo"); color: Theme.fgMuted }
        }
    }

    // ------------------------------------------------- más gestos
    Group {
        visible: page.hasTouchpad && page.tab === "gestures"
        Layout.topMargin: 0
        help: I18n.t("Los gestos se configuran en ~/.config/hypr/hyprlands/misc.lua.")
        OptionRow { title: I18n.t("Mission Control"); help: I18n.t("Desliza hacia arriba con tres dedos"); icon: "view_quilt"; iconColor: "#8E8E93" }
        OptionRow { title: I18n.t("Launchpad"); help: I18n.t("Desliza hacia abajo con tres dedos"); icon: "apps"; iconColor: "#8E8E93" }
        OptionRow { title: I18n.t("Pasar de una ventana a otra"); help: I18n.t("Desliza a la izquierda o a la derecha con tres dedos"); icon: "tab"; iconColor: "#8E8E93" }
        OptionRow { title: I18n.t("Pasar de un escritorio a otro"); help: I18n.t("Desliza a la izquierda o a la derecha con cuatro dedos"); icon: "swap_horiz"; iconColor: "#8E8E93" }
    }
}
