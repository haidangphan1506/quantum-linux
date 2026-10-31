import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Página «Wi-Fi» del centro de control: lista de redes, contraseña y errores.
ColumnLayout {
    id: root

    spacing: 12

    // ------------------------------------------------------------ encabezado
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        IconButton {
            icon: "chevron_left"
            onClicked: Shell.wifiPage = false
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Txt { text: "Wi-Fi"; font.weight: Font.Bold; font.pixelSize: Theme.textLarge }
            Txt { text: root.subtitle; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
        }
        IconButton {
            icon: Net.wifiEnabled ? "wifi" : "wifi_off"
            active: Net.wifiEnabled
            onClicked: Net.toggleWifi()
        }
        IconButton {
            icon: "refresh"
            onClicked: Net.startScan()
        }
    }

    readonly property string subtitle: {
        if (!Net.hasDevice)
            return "Este equipo no tiene adaptador Wi-Fi";
        if (!Net.wifiEnabled)
            return "El Wi-Fi está apagado";
        if (Net.connectedName)
            return "Conectado a " + Net.connectedName;
        if (Net.networks.length === 0)
            return "Buscando redes…";
        return Net.networks.length + (Net.networks.length === 1 ? " red disponible" : " redes disponibles");
    }

    // -------------------------------------------------------------- estado
    Rectangle {
        Layout.fillWidth: true
        visible: !Net.hasDevice || !Net.wifiEnabled
        implicitHeight: 96
        radius: Theme.radius
        color: Theme.surfaceHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Icon {
                Layout.alignment: Qt.AlignHCenter
                text: "wifi_off"
                size: 28
                color: Theme.fgMuted
            }
            Txt {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: !Net.hasDevice ? "No se encontró un adaptador Wi-Fi" : "El Wi-Fi está apagado"
                font.weight: Font.DemiBold
            }
            Txt {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: !Net.hasDevice
                    ? "Conéctate con un cable de red o revisa si el equipo tiene Wi-Fi."
                    : "Enciéndelo para ver las redes de alrededor."
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall
            }
            IconButton {
                Layout.alignment: Qt.AlignHCenter
                visible: Net.hasDevice && !Net.wifiEnabled
                icon: "power_settings_new"
                onClicked: Net.toggleWifi()
            }
        }
    }

    // ---------------------------------------------------------- contraseña
    Rectangle {
        Layout.fillWidth: true
        visible: Net.pendingSsid !== ""
        implicitHeight: pwCol.implicitHeight + 24
        radius: Theme.radius
        color: Theme.surfaceHigh
        border.width: 1
        border.color: Theme.alpha(Theme.primary, 0.5)

        ColumnLayout {
            id: pwCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Txt {
                Layout.fillWidth: true
                text: "Contraseña de «" + Net.pendingSsid + "»"
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: Theme.radiusSmall
                    color: Theme.surface
                    border.width: pwInput.activeFocus ? 2 : 0
                    border.color: Theme.primary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Icon { text: "key"; size: 18; color: Theme.fgMuted }

                        TextInput {
                            id: pwInput
                            Layout.fillWidth: true
                            font.family: Theme.font
                            font.pixelSize: Theme.textNormal
                            color: Theme.fg
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.primaryFg
                            echoMode: TextInput.Password
                            clip: true
                            onAccepted: Net.connectPending()
                            Keys.onEscapePressed: Net.cancelPending()
                            // Lo que se escribe va al servicio (para poder
                            // conectada por IPC) sin romper el binding.
                            onTextChanged: {
                                if (text !== Net.password)
                                    Net.password = text;
                            }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: 92
                    implicitHeight: 42
                    radius: Theme.radiusSmall
                    color: Theme.primary
                    opacity: pwInput.text.trim() === "" ? 0.5 : 1

                    Txt {
                        anchors.centerIn: parent
                        text: "Conectar"
                        color: Theme.primaryFg
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Net.connectPending()
                    }
                }
            }

            Txt {
                Layout.fillWidth: true
                visible: text !== ""
                text: "Cancelar"
                color: Theme.primary
                font.weight: Font.DemiBold
                font.pixelSize: Theme.textSmall
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Net.cancelPending()
                }
            }
        }

        onVisibleChanged: if (visible) pwInput.forceActiveFocus()
    }

    // ------------------------------------------------------------- redes
    Repeater {
        model: Net.networks

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property alias hovered: area.containsMouse

            Layout.fillWidth: true
            implicitHeight: 54
            radius: Theme.radius
            color: area.containsMouse ? Theme.surfaceHigh : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Icon {
                    text: root.signalIcon(row.modelData)
                    size: 22
                    color: row.modelData.connected ? Theme.primary : Theme.fg
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Txt {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        font.weight: Font.DemiBold
                    }
                    Txt {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.networkHint(row.modelData)
                        color: Theme.fgMuted
                        font.pixelSize: Theme.textSmall
                    }
                }

                Icon {
                    visible: Net.securityKind(row.modelData) !== "open"
                    text: "lock"
                    size: 15
                    color: Theme.fgMuted
                }

                Icon {
                    visible: row.modelData.connected === true
                    text: "check"
                    size: 18
                    color: Theme.primary
                }

                Txt {
                    text: Net.signalOf(row.modelData) + "%"
                    color: Theme.fgMuted
                    font.pixelSize: Theme.textSmall
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Net.select(row.modelData.name)
            }
        }
    }

    // Sin redes todavía
    Rectangle {
        Layout.fillWidth: true
        visible: Net.hasDevice && Net.wifiEnabled && Net.networks.length === 0
        implicitHeight: 84
        radius: Theme.radius
        color: Theme.surfaceHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6
            Icon {
                Layout.alignment: Qt.AlignHCenter
                text: "wifi_find"
                size: 26
                color: Theme.fgMuted
            }
            Txt {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Net.scanning ? "Buscando redes…" : "No hay redes a la vista"
                color: Theme.fgMuted
            }
        }
    }

    // ------------------------------------------------------ mensaje/error
    Rectangle {
        Layout.fillWidth: true
        visible: Net.status !== ""
        implicitHeight: msgCol.implicitHeight + 20
        radius: Theme.radius
        color: Net.statusError ? Theme.alpha(Theme.error, 0.14) : Theme.alpha(Theme.primary, 0.12)

        RowLayout {
            id: msgCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Icon {
                text: Net.statusError ? "error" : "check"
                size: 18
                color: Net.statusError ? Theme.error : Theme.primary
            }
            Txt {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Net.status
                color: Net.statusError ? Theme.error : Theme.fg
                font.pixelSize: Theme.textSmall
            }
        }
    }

    // --------------------------------------------------------- avanzado
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8

        IconButton {
            icon: "settings"
            onClicked: Quickshell.execDetached(["nm-connection-editor"])
        }
        Txt {
            Layout.fillWidth: true
            text: "Configuración avanzada de red"
            color: Theme.fgMuted
            font.pixelSize: Theme.textSmall
        }
    }

    // ------------------------------------------------------------- extras
    // El servicio manda la contraseña (por IPC o al conectar): el campo la
    // refleja y, si cambia la red pendiente, se limpia.
    Connections {
        target: Net
        function onPasswordChanged(): void {
            if (pwInput.text !== Net.password)
                pwInput.text = Net.password;
        }
        function onPendingSsidChanged(): void {
            if (Net.pendingSsid === "")
                pwInput.text = "";
            else
                pwInput.forceActiveFocus();
        }
    }

    function signalIcon(net: var): string {
        const s = Net.signalOf(net);
        if (s > 66)
            return "wifi";
        if (s > 33)
            return "wifi_2_bar";
        return "wifi_1_bar";
    }

    function networkHint(net: var): string {
        if (net.connected === true)
            return "Conectada";
        if (Net.tracked === net && Net.connecting)
            return "Conectando…";
        if (Net.pendingSsid === net.name)
            return "Escribe la contraseña";
        const kind = Net.securityKind(net);
        if (kind === "open")
            return "Abierta";
        if (kind === "enterprise")
            return "Red empresarial";
        if (kind === "wep")
            return "WEP (no compatible)";
        if (kind === "unknown")
            return "No se puede conectar desde aquí";
        return net.known === true ? "Guardada" : "Protegida";
    }
}
