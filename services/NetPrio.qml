pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Ancho de banda por app (netprio, ~/.local/share/netprio): lee el estado con `netprio json`
// y cambia la configuración con `pkexec netprio …` (la regla de polkit no pide contraseña
// en la sesión activa). Solo consulta mientras alguien lo usa (`users`).
Singleton {
    id: root

    property int users: 0
    property var data: ({})
    property bool loaded: false
    readonly property bool installed: data.installed === true && data.apps !== undefined
    readonly property bool enabled: installed && data.enabled === true
    readonly property bool active: installed && data.active === true

    // id de app → { down, up } en bytes/s; "_other" = el resto
    property var speeds: ({})
    property var _prev: null

    property bool busy: false
    property string busyCmd: ""
    property string error: ""
    property var _queue: []

    // tope total en kbit (el aplicado; si no, el medido)
    readonly property int totalDown: data.rates?.down ?? data.measured?.down ?? 0
    readonly property int totalUp: data.rates?.up ?? data.measured?.up ?? 0

    function refresh(): void {
        if (!poll.running) poll.running = true;
    }

    // Ejecuta `netprio <args>` como root; los cambios van en cola para no pisarse
    function run(args: var): void {
        root._queue = root._queue.concat([args]);
        if (!act.running) root._next();
    }
    function _next(): void {
        if (root._queue.length === 0) { root.busy = false; root.busyCmd = ""; return; }
        const a = root._queue[0];
        root._queue = root._queue.slice(1);
        root.busy = true;
        root.busyCmd = a[0];
        act.command = ["sh", "-c", "pkexec /usr/local/bin/netprio \"$@\" 2>&1; echo \"__rc=$?\"", "sh"].concat(a);
        act.running = true;
    }

    function setApp(app: var): void {
        root.run(["app-set", JSON.stringify({
            id: app.id, label: app.label, globs: app.globs,
            share: Math.round(app.share), limitDown: Math.round(app.limitDown), limitUp: Math.round(app.limitUp)
        })]);
    }
    function addApp(label: string, glob: string): void {
        let base = label.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 26) || "app";
        let id = base, n = 2;
        while ((root.data.apps ?? []).some(a => a.id === id)) id = base + "-" + n++;
        root.setApp({ id: id, label: label, globs: [glob], share: 20, limitDown: 0, limitUp: 0 });
    }

    // kbit → «3.9 Mbps» / «800 kbps»
    function fmtKbit(k: real): string {
        return k >= 1000 ? (k / 1000).toFixed(k >= 10000 ? 0 : 1) + " Mbps" : Math.round(k) + " kbps";
    }
    function fmtKbitShort(k: real): string {
        return k >= 1000 ? (k / 1000).toFixed(k >= 10000 ? 0 : 1) + "M" : Math.round(k) + "k";
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.users > 0
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: poll
        command: ["/usr/local/bin/netprio", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { d = { installed: false }; }
                const p = root._prev;
                if (d.apps && p && p.apps && d.time > p.time) {
                    const dt = d.time - p.time, sp = {};
                    const rate = (a, b) => Math.max(0, (a - b) / dt);
                    for (const a of d.apps) {
                        const o = p.apps.find(x => x.id === a.id);
                        if (o) sp[a.id] = { down: rate(a.rxBytes, o.rxBytes), up: rate(a.txBytes, o.txBytes) };
                    }
                    sp._other = { down: rate(d.other.rxBytes, p.other.rxBytes), up: rate(d.other.txBytes, p.other.txBytes) };
                    root.speeds = sp;
                }
                root._prev = d;
                root.data = d;
                root.loaded = true;
            }
        }
    }

    Process {
        id: act
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/__rc=(\d+)\s*$/);
                const rc = m ? parseInt(m[1]) : 1;
                const out = text.replace(/__rc=\d+\s*$/, "").trim();
                // 126/127: pkexec cancelado o sin permiso
                root.error = rc === 0 ? "" : (out.split("\n").filter(l => l.trim()).pop() ?? ("pkexec: " + rc));
                root.refresh();
                root._next();
            }
        }
    }
}
