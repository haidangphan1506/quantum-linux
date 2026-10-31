import QtQuick
import qs.services

// Botón cuadrado de la barra de tareas (Inicio, Buscar y apps).
Rectangle {
    id: root

    property string tip: ""
    property bool active: false
    readonly property bool hovered: area.containsMouse
    readonly property alias pressed: area.pressed
    default property alias content: holder.data
    signal clicked
    signal rightClicked
    signal middleClicked
    // Arrastrar para reordenar (solo si draggable): dragMoved(dx) mientras se mueve, dropped() al soltar
    property bool draggable: false
    property bool dragging: false
    signal dragMoved(real dx)
    signal dropped

    implicitWidth: Math.round(46 * Theme.dockScale)
    implicitHeight: Math.round(44 * Theme.dockScale)
    radius: Math.max(6, Theme.radiusSmall + 2)
    color: active ? Theme.alpha(Theme.fg, 0.12) : area.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Item {
        id: holder
        anchors.fill: parent
        scale: area.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        property real startX: 0
        onPressed: e => { startX = e.x; }
        onPositionChanged: e => {
            if (!root.draggable || !(e.buttons & Qt.LeftButton)) return;
            const dx = e.x - startX;
            if (!root.dragging && Math.abs(dx) > 10) root.dragging = true;
            if (root.dragging) root.dragMoved(dx);
        }
        onReleased: e => {
            if (root.dragging) { root.dragging = false; root.dropped(); }
        }
        onCanceled: if (root.dragging) { root.dragging = false; root.dropped(); }
        onClicked: e => {
            if (root.dragging) return;
            if (e.button === Qt.RightButton) root.rightClicked();
            else if (e.button === Qt.MiddleButton) root.middleClicked();
            else root.clicked();
        }
    }
}
