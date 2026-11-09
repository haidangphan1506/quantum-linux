//@ pragma UseQApplication
//@ pragma IconTheme MacTahoe
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Idioma: el mismo diccionario que Quantum Shell (i18n/strings.js), según ui.lang de settings.json
import "i18n/strings.js" as Strings

// Quantum Task Manager: như Task Manager của Windows, viết bằng Quickshell.
// Số liệu: collector.py (1 dòng JSON / giây). Mở: quantum-taskmgr  (Ctrl+Shift+Esc)
ShellRoot {
    id: app

    // ------------------------------------------------------------------ theme
    // Màu theo theme của Quantum Shell (~/.local/state/quantum/colors.json), tự đổi sáng/tối
    property var c: ({})
    readonly property bool dark: (c.mode ?? "dark") !== "light"
    readonly property color bg: c.surface ?? (dark ? "#16181d" : "#f8f9fc")
    readonly property color panel: c.surface_container_low ?? (dark ? "#1d2026" : "#f1f3f7")
    readonly property color card: c.surface_container ?? (dark ? "#23262d" : "#ebedf1")
    readonly property color hi: c.surface_container_high ?? (dark ? "#2c3038" : "#e3e5ea")
    readonly property color fg: c.on_surface ?? (dark ? "#e3e4e8" : "#191c1e")
    readonly property color muted: c.on_surface_variant ?? (dark ? "#a0a4ad" : "#5c6168")
    readonly property color line: c.outline_variant ?? (dark ? "#3a3e46" : "#c9ccd2")
    readonly property color accent: c.primary ?? "#4f8cff"
    readonly property color onAccent: c.on_primary ?? "#ffffff"
    // màu riêng từng loại (giống Windows: CPU xanh, RAM tím, đĩa xanh lá, mạng cam, GPU hồng)
    readonly property color cCpu: accent
    readonly property color cMem: c.tertiary ?? "#a855f7"
    readonly property color cDisk: "#2fa36b"
    readonly property color cNet: "#e3891c"
    readonly property color cGpu: "#e0457b"
    readonly property string uiFont: "Inter"
    readonly property string iconFont: "Material Symbols Rounded"

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quantum/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { app.c = JSON.parse(text()); } catch (e) {} }
    }

    // ------------------------------------------------------------------ idioma
    property string lang: "vi"
    // Texto en español (clave) → traducción según el idioma; sin traducción, el propio texto
    function tr(s: string): string {
        const d = app.lang === "en" ? Strings.en : Strings.vi;
        return d[s] ?? s;
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/quantum/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { app.lang = JSON.parse(text()).ui?.lang === "en" ? "en" : "vi"; } catch (e) {} }
    }

    // ------------------------------------------------------------------ dữ liệu
    property var d: null           // muestra actual
    property var st: null          // datos estáticos (modelo de CPU, discos...)
    property int interval: 1000
    property bool paused: false
    readonly property int histLen: 60
    property var hCpu: []
    property var hCores: []
    property var hMem: []
    property var hDisk: ({})       // name -> {busy:[], read:[], write:[]}
    property var hNet: ({})        // name -> {rx:[], tx:[]}
    property var hGpu: []
    property int ticks: 0
    property int nproc: 0          // último valor conocido (en Rendimiento se cuenta cada 5 s)
    property int nthreads: 0

    function push(arr: var, v: real): var {
        const a = arr.slice(arr.length >= histLen ? 1 : 0);
        a.push(v);
        return a;
    }

    function ingest(s: var): void {
        if (paused) return;
        if (s.static) st = s.static;
        hCpu = push(hCpu, s.cpu.total);
        const cores = s.cpu.cores.map((v, i) => push(hCores[i] ?? [], v));
        hCores = cores;
        hMem = push(hMem, 100 * s.mem.used / Math.max(1, s.mem.total));
        const hd = {};
        for (const k of s.disks) {
            const o = hDisk[k.name] ?? { busy: [], read: [], write: [] };
            hd[k.name] = { busy: push(o.busy, k.busy), read: push(o.read, k.read), write: push(o.write, k.write) };
        }
        hDisk = hd;
        const hn = {};
        for (const n of s.net) {
            const o = hNet[n.name] ?? { rx: [], tx: [], info: null };
            hn[n.name] = { rx: push(o.rx, n.rx), tx: push(o.tx, n.tx), info: n.info ?? o.info };
        }
        hNet = hn;
        if (s.gpu) hGpu = push(hGpu, s.gpu.busy);
        if (s.procs && s.procs.length) procs.update(s.procs);
        if (s.nproc) { nproc = s.nproc; nthreads = s.nthreads; }
        d = s;
        ticks++;
    }

    Process {
        id: collector
        running: true
        stdinEnabled: true
        command: ["python3", "-I", Quickshell.shellDir + "/collector.py"]
        stdout: SplitParser {
            onRead: line => { try { app.ingest(JSON.parse(line)); } catch (e) { console.warn("taskmgr:", e); } }
        }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 1500; onTriggered: collector.running = true }
    function send(cmd: string): void { if (collector.running) collector.write(cmd + "\n"); }
    onIntervalChanged: send("interval " + (interval / 1000))

    // ------------------------------------------------------------------ dispositivos (Rendimiento)
    readonly property string devKey: {
        if (!d) return "";
        const ids = ["cpu", "mem"];
        for (const k of d.disks) ids.push("disk:" + k.name);
        for (const n of d.net) { const h = hNet[n.name]; if (h && (h.info?.up ?? true)) ids.push("net:" + n.name); }
        if (d.gpu) ids.push("gpu");
        return ids.join(",");
    }
    function devInfo(id: string, _tick: int): var {
        const e = { t: id, s: "", h: [], max: 100, col: accent };
        if (!d) return e;
        if (id === "cpu") return { t: "CPU", col: cCpu, h: hCpu, max: 100,
            s: Math.round(d.cpu.total) + "%  " + d.cpu.freq.toFixed(2) + " GHz" + (d.cpu.temp ? "  (" + Math.round(d.cpu.temp) + "°C)" : "") };
        if (id === "mem") return { t: tr("Memoria"), col: cMem, h: hMem, max: 100,
            s: fmtBytes(d.mem.used, 1) + " / " + fmtBytes(d.mem.total, 1) + "  (" + Math.round(100 * d.mem.used / d.mem.total) + "%)" };
        if (id === "gpu" && d.gpu) return { t: "GPU", col: cGpu, h: hGpu, max: 100,
            s: d.gpu.busy + "%" + (d.gpu.temp ? "  (" + Math.round(d.gpu.temp) + "°C)" : "") };
        if (id.startsWith("disk:")) {
            const n = id.slice(5), k = d.disks.find(x => x.name === n) ?? { busy: 0 }, h = hDisk[n];
            return { t: tr("Disco (") + n + ")", col: cDisk, h: h ? h.busy : [], max: 100, s: "SSD  " + Math.round(k.busy) + "%" };
        }
        if (id.startsWith("net:")) {
            const n = id.slice(4), x = d.net.find(v => v.name === n) ?? { rx: 0, tx: 0 }, h = hNet[n] ?? { rx: [], tx: [], info: null };
            return { t: (h.info?.kind ?? tr("Red")) + " (" + n + ")", col: cNet, h: h.rx.map((v, i) => v + (h.tx[i] ?? 0)), max: 0,
                     s: "↓ " + fmtRate(x.rx) + "  ↑ " + fmtRate(x.tx) };
        }
        return e;
    }

    // ------------------------------------------------------------------ formato
    function fmtBytes(b: real, dec: int): string {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return b.toFixed(i === 0 ? 0 : (dec ?? 1)) + " " + u[i];
    }
    function fmtRate(b: real): string {
        if (b < 1024) return Math.round(b * 8) + " bps";
        const kbps = b * 8 / 1000;
        if (kbps < 1000) return kbps.toFixed(0) + " Kbps";
        return (kbps / 1000).toFixed(1) + " Mbps";
    }
    function fmtDiskRate(b: real): string { return fmtBytes(b, 1) + "/s"; }
    function fmtUptime(s: real): string {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), x = Math.floor(s % 60);
        const p = n => (n < 10 ? "0" : "") + n;
        return d + ":" + p(h) + ":" + p(m) + ":" + p(x);
    }

    // ------------------------------------------------------------------ tiến trình
    QtObject {
        id: procs
        property var raw: []
        property string sortKey: "cpu"
        property bool desc: true
        property bool grouped: true
        property string filter: ""
        property var expanded: ({})
        property var selKey: null            // pid (int) o "g:<name>"
        property real totCpu: 0
        property real totMem: 0

        function keyOf(r: var): var { return r.group ? "g:" + r.name : r.pid; }

        function update(list: var): void { raw = list; rebuild(); }

        function rebuild(): void {
            const f = filter.toLowerCase();
            let list = raw;
            if (f) list = list.filter(p => p.name.toLowerCase().includes(f) || String(p.pid).includes(f) || p.cmd.toLowerCase().includes(f));
            totCpu = raw.reduce((s, p) => s + p.cpu, 0);
            totMem = raw.reduce((s, p) => s + p.mem, 0);
            const cmp = (a, b) => {
                const x = a[sortKey], y = b[sortKey];
                const r = typeof x === "string" ? x.localeCompare(y) : (x - y);
                return desc ? -r : r;
            };
            let rows = [];
            if (grouped) {
                const g = {};
                for (const p of list) {
                    const o = g[p.name] ?? (g[p.name] = { group: true, name: p.name, cpu: 0, mem: 0, threads: 0, pid: p.pid, user: p.user, state: "", cmd: p.cmd, kids: [] });
                    o.cpu += p.cpu; o.mem += p.mem; o.threads += p.threads; o.kids.push(p);
                    if (p.pid < o.pid) { o.pid = p.pid; o.cmd = p.cmd; }
                }
                const groups = Object.values(g).sort(cmp);
                for (const o of groups) {
                    o.count = o.kids.length;
                    o.cpu = Math.round(o.cpu * 10) / 10;
                    rows.push(o);
                    if (o.count > 1 && expanded[o.name])
                        for (const k of o.kids.slice().sort(cmp)) rows.push(Object.assign({ child: true }, k));
                }
            } else {
                rows = list.slice().sort(cmp);
            }
            sync(rows);
        }

        // actualiza el ListModel en el sitio (no salta el scroll)
        function sync(rows: var): void {
            const n = rows.length;
            for (let i = 0; i < n; i++) {
                const r = rows[i];
                const o = {
                    name: r.name, pid: r.pid, cpu: r.cpu, mem: r.mem, threads: r.threads, user: r.user ?? "",
                    state: r.state ?? "", cmd: r.cmd ?? "", group: !!r.group, child: !!r.child, count: r.count ?? 1,
                    pids: r.group ? r.kids.map(k => k.pid).join(",") : String(r.pid)
                };
                if (i < model.count) model.set(i, o); else model.append(o);
            }
            if (model.count > n) model.remove(n, model.count - n);
        }

        property ListModel model: ListModel {}

        // ---- columnas: orden y ancho (kéo thả en el encabezado), guardados en ~/.config/quantum/taskmgr.json
        readonly property var titles: ({ name: tr("Nombre"), pid: "PID", user: tr("Usuario"), threads: tr("Hilos"), cpu: "CPU", mem: tr("Memoria") })
        readonly property var defaultW: ({ name: 0, pid: 80, user: 120, threads: 70, cpu: 90, mem: 110 })
        property var order: ["name", "pid", "user", "threads", "cpu", "mem"]
        property var widths: Object.assign({}, defaultW)
        readonly property string orderKey: order.join(",")
        function setW(key: string, w: real): void {
            const o = Object.assign({}, widths);
            o[key] = Math.round(Math.max(key === "name" ? 160 : 50, Math.min(900, w)));
            widths = o;
            saveTimer.restart();
        }
        function resetW(key: string): void {
            const o = Object.assign({}, widths);
            o[key] = defaultW[key];
            widths = o;
            saveTimer.restart();
        }
        function move(from: int, to: int): void {
            if (from === to) return;
            const o = order.slice();
            const [k] = o.splice(from, 1);
            o.splice(to, 0, k);
            order = o;
            saveTimer.restart();
        }
    }
    FileView {
        id: colsFile
        path: Quickshell.env("HOME") + "/.config/quantum/taskmgr.json"
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                const known = Object.keys(procs.defaultW);
                if (Array.isArray(j.order) && j.order.length === known.length && known.every(k => j.order.includes(k))) procs.order = j.order;
                if (j.widths) procs.widths = Object.assign({}, procs.defaultW, j.widths);
            } catch (e) {}
        }
    }
    Timer {
        id: saveTimer
        interval: 600
        onTriggered: colsFile.setText(JSON.stringify({ order: procs.order, widths: procs.widths }, null, 2) + "\n")
    }

    function killPids(pids: string, force: bool): void {
        if (!pids) return;
        Quickshell.execDetached(["kill", force ? "-KILL" : "-TERM"].concat(pids.split(",")));
    }
    function copy(text: string): void { Quickshell.execDetached(["wl-copy", text]); }

    // ------------------------------------------------------------------ componentes
    component Ico: Text {
        property int size: 18
        property real fill: 0
        font.family: app.iconFont
        font.pixelSize: size
        font.variableAxes: ({ "FILL": fill, "opsz": 24, "wght": 400 })
        color: app.fg
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
    component T: Text {
        font.family: app.uiFont
        font.pixelSize: 13
        color: app.fg
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    // Biểu đồ: đường + vùng tô, lưới mờ. values 0..max (max 0 = tự co theo dữ liệu)
    component Graph: Canvas {
        id: g
        property var values: []
        property var values2: null       // segunda serie (p. ej. escritura / envío), punteada
        property color color: app.accent
        property real max: 100
        property bool grid: true
        property bool fillArea: true
        readonly property real ymax: {
            if (max > 0) return max;
            let m = 1;
            for (const v of values) m = Math.max(m, v);
            if (values2) for (const v of values2) m = Math.max(m, v);
            return m * 1.15;
        }
        onValuesChanged: requestPaint()
        onColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        renderStrategy: Canvas.Cooperative

        function series(ctx, vals, dashed) {
            const n = app.histLen, w = width, h = height;
            if (!vals || vals.length < 2) return;
            const off = n - vals.length;
            const X = i => (off + i) / (n - 1) * w;
            const Y = v => h - Math.min(1, v / ymax) * (h - 2) - 1;
            ctx.beginPath();
            ctx.moveTo(X(0), Y(vals[0]));
            for (let i = 1; i < vals.length; i++) ctx.lineTo(X(i), Y(vals[i]));
            ctx.setLineDash(dashed ? [4, 3] : []);
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = g.color;
            ctx.stroke();
            if (fillArea && !dashed) {
                ctx.lineTo(X(vals.length - 1), h);
                ctx.lineTo(X(0), h);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(g.color.r, g.color.g, g.color.b, 0.16);
                ctx.fill();
            }
        }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (grid) {
                ctx.strokeStyle = Qt.rgba(g.color.r, g.color.g, g.color.b, 0.13);
                ctx.lineWidth = 1;
                for (let i = 1; i < 10; i++) { const x = Math.round(width * i / 10) + 0.5; ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke(); }
                for (let i = 1; i < 5; i++) { const y = Math.round(height * i / 5) + 0.5; ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }
            }
            series(ctx, values, false);
            if (values2) series(ctx, values2, true);
        }
        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(g.color.r, g.color.g, g.color.b, 0.45) }
    }

    // Dato de rendimiento: etiqueta pequeña + valor grande
    component Stat: ColumnLayout {
        property string label
        property string value
        property bool big: true
        spacing: 0
        T { text: parent.label; color: app.muted; font.pixelSize: 12 }
        T { text: parent.value; font.pixelSize: parent.big ? 20 : 14; font.weight: Font.Medium }
    }
    component KV: RowLayout {
        property string k
        property string v
        spacing: 12
        T { text: parent.k; color: app.muted; Layout.preferredWidth: 150 }
        T { text: parent.v; Layout.fillWidth: true }
    }

    component Header: RowLayout {
        property string title
        property string sub
        Layout.fillWidth: true
        T { text: parent.title; font.pixelSize: 24; font.weight: Font.DemiBold }
        Item { Layout.fillWidth: true }
        T { text: parent.sub; font.pixelSize: 14; color: app.muted; Layout.maximumWidth: 420 }
    }
    component Caption: RowLayout {
        property string ltext
        property string rtext
        Layout.fillWidth: true
        T { text: parent.ltext; color: app.muted; font.pixelSize: 12 }
        Item { Layout.fillWidth: true }
        T { text: parent.rtext; color: app.muted; font.pixelSize: 12 }
    }


    // qs -p .../taskmgr/shell.qml ipc call taskmgr page procs|perf  ·  perf cpu|mem|gpu|disk:nvme0n1|net:wlan0
    IpcHandler {
        target: "taskmgr"
        function page(p: string): void { win.page = p; }
        function perf(sel: string): void { win.page = "perf"; win.perfSel = sel; }
        function cores(on: bool): void { win.perCore = on; }
        function colmove(from: int, to: int): void { procs.move(from, to); }       // = kéo tiêu đề cột
        function colwidth(key: string, w: int): void { procs.setW(key, w); }      // = kéo mép cột
        function colauto(key: string): void { procs.resetW(key); }                // = doble clic en el borde
        function colreset(): void { procs.order = ["name", "pid", "user", "threads", "cpu", "mem"]; procs.widths = Object.assign({}, procs.defaultW); saveTimer.restart(); }
    }

    // ------------------------------------------------------------------ ventana
    FloatingWindow {
        id: win
        title: "Trình quản lý tác vụ"
        implicitWidth: 1120
        implicitHeight: 740
        minimumSize: Qt.size(820, 520)
        color: app.bg
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()

        property string page: "procs"     // procs | perf
        property string perfSel: "cpu"     // cpu | mem | disk:<n> | net:<n> | gpu
        property bool perCore: false
        onPageChanged: app.send("procs " + (page === "procs" ? "on" : "off"))

        Shortcut { sequence: "Ctrl+F"; onActivated: { win.page = "procs"; search.forceActiveFocus(); } }
        Shortcut { sequence: "Delete"; onActivated: endBtn.clicked() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ------------------------------------------------ barra lateral
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 210
                color: app.panel

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.margins: 8
                        Layout.bottomMargin: 14
                        spacing: 10
                        IconImage { implicitSize: 26; source: Quickshell.iconPath("utilities-system-monitor", true) }
                        T { text: tr("Administrador de tareas"); font.pixelSize: 15; font.weight: Font.DemiBold }
                    }

                    Repeater {
                        model: [
                            { id: "procs", icon: "apps", text: tr("Procesos") },
                            { id: "perf", icon: "monitoring", text: tr("Rendimiento") }
                        ]
                        Rectangle {
                            id: nav
                            required property var modelData
                            readonly property bool on: win.page === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: 8
                            color: on ? app.hi : navMouse.containsMouse ? Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.05) : "transparent"
                            Rectangle {
                                visible: nav.on
                                width: 3; height: 18; radius: 2
                                anchors.left: parent.left; anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: app.accent
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                spacing: 12
                                Ico { text: nav.modelData.icon; fill: nav.on ? 1 : 0; color: nav.on ? app.accent : app.fg }
                                T { text: nav.modelData.text; Layout.fillWidth: true; font.weight: nav.on ? Font.DemiBold : Font.Normal }
                            }
                            MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.page = nav.modelData.id }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // tốc độ cập nhật
                    T { text: tr("Velocidad de actualización"); color: app.muted; font.pixelSize: 12; Layout.leftMargin: 8 }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        spacing: 4
                        Repeater {
                            model: [{ t: tr("Rápido"), v: 500 }, { t: tr("Normal"), v: 1000 }, { t: tr("Lento"), v: 3000 }]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: app.interval === modelData.v && !app.paused
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 6
                                color: on ? app.accent : app.card
                                T { anchors.centerIn: parent; text: parent.modelData.t; font.pixelSize: 12; color: parent.on ? app.onAccent : app.fg }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { app.paused = false; app.interval = parent.modelData.v; } }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        implicitHeight: 28
                        radius: 6
                        color: app.paused ? app.accent : app.card
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Ico { text: app.paused ? "play_arrow" : "pause"; size: 16; color: app.paused ? app.onAccent : app.fg }
                            T { text: app.paused ? tr("Reanudar") : tr("Pausar"); font.pixelSize: 12; color: app.paused ? app.onAccent : app.fg }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.paused = !app.paused }
                    }
                    T {
                        Layout.leftMargin: 8
                        Layout.topMargin: 6
                        color: app.muted
                        font.pixelSize: 11
                        text: app.d ? (tr("Activo ") + app.fmtUptime(app.d.uptime)) : tr("Cargando…")
                    }
                }
            }

            // ------------------------------------------------ contenido
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ============================== TIẾN TRÌNH
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: win.page === "procs"
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        T { text: tr("Procesos"); font.pixelSize: 20; font.weight: Font.DemiBold }
                        T { text: app.nproc ? (app.nproc + tr(" procesos · ") + app.nthreads + tr(" hilos")) : ""; color: app.muted }
                        Item { Layout.fillWidth: true }
                        // tìm kiếm
                        Rectangle {
                            implicitWidth: 260
                            implicitHeight: 34
                            radius: 8
                            color: app.card
                            border.width: search.activeFocus ? 2 : 1
                            border.color: search.activeFocus ? app.accent : app.line
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 6
                                Ico { text: "search"; size: 18; color: app.muted }
                                TextInput {
                                    id: search
                                    Layout.fillWidth: true
                                    font.family: app.uiFont
                                    font.pixelSize: 13
                                    color: app.fg
                                    selectionColor: app.accent
                                    clip: true
                                    onTextChanged: { procs.filter = text; procs.rebuild(); }
                                    Keys.onEscapePressed: text = ""
                                    T { visible: !search.text; text: tr("Buscar nombre, PID, comando…  (Ctrl+F)"); color: app.muted; anchors.verticalCenter: parent.verticalCenter }
                                }
                                Ico { visible: search.text; text: "close"; size: 16; color: app.muted; MouseArea { anchors.fill: parent; onClicked: search.text = "" } }
                            }
                        }
                        // gộp theo ứng dụng
                        Rectangle {
                            implicitWidth: grpRow.implicitWidth + 20
                            implicitHeight: 34
                            radius: 8
                            color: procs.grouped ? app.hi : app.card
                            border.width: 1
                            border.color: app.line
                            RowLayout {
                                id: grpRow
                                anchors.centerIn: parent
                                spacing: 6
                                Ico { text: procs.grouped ? "account_tree" : "list"; size: 18 }
                                T { text: procs.grouped ? tr("Agrupar por app") : tr("Lista plana") }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { procs.grouped = !procs.grouped; procs.rebuild(); } }
                        }
                        // kết thúc tác vụ
                        Rectangle {
                            id: endBtnRect
                            readonly property bool can: procs.selKey !== null
                            implicitWidth: endRow.implicitWidth + 24
                            implicitHeight: 34
                            radius: 8
                            color: can ? (endMouse.containsMouse ? Qt.darker(app.accent, 1.1) : app.accent) : app.card
                            opacity: can ? 1 : 0.6
                            RowLayout {
                                id: endRow
                                anchors.centerIn: parent
                                spacing: 6
                                Ico { text: "block"; size: 18; color: endBtnRect.can ? app.onAccent : app.muted }
                                T { text: tr("Terminar tarea"); color: endBtnRect.can ? app.onAccent : app.muted; font.weight: Font.Medium }
                            }
                            MouseArea {
                                id: endMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: endBtnRect.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: endBtn.clicked()
                            }
                        }
                        QtObject {
                            id: endBtn
                            signal clicked
                            onClicked: {
                                const r = list.selRow();
                                if (r) app.killPids(r.pids, false);
                            }
                        }
                    }

                    // tabla: columnas con ancho/orden ajustables (arrastrar en el encabezado)
                    Rectangle {
                        id: tbl
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: app.panel
                        border.width: 1
                        border.color: app.line
                        clip: true

                        readonly property int pad: 14
                        // «Tên» con ancho 0 = automático (llena lo que sobra)
                        readonly property real othersW: procs.order.reduce((s, k) => s + (k === "name" ? 0 : procs.widths[k]), 0)
                        function colW(key: string): real {
                            if (key === "name" && !procs.widths.name)
                                return Math.max(220, hflick.width - 2 * pad - othersW);
                            return procs.widths[key];
                        }
                        readonly property real totalW: procs.order.reduce((s, k) => s + colW(k), 0) + 2 * pad
                        function colX(idx: int): real {
                            let x = pad;
                            for (let i = 0; i < idx; i++) x += colW(procs.order[i]);
                            return x;
                        }
                        // arrastre de columna
                        property string dragKey: ""
                        property real dragX: 0
                        readonly property int dropIdx: {
                            if (!dragKey) return -1;
                            let x = pad;
                            for (let i = 0; i < procs.order.length; i++) {
                                const w = colW(procs.order[i]);
                                if (dragX < x + w / 2) return i;
                                x += w;
                            }
                            return procs.order.length;
                        }

                        Flickable {
                            id: hflick
                            anchors.fill: parent
                            contentWidth: Math.max(width, tbl.totalW)
                            contentHeight: height
                            interactive: false
                            clip: true
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                            // rueda/touchpad horizontal (o Shift+rueda) = desplazar columnas
                            WheelHandler {
                                acceptedModifiers: Qt.ShiftModifier
                                onWheel: e => hflick.contentX = Math.max(0, Math.min(hflick.contentWidth - hflick.width, hflick.contentX - e.angleDelta.y / 2))
                            }
                            WheelHandler {
                                orientation: Qt.Horizontal
                                onWheel: e => hflick.contentX = Math.max(0, Math.min(hflick.contentWidth - hflick.width, hflick.contentX - e.angleDelta.x / 2))
                            }

                            Column {
                                width: hflick.contentWidth
                                height: hflick.height

                                // ---------------- encabezado
                                Rectangle {
                                    id: header
                                    width: parent.width
                                    height: 46
                                    color: app.card

                                    Repeater {
                                        model: procs.orderKey.split(",")
                                        Item {
                                            id: hd
                                            required property string modelData
                                            required property int index
                                            readonly property bool on: procs.sortKey === modelData
                                            readonly property bool alignLeft: modelData === "name"
                                            readonly property bool dragging: tbl.dragKey === modelData
                                            x: tbl.colX(index)
                                            width: tbl.colW(modelData)
                                            height: header.height
                                            opacity: dragging ? 0.35 : 1

                                            // tiêu đề + tổng (CPU / RAM)
                                            Column {
                                                anchors.left: hd.alignLeft ? parent.left : undefined
                                                anchors.right: hd.alignLeft ? undefined : parent.right
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 0
                                                T {
                                                    anchors.right: hd.alignLeft ? undefined : parent.right
                                                    visible: hd.modelData === "cpu" || hd.modelData === "mem"
                                                    font.pixelSize: 15
                                                    font.weight: Font.DemiBold
                                                    text: !app.d ? "" : hd.modelData === "cpu" ? Math.round(app.d.cpu.total) + "%"
                                                          : Math.round(100 * app.d.mem.used / app.d.mem.total) + "%"
                                                }
                                                Row {
                                                    anchors.right: hd.alignLeft ? undefined : parent.right
                                                    spacing: 2
                                                    T { text: procs.titles[hd.modelData]; color: hd.on ? app.accent : app.muted; font.pixelSize: 12; font.weight: hd.on ? Font.DemiBold : Font.Normal }
                                                    Ico { visible: hd.on; text: procs.desc ? "arrow_downward" : "arrow_upward"; size: 14; color: app.accent }
                                                }
                                            }

                                            // clic = ordenar · arrastrar = mover la columna
                                            MouseArea {
                                                id: hdMouse
                                                anchors.fill: parent
                                                anchors.rightMargin: 6
                                                hoverEnabled: true
                                                preventStealing: true
                                                cursorShape: tbl.dragKey ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                                property real sx: 0
                                                property bool moved: false
                                                onPressed: e => { sx = e.x; moved = false; }
                                                onPositionChanged: e => {
                                                    if (!pressed) return;
                                                    if (!moved && Math.abs(e.x - sx) > 6) { moved = true; tbl.dragKey = hd.modelData; }
                                                    if (moved) tbl.dragX = mapToItem(header, e.x, 0).x;
                                                }
                                                onReleased: {
                                                    if (moved) {
                                                        const from = procs.order.indexOf(tbl.dragKey);
                                                        let to = tbl.dropIdx;
                                                        tbl.dragKey = "";
                                                        if (from >= 0 && to >= 0) procs.move(from, to > from ? to - 1 : to);
                                                        return;
                                                    }
                                                    if (procs.sortKey === hd.modelData) procs.desc = !procs.desc;
                                                    else { procs.sortKey = hd.modelData; procs.desc = !(hd.modelData === "name" || hd.modelData === "user"); }
                                                    procs.rebuild();
                                                }
                                                onCanceled: tbl.dragKey = ""
                                            }

                                            // mép phải: kéo để đổi độ rộng (doble clic = ancho por defecto)
                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                anchors.topMargin: 10
                                                anchors.bottomMargin: 10
                                                width: rsMouse.containsMouse || rsMouse.pressed ? 3 : 1
                                                radius: 1
                                                color: rsMouse.containsMouse || rsMouse.pressed ? app.accent : app.line
                                            }
                                            MouseArea {
                                                id: rsMouse
                                                anchors.right: parent.right
                                                anchors.rightMargin: -5
                                                width: 11
                                                height: parent.height
                                                z: 2
                                                hoverEnabled: true
                                                preventStealing: true
                                                cursorShape: Qt.SplitHCursor
                                                property real sw: 0
                                                property real sgx: 0
                                                onPressed: e => { sw = hd.width; sgx = mapToItem(tbl, e.x, 0).x; }
                                                onPositionChanged: e => { if (pressed) procs.setW(hd.modelData, sw + mapToItem(tbl, e.x, 0).x - sgx); }
                                                onDoubleClicked: procs.resetW(hd.modelData)
                                            }
                                        }
                                    }

                                    // vạch báo chỗ sẽ thả cột
                                    Rectangle {
                                        visible: tbl.dragKey !== ""
                                        x: tbl.colX(Math.max(0, tbl.dropIdx)) - 2
                                        y: 4
                                        width: 4
                                        height: parent.height - 8
                                        radius: 2
                                        color: app.accent
                                    }
                                    // nhãn cột đang kéo, đi theo chuột
                                    Rectangle {
                                        visible: tbl.dragKey !== ""
                                        x: tbl.dragX - width / 2
                                        y: 8
                                        width: ghostT.implicitWidth + 20
                                        height: 30
                                        radius: 8
                                        color: app.accent
                                        T { id: ghostT; anchors.centerIn: parent; text: procs.titles[tbl.dragKey] ?? ""; color: app.onAccent; font.weight: Font.DemiBold }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.line }
                                }

                                // ---------------- filas
                                ListView {
                                    id: list
                                    width: parent.width
                                    height: parent.height - header.height
                                    clip: true
                                    model: procs.model
                                    boundsBehavior: Flickable.StopAtBounds
                                    reuseItems: true
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    function selRow(): var {
                                        for (let i = 0; i < procs.model.count; i++) {
                                            const r = procs.model.get(i);
                                            const k = r.group ? "g:" + r.name : r.pid;
                                            if (k === procs.selKey) return r;
                                        }
                                        return null;
                                    }

                                    delegate: Rectangle {
                                        id: row
                                        required property int index
                                        required property string name
                                        required property int pid
                                        required property real cpu
                                        required property real mem
                                        required property int threads
                                        required property string user
                                        required property string cmd
                                        required property bool group
                                        required property bool child
                                        required property int count
                                        required property string pids
                                        readonly property var key: group ? "g:" + name : pid
                                        readonly property bool sel: procs.selKey === key
                                        readonly property bool multi: group && count > 1
                                        width: ListView.view.width
                                        height: 34
                                        color: sel ? Qt.rgba(app.accent.r, app.accent.g, app.accent.b, 0.22)
                                             : rowMouse.containsMouse ? Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.05) : "transparent"

                                        // tô nhiệt CPU / RAM như Windows (càng dùng nhiều càng đậm)
                                        function heat(frac: real): color {
                                            const a = Math.min(0.55, frac);
                                            return Qt.rgba(app.cNet.r, app.cNet.g, app.cNet.b, a < 0.02 ? 0.05 : 0.08 + a);
                                        }
                                        function toggle(): void {
                                            const e = Object.assign({}, procs.expanded);
                                            e[name] = !e[name];
                                            procs.expanded = e;
                                            procs.rebuild();
                                        }

                                        // primero (debajo): selección, menú, tooltip
                                        MouseArea {
                                            id: rowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: e => {
                                                procs.selKey = row.key;
                                                if (e.button === Qt.RightButton) ctx.popupFor(row, mapToItem(win.contentItem, e.x, e.y));
                                            }
                                            onDoubleClicked: if (row.multi) row.toggle()
                                            ToolTip.visible: containsMouse && row.cmd.length > 0
                                            ToolTip.text: row.cmd
                                            ToolTip.delay: 900
                                        }

                                        // celdas en el orden de las columnas
                                        Repeater {
                                            model: procs.orderKey.split(",")
                                            Item {
                                                id: cell
                                                required property string modelData
                                                required property int index
                                                x: tbl.colX(index)
                                                width: tbl.colW(modelData)
                                                height: row.height
                                                clip: true

                                                // Tên
                                                Row {
                                                    visible: cell.modelData === "name"
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    leftPadding: row.child ? 26 : 0
                                                    spacing: 8
                                                    Item {
                                                        width: 18; height: 18
                                                        visible: !row.child
                                                        Ico {
                                                            anchors.centerIn: parent
                                                            visible: row.multi
                                                            text: procs.expanded[row.name] ? "expand_more" : "chevron_right"
                                                            size: 18
                                                            color: expMouse.containsMouse ? app.accent : app.muted
                                                        }
                                                        MouseArea {
                                                            id: expMouse
                                                            anchors.fill: parent
                                                            anchors.margins: -4
                                                            enabled: row.multi
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: row.toggle()
                                                        }
                                                    }
                                                    IconImage {
                                                        implicitSize: 18
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        source: Quickshell.iconPath(row.name.toLowerCase(), "application-x-executable")
                                                    }
                                                    T {
                                                        width: Math.max(40, cell.width - 18 - 18 - 16 - 10 - (row.child ? 26 : 0))
                                                        text: row.name + (row.multi ? "  (" + row.count + ")" : "")
                                                    }
                                                }
                                                // PID / Người dùng / Luồng
                                                T {
                                                    visible: cell.modelData === "pid" || cell.modelData === "user" || cell.modelData === "threads"
                                                    anchors.fill: parent
                                                    anchors.rightMargin: 10
                                                    horizontalAlignment: Text.AlignRight
                                                    color: cell.modelData === "threads" ? app.fg : app.muted
                                                    text: cell.modelData === "pid" ? (row.multi ? "" : row.pid)
                                                        : cell.modelData === "user" ? row.user : row.threads
                                                }
                                                // CPU / Bộ nhớ (tô nhiệt)
                                                Rectangle {
                                                    visible: cell.modelData === "cpu" || cell.modelData === "mem"
                                                    anchors.fill: parent
                                                    color: cell.modelData === "cpu" ? row.heat(row.cpu / 50)
                                                         : row.heat(app.d ? row.mem / app.d.mem.total * 4 : 0)
                                                    T {
                                                        anchors.fill: parent
                                                        anchors.rightMargin: 10
                                                        horizontalAlignment: Text.AlignRight
                                                        text: cell.modelData === "cpu" ? row.cpu.toFixed(1) + "%" : app.fmtBytes(row.mem, 1)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ============================== HIỆU NĂNG
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: win.page === "perf"
                    spacing: 14

                    // lista de dispositivos con mini-gráficas
                    Flickable {
                        Layout.preferredWidth: 250
                        Layout.fillHeight: true
                        contentHeight: devCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: devCol
                            width: parent.width
                            spacing: 6

                            Repeater {
                                // SOLO los ids (cadena): cambia únicamente si aparece/desaparece un dispositivo.
                                // Antes era un array nuevo cada segundo -> se recreaban las filas y las
                                // mini-gráficas parpadeaban.
                                model: app.devKey ? app.devKey.split(",") : []
                                Rectangle {
                                    id: dev
                                    required property string modelData
                                    readonly property var info: app.devInfo(modelData, app.ticks)
                                    readonly property bool on: win.perfSel === modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    radius: 8
                                    color: on ? app.hi : devMouse.containsMouse ? Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.05) : "transparent"
                                    border.width: on ? 1 : 0
                                    border.color: app.line
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 10
                                        Graph {
                                            Layout.preferredWidth: 70
                                            Layout.fillHeight: true
                                            values: dev.info.h
                                            max: dev.info.max
                                            color: dev.info.col
                                            grid: false
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            T { Layout.fillWidth: true; text: dev.info.t; font.weight: Font.DemiBold }
                                            T { Layout.fillWidth: true; text: dev.info.s; color: app.muted; font.pixelSize: 12 }
                                        }
                                    }
                                    MouseArea { id: devMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.perfSel = dev.modelData }
                                }
                            }
                        }
                    }

                    // detalle
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: app.panel
                        border.width: 1
                        border.color: app.line

                        Loader {
                            anchors.fill: parent
                            anchors.margins: 18
                            active: app.d !== null
                            sourceComponent: win.perfSel === "cpu" ? cpuView
                                           : win.perfSel === "mem" ? memView
                                           : win.perfSel === "gpu" ? gpuView
                                           : win.perfSel.startsWith("disk:") ? diskView
                                           : win.perfSel.startsWith("net:") ? netView : cpuView
                        }
                    }
                }
            }
        }

        Component {
            id: cpuView
            ColumnLayout {
                spacing: 8
                Header { title: "CPU"; sub: app.st?.cpu?.model ?? "" }
                RowLayout {
                    Layout.fillWidth: true
                    T { text: win.perCore ? tr("Uso por hilo (") + app.d.cpu.cores.length + ")" : tr("% Uso en 60 segundos"); color: app.muted; font.pixelSize: 12 }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        implicitWidth: pcRow.implicitWidth + 16
                        implicitHeight: 26
                        radius: 6
                        color: app.card
                        border.width: 1
                        border.color: app.line
                        RowLayout { id: pcRow; anchors.centerIn: parent; spacing: 4
                            Ico { text: win.perCore ? "grid_view" : "show_chart"; size: 15 }
                            T { text: win.perCore ? tr("Por hilo") : tr("Total"); font.pixelSize: 12 } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.perCore = !win.perCore }
                    }
                    T { text: "100%"; color: app.muted; font.pixelSize: 12 }
                }
                Graph {
                    visible: !win.perCore
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    values: app.hCpu
                    color: app.cCpu
                }
                GridLayout {
                    visible: win.perCore
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 4
                    rowSpacing: 6
                    columnSpacing: 6
                    Repeater {
                        model: win.perCore ? app.hCores.length : 0
                        Graph {
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            values: app.hCores[index] ?? []
                            color: app.cCpu
                            grid: false
                            T { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 4; font.pixelSize: 10; color: app.muted
                                text: "CPU " + parent.index + "  " + Math.round(app.d.cpu.cores[parent.index] ?? 0) + "%" }
                        }
                    }
                }
                Caption { ltext: tr("60 segundos"); rtext: "0" }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 36
                    ColumnLayout {
                        spacing: 10
                        RowLayout { spacing: 36
                            Stat { label: tr("Uso"); value: Math.round(app.d.cpu.total) + "%" }
                            Stat { label: tr("Velocidad"); value: app.d.cpu.freq.toFixed(2) + " GHz" } }
                        RowLayout { spacing: 36
                            Stat { label: tr("Procesos"); value: app.nproc || "–" }
                            Stat { label: tr("Hilos"); value: app.nthreads || "–" }
                            Stat { label: tr("Temperatura"); value: app.d.cpu.temp ? app.d.cpu.temp.toFixed(0) + " °C" : "–" } }
                        Stat { label: tr("Tiempo activo"); value: app.fmtUptime(app.d.uptime) }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 4
                        KV { k: tr("Velocidad máx."); v: (app.st?.cpu?.maxGHz ?? 0) + " GHz" }
                        KV { k: tr("Núcleos"); v: app.st?.cpu?.cores ?? "" }
                        KV { k: tr("Procesadores lógicos"); v: app.st?.cpu?.threads ?? "" }
                        KV { k: tr("Carga media"); v: app.d.cpu.load.map(x => x.toFixed(2)).join("  ") }
                        KV { k: tr("Núcleos del SO"); v: app.st?.kernel ?? "" }
                    }
                }
            }
        }

        Component {
            id: memView
            ColumnLayout {
                spacing: 8
                readonly property var m: app.d.mem
                Header { title: tr("Memoria"); sub: app.fmtBytes(m.total, 1) + " RAM" }
                Caption { ltext: tr("Uso de memoria"); rtext: app.fmtBytes(m.total, 1) }
                Graph { Layout.fillWidth: true; Layout.fillHeight: true; values: app.hMem; color: app.cMem }
                Caption { ltext: tr("60 segundos"); rtext: "0" }
                // thanh thành phần: đang dùng / cache / trống
                T { text: tr("Componentes de memoria"); color: app.muted; font.pixelSize: 12; Layout.topMargin: 6 }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 4
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(app.cMem.r, app.cMem.g, app.cMem.b, 0.6)
                    Row {
                        anchors.fill: parent
                        anchors.margins: 1
                        Rectangle { height: parent.height; width: parent.width * m.used / m.total; color: Qt.rgba(app.cMem.r, app.cMem.g, app.cMem.b, 0.45) }
                        Rectangle { height: parent.height; width: parent.width * Math.min(m.cached, m.avail) / m.total; color: Qt.rgba(app.cMem.r, app.cMem.g, app.cMem.b, 0.18) }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 36
                    ColumnLayout {
                        spacing: 10
                        RowLayout { spacing: 36
                            Stat { label: tr("En uso"); value: app.fmtBytes(m.used, 1) }
                            Stat { label: tr("Libre"); value: app.fmtBytes(m.avail, 1) } }
                        RowLayout { spacing: 36
                            Stat { label: tr("Comprometida"); value: app.fmtBytes(m.committed, 1) + " / " + app.fmtBytes(m.commitLimit, 0) }
                            Stat { label: tr("Caché"); value: app.fmtBytes(m.cached, 1) } }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 4
                        KV { k: "Swap (zram)"; v: app.fmtBytes(m.swapUsed, 1) + " / " + app.fmtBytes(m.swapTotal, 1) }
                        KV { k: tr("Memoria compartida"); v: app.fmtBytes(m.shared, 1) }
                        KV { k: "Buffers"; v: app.fmtBytes(m.buffers, 1) }
                        KV { k: tr("En espera de escritura (dirty)"); v: app.fmtBytes(m.dirty, 1) }
                    }
                }
            }
        }

        Component {
            id: diskView
            ColumnLayout {
                spacing: 8
                readonly property string dn: win.perfSel.slice(5)
                readonly property var info: (app.st?.disks ?? []).find(x => x.name === dn) ?? {}
                readonly property var cur: app.d.disks.find(x => x.name === dn) ?? { busy: 0, read: 0, write: 0 }
                readonly property var h: app.hDisk[dn] ?? { busy: [], read: [], write: [] }
                readonly property var parts: app.d.mounts.filter(x => x.dev.startsWith(dn))
                Header { title: tr("Disco (") + dn + ")"; sub: info.model ?? "" }
                Caption { ltext: tr("Tiempo activo"); rtext: "100%" }
                Graph { Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 3; values: h.busy; color: app.cDisk }
                Caption { ltext: tr("Velocidad de lectura (continua) / escritura (discontinua)"); rtext: app.fmtDiskRate(Math.max(...h.read, ...h.write, 1) * 1.15) }
                Graph { Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 2; values: h.read; values2: h.write; max: 0; color: app.cDisk; fillArea: true }
                Caption { ltext: tr("60 segundos"); rtext: "0" }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 36
                    ColumnLayout {
                        spacing: 10
                        RowLayout { spacing: 36
                            Stat { label: tr("Tiempo activo"); value: Math.round(cur.busy) + "%" }
                            Stat { label: tr("Temperatura"); value: app.d.nvmeTemp ? app.d.nvmeTemp.toFixed(0) + " °C" : "–" } }
                        RowLayout { spacing: 36
                            Stat { label: tr("Velocidad de lectura"); value: app.fmtDiskRate(cur.read) }
                            Stat { label: tr("Velocidad de escritura"); value: app.fmtDiskRate(cur.write) } }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 4
                        KV { k: tr("Capacidad"); v: app.fmtBytes(info.size ?? 0, 0) }
                        KV { k: tr("Tipo"); v: info.ssd ? "SSD (NVMe)" : "HDD" }
                        Repeater {
                            model: parts.length          // número: no recrea las filas cada segundo
                            KV {
                                required property int index
                                readonly property var mp: parts[index] ?? { mount: "", used: 0, total: 0, fs: "" }
                                k: mp.mount
                                v: app.fmtBytes(mp.used, 1) + " / " + app.fmtBytes(mp.total, 1) + "  (" + mp.fs + ")"
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: netView
            ColumnLayout {
                spacing: 8
                readonly property string nn: win.perfSel.slice(4)
                readonly property var cur: app.d.net.find(x => x.name === nn) ?? { rx: 0, tx: 0, rxTotal: 0, txTotal: 0 }
                readonly property var h: app.hNet[nn] ?? { rx: [], tx: [], info: null }
                Header { title: h.info?.kind ?? tr("Red"); sub: nn }
                Caption { ltext: tr("Tráfico: recibido (continuo) / enviado (discontinuo)"); rtext: app.fmtRate(Math.max(...h.rx, ...h.tx, 1) * 1.15) }
                Graph { Layout.fillWidth: true; Layout.fillHeight: true; values: h.rx; values2: h.tx; max: 0; color: app.cNet }
                Caption { ltext: tr("60 segundos"); rtext: "0" }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 36
                    ColumnLayout {
                        spacing: 10
                        RowLayout { spacing: 36
                            Stat { label: tr("Recibidos"); value: app.fmtRate(cur.rx) }
                            Stat { label: tr("Enviados"); value: app.fmtRate(cur.tx) } }
                        RowLayout { spacing: 36
                            Stat { label: tr("Recibido (desde el encendido)"); value: app.fmtBytes(cur.rxTotal, 1); big: false }
                            Stat { label: tr("Enviado (desde el encendido)"); value: app.fmtBytes(cur.txTotal, 1); big: false } }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 4
                        KV { k: tr("Adaptador"); v: nn }
                        KV { k: tr("Tipo de conexión"); v: h.info?.kind ?? "" }
                        KV { k: tr("Dirección IPv4"); v: h.info?.ip || "–" }
                        KV { k: tr("Velocidad del enlace"); v: (h.info?.speed ?? 0) > 0 ? h.info.speed + " Mbps" : "–" }
                    }
                }
            }
        }

        Component {
            id: gpuView
            ColumnLayout {
                spacing: 8
                readonly property var g: app.d.gpu
                Header { title: "GPU"; sub: g?.name ?? "" }
                Caption { ltext: tr("% Uso 3D/cómputo"); rtext: "100%" }
                Graph { Layout.fillWidth: true; Layout.fillHeight: true; values: app.hGpu; color: app.cGpu }
                Caption { ltext: tr("60 segundos"); rtext: "0" }
                T { text: tr("Memoria GPU dedicada (VRAM)"); color: app.muted; font.pixelSize: 12; Layout.topMargin: 6 }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 22
                    radius: 4
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(app.cGpu.r, app.cGpu.g, app.cGpu.b, 0.6)
                    Rectangle { x: 1; y: 1; height: parent.height - 2; width: (parent.width - 2) * (g ? g.vramUsed / Math.max(1, g.vramTotal) : 0); color: Qt.rgba(app.cGpu.r, app.cGpu.g, app.cGpu.b, 0.4) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 36
                    ColumnLayout {
                        spacing: 10
                        RowLayout { spacing: 36
                            Stat { label: tr("Uso"); value: (g?.busy ?? 0) + "%" }
                            Stat { label: tr("Temperatura"); value: g?.temp ? g.temp.toFixed(0) + " °C" : "–" }
                            Stat { label: tr("Potencia"); value: (g?.power ?? 0) + " W" } }
                        RowLayout { spacing: 36
                            Stat { label: "VRAM"; value: app.fmtBytes(g?.vramUsed ?? 0, 1) + " / " + app.fmtBytes(g?.vramTotal ?? 0, 1) }
                            Stat { label: tr("Memoria compartida (GTT)"); value: app.fmtBytes(g?.gttUsed ?? 0, 1) + " / " + app.fmtBytes(g?.gttTotal ?? 0, 1) } }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 4
                        KV { k: "Pin"; v: app.d.bat ? app.d.bat.percent + "%  ·  " + app.d.bat.status : "–" }
                        KV { k: tr("Capacidad de la batería"); v: app.d.bat && app.d.bat.power > 0 ? app.d.bat.power + " W" : "–" }
                    }
                }
            }
        }

        // ------------------------------------------------ menú contextual
        Rectangle {
            id: ctx
            visible: false
            z: 100
            width: 230
            height: ctxCol.implicitHeight + 12
            radius: 10
            color: app.card
            border.width: 1
            border.color: app.line
            property var r: null
            function popupFor(row: var, p: point): void {
                r = { name: row.name, pid: row.pid, pids: row.pids, cmd: row.cmd, group: row.group, count: row.count };
                x = Math.min(p.x, win.width - width - 8);
                y = Math.min(p.y, win.height - height - 8);
                visible = true;
            }
            MouseArea {     // cerrar al hacer clic fuera
                parent: win.contentItem
                anchors.fill: parent
                visible: ctx.visible
                z: 99
                onClicked: ctx.visible = false
            }
            ColumnLayout {
                id: ctxCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 0
                Repeater {
                    model: ctx.r ? [
                        { i: "block", t: ctx.r.group && ctx.r.count > 1 ? tr("Terminar todo (") + ctx.r.count + ")" : tr("Terminar tarea"), a: () => app.killPids(ctx.r.pids, false) },
                        { i: "dangerous", t: tr("Forzar parada (SIGKILL)"), a: () => app.killPids(ctx.r.pids, true) },
                        { i: "content_copy", t: tr("Copiar PID"), a: () => app.copy(ctx.r.pids) },
                        { i: "terminal", t: tr("Copiar línea de comando"), a: () => app.copy(ctx.r.cmd) },
                        { i: "folder_open", t: tr("Abrir ubicación del archivo"), a: () => Quickshell.execDetached(["sh", "-c", "d=$(dirname \"$(readlink -f /proc/" + ctx.r.pid + "/exe)\") && xdg-open \"$d\""]) }
                    ] : []
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 6
                        color: ctxMouse.containsMouse ? app.accent : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            spacing: 10
                            Ico { text: parent.parent.modelData.i; size: 17; color: ctxMouse.containsMouse ? app.onAccent : app.fg }
                            T { Layout.fillWidth: true; text: parent.parent.modelData.t; color: ctxMouse.containsMouse ? app.onAccent : app.fg }
                        }
                        MouseArea {
                            id: ctxMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { parent.modelData.a(); ctx.visible = false; }
                        }
                    }
                }
            }
        }
    }
}
