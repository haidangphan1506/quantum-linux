import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

// Menú desplegable estilo macOS (barra de menús). items: lista de
// { text, shortcut?, enabled?, action: function } o { separator: true }.
//
// Es una capa propia (PanelWindow) y no un PopupWindow: en Hyprland 0.57 los
// xdg_popup de la barra no recibían el ratón (ni hover ni clic: el clic caía en la
// ventana de debajo y el grab se soltaba), así que ninguna acción se ejecutaba.
PanelWindow {
    id: menu

    property Item anchorItem
    property var items: []
    property var barWindow: null   // la barra entra en el grab: al pasar a otro botón se cambia de menú (como macOS)
    property real closedAt: 0      // evita reabrir al hacer clic en el mismo botón para cerrarlo
    property bool pressing: false
    signal opened()

    function open(): void {
        if (anchorItem) {
            const p = anchorItem.mapToItem(null, 0, anchorItem.height);
            posX = Math.round(p.x);
            posY = Math.round(p.y + 3);
        }
        visible = true;
        opened();
    }
    function close(): void { if (visible) { visible = false; closedAt = Date.now(); pressing = false; } }
    function toggle(): void { if (visible) close(); else if (Date.now() - closedAt > 200) open(); }
    function run(entry: var): void {
        if (!entry.on) return;
        const act = entry.modelData.action;
        close();
        if (act) act();
    }

    property int posX: 0
    property int posY: 0

    visible: false
    screen: barWindow?.screen ?? null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true }
    margins { top: posY; left: Math.min(posX, (screen?.width ?? 1920) - implicitWidth - 4) }
    implicitWidth: Math.max(230, col.implicitWidth + 12)
    implicitHeight: col.implicitHeight + 12
    color: "transparent"

    HyprlandFocusGrab {
        windows: menu.barWindow ? [menu, menu.barWindow] : [menu]
        active: menu.visible
        // por si acaso: si el clic es dentro del menú, no cerrar antes de recibirlo
        onCleared: if (!hover.hovered && !menu.pressing) menu.close()
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.alpha(Theme.surface, 0.96)
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.12)

        HoverHandler { id: hover }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 6
            spacing: 0

            Repeater {
                model: menu.items

                Item {
                    id: entry
                    required property var modelData
                    readonly property bool sep: !!modelData.separator
                    readonly property bool on: modelData.enabled === undefined || modelData.enabled
                    readonly property bool hot: area.containsMouse && on

                    Layout.fillWidth: true
                    implicitHeight: sep ? 11 : 26
                    implicitWidth: sep ? 0 : label.implicitWidth + keys.implicitWidth + 44

                    Rectangle {
                        visible: entry.sep
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: 1
                        color: Theme.alpha(Theme.fg, 0.12)
                    }

                    // resaltado al pasar el ratón (color de acento, como macOS)
                    Rectangle {
                        visible: !entry.sep
                        anchors.fill: parent
                        radius: 6
                        color: entry.hot ? (area.pressed ? Qt.darker(Theme.primary, 1.15) : Theme.primary) : "transparent"
                        Behavior on color { ColorAnimation { duration: 90 } }
                    }
                    Txt {
                        id: label
                        visible: !entry.sep
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text ?? ""
                        font.pixelSize: 13
                        color: !entry.on ? Theme.fgMuted : entry.hot ? Theme.primaryFg : Theme.fg
                    }
                    Txt {
                        id: keys
                        visible: !entry.sep && !!entry.modelData.shortcut
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.shortcut ?? ""
                        font.pixelSize: 12
                        color: entry.hot ? Theme.alpha(Theme.primaryFg, 0.8) : Theme.fgMuted
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        enabled: !entry.sep
                        hoverEnabled: true
                        cursorShape: entry.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: menu.pressing = true
                        onCanceled: menu.pressing = false
                        onReleased: {
                            menu.pressing = false;
                            if (containsMouse) menu.run(entry);
                        }
                    }
                }
            }
        }
    }
}
