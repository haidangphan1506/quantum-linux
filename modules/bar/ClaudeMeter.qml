import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.components

// Uso de Claude Code en la barra superior: contexto del chat actual y el % ya usado de la
// ventana de 5 h y de la semana. Clic: popup con el detalle (límites, ritmo, previsión,
// tokens por tipo/día/modelo, sesión, coste…).
MouseArea {
    id: root

    required property var window
    readonly property var s: ClaudeUsage.session

    implicitWidth: pillRow.implicitWidth + 16
    implicitHeight: 24
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: panel.visible ? panel.close() : panel.open()

    // el sondeo solo corre mientras la barra (o el popup) lo muestra
    Binding { target: ClaudeUsage; property: "active"; value: root.visible }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property real now: clock.date.getTime() / 1000
    // reloj de segundos para la cuenta atrás del caché (solo se usa dentro del popup)
    SystemClock { id: secClock; precision: SystemClock.Seconds }
    readonly property real cacheLeft: ClaudeUsage.cacheLeft(secClock.date.getTime() / 1000)

    // "5 h 27%": porcentaje ya usado de cada ventana. Si aún no hay lectura de los límites
    // (statusLine sin configurar o ventana reiniciada sin respuesta nueva) se muestra "—".
    function limPart(key: string, label: string): string {
        const u = ClaudeUsage.used(key);
        return label + " " + (u >= 0 ? Math.round(u) + "%" : "—");
    }

    function pill(): string {
        if (!ClaudeUsage.ready) return "Claude";
        const p = [];
        if (ClaudeUsage.ctxPct >= 0) p.push(I18n.t("Contexto") + " " + Math.round(ClaudeUsage.ctxPct) + "%");
        p.push(limPart("five_hour", I18n.t("5 h")));
        p.push(limPart("seven_day", I18n.t("7 días")));
        return p.join("   ");
    }

    // Color según lo que se ha llenado del contexto
    function ctxColor(p: real): color {
        return p > 85 ? Theme.macRed : p > 65 ? Theme.macOrange : Theme.macBlue;
    }

    RowLayout {
        id: pillRow
        anchors.centerIn: parent
        spacing: 5
        Icon { text: "bolt"; size: 16; fill: 1; color: Theme.primary }
        Txt { font.pixelSize: 13; text: root.pill() }
    }

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: root.containsMouse || panel.visible ? Theme.alpha(Theme.fg, 0.12) : "transparent"
    }

    // Fila de detalle: icono · etiqueta · valor
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

    // Barra de progreso fina
    component Meter: Rectangle {
        property real value: 0
        property color accent: Theme.macBlue
        Layout.fillWidth: true
        implicitHeight: 5
        radius: 2.5
        color: Theme.alpha(Theme.fg, Theme.dark ? 0.16 : 0.1)
        Rectangle {
            width: parent.width * Math.min(1, Math.max(0, parent.value))
            height: parent.height
            radius: 2.5
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

        HyprlandFocusGrab {
            windows: root.window ? [panel, root.window] : [panel]
            active: panel.visible
            onCleared: panel.close()
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.popover   // popover de macOS
            border.width: 1
            border.color: Theme.popoverBorder

            ColumnLayout {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 14
                spacing: 10

                // cabecera: Claude Code · modelo
                RowLayout {
                    Layout.fillWidth: true
                    Icon { text: "bolt"; size: 18; fill: 1; color: Theme.primary }
                    Txt { Layout.fillWidth: true; text: "Claude Code"; font.pixelSize: 15; font.weight: Font.Bold }
                    Txt { visible: !!root.s?.model; text: root.s?.model ?? ""; font.pixelSize: 12; color: Theme.fgMuted }
                }

                Txt {
                    visible: !ClaudeUsage.limits
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: Theme.fgMuted
                    text: I18n.t("Sin datos de límites: hace falta una suscripción de Claude, el statusLine de Quantum en ~/.claude/settings.json y una respuesta de Claude Code.")
                }

                ClaudeLimitCard {
                    now: root.now
                    title: I18n.t("Ventana de 5 h"); key: "five_hour"; tok: ClaudeUsage.block
                    ClaudeSubRow {
                        visible: ClaudeUsage.block.active && ClaudeUsage.block.burn_per_h > 0
                        label: I18n.t("Ritmo")
                        value: ClaudeUsage.fmtTokens(ClaudeUsage.block.burn_per_h) + " " + I18n.t("tokens/h")
                        valueColor: Theme.fgMuted
                    }
                }
                ClaudeLimitCard {
                    now: root.now
                    title: I18n.t("Semana"); key: "seven_day"; tok: ClaudeUsage.week
                    // tokens por día, últimos 7 días (hoy a la derecha)
                    RowLayout {
                        id: days
                        readonly property var vals: ClaudeUsage.week.daily ?? []
                        readonly property real maxV: Math.max(1, ...vals)
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 4
                        Repeater {
                            model: days.vals.length
                            ColumnLayout {
                                id: dayCol
                                required property int index
                                readonly property var date: new Date(((ClaudeUsage.week.start || root.now) + index * 86400 + 3600) * 1000)
                                Layout.fillWidth: true
                                spacing: 2
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(parent.width, 18)
                                        height: Math.max(2, parent.height * days.vals[dayCol.index] / days.maxV)
                                        radius: 2
                                        color: dayCol.date.toDateString() === new Date(ClaudeUsage.since4.start * 1000 + 3600000).toDateString() ? Theme.primary : Theme.alpha(Theme.primary, 0.45)
                                    }
                                }
                                Txt {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: 9
                                    color: Theme.fgMuted
                                    text: I18n.weekdaysShort[(dayCol.date.getDay() + 6) % 7]
                                }
                            }
                        }
                    }
                    // tokens por modelo (7 días)
                    Repeater {
                        model: (ClaudeUsage.week.models ?? []).slice(0, 4)
                        ClaudeSubRow {
                            required property var modelData
                            label: "  " + modelData.model.replace(/^claude-/, "")
                            value: ClaudeUsage.fmtTokens(modelData.tokens) + " · " + modelData.msgs + " " + I18n.t("msgs")
                            valueColor: Theme.fgMuted
                        }
                    }
                }

                // tokens y mensajes desde las 04:00 (reinicio diario del límite)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: s4Col.implicitHeight + 20
                    radius: 10
                    color: Theme.alpha(Theme.fg, 0.05)
                    ColumnLayout {
                        id: s4Col
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Txt { Layout.fillWidth: true; text: I18n.t("Desde las 04:00"); font.pixelSize: 12; font.weight: Font.DemiBold }
                            Txt {
                                text: ClaudeUsage.fmtTokens(ClaudeUsage.since4.tokens) + " · " + ClaudeUsage.since4.msgs + " " + I18n.t("msgs")
                                font.pixelSize: 13; font.weight: Font.Bold; font.features: { "tnum": 1 }
                                color: Theme.primary
                            }
                        }
                        ClaudeSubRow {
                            label: "  " + I18n.t("entrada / salida")
                            value: ClaudeUsage.fmtTokens(ClaudeUsage.since4.input) + " / " + ClaudeUsage.fmtTokens(ClaudeUsage.since4.output)
                            valueColor: Theme.fgMuted
                        }
                        ClaudeSubRow {
                            label: "  " + I18n.t("caché: escritura / lectura")
                            value: ClaudeUsage.fmtTokens(ClaudeUsage.since4.cache_write) + " / " + ClaudeUsage.fmtTokens(ClaudeUsage.since4.cache_read)
                            valueColor: Theme.fgMuted
                        }
                        Repeater {
                            model: (ClaudeUsage.since4.models ?? []).slice(0, 4)
                            ClaudeSubRow {
                                required property var modelData
                                label: "  " + modelData.model.replace(/^claude-/, "")
                                value: ClaudeUsage.fmtTokens(modelData.tokens) + " · " + modelData.msgs + " " + I18n.t("msgs")
                                valueColor: Theme.fgMuted
                            }
                        }
                    }
                }

                // contexto del chat actual
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ctxCol.implicitHeight + 20
                    radius: 10
                    color: Theme.popoverCard
                    border.width: 1
                    border.color: Theme.popoverCardBorder
                    visible: root.s !== null
                    ColumnLayout {
                        id: ctxCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Txt { Layout.fillWidth: true; text: I18n.t("Contexto de este chat"); font.pixelSize: 12; color: Theme.fgMuted }
                            Txt {
                                text: ClaudeUsage.ctxPct >= 0 ? Math.round(ClaudeUsage.ctxPct) + "%" : "—"
                                font.pixelSize: 12; font.weight: Font.DemiBold
                                color: root.ctxColor(ClaudeUsage.ctxPct)
                            }
                        }
                        Meter { value: ClaudeUsage.ctxPct / 100; accent: root.ctxColor(ClaudeUsage.ctxPct) }
                        Txt {
                            font.pixelSize: 11
                            color: Theme.fgMuted
                            text: ClaudeUsage.fmtTokens(root.s?.ctx_tokens ?? 0) + " / " + ClaudeUsage.fmtTokens(root.s?.ctx_size ?? 0) + " " + I18n.t("tokens")
                        }
                    }
                }

                // detalle de la sesión
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: detCol.implicitHeight + 20
                    radius: 10
                    color: Theme.popoverCard
                    border.width: 1
                    border.color: Theme.popoverCardBorder
                    visible: root.s !== null
                    ColumnLayout {
                        id: detCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6
                        InfoRow {
                            visible: !!root.s?.name
                            icon: "label"; label: I18n.t("Nombre"); value: root.s?.name ?? ""
                        }
                        InfoRow {
                            icon: "folder"; label: I18n.t("Carpeta")
                            value: (root.s?.cwd ?? "").split("/").pop() || "—"
                        }
                        InfoRow {
                            visible: root.s?.cost_usd != null
                            icon: "payments"; label: I18n.t("Coste de la sesión")
                            value: "$" + (root.s?.cost_usd ?? 0).toFixed(2)
                        }
                        InfoRow {
                            visible: (root.s?.duration_ms ?? 0) > 0
                            icon: "schedule"; label: I18n.t("Duración")
                            value: ClaudeUsage.fmtDuration(root.s?.duration_ms ?? 0)
                        }
                        InfoRow {
                            visible: root.s?.lines_added != null
                            icon: "code"; label: I18n.t("Líneas cambiadas")
                            value: "+" + (root.s?.lines_added ?? 0) + "  −" + (root.s?.lines_removed ?? 0)
                        }
                        // caché del prompt: pin verde = còn caché; cuenta atrás + thanh = tiempo que queda
                        RowLayout {
                            visible: ClaudeUsage.cache.last > 0
                            Layout.fillWidth: true
                            spacing: 8
                            Icon {
                                text: "keep"; size: 16; fill: root.cacheLeft > 0 ? 1 : 0
                                color: root.cacheLeft > 0 ? Theme.macGreen : Theme.fgMuted
                            }
                            Txt { Layout.fillWidth: true; text: I18n.t("Caché del prompt"); font.pixelSize: 13; color: Theme.fgMuted }
                            Txt {
                                text: root.cacheLeft > 0 ? ClaudeUsage.fmtCountdown(root.cacheLeft) : I18n.t("expirada")
                                font.pixelSize: 13; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                                color: root.cacheLeft > 0 ? Theme.macGreen : Theme.fgMuted
                            }
                        }
                        RowLayout {
                            visible: ClaudeUsage.cache.last > 0
                            Layout.fillWidth: true
                            spacing: 8
                            Icon {
                                text: "timer"; size: 16
                                color: root.cacheLeft > 0 ? Theme.macGreen : Theme.fgMuted
                            }
                            Meter {
                                value: root.cacheLeft / Math.max(1, ClaudeUsage.cache.ttl)
                                accent: Theme.macGreen
                            }
                        }
                    }
                }

                // totales de todas las sesiones y de los registros locales
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: totCol.implicitHeight + 20
                    radius: 10
                    color: Theme.popoverCard
                    border.width: 1
                    border.color: Theme.popoverCardBorder
                    ColumnLayout {
                        id: totCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6
                        InfoRow {
                            icon: "forum"; label: I18n.t("Sesiones activas (5 h)")
                            value: String(ClaudeUsage.sessions5h)
                        }
                        InfoRow {
                            visible: ClaudeUsage.cost5h > 0
                            icon: "payments"; label: I18n.t("Coste (5 h, aprox.)")
                            value: "$" + ClaudeUsage.cost5h.toFixed(2)
                        }
                    }
                }
            }
        }
    }
}
