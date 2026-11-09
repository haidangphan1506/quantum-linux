import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Mouse y touchpad: velocidad, aceleración, desplazamiento natural, tocar para hacer
// clic… Van a la sección [input] de wayfire.ini (quantum-theme) y se aplican al instante.
ColumnLayout {
    id: page

    spacing: 16
    readonly property var m: Settings.mouse
    readonly property var t: Settings.touchpad
    // la sección del touchpad solo aparece si el equipo tiene uno
    property bool hasTouchpad: false
    Process {
        running: true
        command: ["sh", "-c", "grep -qiE 'touchpad|trackpad' /proc/bus/input/devices"]
        onExited: code => page.hasTouchpad = code === 0
    }

    // Dibujo de un mouse o un touchpad, con flechas que muestran hacia dónde va el contenido
    component Art: Item {
        id: art
        property bool pad: false
        property bool natural: false
        Rectangle {
            anchors.centerIn: parent
            width: art.pad ? 120 : 62; height: art.pad ? 80 : 96
            radius: art.pad ? 14 : 31
            color: Theme.surfaceHighest
            border.width: 2; border.color: Theme.alpha(Theme.fg, 0.15)
            // rueda o dos dedos
            Rectangle { visible: !art.pad; anchors.horizontalCenter: parent.horizontalCenter; y: 16; width: 8; height: 18; radius: 4; color: Theme.primary }
            Rectangle { visible: !art.pad; anchors.horizontalCenter: parent.horizontalCenter; y: 0; width: 2; height: 40; color: Theme.alpha(Theme.fg, 0.15) }
            Row {
                visible: art.pad; anchors.centerIn: parent; spacing: 10
                Repeater { model: 2; Rectangle { width: 16; height: 16; radius: 8; color: Theme.primary } }
            }
        }
        // dedo hacia arriba → el contenido va hacia… arriba (natural) o abajo
        Column {
            anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Icon { text: "north"; size: 18; color: Theme.fgMuted }
            Txt { text: "dedo"; font.pixelSize: 10; color: Theme.fgMuted }
        }
        Column {
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Icon { anchors.horizontalCenter: parent.horizontalCenter; text: art.natural ? "north" : "south"; size: 18; color: Theme.primary }
            Txt { text: I18n.t("página"); font.pixelSize: 10; color: Theme.fgMuted }
        }
    }

    // Zona para probar el desplazamiento y la velocidad
    component TryZone: Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: 120
        radius: 14; color: Theme.surfaceHigh; clip: true
        border.width: 1; border.color: Theme.alpha(Theme.fg, 0.08)
        ListView {
            anchors.fill: parent; anchors.margins: 8
            spacing: 6
            model: 30
            delegate: Rectangle {
                required property int index
                width: ListView.view.width; height: 30; radius: 8
                color: index % 2 ? Theme.alpha(Theme.primary, 0.1) : "transparent"
                Txt { x: 12; anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Línea ") + (parent.index + 1) + I18n.t(" · prueba aquí el desplazamiento"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
            }
        }
    }

    // ---------------------------------------------------------------- mouse
    Group {
        title: I18n.t("Mouse")
        help: I18n.t("Los cambios se aplican al instante.")
        icon: "mouse"

        OptionRow {
            title: I18n.t("Velocidad del puntero")
            Slider {
                Layout.preferredWidth: 300; from: -1; to: 1; step: 0.05; live: true
                value: page.m.speed
                text: value < -0.3 ? I18n.t("Lenta") : value > 0.3 ? I18n.t("Rápida") : I18n.t("Normal")
                onMoved: v => Settings.set("mouse", "speed", v)
            }
        }
        OptionRow {
            title: I18n.t("Aceleración del mouse")
            help: page.m.accel ? I18n.t("El puntero llega más lejos si mueves el mouse rápido.") : I18n.t("Sin aceleración: el puntero se mueve siempre igual. Ideal para juegos.")
            Toggle { checked: page.m.accel; onToggled: v => Settings.set("mouse", "accel", v) }
        }
        OptionRow {
            title: I18n.t("Desplazamiento natural")
            help: I18n.t("La página sigue a la rueda, como en un celular.")
            Toggle { checked: page.m.natural; onToggled: v => Settings.set("mouse", "natural", v) }
        }
        OptionRow {
            title: I18n.t("Velocidad de la rueda")
            Slider {
                Layout.preferredWidth: 300; from: 0.25; to: 3; step: 0.05; live: true
                value: page.m.scrollSpeed; text: value.toFixed(1) + "×"
                onMoved: v => Settings.set("mouse", "scrollSpeed", v)
            }
        }
        OptionRow {
            title: I18n.t("Modo zurdo")
            help: I18n.t("Cambia el botón izquierdo por el derecho.")
            advanced: true
            Toggle { checked: page.m.leftHanded; onToggled: v => Settings.set("mouse", "leftHanded", v) }
        }
        TryZone {}
    }

    // ---------------------------------------------------------------- touchpad
    Group {
        title: I18n.t("Touchpad")
        help: I18n.t("El panel táctil de tu laptop.")
        icon: "touchpad_mouse"
        visible: page.hasTouchpad || !!Quickshell.env("QUANTUM_DEMO_TOUCHPAD")

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: [{ n: false, t: I18n.t("Tradicional"), h: I18n.t("Como un mouse con rueda.") }, { n: true, t: I18n.t("Natural"), h: I18n.t("Como un celular.") }]
                ChoiceCard {
                    id: cc
                    required property var modelData
                    title: modelData.t
                    help: modelData.h
                    selected: page.t.natural === modelData.n
                    previewHeight: 110
                    onClicked: Settings.set("touchpad", "natural", modelData.n)
                    Art { anchors.fill: parent; pad: true; natural: cc.modelData.n }
                }
            }
        }
        OptionRow {
            title: I18n.t("Velocidad del puntero")
            Slider {
                Layout.preferredWidth: 300; from: -1; to: 1; step: 0.05; live: true
                value: page.t.speed
                text: value < -0.3 ? I18n.t("Lenta") : value > 0.3 ? I18n.t("Rápida") : I18n.t("Normal")
                onMoved: v => Settings.set("touchpad", "speed", v)
            }
        }
        OptionRow {
            title: I18n.t("Tocar para hacer clic")
            help: I18n.t("Un toque suave cuenta como clic, sin apretar el touchpad.")
            Toggle { checked: page.t.tapToClick; onToggled: v => Settings.set("touchpad", "tapToClick", v) }
        }
        OptionRow {
            title: I18n.t("Desactivar mientras escribes")
            help: I18n.t("Evita mover el puntero sin querer con la palma.")
            Toggle { checked: page.t.disableWhileTyping; onToggled: v => Settings.set("touchpad", "disableWhileTyping", v) }
        }
        OptionRow {
            title: I18n.t("Clic derecho")
            Segmented {
                options: [{ v: "clickfinger", t: I18n.t("Con dos dedos"), i: "touch_app" }, { v: "button-areas", t: I18n.t("Esquina derecha"), i: "south_east" }]
                value: page.t.clickMethod
                onPicked: v => Settings.set("touchpad", "clickMethod", v)
            }
        }
        OptionRow {
            title: I18n.t("Velocidad del desplazamiento")
            advanced: true
            Slider {
                Layout.preferredWidth: 300; from: 0.25; to: 3; step: 0.05; live: true
                value: page.t.scrollSpeed; text: value.toFixed(1) + "×"
                onMoved: v => Settings.set("touchpad", "scrollSpeed", v)
            }
        }
    }

    // ---------------------------------------------------------------- puntero
    Group {
        title: I18n.t("Puntero")
        icon: "arrow_selector_tool"
        OptionRow {
            title: I18n.t("Tamaño")
            Segmented {
                options: [{ v: 24, t: I18n.t("Normal") }, { v: 32, t: I18n.t("Grande") }, { v: 48, t: I18n.t("Muy grande") }]
                value: page.m.cursorSize
                onPicked: v => Settings.set("mouse", "cursorSize", v)
            }
        }
    }
}
