import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Ventanas y animaciones: esquinas, velocidad, botones de ventana y efectos.
ColumnLayout {
    id: page

    spacing: 16

    // Ventanita de muestra con su barra de título.
    component WinArt: Item {
        id: wa
        property real corner: 12
        property bool btnLeft: false
        Rectangle {
            anchors.fill: parent
            anchors.margins: 6
            radius: wa.corner
            color: Theme.surface
            border.width: 1
            border.color: Theme.alpha(Theme.fg, 0.12)
            clip: true
            Rectangle {
                width: parent.width; height: 24
                color: Theme.surfaceHighest
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    x: wa.btnLeft ? 64 : 10
                    text: "Mi ventana"
                    font.pixelSize: Theme.textSmall
                    color: Theme.fgMuted
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: wa.btnLeft ? 9 : parent.width - width - 10
                    spacing: wa.btnLeft ? 6 : 10
                    Repeater {
                        model: wa.btnLeft ? ["#FF5F57", "#FEBC2E", "#28C840"] : ["remove", "crop_square", "close"]
                        Item {
                            id: b
                            required property var modelData
                            width: wa.btnLeft ? 11 : 14; height: width
                            Rectangle { anchors.fill: parent; radius: width / 2; visible: wa.btnLeft; color: wa.btnLeft ? b.modelData : "transparent" }
                            Icon { anchors.centerIn: parent; visible: !wa.btnLeft; text: wa.btnLeft ? "" : b.modelData; size: 14; color: Theme.fg }
                        }
                    }
                }
            }
            Column {
                x: 12; y: 36; spacing: 7
                Rectangle { width: 70; height: 7; radius: 3.5; color: Theme.primary }
                Rectangle { width: 110; height: 7; radius: 3.5; color: Theme.alpha(Theme.fg, 0.2) }
                Rectangle { width: 90; height: 7; radius: 3.5; color: Theme.alpha(Theme.fg, 0.2) }
            }
        }
    }

    Group {
        title: "Esquinas"
        help: "Qué tan redondeados se ven los paneles, menús y tarjetas de Quantum."
        icon: "rounded_corner"
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: [{ v: "sharp", t: "Rectas", c: 3 }, { v: "soft", t: "Suaves", c: 10 }, { v: "round", t: "Redondeadas", c: 20 }]
                ChoiceCard {
                    id: cc
                    required property var modelData
                    title: modelData.t
                    selected: Settings.windows.corners === modelData.v
                    previewHeight: 96
                    onClicked: Settings.set("windows", "corners", modelData.v)
                    WinArt { anchors.fill: parent; corner: cc.modelData.c }
                }
            }
        }
    }

    Group {
        title: "Botones de las ventanas"
        help: "Dónde van minimizar, maximizar y cerrar. Se aplica a las ventanas que abras desde ahora."
        icon: "web_asset"
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            ChoiceCard {
                title: "A la derecha"
                help: "Como en Windows."
                selected: !Settings.windows.buttonsLeft
                previewHeight: 96
                onClicked: Settings.set("windows", "buttonsLeft", false)
                WinArt { anchors.fill: parent; corner: 10 }
            }
            ChoiceCard {
                title: "A la izquierda"
                help: "Como en macOS."
                selected: Settings.windows.buttonsLeft
                previewHeight: 96
                onClicked: Settings.set("windows", "buttonsLeft", true)
                WinArt { anchors.fill: parent; corner: 10; btnLeft: true }
            }
        }
    }

    Group {
        title: "Animaciones"
        help: "La velocidad al abrir, cerrar y mover ventanas y paneles."
        icon: "animation"
        OptionRow {
            title: "Velocidad"
            Segmented {
                options: [{ v: "none", t: "Sin animaciones" }, { v: "fast", t: "Rápidas" }, { v: "normal", t: "Normales" }, { v: "smooth", t: "Suaves" }]
                value: Settings.windows.animations
                onPicked: v => Settings.set("windows", "animations", v)
            }
        }
        OptionRow {
            title: "Al minimizar"
            help: "Cómo se va la ventana a la barra de tareas."
            visible: Settings.windows.animations !== "none"
            Segmented {
                options: [{ v: "zoom", t: "Encoger", i: "close_fullscreen" }, { v: "squeezimize", t: "Aspirar", i: "south" },
                          { v: "none", t: "Sin efecto", i: "block" }]
                value: Settings.windows.minimizeAnimation
                onPicked: v => Settings.set("windows", "minimizeAnimation", v)
            }
        }
        OptionRow {
            title: "Al abrir una ventana"
            visible: Settings.ui.advanced && Settings.windows.animations !== "none"
            Segmented {
                options: [{ v: "zoom", t: "Zoom", i: "zoom_in" }, { v: "fade", t: "Aparecer", i: "gradient" },
                          { v: "fire", t: "Fuego", i: "local_fire_department" }, { v: "spin", t: "Girar", i: "autorenew" }]
                value: Settings.windows.openAnimation
                onPicked: v => Settings.set("windows", "openAnimation", v)
            }
        }
        OptionRow {
            title: "Ventanas gelatina"
            help: "Las ventanas se estiran como gelatina al moverlas. Divertido, pero consume más."
            advanced: true
            Toggle { checked: Settings.windows.wobbly; onToggled: c => Settings.set("windows", "wobbly", c) }
        }
    }

    Group {
        title: "Organización"
        icon: "dashboard"
        OptionRow {
            title: "Mosaico automático"
            help: "Las ventanas se acomodan solas una al lado de otra, sin encimarse."
            Toggle { checked: Settings.windows.tiling; onToggled: c => Settings.set("windows", "tiling", c) }
        }
    }

    Group {
        title: "Barra de título"
        help: "Se aplica a las ventanas que abras desde ahora."
        icon: "toolbar"
        advanced: true
        OptionRow {
            title: "Alto de la barra de título"
            Slider {
                implicitWidth: 240
                from: 26; to: 44; step: 1
                value: Settings.windows.titleHeight
                text: Math.round(_shown) + " px"
                onMoved: v => Settings.set("windows", "titleHeight", Math.round(v))
            }
        }
        OptionRow {
            title: "Grosor del borde"
            Slider {
                implicitWidth: 240
                from: 0; to: 4; step: 1
                value: Settings.windows.borderSize
                text: Math.round(_shown) + " px"
                onMoved: v => Settings.set("windows", "borderSize", Math.round(v))
            }
        }
    }
}
