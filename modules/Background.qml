import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Fondo de pantalla en cada monitor. Al cambiarlo, el nuevo se revela con un
// círculo que crece desde el centro, con un anillo de luz en el borde.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData
        // «quantum:live» = fondo vivo (el átomo de Quantum animado); si no, una imagen
        readonly property bool live: Settings.appearance.wallpaper === "quantum:live"
        readonly property string source: !live && Settings.appearance.wallpaper ? "file://" + Settings.appearance.wallpaper : ""
        // radio del círculo que revela el fondo nuevo
        property real radius: 0
        readonly property real maxRadius: Math.hypot(width, height) / 2 + 40
        property bool revealing: false

        screen: modelData
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quantum-background"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.surface

        Component.onCompleted: under.source = source
        onSourceChanged: {
            if (!under.source.toString() || Theme.animMult === 0)
                under.source = source;
            else
                over.source = source;
        }

        component Wall: Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize: Qt.size(win.width, win.height)
        }

        // el fondo actual
        Wall { id: under; visible: !win.live }

        // el fondo nuevo: se carga escondido y se muestra a través del círculo
        Wall {
            id: over
            visible: false
            onStatusChanged: {
                if (status === Image.Ready && source.toString() === win.source) {
                    win.radius = 0;
                    win.revealing = true;
                    reveal.restart();
                }
            }
        }
        NumberAnimation {
            id: reveal
            target: win
            property: "radius"
            to: win.maxRadius
            duration: Math.round(1100 * Math.max(0.5, Theme.animMult))
            easing.type: Easing.InOutCubic
            // al terminar, el nuevo pasa a ser el de abajo
            onFinished: under.source = over.source
        }
        Connections {
            target: under
            function onStatusChanged() {
                if (under.status === Image.Ready && under.source === over.source) {
                    win.revealing = false;
                    over.source = "";
                }
            }
        }

        Item {
            id: mask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                x: parent.width / 2 - win.radius
                y: parent.height / 2 - win.radius
                width: win.radius * 2
                height: width
                radius: win.radius
                color: "white"
            }
        }
        MultiEffect {
            anchors.fill: parent
            visible: win.revealing && !win.live
            source: over
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.2
        }
        // anillo de luz con los colores de Quantum en el borde del círculo
        Rectangle {
            visible: win.revealing && !win.live && win.radius < win.maxRadius - 1
            x: win.width / 2 - win.radius
            y: win.height / 2 - win.radius
            width: win.radius * 2
            height: width
            radius: win.radius
            color: "transparent"
            border.width: 3
            border.color: Theme.alpha(Theme.brandCyan, 0.7 * (1 - win.radius / win.maxRadius))
        }

        // Fondo vivo: se pausa con juegos, ventanas a pantalla completa o maximizadas,
        // el modo juego o la pantalla bloqueada, para no gastar batería ni gráfica.
        LazyLoader {
            active: win.live
            LiveWallpaper {
                parent: win.contentItem
                anchors.fill: parent
                running: !Shell.gameMode && !(Wm.active?.fullscreen ?? false) && !(Wm.active?.maximized ?? false)
                         && Settings.windows.animations !== "none"
            }
        }
    }
}
