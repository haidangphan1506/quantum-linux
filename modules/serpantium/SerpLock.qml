import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import qs.services
import qs.components

// Serpantium: pantalla de bloqueo. Primero solo la hora gigante sobre el fondo
// difuminado; al tocar una tecla o hacer clic aparecen tu foto y la contraseña.
// Misma lógica que la de siempre (Lock.qml): solo cambia cómo se ve.
Item {
    id: root

    required property var lock
    property bool preview: false
    signal closePreview
    anchors.fill: parent

    readonly property real km: Theme.animMult > 0 ? Theme.animMult : 0.001
    property bool asking: false                   // ya se ve la contraseña (al tocar una tecla)
    readonly property var battery: UPower.displayDevice
    readonly property string home: Quickshell.env("HOME") ?? ""

    property real appear: 0
    NumberAnimation on appear { from: 0; to: 1; duration: 900 * root.km; easing.type: Easing.OutCubic }
    property real ask: asking ? 1 : 0
    Behavior on ask { NumberAnimation { duration: 420 * root.km; easing.type: Easing.OutBack } }
    property real out: lock.leaving ? 1 : 0
    Behavior on out { NumberAnimation { duration: 600 * root.km; easing.type: Easing.InOutCubic } }

    SystemClock { id: clk; precision: SystemClock.Seconds }

    // fondo: el tuyo, difuminado y teñido de rosa
    Rectangle { anchors.fill: parent; color: Serp.bg }
    Image {
        id: wall
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: Settings.appearance.wallpaper && Settings.appearance.wallpaper !== "quantum:live" ? "file://" + Settings.appearance.wallpaper : "file://" + Serp.wallpaper
        sourceSize: Qt.size(1280, 720)
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true; blur: 0.5 + 0.5 * root.ask; blurMax: 64
        brightness: -0.08 - 0.1 * root.ask
        opacity: root.appear * (1 - root.out)
        scale: 1.06 - 0.06 * root.appear + 0.05 * root.out
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.96, 0.65, 0.79, 0.06) }

    // halos, como en los paneles
    Repeater {
        model: 2
        Rectangle {
            required property int index
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: index === 0 ? -parent.width * 0.12 : parent.width * 0.18
            anchors.verticalCenterOffset: index === 0 ? -parent.height * 0.05 : parent.height * 0.1
            width: parent.height * (index === 0 ? 1.1 : 0.8); height: width; radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.025)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.05)
            opacity: root.appear * (1 - root.out)
            rotation: clk.seconds * 6
        }
    }

    // la hora
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.36 - root.ask * parent.height * 0.14
        spacing: 6
        opacity: root.appear * (1 - root.out)
        scale: 1 - 0.35 * root.ask
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            Text { text: Qt.formatTime(clk.date, "HH"); font.family: Serp.font; font.pixelSize: 150; font.weight: Font.Bold; color: Qt.rgba(1, 1, 1, 0.92) }
            Text {
                text: ":"; font.family: Serp.font; font.pixelSize: 150; font.weight: Font.Bold; color: Serp.pink
                opacity: clk.seconds % 2 === 0 ? 1 : 0.25
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            Text { text: Qt.formatTime(clk.date, "mm"); font.family: Serp.font; font.pixelSize: 150; font.weight: Font.Bold; color: Qt.rgba(1, 1, 1, 0.92) }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Serp.cap(Qt.locale("es_ES").toString(clk.date, "dddd d 'de' MMMM"))
            font.family: Serp.font; font.pixelSize: 20; color: Qt.rgba(1, 1, 1, 0.75)
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.66
        text: "Presiona una tecla para desbloquear"
        font.family: Serp.font; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.6)
        opacity: root.appear * (1 - root.ask) * (1 - root.out)
    }

    // foto + contraseña
    Row {
        id: login
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.52
        spacing: 22
        opacity: root.ask * (1 - root.out)
        visible: opacity > 0.01
        transform: Translate { y: (1 - root.ask) * 40 }

        ClippingRectangle {
            id: face
            width: 96; height: 96; radius: 48
            color: Serp.cardHi
            border.width: 3; border.color: root.lock.error ? "#FF6B7A" : root.lock.success ? "#7BE0A4" : Serp.pink
            property int si: 0
            readonly property var sources: ["file://" + root.home + "/.face", "file:///var/lib/AccountsService/icons/" + (Quickshell.env("USER") ?? "")]
            Image {
                anchors.fill: parent
                source: face.si < face.sources.length ? face.sources[face.si] : ""
                fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(192, 192)
                onStatusChanged: if (status === Image.Error) Qt.callLater(() => face.si++)
            }
            Icon { anchors.centerIn: parent; visible: face.si >= face.sources.length; text: "person"; size: 48; fill: 1; color: Serp.pink }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text { text: Quickshell.env("USER") ?? ""; font.family: Serp.font; font.pixelSize: 18; font.weight: Font.Bold; color: "white" }
            Rectangle {
                id: field
                width: 300; height: 44; radius: 22
                color: Qt.rgba(0.09, 0.07, 0.09, 0.75)
                border.width: 1; border.color: root.lock.error ? "#FF6B7A" : input.activeFocus ? Qt.rgba(0.96, 0.65, 0.79, 0.6) : Qt.rgba(1, 1, 1, 0.12)
                property real shake: 0
                transform: Translate { x: Math.sin(field.shake * Math.PI * 6) * 10 * (1 - field.shake) }
                NumberAnimation { id: shakeAnim; target: field; property: "shake"; from: 0; to: 1; duration: 450 }
                Connections { target: root.lock; function onErrorChanged() { if (root.lock.error) shakeAnim.restart(); } }

                TextInput {
                    id: input
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 44
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    font.family: Serp.font; font.pixelSize: 16; font.letterSpacing: 3
                    color: Serp.pink
                    selectionColor: "transparent"
                    focus: true
                    enabled: !root.lock.busy && !root.lock.leaving
                    text: root.lock.password
                    onTextChanged: { root.lock.password = text; if (text.length) root.asking = true; }
                    onAccepted: root.preview ? root.closePreview() : root.lock.tryUnlock()
                    Keys.onPressed: e => { root.asking = true; }
                    Keys.onEscapePressed: { if (root.preview) root.closePreview(); else if (!text.length) root.asking = false; }
                    Component.onCompleted: forceActiveFocus()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: root.lock.busy ? "Verificando..." : root.lock.error || "Contraseña"
                        font.family: Serp.font; font.pixelSize: 13; font.letterSpacing: 0
                        color: root.lock.error ? "#FF8A96" : Serp.muted
                    }
                }
                MouseArea {
                    anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; cursorShape: Qt.PointingHandCursor
                    onClicked: root.preview ? root.closePreview() : root.lock.tryUnlock()
                    Rectangle { anchors.fill: parent; radius: 17; color: Serp.pink }
                    Icon { anchors.centerIn: parent; text: root.lock.success ? "lock_open" : "arrow_forward"; size: 18; color: Serp.pinkFg }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: { root.asking = true; input.forceActiveFocus(); }
    }

    // abajo: estado
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 30
        spacing: 22
        opacity: 0.8 * root.appear * (1 - root.out)
        component St: Row {
            property string icon: ""
            property string text: ""
            spacing: 6
            Icon { anchors.verticalCenter: parent.verticalCenter; text: parent.icon; size: 16; fill: 1; color: "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.text; font.family: Serp.font; font.pixelSize: 12; color: "white" }
        }
        St { icon: Net.icon; text: Net.online ? Net.label : "Sin red" }
        St { visible: root.battery?.isLaptopBattery ?? false; icon: "battery_full"; text: Math.round((root.battery?.percentage ?? 0) * 100) + "%" }
        St { visible: Weather.ready; icon: Weather.icon; text: Math.round(Weather.temp) + "°C" }
    }

    // abajo a la derecha: apagar, reiniciar, suspender
    Row {
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 26
        spacing: 8
        opacity: root.appear * (1 - root.out)
        visible: !root.preview
        Repeater {
            model: [{ i: "bedtime", c: ["systemctl", "suspend"] }, { i: "restart_alt", c: ["systemctl", "reboot"] }, { i: "power_settings_new", c: ["systemctl", "poweroff"] }]
            MouseArea {
                id: pb
                required property var modelData
                width: 38; height: 38; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(modelData.c)
                Rectangle { anchors.fill: parent; radius: 19; color: pb.containsMouse ? Serp.pink : Qt.rgba(0.09, 0.07, 0.09, 0.6); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1) }
                Icon { anchors.centerIn: parent; text: pb.modelData.i; size: 18; color: pb.containsMouse ? Serp.pinkFg : "white" }
            }
        }
    }
}
