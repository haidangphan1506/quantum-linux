import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components

// Vista previa tipo Quick Look: imagen o video en una ventana flotante con cabecera.
// Thunar la abre con Space (acción «Quick Look» en ~/.config/Thunar/uca.xml),
// y el dock / doble clic la abren vía Shell.preview (cael-quicklook.desktop):
//   qs -c caelestia ipc call preview open /ruta/archivo
//   Space / Esc / clic fuera = cerrar. Clic en el video = pausar / reproducir.
Scope {
    id: root

    property string path: ""
    property bool shown: false
    property real progress: 0
    property bool full: false      // botón verde: ventana a pantalla completa
    readonly property bool isVid: Wallpaper.isVideo(path)
    readonly property string fileName: path.split("/").pop()

    // Mismo archivo otra vez = cerrar (como Quick Look con Space)
    function open(p: string): void {
        if (shown && p === path) { shown = false; return; }
        path = p;
        shown = true;
    }
    function show(p: string): void { path = p; shown = true; }
    function close(): void { shown = false; full = false; }

    // desde el dock / menús (Shell.preview): siempre abre, no alterna
    Connections {
        target: Shell
        function onPreviewRequested(p: string): void { root.show(p); }
    }

    onShownChanged: {
        anim.to = shown ? 1 : 0;
        anim.duration = shown ? 240 : 180;
        anim.easing.type = shown ? Easing.OutCubic : Easing.InCubic;
        anim.restart();
    }
    NumberAnimation { id: anim; target: root; property: "progress" }

    IpcHandler {
        target: "preview"
        function open(file: string): void { root.open(file); }
        function close(): void { root.close(); }
        function status(): string { return root.shown ? root.path : ""; }
    }

    PanelWindow {
        id: win
        screen: Wm.screen
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quantum-preview"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.alpha(Theme.scrim, 0.55 * Math.min(1, root.progress))
        visible: root.shown || root.progress > 0.001

        // clic fuera de la ventana = cerrar
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        // teclado: Space y Esc cierran
        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Space || e.key === Qt.Key_Escape) {
                    root.close();
                    e.accepted = true;
                }
            }
            Connections {
                target: root
                function onShownChanged() { if (root.shown) keys.forceActiveFocus(); }
            }
        }

        // ------------------------------------------------------------ ventana
        Rectangle {
            id: frame
            anchors.centerIn: parent
            width: root.full ? parent.width : Math.round(parent.width * 0.86)
            height: root.full ? parent.height : Math.round(parent.height * 0.84)
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            radius: root.full ? 0 : Theme.radiusLarge
            color: Theme.dark ? "#1e1e1e" : "#ececec"
            border.width: 1
            border.color: Theme.popoverBorder
            clip: true
            opacity: Math.min(1, root.progress)
            scale: 0.95 + 0.05 * Math.min(1, root.progress)

            // absorbe los clics dentro de la ventana (no cierran)
            MouseArea { anchors.fill: parent }

            // ---- cabecera
            Rectangle {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 46
                radius: frame.radius          // bo góc trên theo khung
                color: Theme.dark ? "#2b2b2b" : "#dcdcdc"

                // tấm phủ để góc dưới của cabecera vuông (chỉ bo góc trên)
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: frame.radius
                    color: parent.color
                }

                // ---- semáforo: rojo cerrar, amarillo mostrar en carpeta, verde pantalla completa
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Repeater {
                        model: [
                            { color: "#ff5f57", glyph: "×", tip: "Cerrar",
                              act: () => root.close() },
                            { color: "#febc2e", glyph: "−", tip: "Mostrar en carpeta",
                              act: () => Quickshell.execDetached(["xdg-open", root.path.slice(0, root.path.lastIndexOf("/")) || "/"]) },
                            { color: "#28c840", glyph: "+", tip: "Pantalla completa",
                              act: () => root.full = !root.full },
                        ]

                        Rectangle {
                            id: light
                            required property var modelData
                            width: 12
                            height: 12
                            radius: 6
                            color: modelData.color
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.18)

                            Text {
                                anchors.centerIn: parent
                                text: light.modelData.glyph
                                color: Qt.rgba(0, 0, 0, 0.55)
                                font.pixelSize: 10
                                font.bold: true
                                opacity: lightArea.containsMouse ? 1 : 0
                            }

                            MouseArea {
                                id: lightArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: light.modelData.act()
                            }
                        }
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 84
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isVid ? "movie" : "image"
                        size: 20
                        color: Theme.primary
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(120, header.width - 260)
                        Txt {
                            width: parent.width
                            text: root.fileName
                            font.weight: Font.DemiBold
                            font.pixelSize: 13
                        }
                        Txt {
                            width: parent.width
                            text: root.isVid ? "Video" : "Imagen"
                            color: Theme.fgMuted
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // línea divisoria bajo la cabecera
            Rectangle {
                id: divider
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Theme.popoverBorder
            }

            // ---- contenido (imagen o video)
            Rectangle {
                anchors.top: divider.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                radius: frame.radius          // bo góc dưới theo khung
                color: "black"
                clip: true

                // tấm phủ để góc trên của vùng media vuông (chỉ bo góc dưới)
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: frame.radius
                    color: parent.color
                }

                Loader {
                    id: media
                    anchors.fill: parent
                    active: win.visible && root.path !== ""
                    sourceComponent: root.isVid ? videoView : imageView
                }
            }
        }

        Component {
            id: imageView
            Image {
                anchors.fill: parent
                anchors.margins: 12
                source: "file://" + root.path
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                autoTransform: true
                smooth: true
                // clic dentro de la imagen no cierra
                MouseArea { anchors.fill: parent }
            }
        }

        Component {
            id: videoView
            Video {
                anchors.fill: parent
                source: "file://" + root.path
                fillMode: VideoOutput.PreserveAspectFit
                loops: MediaPlayer.Infinite
                autoPlay: true
                // (sin sonido ni controles: es una vista rápida)
                MouseArea {
                    anchors.fill: parent
                    onClicked: parent.playbackState === MediaPlayer.PlayingState ? parent.pause() : parent.play()
                }
            }
        }

        // pista de teclas bajo la ventana
        Txt {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 10
            text: "Space / Esc: cerrar"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 12
            opacity: Math.min(1, root.progress)
        }
    }
}
