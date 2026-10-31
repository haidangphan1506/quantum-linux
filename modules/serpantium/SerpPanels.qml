import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.services
import qs.components

// Serpantium: los paneles que bajan desde la barra.
//  - Música (izquierda): disco girando, avance y controles.
//  - Hora (centro): reloj grande, calendario y clima.
//  - Control (derecha): batería o volumen en un anillo, deslizadores, Wi-Fi, Bluetooth,
//    energía, notificaciones y botones de bloquear / suspender / reiniciar / apagar.
PanelWindow {
    id: win

    readonly property string panel: Serp.panel
    property string shown: ""            // el panel que se ve mientras se cierra
    property real k: 0                   // 0 = cerrado, 1 = abierto
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false

    visible: panel !== "" || k > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quantum-serpantium"
    WlrLayershell.keyboardFocus: panel !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal      // empieza debajo de la barra
    color: "transparent"

    onPanelChanged: {
        if (panel !== "" && shown !== "" && shown !== panel) { shown = panel; k = 0; }
        if (panel !== "") shown = panel;
        anim.to = panel !== "" ? 1 : 0;
        anim.duration = panel !== "" ? Math.max(1, 380 * Theme.animMult) : Math.max(1, 160 * Theme.animMult);
        anim.easing.type = panel !== "" ? Easing.OutBack : Easing.InCubic;
        anim.restart();
    }
    NumberAnimation { id: anim; target: win; property: "k"; easing.overshoot: 1.1 }

    MouseArea { anchors.fill: parent; enabled: win.panel !== ""; onClicked: Serp.panel = "" }
    Item { focus: win.panel !== ""; Keys.onEscapePressed: Serp.panel = "" }

    // ------------------------------------------------------------- piezas
    component Card: Rectangle {
        id: card
        property string name: ""
        visible: win.shown === name && win.k > 0.001
        y: 6
        radius: 18
        color: Serp.bg
        border.width: 1; border.color: Serp.line
        opacity: Math.min(1, win.k * 1.6)
        transformOrigin: Item.Top
        scale: 0.92 + 0.08 * win.k
        transform: Translate { y: (1 - win.k) * -18 }
        clip: true
        MouseArea { anchors.fill: parent }       // los clics dentro no cierran
        // círculo de luz rosada al fondo, como un halo
        Rectangle {
            width: card.width * 1.1; height: width; radius: width / 2
            x: card.width * 0.35; y: -card.width * 0.25
            color: "transparent"
            border.width: 1; border.color: Qt.rgba(0.96, 0.65, 0.79, 0.06)
            Rectangle { anchors.centerIn: parent; width: parent.width * 0.7; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.015) }
        }
    }
    component T: Text { font.family: Serp.font; font.pixelSize: 12; color: Serp.fg; elide: Text.ElideRight }
    component Btn: MouseArea {
        id: b
        property string icon: ""
        property string label: ""
        property bool on: false
        property int size: 38
        implicitWidth: label !== "" ? lbl.implicitWidth + (icon !== "" ? 50 : 30) : size
        implicitHeight: size
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        scale: pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: b.pressed ? 70 : 280; easing.type: b.pressed ? Easing.OutQuad : Easing.OutBack } }
        Rectangle {
            anchors.fill: parent; radius: b.label !== "" ? 10 : b.height / 2
            color: b.on ? Serp.pink : b.containsMouse ? Serp.cardHi : Serp.card
            border.width: 1; border.color: b.on ? "transparent" : Serp.line
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        Row {
            anchors.centerIn: parent; spacing: 6
            Icon { anchors.verticalCenter: parent.verticalCenter; visible: b.icon !== ""; text: b.icon; size: 18; fill: 1; color: b.on ? Serp.pinkFg : Serp.fg }
            T { id: lbl; anchors.verticalCenter: parent.verticalCenter; visible: b.label !== ""; text: b.label; font.pixelSize: 11; font.weight: Font.DemiBold; color: b.on ? Serp.pinkFg : Serp.fg }
        }
    }
    component Bar: Item {
        id: sl
        property real value: 0
        property string icon: ""
        signal moved(real v)
        implicitHeight: 22
        Icon { id: ic; anchors.verticalCenter: parent.verticalCenter; text: sl.icon; size: 16; fill: 1; color: Serp.muted }
        Rectangle {
            id: track
            anchors.left: ic.right; anchors.leftMargin: 12; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 8; radius: 4; color: Serp.cardHi
            Rectangle { width: Math.max(8, parent.width * sl.value); height: parent.height; radius: 4; color: Serp.pink }
            MouseArea {
                anchors.fill: parent; anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                function set(m) { sl.moved(Math.max(0, Math.min(1, (m.x - 8) / track.width))); }
                onPressed: m => set(m)
                onPositionChanged: m => { if (pressed) set(m); }
            }
        }
    }

    // ------------------------------------------------------------- música
    Card {
        name: "media"
        x: 8; width: 400; height: mediaCol.implicitHeight + 36
        Timer { running: win.shown === "media" && (win.player?.isPlaying ?? false); interval: 1000; repeat: true; onTriggered: win.player?.positionChanged() }
        Column {
            id: mediaCol
            x: 18; y: 18; width: parent.width - 36; spacing: 16
            Row {
                spacing: 16
                Item {
                    width: 116; height: 116
                    Rectangle { anchors.fill: parent; radius: width / 2; color: "#0B080A"; border.width: 2; border.color: Qt.rgba(0.96, 0.65, 0.79, 0.35) }
                    Repeater { model: 3; Rectangle { required property int index; anchors.centerIn: parent; width: 108 - index * 14; height: width; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.05) } }
                    ClippingRectangle {
                        anchors.centerIn: parent; width: 64; height: 64; radius: 32; color: Serp.cardHi
                        RotationAnimation on rotation { running: win.player?.isPlaying ?? false; from: 0; to: 360; duration: 8000; loops: Animation.Infinite }
                        Image { anchors.fill: parent; source: win.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(128, 128) }
                        Icon { anchors.centerIn: parent; visible: !(win.player?.trackArtUrl); text: "music_note"; size: 28; color: Serp.pink }
                    }
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Serp.bg }
                }
                Column {
                    width: mediaCol.width - 132; spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    T { width: parent.width; text: win.player?.trackTitle || "Nada sonando"; font.pixelSize: 15; font.weight: Font.Bold }
                    T { width: parent.width; text: win.player?.trackArtist || ""; color: Serp.muted; visible: text !== "" }
                    Rectangle {
                        visible: (win.player?.identity ?? "") !== ""
                        width: via.implicitWidth + 16; height: 22; radius: 6; color: Serp.pinkSoft
                        T { id: via; anchors.centerIn: parent; text: "en " + (win.player?.identity ?? ""); font.pixelSize: 10; color: Serp.pink }
                    }
                }
            }
            // avance
            Column {
                width: parent.width; spacing: 6
                visible: (win.player?.lengthSupported ?? false) && (win.player?.length ?? 0) > 0
                function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
                Rectangle {
                    width: parent.width; height: 6; radius: 3; color: Serp.cardHi
                    Rectangle { width: parent.width * Math.min(1, (win.player?.position ?? 0) / Math.max(1, win.player?.length ?? 1)); height: parent.height; radius: 3; color: Serp.pink }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                        enabled: win.player?.canSeek ?? false
                        onClicked: m => win.player.position = (m.x - 6) / parent.width * win.player.length
                    }
                }
                Item {
                    width: parent.width; height: 14
                    T { text: parent.parent.fmt(win.player?.position ?? 0); font.pixelSize: 10; color: Serp.muted }
                    T { anchors.right: parent.right; text: parent.parent.fmt(win.player?.length ?? 0); font.pixelSize: 10; color: Serp.muted }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 14
                Btn { icon: "shuffle"; on: win.player?.shuffle ?? false; visible: win.player?.shuffleSupported ?? false; anchors.verticalCenter: parent.verticalCenter; onClicked: win.player.shuffle = !win.player.shuffle }
                Btn { icon: "skip_previous"; anchors.verticalCenter: parent.verticalCenter; onClicked: win.player?.previous() }
                Btn { icon: (win.player?.isPlaying ?? false) ? "pause" : "play_arrow"; on: true; size: 52; onClicked: win.player?.togglePlaying() }
                Btn { icon: "skip_next"; anchors.verticalCenter: parent.verticalCenter; onClicked: win.player?.next() }
                Btn { icon: "repeat"; on: (win.player?.loopState ?? 0) !== MprisLoopState.None; visible: win.player?.loopSupported ?? false; anchors.verticalCenter: parent.verticalCenter
                      onClicked: win.player.loopState = win.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist : MprisLoopState.None }
            }
            // barras que bailan mientras suena (decorativas) y el volumen
            Item {
                width: parent.width; height: 46
                Row {
                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                    Repeater {
                        model: 24
                        Rectangle {
                            id: eq
                            required property int index
                            width: 8; radius: 3; anchors.bottom: parent.bottom
                            color: Qt.rgba(0.96, 0.65, 0.79, 0.25 + 0.6 * (height / 46))
                            property real h: 6
                            height: h
                            Behavior on h { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                            Timer {
                                running: win.shown === "media" && (win.player?.isPlaying ?? false)
                                interval: 170 + (eq.index % 5) * 23; repeat: true
                                onTriggered: eq.h = 6 + Math.random() * 40 * (0.5 + 0.5 * Math.sin(eq.index / 23 * Math.PI))
                                onRunningChanged: if (!running) eq.h = 6
                            }
                        }
                    }
                }
            }
            Bar { width: parent.width; icon: Audio.icon; value: Audio.volume; onMoved: v => Audio.setVolume(v) }
        }
    }

    // ------------------------------------------------------------- hora, calendario y clima
    Card {
        name: "clock"
        x: (win.width - width) / 2; width: 780; height: 330
        property date shownMonth: new Date()
        onVisibleChanged: if (visible) shownMonth = new Date()
        SystemClock { id: clk; precision: SystemClock.Seconds }

        // calendario
        Column {
            id: cal
            x: 24; y: 22; width: 230; spacing: 10
            readonly property var loc: Qt.locale("es_ES")
            Item {
                width: parent.width; height: 24
                MouseArea { width: 24; height: 24; cursorShape: Qt.PointingHandCursor; onClicked: { const d = parent.parent.parent.shownMonth; parent.parent.parent.shownMonth = new Date(d.getFullYear(), d.getMonth() - 1, 1); }
                    Icon { anchors.centerIn: parent; text: "chevron_left"; size: 18; color: Serp.muted } }
                T { anchors.centerIn: parent; text: Serp.cap(cal.loc.toString(parent.parent.parent.shownMonth, "MMMM yyyy")); font.weight: Font.Bold }
                MouseArea { anchors.right: parent.right; width: 24; height: 24; cursorShape: Qt.PointingHandCursor; onClicked: { const d = parent.parent.parent.shownMonth; parent.parent.parent.shownMonth = new Date(d.getFullYear(), d.getMonth() + 1, 1); }
                    Icon { anchors.centerIn: parent; text: "chevron_right"; size: 18; color: Serp.muted } }
            }
            Grid {
                columns: 7; spacing: 2
                readonly property date m: parent.parent.shownMonth
                readonly property int first: (new Date(m.getFullYear(), m.getMonth(), 1).getDay() + 6) % 7
                readonly property int days: new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate()
                Repeater {
                    model: ["Lu", "Ma", "Mi", "Ju", "Vi", "Sá", "Do"]
                    T { required property string modelData; width: 30; height: 22; text: modelData; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 10; color: Serp.muted }
                }
                Repeater {
                    model: 42
                    Rectangle {
                        required property int index
                        readonly property int day: index - parent.first + 1
                        readonly property bool today: day === clk.date.getDate() && parent.m.getMonth() === clk.date.getMonth() && parent.m.getFullYear() === clk.date.getFullYear()
                        width: 30; height: 26; radius: 7
                        visible: index < 35 || parent.first + parent.days > 35
                        color: today ? Serp.pink : "transparent"
                        T { anchors.centerIn: parent; visible: parent.day >= 1 && parent.day <= parent.parent.days; text: parent.day; font.pixelSize: 11; color: parent.today ? Serp.pinkFg : Serp.fg; font.weight: parent.today ? Font.Bold : Font.Normal }
                    }
                }
            }
        }

        // reloj
        Column {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.horizontalCenterOffset: 20
            y: 92; spacing: 8
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                T { text: Qt.formatTime(clk.date, "HH:mm"); font.pixelSize: 64; font.weight: Font.Bold }
                T { anchors.baseline: parent.children[0].baseline; text: ":" + Qt.formatTime(clk.date, "ss"); font.pixelSize: 20; color: Serp.muted }
            }
            T { anchors.horizontalCenter: parent.horizontalCenter; text: Serp.cap(cal.loc.toString(clk.date, "dddd d 'de' MMMM")); color: Serp.muted }
            // cuánto falta del día
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 200; height: 4; radius: 2; color: Serp.cardHi
                Rectangle { height: 4; radius: 2; color: Serp.pink; width: parent.width * (clk.date.getHours() * 60 + clk.date.getMinutes()) / 1440 }
            }
        }

        // clima
        Column {
            anchors.right: parent.right; anchors.rightMargin: 26; y: 26
            spacing: 4
            T { anchors.right: parent.right; text: cal.loc.toString(clk.date, "dddd"); font.pixelSize: 11; color: Serp.muted; font.capitalization: Font.AllUppercase }
            Row {
                anchors.right: parent.right; spacing: 8
                Icon { anchors.verticalCenter: parent.verticalCenter; text: Weather.ready ? Weather.icon : "cloud_off"; size: 34; fill: 1; color: Serp.pink }
                T { text: Weather.ready ? Math.round(Weather.temp) + "°" : "--"; font.pixelSize: 52; font.weight: Font.Bold }
            }
            T { anchors.right: parent.right; text: Weather.ready ? Weather.text : "Sin datos del clima"; color: Serp.muted }
            T { anchors.right: parent.right; visible: Weather.ready; text: "Máx " + Math.round(Weather.high) + "°  Mín " + Math.round(Weather.low) + "°"; font.pixelSize: 11; color: Serp.muted }
            T { anchors.right: parent.right; visible: Weather.ready; text: "Sensación " + Math.round(Weather.feels) + "°"; font.pixelSize: 11; color: Serp.muted }
        }

        // pie: uso del sistema
        Row {
            anchors.bottom: parent.bottom; anchors.bottomMargin: 20
            anchors.right: parent.right; anchors.rightMargin: 26
            spacing: 18
            Component.onCompleted: SysInfo.active = true
            Repeater {
                model: [{ n: "CPU", v: () => SysInfo.cpu }, { n: "RAM", v: () => SysInfo.ram }, { n: "DISCO", v: () => SysInfo.disk }]
                Row {
                    required property var modelData
                    spacing: 8
                    Item {
                        width: 34; height: 34
                        Canvas {
                            id: ring
                            anchors.fill: parent
                            property real v: parent.parent.modelData.v()
                            onVChanged: requestPaint()
                            onPaint: {
                                const c = getContext("2d"); c.reset(); c.lineWidth = 3; c.lineCap = "round";
                                c.strokeStyle = "#2A2027"; c.beginPath(); c.arc(17, 17, 14, 0, 2 * Math.PI); c.stroke();
                                c.strokeStyle = "#F4A7C9"; c.beginPath(); c.arc(17, 17, 14, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * v); c.stroke();
                            }
                        }
                        T { anchors.centerIn: parent; text: Math.round(ring.v * 100); font.pixelSize: 9 }
                    }
                    T { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.n; font.pixelSize: 10; color: Serp.muted }
                }
            }
        }
    }

    // ------------------------------------------------------------- control
    Card {
        name: "control"
        x: win.width - width - 8; width: 400; height: ctl.implicitHeight + 36
        Column {
            id: ctl
            x: 18; y: 18; width: parent.width - 36; spacing: 16

            // notificaciones
            Item {
                width: parent.width; height: 20
                T { text: "Notificaciones"; font.weight: Font.Bold }
                MouseArea {
                    anchors.right: parent.right; width: clr.implicitWidth; height: 20
                    visible: Notifs.count > 0; cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.clearAll()
                    T { id: clr; text: "Borrar todo"; font.pixelSize: 10; color: Serp.pink }
                }
            }
            Column {
                width: parent.width; spacing: 6
                T { visible: Notifs.count === 0; text: "Nada nuevo por aquí."; color: Serp.muted; font.pixelSize: 11 }
                Repeater {
                    model: Notifs.list.slice(-3).reverse()
                    Rectangle {
                        required property var modelData
                        width: ctl.width; height: nc.implicitHeight + 16; radius: 10; color: Serp.card
                        border.width: 1; border.color: Serp.line
                        Column {
                            id: nc; x: 12; y: 8; width: parent.width - 24; spacing: 2
                            T { width: parent.width; text: parent.parent.modelData.summary || parent.parent.modelData.appName; font.weight: Font.Bold; font.pixelSize: 11 }
                            T { width: parent.width; text: parent.parent.modelData.body; color: Serp.muted; font.pixelSize: 10; maximumLineCount: 2; wrapMode: Text.WordWrap; textFormat: Text.PlainText; visible: text !== "" }
                        }
                    }
                }
            }

            // anillo: batería (portátil) o volumen (PC de escritorio)
            Item {
                width: parent.width; height: 170
                Canvas {
                    id: big
                    anchors.centerIn: parent; width: 150; height: 150
                    property real v: win.hasBattery ? (win.battery?.percentage ?? 0) : Audio.volume
                    onVChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"); c.reset(); c.lineCap = "round";
                        c.lineWidth = 10; c.strokeStyle = "#2A2027"; c.beginPath(); c.arc(75, 75, 64, 0, 2 * Math.PI); c.stroke();
                        c.strokeStyle = "#F4A7C9"; c.beginPath(); c.arc(75, 75, 64, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * v); c.stroke();
                    }
                }
                Column {
                    anchors.centerIn: parent
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 4
                        Icon { anchors.verticalCenter: parent.verticalCenter; text: win.hasBattery ? "battery_full" : Audio.icon; size: 20; fill: 1; color: Serp.pink }
                        T { text: Math.round(big.v * 100) + "%"; font.pixelSize: 28; font.weight: Font.Bold }
                    }
                    T {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: 9; color: Serp.muted
                        text: !win.hasBattery ? "VOLUMEN" : win.battery?.state === UPowerDeviceState.Charging ? "CARGANDO" : "SIN CARGAR"
                    }
                }
            }

            Bar { width: parent.width; icon: Audio.icon; value: Audio.volume; onMoved: v => Audio.setVolume(v) }
            Bar { width: parent.width; visible: Brightness.available; icon: "light_mode"; value: Brightness.value; onMoved: v => Brightness.set(v) }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 10
                Btn { icon: "lock"; onClicked: { Serp.panel = ""; Shell.lock(); } }
                Btn { icon: "bedtime"; onClicked: { Serp.panel = ""; Quickshell.execDetached(["systemctl", "suspend"]); } }
                Btn { icon: "restart_alt"; onClicked: { Serp.panel = ""; Shell.toggleSession(); } }
                Btn { icon: "power_settings_new"; onClicked: { Serp.panel = ""; Shell.toggleSession(); } }
            }

            Row {
                width: parent.width; spacing: 8
                Btn { width: (parent.width - 16) / 3; icon: Net.icon; label: "Wi-Fi"; on: Net.wifiEnabled; onClicked: Net.toggleWifi(); onPressAndHold: Shell.openWifi() }
                Btn { width: (parent.width - 16) / 3; icon: Bt.icon; label: "Bluetooth"; on: Bt.enabled; opacity: Bt.available ? 1 : 0.4; onClicked: Bt.toggle() }
                Btn { width: (parent.width - 16) / 3; icon: "nightlight"; label: "Nocturna"; on: Settings.display.nightLight
                      onClicked: Shell.toggleNightLight(); onPressAndHold: { Serp.panel = ""; Shell.personalizePage("display"); } }
            }
            Row {
                width: parent.width; spacing: 8
                readonly property var profiles: [PowerProfile.Performance, PowerProfile.Balanced, PowerProfile.PowerSaver]
                Repeater {
                    model: [{ i: "bolt", n: "Rendimiento" }, { i: "balance", n: "Equilibrio" }, { i: "eco", n: "Ahorro" }]
                    Btn {
                        required property var modelData
                        required property int index
                        width: (ctl.width - 16) / 3
                        icon: modelData.i; label: modelData.n
                        on: PowerProfiles.profile === parent.profiles[index]
                        opacity: index === 0 && !PowerProfiles.hasPerformanceProfile ? 0.4 : 1
                        onClicked: if (!(index === 0 && !PowerProfiles.hasPerformanceProfile)) PowerProfiles.profile = parent.profiles[index]
                    }
                }
            }
            Row {
                width: parent.width; spacing: 8
                Btn { width: (parent.width - 8) / 2; icon: "tune"; label: "Personalizar"; onClicked: { Serp.panel = ""; Shell.personalizePage("bar"); } }
                Btn { width: (parent.width - 8) / 2; icon: "blur_on"; label: "Usar Caelestial"; onClicked: Serp.choose("caelestial", false) }
            }
            T {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Mantén presionado para más opciones"; font.pixelSize: 9; color: Serp.muted
            }
        }
    }
}
