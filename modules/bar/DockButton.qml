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
    // Arrastrar para reordenar o quitar (solo si draggable): dragMoved(dx, dy) mientras se mueve, dropped() al soltar
    property bool draggable: false
    property bool dragging: false
    // mantener pulsado este tiempo (ms) levanta el icono sin tener que moverlo primero
    property int holdDelay: 300
    signal dragMoved(real dx, real dy)
    signal dropped

    // flat: sin fondo al pasar el mouse ni al estar activa (el dock de macOS solo usa un punto)
    property bool flat: false
    // busy: la app esta abriendo; el puntero del mouse muestra la espera
    property bool busy: false

    implicitWidth: Math.round(50 * Theme.dockScale)
    implicitHeight: Math.round(50 * Theme.dockScale)
    radius: Math.max(6, Theme.radiusSmall + 2)
    color: flat ? "transparent" : active ? Theme.alpha(Theme.fg, 0.12) : area.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Item {
        id: holder
        anchors.fill: parent
        // al levantarlo (nhấn giữ / arrastrar) el icono vuelve a su tamaño: se ve que «se despegó»
        scale: root.dragging ? 1 : area.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.busy ? Qt.BusyCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        // Se mide en coordenadas de la ventana (escena), no locales: el botón arrastrado se mueve
        // con un Translate, y en coordenadas locales el desplazamiento se «anula» a sí mismo
        // (el icono temblaba y saltaba de un lado a otro mientras se arrastraba).
        property real startX: 0
        property real startY: 0
        // hubo arrastre en esta pulsación: el clic que llega después de soltar no cuenta
        property bool moved: false
        preventStealing: true
        onPressed: e => {
            const p = area.mapToItem(null, e.x, e.y);
            startX = p.x; startY = p.y;
            moved = false;
            if (root.draggable && e.button === Qt.LeftButton) holdTimer.restart();
        }
        // nhấn giữ: el icono se levanta y ya sigue al mouse (para reordenar o sacarlo del dock)
        Timer {
            id: holdTimer
            interval: root.holdDelay
            onTriggered: if (area.pressed && !root.dragging) {
                root.dragging = true;
                area.moved = true;
                root.dragMoved(0, 0);
            }
        }
        onPositionChanged: e => {
            if (!root.draggable || !(e.buttons & Qt.LeftButton)) return;
            const p = area.mapToItem(null, e.x, e.y);
            const dx = p.x - startX;
            const dy = p.y - startY;
            if (!root.dragging && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) { holdTimer.stop(); root.dragging = true; moved = true; }
            if (root.dragging) root.dragMoved(dx, dy);
        }
        onReleased: e => {
            holdTimer.stop();
            if (root.dragging) { root.dragging = false; root.dropped(); }
        }
        onCanceled: {
            holdTimer.stop();
            if (root.dragging) { root.dragging = false; root.dropped(); }
        }
        onClicked: e => {
            if (root.dragging || moved) return;
            if (e.button === Qt.RightButton) root.rightClicked();
            else if (e.button === Qt.MiddleButton) root.middleClicked();
            else root.clicked();
        }
    }
}
