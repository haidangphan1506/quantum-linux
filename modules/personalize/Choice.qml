import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.components

// Menú desplegable estilo macOS (botón con ⌃⌄): [{ v: valor, t: "Texto" }].
// El menú se dibuja en la capa superior de la ventana, así no lo recorta el desplazamiento.
Rectangle {
    id: root

    property var options: []
    property var value
    property string placeholder: "—"
    signal picked(var value)

    readonly property var currentOpt: options.find(o => o.v === value) ?? null

    implicitWidth: Math.min(280, Math.max(110, lab.implicitWidth + 44))
    implicitHeight: 28
    radius: 7
    color: area.pressed ? Theme.alpha(Theme.fg, 0.14) : Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : "white"
    border.width: 1
    border.color: Theme.alpha(Theme.fg, Theme.dark ? 0.1 : 0.14)

    Txt {
        id: lab
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: chev.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: root.currentOpt?.t ?? root.placeholder
        font.pixelSize: Theme.textSmall + 1
        elide: Text.ElideRight
    }
    Icon {
        id: chev
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: "unfold_more"
        size: 16
        color: Theme.fgMuted
    }
    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.open()
    }

    Popup {
        id: menu
        // se abre con la opción elegida sobre el botón, como en macOS
        y: -Math.max(0, root.options.findIndex(o => o.v === root.value)) * 28 - 5
        width: Math.max(root.width, list.contentWidth + 10)
        height: Math.min(list.contentHeight + 10, 360)
        padding: 5
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 9
            color: Theme.dark ? "#2c2c2e" : "#f6f6f6"
            border.width: 1
            border.color: Theme.alpha(Theme.fg, 0.14)
        }
        contentItem: ListView {
            id: list
            clip: true
            model: root.options
            boundsBehavior: Flickable.StopAtBounds
            implicitHeight: contentHeight
            property real contentWidthMax: 0
            contentWidth: contentWidthMax
            delegate: Rectangle {
                id: it
                required property var modelData
                required property int index
                readonly property bool on: root.value === modelData.v
                width: ListView.view.width
                height: 28
                radius: 5
                color: itArea.containsMouse ? "#007aff" : "transparent"
                Component.onCompleted: list.contentWidthMax = Math.max(list.contentWidthMax, itT.implicitWidth + 44)
                Icon {
                    anchors.left: parent.left; anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: it.on
                    text: "check"; size: 15
                    color: itArea.containsMouse ? "white" : Theme.fg
                }
                Txt {
                    id: itT
                    anchors.left: parent.left; anchors.leftMargin: 26
                    anchors.verticalCenter: parent.verticalCenter
                    text: it.modelData.t
                    font.pixelSize: Theme.textSmall + 1
                    color: itArea.containsMouse ? "white" : Theme.fg
                }
                MouseArea {
                    id: itArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { menu.close(); if (!it.on) root.picked(it.modelData.v); }
                }
            }
        }
    }
}
