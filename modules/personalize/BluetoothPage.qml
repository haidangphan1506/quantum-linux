import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Bluetooth como en macOS: encabezado, interruptor (el equipo es visible mientras esta
// página está abierta), «Mis dispositivos» con detalles al tocar (conectar, confiar,
// bloquear, renombrar, enviar archivos, olvidar) y «Dispositivos cercanos».
ColumnLayout {
    id: page

    spacing: 16
    readonly property var ad: Bt.adapter
    // dirección del dispositivo abierto (detalles)
    property string expanded: ""

    // Como en macOS: mientras la página está abierta se busca y el equipo es visible
    property bool wasDiscoverable: false
    Component.onCompleted: {
        Bt.startScan();
        if (ad && Bt.enabled) { wasDiscoverable = ad.discoverable; ad.discoverable = true; }
    }
    Component.onDestruction: {
        if (!Shell.btPage) Bt.stopScan();
        if (ad && !wasDiscoverable) ad.discoverable = false;
    }

    // Campo de texto con botón «Guardar»
    component NameField: RowLayout {
        id: nf
        property string value: ""
        property string placeholder: ""
        signal saved(string text)
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28; radius: 7
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : "white"
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
            implicitHeight: 28
            text: I18n.t("Guardar")
            enabled_: input.text.trim() !== "" && input.text !== nf.value
            onClicked: nf.saved(input.text.trim())
        }
    }

    // ------------------------------------------------------------ adaptador
    PageHero {
        icon: "bluetooth"
        color: "#007AFF"
        title: "Bluetooth"
        text: I18n.t("Conecta accesorios como auriculares, teclados, mouse y mandos para escuchar música, escribir o jugar.")
    }

    Group {
        help: !Bt.available ? I18n.t("No se encontró un adaptador Bluetooth")
            : Bt.enabled ? I18n.t("Este equipo es visible como «") + (page.ad?.name ?? "") + I18n.t("» mientras los ajustes de Bluetooth están abiertos.") : ""
        OptionRow {
            visible: Bt.available
            title: "Bluetooth"
            Toggle { checked: Bt.enabled; onToggled: c => { if (page.ad) page.ad.enabled = c; } }
        }
    }

    Group {
        visible: Bt.available && Bt.enabled
        advanced: true
        title: I18n.t("Este equipo")
        OptionRow {
            title: I18n.t("Nombre del equipo")
            NameField {
                implicitWidth: 300
                value: page.ad?.name ?? ""
                placeholder: I18n.t("Nombre que ven los demás")
                onSaved: t => Quickshell.execDetached(["busctl", "set-property", "org.bluez", page.ad.dbusPath, "org.bluez.Adapter1", "Alias", "s", t])
            }
        }
        OptionRow {
            title: I18n.t("Permitir emparejar")
            help: I18n.t("Si se apaga, ningún dispositivo nuevo puede emparejarse.")
            Toggle { checked: page.ad?.pairable ?? false; onToggled: c => page.ad.pairable = c }
        }
    }

    // ------------------------------------------------------ dispositivos
    component DeviceCard: Rectangle {
        id: card
        required property var modelData
        readonly property var dev: modelData
        readonly property bool isPaired: dev.paired || dev.bonded
        readonly property bool open: isPaired && page.expanded === dev.address

        required property int index
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 8
        color: "transparent"
        // línea entre filas, como las listas de macOS
        Rectangle { visible: card.index > 0; width: parent.width; height: 1; color: Theme.alpha(Theme.fg, 0.08) }

        ColumnLayout {
            id: col
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.topMargin: 4
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
                    spacing: 12

                    Rectangle {
                        implicitWidth: 32; implicitHeight: 32; radius: 16
                        color: card.dev.connected ? "#007AFF" : Theme.alpha(Theme.fg, 0.1)
                        Icon {
                            anchors.centerIn: parent
                            text: Bt.deviceIcon(card.dev)
                            size: 18
                            color: card.dev.connected ? "white" : Theme.fg
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
                        Txt { Layout.fillWidth: true; text: card.dev.name; elide: Text.ElideRight }
                        Txt {
                            Layout.fillWidth: true
                            text: Bt.hint(card.dev) + (card.dev.blocked ? " · " + I18n.t("Bloqueado") : card.dev.trusted && card.isPaired ? " · " + I18n.t("De confianza") : "")
                            color: Theme.fgMuted
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
                        implicitHeight: 28
                        visible: !card.isPaired || !card.open
                        text: !card.isPaired ? I18n.t("Emparejar") : card.dev.connected ? I18n.t("Desconectar") : I18n.t("Conectar")
                        primary: !card.dev.connected
                        enabled_: !Bt.busy(card.dev) && !card.dev.blocked
                        onClicked: Bt.activate(card.dev)
                    }
                    Icon {
                        visible: card.isPaired
                        text: card.open ? "expand_less" : "info"
                        size: 20
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
            spacing: 0
            Repeater {
                model: Bt.paired
                delegate: DeviceCard {}
            }
        }
    }

    Group {
        visible: Bt.enabled
        title: I18n.t("Dispositivos cercanos")
        help: Bt.discovering ? I18n.t("Buscando dispositivos… Pon el dispositivo en modo de emparejamiento.") : I18n.t("Pulsa buscar para encontrar dispositivos cercanos.")
        icon: "bluetooth_searching"

        OptionRow {
            title: Bt.nearby.length + I18n.t(" encontrados")
            PillButton {
                implicitHeight: 28
                text: Bt.discovering ? I18n.t("Detener") : I18n.t("Buscar")
                icon: Bt.discovering ? "stop" : "search"
                onClicked: Bt.discovering ? Bt.stopScan() : Bt.startScan()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
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
