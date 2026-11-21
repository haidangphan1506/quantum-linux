import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Ancho de banda: velocidad actual, tope total (automático o manual) y prioridad / límite
// de cada app. Lo aplica netprio (tc + nftables) según el cgroup de la app.
ColumnLayout {
    id: page
    spacing: 16

    Component.onCompleted: { NetPrio.users++; SysInfo.barUsers++; }
    Component.onDestruction: { NetPrio.users--; SysInfo.barUsers--; }

    readonly property var d: NetPrio.data
    readonly property bool manual: d.down !== "auto" && d.down !== undefined
    readonly property var apps: d.apps ?? []
    readonly property int shareSum: apps.reduce((s, a) => s + a.share, 0) + (d.otherShare ?? 0)
    // tope de los deslizadores: el doble de lo medido, mínimo 10 Mbps
    readonly property int maxDown: Math.max(10000, Math.ceil(Math.max(NetPrio.totalDown, d.measured?.down ?? 0) * 2 / 1000) * 1000)
    readonly property int maxUp: Math.max(10000, Math.ceil(Math.max(NetPrio.totalUp, d.measured?.up ?? 0) * 2 / 1000) * 1000)

    function pct(share: int): int { return page.shareSum > 0 ? Math.round(share * 100 / page.shareSum) : 0; }
    function limitText(k: real): string { return k <= 0 ? "∞" : NetPrio.fmtKbitShort(k); }
    function speedText(s: var): string {
        return s ? "↓ " + SysInfo.fmtRate(s.down) + "   ↑ " + SysInfo.fmtRate(s.up) : "—";
    }
    function appIconFor(a: var): string {
        return ({ brave: "brave-browser", herdr: "utilities-terminal" })[a.id] ?? a.label.toLowerCase();
    }

    // ---------------------------------------------------------------- no instalado
    Group {
        shown: NetPrio.loaded && !NetPrio.installed
        help: I18n.t("Instálalo una vez en una terminal:") + "  sudo ~/.local/share/netprio/install.sh"
        OptionRow {
            title: I18n.t("netprio no está instalado")
            icon: "speed"
            iconColor: "#8E8E93"
        }
    }

    // ---------------------------------------------------------------- general
    Group {
        shown: NetPrio.installed
        help: NetPrio.error !== "" ? "⚠ " + NetPrio.error
            : !NetPrio.enabled ? I18n.t("Todas las apps comparten la red sin reglas.")
            : d.pending ? I18n.t("Esperando una conexión completa para medir la velocidad…")
            : I18n.t("Cuando varias apps usan la red a la vez, cada una recibe su parte; si solo una la usa, puede usarla toda (salvo su límite).")
        OptionRow {
            title: I18n.t("Ancho de banda por app")
            icon: "speed"
            iconColor: "#34C759"
            help: NetPrio.busy ? (NetPrio.busyCmd === "remeasure" || NetPrio.busyCmd === "enable" ? I18n.t("Midiendo la velocidad…") : I18n.t("Aplicando…"))
                : NetPrio.active ? I18n.t("Activo") + " · ↓ " + NetPrio.fmtKbit(NetPrio.totalDown) + "  ↑ " + NetPrio.fmtKbit(NetPrio.totalUp)
                : I18n.t("Inactivo")
            Toggle { checked: NetPrio.enabled; onToggled: c => NetPrio.run([c ? "enable" : "disable"]) }
        }
        OptionRow {
            title: I18n.t("Velocidad actual")
            Txt { text: "↓ " + SysInfo.fmtRate(SysInfo.netDown) + "   ↑ " + SysInfo.fmtRate(SysInfo.netUp); color: Theme.fgMuted; font.features: { "tnum": 1 } }
        }
        OptionRow {
            title: I18n.t("Mostrar la velocidad en la barra de menús")
            Toggle {
                checked: Settings.layout.topBar.showNetSpeed
                onToggled: c => Settings.setPath("layout.topBar.showNetSpeed", c)
            }
        }
    }

    // ---------------------------------------------------------------- tope total
    Group {
        shown: NetPrio.installed && NetPrio.enabled
        title: I18n.t("Velocidad total")
        help: page.manual ? I18n.t("Pon un poco menos de la velocidad real de la red para que la prioridad funcione.")
            : I18n.t("Se mide al conectarse y se usa el ") + (d.headroom ?? 90) + "% " + I18n.t("de lo medido.")
        OptionRow {
            title: I18n.t("Modo")
            Segmented {
                options: [{ v: "auto", t: I18n.t("Automático") }, { v: "manual", t: I18n.t("Manual") }]
                value: page.manual ? "manual" : "auto"
                onPicked: v => {
                    if (v === "auto") NetPrio.run(["set", "auto", "auto"]);
                    else NetPrio.run(["set", String(Math.max(256, NetPrio.totalDown)), String(Math.max(128, NetPrio.totalUp))]);
                }
            }
        }
        OptionRow {
            visible: page.manual
            title: I18n.t("Descarga")
            Slider {
                from: 256; to: page.maxDown; step: 64
                value: NetPrio.totalDown
                text: NetPrio.fmtKbitShort(value)
                onMoved: v => NetPrio.run(["set", String(Math.round(v)), String(NetPrio.totalUp)])
            }
        }
        OptionRow {
            visible: !page.manual
            title: I18n.t("Descarga")
            Txt { text: NetPrio.fmtKbit(NetPrio.totalDown); color: Theme.fgMuted }
        }
        OptionRow {
            visible: page.manual
            title: I18n.t("Subida")
            Slider {
                from: 128; to: page.maxUp; step: 64
                value: NetPrio.totalUp
                text: NetPrio.fmtKbitShort(value)
                onMoved: v => NetPrio.run(["set", String(NetPrio.totalDown), String(Math.round(v))])
            }
        }
        OptionRow {
            visible: !page.manual
            title: I18n.t("Subida")
            Txt { text: NetPrio.fmtKbit(NetPrio.totalUp); color: Theme.fgMuted }
        }
        OptionRow {
            visible: !page.manual
            title: I18n.t("Volver a medir")
            PillButton {
                text: NetPrio.busy && NetPrio.busyCmd === "remeasure" ? I18n.t("Midiendo…") : I18n.t("Medir")
                icon: "refresh"
                implicitHeight: 28
                enabled_: !NetPrio.busy
                onClicked: if (!NetPrio.busy) NetPrio.run(["remeasure"])
            }
        }
    }

    // ---------------------------------------------------------------- por app
    Repeater {
        model: NetPrio.enabled ? page.apps : []
        delegate: Group {
            id: appGroup
            required property var modelData
            readonly property var app: modelData
            title: app.label
            help: I18n.t("Reconoce: ") + app.globs.join(", ")

            OptionRow {
                title: appGroup.app.running.length > 0 ? I18n.t("En uso") : I18n.t("No se está ejecutando")
                appIcon: page.appIconFor(appGroup.app)
                help: appGroup.app.running.length > 0 ? page.speedText(NetPrio.speeds[appGroup.app.id]) : ""
                PillButton {
                    text: I18n.t("Quitar")
                    danger: true
                    implicitHeight: 28
                    onClicked: NetPrio.run(["app-del", appGroup.app.id])
                }
            }
            OptionRow {
                title: I18n.t("Prioridad")
                help: I18n.t("Al competir recibe ~") + page.pct(appGroup.app.share) + "% " + I18n.t("de la red")
                Slider {
                    from: 1; to: 100; step: 1
                    value: appGroup.app.share
                    text: String(Math.round(value))
                    minText: I18n.t("Baja"); maxText: I18n.t("Alta")
                    onMoved: v => NetPrio.setApp(Object.assign({}, appGroup.app, { share: v }))
                }
            }
            OptionRow {
                title: I18n.t("Límite de descarga")
                Slider {
                    from: 0; to: page.maxDown; step: 64
                    value: appGroup.app.limitDown
                    text: page.limitText(value)
                    onMoved: v => NetPrio.setApp(Object.assign({}, appGroup.app, { limitDown: v < 64 ? 0 : v }))
                }
            }
            OptionRow {
                title: I18n.t("Límite de subida")
                Slider {
                    from: 0; to: page.maxUp; step: 64
                    value: appGroup.app.limitUp
                    text: page.limitText(value)
                    onMoved: v => NetPrio.setApp(Object.assign({}, appGroup.app, { limitUp: v < 64 ? 0 : v }))
                }
            }
        }
    }

    // ---------------------------------------------------------------- el resto
    Group {
        shown: NetPrio.installed && NetPrio.enabled
        title: I18n.t("Otras apps")
        help: I18n.t("Todo lo que no está en la lista de arriba (terminales sueltas, servicios, contenedores…).")
        OptionRow {
            title: I18n.t("En uso")
            icon: "apps"
            iconColor: "#8E8E93"
            help: page.speedText(NetPrio.speeds._other)
        }
        OptionRow {
            title: I18n.t("Prioridad")
            help: I18n.t("Al competir recibe ~") + page.pct(d.otherShare ?? 0) + "% " + I18n.t("de la red")
            Slider {
                from: 1; to: 100; step: 1
                value: d.otherShare ?? 10
                text: String(Math.round(value))
                minText: I18n.t("Baja"); maxText: I18n.t("Alta")
                onMoved: v => NetPrio.run(["other-share", String(Math.round(v))])
            }
        }
    }

    // ---------------------------------------------------------------- añadir
    Group {
        shown: NetPrio.installed && NetPrio.enabled
        title: I18n.t("Añadir app")
        help: I18n.t("Apps abiertas que todavía no tienen regla. Ábrela primero si no sale aquí.")
        Repeater {
            model: d.candidates ?? []
            OptionRow {
                required property var modelData
                title: modelData.label
                help: modelData.glob
                appIcon: modelData.label.toLowerCase()
                PillButton {
                    text: I18n.t("Añadir")
                    icon: "add"
                    implicitHeight: 28
                    enabled_: (page.apps.length) < 14
                    onClicked: NetPrio.addApp(modelData.label, modelData.glob)
                }
            }
        }
        OptionRow {
            visible: (d.candidates ?? []).length === 0
            title: I18n.t("No hay otras apps abiertas")
        }
    }
}
