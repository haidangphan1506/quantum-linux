import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Fila de un Group (estilo macOS): título (y ayuda) a la izquierda, el control a la
// derecha y una línea fina encima si hay otra fila visible antes.
Item {
    id: root

    property string title: ""
    property string help: ""
    property string icon: ""
    property color iconColor: "#007aff"
    property string appIcon: ""            // ícono de una app (en vez del cuadro de color)
    property bool advanced: false
    property bool dim: false               // atenuada (opción que no se aplica ahora)
    default property alias control: holder.data

    // primera fila visible del recuadro: sin línea encima
    readonly property bool first: {
        const kids = parent ? parent.children : [];
        for (let i = 0; i < kids.length; i++)
            if (kids[i].visible) return kids[i] === root;
        return true;
    }

    visible: !advanced || Settings.ui.advanced
    Layout.fillWidth: true
    implicitHeight: Math.max(44, row.implicitHeight + 16)
    opacity: dim ? 0.5 : 1

    Rectangle {
        visible: !root.first
        width: parent.width
        height: 1
        color: Theme.alpha(Theme.fg, 0.08)
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Rectangle {
            visible: root.icon !== ""
            implicitWidth: 26; implicitHeight: 26; radius: 7
            color: root.iconColor
            Icon { anchors.centerIn: parent; text: root.icon; size: 17; fill: 1; color: "white" }
        }
        AppIcon {
            visible: root.appIcon !== ""
            name: root.appIcon
            size: 26
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Txt { Layout.fillWidth: true; text: root.title; wrapMode: Text.WordWrap; elide: Text.ElideNone }
            Txt {
                visible: root.help !== ""
                Layout.fillWidth: true
                text: root.help
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }
        Item {
            id: holder
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
