import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Teclado como en Ajustes del Sistema de macOS: velocidad de repetición, retardo,
// luz del teclado, atajos de teclado y fuentes de entrada (distribución y Fcitx5).
ColumnLayout {
    id: page
    spacing: 16

    readonly property var k: Settings.keyboard
    property int kbdMax: 0
    property int kbdNow: 0
    property bool showShortcuts: false
    property var shortcuts: []

    Component.onCompleted: kbd.running = true
    Process {
        id: kbd
        command: ["brightnessctl", "-d", "*kbd_backlight*", "-m", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                if (p.length >= 5) { page.kbdNow = parseInt(p[2]); page.kbdMax = parseInt(p[4]); }
            }
        }
    }
    Process { id: kbdSet; onExited: kbd.running = true }
    Process {
        id: keys
        command: ["sh", Quickshell.shellDir + "/scripts/keybinds.sh"]
        stdout: StdioCollector {
            onStreamFinished: page.shortcuts = text.split("\n").map(l => l.trim()).filter(l => l).map(l => {
                const m = l.match(/^(\S+(?:\s\S+)*?)\s{2,}(.*)$/);
                return m ? { k: m[1], a: m[2] } : { k: l, a: "" };
            })
        }
    }

    // repetición: macOS va de «Desactivado/Lenta» a «Rápida»; Hyprland en teclas por segundo
    Group {
        OptionRow {
            title: I18n.t("Repetición de teclas")
            Slider {
                implicitWidth: 260
                from: 5; to: 60; step: 1
                value: page.k.repeatRate
                minText: I18n.t("Lenta"); maxText: I18n.t("Rápida")
                onMoved: v => Settings.set("keyboard", "repeatRate", Math.round(v))
            }
        }
        OptionRow {
            title: I18n.t("Retardo hasta repetir")
            Slider {
                implicitWidth: 260
                from: 0; to: 1; step: 0.02
                value: (1000 - page.k.repeatDelay) / 850
                minText: I18n.t("Largo"); maxText: I18n.t("Corto")
                onMoved: v => Settings.set("keyboard", "repeatDelay", Math.round(1000 - v * 850))
            }
        }
        OptionRow {
            title: I18n.t("Prueba aquí")
            Rectangle {
                implicitWidth: 260; implicitHeight: 28; radius: 7
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : "white"
                border.width: 1; border.color: Theme.alpha(Theme.fg, 0.15)
                TextInput {
                    id: tryIn
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font; font.pixelSize: Theme.textNormal
                    color: Theme.fg; clip: true
                    Txt { anchors.verticalCenter: parent.verticalCenter; visible: !tryIn.text; text: I18n.t("Mantén pulsada una tecla"); color: Theme.fgMuted }
                }
            }
        }
        OptionRow {
            visible: page.kbdMax > 0
            title: I18n.t("Luz del teclado")
            Segmented {
                options: Array.from({ length: page.kbdMax + 1 }, (_, i) => ({ v: i, t: i === 0 ? I18n.t("Apagada") : page.kbdMax === 2 ? (i === 1 ? I18n.t("Baja") : I18n.t("Alta")) : String(i) }))
                value: page.kbdNow
                onPicked: v => { kbdSet.command = ["brightnessctl", "-d", "*kbd_backlight*", "set", String(v)]; kbdSet.running = true; }
            }
        }
        NavRow {
            title: I18n.t("Atajos de teclado…")
            value: page.showShortcuts ? I18n.t("Ocultar") : ""
            onClicked: { page.showShortcuts = !page.showShortcuts; if (page.showShortcuts && page.shortcuts.length === 0) keys.running = true; }
        }
    }

    Group {
        visible: page.showShortcuts
        title: I18n.t("Atajos de teclado")
        help: I18n.t("Se cambian en ~/.config/hypr/variable.lua.")
        Repeater {
            model: page.shortcuts
            OptionRow {
                required property var modelData
                title: modelData.a
                Rectangle {
                    implicitWidth: kt.implicitWidth + 14; implicitHeight: 22; radius: 5
                    color: Theme.alpha(Theme.fg, 0.08)
                    Txt { id: kt; anchors.centerIn: parent; text: modelData.k; font.pixelSize: Theme.textSmall; font.family: "monospace" }
                }
            }
        }
    }

    Group {
        title: I18n.t("Fuentes de entrada")
        help: I18n.t("Para escribir en vietnamita (Telex, VNI) se usa Fcitx5; cambia de método con su atajo (por defecto Ctrl + Mayús).")
        OptionRow {
            title: I18n.t("Distribución del teclado")
            Choice {
                options: [{ v: "", t: I18n.t("La de Hyprland (us)") }, { v: "us", t: "English (US)" }, { v: "gb", t: "English (UK)" },
                          { v: "us(intl)", t: "English (US, intl.)" }, { v: "fr", t: "Français" }, { v: "de", t: "Deutsch" },
                          { v: "es", t: "Español" }, { v: "latam", t: "Español (Latinoamérica)" }, { v: "jp", t: "日本語" }, { v: "kr", t: "한국어" }]
                value: page.k.layout === "us" && page.k.variant === "intl" ? "us(intl)" : page.k.layout
                onPicked: v => {
                    const m = v.match(/^(\w+)\((\w+)\)$/);
                    Settings.setMany({ keyboard: m ? { layout: m[1], variant: m[2] } : { layout: v, variant: "" } });
                }
            }
        }
        OptionRow {
            title: I18n.t("Métodos de entrada")
            PillButton { text: I18n.t("Configurar Fcitx5…"); implicitHeight: 28; onClicked: Quickshell.execDetached(["fcitx5-configtool"]) }
        }
    }
}
