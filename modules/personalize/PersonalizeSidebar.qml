// Barra lateral de Ajustes del Sistema (estilo macOS): buscador, cuenta del usuario y
// las páginas en grupos con ícono en cuadro de color; la elegida va en azul de acento.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

Rectangle {
    id: side
    required property var host
    readonly property string user: Quickshell.env("USER") ?? ""
    Layout.fillHeight: true
    Layout.preferredWidth: 240
    // gris claro/oscuro translúcido, como la barra lateral de vidrio de macOS
    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.035)

    // línea que separa la barra lateral del contenido
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.alpha(Theme.fg, 0.08)
    }

    // pie: Deshacer, Restablecer y Avanzado (en macOS no hay botones a la derecha del título)
    Rectangle {
        id: foot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 44
        color: "transparent"
        Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.fg, 0.08) }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 2
            ToolBtn { icon: "undo"; enabled_: Settings.changed; onClicked: Settings.undo() }
            ToolBtn {
                icon: side.host.confirmReset ? "warning" : "restart_alt"
                danger: side.host.confirmReset
                onClicked: {
                    if (!side.host.confirmReset) { side.host.confirmReset = true; resetTimer.restart(); return; }
                    side.host.confirmReset = false;
                    Settings.resetAll();
                }
                Timer { id: resetTimer; interval: 3000; onTriggered: side.host.confirmReset = false }
            }
            Item { Layout.fillWidth: true }
            Txt { text: I18n.t("Avanzado"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
            Toggle {
                Layout.leftMargin: 4
                checked: Settings.ui.advanced
                onToggled: c => Settings.setUi("advanced", c)
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 14
        anchors.bottomMargin: 54
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 1

            // buscador
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                implicitHeight: 30
                radius: 8
                color: Theme.alpha(Theme.fg, 0.07)
                Icon { id: searchIcon; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "search"; size: 16; color: Theme.fgMuted }
                TextInput {
                    id: searchIn
                    anchors.left: searchIcon.right; anchors.leftMargin: 6
                    anchors.right: parent.right; anchors.rightMargin: 8
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

            // cuenta (como «Apple Account»)
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                implicitHeight: 52
                radius: 8
                color: accArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 10
                    Rectangle {
                        implicitWidth: 38; implicitHeight: 38; radius: 19
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#64a8ff" }
                            GradientStop { position: 1; color: "#0062d6" }
                        }
                        Txt {
                            anchors.centerIn: parent
                            text: side.user.charAt(0).toUpperCase()
                            color: "white"
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Txt { Layout.fillWidth: true; text: side.user; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Txt { Layout.fillWidth: true; text: "Quantum Linux"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                    }
                }
                MouseArea { id: accArea; anchors.fill: parent; hoverEnabled: true }
            }

            Repeater {
                model: side.host.pages
                Rectangle {
                    id: nav
                    required property var modelData
                    required property int index
                    // una subpágina (General → Acerca de) deja marcada a su página
                    readonly property bool on: side.host.current === modelData.id || side.host.page.p === modelData.id
                    // al buscar también salen las subpáginas y cuenta la descripción
                    readonly property string q: side.host.query.toLowerCase()
                    readonly property bool matches: q === "" ? !modelData.p
                        : (modelData.t + " " + (modelData.h ?? "")).toLowerCase().indexOf(q) >= 0
                    // espacio entre grupos
                    readonly property bool newGroup: index > 0 && side.host.pages[index - 1].g !== modelData.g
                    visible: matches
                    Layout.fillWidth: true
                    Layout.topMargin: newGroup && side.host.query === "" ? 17 : 0
                    implicitHeight: 34
                    radius: 7
                    // como el ejemplo: la página elegida en gris, no en azul
                    color: on ? Theme.alpha(Theme.fg, 0.1) : navArea.containsMouse ? Theme.alpha(Theme.fg, 0.05) : "transparent"
                    // línea fina que separa los grupos
                    Rectangle {
                        visible: nav.newGroup && side.host.query === ""
                        y: -9
                        x: 8
                        width: parent.width - 16
                        height: 1
                        color: Theme.alpha(Theme.fg, 0.12)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 8
                        spacing: 12
                        // ícono en cuadro de color redondeado, como en macOS
                        Rectangle {
                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                            radius: 7
                            color: nav.modelData.k
                            Icon { anchors.centerIn: parent; text: nav.modelData.i; size: 18; fill: 1; color: "white" }
                        }
                        Txt {
                            Layout.fillWidth: true
                            text: nav.modelData.t
                            color: Theme.fg
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: side.host.go(nav.modelData.id)
                    }
                }
            }
        }
    }
}
