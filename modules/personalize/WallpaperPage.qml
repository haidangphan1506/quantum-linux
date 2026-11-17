import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Fondo de pantalla como en Ajustes del Sistema de macOS: el fondo actual arriba con su
// nombre, y debajo las colecciones (Quantum, tus fotos) en cuadrícula y «Agregar foto…».
ColumnLayout {
    id: page
    spacing: 16

    property var walls: []
    readonly property string current: Settings.appearance.wallpaper
    readonly property bool live: current === "quantum:live"
    readonly property var quantum: walls.filter(w => w.startsWith("/usr/share/backgrounds/"))
    readonly property var mine: walls.filter(w => !w.startsWith("/usr/share/backgrounds/"))

    Component.onCompleted: lister.running = true
    Process {
        id: lister
        command: ["sh", "-c", "for d in /usr/share/backgrounds/quantum \"$HOME/Imágenes/Fondos\" \"$HOME/Pictures/Wallpapers\" \"$HOME/Pictures\" \"$(dirname \"$1\")\"; do " +
                  "[ -d \"$d\" ] && find \"$d\" -maxdepth 1 -type f \\( " + Wallpaper.findExpr + " \\); done | sort -u",
                  "sh", Settings.appearance.wallpaper]
        stdout: StdioCollector { onStreamFinished: { page.walls = text.trim().split("\n").filter(s => s.length); Wallpaper.prepare(page.walls); } }
    }

    function thumb(path: string): string {
        const dir = path.substring(0, path.lastIndexOf("/"));
        const name = path.substring(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
        return "file://" + dir + "/thumbs/" + name + ".jpg";
    }
    function nameOf(path: string): string {
        if (path === "quantum:live") return I18n.t("Fondo vivo de Quantum");
        return path.substring(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ");
    }
    // cuadrícula fija (aunque haya pocas fotos, como en macOS)
    readonly property int cols: Math.max(3, Math.floor(page.width / 170))
    readonly property real tileW: (page.width - (cols - 1) * 10) / cols
    function setWallpaper(path: string): void { Settings.set("appearance", "wallpaper", path); }

    // --------------------------------------------------------- fondo actual
    Group {
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            spacing: 16
            Rectangle {
                implicitWidth: 200; implicitHeight: 125
                radius: 8
                clip: true
                color: "#0B0820"
                LiveWallpaper { anchors.fill: parent; visible: page.live; running: page.live }
                Image {
                    anchors.fill: parent
                    visible: !page.live
                    source: page.live ? "" : (Wallpaper.isVideo(page.current) ? page.thumb(page.current) : "file://" + page.current)
                    sourceSize: Qt.size(400, 250)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Txt { Layout.fillWidth: true; text: page.nameOf(page.current); font.weight: Font.Bold; font.pixelSize: Theme.textNormal + 2; elide: Text.ElideRight }
                Txt {
                    Layout.fillWidth: true
                    text: page.live ? I18n.t("Animado") : Wallpaper.isVideo(page.current) ? I18n.t("Video") : I18n.t("Imagen")
                    color: Theme.fgMuted; font.pixelSize: Theme.textSmall
                }
                Txt {
                    Layout.fillWidth: true
                    text: Settings.appearance.dynamicColors ? I18n.t("El color de acento sale de este fondo.") : ""
                    color: Theme.fgMuted; font.pixelSize: Theme.textSmall
                    visible: text !== ""
                }
                RowLayout {
                    Layout.topMargin: 6
                    spacing: 8
                    PillButton { text: I18n.t("Agregar foto…"); icon: "add_photo_alternate"; implicitHeight: 28; onClicked: wallDialog.open() }
                    PillButton { text: I18n.t("Usar sus colores"); implicitHeight: 28; enabled_: !Settings.appearance.dynamicColors; onClicked: Settings.set("appearance", "dynamicColors", true) }
                }
            }
        }
    }

    FileDialog {
        id: wallDialog
        title: I18n.t("Elegir fondo de pantalla")
        nameFilters: [I18n.t("Imágenes y videos (*.png *.jpg *.jpeg *.webp *.mp4 *.webm *.mkv *.mov)")]
        onAccepted: {
            page.setWallpaper(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")));
            lister.running = true;
        }
    }

    // Miniatura de un fondo
    component Tile: Rectangle {
        id: tile
        required property string modelData
        readonly property bool on: modelData === page.current
        Layout.preferredWidth: page.tileW
        Layout.preferredHeight: width * 10 / 16
        radius: 7
        color: Theme.alpha(Theme.fg, 0.06)
        border.width: on ? 3 : 0
        border.color: Theme.primary
        clip: true
        Image {
            id: thImg
            anchors.fill: parent
            anchors.margins: tile.on ? 3 : 0
            source: page.thumb(tile.modelData)
            sourceSize: Qt.size(320, 200)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            onStatusChanged: if (status === Image.Error && !Wallpaper.isVideo(tile.modelData)) source = "file://" + tile.modelData
            Connections {
                target: Wallpaper
                function onThumbsReady(): void { thImg.source = ""; thImg.source = page.thumb(tile.modelData); }
            }
        }
        Rectangle {
            visible: Wallpaper.isVideo(tile.modelData)
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 6
            width: 22; height: 22; radius: 11
            color: Qt.rgba(0, 0, 0, 0.55)
            Icon { anchors.centerIn: parent; text: "play_arrow"; size: 16; fill: 1; color: "white" }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.setWallpaper(tile.modelData)
        }
    }

    // --------------------------------------------------------- colecciones
    Group {
        title: "Quantum"
        boxed: false
        GridLayout {
            Layout.fillWidth: true
            columns: page.cols
            columnSpacing: 10
            rowSpacing: 10
            // Fondo vivo: el átomo de Quantum animado
            Rectangle {
                id: liveTile
                Layout.preferredWidth: page.tileW
                Layout.preferredHeight: width * 10 / 16
                radius: 7
                color: "#0B0820"
                border.width: page.live ? 3 : 0
                border.color: Theme.primary
                clip: true
                LiveWallpaper {
                    anchors.fill: parent
                    anchors.margins: page.live ? 3 : 0
                    running: liveArea.containsMouse
                }
                Rectangle {
                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 6
                    width: liveT.implicitWidth + 12; height: 20; radius: 10
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Txt { id: liveT; anchors.centerIn: parent; text: I18n.t("Animado"); font.pixelSize: Theme.textSmall - 1; color: "white" }
                }
                MouseArea { id: liveArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.setWallpaper("quantum:live") }
            }
            Repeater { model: page.quantum; delegate: Tile {} }
        }
    }

    Group {
        visible: page.mine.length > 0
        title: I18n.t("Tus fotos")
        help: I18n.t("De Imágenes y Imágenes/Wallpapers. También puedes usar Super + W.")
        boxed: false
        GridLayout {
            Layout.fillWidth: true
            columns: page.cols
            columnSpacing: 10
            rowSpacing: 10
            Repeater { model: page.mine; delegate: Tile {} }
        }
    }
}
