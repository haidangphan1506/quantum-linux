import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Búsqueda estilo Spotlight (icono de búsqueda de la barra): una barra compacta
// en el centro; los resultados aparecen debajo solo cuando se escribe algo.
PanelWindow {
    id: win

    readonly property bool open: Shell.spotlightOpen
    property real enter: 0
    visible: open || enter > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-spotlight"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    onOpenChanged: {
        anim.to = open ? 1 : 0;
        anim.duration = Math.round((open ? 160 : 100) * Theme.animMult);
        anim.restart();
        if (!open)
            return;
        input.text = "";
        list.currentIndex = 0;
        input.forceActiveFocus();
    }
    NumberAnimation { id: anim; target: win; property: "enter" }

    readonly property string query: input.text.trim()
    readonly property var results: query === "" ? [] : Apps.search(input.text).slice(0, 7)

    function activate(i: int): void {
        const item = results[i];
        if (!item)
            return;
        Apps.launch(item);
        Shell.spotlightOpen = false;
    }

    MouseArea {
        anchors.fill: parent
        enabled: win.open
        onClicked: Shell.spotlightOpen = false
    }

    Card {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.22)
        width: Math.min(640, parent.width - 40)
        height: 64 + (win.results.length > 0 ? list.contentHeight + 20 : 0)
        color: Theme.glassPanel
        opacity: win.enter
        scale: 0.97 + 0.03 * win.enter
        transformOrigin: Item.Top
        Behavior on height { NumberAnimation { duration: Theme.animFast } }

        MouseArea { anchors.fill: parent }

        RowLayout {
            id: bar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 64
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 14

            Icon { text: "search"; size: 26; color: Theme.fgMuted }
            TextInput {
                id: input
                Layout.fillWidth: true
                font.family: Theme.font
                font.pixelSize: 22
                color: Theme.fg
                selectionColor: Theme.primary
                selectedTextColor: Theme.primaryFg
                clip: true
                onTextChanged: list.currentIndex = 0

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text && input.preeditText === ""
                    text: I18n.t("Spotlight")
                    font.pixelSize: 22
                    color: Theme.fgMuted
                }

                Keys.onEscapePressed: Shell.spotlightOpen = false
                Keys.onReturnPressed: win.activate(list.currentIndex)
                Keys.onEnterPressed: win.activate(list.currentIndex)
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Down) list.currentIndex = Math.min(win.results.length - 1, list.currentIndex + 1);
                    else if (e.key === Qt.Key_Up) list.currentIndex = Math.max(0, list.currentIndex - 1);
                    else return;
                    e.accepted = true;
                }
            }
        }

        ListView {
            id: list
            anchors { top: bar.bottom; left: parent.left; right: parent.right; margins: 10 }
            height: contentHeight
            visible: win.results.length > 0
            interactive: false
            model: win.results
            currentIndex: 0

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: 48
                radius: Theme.radiusSmall
                color: ListView.isCurrentItem ? Theme.alpha(Theme.primary, 0.9) : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12
                    AppIcon { size: 30; name: row.modelData.icon }
                    Txt {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        color: row.ListView.isCurrentItem ? Theme.primaryFg : Theme.fg
                        elide: Text.ElideRight
                    }
                    Txt {
                        visible: row.ListView.isCurrentItem
                        text: "↵"
                        color: Theme.primaryFg
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: list.currentIndex = row.index
                    onClicked: win.activate(row.index)
                }
            }
        }
    }
}
