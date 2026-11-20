import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Mouse como en Ajustes del Sistema de macOS: velocidad del puntero, desplazamiento
// natural, clic secundario, velocidad de desplazamiento y aceleración; además el tamaño
// del puntero. Se aplica al instante en Hyprland (HyprApply).
ColumnLayout {
    id: page
    spacing: 16

    readonly property var m: Settings.mouse

    Group {
        OptionRow {
            title: I18n.t("Velocidad del puntero")
            Slider {
                implicitWidth: 260
                from: -1; to: 1; step: 0.05; live: true; ticks: 9
                value: page.m.speed
                minText: I18n.t("Lenta"); maxText: I18n.t("Rápida")
                onMoved: v => Settings.set("mouse", "speed", v)
            }
        }
        OptionRow {
            title: I18n.t("Desplazamiento natural")
            help: I18n.t("El contenido sigue el movimiento de la rueda, como en un celular.")
            Toggle { checked: page.m.natural; onToggled: c => Settings.set("mouse", "natural", c) }
        }
        OptionRow {
            title: I18n.t("Clic secundario")
            Choice {
                options: [{ v: false, t: I18n.t("Clic en el lado derecho") }, { v: true, t: I18n.t("Clic en el lado izquierdo") }]
                value: page.m.leftHanded
                onPicked: v => Settings.set("mouse", "leftHanded", v)
            }
        }
        OptionRow {
            title: I18n.t("Velocidad de desplazamiento")
            Slider {
                implicitWidth: 260
                from: 0.25; to: 3; step: 0.05; live: true
                value: page.m.scrollSpeed
                minText: I18n.t("Lenta"); maxText: I18n.t("Rápida")
                onMoved: v => Settings.set("mouse", "scrollSpeed", v)
            }
        }
    }

    Group {
        OptionRow {
            title: I18n.t("Aceleración del puntero")
            help: page.m.accel ? I18n.t("El puntero llega más lejos si mueves el mouse rápido.") : I18n.t("El puntero se mueve siempre igual. Ideal para juegos.")
            Toggle { checked: page.m.accel; onToggled: c => Settings.set("mouse", "accel", c) }
        }
        OptionRow {
            title: I18n.t("Tamaño del puntero")
            Segmented {
                options: [{ v: 24, t: I18n.t("Normal") }, { v: 32, t: I18n.t("Grande") }, { v: 48, t: I18n.t("Muy grande") }]
                value: page.m.cursorSize
                onPicked: v => Settings.set("mouse", "cursorSize", v)
            }
        }
    }
}
