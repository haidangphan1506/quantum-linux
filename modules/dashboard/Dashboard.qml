import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.services
import qs.components

// Panel central (estilo Caelestia): baja desde el reloj. Pestañas «Inicio»
// (hora, calendario y música) y «Rendimiento» (CPU, RAM, disco y temperatura).
// Es una tarjeta bajo la barra: no tapa toda la pantalla.
PanelWindow {
    id: win

    readonly property bool open: Shell.dashboardOpen
    property real progress: 0
    property int tab: 0

    visible: open || progress > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-dashboard"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    // abrir con rebote suave; cerrar rápido hacia arriba
    onOpenChanged: {
        anim.to = open ? 1 : 0;
        anim.duration = open ? 560 : 220;
        anim.easing.type = open ? Easing.OutBack : Easing.InCubic;
        anim.restart();
        if (open) cal.month = new Date();
    }
    NumberAnimation { id: anim; target: win; property: "progress"; easing.overshoot: 1.25 }

    // las tarjetas entran una tras otra: 0 → 1 para la tarjeta i
    function stage(i: int): real { return Math.max(0, Math.min(1, (progress - 0.12 - i * 0.13) / 0.45)); }

    // abierto con el mouse: se cierra al salir de la tarjeta y de la franja de arriba
    Timer {
        id: leaveTimer
        interval: 450
        onTriggered: if (Shell.dashboardHover && !hover.hovered && !Shell.dashboardZoneHovered) Shell.dashboardOpen = false
    }
    readonly property bool away: Shell.dashboardHover && win.open && !hover.hovered && !Shell.dashboardZoneHovered
    onAwayChanged: away ? leaveTimer.restart() : leaveTimer.stop()

    Binding { target: SysInfo; property: "active"; value: win.open && win.tab === 1 }

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property string user: Quickshell.env("USER") ?? ""

    MouseArea {
        anchors.fill: parent
        enabled: win.open
        onClicked: Shell.dashboardOpen = false
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // qs ipc call dashboard open <pestaña>: 0 = Inicio, 1 = Rendimiento
    IpcHandler {
        target: "dashboard"
        function open(tab: int): void {
            if (!Shell.dashboardOpen) Shell.toggleDashboard();
            win.tab = tab;
        }
    }

    Card {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        width: Math.min(940, parent.width - 40)
        height: 470
        color: Theme.alpha(Theme.surface, 0.94)
        opacity: Math.min(1, win.progress * 1.6)
        scale: 0.92 + 0.08 * win.progress
        transformOrigin: Item.Top
        transform: Translate { y: (1 - win.progress) * -40 }
        focus: win.open
        Keys.onEscapePressed: Shell.dashboardOpen = false
        Keys.onLeftPressed: win.tab = 0
        Keys.onRightPressed: win.tab = 1

        // un clic adentro lo deja fijo aunque se haya abierto con el mouse
        MouseArea { anchors.fill: parent; onPressed: e => { Shell.dashboardHover = false; e.accepted = true; } }
        HoverHandler { id: hover }

        // línea de color de Quantum
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 2 * parent.radius
            height: 1
            opacity: 0.6
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.25; color: Theme.brandCyan }
                GradientStop { position: 0.5; color: Theme.brandIndigo }
                GradientStop { position: 0.75; color: Theme.brandViolet }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 18

            // pestañas con indicador que se desliza
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 320
                implicitHeight: 44
                radius: 22
                color: Theme.surfaceHigh
                Rectangle {
                    width: parent.width / 2 - 6
                    height: parent.height - 8
                    y: 4
                    x: 4 + win.tab * (parent.width / 2 - 2)
                    radius: height / 2
                    color: Theme.primaryContainer
                    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                }
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: [{ i: "home", t: "Inicio" }, { i: "monitoring", t: "Rendimiento" }]
                        Item {
                            required property var modelData
                            required property int index
                            width: parent.width / 2
                            height: parent.height
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Icon { text: modelData.i; size: 20; fill: win.tab === index ? 1 : 0; color: win.tab === index ? Theme.primaryContainerFg : Theme.fg }
                                Txt { text: modelData.t; font.weight: Font.DemiBold; color: win.tab === index ? Theme.primaryContainerFg : Theme.fg }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.tab = index }
                        }
                    }
                }
            }

            // contenido: las dos pestañas se deslizan de lado
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Item {
                    id: slider
                    width: parent.width * 2
                    height: parent.height
                    x: -win.tab * parent.width
                    Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                    // entrada escalonada de las tarjetas de cada pestaña (suben y aparecen)
                    Component.onCompleted: {
                        for (const row of slider.children) {
                            for (let i = 0; i < row.children.length; i++) {
                                const c = row.children[i];
                                const k = i;
                                c.opacity = Qt.binding(() => win.stage(k));
                                const t = Qt.createQmlObject("import QtQuick; Translate {}", c);
                                t.y = Qt.binding(() => (1 - win.stage(k)) * 26);
                                c.transform = [t];
                            }
                        }
                    }

                    // ------------------------------------------------ Inicio
                    RowLayout {
                        width: slider.width / 2
                        height: slider.height
                        spacing: 16

                        // hora y saludo
                        Rectangle {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 270
                            radius: Theme.radiusLarge
                            gradient: Gradient {
                                GradientStop { position: 0; color: Theme.alpha(Theme.brandIndigo, 0.35) }
                                GradientStop { position: 1; color: Theme.alpha(Theme.brandViolet, 0.18) }
                            }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 22
                                spacing: 4
                                Txt { text: Qt.formatDateTime(clock.date, "HH:mm"); font.pixelSize: 64; font.weight: Font.Black }
                                Txt { text: Qt.formatDateTime(clock.date, "ss") + " s"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                                Item { Layout.fillHeight: true }
                                Txt {
                                    Layout.fillWidth: true
                                    text: clock.date.toLocaleDateString(Qt.locale(), "dddd")
                                    font.pixelSize: Theme.textLarge + 2
                                    font.weight: Font.Bold
                                    font.capitalization: Font.Capitalize
                                }
                                Txt { text: clock.date.toLocaleDateString(Qt.locale(), "d 'de' MMMM yyyy"); color: Theme.fgMuted }
                                Txt {
                                    Layout.topMargin: 10
                                    readonly property int h: clock.date.getHours()
                                    text: (h < 12 ? "Buenos días" : h < 20 ? "Buenas tardes" : "Buenas noches") + ", " + win.user
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                }
                            }
                        }

                        // calendario
                        Rectangle {
                            id: cal
                            property date month: new Date()
                            Layout.fillHeight: true
                            Layout.preferredWidth: 320
                            radius: Theme.radiusLarge
                            color: Theme.surfaceContainer
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    IconButton { icon: "chevron_left"; onClicked: cal.month = new Date(cal.month.getFullYear(), cal.month.getMonth() - 1, 1) }
                                    Txt {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: cal.month.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                                        font.weight: Font.Bold
                                        font.capitalization: Font.Capitalize
                                    }
                                    IconButton { icon: "chevron_right"; onClicked: cal.month = new Date(cal.month.getFullYear(), cal.month.getMonth() + 1, 1) }
                                }
                                Grid {
                                    Layout.alignment: Qt.AlignHCenter
                                    columns: 7
                                    columnSpacing: 2
                                    rowSpacing: 2
                                    Repeater {
                                        model: ["L", "M", "M", "J", "V", "S", "D"]
                                        Txt { required property string modelData; width: 38; height: 26; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.fgMuted; font.pixelSize: Theme.textSmall; font.weight: Font.Bold }
                                    }
                                    Repeater {
                                        // 6 semanas desde el lunes anterior al día 1
                                        model: 42
                                        Rectangle {
                                            required property int index
                                            readonly property date first: new Date(cal.month.getFullYear(), cal.month.getMonth(), 1)
                                            readonly property int offset: (first.getDay() + 6) % 7
                                            readonly property date day: new Date(first.getFullYear(), first.getMonth(), 1 - offset + index)
                                            readonly property bool inMonth: day.getMonth() === first.getMonth()
                                            readonly property bool today: day.toDateString() === clock.date.toDateString()
                                            width: 38; height: 34; radius: 17
                                            color: today ? Theme.primary : dayArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
                                            Txt {
                                                anchors.centerIn: parent
                                                text: parent.day.getDate()
                                                font.weight: parent.today ? Font.Bold : Font.Normal
                                                color: parent.today ? Theme.primaryFg : parent.inMonth ? Theme.fg : Theme.alpha(Theme.fgMuted, 0.45)
                                            }
                                            MouseArea { id: dayArea; anchors.fill: parent; hoverEnabled: true }
                                        }
                                    }
                                }
                            }
                        }

                        // música
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusLarge
                            color: Theme.surfaceContainer
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: win.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                opacity: 0.25
                                visible: status === Image.Ready
                            }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 10
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 120; implicitHeight: 120; radius: 22
                                    color: Theme.surfaceHigh
                                    clip: true
                                    Image { id: art; anchors.fill: parent; source: win.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop }
                                    Icon { anchors.centerIn: parent; visible: art.status !== Image.Ready; text: "music_note"; size: 48; color: Theme.fgMuted }
                                    // gira suave mientras suena
                                    rotation: win.player?.isPlaying ? Math.sin(clock.date.getSeconds() / 9.5) * 2 : 0
                                    Behavior on rotation { NumberAnimation { duration: 900 } }
                                }
                                Txt { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: win.player ? (win.player.trackTitle || "Sin título") : "Nada sonando"; font.weight: Font.Bold }
                                Txt { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: win.player ? (win.player.trackArtist || win.player.identity || "") : "Pon música y aparecerá aquí"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    enabled: win.player !== null
                                    opacity: enabled ? 1 : 0.4
                                    spacing: 8
                                    IconButton { icon: "skip_previous"; onClicked: win.player.previous() }
                                    IconButton {
                                        icon: win.player?.isPlaying ? "pause" : "play_arrow"
                                        active: true
                                        implicitWidth: 48; implicitHeight: 48
                                        onClicked: win.player.togglePlaying()
                                    }
                                    IconButton { icon: "skip_next"; onClicked: win.player.next() }
                                }
                            }
                        }
                    }

                    // --------------------------------------------- Rendimiento
                    ColumnLayout {
                        x: slider.width / 2
                        width: slider.width / 2
                        height: slider.height
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 14
                            Repeater {
                                model: [
                                    { icon: "memory", name: "Procesador", v: SysInfo.cpu, txt: Math.round(SysInfo.cpu * 100) + "%" },
                                    { icon: "memory_alt", name: "Memoria", v: SysInfo.ram, txt: SysInfo.ramUsedGb.toFixed(1) + " / " + SysInfo.ramTotalGb.toFixed(0) + " GB" },
                                    { icon: "hard_drive", name: "Disco", v: SysInfo.disk, txt: Math.round(SysInfo.diskUsedGb) + " / " + Math.round(SysInfo.diskTotalGb) + " GB" },
                                    { icon: "thermostat", name: "Temperatura", v: Math.min(1, SysInfo.temp / 100), txt: SysInfo.temp > 0 ? Math.round(SysInfo.temp) + " °C" : "—" },
                                ]
                                Rectangle {
                                    id: gauge
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.radiusLarge
                                    color: Theme.surfaceContainer
                                    // el anillo se llena animado
                                    property real shown: 0
                                    Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                    Component.onCompleted: shown = Qt.binding(() => win.tab === 1 ? gauge.modelData.v : 0)
                                    onShownChanged: ring.requestPaint()

                                    Canvas {
                                        id: ring
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 18
                                        width: 128; height: 128
                                        onPaint: {
                                            const g = getContext("2d");
                                            g.reset();
                                            const c = 64, r = 54;
                                            g.lineWidth = 12;
                                            g.lineCap = "round";
                                            g.strokeStyle = Theme.alpha(Theme.fg, 0.08);
                                            g.beginPath(); g.arc(c, c, r, 0.75 * Math.PI, 2.25 * Math.PI); g.stroke();
                                            const grad = g.createLinearGradient(0, 0, 128, 128);
                                            grad.addColorStop(0, Theme.brandCyan);
                                            grad.addColorStop(0.5, Theme.brandIndigo);
                                            grad.addColorStop(1, Theme.brandViolet);
                                            g.strokeStyle = gauge.modelData.v > 0.85 && gauge.index !== 2 ? Theme.error : grad;
                                            g.beginPath(); g.arc(c, c, r, 0.75 * Math.PI, 0.75 * Math.PI + 1.5 * Math.PI * Math.max(0.001, gauge.shown)); g.stroke();
                                        }
                                        Icon { anchors.centerIn: parent; anchors.verticalCenterOffset: -8; text: gauge.modelData.icon; size: 26; color: Theme.primary; fill: 1 }
                                        Txt { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 26; text: Math.round(gauge.shown * 100) + "%"; font.weight: Font.Bold }
                                    }
                                    ColumnLayout {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 18
                                        spacing: 2
                                        Txt { Layout.alignment: Qt.AlignHCenter; text: gauge.modelData.name; font.weight: Font.Bold }
                                        Txt { Layout.alignment: Qt.AlignHCenter; text: gauge.modelData.txt; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                                    }
                                }
                            }
                        }

                        // historial de CPU
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 92
                            radius: Theme.radiusLarge
                            color: Theme.surfaceContainer
                            Txt { x: 16; y: 10; text: "Procesador · últimos 45 s"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                            Canvas {
                                id: spark
                                anchors.fill: parent
                                anchors.topMargin: 30
                                anchors.margins: 14
                                property var data: SysInfo.cpuHistory
                                onDataChanged: requestPaint()
                                onPaint: {
                                    const g = getContext("2d");
                                    g.reset();
                                    const d = data, n = 30;
                                    if (d.length < 2) return;
                                    const w = width, h = height, step = w / (n - 1);
                                    const x0 = w - (d.length - 1) * step;
                                    const grad = g.createLinearGradient(0, 0, w, 0);
                                    grad.addColorStop(0, Theme.brandCyan);
                                    grad.addColorStop(1, Theme.brandViolet);
                                    g.beginPath();
                                    d.forEach((v, i) => { const x = x0 + i * step, y = h - v * h; i ? g.lineTo(x, y) : g.moveTo(x, y); });
                                    g.lineWidth = 3; g.strokeStyle = grad; g.lineJoin = "round"; g.stroke();
                                    g.lineTo(w, h); g.lineTo(x0, h); g.closePath();
                                    g.globalAlpha = 0.18; g.fillStyle = grad; g.fill();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
