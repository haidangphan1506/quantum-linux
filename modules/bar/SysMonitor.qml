import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.components

// Monitor del sistema en la barra superior: temperatura de la CPU, uso de CPU y RAM
// en tiempo real. Al hacer clic abre un panel con todo el detalle (temperaturas de
// CPU/GPU/SSD, red, disco, carga, tiempo encendido y procesos que más consumen).
MouseArea {
    id: root

    property var barWindow: null
    property bool compact: false

    implicitWidth: row.implicitWidth + 14
    implicitHeight: 24
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    // clic: panel de detalle · clic derecho: Quản lý tác vụ (apps/taskmgr, như Task Manager)
    onClicked: e => {
        if (e.button === Qt.RightButton) { panel.close(); Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/quantum-taskmgr"]); }
        else panel.visible ? panel.close() : panel.open();
    }

    Component.onCompleted: SysInfo.barUsers++
    Component.onDestruction: SysInfo.barUsers--

    // %RAM của một app (top) → dung lượng: MB dưới 1 GB, GB từ 1 GB trở lên
    function fmtProcMem(pct: real): string {
        const gb = pct / 100 * SysInfo.ramTotalGb;
        return gb >= 1 ? gb.toFixed(1) + " GB" : Math.round(gb * 1024) + " MB";
    }

    function tempColor(t: real): color {
        const l = SysInfo.tempLevel(t);
        return l === 2 ? Theme.error : l === 1 ? Theme.tertiary : Theme.fg;
    }

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: panel.visible ? Theme.alpha(Theme.fg, 0.22) : root.containsMouse ? Theme.alpha(Theme.fg, 0.12) : "transparent"
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Icon {
            visible: SysInfo.temp > 0
            text: "device_thermostat"
            size: 15
            color: root.tempColor(SysInfo.temp)
        }
        Txt {
            visible: SysInfo.temp > 0
            text: Math.round(SysInfo.temp) + "°"
            font.pixelSize: 13
            font.features: { "tnum": 1 }
            color: root.tempColor(SysInfo.temp)
        }
        Item { visible: !root.compact; implicitWidth: 4 }
        Icon { visible: !root.compact; text: "memory"; size: 15 }
        Txt {
            visible: !root.compact
            text: Math.round(SysInfo.cpu * 100) + "%"
            font.pixelSize: 13
            font.features: { "tnum": 1 }
            Layout.minimumWidth: 30
        }
        Icon { visible: !root.compact; text: "memory_alt"; size: 15 }
        Txt {
            visible: !root.compact
            text: Math.round(SysInfo.ram * 100) + "%"
            font.pixelSize: 13
            font.features: { "tnum": 1 }
            Layout.minimumWidth: 30
        }
    }

    // ------------------------------------------------------------ panel
    component Spark: Canvas {
        id: sp
        property var values: []
        property real max: 1
        property color stroke: Theme.primary
        implicitHeight: 36
        onValuesChanged: requestPaint()
        onStrokeChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const v = sp.values;
            if (v.length < 2) return;
            const w = width, h = height, step = w / 29, x0 = w - (v.length - 1) * step;
            const y = val => h - 2 - Math.min(1, val / sp.max) * (h - 4);
            ctx.beginPath();
            ctx.moveTo(x0, h);
            for (let i = 0; i < v.length; i++) ctx.lineTo(x0 + i * step, y(v[i]));
            ctx.lineTo(w, h);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(sp.stroke.r, sp.stroke.g, sp.stroke.b, 0.18);
            ctx.fill();
            ctx.beginPath();
            for (let i = 0; i < v.length; i++) i === 0 ? ctx.moveTo(x0, y(v[0])) : ctx.lineTo(x0 + i * step, y(v[i]));
            ctx.strokeStyle = sp.stroke;
            ctx.lineWidth = 1.6;
            ctx.stroke();
        }
    }

    // Tarjeta: ícono, título, valor grande y gráfico
    component StatCard: Rectangle {
        id: sc
        property string icon
        property string title
        property string value
        property string sub
        property var values: []
        property real max: 1
        property color accent: Theme.primary
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: scCol.implicitHeight + 20
        radius: 10
        color: Theme.alpha(Theme.fg, 0.05)
        ColumnLayout {
            id: scCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 10
            spacing: 2
            RowLayout {
                spacing: 5
                Icon { text: sc.icon; size: 15; color: sc.accent }
                Txt { text: sc.title; font.pixelSize: 12; color: Theme.fgMuted }
            }
            Txt { text: sc.value; font.pixelSize: 20; font.weight: Font.Bold; font.features: { "tnum": 1 } }
            Txt { Layout.fillWidth: true; text: sc.sub; font.pixelSize: 11; color: Theme.fgMuted; elide: Text.ElideRight }
            Spark { Layout.fillWidth: true; Layout.topMargin: 4; values: sc.values; max: sc.max; stroke: sc.accent }
        }
    }

    // Fila de detalle: etiqueta · valor
    component InfoRow: RowLayout {
        property string icon
        property string label
        property string value
        property color valueColor: Theme.fg
        Layout.fillWidth: true
        spacing: 8
        Icon { text: parent.icon; size: 16; color: Theme.fgMuted }
        Txt { Layout.fillWidth: true; text: parent.label; font.pixelSize: 13; color: Theme.fgMuted }
        Txt { text: parent.value; font.pixelSize: 13; font.weight: Font.DemiBold; font.features: { "tnum": 1 }; color: parent.valueColor }
    }

    component Bar: Rectangle {
        property real value: 0
        property color accent: Theme.primary
        Layout.fillWidth: true
        implicitHeight: 5
        radius: 3
        color: Theme.alpha(Theme.fg, 0.1)
        Rectangle {
            width: parent.width * Math.min(1, Math.max(0, parent.value))
            height: parent.height
            radius: 3
            color: parent.accent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    PopupWindow {
        id: panel

        property real closedAt: 0
        function open(): void { if (Date.now() - closedAt > 200) visible = true; }
        function close(): void { if (visible) { visible = false; closedAt = Date.now(); } }

        anchor.item: root
        anchor.rect.x: root.width - implicitWidth
        anchor.rect.y: root.height + 3
        implicitWidth: 360
        implicitHeight: col.implicitHeight + 28
        color: "transparent"

        Binding { target: SysInfo; property: "detail"; value: panel.visible }

        HyprlandFocusGrab {
            windows: root.barWindow ? [panel, root.barWindow] : [panel]
            active: panel.visible
            onCleared: panel.close()
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.alpha(Theme.surface, 0.96)
            border.width: 1
            border.color: Theme.alpha(Theme.fg, 0.12)

            ColumnLayout {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Txt { Layout.fillWidth: true; text: I18n.t("Sistema"); font.pixelSize: 15; font.weight: Font.Bold }
                    Txt { text: I18n.t("Encendido ") + SysInfo.fmtUptime(SysInfo.uptime); font.pixelSize: 12; color: Theme.fgMuted }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatCard {
                        icon: "memory"; title: "CPU"
                        value: Math.round(SysInfo.cpu * 100) + "%"
                        sub: (SysInfo.cpuMhz / 1000).toFixed(2) + " GHz"
                        values: SysInfo.cpuHistory
                        accent: Theme.primary
                    }
                    StatCard {
                        icon: "memory_alt"; title: "RAM"
                        value: Math.round(SysInfo.ram * 100) + "%"
                        sub: SysInfo.ramUsedGb.toFixed(1) + " / " + SysInfo.ramTotalGb.toFixed(0) + " GB"
                        values: SysInfo.ramHistory
                        accent: Theme.tertiary
                    }
                    StatCard {
                        icon: "device_thermostat"; title: I18n.t("Temp.")
                        value: SysInfo.temp > 0 ? Math.round(SysInfo.temp) + "°C" : "—"
                        sub: "CPU"
                        values: SysInfo.tempHistory
                        max: 100
                        accent: SysInfo.tempLevel(SysInfo.temp) === 2 ? Theme.error : SysInfo.tempLevel(SysInfo.temp) === 1 ? Theme.tertiary : "#4cc38a"
                    }
                }

                // Temperaturas
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: tCol.implicitHeight + 20
                    radius: 10
                    color: Theme.alpha(Theme.fg, 0.05)
                    ColumnLayout {
                        id: tCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6
                        InfoRow { icon: "memory"; label: I18n.t("Procesador"); value: SysInfo.temp > 0 ? Math.round(SysInfo.temp) + " °C" : "—"; valueColor: root.tempColor(SysInfo.temp) }
                        InfoRow { visible: SysInfo.gpuTemp > 0; icon: "developer_board"; label: I18n.t("Gráfica"); value: Math.round(SysInfo.gpuTemp) + " °C"; valueColor: root.tempColor(SysInfo.gpuTemp) }
                        InfoRow { visible: SysInfo.ssdTemp > 0; icon: "hard_drive"; label: "SSD"; value: Math.round(SysInfo.ssdTemp) + " °C"; valueColor: root.tempColor(SysInfo.ssdTemp) }
                    }
                }

                // Disco, red, carga
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: dCol.implicitHeight + 20
                    radius: 10
                    color: Theme.alpha(Theme.fg, 0.05)
                    ColumnLayout {
                        id: dCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6
                        InfoRow { icon: "hard_drive"; label: I18n.t("Disco"); value: Math.round(SysInfo.diskUsedGb) + " / " + Math.round(SysInfo.diskTotalGb) + " GB" }
                        Bar { value: SysInfo.disk; accent: Theme.primary }
                        InfoRow { visible: SysInfo.swapTotalGb > 0; icon: "swap_horiz"; label: "Swap"; value: SysInfo.swapUsedGb.toFixed(1) + " / " + SysInfo.swapTotalGb.toFixed(0) + " GB" }
                        InfoRow { icon: "download"; label: I18n.t("Descarga"); value: SysInfo.fmtRate(SysInfo.netDown) }
                        InfoRow { icon: "upload"; label: I18n.t("Subida"); value: SysInfo.fmtRate(SysInfo.netUp) }
                        InfoRow { icon: "speed"; label: I18n.t("Carga (1/5/15 min)"); value: SysInfo.load }
                    }
                }

                // Procesos
                Txt { text: I18n.t("Procesos que más consumen"); font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.fgMuted }
                Repeater {
                    model: SysInfo.procs
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Txt { Layout.fillWidth: true; text: modelData.name; font.pixelSize: 13; elide: Text.ElideRight }
                        Txt { text: modelData.cpu.toFixed(1) + "%"; font.pixelSize: 12; font.features: { "tnum": 1 }; color: Theme.primary; Layout.minimumWidth: 44; horizontalAlignment: Text.AlignRight }
                        Txt { text: root.fmtProcMem(modelData.mem); font.pixelSize: 12; font.features: { "tnum": 1 }; color: Theme.fgMuted; Layout.minimumWidth: 70; horizontalAlignment: Text.AlignRight }
                    }
                }
                Txt { visible: SysInfo.procs.length === 0; text: I18n.t("Midiendo…"); font.pixelSize: 12; color: Theme.fgMuted }
            }
        }
    }
}
