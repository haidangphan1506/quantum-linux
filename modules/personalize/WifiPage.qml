import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Wi-Fi como en Ajustes del Sistema de macOS: interruptor, la red conectada con sus
// «Detalles…» (IP, router, DNS, MAC, olvidar), «Redes conocidas» y «Otras redes»
// (la contraseña se escribe en la misma fila).
ColumnLayout {
    id: page
    spacing: 16

    Component.onCompleted: Net.startScan()
    Component.onDestruction: if (!Shell.wifiPage) Net.stopScanLater()

    readonly property var current: Net.networks.find(n => n.connected) ?? null

    // Las listas NO son bindings: con ~80 redes, cada cambio de señal de cualquiera volvía a
    // filtrar/ordenar y el Repeater recreaba todas las filas (CPU ~100 % y ~1 s de retraso al
    // entrar o salir). Se recalculan cada 2 s y solo se reemplazan si cambian las redes o el orden.
    property var known: []
    property var others: []
    property int hiddenCount: 0
    property bool showAll: false
    readonly property int maxOthers: showAll ? 60 : 10   // pocas filas al abrir: crear/destruir cada una cuesta
    function sameList(a: var, b: var): bool {
        if (a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
        return true;
    }
    function refreshLists(): void {
        const bySignal = (a, b) => Net.signalOf(b) - Net.signalOf(a);
        const all = Net.networks;
        const k = all.filter(n => n.known && !n.connected).sort(bySignal);
        const oAll = all.filter(n => !n.known && !n.connected && n.name).sort(bySignal);
        const o = oAll.slice(0, maxOthers);
        hiddenCount = oAll.length - o.length;
        if (!sameList(k, known)) known = k;
        if (!sameList(o, others)) others = o;
    }
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: page.refreshLists()
    }
    property bool details: false
    property var info: ({})

    function bars(net: var): string {
        const s = Net.signalOf(net);
        return s > 75 ? "signal_wifi_4_bar" : s > 50 ? "network_wifi_3_bar" : s > 25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
    }
    function loadInfo(): void { infoProc.running = true; }
    Process {
        id: infoProc
        command: ["sh", "-c", "d=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2==\"wifi\"{print $1; exit}'); [ -n \"$d\" ] && nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,GENERAL.HWADDR device show \"$d\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) {
                    const i = l.indexOf(":");
                    if (i < 0) continue;
                    const k = l.slice(0, i).replace(/\[\d+\]/, ""), v = l.slice(i + 1).replace(/\\:/g, ":");
                    if (!o[k]) o[k] = v; else o[k] += ", " + v;
                }
                page.info = o;
            }
        }
    }
    function forget(ssid: string): void {
        Quickshell.execDetached(["nmcli", "connection", "delete", "id", ssid]);
        page.details = false;
    }

    Group {
        help: !Net.hasDevice ? I18n.t("No se encontró un adaptador Wi-Fi") : ""
        OptionRow {
            title: "Wi-Fi"
            icon: "wifi"
            iconColor: "#007AFF"
            Toggle { checked: Net.wifiEnabled; onToggled: Net.toggleWifi() }
        }
        OptionRow {
            visible: Net.wifiEnabled && page.current !== null
            title: page.current?.name ?? ""
            help: "● " + I18n.t("Conectado")
            RowLayout {
                spacing: 8
                Icon { visible: page.current && Net.securityKind(page.current) !== "open"; text: "lock"; size: 16; color: Theme.fgMuted }
                Icon { text: page.current ? page.bars(page.current) : "wifi"; size: 18 }
                PillButton {
                    text: page.details ? I18n.t("Ocultar") : I18n.t("Detalles…")
                    implicitHeight: 28
                    onClicked: { page.details = !page.details; if (page.details) page.loadInfo(); }
                }
            }
        }
        OptionRow { visible: page.details && !!page.current; title: I18n.t("Dirección IP"); Txt { text: (page.info["IP4.ADDRESS"] ?? "—"); color: Theme.fgMuted } }
        OptionRow { visible: page.details && !!page.current; title: I18n.t("Router"); Txt { text: page.info["IP4.GATEWAY"] || "—"; color: Theme.fgMuted } }
        OptionRow { visible: page.details && !!page.current; title: "DNS"; Txt { text: page.info["IP4.DNS"] || "—"; color: Theme.fgMuted; elide: Text.ElideRight; width: Math.min(implicitWidth, 320) } }
        OptionRow { visible: page.details && !!page.current; title: I18n.t("Dirección MAC"); Txt { text: page.info["GENERAL.HWADDR"] || "—"; color: Theme.fgMuted } }
        OptionRow {
            visible: page.details && !!page.current
            title: ""
            RowLayout {
                spacing: 8
                PillButton { text: I18n.t("Desconectar"); implicitHeight: 28; onClicked: { Net.disconnect(page.current.name); page.details = false; } }
                PillButton { text: I18n.t("Olvidar esta red…"); danger: true; implicitHeight: 28; onClicked: page.forget(page.current.name) }
            }
        }
    }

    Group {
        visible: Net.wifiEnabled && page.known.length > 0
        title: I18n.t("Redes conocidas")
        Repeater { model: page.known; delegate: WifiNetRow {} }
    }

    Group {
        visible: Net.wifiEnabled
        title: I18n.t("Otras redes")
        help: Net.status !== "" ? Net.status : ""
        Repeater { model: page.others; delegate: WifiNetRow {} }
        OptionRow {
            visible: page.hiddenCount > 0 || page.showAll
            title: page.showAll ? I18n.t("Mostrar menos") : I18n.t("Mostrar más") + " (" + page.hiddenCount + ")"
            PillButton {
                text: page.showAll ? I18n.t("Menos") : I18n.t("Más")
                implicitHeight: 28
                onClicked: { page.showAll = !page.showAll; page.refreshLists(); }
            }
        }
        OptionRow {
            visible: page.others.length === 0
            title: Net.scanning ? I18n.t("Buscando redes…") : I18n.t("No hay otras redes")
            PillButton { text: I18n.t("Buscar"); icon: "refresh"; implicitHeight: 28; onClicked: Net.startScan() }
        }
    }
}
