import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Página «Bluetooth» del centro de control: dispositivos emparejados,
// búsqueda de dispositivos cercanos y emparejamiento (igual que WifiView).
ColumnLayout {
    id: root

    spacing: 12

    // ------------------------------------------------------------ encabezado
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        IconButton {
            icon: "chevron_left"
            onClicked: Shell.btPage = false
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Txt { text: "Bluetooth"; font.weight: Font.Bold; font.pixelSize: Theme.textLarge }
            Txt { Layout.fillWidth: true; text: root.subtitle; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
        }
        IconButton {
            icon: Bt.enabled ? "bluetooth" : "bluetooth_disabled"
            active: Bt.enabled
            onClicked: Bt.toggle()
        }
        IconButton {
            icon: Bt.discovering ? "bluetooth_searching" : "refresh"
            active: Bt.discovering
            onClicked: Bt.discovering ? Bt.stopScan() : Bt.startScan()
        }
    }

    readonly property string subtitle: {
        if (!Bt.available)
            return I18n.t("Este equipo no tiene adaptador Bluetooth");
        if (!Bt.enabled)
            return I18n.t("El Bluetooth está apagado");
        if (Bt.discovering)
            return I18n.t("Buscando dispositivos…");
        if (Bt.connected.length > 0)
            return I18n.t("Conectado a ") + Bt.connected[0].name;
        return I18n.t("Encendido");
    }

    // -------------------------------------------------------------- estado
    Rectangle {
        Layout.fillWidth: true
        visible: !Bt.available || !Bt.enabled
        implicitHeight: 96
        radius: Theme.radius
        color: Theme.surfaceHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Icon {
                Layout.alignment: Qt.AlignHCenter
                text: "bluetooth_disabled"
                size: 28
                color: Theme.fgMuted
            }
            Txt {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: !Bt.available ? I18n.t("No se encontró un adaptador Bluetooth") : I18n.t("El Bluetooth está apagado")
                font.weight: Font.DemiBold
            }
            IconButton {
                Layout.alignment: Qt.AlignHCenter
                visible: Bt.available && !Bt.enabled
                icon: "power_settings_new"
                onClicked: Bt.toggle()
            }
        }
    }

    // ------------------------------------------------------- dispositivos
    component Section: Txt {
        Layout.fillWidth: true
        Layout.topMargin: 2
        font.weight: Font.DemiBold
        font.pixelSize: Theme.textSmall
        color: Theme.fgMuted
    }

    component DeviceRow: Rectangle {
        id: row
        required property var modelData
        readonly property var dev: modelData
        readonly property bool busy: Bt.busy(dev)

        Layout.fillWidth: true
        implicitHeight: 54
        radius: Theme.radius
        color: area.containsMouse ? Theme.surfaceHigh : "transparent"

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Bt.activate(row.dev)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 6
            spacing: 12

            Icon {
                text: Bt.deviceIcon(row.dev)
                size: 22
                color: row.dev.connected ? Theme.primary : Theme.fg
                opacity: row.busy ? 0.5 : 1
                SequentialAnimation on opacity {
                    running: row.busy
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Txt {
                    Layout.fillWidth: true
                    text: row.dev.name
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Txt {
                    Layout.fillWidth: true
                    text: Bt.hint(row.dev)
                    color: row.dev.connected ? Theme.primary : Theme.fgMuted
                    font.pixelSize: Theme.textSmall
                }
            }

            Icon {
                visible: row.dev.connected
                text: "check"
                size: 18
                color: Theme.primary
            }

            // Olvidar (solo emparejados)
            IconButton {
                visible: row.dev.paired || row.dev.bonded
                icon: "delete"
                iconSize: 18
                onClicked: Bt.forget(row.dev)
            }
        }
    }

    Section {
        visible: Bt.enabled && Bt.paired.length > 0
        text: I18n.t("Mis dispositivos")
    }
    Repeater {
        model: Bt.enabled ? Bt.paired : []
        delegate: DeviceRow {}
    }

    Section {
        visible: Bt.enabled
        text: I18n.t("Otros dispositivos")
    }
    Repeater {
        model: Bt.enabled ? Bt.nearby : []
        delegate: DeviceRow {}
    }

    // Sin dispositivos nuevos todavía
    Rectangle {
        Layout.fillWidth: true
        visible: Bt.enabled && Bt.nearby.length === 0
        implicitHeight: 84
        radius: Theme.radius
        color: Theme.surfaceHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6
            Icon {
                Layout.alignment: Qt.AlignHCenter
                text: "bluetooth_searching"
                size: 26
                color: Theme.fgMuted
            }
            Txt {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Bt.discovering ? I18n.t("Buscando dispositivos… Pon el dispositivo en modo de emparejamiento.") : I18n.t("Pulsa actualizar para buscar dispositivos")
                color: Theme.fgMuted
            }
        }
    }

    // ------------------------------------------------------ mensaje/error
    Rectangle {
        Layout.fillWidth: true
        visible: Bt.status !== ""
        implicitHeight: msgRow.implicitHeight + 20
        radius: Theme.radius
        color: Bt.statusError ? Theme.alpha(Theme.error, 0.14) : Theme.alpha(Theme.primary, 0.12)

        RowLayout {
            id: msgRow
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Icon {
                text: Bt.statusError ? "error" : "check"
                size: 18
                color: Bt.statusError ? Theme.error : Theme.primary
            }
            Txt {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Bt.status
                color: Bt.statusError ? Theme.error : Theme.fg
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
            onClicked: Shell.personalizePage("bluetooth")
        }
        Txt {
            Layout.fillWidth: true
            text: I18n.t("Configuración avanzada de Bluetooth")
            color: Theme.fgMuted
            font.pixelSize: Theme.textSmall
        }
    }
}
