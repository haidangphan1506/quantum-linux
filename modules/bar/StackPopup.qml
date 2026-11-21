import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components
import "stack.js" as Stack

// Contenido de una carpeta fijada en el dock, en abanico como los "stacks" de macOS:
// lo más reciente junto al dock y arriba "Abrir en Archivos". En el dock vertical, una lista al lado.
// También hace de menú del clic derecho de un stack (mode: "menu").
// Capa propia (PanelWindow) como MacMenu: el dock mide solo 360 px y el abanico es más alto.
PanelWindow {
    id: pop

    required property var dock
    property Item anchorItem: null
    property string path: ""
    property string title: ""
    property string mode: "stack"   // stack | menu
    property var items: []          // { path, name, mime, isDir }
    property int total: 0
    property bool loaded: false
    property int maxItems: 10
    property real closedAt: 0
    property string closedKey: ""

    readonly property string pos: dock.pos
    readonly property bool fan: pos === "bottom" || pos === "top"
    readonly property int rowH: 54
    readonly property int thumb: 46
    readonly property int curve: fan ? 34 : 0        // cuánto se curva el abanico hacia la derecha arriba
    readonly property int pad: 10

    function key(): string { return mode + ":" + path; }

    function openStack(item: Item, p: string, t: string): void {
        // el clic que cerró el abanico (al soltar el grab) no lo vuelve a abrir
        if (!visible && closedKey === "stack:" + p && Date.now() - closedAt < 350) return;
        if (visible && mode === "stack" && path === p) { close(); return; }
        anchorItem = item; path = p; title = t; mode = "stack";
        place();
        const avail = fan ? (pos === "bottom" ? aTop - dock.topInset - 16 : dock.screen.height - aBottom - 16)
                          : dock.screen.height - dock.topInset - 32;
        maxItems = Math.max(3, Math.min(14, Math.floor(avail / rowH) - 1));
        items = []; total = 0; loaded = false;
        lister.running = false;
        lister.command = ["sh", Quickshell.shellDir + "/scripts/dock-stack.sh", p, String(maxItems)];
        lister.running = true;
        show();
    }
    function openMenu(item: Item): void {
        anchorItem = item; path = item.path; title = item.label; mode = "menu";
        place();
        show();
    }
    function show(): void {
        intro.stop();
        progress = 0;
        visible = true;
        intro.start();
    }
    function close(): void {
        if (!visible) return;
        closedKey = key();
        closedAt = Date.now();
        visible = false;
    }
    function openPath(p: string, isDir: bool): void {
        if (isDir) Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/open-folder.sh", p]);
        else Quickshell.execDetached(["xdg-open", p]);
        close();
    }

    // posición del icono en la pantalla (se calcula al abrir)
    property real aCx: 0
    property real aCy: 0
    property real aTop: 0
    property real aBottom: 0
    property real cardNear: 0      // borde de la barra del lado de la pantalla (dock vertical)
    function place(): void {
        const it = anchorItem;
        if (!it) return;
        const c = dock.screenPoint(it, it.width / 2, it.height / 2);
        aCx = c.x; aCy = c.y;
        aTop = dock.screenPoint(it, 0, 0).y;
        aBottom = dock.screenPoint(it, 0, it.height).y;
        const card = dock.cardItem;
        cardNear = pos === "left" ? dock.screenPoint(card, card.width, 0).x : dock.screenPoint(card, 0, 0).x;
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let total = 0;
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i < 0) continue;
                    const a = line.slice(0, i), b = line.slice(i + 1);
                    if (a === "total") { total = parseInt(b) || 0; continue; }
                    out.push({ path: b, name: Stack.baseName(b), mime: a, isDir: a === "inode/directory" });
                }
                pop.items = out;
                pop.total = total;
                pop.loaded = true;
            }
        }
    }

    // filas del abanico, de arriba hacia abajo. «k» = distancia al dock (0 = junto al icono)
    readonly property var rows: {
        if (mode !== "stack") return [];
        const more = Math.max(0, total - items.length);
        const head = { kind: "open", name: I18n.t("Abrir en Archivos") + (more > 0 ? "  (+" + more + ")" : "") };
        let body = items.map(x => Object.assign({ kind: "item" }, x));
        if (loaded && total === 0) body = [{ kind: "empty", name: I18n.t("Carpeta vacía") }];
        if (loaded && total < 0) body = [{ kind: "empty", name: I18n.t("No encontrado") }];
        // abajo: lo más nuevo abajo (junto al dock); arriba: lo más nuevo arriba
        if (pos === "bottom") return [head].concat(body.slice().reverse());
        if (pos === "top") return body.concat([head]);
        return [head].concat(body);
    }

    // animación de apertura: las filas salen del icono hacia afuera
    property real progress: 0
    NumberAnimation {
        id: intro
        target: pop
        property: "progress"
        from: 0; to: 1
        duration: 300
        easing.type: Easing.OutCubic
    }

    visible: false
    screen: dock.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-stack"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors { top: true; left: true }

    readonly property real contentW: mode === "menu" ? menuCard.implicitWidth : (fan ? 380 : 360)
    readonly property real contentH: mode === "menu" ? menuCard.implicitHeight : stackCol.implicitHeight + 2 * pad
    implicitWidth: contentW
    implicitHeight: contentH
    // centro de la columna de miniaturas: queda justo sobre el icono del dock
    readonly property real thumbCx: pos === "left" ? pad + thumb / 2 : contentW - curve - pad - thumb / 2
    readonly property real wantX: {
        if (mode === "menu") {
            if (pos === "left") return cardNear + 8;
            if (pos === "right") return cardNear - contentW - 8;
            return aCx - contentW / 2;
        }
        if (pos === "left") return cardNear + 8;
        if (pos === "right") return cardNear - contentW - 8;
        return aCx - thumbCx;
    }
    readonly property real wantY: {
        if (pos === "bottom") return aTop - contentH - 4;
        if (pos === "top") return aBottom + 4;
        return aCy - contentH / 2;
    }
    margins {
        left: Math.round(Math.max(4, Math.min(wantX, (screen?.width ?? 1920) - contentW - 4)))
        top: Math.round(Math.max(4, Math.min(wantY, (screen?.height ?? 1080) - contentH - 4)))
    }

    HyprlandFocusGrab {
        windows: [pop]
        active: pop.visible
        onCleared: pop.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: pop.close()

        // ------------------------------------------------------------ abanico
        Column {
            id: stackCol
            visible: pop.mode === "stack"
            x: 0
            y: pop.pad
            width: pop.contentW
            spacing: 0

            Repeater {
                model: pop.rows

                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property int k: pop.pos === "bottom" ? pop.rows.length - 1 - index : pop.pos === "top" ? index : index
                    readonly property real t: pop.rows.length > 1 ? k / (pop.rows.length - 1) : 0
                    readonly property bool isOpen: modelData.kind === "open"
                    readonly property bool clickable: modelData.kind !== "empty"
                    readonly property bool hot: rowArea.containsMouse && clickable
                    width: pop.contentW
                    height: pop.rowH

                    // abanico: cuanto más lejos del dock, más se corre a la derecha y más gira
                    // entrada: cada fila sale desde el icono (escalonado según la distancia)
                    readonly property real p: Math.max(0, Math.min(1, pop.progress * 1.6 - row.t * 0.6))
                    opacity: p
                    transform: [
                        Rotation {
                            origin.x: pop.thumbCx
                            origin.y: pop.rowH / 2
                            angle: pop.fan ? (pop.pos === "bottom" ? 1 : -1) * 5 * row.t * row.t : 0
                        },
                        Translate {
                            x: pop.curve * row.t * row.t
                               + (pop.fan ? 0 : (1 - row.p) * (pop.pos === "left" ? -30 : 30))
                            y: pop.fan ? (1 - row.p) * (row.k + 1) * pop.rowH * (pop.pos === "bottom" ? 0.7 : -0.7) : 0
                        }
                    ]

                    Row {
                        id: rowContent
                        anchors.verticalCenter: parent.verticalCenter
                        x: pop.pos === "left" ? pop.pad : pop.contentW - pop.curve - pop.pad - width
                        spacing: 10
                        layoutDirection: pop.pos === "left" ? Qt.RightToLeft : Qt.LeftToRight

                        // nombre en una pastilla (azul al pasar el mouse, como macOS)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(260, nameText.implicitWidth + 20)
                            height: nameText.implicitHeight + 8
                            radius: height / 2
                            color: row.hot ? Theme.primary : Theme.popover
                            border.width: row.hot ? 0 : 1
                            border.color: Theme.popoverBorder
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Txt {
                                id: nameText
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, 240)
                                text: row.modelData.name
                                font.pixelSize: Theme.textSmall
                                font.weight: Font.Medium
                                color: row.hot ? "white" : row.modelData.kind === "empty" ? Theme.fgMuted : Theme.fg
                                elide: Text.ElideMiddle
                            }
                        }

                        // miniatura / icono
                        Item {
                            width: pop.thumb
                            height: pop.thumb
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.kind !== "empty"
                            scale: row.hot ? 1.08 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                            // «Abrir en Archivos»: círculo con flecha
                            Rectangle {
                                visible: row.isOpen
                                anchors.centerIn: parent
                                width: 38; height: 38
                                radius: 19
                                color: row.hot ? Theme.primary : Theme.alpha(Theme.surfaceHighest, 0.92)
                                border.width: 1
                                border.color: Theme.popoverBorder
                                Icon { anchors.centerIn: parent; text: "arrow_forward"; size: 22; color: row.hot ? "white" : Theme.fg }
                            }
                            AppIcon {
                                visible: !row.isOpen && !img.visible
                                anchors.fill: parent
                                size: pop.thumb
                                name: row.modelData.isDir ? Stack.folderIcon(row.modelData.path, Quickshell.env("HOME")) : Stack.mimeIcon(row.modelData.mime)
                                fallback: row.modelData.isDir ? "folder" : Stack.mimeFallback(row.modelData.mime)
                                glyph: Stack.mimeGlyph(row.modelData.mime)
                            }
                            // imágenes: miniatura real con marco blanco (como las vistas previas de macOS)
                            Rectangle {
                                visible: img.visible
                                anchors.centerIn: parent
                                width: img.paintedWidth + 4
                                height: img.paintedHeight + 4
                                color: "white"
                                radius: 3
                                border.width: 1
                                border.color: Qt.rgba(0, 0, 0, 0.15)
                            }
                            Image {
                                id: img
                                anchors.fill: parent
                                anchors.margins: 3
                                visible: !row.isOpen && Stack.isImage(row.modelData.mime) && status === Image.Ready
                                source: !row.isOpen && Stack.isImage(row.modelData.mime) ? "file://" + row.modelData.path : ""
                                sourceSize: Qt.size(128, 128)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                            }
                        }
                    }

                    MouseArea {
                        id: rowArea
                        // solo la pastilla y el icono (no el hueco transparente de la fila)
                        x: rowContent.x
                        width: rowContent.width
                        height: parent.height
                        hoverEnabled: true
                        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (row.isOpen) pop.openPath(pop.path, true);
                            else if (row.modelData.kind === "item") pop.openPath(row.modelData.path, row.modelData.isDir);
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------- menú (clic derecho)
        Card {
            id: menuCard
            visible: pop.mode === "menu"
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.popover
            border.width: 1
            border.color: Theme.popoverBorder
            implicitWidth: 240
            implicitHeight: menuCol.implicitHeight + 12
            opacity: pop.progress
            scale: 0.96 + 0.04 * pop.progress

            ColumnLayout {
                id: menuCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    spacing: 10
                    Icon { text: pop.anchorItem?.isDir ? "folder" : "description"; size: 20; color: Theme.fg }
                    Txt { Layout.fillWidth: true; text: pop.title; font.weight: Font.Bold; elide: Text.ElideMiddle }
                }
                Rectangle { Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; implicitHeight: 1; color: Theme.alpha(Theme.fg, 0.12) }

                Repeater {
                    model: pop.mode !== "menu" || !pop.anchorItem ? [] : [
                        { icon: "open_in_new", text: I18n.t("Abrir"), show: !pop.anchorItem.missing && !pop.anchorItem.isDir,
                          run: () => pop.openPath(pop.path, false) },
                        { icon: "folder_open", text: I18n.t("Abrir en Archivos"), show: !pop.anchorItem.missing,
                          run: () => pop.openPath(pop.anchorItem.isDir ? pop.path : pop.path.slice(0, pop.path.lastIndexOf("/")) || "/", true) },
                        { icon: "keep_off", text: I18n.t("Quitar del Dock"), show: true,
                          run: () => { const it = pop.anchorItem; pop.close(); it.removeRequested(); } },
                    ].filter(o => o.show)

                    Rectangle {
                        id: opt
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Theme.radiusSmall
                        color: optArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            spacing: 12
                            Icon { text: opt.modelData.icon; size: 20; color: Theme.fg }
                            Txt { Layout.fillWidth: true; text: opt.modelData.text }
                        }
                        MouseArea {
                            id: optArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: opt.modelData.run()
                        }
                    }
                }
            }
        }
    }
}
