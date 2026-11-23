// Botones de ventana estilo macOS (rojo cierra, amarillo minimiza al dock, verde zoom 3/4 <-> completo).
// Ajustes del Sistema no tiene barra hyprbars (titlebar.lua: no_bar), así que los dibuja aquí y llama
// a las funciones de ventana de Hyprland (config/hypr/hyprlands/minimize.lua) sobre la ventana enfocada.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

RowLayout {
    id: wb
    signal closeRequested()
    spacing: 8
    readonly property bool focused: wb.Window.active
    HoverHandler { id: wbHover }

    Repeater {
        model: [
            { a: "close", c: "#ff5f57", f: "#4d0000", g: "×" },
            { a: "min", c: "#febc2e", f: "#5a3e00", g: "−" },
            { a: "max", c: "#28c840", f: "#004d00", g: "+" }
        ]
        Rectangle {
            id: btn
            required property var modelData
            implicitWidth: 13; implicitHeight: 13; radius: 6.5
            color: wb.focused || wbHover.hovered ? modelData.c : Theme.alpha(Theme.fg, 0.18)
            border.color: Qt.rgba(0, 0, 0, 0.14)
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -0.5
                visible: wbHover.hovered
                text: btn.modelData.g
                font.pixelSize: 12; font.weight: Font.Black
                color: btn.modelData.f
            }
            MouseArea {
                anchors.fill: parent
                onPressed: btn.opacity = 0.75
                onReleased: btn.opacity = 1
                onClicked: {
                    if (btn.modelData.a === "close") wb.closeRequested();
                    else if (btn.modelData.a === "min") Quickshell.execDetached(["hyprctl", "eval", "cael_minimize('')"]);
                    else Quickshell.execDetached(["hyprctl", "eval", "cael_toggle_size('')"]);
                }
            }
        }
    }
}
