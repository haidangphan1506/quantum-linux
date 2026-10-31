import QtQuick
import Quickshell
import qs.services

// Escritorio en miniatura dibujado a partir de unos ajustes: sirve de vista previa
// en vivo y de imagen en las tarjetas de estilos. `v` tiene la forma de settings.json
// (solo las claves visuales); lo que falte sale de los valores de fábrica.
Rectangle {
    id: root

    property var v: ({})
    readonly property var d: Settings.defaults
    function get(sec, key, sub) {
        const s = v[sec] ?? {};
        if (sub !== undefined)
            return (s[key] ?? {})[sub] ?? d[sec][key][sub];
        return s[key] ?? d[sec][key];
    }

    readonly property bool light: get("appearance", "mode") === "light"
    readonly property color accent: get("appearance", "dynamicColors") ? Theme.primaryContainer : get("appearance", "accent")
    readonly property string wallpaper: v.appearance?.wallpaper ?? ""
    readonly property bool single: get("layout", "style") === "single"
    readonly property bool dockFloat: get("dock", "floating")
    readonly property bool dockLeft: get("dock", "align") === "left"
    readonly property bool topFloat: get("layout", "topBar", "floating")
    readonly property bool hidden: get("dock", "autohide")
    readonly property real k: width / 320
    readonly property real cr: ({ sharp: 1, soft: 4, round: 7 })[get("windows", "corners")] * k
    readonly property bool leftButtons: get("windows", "buttonsLeft")

    readonly property color panel: light ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(0.07, 0.07, 0.11, 0.9)
    readonly property color winBg: light ? "#F4F2FA" : "#1B1A24"
    readonly property color winBar: light ? "#E6E3F0" : "#26242F"
    readonly property color ink: light ? "#2A2738" : "#E4E0EE"

    radius: 10 * k
    clip: true
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: root.light ? "#C9C4F2" : "#140F2E" }
        GradientStop { position: 1; color: root.light ? "#F1D9F7" : "#3B2C9A" }
    }

    // fondo vivo: el átomo quieto en miniatura
    Image {
        visible: root.wallpaper === "quantum:live"
        anchors.centerIn: parent
        height: parent.height * 0.8; width: height
        source: Quickshell.shellDir + "/assets/quantum-mark.svg"
        sourceSize: Qt.size(256, 256)
        opacity: 0.85
    }
    Image {
        anchors.fill: parent
        readonly property bool real: root.wallpaper !== "" && root.wallpaper !== "quantum:live"
        visible: real
        source: real ? "file://" + root.wallpaper : ""
        sourceSize: Qt.size(480, 270)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.9
    }

    // barra superior
    Rectangle {
        visible: !root.single
        x: root.topFloat ? 6 * root.k : 0
        y: root.topFloat ? 5 * root.k : 0
        width: parent.width - 2 * x
        height: 13 * root.k
        radius: root.topFloat ? height / 2 : 0
        color: root.topFloat ? "transparent" : root.panel
        Rectangle { visible: root.topFloat; width: 46 * root.k; height: parent.height; radius: height / 2; color: root.panel }
        Rectangle { visible: root.topFloat; anchors.right: parent.right; width: 70 * root.k; height: parent.height; radius: height / 2; color: root.panel }
        Rectangle { x: 5 * root.k; anchors.verticalCenter: parent.verticalCenter; width: 22 * root.k; height: 3 * root.k; radius: height / 2; color: root.ink; opacity: 0.6 }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 6 * root.k; anchors.verticalCenter: parent.verticalCenter; width: 30 * root.k; height: 3 * root.k; radius: height / 2; color: root.ink; opacity: 0.6 }
    }

    // ventanas
    Repeater {
        model: [{ x: 0.07, y: 0.2, w: 0.5, h: 0.5, on: false }, { x: 0.42, y: 0.3, w: 0.48, h: 0.46, on: true }]
        Rectangle {
            id: w
            required property var modelData
            x: root.width * modelData.x
            y: root.height * modelData.y
            width: root.width * modelData.w
            height: root.height * modelData.h
            radius: root.cr
            color: root.winBg
            border.width: 1
            border.color: modelData.on ? root.accent : Qt.rgba(0.5, 0.5, 0.6, 0.3)
            clip: true
            Rectangle {
                width: parent.width
                height: 11 * root.k
                color: root.winBar
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.leftButtons ? 5 * root.k : parent.width - width - 5 * root.k
                    spacing: 3 * root.k
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: 4 * root.k; height: width; radius: width / 2
                            color: root.leftButtons ? ["#FF5F57", "#FEBC2E", "#28C840"][index] : (index === 2 ? "#E81123" : root.ink)
                            opacity: root.leftButtons || index === 2 ? 0.9 : 0.45
                        }
                    }
                }
            }
            Column {
                x: 7 * root.k; y: 17 * root.k
                spacing: 4 * root.k
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: (index === 0 ? 0.5 : 0.75 - index * 0.15) * w.width
                        height: 4 * root.k; radius: height / 2
                        color: index === 0 && w.modelData.on ? root.accent : Qt.rgba(0.5, 0.5, 0.6, 0.35)
                    }
                }
            }
        }
    }

    // barra de tareas
    Rectangle {
        id: dockBar
        readonly property bool full: root.single || !root.dockFloat
        readonly property real gap: root.dockFloat ? 5 * root.k : 0
        height: 15 * root.k
        width: full ? root.width - 2 * gap : 92 * root.k
        x: full ? gap : (root.width - width) / 2
        y: root.height - height - gap + (root.hidden ? height * 0.75 : 0)
        radius: root.dockFloat ? root.cr + 3 * root.k : 0
        color: root.panel
        opacity: root.hidden ? 0.7 : 1
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: !dockBar.full ? (parent.width - width) / 2 : root.dockLeft ? 6 * root.k : (parent.width - width) / 2
            spacing: 3.5 * root.k
            Repeater {
                model: 6
                Rectangle {
                    required property int index
                    width: 7 * root.k; height: width; radius: 2 * root.k
                    color: index === 0 ? root.accent : Qt.rgba(0.6, 0.6, 0.7, index === 3 ? 0.9 : 0.5)
                }
            }
        }
        Rectangle {
            visible: root.single
            anchors.right: parent.right; anchors.rightMargin: 6 * root.k
            anchors.verticalCenter: parent.verticalCenter
            width: 26 * root.k; height: 3 * root.k; radius: height / 2
            color: root.ink; opacity: 0.6
        }
    }
}
