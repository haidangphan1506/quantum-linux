import QtQuick
import QtQuick.Layouts
import qs.services

// Barra de uso de un límite de Claude con una marca del tiempo transcurrido de la ventana:
// si la barra pasa la marca, se está gastando más rápido de lo que avanza el tiempo.
Item {
    id: pm

    property real value: 0          // 0-1, uso
    property real mark: -1          // 0-1, tiempo transcurrido (-1: sin marca)
    property color accent: Theme.primary

    Layout.fillWidth: true
    implicitHeight: 10

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.alpha(Theme.fg, 0.1)
        Rectangle {
            width: parent.width * Math.min(1, Math.max(0, pm.value))
            height: parent.height
            radius: 3
            color: pm.accent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }
    Rectangle {
        visible: pm.mark >= 0
        x: Math.round(pm.width * Math.max(0, pm.mark)) - 1
        width: 2
        height: pm.height
        radius: 1
        color: Theme.fg
        opacity: 0.7
    }
}
