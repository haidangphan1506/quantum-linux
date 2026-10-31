import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components

// Indicador de volumen y brillo al cambiarlos: una píldora que sube desde abajo
// con rebote, barra con el degradado de Quantum y el ícono que «salta» con cada cambio.
PanelWindow {
    id: win

    property string kind: "volume"
    property bool shown: false
    property real progress: 0
    // Al iniciar, Pipewire informa el volumen actual: no mostrar el OSD por eso.
    property bool armed: false

    // demo >= 0: valor de mentira para videos (qs ipc call osd demo volume 0.6)
    property real demo: -1
    readonly property real value: demo >= 0 ? demo : kind === "volume" ? (Audio.muted ? 0 : Audio.volume) : Brightness.value
    readonly property string glyph: kind === "volume" ? Audio.icon
        : value < 0.34 ? "brightness_5" : value < 0.67 ? "brightness_6" : "brightness_7"

    visible: shown || progress > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-osd"
    exclusionMode: ExclusionMode.Ignore
    anchors { bottom: true }
    margins { bottom: 84 }
    implicitWidth: 360
    implicitHeight: 110
    color: "transparent"
    mask: Region {}

    function show(k: string): void {
        if (!armed)
            return;
        kind = k;
        shown = true;
        bump.restart();
        hideTimer.restart();
    }

    onShownChanged: {
        anim.to = shown ? 1 : 0;
        anim.duration = shown ? 460 : 220;
        anim.easing.type = shown ? Easing.OutBack : Easing.InCubic;
        anim.restart();
    }
    NumberAnimation { id: anim; target: win; property: "progress"; easing.overshoot: 1.6 }

    Timer { interval: 2500; running: true; onTriggered: win.armed = true }
    Timer { id: hideTimer; interval: 1600; onTriggered: win.shown = false }
    onProgressChanged: if (progress < 0.001 && !shown) demo = -1

    Connections { target: Audio; function onChanged() { win.show("volume"); Sounds.play("volume"); } }
    Connections { target: Brightness; function onChanged() { win.show("brightness"); } }

    // Para probar: qs ipc call osd test volume|brightness
    IpcHandler {
        target: "osd"
        function test(k: string): void { win.armed = true; win.show(k); }
        function demo(k: string, v: real): void { win.armed = true; win.demo = v; win.show(k); }
    }

    Card {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: 330
        height: 64
        radius: height / 2
        color: Theme.alpha(Theme.surface, 0.92)
        opacity: Math.min(1, win.progress * 1.5)
        scale: 0.8 + 0.2 * win.progress
        transform: Translate { y: (1 - win.progress) * 36 }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 22
            spacing: 14

            // ícono en un círculo con el degradado de Quantum
            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: 22
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.brandCyan }
                    GradientStop { position: 0.55; color: Theme.brandIndigo }
                    GradientStop { position: 1; color: Theme.brandViolet }
                }
                Icon {
                    id: ic
                    anchors.centerIn: parent
                    text: win.glyph
                    size: 24
                    fill: 1
                    color: "white"
                }
                SequentialAnimation {
                    id: bump
                    NumberAnimation { target: ic; property: "scale"; to: 1.25; duration: 90; easing.type: Easing.OutQuad }
                    NumberAnimation { target: ic; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true
                    Txt {
                        text: win.kind === "volume" ? (Audio.muted ? "Silenciado" : "Volumen") : "Brillo"
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    Txt {
                        text: Math.round(win.value * 100) + "%"
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                // barra con degradado y un punto brillante en la punta
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 10
                    radius: 5
                    color: Theme.surfaceHighest
                    Rectangle {
                        id: fill
                        width: Math.max(height, parent.width * win.value)
                        height: parent.height
                        radius: 5
                        opacity: win.value > 0 ? 1 : 0.3
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.brandCyan }
                            GradientStop { position: 0.55; color: Theme.brandIndigo }
                            GradientStop { position: 1; color: Theme.brandViolet }
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 14
                            radius: 7
                            color: "white"
                            visible: win.value > 0
                        }
                    }
                }
            }
        }
    }
}
