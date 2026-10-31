import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Bluetooth: reemplaza a blueman-manager. Adaptador (encendido, nombre,
// visibilidad), dispositivos emparejados (conectar, confiar, bloquear,
// renombrar, enviar archivos, olvidar) y búsqueda de dispositivos nuevos.
ColumnLayout {
    id: page

    spacing: 16
    readonly property var ad: Bt.adapter
    // dirección del dispositivo abierto (detalles)
    property string expanded: ""

    // La búsqueda corre mientras esta página está abierta
    Component.onCompleted: Bt.startScan()
    Component.onDestruction: if (!Shell.btPage) Bt.stopScan()

    // Campo de texto con botón «Guardar»
    component NameField: RowLayout {
        id: nf
        property string value: ""
        property string placeholder: ""
        signal saved(string text)
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40; radius: 20
            color: Theme.surfaceHigh
            border.width: input.activeFocus ? 2 : 1
            border.color: input.activeFocus ? Theme.primary : Theme.alpha(Theme.fg, 0.1)
            Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "edit"; size: 18; color: Theme.fgMuted }
            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 42; anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.font; font.pixelSize: Theme.textNormal
                color: Theme.fg
                selectionColor: Theme.primary
                selectedTextColor: Theme.primaryFg
                clip: true
                text: nf.value
                onAccepted: if (text.trim() !== "" && text !== nf.value) nf.saved(text.trim())
                Txt { anchors.verticalCenter: parent.verticalCenter; visible: !input.text && !input.activeFocus; text: nf.placeholder; color: Theme.fgMuted }
            }
        }
        PillButton {
            text: I18n.t("Guardar")
            enabled_: input.text.trim() !== "" && input.text !== nf.value
            onClicked: nf.saved(input.text.trim())
        }
    }

    // ------------------------------------------------------------ adaptador
    Group {
        title: I18n.t("Este equipo")
        help: !Bt.available ? I18n.t("No se encontró un adaptador Bluetooth") : I18n.t("Enciende el Bluetooth y elige cómo te ven los demás dispositivos.")
        icon: "bluetooth"

        OptionRow {
            visible: Bt.available
            title: "Bluetooth"
            help: Bt.enabled ? I18n.t("Encendido") : I18n.t("Apagado")
            icon: Bt.enabled ? "bluetooth" : "bluetooth_disabled"
            Toggle { checked: Bt.enabled; onToggled: c => { if (page.ad) page.ad.enabled = c; } }
        }

        OptionRow {
            visible: Bt.enabled
            title: I18n.t("Visible para otros")
            help: page.ad?.discoverable
                ? I18n.t("Otros dispositivos pueden encontrar este equipo como «") + (page.ad?.name ?? "") + "»"
                : I18n.t("Solo los dispositivos emparejados ven este equipo")
            icon: "visibility"
            Toggle { checked: page.ad?.discoverable ?? false; onToggled: c => page.ad.discoverable = c }
        }

        OptionRow {
            visible: Bt.enabled && (page.ad?.discoverable ?? false)
            title: I18n.t("Tiempo visible")
            help: I18n.t("Después se oculta solo.")
            icon: "timer"
            Segmented {
                options: [{ v: 120, t: "2 min" }, { v: 300, t: "5 min" }, { v: 0, t: I18n.t("Siempre") }]
                value: page.ad?.discoverableTimeout ?? 0
                onPicked: v => page.ad.discoverableTimeout = v
            }
        }

        OptionRow {
            visible: Bt.enabled
            advanced: true
            title: I18n.t("Permitir emparejar")
            help: I18n.t("Si se apaga, ningún dispositivo nuevo puede emparejarse.")
            icon: "link"
            Toggle { checked: page.ad?.pairable ?? false; onToggled: c => page.ad.pairable = c }
        }

        ColumnLayout {
            visible: Bt.available
            Layout.fillWidth: true
            spacing: 6
            Txt { text: I18n.t("Nombre del equipo"); font.weight: Font.DemiBold }
            NameField {
                Layout.fillWidth: true
                value: page.ad?.name ?? ""
                placeholder: I18n.t("Nombre que ven los demás")
                onSaved: t => Quickshell.execDetached(["busctl", "set-property", "org.bluez", page.ad.dbusPath, "org.bluez.Adapter1", "Alias", "s", t])
            }
        }
    }

    // ------------------------------------------------------ dispositivos
    component DeviceCard: Rectangle {
        id: card
        required property var modelData
        readonly property var dev: modelData
        readonly property bool isPaired: dev.paired || dev.bonded
        readonly property bool open: isPaired && page.expanded === dev.address

        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 16
        radius: Theme.radius
        color: open ? Theme.surfaceHigh : head.containsMouse ? Theme.alpha(Theme.fg, 0.05) : "transparent"
        border.width: open ? 1 : 0
        border.color: Theme.alpha(Theme.fg, 0.08)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        ColumnLayout {
            id: col
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 8
            spacing: 10

            // fila principal
            Item {
                Layout.fillWidth: true
                implicitHeight: 46

                MouseArea {
                    id: head
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.isPaired ? page.expanded = (card.open ? "" : card.dev.address) : Bt.activate(card.dev)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    spacing: 12

                    Rectangle {
                        implicitWidth: 40; implicitHeight: 40; radius: 12
                        color: card.dev.connected ? Theme.alpha(Theme.primary, 0.18) : Theme.surfaceHighest
                        Icon {
                            anchors.centerIn: parent
                            text: Bt.deviceIcon(card.dev)
                            size: 22
                            color: card.dev.connected ? Theme.primary : Theme.fg
                            SequentialAnimation on opacity {
                                running: Bt.busy(card.dev)
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Txt { Layout.fillWidth: true; text: card.dev.name; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Txt {
                            Layout.fillWidth: true
                            text: Bt.hint(card.dev) + (card.dev.blocked ? " · " + I18n.t("Bloqueado") : card.dev.trusted && card.isPaired ? " · " + I18n.t("De confianza") : "")
                            color: card.dev.connected ? Theme.primary : Theme.fgMuted
                            font.pixelSize: Theme.textSmall
                        }
                    }
                    // batería
                    RowLayout {
                        visible: card.dev.batteryAvailable
                        spacing: 2
                        Icon { text: card.dev.battery > 0.8 ? "battery_full" : card.dev.battery > 0.3 ? "battery_4_bar" : "battery_1_bar"; size: 18; color: Theme.fgMuted }
                        Txt { text: Math.round(card.dev.battery * 100) + "%"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                    }
                    PillButton {
                        visible: !card.isPaired || !card.open
                        text: !card.isPaired ? I18n.t("Emparejar") : card.dev.connected ? I18n.t("Desconectar") : I18n.t("Conectar")
                        primary: !card.dev.connected
                        enabled_: !Bt.busy(card.dev) && !card.dev.blocked
                        onClicked: Bt.activate(card.dev)
                    }
                    Icon {
                        visible: card.isPaired
                        text: card.open ? "expand_less" : "expand_more"
                        size: 22
                        color: Theme.fgMuted
                    }
                }
            }

            // detalles (solo emparejados)
            ColumnLayout {
                visible: card.open
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 6
                spacing: 12

                Txt {
                    text: I18n.t("Dirección: ") + card.dev.address + (card.dev.icon ? "  ·  " + card.dev.icon : "")
                    color: Theme.fgMuted
                    font.pixelSize: Theme.textSmall
                }

                NameField {
                    Layout.fillWidth: true
                    value: card.dev.name
                    placeholder: card.dev.deviceName
                    onSaved: t => card.dev.name = t
                }

                OptionRow {
                    title: I18n.t("De confianza")
                    help: I18n.t("Se conecta solo, sin pedir permiso.")
                    Toggle { checked: card.dev.trusted; onToggled: c => card.dev.trusted = c }
                }
                OptionRow {
                    title: I18n.t("Bloquear")
                    help: I18n.t("Rechaza cualquier conexión de este dispositivo.")
                    Toggle { checked: card.dev.blocked; onToggled: c => card.dev.blocked = c }
                }
                OptionRow {
                    advanced: true
                    title: I18n.t("Puede despertar el equipo")
                    help: I18n.t("Para teclados y mouse: salir de la suspensión al usarlo.")
                    Toggle { checked: card.dev.wakeAllowed; onToggled: c => card.dev.wakeAllowed = c }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PillButton {
                        text: card.dev.connected ? I18n.t("Desconectar") : I18n.t("Conectar")
                        icon: card.dev.connected ? "link_off" : "link"
                        primary: !card.dev.connected
                        enabled_: !Bt.busy(card.dev) && !card.dev.blocked
                        onClicked: Bt.activate(card.dev)
                    }
                    PillButton {
                        visible: card.dev.connected
                        text: I18n.t("Enviar archivo")
                        icon: "upload_file"
                        onClicked: Quickshell.execDetached(["blueman-sendto", "--device=" + card.dev.address])
                    }
                    Item { Layout.fillWidth: true }
                    PillButton {
                        text: I18n.t("Olvidar")
                        icon: "delete"
                        danger: true
                        onClicked: { page.expanded = ""; Bt.forget(card.dev); }
                    }
                }
            }
        }
    }

    Group {
        visible: Bt.enabled
        title: I18n.t("Mis dispositivos")
        help: Bt.paired.length === 0 ? I18n.t("Todavía no hay dispositivos emparejados.") : I18n.t("Toca un dispositivo para ver sus opciones.")
        icon: "devices"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: Bt.paired
                delegate: DeviceCard {}
            }
        }
    }

    Group {
        visible: Bt.enabled
        title: I18n.t("Otros dispositivos")
        help: Bt.discovering ? I18n.t("Buscando dispositivos… Pon el dispositivo en modo de emparejamiento.") : I18n.t("Pulsa buscar para encontrar dispositivos cercanos.")
        icon: "bluetooth_searching"

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PillButton {
                text: Bt.discovering ? I18n.t("Detener") : I18n.t("Buscar")
                icon: Bt.discovering ? "stop" : "search"
                primary: !Bt.discovering
                onClicked: Bt.discovering ? Bt.stopScan() : Bt.startScan()
            }
            Txt {
                Layout.fillWidth: true
                text: Bt.nearby.length + I18n.t(" encontrados")
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: Bt.nearby
                delegate: DeviceCard {}
            }
        }
    }

    // mensaje de la última acción
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
            Icon { text: Bt.statusError ? "error" : "check"; size: 18; color: Bt.statusError ? Theme.error : Theme.primary }
            Txt { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Bt.status; color: Bt.statusError ? Theme.error : Theme.fg; font.pixelSize: Theme.textSmall }
        }
    }

    // ------------------------------------------------------------ avanzado
    Group {
        advanced: true
        title: I18n.t("Más herramientas")
        help: I18n.t("Para lo que no está aquí: perfiles de audio, red por Bluetooth, etc.")
        icon: "build"
        RowLayout {
            spacing: 8
            PillButton { text: "Blueman"; icon: "open_in_new"; onClicked: Quickshell.execDetached(["blueman-manager"]) }
            PillButton { text: I18n.t("Enviar archivo"); icon: "upload_file"; onClicked: Quickshell.execDetached(["blueman-sendto"]) }
        }
    }
}
