import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.components

// Serpantium: el menú de apps (tecla Super). Una lista simple: escribes, flechas y Enter.
// El portapapeles (Super + V) sigue usando el menú de siempre.
PanelWindow {
    id: win

    readonly property bool open: Shell.launcherOpen && !Shell.clipboardMode
    property real k: 0
    property int sel: 0
    readonly property var results: Apps.search(search.text).slice(0, 60)

    visible: open || k > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-launcher"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0, 0, 0, 0.18 * k)

    onOpenChanged: {
        anim.to = open ? 1 : 0;
        anim.duration = Math.max(1, (open ? 320 : 150) * Theme.animMult);
        anim.easing.type = open ? Easing.OutBack : Easing.InCubic;
        anim.restart();
        if (open) { search.text = ""; sel = 0; search.forceActiveFocus(); }
    }
    NumberAnimation { id: anim; target: win; property: "k" }
    onResultsChanged: sel = 0

    function launch(i: int): void {
        const a = results[i];
        if (!a) return;
        Apps.launch(a);
        Shell.launcherOpen = false;
    }

    MouseArea { anchors.fill: parent; onClicked: Shell.launcherOpen = false }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        width: 560; height: 470
        radius: 18
        color: Serp.bg
        border.width: 1; border.color: Serp.line
        opacity: Math.min(1, win.k * 1.5)
        scale: 0.94 + 0.06 * win.k
        clip: true
        MouseArea { anchors.fill: parent }

        // halo
        Rectangle {
            width: 520; height: 520; radius: 260
            x: 230; y: 40
            color: Qt.rgba(1, 1, 1, 0.018)
            border.width: 1; border.color: Qt.rgba(0.96, 0.65, 0.79, 0.05)
        }

        // buscador
        Rectangle {
            id: field
            x: 12; y: 12; width: parent.width - 24; height: 42; radius: 10
            color: Serp.card; border.width: 1; border.color: search.activeFocus ? Qt.rgba(0.96, 0.65, 0.79, 0.4) : Serp.line
            Icon { id: si; x: 12; anchors.verticalCenter: parent.verticalCenter; text: "search"; size: 18; color: Serp.muted }
            TextInput {
                id: search
                anchors.left: si.right; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                font.family: Serp.font; font.pixelSize: 13; color: Serp.fg
                selectionColor: Serp.pink; selectedTextColor: Serp.pinkFg
                clip: true
                Text {
                    visible: !search.text
                    text: "Buscar apps..."
                    font: search.font; color: Serp.muted
                }
                Keys.onDownPressed: { win.sel = Math.min(win.results.length - 1, win.sel + 1); list.positionViewAtIndex(win.sel, ListView.Contain); }
                Keys.onUpPressed: { win.sel = Math.max(0, win.sel - 1); list.positionViewAtIndex(win.sel, ListView.Contain); }
                Keys.onReturnPressed: win.launch(win.sel)
                Keys.onEnterPressed: win.launch(win.sel)
                Keys.onEscapePressed: Shell.launcherOpen = false
            }
        }

        ListView {
            id: list
            x: 12; y: field.y + field.height + 10
            width: parent.width - 24; height: parent.height - y - 12
            clip: true
            spacing: 2
            model: win.results
            boundsBehavior: Flickable.StopAtBounds
            delegate: MouseArea {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: index === win.sel
                width: list.width; height: 42
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: win.sel = index
                onClicked: win.launch(index)
                scale: pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
                Rectangle {
                    anchors.fill: parent; radius: 9
                    color: row.on ? Serp.pink : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }
                }
                IconImage {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 22
                    source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                }
                Text {
                    x: 46; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 60
                    text: row.modelData.name
                    font.family: Serp.font; font.pixelSize: 13; font.weight: row.on ? Font.Bold : Font.Normal
                    color: row.on ? Serp.pinkFg : Serp.fg
                    elide: Text.ElideRight
                }
            }
            Text {
                anchors.centerIn: parent
                visible: win.results.length === 0
                text: "No encontré nada con «" + search.text + "»"
                font.family: Serp.font; font.pixelSize: 12; color: Serp.muted
            }
        }
    }
}
