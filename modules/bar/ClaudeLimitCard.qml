import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Tarjeta de un límite de Claude (popup de ClaudeMeter): % usado · barra con la marca del
// tiempo transcurrido · reinicio · ritmo y previsión · tokens de los registros locales en
// esa ventana. Los hijos que se le pongan se añaden al final (antes de «leído a las»).
Rectangle {
    id: lc

    property real now: Date.now() / 1000
    property string title
    property string key
    property var tok: ({})          // desglose local: { tokens, msgs, input, output, cache_write, cache_read }
    default property alias extra: lcExtra.data
    readonly property var lim: ClaudeUsage.limits?.[key]
    readonly property real usedPct: ClaudeUsage.used(key)
    readonly property real leftPct: ClaudeUsage.left(key)
    readonly property real elapsed: ClaudeUsage.elapsed(key, lc.now)
    readonly property real proj: ClaudeUsage.projected(key, lc.now)
    // Color según lo ya usado
    function usedColor(u: real): color {
        return u < 0 ? Theme.fgMuted : u > 85 ? Theme.error : u > 65 ? Theme.tertiary : Theme.primary;
    }

    Layout.fillWidth: true
    implicitHeight: lcCol.implicitHeight + 20
    radius: 10
    color: Theme.alpha(Theme.fg, 0.05)
    ColumnLayout {
        id: lcCol
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: 10
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            Txt { Layout.fillWidth: true; text: lc.title; font.pixelSize: 12; font.weight: Font.DemiBold }
            Txt {
                text: lc.usedPct >= 0 ? Math.round(lc.usedPct) + "% " + I18n.t("usado") : "—"
                font.pixelSize: 13; font.weight: Font.Bold; font.features: { "tnum": 1 }
                color: lc.usedColor(lc.usedPct)
            }
        }
        ClaudePaceMeter {
            value: Math.max(0, lc.usedPct) / 100
            mark: lc.usedPct >= 0 ? lc.elapsed : -1
            accent: lc.usedColor(lc.usedPct)
        }
        ClaudeSubRow {
            visible: lc.leftPct >= 0
            label: I18n.t("Restante")
            value: Math.round(lc.leftPct) + "%"
        }
        ClaudeSubRow {
            visible: lc.usedPct >= 0 && !!lc.lim?.resets
            label: I18n.t("Se reinicia")
            value: ClaudeUsage.resetAt(lc.lim?.resets ?? 0) + " · " + I18n.t("en") + " " + ClaudeUsage.until(lc.lim?.resets ?? 0, lc.now)
        }
        ClaudeSubRow {
            visible: lc.usedPct >= 0 && lc.elapsed >= 0
            label: I18n.t("Tiempo transcurrido")
            value: Math.round(lc.elapsed * 100) + "%"
        }
        ClaudeSubRow {
            visible: lc.proj >= 0
            label: I18n.t("Al ritmo actual, al reiniciar")
            value: "≈ " + Math.round(lc.proj) + "%" + (lc.proj > 100 ? " ⚠" : "")
            valueColor: lc.proj > 100 ? Theme.error : lc.proj > 80 ? Theme.tertiary : Theme.primary
        }
        Txt {
            visible: lc.usedPct < 0
            Layout.fillWidth: true
            font.pixelSize: 11
            color: Theme.fgMuted
            wrapMode: Text.WordWrap
            text: lc.lim ? I18n.t("Sin lectura tras el reinicio") : I18n.t("Aún no hay lectura del límite: se actualiza tras la próxima respuesta de Claude Code.")
        }

        // separador + tokens de los registros locales
        Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; implicitHeight: 1; color: Theme.alpha(Theme.fg, 0.08) }
        ClaudeSubRow {
            label: I18n.t("Tokens (registros locales)")
            value: ClaudeUsage.fmtTokens(lc.tok?.tokens ?? 0) + " · " + (lc.tok?.msgs ?? 0) + " " + I18n.t("msgs")
        }
        ClaudeSubRow {
            label: "  " + I18n.t("entrada / salida")
            value: ClaudeUsage.fmtTokens(lc.tok?.input ?? 0) + " / " + ClaudeUsage.fmtTokens(lc.tok?.output ?? 0)
            valueColor: Theme.fgMuted
        }
        ClaudeSubRow {
            label: "  " + I18n.t("caché: escritura / lectura")
            value: ClaudeUsage.fmtTokens(lc.tok?.cache_write ?? 0) + " / " + ClaudeUsage.fmtTokens(lc.tok?.cache_read ?? 0)
            valueColor: Theme.fgMuted
        }
        ColumnLayout { id: lcExtra; Layout.fillWidth: true; spacing: 4 }
        Txt {
            visible: !!ClaudeUsage.readAt(lc.key)
            Layout.fillWidth: true
            font.pixelSize: 10
            color: Theme.fgMuted
            opacity: 0.8
            text: I18n.t("leído a las") + " " + ClaudeUsage.readAt(lc.key)
        }
    }
}
