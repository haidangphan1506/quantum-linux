import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Editor de capturas (como «Marcación» de macOS): círculo / rectángulo rojo, flecha, lápiz,
// resaltador, nota de texto, deshacer y guardar / copiar. Las formas se guardan en coordenadas
// de la imagen original, así que el resultado sale a tamaño completo.
FloatingWindow {
    id: win

    required property string path           // ruta de la captura
    signal finished

    title: I18n.t("Captura de pantalla")
    color: Theme.surface
    implicitWidth: Math.min(1280, Math.round((Quickshell.screens[0]?.width ?? 1920) * 0.7))
    implicitHeight: Math.min(860, Math.round((Quickshell.screens[0]?.height ?? 1080) * 0.75))
    minimumSize: Qt.size(640, 420)
    visible: true
    onVisibleChanged: if (!visible) win.finished()

    // ------------------------------------------------------------ estado
    property string tool: "ellipse"          // pen | arrow | rect | ellipse | highlight | text
    property color ink: "#ff3b30"
    property int strokeW: 4
    property var shapes: []                  // [{ t, c, w, pts:[[x,y]…] o x0,y0,x1,y1, text }]
    property var live: null                  // forma que se está dibujando
    property string status: ""
    property bool busy: false

    readonly property var tools: [
        { id: "ellipse", icon: "circle", tip: I18n.t("Círculo") },
        { id: "rect", icon: "crop_square", tip: I18n.t("Rectángulo") },
        { id: "arrow", icon: "north_east", tip: I18n.t("Flecha") },
        { id: "pen", icon: "edit", tip: I18n.t("Lápiz") },
        { id: "highlight", icon: "ink_highlighter", tip: I18n.t("Resaltador") },
        { id: "text", icon: "text_fields", tip: I18n.t("Nota de texto") },
    ]
    readonly property var colors: ["#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#007aff", "#ffffff", "#1c1c1e"]

    function undo(): void { if (shapes.length) { const a = shapes.slice(0, -1); shapes = a; canvas.requestPaint(); } }
    function clearAll(): void { shapes = []; canvas.requestPaint(); }

    // ------------------------------------------------------- guardar / copiar
    readonly property string outDir: Quickshell.env("HOME") + "/Pictures/Screenshots"
    function outPath(): string {
        const base = win.path.replace(/\.png$/i, "").replace(/-edit(ado)?$/, "");
        return base + "-editado.png";
    }
    function render(then: var): void {
        if (busy) return;
        busy = true;
        textEdit.commit();
        const out = outPath();
        stage.grabToImage(r => {
            const ok = r.saveToFile(out);
            busy = false;
            if (ok) then(out); else status = I18n.t("No se pudo guardar la imagen.");
        }, Qt.size(img.implicitWidth, img.implicitHeight));
    }
    function save(): void {
        render(out => { status = I18n.t("Guardada en ") + out; });
    }
    function copy(): void {
        render(out => {
            Quickshell.execDetached(["sh", "-c", "wl-copy < '" + out.replace(/'/g, "'\\''") + "'"]);
            status = I18n.t("Copiada al portapapeles");
        });
    }
    function saveAndClose(): void { render(out => { Quickshell.execDetached(["sh", "-c", "wl-copy < '" + out.replace(/'/g, "'\\''") + "'"]); win.visible = false; }); }

    Shortcut { sequence: "Escape"; onActivated: { if (textEdit.active) textEdit.cancel(); else win.visible = false; } }
    Shortcut { sequence: "Ctrl+Z"; onActivated: win.undo() }
    Shortcut { sequence: "Ctrl+S"; onActivated: win.save() }
    Shortcut { sequence: "Ctrl+C"; enabled: !textEdit.active; onActivated: win.copy() }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ------------------------------------------------------ barra de herramientas
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 4

                Repeater {
                    model: win.tools
                    Rectangle {
                        id: tb
                        required property var modelData
                        readonly property bool on: win.tool === modelData.id
                        implicitWidth: 34; implicitHeight: 32; radius: 8
                        color: on ? Theme.alpha(Theme.macBlue, 0.2) : tbArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                        Icon { anchors.centerIn: parent; text: tb.modelData.icon; size: 20; color: tb.on ? Theme.macBlue : Theme.fg }
                        MouseArea { id: tbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.tool = tb.modelData.id }
                        Txt {
                            visible: tbArea.containsMouse
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 4
                            text: tb.modelData.tip
                            font.pixelSize: Theme.textSmall - 1
                            color: Theme.fgMuted
                            z: 5
                        }
                    }
                }

                Rectangle { implicitWidth: 1; implicitHeight: 20; color: Theme.alpha(Theme.fg, 0.15); Layout.leftMargin: 6; Layout.rightMargin: 6 }

                Repeater {
                    model: win.colors
                    Rectangle {
                        id: cd
                        required property string modelData
                        readonly property bool on: win.ink.toString().toLowerCase() === modelData
                        implicitWidth: 22; implicitHeight: 22; radius: 11
                        color: modelData
                        border.width: on ? 3 : 1
                        border.color: on ? Theme.macBlue : Qt.rgba(0, 0, 0, 0.25)
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.ink = cd.modelData }
                    }
                }

                Rectangle { implicitWidth: 1; implicitHeight: 20; color: Theme.alpha(Theme.fg, 0.15); Layout.leftMargin: 6; Layout.rightMargin: 6 }

                Repeater {
                    model: [2, 4, 8]
                    Rectangle {
                        id: sw
                        required property int modelData
                        readonly property bool on: win.strokeW === modelData
                        implicitWidth: 30; implicitHeight: 30; radius: 8
                        color: on ? Theme.alpha(Theme.macBlue, 0.2) : swArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                        Rectangle { anchors.centerIn: parent; width: 16; height: sw.modelData; radius: sw.modelData / 2; color: sw.on ? Theme.macBlue : Theme.fg }
                        MouseArea { id: swArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.strokeW = sw.modelData }
                    }
                }

                Item { Layout.fillWidth: true }

                Txt { visible: win.status !== ""; text: win.status; color: Theme.fgMuted; font.pixelSize: Theme.textSmall; elide: Text.ElideMiddle; Layout.maximumWidth: 260 }
                IconButton { icon: "undo"; iconSize: 20; implicitWidth: 34; implicitHeight: 32; opacity: win.shapes.length ? 1 : 0.4; onClicked: win.undo() }
                IconButton { icon: "delete"; iconSize: 20; implicitWidth: 34; implicitHeight: 32; opacity: win.shapes.length ? 1 : 0.4; onClicked: win.clearAll() }
                PillButton { text: I18n.t("Guardar"); icon: "save"; implicitHeight: 30; onClicked: win.save() }
                PillButton { text: I18n.t("Copiar"); icon: "content_copy"; implicitHeight: 30; onClicked: win.copy() }
                PillButton { text: I18n.t("Listo"); primary: true; implicitHeight: 30; onClicked: win.saveAndClose() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.alpha(Theme.fg, 0.1) }
        }

        // ------------------------------------------------------------ lienzo
        Rectangle {
            id: area
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.dark ? "#161618" : "#e4e4e8"
            clip: true

            readonly property real fit: img.implicitWidth > 0
                ? Math.min(1, (width - 40) / img.implicitWidth, (height - 40) / img.implicitHeight) : 1

            Item {
                id: holder
                width: img.implicitWidth * area.fit
                height: img.implicitHeight * area.fit
                anchors.centerIn: parent

                Item {
                    id: scaler
                    width: img.implicitWidth; height: img.implicitHeight
                    scale: area.fit
                    transformOrigin: Item.TopLeft

                    // lo que se exporta: imagen + anotaciones, a tamaño original
                    Item {
                        id: stage
                        anchors.fill: parent

                        Image {
                            id: img
                            source: "file://" + win.path
                            cache: false
                            smooth: true
                        }

                        Canvas {
                            id: canvas
                            anchors.fill: parent
                            renderTarget: Canvas.Image
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const all = win.live ? win.shapes.concat([win.live]) : win.shapes;
                                for (const sh of all) win.draw(ctx, sh);
                            }
                        }

                        // nota de texto en edición
                        Item {
                            id: textEdit
                            property real tx: 0
                            property real ty: 0
                            readonly property bool active: visible
                            visible: false
                            x: tx; y: ty
                            width: Math.max(80, input.implicitWidth + 16)
                            height: input.implicitHeight + 8
                            function begin(px: real, py: real): void { tx = px; ty = py - 14; input.text = ""; visible = true; input.forceActiveFocus(); }
                            function commit(): void {
                                if (!visible) return;
                                visible = false;
                                const t = input.text.trim();
                                if (t !== "") {
                                    win.shapes = win.shapes.concat([{ t: "text", c: win.ink.toString(), w: win.strokeW, x0: tx, y0: ty, text: t }]);
                                    canvas.requestPaint();
                                }
                            }
                            function cancel(): void { visible = false; }
                            Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.12); border.width: 1; border.color: win.ink; radius: 4 }
                            TextInput {
                                id: input
                                anchors.centerIn: parent
                                color: win.ink
                                font.pixelSize: win.fontPx()
                                font.weight: Font.Bold
                                font.family: Theme.font
                                selectByMouse: true
                                onAccepted: textEdit.commit()
                                onActiveFocusChanged: if (!activeFocus) textEdit.commit()
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !win.busy
                    cursorShape: Qt.CrossCursor
                    acceptedButtons: Qt.LeftButton
                    // coordenadas de la imagen original
                    function p(e): var { return [e.x / area.fit, e.y / area.fit]; }
                    onPressed: e => {
                        const [x, y] = p(e);
                        win.status = "";
                        if (win.tool === "text") { textEdit.commit(); textEdit.begin(x, y); return; }
                        textEdit.commit();
                        if (win.tool === "pen") win.live = { t: "pen", c: win.ink.toString(), w: win.strokeW, pts: [[x, y]] };
                        else win.live = { t: win.tool, c: win.ink.toString(), w: win.strokeW, x0: x, y0: y, x1: x, y1: y };
                    }
                    onPositionChanged: e => {
                        if (!win.live) return;
                        const [x, y] = p(e);
                        const l = Object.assign({}, win.live);
                        if (l.t === "pen") l.pts = l.pts.concat([[x, y]]); else { l.x1 = x; l.y1 = y; }
                        win.live = l;
                        canvas.requestPaint();
                    }
                    onReleased: {
                        if (!win.live) return;
                        const l = win.live;
                        win.live = null;
                        const tiny = l.t === "pen" ? l.pts.length < 2 : Math.abs(l.x1 - l.x0) + Math.abs(l.y1 - l.y0) < 6;
                        if (!tiny) win.shapes = win.shapes.concat([l]);
                        canvas.requestPaint();
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ dibujo
    function fontPx(): int { return 14 + strokeW * 4; }
    function rgba(c: string, a: real): string {
        const h = parseInt(c.slice(1, 7), 16);
        return "rgba(" + ((h >> 16) & 255) + "," + ((h >> 8) & 255) + "," + (h & 255) + "," + a + ")";
    }
    function draw(ctx: var, sh: var): void {
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.strokeStyle = sh.c;
        ctx.fillStyle = sh.c;
        ctx.lineWidth = sh.w * 1.5;
        if (sh.t === "pen") {
            ctx.beginPath();
            ctx.moveTo(sh.pts[0][0], sh.pts[0][1]);
            for (let i = 1; i < sh.pts.length; i++) ctx.lineTo(sh.pts[i][0], sh.pts[i][1]);
            ctx.stroke();
        } else if (sh.t === "rect") {
            ctx.strokeRect(Math.min(sh.x0, sh.x1), Math.min(sh.y0, sh.y1), Math.abs(sh.x1 - sh.x0), Math.abs(sh.y1 - sh.y0));
        } else if (sh.t === "highlight") {
            ctx.fillStyle = rgba(sh.c.length === 7 ? sh.c : "#ffcc00", 0.4);
            ctx.fillRect(Math.min(sh.x0, sh.x1), Math.min(sh.y0, sh.y1), Math.abs(sh.x1 - sh.x0), Math.abs(sh.y1 - sh.y0));
        } else if (sh.t === "ellipse") {
            const cx = (sh.x0 + sh.x1) / 2, cy = (sh.y0 + sh.y1) / 2, rx = Math.abs(sh.x1 - sh.x0) / 2, ry = Math.abs(sh.y1 - sh.y0) / 2;
            ctx.beginPath();
            ctx.ellipse(cx - rx, cy - ry, rx * 2, ry * 2);
            ctx.stroke();
        } else if (sh.t === "arrow") {
            const a = Math.atan2(sh.y1 - sh.y0, sh.x1 - sh.x0), len = 12 + sh.w * 4;
            ctx.beginPath();
            ctx.moveTo(sh.x0, sh.y0);
            ctx.lineTo(sh.x1, sh.y1);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(sh.x1, sh.y1);
            ctx.lineTo(sh.x1 - len * Math.cos(a - 0.45), sh.y1 - len * Math.sin(a - 0.45));
            ctx.lineTo(sh.x1 - len * Math.cos(a + 0.45), sh.y1 - len * Math.sin(a + 0.45));
            ctx.closePath();
            ctx.fill();
        } else if (sh.t === "text") {
            ctx.font = "bold " + (14 + sh.w * 4) + "px sans-serif";
            ctx.textBaseline = "top";
            ctx.fillText(sh.text, sh.x0 + 8, sh.y0 + 4);
        }
    }
}
