import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components

// Selector de fondos (Super + W): una tira flotante sobre la barra de tareas con
// los fondos de Quantum y de tu carpeta Imágenes/Fondos, más claro/oscuro y
// colores del fondo. Elegir uno cambia todo el sistema al instante.
PanelWindow {
    id: win

    readonly property bool open: Shell.wallpapersOpen
    property real progress: 0
    property var walls: []

    visible: open || progress > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-wallpapers"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    onOpenChanged: {
        anim.to = open ? 1 : 0;
        anim.duration = open ? 420 : 190;
        anim.easing.type = open ? Easing.OutBack : Easing.InCubic;
        anim.restart();
        if (open) lister.running = true;
    }
    NumberAnimation { id: anim; target: win; property: "progress"; easing.overshoot: 1.15 }

    readonly property string current: Settings.appearance.wallpaper
    readonly property string sysDir: current.indexOf("/usr/share/backgrounds/quantum/") === 0 || !current.startsWith("/")
        ? "/usr/share/backgrounds/quantum" : current.substring(0, current.lastIndexOf("/"))

    // fondos del sistema + ~/Imágenes/Fondos (si existe)
    Process {
        id: lister
        command: ["sh", "-c", "for d in \"$1\" /usr/share/backgrounds/quantum \"$HOME/Imágenes/Fondos\" \"$HOME/Pictures/Wallpapers\"; do " +
                  "[ -d \"$d\" ] && find \"$d\" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\); done | sort -u", "sh", win.sysDir]
        stdout: StdioCollector {
            onStreamFinished: win.walls = text.trim().split("\n").filter(s => s.length)
        }
    }

    function thumb(path: string): string {
        // miniatura pre-generada si existe (thumbs/<nombre>.jpg), si no la imagen misma
        const dir = path.substring(0, path.lastIndexOf("/"));
        const name = path.substring(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
        return "file://" + dir + "/thumbs/" + name + ".jpg";
    }

    MouseArea {
        anchors.fill: parent
        enabled: win.open
        onClicked: Shell.wallpapersOpen = false
    }

    Card {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80
        width: Math.min(parent.width - 40, Math.max(640, row.implicitWidth + 48))
        height: 228
        color: Theme.alpha(Theme.surface, 0.94)
        opacity: Math.min(1, win.progress * 1.4)
        scale: 0.94 + 0.06 * win.progress
        transformOrigin: Item.Bottom
        transform: Translate { y: (1 - win.progress) * 40 }
        focus: win.open
        Keys.onEscapePressed: Shell.wallpapersOpen = false

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Icon { text: "wallpaper"; size: 22; fill: 1; color: Theme.primary }
                Txt { text: "Fondo de pantalla"; font.weight: Font.Bold; font.pixelSize: Theme.textLarge }
                Item { Layout.fillWidth: true }
                // claro / oscuro
                Rectangle {
                    implicitWidth: modeRow.implicitWidth + 24; implicitHeight: 36; radius: 18
                    color: Theme.surfaceHigh
                    RowLayout {
                        id: modeRow
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: [{ m: "dark", i: "dark_mode", t: "Oscuro" }, { m: "light", i: "light_mode", t: "Claro" }]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: Settings.appearance.mode === modelData.m
                                implicitWidth: mr.implicitWidth + 20; implicitHeight: 28; radius: 14
                                color: on ? Theme.primaryContainer : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                RowLayout {
                                    id: mr
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Icon { text: modelData.i; size: 16; fill: parent.parent.on ? 1 : 0; color: parent.parent.on ? Theme.primaryContainerFg : Theme.fg }
                                    Txt { text: modelData.t; font.pixelSize: Theme.textSmall; font.weight: Font.DemiBold; color: parent.parent.on ? Theme.primaryContainerFg : Theme.fg }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Settings.set("appearance", "mode", modelData.m) }
                            }
                        }
                    }
                }
                // colores del fondo
                Rectangle {
                    readonly property bool on: Settings.appearance.dynamicColors
                    implicitWidth: dynRow.implicitWidth + 24; implicitHeight: 36; radius: 18
                    color: on ? Theme.alpha(Theme.primary, 0.18) : Theme.surfaceHigh
                    border.width: on ? 1 : 0
                    border.color: Theme.alpha(Theme.primary, 0.5)
                    RowLayout {
                        id: dynRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { text: "palette"; size: 16; fill: parent.parent.on ? 1 : 0; color: parent.parent.on ? Theme.primary : Theme.fg }
                        Txt { text: "Colores del fondo"; font.pixelSize: Theme.textSmall; font.weight: Font.DemiBold }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Settings.set("appearance", "dynamicColors", !parent.on) }
                }
            }

            // miniaturas
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: row.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: row
                    spacing: 14
                    // Fondo vivo: el átomo de Quantum animado
                    Rectangle {
                        id: liveTile
                        readonly property bool on: Settings.appearance.wallpaper === "quantum:live"
                        width: 240; height: 140; radius: 18
                        color: "#0B0820"
                        border.width: on ? 3 : 0
                        border.color: Theme.primary
                        clip: true
                        opacity: Math.min(1, Math.max(0, win.progress * 3))
                        scale: (liveArea.containsMouse ? 1.05 : 1) * (0.9 + 0.1 * Math.min(1, win.progress))
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        LiveWallpaper { anchors.fill: parent; anchors.margins: liveTile.on ? 3 : 0; running: win.open }
                        Rectangle {
                            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
                            width: liveT.implicitWidth + 16; height: 24; radius: 12
                            color: Qt.rgba(0, 0, 0, 0.55)
                            Txt { id: liveT; anchors.centerIn: parent; text: "Fondo vivo"; font.pixelSize: Theme.textSmall; font.weight: Font.Bold; color: "white" }
                        }
                        MouseArea {
                            id: liveArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.set("appearance", "wallpaper", "quantum:live")
                        }
                    }
                    Repeater {
                        model: win.walls
                        Rectangle {
                            id: tile
                            required property string modelData
                            required property int index
                            readonly property bool on: modelData === win.current
                            width: 240; height: 140; radius: 18
                            color: Theme.surfaceHigh
                            border.width: on ? 3 : 0
                            border.color: Theme.primary
                            clip: true
                            // entrada escalonada
                            opacity: Math.min(1, Math.max(0, win.progress * 3 - index * 0.25))
                            scale: (tileArea.containsMouse ? 1.05 : 1) * (0.9 + 0.1 * Math.min(1, win.progress))
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Image {
                                id: th
                                anchors.fill: parent
                                anchors.margins: tile.on ? 3 : 0
                                source: win.thumb(tile.modelData)
                                sourceSize: Qt.size(480, 280)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                onStatusChanged: if (status === Image.Error) source = "file://" + tile.modelData
                            }
                            Rectangle {
                                visible: tile.on
                                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                                width: 30; height: 30; radius: 15; color: Theme.primary
                                Icon { anchors.centerIn: parent; text: "check"; size: 20; color: Theme.primaryFg }
                            }
                            MouseArea {
                                id: tileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Settings.set("appearance", "wallpaper", tile.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
