import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

// Launchpad (como macOS): vuốt 4 ngón lên (o IPC `launchpad toggle`).
//  - Pantalla completa, fondo difuminado (capa quantum-launchpad, blur en decorators.lua).
//  - Buscador pequeño arriba, cuadrícula de apps por páginas y puntos de página abajo.
//  - Cambiar de página: arrastrar, rueda / 2 ngón ngang, ← →, clic en los puntos.
//  - Clic = abrir app, clic derecho = menú (fijar / ocultar). Esc, clic en vacío o
//    vuốt 4 ngón xuống: cerrar.
Scope {
    id: root

    property bool open: false
    property real p: open ? 1 : 0
    Behavior on p { NumberAnimation { duration: Math.max(1, root.open ? Theme.animSlow : Theme.anim); easing.type: Easing.OutCubic } }
    readonly property bool shown: open || p > 0.001

    function show(): void {
        if (open) return;
        Shell.closeAll();
        open = true;
    }
    function hide(): void { open = false; }
    function toggle(): void { open ? hide() : show(); }

    // estado para Shell.swipe() y órdenes que llegan desde ahí
    Binding { target: Shell; property: "launchpadOpen"; value: root.open }
    Connections {
        target: Shell
        function onLaunchpadRequest(fn: string): void { fn === "open" ? root.show() : root.hide(); }
    }

    IpcHandler {
        target: "launchpad"
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win

            readonly property var mon: Hyprland.focusedMonitor
            screen: Quickshell.screens.find(s => s.name === mon?.name) ?? Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-launchpad"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore

            readonly property string query: search.text.trim()
            readonly property var results: Apps.search(search.text)

            // cuadrícula: ~7 x 5 como macOS, según el tamaño de la pantalla
            readonly property real gridW: Math.min(width - 160, 1500)
            readonly property real gridH: height - 120 - 110
            readonly property int cols: Math.max(4, Math.min(8, Math.floor(gridW / 170)))
            readonly property int rows: Math.max(3, Math.min(6, Math.floor(gridH / 150)))
            readonly property int perPage: cols * rows
            readonly property int pageCount: Math.max(1, Math.ceil(results.length / perPage))
            readonly property real cellW: gridW / cols
            readonly property real cellH: Math.min(gridH / rows, 170)

            // selección con teclado (índice en results); -1 = ninguna
            property int sel: -1
            onResultsChanged: {
                sel = query !== "" && results.length > 0 ? 0 : -1;
                pages.currentIndex = 0;
            }
            onSelChanged: if (sel >= 0) pages.currentIndex = Math.floor(sel / perPage)

            function launch(app: var): void {
                if (!app) return;
                Apps.launch(app);
                root.hide();
            }

            function goPage(i: int): void {
                pages.currentIndex = Math.max(0, Math.min(pageCount - 1, i));
            }

            // menú contextual
            property var ctxApp: null
            property point ctxPos: Qt.point(0, 0)

            Component.onCompleted: {
                search.text = "";
                search.forceActiveFocus();
            }
            Connections {
                target: root
                function onOpenChanged(): void {
                    if (!root.open) return;
                    search.text = "";
                    win.ctxApp = null;
                    pages.currentIndex = 0;
                    pages.positionViewAtBeginning();
                    search.forceActiveFocus();
                }
            }

            // fondo: oscurece (y Hyprland difumina la capa)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.04, 0.04, 0.06, 0.5 * root.p)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }

            Item {
                id: content
                anchors.fill: parent
                opacity: root.p
                // como macOS: al abrir, la cuadrícula «se aleja» desde un poco más grande
                scale: 1.08 - 0.08 * root.p
                transformOrigin: Item.Center

                // ------------------------------------------------ buscador
                Rectangle {
                    id: searchBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 48
                    width: 240
                    height: 30
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, search.activeFocus ? 0.28 : 0.16)

                    Row {
                        anchors.centerIn: search.text === "" ? parent : undefined
                        anchors.left: search.text === "" ? undefined : parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Icon { text: "search"; size: 16; color: Qt.rgba(1, 1, 1, 0.7); anchors.verticalCenter: parent.verticalCenter }
                        Txt {
                            visible: search.text === ""
                            text: I18n.t("Buscar")
                            color: Qt.rgba(1, 1, 1, 0.55)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.leftMargin: 32
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.font
                        font.pixelSize: Theme.textNormal
                        color: "white"
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.primaryFg
                        clip: true
                        // con el texto vacío el «Buscar» va centrado: sin cursor a la izquierda
                        cursorDelegate: Rectangle { width: 1.5; color: "white"; visible: search.text !== "" && search.cursorVisible }

                        Keys.onEscapePressed: {
                            if (win.ctxApp) win.ctxApp = null;
                            else if (search.text !== "") search.text = "";
                            else root.hide();
                        }
                        Keys.onReturnPressed: win.launch(win.results[Math.max(0, win.sel)])
                        Keys.onEnterPressed: win.launch(win.results[Math.max(0, win.sel)])
                        Keys.onPressed: e => {
                            const n = win.results.length;
                            const atEnd = search.cursorPosition === search.text.length;
                            if (e.key === Qt.Key_Right && atEnd) {
                                if (win.sel < 0) win.goPage(pages.currentIndex + 1);
                                else win.sel = Math.min(n - 1, win.sel + 1);
                            } else if (e.key === Qt.Key_Left && search.cursorPosition === 0) {
                                if (win.sel < 0) win.goPage(pages.currentIndex - 1);
                                else win.sel = Math.max(0, win.sel - 1);
                            } else if (e.key === Qt.Key_Down) {
                                win.sel = win.sel < 0 ? pages.currentIndex * win.perPage : Math.min(n - 1, win.sel + win.cols);
                            } else if (e.key === Qt.Key_Up) {
                                win.sel = Math.max(0, win.sel - win.cols);
                            } else if (e.key === Qt.Key_PageDown) {
                                win.goPage(pages.currentIndex + 1);
                            } else if (e.key === Qt.Key_PageUp) {
                                win.goPage(pages.currentIndex - 1);
                            } else return;
                            e.accepted = true;
                        }
                    }
                }

                // ------------------------------------------------ páginas
                ListView {
                    id: pages
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: 120
                    height: win.gridH
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    highlightMoveDuration: Math.max(1, Theme.animSlow)
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    model: win.pageCount
                    currentIndex: 0

                    delegate: Item {
                        id: page
                        required property int index
                        width: pages.width
                        height: pages.height

                        // clic en un hueco vacío = cerrar (Flickable no deja pasar el clic al fondo)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.hide()
                        }

                        Grid {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Math.max(0, (parent.height - win.rows * win.cellH) / 2)
                            columns: win.cols

                            Repeater {
                                model: win.results.slice(page.index * win.perPage, (page.index + 1) * win.perPage)

                                MouseArea {
                                    id: cell
                                    required property var modelData
                                    required property int index
                                    readonly property int gIndex: page.index * win.perPage + index
                                    readonly property bool selected: win.sel === gIndex

                                    width: win.cellW
                                    height: win.cellH
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: e => {
                                        if (e.button === Qt.RightButton) {
                                            win.ctxPos = cell.mapToItem(content, e.x, e.y);
                                            win.ctxApp = cell.modelData;
                                        } else {
                                            win.launch(cell.modelData);
                                        }
                                    }

                                    Rectangle {
                                        anchors.centerIn: icon
                                        width: icon.width + 22
                                        height: icon.height + 22
                                        radius: 22
                                        color: Qt.rgba(1, 1, 1, cell.selected ? 0.22 : 0)
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    }

                                    AppIcon {
                                        id: icon
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: Math.max(4, (parent.height - 96 - 34) / 2)
                                        size: 96
                                        name: cell.modelData.icon ?? ""
                                        scale: cell.pressed ? 0.9 : 1
                                        Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                                    }
                                    Txt {
                                        anchors.top: icon.bottom
                                        anchors.topMargin: 10
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 20
                                        horizontalAlignment: Text.AlignHCenter
                                        text: cell.modelData.name
                                        color: "white"
                                        font.pixelSize: Theme.textSmall + 1
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.35)
                                    }
                                    Icon {
                                        visible: Apps.isPinned(cell.modelData.id ?? "")
                                        anchors.right: icon.right
                                        anchors.top: icon.top
                                        anchors.margins: -4
                                        text: "keep"
                                        size: 16
                                        fill: 1
                                        color: "white"
                                    }
                                }
                            }
                        }
                    }

                    // rueda / desplazamiento con 2 dedos: una página por gesto
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        property real acc: 0
                        property bool locked: false
                        Timer { id: wheelReset; interval: 180; onTriggered: { parent.acc = 0; parent.locked = false; } }
                        onWheel: e => {
                            const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : e.angleDelta.y;
                            wheelReset.restart();
                            if (locked) return;
                            acc += d;
                            if (acc <= -120) { win.goPage(pages.currentIndex + 1); acc = 0; locked = true; }
                            else if (acc >= 120) { win.goPage(pages.currentIndex - 1); acc = 0; locked = true; }
                        }
                    }

                    // sin resultados
                    Txt {
                        anchors.centerIn: parent
                        visible: win.results.length === 0
                        text: I18n.t("No encontré nada con «") + search.text + "»"
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.pixelSize: Theme.textLarge
                    }
                }

                // ------------------------------------------------ puntos de página
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: pages.bottom
                    anchors.topMargin: 18
                    spacing: 4
                    visible: win.pageCount > 1
                    Repeater {
                        model: win.pageCount
                        MouseArea {
                            id: dot
                            required property int index
                            width: 18
                            height: 18
                            onClicked: win.goPage(dot.index)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: Qt.rgba(1, 1, 1, pages.currentIndex === dot.index ? 0.92 : 0.35)
                                Behavior on color { ColorAnimation { duration: Theme.anim } }
                            }
                        }
                    }
                }

                // ------------------------------------------------ menú contextual
                MouseArea {
                    anchors.fill: parent
                    visible: !!win.ctxApp
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: win.ctxApp = null
                }
                Rectangle {
                    id: ctxMenu
                    visible: !!win.ctxApp
                    x: Math.max(8, Math.min(win.ctxPos.x, content.width - width - 8))
                    y: Math.max(8, Math.min(win.ctxPos.y, content.height - height - 8))
                    width: 230
                    height: ctxCol.implicitHeight + 12
                    radius: 10
                    color: Theme.alpha(Theme.surfaceHigh, 0.97)
                    border.width: 1
                    border.color: Theme.alpha(Theme.fg, 0.12)
                    readonly property bool pinned: !!win.ctxApp && Apps.isPinned(win.ctxApp.id)
                    ColumnLayout {
                        id: ctxCol
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 0
                        Repeater {
                            model: win.ctxApp ? [
                                { icon: "open_in_new", text: I18n.t("Abrir"), run: () => win.launch(win.ctxApp) },
                                { icon: ctxMenu.pinned ? "keep_off" : "keep", text: ctxMenu.pinned ? I18n.t("Quitar de la barra") : I18n.t("Fijar en la barra"), run: () => Wm.togglePin(win.ctxApp.id) },
                                { icon: "visibility_off", text: I18n.t("Ocultar del menú"), run: () => Apps.setVisible(win.ctxApp, false) }
                            ] : []
                            MouseArea {
                                id: opt
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                hoverEnabled: true
                                onClicked: { opt.modelData.run(); win.ctxApp = null; }
                                Rectangle { anchors.fill: parent; radius: 6; color: opt.containsMouse ? Theme.alpha(Theme.primary, 0.18) : "transparent" }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    spacing: 10
                                    Icon { text: opt.modelData.icon; size: 18 }
                                    Txt { text: opt.modelData.text; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
