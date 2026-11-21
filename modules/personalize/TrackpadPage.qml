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

    // cabecera y vista previa: el trackpad con dos puntos, y una pantalla de ejemplo
    Txt { visible: page.hasTouchpad; text: I18n.t("Trackpad"); font.weight: Font.Bold; font.pixelSize: Theme.textNormal + 2 }
    RowLayout {
        visible: page.hasTouchpad
        Layout.fillWidth: true
        spacing: 16
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 144
            radius: 8
            color: Theme.alpha(Theme.fg, 0.05)
            border.width: 1; border.color: Theme.alpha(Theme.fg, 0.08)
            Rectangle {
                anchors.centerIn: parent
                width: 130; height: 84; radius: 14
                color: "transparent"
                border.width: 2; border.color: Theme.alpha(Theme.fg, 0.25)
                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater { model: 2; Rectangle { width: 10; height: 10; radius: 5; color: Theme.primary; opacity: 0.8 } }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 144
            radius: 8
            gradient: Gradient {
                GradientStop { position: 0; color: "#64a8ff" }
                GradientStop { position: 1; color: "#7b5cff" }
            }
            Rectangle { anchors.centerIn: parent; width: parent.width * 0.62; height: parent.height * 0.62; radius: 6; color: Qt.rgba(1, 1, 1, 0.85) }
        }
    }

    TabBar {
        visible: page.hasTouchpad
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
    // Solo informativo: los gestos se definen en Hyprland, aquí se muestran como en macOS.
    Group {
        visible: page.hasTouchpad && page.tab === "gestures"
        Layout.topMargin: 0
        help: I18n.t("Los gestos se configuran en ~/.config/hypr/hyprlands/misc.lua.")
        Repeater {
            model: [
                { t: I18n.t("Mission Control"), v: I18n.t("Desliza hacia arriba con tres dedos") },
                { t: I18n.t("Launchpad"), v: I18n.t("Desliza hacia abajo con tres dedos") },
                { t: I18n.t("Pasar de una ventana a otra"), v: I18n.t("Desliza a la izquierda o a la derecha con tres dedos") },
                { t: I18n.t("Pasar de un escritorio a otro"), v: I18n.t("Desliza a la izquierda o a la derecha con cuatro dedos") },
            ]
            OptionRow {
                required property var modelData
                title: modelData.t
                Txt { text: modelData.v; color: Theme.fgMuted; font.pixelSize: Theme.textSmall + 1 }
            }
        }
    }
}
