pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Uso de Claude Code para la barra: sesión actual (contexto, coste…), % usado de la
// ventana de 5 h y de 7 días (statusLine → scripts/claude-statusline.py) y, de respaldo,
// tokens de los registros locales (scripts/claude-usage.py). Solo consulta mientras se muestra.
Singleton {
    id: root

    property bool active: false
    property bool ready: false
    property var session: null
    property var limits: null          // { five_hour: { used, resets }, seven_day: { … } } o null
    property int sessions5h: 0
    property real cost5h: 0
    property var block: ({ active: false, reset: 0, tokens: 0, msgs: 0 })
    property var week: ({ tokens: 0, msgs: 0 })

    // Porcentaje que queda de un límite (0-100), o -1 si no se conoce
    function left(key: string): real {
        const l = limits?.[key];
        return l ? Math.max(0, 100 - l.used) : -1;
    }

    // Porcentaje de contexto usado de la sesión actual, o -1
    readonly property real ctxPct: session?.ctx_pct ?? -1

    // 1,2 M / 845 k / 912
    function fmtTokens(n: real): string {
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(".", ",") + " M";
        if (n >= 1e3) return Math.round(n / 1e3) + " k";
        return String(Math.round(n));
    }

    // Tiempo hasta un instante (epoch s): «2 h 14 min», «3 d 4 h»
    function until(epoch: real, now: real): string {
        if (!epoch) return "";
        const s = Math.max(0, epoch - now);
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        if (d > 0) return d + " " + I18n.t("d") + " " + h + " " + I18n.t("h");
        return (h > 0 ? h + " " + I18n.t("h") + " " : "") + m + " " + I18n.t("min");
    }

    // 3 h 12 min → «3 h 12 min»; duración de la sesión en ms
    function fmtDuration(ms: real): string {
        if (!ms) return "";
        const m = Math.floor(ms / 60000);
        return m >= 60 ? Math.floor(m / 60) + " " + I18n.t("h") + " " + (m % 60) + " " + I18n.t("min") : m + " " + I18n.t("min");
    }

    Timer {
        interval: 20000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellDir + "/scripts/claude-usage.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.session = d.session;
                    root.limits = d.limits;
                    root.sessions5h = d.sessions_5h ?? 0;
                    root.cost5h = d.cost_5h ?? 0;
                    root.block = d.block;
                    root.week = d.week;
                    root.ready = true;
                } catch (e) {
                    root.ready = false;
                }
            }
        }
    }
}
