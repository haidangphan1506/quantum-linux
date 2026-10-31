import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Aviso «Reinicia para terminar de actualizar»: aparece cuando una actualización
// (quantum-update, Quantum Store, yay o pacman) termina. «Más tarde» lo vuelve a mostrar
// a las 2 horas; mientras tanto la barra muestra un botón para reiniciar.
// Para probar: qs ipc call updates rebootPrompt
PanelWindow {
    id: win

    readonly property bool open: Updates.rebootAsk && Updates.rebootNeeded
    property real k: 0
    readonly property bool serp: Serp.on
    readonly property color accent: serp ? Serp.pink : Theme.primary
    readonly property color accentFg: serp ? Serp.pinkFg : Theme.primaryFg

    visible: open || k > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-reboot"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0, 0, 0, 0.45 * k)

    onOpenChanged: {
        anim.to = open ? 1 : 0;
        anim.duration = Math.max(1, (open ? 420 : 180) * Theme.animMult);
        anim.easing.type = open ? Easing.OutBack : Easing.InCubic;
        anim.restart();
        if (open) Sounds.play("notification");
    }
    NumberAnimation { id: anim; target: win; property: "k" }

    MouseArea { anchors.fill: parent }        // el aviso pide una respuesta

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 560; height: col.implicitHeight + 64
        radius: win.serp ? 18 : 28
        color: win.serp ? Serp.bg : Theme.surfaceContainer
        border.width: 1; border.color: win.serp ? Qt.rgba(0.96, 0.65, 0.79, 0.25) : Theme.alpha(Theme.fg, 0.08)
        opacity: Math.min(1, win.k * 1.4)
        scale: 0.9 + 0.1 * win.k
        clip: true

        // halo, como los paneles de Serpantium / brillo del degradado de Quantum
        Rectangle {
            width: 520; height: 520; radius: 260; x: card.width - 260; y: -300
            color: win.serp ? Qt.rgba(1, 1, 1, 0.02) : Theme.alpha(Theme.primary, 0.08)
            border.width: 1; border.color: win.serp ? Qt.rgba(0.96, 0.65, 0.79, 0.06) : "transparent"
        }

        Column {
            id: col
            x: 32; y: 32; width: card.width - 64; spacing: 16

            // ícono que gira despacio
            Rectangle {
                width: 72; height: 72; radius: 36
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: win.serp ? "#F4A7C9" : Theme.brandCyan }
                    GradientStop { position: 1; color: win.serp ? "#E07BAA" : Theme.brandViolet }
                }
                Icon {
                    anchors.centerIn: parent; text: "restart_alt"; size: 38; fill: 1
                    color: win.serp ? Serp.pinkFg : "white"
                    RotationAnimation on rotation { running: win.open; from: 0; to: -360; duration: 3200; loops: Animation.Infinite }
                }
            }
            Txt {
                width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                text: "Reinicia para terminar de actualizar"
                font.pixelSize: 24; font.weight: Font.Bold
                color: win.serp ? Serp.fg : Theme.fg
            }
            Txt {
                width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                readonly property string what: Updates.friendly()
                text: "Quantum se actualizó" + (what ? " (" + what + ")" : "") +
                      ". Los cambios se aplican al reiniciar. Guarda lo que estés haciendo antes."
                font.pixelSize: 15; lineHeight: 1.15
                color: win.serp ? Serp.muted : Theme.fgMuted
            }
            Txt {
                text: Updates.rebootPackages.length === 1 ? "1 paquete actualizado" : Updates.rebootPackages.length + " paquetes actualizados"
                font.pixelSize: 12
                color: win.serp ? Serp.muted : Theme.fgMuted
                opacity: 0.8
            }
            Item { width: 1; height: 4 }
            Row {
                anchors.right: parent.right
                spacing: 12
                component Btn: Rectangle {
                    id: b
                    property string label: ""
                    property string icon: ""
                    property bool primary: false
                    signal clicked()
                    width: row.implicitWidth + 44; height: 48; radius: win.serp ? 12 : 24
                    color: primary ? win.accent : ma.containsMouse ? Theme.alpha(win.serp ? Serp.fg : Theme.fg, 0.08) : "transparent"
                    border.width: primary ? 0 : 1; border.color: Theme.alpha(win.serp ? Serp.fg : Theme.fg, 0.18)
                    scale: ma.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    Row {
                        id: row; anchors.centerIn: parent; spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; visible: b.icon !== ""; text: b.icon; size: 20; color: b.primary ? win.accentFg : (win.serp ? Serp.fg : Theme.fg) }
                        Txt { anchors.verticalCenter: parent.verticalCenter; text: b.label; font.pixelSize: 15; font.weight: Font.DemiBold; color: b.primary ? win.accentFg : (win.serp ? Serp.fg : Theme.fg) }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
                }
                Btn { label: "Más tarde"; onClicked: Updates.snoozeReboot() }
                Btn { label: "Reiniciar ahora"; icon: "restart_alt"; primary: true; onClicked: Updates.reboot() }
            }
        }
    }

    Item {
        focus: win.open
        Keys.onEscapePressed: Updates.snoozeReboot()     // sin Enter: alguien escribiendo podría reiniciar sin querer
    }
}
