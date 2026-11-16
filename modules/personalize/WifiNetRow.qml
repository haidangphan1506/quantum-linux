import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Fila de una red en Wi-Fi: candado, señal y, si pide contraseña, el campo en la misma fila.
OptionRow {
    id: nr
    required property var modelData
    readonly property bool asking: Net.pendingSsid === modelData.name
    title: modelData.name
    help: Net.connecting && Net.tracked === modelData ? I18n.t("Conectando…") : ""
    MouseArea {
        parent: nr
        z: -1
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!nr.asking) Net.select(nr.modelData.name)
        Rectangle {
            anchors.fill: parent; anchors.leftMargin: -8; anchors.rightMargin: -8; radius: 6
            color: parent.containsMouse && !nr.asking ? Theme.alpha(Theme.fg, 0.04) : "transparent"
        }
    }
    RowLayout {
        spacing: 8
        Rectangle {
            visible: nr.asking
            implicitWidth: 200; implicitHeight: 28; radius: 7
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : "white"
            border.width: 1; border.color: Theme.alpha(Theme.fg, 0.15)
            TextInput {
                id: pw
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                font.family: Theme.font; font.pixelSize: Theme.textNormal
                color: Theme.fg
                clip: true
                focus: nr.asking
                onTextChanged: Net.password = text
                onAccepted: Net.connectPending()
                Txt { anchors.verticalCenter: parent.verticalCenter; visible: !pw.text; text: I18n.t("Contraseña"); color: Theme.fgMuted }
            }
        }
        PillButton { visible: nr.asking; text: I18n.t("Unirse"); primary: true; implicitHeight: 28; onClicked: Net.connectPending() }
        PillButton { visible: nr.asking; text: I18n.t("Cancelar"); implicitHeight: 28; onClicked: Net.cancelPending() }
        Icon { visible: Net.securityKind(nr.modelData) !== "open"; text: "lock"; size: 16; color: Theme.fgMuted }
        Icon { text: nr.bars; size: 18; color: Theme.fg }
    }

    readonly property string bars: { const s = Net.signalOf(modelData); return s > 75 ? "signal_wifi_4_bar" : s > 50 ? "network_wifi_3_bar" : s > 25 ? "network_wifi_2_bar" : "network_wifi_1_bar"; }
}
