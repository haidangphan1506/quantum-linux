import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Historial del portapapeles (Super + Shift + V / menú Editar). Las apps se buscan con
// Spotlight y se ven en Launchpad: aquí solo queda el portapapeles (cliphist).
PanelWindow {
    id: win

    readonly property bool open: Shell.clipboardOpen
    visible: open || card.enter > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.alpha(Theme.scrim, 0.22 * card.enter)

    readonly property var results: Clipboard.entries.filter(e => Apps.normalize(e.text).includes(Apps.normalize(search.text)))

    onOpenChanged: {
        enterAnim.to = open ? 1 : 0;
        enterAnim.duration = open ? 300 : 160;
        enterAnim.easing.type = open ? Easing.OutBack : Easing.InCubic;
        enterAnim.restart();
        if (!open)
            return;
        search.text = "";
        search.forceActiveFocus();
        Clipboard.refresh();
        list.currentIndex = 0;
        list.positionViewAtBeginning();
    }

    function activate(index: int): void {
        const item = results[index];
        if (!item)
            return;
        Clipboard.copy(item);
        Shell.clipboardOpen = false;
    }

    // Clic fuera de la tarjeta: cerrar
    MouseArea {
        anchors.fill: parent
        enabled: win.open
        onClicked: Shell.clipboardOpen = false
    }

    Card {
        id: card

        property real enter: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(560, parent.width - 40)
        height: Math.min(520, parent.height - 120)
        color: Theme.glassPanel
        opacity: Math.min(1, enter * 1.3)
        scale: 0.96 + 0.04 * enter
        NumberAnimation { id: enterAnim; target: card; property: "enter"; easing.overshoot: 1.05 }

        MouseArea { anchors.fill: parent }  // no cerrar al hacer clic dentro

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // Buscador + «Borrar todo»
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: height / 2
                color: Theme.glassTile
                border.width: search.activeFocus ? 2 : 0
                border.color: Theme.primary

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10
                    Icon { text: "content_paste"; color: Theme.fgMuted }
                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        font.family: Theme.font
                        font.pixelSize: Theme.textNormal
                        color: Theme.fg
                        clip: true
                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !search.text
                            text: I18n.t("Busca en lo que copiaste…")
                            color: Theme.fgMuted
                        }
                        onTextChanged: list.currentIndex = 0
                        Keys.onEscapePressed: Shell.clipboardOpen = false
                        Keys.onDownPressed: list.currentIndex = Math.min(win.results.length - 1, list.currentIndex + 1)
                        Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
                        Keys.onReturnPressed: win.activate(list.currentIndex)
                        Keys.onEnterPressed: win.activate(list.currentIndex)
                    }
                    Txt {
                        visible: Clipboard.entries.length > 0
                        text: I18n.t("Borrar todo")
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

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: win.results
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 46
                    radius: 10
                    color: list.currentIndex === index ? Theme.alpha(Theme.primary, 0.16)
                         : rowArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Icon { text: row.modelData.isImage ? "image" : "notes"; color: Theme.fgMuted }
                        Txt {
                            Layout.fillWidth: true
                            text: row.modelData.isImage ? I18n.t("Imagen") : row.modelData.text
                            maximumLineCount: 1
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = row.index
                        onClicked: win.activate(row.index)
                    }
                }

                Txt {
                    anchors.centerIn: parent
                    visible: win.results.length === 0
                    text: Clipboard.entries.length === 0 ? I18n.t("Aún no has copiado nada") : I18n.t("No encontré nada con «") + search.text + "»"
                    color: Theme.fgMuted
                }
            }

            Txt {
                Layout.alignment: Qt.AlignHCenter
                text: I18n.t("Enter para copiar · Esc para cerrar")
                font.pixelSize: Theme.textSmall
                color: Theme.alpha(Theme.fgMuted, 0.75)
            }
        }
    }
}
