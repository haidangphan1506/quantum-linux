import QtQuick
import qs.services

// Un dígito del reloj que, al cambiar, rueda: el nuevo baja desde arriba y el viejo
// cae y se desvanece.
Item {
    id: r

    property string ch: "0"
    property color color: "white"
    property alias font: cur.font
    property string shown: ""
    property string prev: ""
    property real p: 1

    implicitWidth: cur.implicitWidth
    implicitHeight: cur.implicitHeight
    clip: true

    Component.onCompleted: shown = ch
    onChChanged: {
        if (ch === shown) return;
        prev = shown;
        shown = ch;
        roll.restart();
    }
    NumberAnimation { id: roll; target: r; property: "p"; from: 0; to: 1; duration: Theme.animSlow * 1.6; easing.type: Easing.OutCubic }

    Text {
        id: old
        text: r.prev
        font: cur.font
        color: r.color
        y: r.p * r.height * 0.9
        opacity: 1 - r.p
        visible: r.p < 1
    }
    Text {
        id: cur
        text: r.shown
        color: r.color
        y: (r.p - 1) * r.height * 0.9
        opacity: r.p
    }
}
