import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Shapes
import qs.services

// Fondo vivo de Quantum: espacio profundo con estrellas, nebulosas de colores y el
// logo de Quantum al centro, con el cubo que brilla y electrones que orbitan dejando
// estela. `running` lo pausa (juegos, ventanas a pantalla completa) para no gastar.
Item {
    id: root

    property bool running: true
    property real time: 0
    property real logoScale: Math.min(width, height) / 1080
    // sin tarjeta gráfica (máquinas virtuales): 20 cuadros por segundo en vez de 60
    readonly property bool lowPower: !!Quickshell.env("QUANTUM_SOFTWARE_GL")
    FrameAnimation {
        running: root.running && root.visible && !root.lowPower
        onTriggered: root.time += frameTime
    }
    Timer {
        running: root.running && root.visible && root.lowPower
        interval: 50; repeat: true
        onTriggered: root.time += 0.05
    }

    readonly property color cCyan: "#4FD8FF"
    readonly property color cIndigo: "#6A5CFF"
    readonly property color cViolet: "#B14DFF"

    // fondo
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#05040C" }
            GradientStop { position: 0.55; color: "#0B0820" }
            GradientStop { position: 1; color: "#120B2E" }
        }
    }

    // nebulosas que derivan
    Repeater {
        model: [
            { c: root.cIndigo, x: 0.3, y: 0.35, r: 0.62, s: 0.05, o: 0.26 },
            { c: root.cViolet, x: 0.74, y: 0.66, r: 0.7, s: 0.04, o: 0.24 },
            { c: root.cCyan, x: 0.62, y: 0.22, r: 0.42, s: 0.06, o: 0.14 },
            { c: "#FF4F9A", x: 0.18, y: 0.8, r: 0.36, s: 0.05, o: 0.10 },
        ]
        Rectangle {
            required property var modelData
            required property int index
            width: root.width * modelData.r; height: width; radius: width / 2
            x: root.width * modelData.x - width / 2 + Math.sin(root.time * modelData.s + index * 1.7) * root.width * 0.05
            y: root.height * modelData.y - height / 2 + Math.cos(root.time * modelData.s * 0.8 + index) * root.height * 0.05
            color: modelData.c
            opacity: modelData.o
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
        }
    }

    // estrellas que titilan (posiciones fijas, pseudoaleatorias)
    Repeater {
        model: root.lowPower ? 50 : 140
        Rectangle {
            required property int index
            function rnd(k: real): real { const s = Math.sin(index * 12.9898 + k * 78.233) * 43758.5453; return s - Math.floor(s); }
            readonly property real sz: 1 + rnd(3) * 2.2
            x: rnd(1) * root.width
            y: rnd(2) * root.height
            width: sz; height: sz; radius: sz / 2
            color: rnd(5) > 0.8 ? "#C5C0FF" : "white"
            opacity: (0.25 + 0.55 * rnd(4)) * (0.6 + 0.4 * Math.sin(root.time * (0.6 + rnd(6) * 1.4) + index))
        }
    }

    // ----------------------------------------------------- el átomo de Quantum
    Item {
        id: atom
        anchors.centerIn: parent
        width: 860 * root.logoScale; height: width
        readonly property real k: width / 256          // el logo original mide 256
        scale: 1 + 0.015 * Math.sin(root.time * 0.5)
        rotation: Math.sin(root.time * 0.12) * 4

        // halo del núcleo
        Rectangle {
            anchors.centerIn: parent
            width: 120 * atom.k; height: width; radius: width / 2
            color: root.cIndigo
            opacity: 0.45 + 0.12 * Math.sin(root.time * 1.2)
            scale: 1 + 0.08 * Math.sin(root.time * 1.2)
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
        }

        // órbitas (como en el logo: vertical y ±30°) con su electrón y estela
        Repeater {
            model: [90, -30, 30]
            Item {
                id: orb
                required property real modelData
                required property int index
                anchors.fill: parent
                rotation: modelData
                readonly property real rx: 104 * atom.k
                readonly property real ry: 38 * atom.k
                readonly property real speed: [0.55, 0.42, 0.48][index]
                readonly property real a: root.time * speed + index * 2.09
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 10 * atom.k * 0.4
                        fillColor: "transparent"
                        strokeColor: Qt.rgba([0.31, 0.42, 0.69][orb.index], [0.85, 0.36, 0.3][orb.index], 1, 0.5)
                        PathAngleArc { centerX: atom.width / 2; centerY: atom.height / 2; radiusX: orb.rx; radiusY: orb.ry; startAngle: 0; sweepAngle: 360 }
                    }
                }
                // estela del electrón
                Repeater {
                    model: root.lowPower ? 5 : 14
                    Rectangle {
                        required property int index
                        readonly property real b: orb.a - index * 0.045
                        readonly property real sz: (16 - index) * atom.k * 0.55
                        x: atom.width / 2 + orb.rx * Math.cos(b) - sz / 2
                        y: atom.height / 2 + orb.ry * Math.sin(b) - sz / 2
                        width: sz; height: sz; radius: sz / 2
                        color: [root.cCyan, root.cIndigo, root.cViolet][orb.index]
                        opacity: index === 0 ? 1 : 0.5 * (1 - index / (root.lowPower ? 5 : 14))
                    }
                }
                // electrón con brillo
                Rectangle {
                    readonly property real sz: 9 * atom.k
                    x: atom.width / 2 + orb.rx * Math.cos(orb.a) - sz / 2
                    y: atom.height / 2 + orb.ry * Math.sin(orb.a) - sz / 2
                    width: sz; height: sz; radius: sz / 2
                    color: "white"
                    border.width: 2 * atom.k * 0.5
                    border.color: [root.cCyan, root.cIndigo, root.cViolet][orb.index]
                }
            }
        }

        // el cubo (núcleo), con sus tres caras y un brillo que lo recorre
        Shape {
            id: cube
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            readonly property real k: atom.k
            scale: 1 + 0.04 * Math.sin(root.time * 1.2)
            component Face: ShapePath {
                property real alpha: 1
                strokeColor: Qt.rgba(1, 1, 1, 0.6)
                strokeWidth: 2 * cube.k * 0.5
                joinStyle: ShapePath.RoundJoin
                fillGradient: LinearGradient {
                    x1: 105 * cube.k; y1: 102 * cube.k; x2: 151 * cube.k; y2: 154 * cube.k
                    GradientStop { position: 0; color: Qt.rgba(0.31, 0.85, 1, alpha) }
                    GradientStop { position: 0.5; color: Qt.rgba(0.42, 0.36, 1, alpha) }
                    GradientStop { position: 1; color: Qt.rgba(0.69, 0.3, 1, alpha) }
                }
            }
            Face {
                alpha: 1
                startX: 128 * cube.k; startY: 102 * cube.k
                PathLine { x: 150.6 * cube.k; y: 115 * cube.k }
                PathLine { x: 128 * cube.k; y: 128 * cube.k }
                PathLine { x: 105.4 * cube.k; y: 115 * cube.k }
                PathLine { x: 128 * cube.k; y: 102 * cube.k }
            }
            Face {
                alpha: 0.75
                startX: 105.4 * cube.k; startY: 115 * cube.k
                PathLine { x: 128 * cube.k; y: 128 * cube.k }
                PathLine { x: 128 * cube.k; y: 154 * cube.k }
                PathLine { x: 105.4 * cube.k; y: 141 * cube.k }
                PathLine { x: 105.4 * cube.k; y: 115 * cube.k }
            }
            Face {
                alpha: 0.55
                startX: 128 * cube.k; startY: 128 * cube.k
                PathLine { x: 150.6 * cube.k; y: 115 * cube.k }
                PathLine { x: 150.6 * cube.k; y: 141 * cube.k }
                PathLine { x: 128 * cube.k; y: 154 * cube.k }
                PathLine { x: 128 * cube.k; y: 128 * cube.k }
            }
        }
    }

    // viñeta suave
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.25) }
            GradientStop { position: 0.25; color: "transparent" }
            GradientStop { position: 0.75; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) }
        }
    }
}
