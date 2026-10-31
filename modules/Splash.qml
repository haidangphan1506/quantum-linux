import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// Pantalla de carga al iniciar sesión: continúa la animación de arranque (el átomo
// de Quantum) mientras el escritorio carga de fondo, y luego se desvanece para que
// aparezca todo de golpe. Es liviana a propósito (sin desenfoques ni formas) para
// mostrarse enseguida aunque sea la primera vez o no haya tarjeta gráfica.
// No aparece al recargar el shell (por ejemplo, tras una actualización).
Scope {
    id: root

    required property bool desktopReady       // el resto del shell ya cargó
    signal sessionStarted                     // la pantalla se fue: es el inicio de la sesión

    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quantum-session-ready"
    property bool needed: false
    property bool checked: false
    property bool leaving: false
    property bool minTimePassed: false

    // ¿Es el inicio de la sesión? (si el marcador no existe)
    Process {
        running: true
        command: ["sh", "-c", "[ -e \"$1\" ]", "sh", root.marker]
        onExited: code => {
            root.needed = code !== 0 && !Quickshell.env("QUANTUM_NO_SPLASH");
            root.checked = true;
        }
    }
    Process { id: mark; command: ["sh", "-c", ": > \"$1\"", "sh", root.marker] }

    Timer { running: root.needed; interval: 1400; onTriggered: root.minTimePassed = true }
    // espera a que el escritorio esté listo (y un respiro para que pinte su primer cuadro)
    Timer {
        running: root.needed && root.desktopReady && root.minTimePassed && !root.leaving
        interval: 350
        onTriggered: { root.leaving = true; mark.running = true; root.sessionStarted(); }
    }

    LazyLoader {
        active: root.needed && !root.gone
        PanelWindow {
            id: win
            screen: Quickshell.screens[0]
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-splash"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            property real time: 0
            FrameAnimation { running: true; onTriggered: win.time += frameTime }

            property real fade: root.leaving ? 0 : 1
            Behavior on fade { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
            onFadeChanged: if (fade === 0) root.gone = true

            Item {
                anchors.fill: parent
                opacity: win.fade
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#05040C" }
                        GradientStop { position: 1; color: "#120B2E" }
                    }
                }
                // estrellas
                Repeater {
                    model: 60
                    Rectangle {
                        required property int index
                        function rnd(k: real): real { const s = Math.sin(index * 12.9898 + k * 78.233) * 43758.5453; return s - Math.floor(s); }
                        x: rnd(1) * win.width; y: rnd(2) * win.height
                        width: 2 + rnd(3) * 2; height: width; radius: width / 2
                        color: "white"
                        opacity: (0.15 + 0.45 * rnd(4)) * (0.55 + 0.45 * Math.sin(win.time * (1 + rnd(6) * 2) + index))
                    }
                }
                // el átomo: crece un poco al irse, como si el escritorio saliera de él
                Item {
                    id: atom
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -30
                    width: 360; height: 360
                    scale: (1 + 0.03 * Math.sin(win.time * 1.6)) * (1 + 0.5 * (1 - win.fade))
                    readonly property real k: width / 256
                    Image {
                        anchors.fill: parent
                        source: Quickshell.shellDir + "/assets/quantum-atom.svg"
                        sourceSize: Qt.size(720, 720)
                    }
                    Repeater {
                        model: [90, -30, 30]
                        Item {
                            id: orb
                            required property real modelData
                            required property int index
                            anchors.fill: parent
                            rotation: modelData
                            readonly property real a: win.time * [2.4, 1.9, 2.1][index] + index * 2.09
                            Repeater {
                                model: 6
                                Rectangle {
                                    required property int index
                                    readonly property real b: orb.a - index * 0.08
                                    readonly property real sz: (22 - index * 2.6)
                                    x: atom.width / 2 + 104 * atom.k * Math.cos(b) - sz / 2
                                    y: atom.height / 2 + 38 * atom.k * Math.sin(b) - sz / 2
                                    width: sz; height: sz; radius: sz / 2
                                    color: index === 0 ? "white" : ["#4FD8FF", "#6A5CFF", "#B14DFF"][orb.index]
                                    opacity: index === 0 ? 1 : 0.55 * (1 - index / 6)
                                    border.width: index === 0 ? 3 : 0
                                    border.color: ["#4FD8FF", "#6A5CFF", "#B14DFF"][orb.index]
                                }
                            }
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: atom.bottom
                    anchors.topMargin: 40
                    text: "Preparando tu escritorio"
                    font.family: "Inter"
                    font.pixelSize: 17
                    color: "#9C95B8"
                    opacity: Math.min(1, Math.max(0, (win.time - 1.2) / 0.6)) * (0.7 + 0.3 * Math.sin(win.time * 2))
                }
            }
        }
    }
    property bool gone: false
}
