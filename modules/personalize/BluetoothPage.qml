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
    // La búsqueda dura 15 s y se detiene sola (el spinner se detiene con ella)
    function scan(): void { Bt.startScan(); scanTimer.restart(); }
    Timer { id: scanTimer; interval: 15000; onTriggered: Bt.stopScan() }
    Connections {
        target: Bt
        function onEnabledChanged(): void { if (Bt.enabled) scanTimer.restart(); else scanTimer.stop(); }
    }

    Component.onCompleted: {
        page.scan();
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
    Group {
        OptionRow {
            visible: Bt.available
            title: "Bluetooth"
            help: I18n.t("Conecta accesorios como auriculares, teclados, mouse y mandos para escuchar música, escribir o jugar.")
            icon: "bluetooth"
            iconColor: "#007AFF"
            Toggle { checked: Bt.enabled; onToggled: c => { if (page.ad) page.ad.enabled = c; } }
        }
        OptionRow {
            visible: !Bt.available
            title: I18n.t("No se encontró un adaptador Bluetooth")
            icon: "bluetooth_disabled"
            iconColor: "#8E8E93"
        }
        // nota de visibilidad dentro del recuadro, como en macOS
        Item {
            visible: Bt.available && Bt.enabled
            Layout.fillWidth: true
            implicitHeight: visNote.implicitHeight + 20
            Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.fg, 0.08) }
            Txt {
                id: visNote
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("Este equipo es visible como «") + (page.ad?.name ?? "") + I18n.t("» mientras los ajustes de Bluetooth están abiertos.")
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }
    }

    // ------------------------------------------------------ dispositivos
    component DeviceCard: ColumnLayout {
        id: card
        required property var modelData
        required property int index
        readonly property var dev: modelData
        readonly property bool isPaired: dev.paired || dev.bonded
        readonly property bool open: isPaired && page.expanded === dev.address

        Layout.fillWidth: true
        spacing: 0
        Rectangle { visible: card.index > 0; Layout.fillWidth: true; implicitHeight: 1; color: Theme.alpha(Theme.fg, 0.08) }

        // fila principal
        Item {
            Layout.fillWidth: true
            implicitHeight: 56

            HoverHandler { id: hov }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Bt.activate(card.dev)
            }

            RowLayout {
                anchors.fill: parent
                spacing: 12

                Item {
                    implicitWidth: 34; implicitHeight: 34
                    Icon {
                        anchors.centerIn: parent
                        text: Bt.deviceIcon(card.dev)
                        size: 30
                        fill: 1
                        color: card.dev.connected ? Theme.fg : Theme.alpha(Theme.fg, 0.75)
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
                    RowLayout {
                        visible: card.isPaired
                        Layout.fillWidth: true
                        spacing: 4
                        Txt {
                            text: (card.dev.connected ? I18n.t("Conectado") : Bt.busy(card.dev) ? Bt.hint(card.dev) : I18n.t("No conectado")) + (card.dev.blocked ? " · " + I18n.t("Bloqueado") : "")
                            color: Theme.fgMuted
                            font.pixelSize: Theme.textSmall
                        }
                        Txt { visible: card.dev.connected && card.dev.batteryAvailable; text: "–"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                        Icon {
                            visible: card.dev.connected && card.dev.batteryAvailable
                            text: card.dev.battery > 0.8 ? "battery_full" : card.dev.battery > 0.3 ? "battery_4_bar" : "battery_1_bar"
                            size: 16; color: Theme.fgMuted
                        }
                        Txt { visible: card.dev.connected && card.dev.batteryAvailable; text: Math.round(card.dev.battery * 100) + "%"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                        Item { Layout.fillWidth: true }
                    }
                }
                PillButton {
                    implicitHeight: 28
                    visible: hov.hovered || Bt.busy(card.dev)
                    text: !card.isPaired ? I18n.t("Conectar") : card.dev.connected ? I18n.t("Desconectar") : I18n.t("Conectar")
                    enabled_: !Bt.busy(card.dev) && !card.dev.blocked
                    onClicked: Bt.activate(card.dev)
                }
                // botón (i) de detalles
                Item {
                    visible: card.isPaired
                    implicitWidth: 28; implicitHeight: 28
                    Icon { anchors.centerIn: parent; text: card.open ? "expand_less" : "info"; size: 22; color: Theme.fgMuted }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.expanded = card.open ? "" : card.dev.address
                    }
                }
            }
        }

        // detalles (solo emparejados)
        ColumnLayout {
            visible: card.open
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 0

            OptionRow {
                title: I18n.t("Nombre")
                NameField {
                    implicitWidth: 300
                    value: card.dev.name
                    placeholder: card.dev.deviceName
                    onSaved: t => card.dev.name = t
                }
            }
            OptionRow {
                title: I18n.t("Dirección")
                Txt { text: card.dev.address + (card.dev.icon ? "  ·  " + card.dev.icon : ""); color: Theme.fgMuted }
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
                title: ""
                RowLayout {
                    spacing: 8
                    PillButton {
                        visible: card.dev.connected
                        text: I18n.t("Enviar archivo")
                        icon: "upload_file"
                        implicitHeight: 28
                        onClicked: Quickshell.execDetached(["blueman-sendto", "--device=" + card.dev.address])
                    }
                    PillButton {
                        text: I18n.t("Olvidar este dispositivo…")
                        icon: "delete"
                        danger: true
                        implicitHeight: 28
                        onClicked: { page.expanded = ""; Bt.forget(card.dev); }
                    }
                }
            }
        }
    }

    Group {
        visible: Bt.enabled
        title: I18n.t("Mis dispositivos")
        Repeater {
            model: Bt.paired
            delegate: DeviceCard {}
        }
        OptionRow {
            visible: Bt.paired.length === 0
            title: I18n.t("Todavía no hay dispositivos emparejados.")
            dim: true
        }
    }

    ColumnLayout {
        visible: Bt.enabled
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.leftMargin: 4
            Layout.rightMargin: 8
            Txt { Layout.fillWidth: true; text: I18n.t("Dispositivos cercanos"); font.weight: Font.Bold }
            // indicador de búsqueda (clic: detener / buscar)
            Item {
                implicitWidth: Bt.discovering ? 24 : refreshTxt.implicitWidth; implicitHeight: 24
                Txt {
                    id: refreshTxt
                    visible: !Bt.discovering
                    anchors.centerIn: parent
                    text: I18n.t("Actualizar lista")
                    color: Theme.primary
                    font.pixelSize: Theme.textSmall
                }
                // spinner de rayos como en macOS
                Item {
                    id: spin
                    visible: Bt.discovering
                    anchors.centerIn: parent
                    width: 20; height: 20
                    property int step: 0
                    Timer { interval: 90; repeat: true; running: Bt.discovering; onTriggered: spin.step = (spin.step + 1) % 8 }
                    Repeater {
                        model: 8
                        Rectangle {
                            required property int index
                            width: 2.5; height: 6; radius: 1.2
                            x: 10 - width / 2; y: 1
                            transform: Rotation { origin.x: 1.25; origin.y: 9; angle: index * 45 }
                            color: Theme.fgMuted
                            opacity: Bt.discovering ? 0.2 + 0.8 * (((spin.step - index) % 8 + 8) % 8 === 0 ? 1 : 1 - (((spin.step - index) % 8 + 8) % 8) / 8) : 0.4
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (Bt.discovering) { Bt.stopScan(); scanTimer.stop(); } else page.scan(); }
                }
            }
        }

        Group {
            Layout.topMargin: 0
            Repeater {
                model: Bt.nearby
                delegate: DeviceCard {}
            }
            OptionRow {
                visible: Bt.nearby.length === 0
                title: Bt.discovering ? I18n.t("Buscando dispositivos… Pon el dispositivo en modo de emparejamiento.") : I18n.t("No hay dispositivos cercanos")
                dim: true
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
}
