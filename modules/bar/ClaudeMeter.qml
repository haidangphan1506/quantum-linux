import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.components

// Uso de Claude Code en la barra superior: contexto del chat actual y lo que queda de la
// ventana de 5 h y de la semana. Clic: popup con el detalle (límites, sesión, coste…).
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

    function pill(): string {
        if (!ClaudeUsage.ready) return "Claude";
        const p = [];
        if (ClaudeUsage.ctxPct >= 0) p.push(I18n.t("Contexto") + " " + Math.round(ClaudeUsage.ctxPct) + "%");
        const l5 = ClaudeUsage.left("five_hour"), l7 = ClaudeUsage.left("seven_day");
        // sin límites de la cuenta: se muestran los tokens de los registros locales
        p.push(I18n.t("5 h") + " " + (l5 >= 0 ? Math.round(l5) + "%" : ClaudeUsage.fmtTokens(ClaudeUsage.block.tokens)));
        p.push(I18n.t("7 días") + " " + (l7 >= 0 ? Math.round(l7) + "%" : ClaudeUsage.fmtTokens(ClaudeUsage.week.tokens)));
        return p.join("   ");
    }

    // Color según lo que queda (límites) o lo que se ha llenado (contexto)
    function leftColor(l: real): color {
        return l < 15 ? Theme.error : l < 35 ? Theme.tertiary : Theme.primary;
    }
    function ctxColor(p: real): color {
        return p > 85 ? Theme.error : p > 65 ? Theme.tertiary : Theme.primary;
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
        property color accent: Theme.primary
        Layout.fillWidth: true
        implicitHeight: 6
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

    // Tarjeta de un límite: nombre · % restante · barra · cuándo se reinicia
    component LimitCard: Rectangle {
        id: lc
        property string title
        property string key
        readonly property real leftPct: ClaudeUsage.left(key)
        readonly property var lim: ClaudeUsage.limits?.[key]
        Layout.fillWidth: true
        implicitHeight: lcCol.implicitHeight + 20
        radius: 10
        color: Theme.alpha(Theme.fg, 0.05)
        visible: lim !== undefined && lim !== null
        ColumnLayout {
            id: lcCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 10
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Txt { Layout.fillWidth: true; text: lc.title; font.pixelSize: 12; color: Theme.fgMuted }
                Txt { text: Math.round(lc.leftPct) + "% " + I18n.t("restante"); font.pixelSize: 12; font.weight: Font.DemiBold; color: root.leftColor(lc.leftPct) }
            }
            Meter { value: lc.leftPct / 100; accent: root.leftColor(lc.leftPct) }
            Txt {
                Layout.fillWidth: true
                font.pixelSize: 11
                color: Theme.fgMuted
                text: I18n.t("reinicia en") + " " + ClaudeUsage.until(lc.lim?.resets ?? 0, root.now)
            }
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
        implicitWidth: 340
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
            color: Theme.alpha(Theme.surface, 0.96)
            border.width: 1
            border.color: Theme.alpha(Theme.fg, 0.12)

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
                    text: I18n.t("Sin datos de límites: hace falta una suscripción de Claude y una respuesta de Claude Code.")
                }

                LimitCard { title: I18n.t("Ventana de 5 h"); key: "five_hour" }
                LimitCard { title: I18n.t("Semana"); key: "seven_day" }

                // contexto del chat actual
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ctxCol.implicitHeight + 20
                    radius: 10
                    color: Theme.alpha(Theme.fg, 0.05)
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
                    color: Theme.alpha(Theme.fg, 0.05)
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
                        InfoRow {
                            visible: root.s?.cache_warm != null
                            icon: "cached"; label: I18n.t("Caché del prompt")
                            value: root.s?.cache_warm ? I18n.t("caliente") : I18n.t("fría")
                            valueColor: root.s?.cache_warm ? Theme.primary : Theme.fgMuted
                        }
                    }
                }

                // totales de todas las sesiones y de los registros locales
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: totCol.implicitHeight + 20
                    radius: 10
                    color: Theme.alpha(Theme.fg, 0.05)
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
                        InfoRow {
                            icon: "token"; label: I18n.t("Tokens bloque 5 h")
                            value: ClaudeUsage.fmtTokens(ClaudeUsage.block.tokens) + " · " + ClaudeUsage.block.msgs + " " + I18n.t("msgs")
                        }
                        InfoRow {
                            icon: "calendar_month"; label: I18n.t("Tokens últimos 7 días")
                            value: ClaudeUsage.fmtTokens(ClaudeUsage.week.tokens) + " · " + ClaudeUsage.week.msgs + " " + I18n.t("msgs")
                        }
                    }
                }
            }
        }
    }
}
