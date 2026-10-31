import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.components

// Menú de apps (Super) y historial del portapapeles (Super + V).
PanelWindow {
    id: win

    readonly property bool clipMode: Shell.clipboardMode

    // con Serpantium, el menú de apps es SerpLauncher (aquí queda el portapapeles)
    readonly property bool open: Shell.launcherOpen && (!Serp.on || Shell.clipboardMode)
    visible: open || card.enter > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.alpha(Theme.scrim, 0.22 * card.enter)

    readonly property string user: Quickshell.env("USER") ?? ""

    onOpenChanged: {
        enterAnim.to = open ? 1 : 0;
        enterAnim.duration = open ? 340 : 170;
        enterAnim.easing.type = open ? Easing.OutBack : Easing.InCubic;
        enterAnim.restart();
        if (!open)
            return;
        search.text = "";
        search.forceActiveFocus();
        if (clipMode)
            Clipboard.refresh();
    }

    readonly property var results: clipMode
        ? Clipboard.entries.filter(e => Apps.normalize(e.text).includes(Apps.normalize(search.text)))
        : Apps.search(search.text)

    function activate(index: int): void {
        const item = results[index];
        if (!item)
            return;
        if (clipMode)
            Clipboard.copy(item);
        else
            Apps.launch(item);
        Shell.launcherOpen = false;
    }

    // Clic fuera de la tarjeta: cerrar
    MouseArea {
        anchors.fill: parent
        enabled: win.open
        onClicked: Shell.launcherOpen = false
    }

    Card {
        id: card

        // Se abre desde la barra de tareas, como el menú Inicio de Windows 11
        property real enter: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 78
        width: Math.min(720, parent.width - 40)
        height: Math.min(640, parent.height - 78 - 70)
        color: Theme.alpha(Theme.surface, 0.94)
        opacity: Math.min(1, enter * 1.3)
        scale: 0.96 + 0.04 * enter
        transformOrigin: Item.Bottom
        transform: Translate { y: (1 - card.enter) * 40 }
        NumberAnimation { id: enterAnim; target: card; property: "enter"; easing.overshoot: 1.05 }

        // línea de color de Quantum arriba
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 2 * parent.radius
            height: 1
            opacity: 0.6
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.25; color: Theme.brandCyan }
                GradientStop { position: 0.5; color: Theme.brandIndigo }
                GradientStop { position: 0.75; color: Theme.brandViolet }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        MouseArea { anchors.fill: parent }  // no cerrar al hacer clic dentro

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // Buscador
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: height / 2
                color: Theme.surfaceHigh
                border.width: search.activeFocus ? 2 : 0
                border.color: Theme.primary

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 12

                    Icon {
                        text: win.clipMode ? "content_paste" : "search"
                        size: 22
                        color: Theme.fgMuted
                    }

                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        font.family: Theme.font
                        font.pixelSize: Theme.textLarge
                        color: Theme.fg
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.primaryFg
                        clip: true
                        onTextChanged: grid.currentIndex = 0

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !search.text
                            text: win.clipMode ? "Busca en lo que copiaste…" : "Busca apps, juegos o ajustes…"
                            font.pixelSize: Theme.textLarge
                            color: Theme.fgMuted
                        }

                        Keys.onEscapePressed: Shell.launcherOpen = false
                        Keys.onReturnPressed: win.activate(grid.currentIndex)
                        Keys.onEnterPressed: win.activate(grid.currentIndex)
                        Keys.onPressed: e => {
                            const cols = win.clipMode ? 1 : grid.columns;
                            if (e.key === Qt.Key_Down) grid.currentIndex = Math.min(win.results.length - 1, grid.currentIndex + cols);
                            else if (e.key === Qt.Key_Up) grid.currentIndex = Math.max(0, grid.currentIndex - cols);
                            else if (e.key === Qt.Key_Right && !win.clipMode && search.cursorPosition === search.text.length) grid.currentIndex = Math.min(win.results.length - 1, grid.currentIndex + 1);
                            else if (e.key === Qt.Key_Left && !win.clipMode && search.cursorPosition === 0) grid.currentIndex = Math.max(0, grid.currentIndex - 1);
                            else return;
                            e.accepted = true;
                        }
                    }

                    Txt {
                        visible: win.clipMode && Clipboard.entries.length > 0
                        text: "Borrar todo"
                        color: Theme.primary
                        font.weight: Font.DemiBold
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Clipboard.clear()
                        }
                    }
                }
            }

            // Resultados
            GridView {
                id: grid

                readonly property int columns: win.clipMode ? 1 : Math.max(1, Math.floor(width / 132))

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: win.results
                cellWidth: win.clipMode ? width : width / columns
                cellHeight: win.clipMode ? 52 : 118
                currentIndex: 0
                highlightFollowsCurrentItem: true
                highlightMoveDuration: Theme.animFast
                boundsBehavior: Flickable.StopAtBounds

                highlight: Rectangle {
                    radius: Theme.radius
                    color: Theme.alpha(Theme.primary, 0.16)
                    border.width: 1
                    border.color: Theme.alpha(Theme.primary, 0.4)
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index

                    width: grid.cellWidth
                    height: grid.cellHeight

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: 3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: grid.currentIndex = cell.index
                        onClicked: win.activate(cell.index)
                    }

                    // Modo apps: ícono grande y nombre
                    ColumnLayout {
                        visible: !win.clipMode
                        anchors.centerIn: parent
                        width: parent.width - 16
                        spacing: 8

                        AppIcon {
                            Layout.alignment: Qt.AlignHCenter
                            size: 52
                            name: win.clipMode ? "" : cell.modelData.icon
                        }
                        Txt {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: win.clipMode ? "" : cell.modelData.name
                            font.pixelSize: Theme.textSmall + 1
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                        }
                    }

                    // Modo portapapeles: una línea por elemento
                    RowLayout {
                        visible: win.clipMode
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        Icon {
                            text: win.clipMode && cell.modelData.isImage ? "image" : "notes"
                            color: Theme.fgMuted
                        }
                        Txt {
                            Layout.fillWidth: true
                            text: win.clipMode ? (cell.modelData.isImage ? "Imagen" : cell.modelData.text) : ""
                            maximumLineCount: 1
                        }
                    }
                }

                // Sin resultados
                Txt {
                    anchors.centerIn: parent
                    visible: win.results.length === 0
                    text: win.clipMode ? "Aún no has copiado nada" : "No encontré nada con «" + search.text + "»"
                    color: Theme.fgMuted
                }
            }

            // Pie: usuario, ayuda y apagado (como en Windows 11)
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: -18
                Layout.rightMargin: -18
                Layout.bottomMargin: -18
                implicitHeight: 60
                color: Theme.alpha(Theme.surfaceLow, 0.9)
                bottomLeftRadius: card.radius
                bottomRightRadius: card.radius
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.alpha(Theme.fg, 0.06) }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 14
                    spacing: 10
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 34; radius: 17
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.brandCyan }
                            GradientStop { position: 0.5; color: Theme.brandIndigo }
                            GradientStop { position: 1; color: Theme.brandViolet }
                        }
                        Txt { anchors.centerIn: parent; text: win.user.charAt(0).toUpperCase(); color: "white"; font.weight: Font.Bold }
                    }
                    Txt { text: win.user; font.weight: Font.DemiBold }
                    Txt {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: win.clipMode ? "Enter para copiar · Esc para cerrar" : "Enter para abrir · Esc para cerrar"
                        font.pixelSize: Theme.textSmall
                        color: Theme.alpha(Theme.fgMuted, 0.75)
                    }
                    IconButton {
                        icon: "settings"
                        onClicked: { Shell.launcherOpen = false; Quickshell.execDetached(["quantum-center", "--page", "ajustes"]); }
                    }
                    IconButton {
                        icon: "power_settings_new"
                        onClicked: { Shell.launcherOpen = false; Shell.toggleSession(); }
                    }
                }
            }
        }
    }
}
