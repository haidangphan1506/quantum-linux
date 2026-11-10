// Barra lateral de Personalizar: perfil, buscador, páginas, vista previa y deshacer/restablecer.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

Rectangle {
    id: side
    required property var host
    Layout.fillHeight: true
    Layout.preferredWidth: 270
    color: Theme.surfaceLow

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 6

        // tarjeta de perfil (como el Apple Account de macOS)
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            implicitHeight: profRow.implicitHeight + 16
            radius: 12
            color: profArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
            RowLayout {
                id: profRow
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8; anchors.rightMargin: 8
                spacing: 12
                Image {
                    Layout.preferredWidth: 46; Layout.preferredHeight: 46
                    source: Quickshell.shellDir + "/assets/quantum-personalize.svg"
                    sourceSize: Qt.size(92, 92)
                    smooth: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Txt { text: I18n.t("Personalizar"); font.pixelSize: Theme.textLarge; font.weight: Font.Bold }
                    Txt { text: I18n.t("Tu escritorio, a tu manera"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                }
            }
            MouseArea { id: profArea; anchors.fill: parent; hoverEnabled: true }
        }

        // buscador (como «Buscar» en Ajustes del Sistema)
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            implicitHeight: 34
            radius: 17
            color: Theme.alpha(Theme.fg, 0.07)
            Icon { id: searchIcon; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "search"; size: 18; color: Theme.fgMuted }
            TextInput {
                id: searchIn
                anchors.left: searchIcon.right; anchors.leftMargin: 8
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font
                font.pixelSize: Theme.textNormal
                color: Theme.fg
                clip: true
                onTextChanged: side.host.query = text.trim()
                Txt {
                    visible: !searchIn.text && !searchIn.activeFocus
                    text: I18n.t("Buscar")
                    color: Theme.fgMuted
                }
            }
        }

        Repeater {
            model: side.host.pages
            Rectangle {
                id: nav
                required property var modelData
                required property int index
                readonly property bool on: side.host.current === modelData.id
                readonly property bool matches: side.host.query === "" || modelData.t.toLowerCase().indexOf(side.host.query.toLowerCase()) >= 0
                // espacio entre grupos
                readonly property bool newGroup: index > 0 && side.host.pages[index - 1].g !== modelData.g
                visible: matches
                Layout.fillWidth: true
                Layout.topMargin: newGroup ? 14 : 0
                implicitHeight: 36
                radius: 9
                color: on ? Theme.primary : navArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 10
                    spacing: 10
                    // ícono en cuadro de color redondeado, como en macOS
                    Rectangle {
                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                        radius: 7
                        color: nav.modelData.k
                        Icon { anchors.centerIn: parent; text: nav.modelData.i; size: 16; fill: 1; color: "white" }
                    }
                    Txt {
                        Layout.fillWidth: true
                        text: nav.modelData.t
                        font.weight: nav.on ? Font.DemiBold : Font.Normal
                        color: nav.on ? Theme.primaryFg : Theme.fg
                    }
                }
                MouseArea {
                    id: navArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { side.host.current = nav.modelData.id; Settings.setUi("page", nav.modelData.id); }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // vista previa en vivo de los ajustes actuales
        Txt { text: I18n.t("Vista previa"); font.weight: Font.Bold; font.pixelSize: Theme.textSmall; color: Theme.fgMuted }
        MiniDesktop {
            Layout.fillWidth: true
            Layout.preferredHeight: width * 9 / 16
            v: Settings.visualState()
        }

        PillButton {
            Layout.fillWidth: true
            Layout.topMargin: 10
            text: I18n.t("Deshacer cambios")
            icon: "undo"
            enabled_: Settings.changed
            onClicked: Settings.undo()
        }
        PillButton {
            Layout.fillWidth: true
            text: side.host.confirmReset ? I18n.t("¿Seguro? Toca otra vez") : I18n.t("Restablecer todo")
            icon: "restart_alt"
            danger: true
            onClicked: {
                if (!side.host.confirmReset) { side.host.confirmReset = true; resetTimer.restart(); return; }
                side.host.confirmReset = false;
                Settings.resetAll();
            }
            Timer { id: resetTimer; interval: 3000; onTriggered: side.host.confirmReset = false }
        }
    }
}
