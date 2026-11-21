import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components
import "stack.js" as Stack

// Archivo o carpeta fijado junto a la papelera (como los "stacks" del Dock de macOS).
// Carpeta: clic = se abre en abanico con su contenido (StackPopup). Archivo: clic = abrirlo.
// Clic derecho: menú (abrir / quitar). Arrastrarlo hacia afuera del dock lo quita.
DockButton {
    id: btn

    required property var dock
    property string path: ""
    // nombre a mostrar (por defecto, el del archivo o carpeta)
    property string label: Stack.baseName(path)
    signal removeRequested

    // tipo del archivo (inode/directory para carpetas); "" mientras no se sabe; "missing" si ya no existe
    property string mime: ""
    readonly property bool isDir: mime === "inode/directory"
    readonly property bool missing: mime === "missing"
    // el comando se arma aquí (no por binding): en onPathChanged el binding todavía puede tener la ruta vieja
    function refresh(): void {
        if (!path) return;
        probe.command = ["sh", "-c", "[ -e \"$1\" ] || { echo missing; exit; }; file --mime-type -b -L -- \"$1\"", "sh", path];
        probe.running = true;
    }
    onPathChanged: refresh()
    Component.onCompleted: refresh()
    Process {
        id: probe
        stdout: StdioCollector { onStreamFinished: btn.mime = text.trim() || "application/octet-stream" }
    }

    flat: true
    tip: label

    function open(): void {
        if (missing) return;
        if (isDir) dock.openStack(btn, path, label);
        else Quickshell.execDetached(["xdg-open", path]);
    }
    onClicked: { dock.closeMenu(); dock.hoverGroup = null; refresh(); open(); }
    onRightClicked: { dock.hoverGroup = null; dock.openStackMenu(btn); }
    onHoveredChanged: {
        if (hovered && !dock.stackOpen) {
            dock.cancelHide();
            dock.hoverItem = btn;
            dock.hoverGroup = { name: btn.missing ? btn.label + " — " + I18n.t("No encontrado") : btn.label, wins: [], entry: null, pinned: false, icon: "" };
        } else if (dock.hoverItem === btn) {
            dock.scheduleHide();
        }
    }

    // ---- arrastrar hacia afuera del dock para quitarlo (como las apps fijadas)
    draggable: true
    readonly property real outSign: dock?.pos === "bottom" || dock?.pos === "left" ? -1 : 1
    readonly property real removeDist: Math.round(60 * Theme.dockScale)
    property real dragOut: 0
    property real dragAlong: 0
    // no depende de «dragging»: DockButton lo pone en false ANTES de emitir dropped(),
    // y al soltar hay que saber si estaba afuera (dragOut se pone en 0 después, en onDropped)
    readonly property bool removing: dragOut > removeDist
    z: dragging ? 10 : 0
    onDraggingChanged: dock.stackDrag = dragging
    onDragMoved: (dx, dy) => {
        dragOut = outSign * ((dock?.vertical ?? false) ? dx : dy);
        dragAlong = (dock?.vertical ?? false) ? dy : dx;
        dock.hoverGroup = null;
    }
    onDropped: {
        const rm = removing;
        dragOut = 0; dragAlong = 0;
        if (rm) removeRequested();
    }
    transform: Translate {
        readonly property real cross: btn.outSign * Math.max(0, Math.min(240, btn.dragOut))
        // a lo largo de la barra solo se despega un poco (los stacks no se reordenan)
        readonly property real along: Math.max(-12, Math.min(12, btn.dragAlong))
        x: (btn.dock?.vertical ?? false) ? cross : along
        y: (btn.dock?.vertical ?? false) ? along : cross
        Behavior on x { enabled: !btn.dragging; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !btn.dragging; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }

    // ---- icono: carpeta según su nombre, miniatura si es imagen, si no el del tipo de archivo
    Item {
        id: iconBox
        anchors.centerIn: parent
        width: Math.round(38 * Theme.dockScale)
        height: width
        opacity: (btn.missing ? 0.4 : 1) * (btn.removing ? 0.45 : 1)
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        AppIcon {
            anchors.fill: parent
            visible: !thumb.visible
            size: parent.width
            name: btn.isDir ? Stack.folderIcon(btn.path, Quickshell.env("HOME")) : Stack.mimeIcon(btn.mime)
            fallback: btn.isDir || btn.mime === "" ? "folder" : Stack.mimeFallback(btn.mime)
            glyph: btn.isDir ? "folder" : Stack.mimeGlyph(btn.mime)
        }
        Image {
            id: thumb
            anchors.fill: parent
            visible: Stack.isImage(btn.mime) && status === Image.Ready
            source: Stack.isImage(btn.mime) ? "file://" + btn.path : ""
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
    }

    // cartel "Quitar del Dock" al sacarlo de la barra
    Rectangle {
        z: 5
        opacity: btn.removing ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        width: removeText.implicitWidth + 16
        height: removeText.implicitHeight + 8
        radius: height / 2
        color: Theme.alpha(Theme.surface, 0.92)
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.15)
        x: (btn.dock?.vertical ?? false) ? (btn.outSign > 0 ? btn.width + 6 : -width - 6) : (btn.width - width) / 2
        y: (btn.dock?.vertical ?? false) ? (btn.height - height) / 2 : (btn.outSign > 0 ? btn.height + 6 : -height - 6)
        Txt {
            id: removeText
            anchors.centerIn: parent
            text: I18n.t("Quitar del Dock")
            font.weight: Font.DemiBold
        }
    }
}
