import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Activity Monitor: monitor de rendimiento al estilo macOS (CPU / Memoria / Energía / Disco / Red).
// Módulo del shell (como Ajustes del Sistema): solo existe mientras está abierto.
// Datos: apps/activitymonitor/collector.py (1 línea JSON por intervalo, lee /proc).
Scope {
    id: app

    // ------------------------------------------------------------------ tema (estilo macOS)
    readonly property bool dark: Theme.dark
    readonly property color win: dark ? "#1e1e1e" : "#ececec"
    readonly property color bar: dark ? "#2b2b2b" : "#dcdcdc"
    readonly property color content: dark ? "#1e1e1e" : "#ffffff"
    readonly property color altRow: dark ? "#252525" : "#f4f5f5"
    readonly property color fg: dark ? "#e8e8e8" : "#1d1d1f"
    readonly property color muted: dark ? "#9a9a9e" : "#6e6e73"
    readonly property color line: dark ? "#3a3a3c" : "#d2d2d6"
    readonly property color accent: "#0a84ff"
    readonly property color cUser: "#0a84ff"
    readonly property color cSys: "#ff453a"
    readonly property color cGreen: "#32d74b"
    readonly property color cOrange: "#ff9f0a"
    readonly property string uiFont: "Inter"
    readonly property string iconFont: "Material Symbols Rounded"

    // ------------------------------------------------------------------ estado
    readonly property var tabs: [
        { id: "cpu", title: "CPU" }, { id: "mem", title: "Memory" }, { id: "energy", title: "Energy" },
        { id: "disk", title: "Disk" }, { id: "net", title: "Network" }
    ]
    property string tab: "cpu"
    property string sortKey: "cpu"
    property bool sortDesc: true
    property string query: ""
    property int selPid: -1
    property var d: null
    readonly property int histLen: 90
    property var hUser: []
    property var hSys: []
    property var hMem: []
    property var hA: []     // lectura / recibido
    property var hB: []     // escritura / enviado
    property var stats: []
    property int tick: 0

    function push(arr: var, v: real): var {
        const a = arr.length >= histLen ? arr.slice(1) : arr.slice();
        a.push(v);
        return a;
    }

    // columnas por pestaña: key, título, ancho, alineación, formato
    readonly property var columns: ({
        cpu: [
            { k: "cpu", t: "% CPU", w: 90, f: "pct" }, { k: "threads", t: "Threads", w: 80, f: "int" },
            { k: "pid", t: "PID", w: 80, f: "int" }, { k: "user", t: "User", w: 110, f: "str" }],
        mem: [
            { k: "mem", t: "Memory", w: 110, f: "bytes" }, { k: "threads", t: "Threads", w: 80, f: "int" },
            { k: "pid", t: "PID", w: 80, f: "int" }, { k: "user", t: "User", w: 110, f: "str" }],
        energy: [
            { k: "cpu", t: "Energy Impact", w: 120, f: "dec" }, { k: "state", t: "State", w: 70, f: "str" },
            { k: "pid", t: "PID", w: 80, f: "int" }, { k: "user", t: "User", w: 110, f: "str" }],
        disk: [
            { k: "wrTotal", t: "Bytes Written", w: 110, f: "bytes" }, { k: "rdTotal", t: "Bytes Read", w: 110, f: "bytes" },
            { k: "wr", t: "Writes/s", w: 90, f: "rate" }, { k: "rd", t: "Reads/s", w: 90, f: "rate" },
            { k: "pid", t: "PID", w: 70, f: "int" }, { k: "user", t: "User", w: 100, f: "str" }],
        net: [
            { k: "threads", t: "Threads", w: 80, f: "int" }, { k: "state", t: "State", w: 70, f: "str" },
            { k: "pid", t: "PID", w: 80, f: "int" }, { k: "user", t: "User", w: 110, f: "str" }]
    })
    readonly property var cols: columns[tab]
    readonly property real fixedW: cols.reduce((s, x) => s + x.w, 0)

    function fmtBytes(n: real): string {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (n >= 1024 && i < 4) { n /= 1024; i++; }
        return (i === 0 ? Math.round(n) : n.toFixed(n >= 100 ? 0 : 1)) + " " + u[i];
    }
    function fmt(v: var, f: string): string {
        switch (f) {
        case "pct": return v.toFixed(1);
        case "dec": return v.toFixed(1);
        case "bytes": return fmtBytes(v);
        case "rate": return v > 0 ? fmtBytes(v) + "/s" : "0";
        case "int": return String(v);
        default: return String(v);
        }
    }
    function fmtUptime(s: real): string {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d ? d + "d " : "") + h + "h " + m + "m";
    }

    function ingest(s: var): void {
        d = s;
        hUser = push(hUser, s.cpu.user);
        hSys = push(hSys, s.cpu.system);
        hMem = push(hMem, s.mem.pressure);
        hA = push(hA, tab === "net" ? s.net.rx : s.disk.read);
        hB = push(hB, tab === "net" ? s.net.tx : s.disk.write);
        refreshRows();
        refreshStats();
        tick++;
    }

    // el historial de disco y de red es distinto: se reinicia al cambiar de pestaña
    onTabChanged: {
        hA = []; hB = [];
        const first = columns[tab][0].k;
        sortKey = first === "wrTotal" ? "wrTotal" : (first === "threads" ? "pid" : first);
        sortDesc = !(sortKey === "pid");
        if (d) { refreshRows(); refreshStats(); }
    }
    onSortKeyChanged: if (d) refreshRows()
    onSortDescChanged: if (d) refreshRows()
    onQueryChanged: if (d) refreshRows()

    ListModel { id: rows }

    function refreshRows(): void {
        const q = query.trim().toLowerCase();
        let list = d.procs;
        if (q)
            list = list.filter(p => p.name.toLowerCase().includes(q) || String(p.pid) === q || p.user.toLowerCase().includes(q));
        const k = sortKey, dir = sortDesc ? -1 : 1;
        list = list.slice().sort((a, b) => {
            const x = a[k], y = b[k];
            const r = typeof x === "string" ? x.localeCompare(y) : x - y;
            return r !== 0 ? dir * r : a.pid - b.pid;
        });
        // actualiza en sitio para conservar el scroll
        for (let i = 0; i < list.length; i++) {
            if (i < rows.count) rows.set(i, list[i]);
            else rows.append(list[i]);
        }
        if (rows.count > list.length)
            rows.remove(list.length, rows.count - list.length);
    }

    function refreshStats(): void {
        const s = d;
        const f1 = v => v.toFixed(2) + "%";
        switch (tab) {
        case "cpu":
            stats = [["System:", f1(s.cpu.system), app.cSys], ["User:", f1(s.cpu.user), app.cUser], ["Idle:", f1(s.cpu.idle), ""],
                     ["Threads:", s.nthreads, ""], ["Processes:", s.nproc, ""]];
            break;
        case "mem":
            stats = [["Physical Memory:", fmtBytes(s.mem.total), ""], ["Memory Used:", fmtBytes(s.mem.used), ""],
                     ["Cached Files:", fmtBytes(s.mem.cached), ""], ["Swap Used:", fmtBytes(s.mem.swapUsed), ""],
                     ["Swap Total:", fmtBytes(s.mem.swapTotal), ""]];
            break;
        case "energy":
            stats = [["Battery:", s.battery ? s.battery.pct + "%" : "—", ""], ["Status:", s.battery ? s.battery.status : "AC power", ""],
                     ["Load (1 min):", s.load[0].toFixed(2), ""], ["Load (5 min):", s.load[1].toFixed(2), ""],
                     ["Uptime:", fmtUptime(s.uptime), ""]];
            break;
        case "disk":
            stats = [["Reads in:", Math.round(s.disk.rops), app.cUser], ["Writes out:", Math.round(s.disk.wops), app.cSys],
                     ["Data read/s:", fmtBytes(s.disk.read) + "/s", app.cUser], ["Data written/s:", fmtBytes(s.disk.write) + "/s", app.cSys],
                     ["Total read / written:", fmtBytes(s.disk.readTotal) + " / " + fmtBytes(s.disk.writeTotal), ""]];
            break;
        default:
            stats = [["Data received/s:", fmtBytes(s.net.rx) + "/s", app.cUser], ["Data sent/s:", fmtBytes(s.net.tx) + "/s", app.cSys],
                     ["Packets in/s:", Math.round(s.net.rp), ""], ["Packets out/s:", Math.round(s.net.tp), ""],
                     ["Total received / sent:", fmtBytes(s.net.rxTotal) + " / " + fmtBytes(s.net.txTotal), ""]];
        }
    }

    Process {
        id: collector
        running: Shell.activityOpen
        stdinEnabled: true
        command: ["python3", "-I", Quickshell.shellDir + "/apps/activitymonitor/collector.py"]
        stdout: SplitParser {
            onRead: line => { try { app.ingest(JSON.parse(line)); } catch (e) { console.warn("activitymonitor:", e); } }
        }
        onStarted: write("interval 2\n")
        onExited: if (Shell.activityOpen) restart.start()
    }
    Timer { id: restart; interval: 1500; onTriggered: collector.running = Shell.activityOpen }
    function send(cmd: string): void { if (collector.running) collector.write(cmd + "\n"); }

    // ------------------------------------------------------------------ ventana
    LazyLoader {
        active: Shell.activityOpen

    FloatingWindow {
        id: window
        title: "Activity Monitor"
        visible: true
        onVisibleChanged: if (!visible) Shell.activityOpen = false
        implicitWidth: 960
        implicitHeight: 720
        minimumSize: Qt.size(700, 480)
        color: app.win

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---------------------------------------------------------- barra superior
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 56
                color: app.bar
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.line }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    // botón «detener proceso»
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 28; radius: 6
                        color: stopArea.containsMouse ? Qt.rgba(1, 1, 1, app.dark ? 0.12 : 0.6) : "transparent"
                        opacity: app.selPid > 0 ? 1 : 0.4
                        Text {
                            anchors.centerIn: parent
                            text: "cancel"
                            font.family: app.iconFont; font.pixelSize: 20
                            color: app.fg
                        }
                        MouseArea {
                            id: stopArea
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: app.selPid > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (app.selPid > 0) app.send((mouse.modifiers & Qt.ShiftModifier ? "kill " : "term ") + app.selPid)
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Text { text: "Activity Monitor"; color: app.fg; font.family: app.uiFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { text: "All Processes"; color: app.muted; font.family: app.uiFont; font.pixelSize: 11 }
                    }

                    Item { Layout.fillWidth: true }

                    // pestañas (control segmentado)
                    Rectangle {
                        implicitWidth: segRow.implicitWidth + 4
                        implicitHeight: 28
                        radius: 7
                        color: app.dark ? "#1c1c1e" : "#c9c9cc"
                        Row {
                            id: segRow
                            anchors.centerIn: parent
                            spacing: 0
                            Repeater {
                                model: app.tabs
                                Rectangle {
                                    required property var modelData
                                    width: 78; height: 24; radius: 5
                                    color: app.tab === modelData.id ? (app.dark ? "#636366" : "#ffffff") : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.title
                                        font.family: app.uiFont; font.pixelSize: 12
                                        font.weight: app.tab === modelData.id ? Font.DemiBold : Font.Normal
                                        color: app.fg
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.tab = modelData.id }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // búsqueda
                    Rectangle {
                        implicitWidth: 190; implicitHeight: 26; radius: 7
                        color: app.dark ? "#1c1c1e" : "#f6f6f6"
                        border.width: search.activeFocus ? 2 : 1
                        border.color: search.activeFocus ? app.accent : app.line
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                            Text { text: "search"; font.family: app.iconFont; font.pixelSize: 16; color: app.muted }
                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                font.family: app.uiFont; font.pixelSize: 12
                                color: app.fg; clip: true
                                selectionColor: app.accent
                                onTextChanged: app.query = text
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !search.text
                                    text: "Search"; color: app.muted
                                    font.family: app.uiFont; font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------------- cabecera de la tabla
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 24
                color: app.content
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.line }
                Row {
                    anchors.fill: parent
                    Item {
                        width: Math.max(180, parent.width - app.fixedW); height: parent.height
                        HeaderCell { anchors.fill: parent; title: "Process Name"; key: "name"; alignLeft: true }
                    }
                    Repeater {
                        model: app.cols
                        Item {
                            required property var modelData
                            width: modelData.w; height: 24
                            HeaderCell { anchors.fill: parent; title: parent.modelData.t; key: parent.modelData.k; alignLeft: parent.modelData.f === "str" }
                        }
                    }
                }
            }

            // ---------------------------------------------------------- filas
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: rows
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                Rectangle { anchors.fill: parent; z: -1; color: app.content }

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property int pid
                    required property string name
                    required property var model
                    readonly property bool sel: app.selPid === pid
                    width: list.width
                    height: 22
                    color: sel ? app.accent : (index % 2 ? app.altRow : app.content)

                    Row {
                        anchors.fill: parent
                        Item {
                            width: Math.max(180, row.width - app.fixedW); height: row.height
                            Text {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                text: row.name
                                elide: Text.ElideRight
                                font.family: app.uiFont; font.pixelSize: 12
                                color: row.sel ? "white" : app.fg
                            }
                        }
                        Repeater {
                            model: app.cols
                            Item {
                                required property var modelData
                                width: modelData.w; height: row.height
                                Text {
                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 10
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: parent.modelData.f === "str" ? Text.AlignLeft : Text.AlignRight
                                    text: app.fmt(row.model[parent.modelData.k], parent.modelData.f)
                                    elide: Text.ElideRight
                                    font.family: app.uiFont; font.pixelSize: 12
                                    font.features: { "tnum": 1 }
                                    color: row.sel ? "white" : app.fg
                                }
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: app.selPid = row.pid }
                }
            }

            // ---------------------------------------------------------- panel inferior
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 168
                color: app.win
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: app.line }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 18

                    // estadísticas
                    ColumnLayout {
                        Layout.preferredWidth: 300
                        Layout.maximumWidth: 300
                        Layout.minimumWidth: 300
                        Layout.fillHeight: true
                        spacing: 4
                        Repeater {
                            model: app.stats
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { visible: modelData[2] !== ""; implicitWidth: 8; implicitHeight: 8; radius: 4; color: modelData[2] || "transparent" }
                                Text { text: modelData[0]; color: app.muted; font.family: app.uiFont; font.pixelSize: 12 }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: String(modelData[1]); color: app.fg
                                    font.family: app.uiFont; font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }

                    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: app.line }

                    // gráfica
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 4
                        Text {
                            text: ({ cpu: "CPU LOAD", mem: "MEMORY PRESSURE", energy: "CPU LOAD", disk: "DISK ACTIVITY", net: "NETWORK DATA" })[app.tab]
                            color: app.muted; font.family: app.uiFont; font.pixelSize: 10; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            radius: 6
                            color: app.content
                            border.width: 1; border.color: app.line
                            Chart {
                                anchors.fill: parent; anchors.margins: 1
                                tick: app.tick
                                mode: app.tab === "mem" ? "single" : (app.tab === "cpu" || app.tab === "energy" ? "stacked" : "lines")
                                a: app.tab === "mem" ? app.hMem : (app.tab === "cpu" || app.tab === "energy" ? app.hSys : app.hA)
                                b: app.tab === "cpu" || app.tab === "energy" ? app.hUser : app.hB
                                colorA: app.tab === "mem" ? app.cGreen : (app.tab === "cpu" || app.tab === "energy" ? app.cSys : app.cUser)
                                colorB: app.tab === "cpu" || app.tab === "energy" ? app.cUser : app.cSys
                                fixedMax: app.tab === "mem" || app.tab === "cpu" || app.tab === "energy" ? 100 : 0
                            }
                        }
                    }
                }
            }
        }
    }

    }

    // ------------------------------------------------------------------ componentes
    component HeaderCell: Item {
        id: hc
        property string title
        property string key
        property bool alignLeft: false
        readonly property bool active: app.sortKey === key
        Text {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: hc.alignLeft ? Text.AlignLeft : Text.AlignRight
            text: hc.title + (hc.active ? (app.sortDesc ? "  ▾" : "  ▴") : "")
            elide: Text.ElideRight
            font.family: app.uiFont; font.pixelSize: 11
            font.weight: hc.active ? Font.DemiBold : Font.Normal
            color: hc.active ? app.fg : app.muted
        }
        Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 1; height: 14; color: app.line }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (app.sortKey === hc.key) app.sortDesc = !app.sortDesc;
                else { app.sortKey = hc.key; app.sortDesc = hc.key !== "name" && hc.key !== "user"; }
            }
        }
    }

    // Gráfica de historial: apilada (CPU), línea única rellena (memoria) o dos líneas (disco/red)
    component Chart: Canvas {
        id: ch
        property int tick: 0
        property string mode: "lines"
        property var a: []
        property var b: []
        property color colorA: "red"
        property color colorB: "blue"
        property real fixedMax: 0
        onTickChanged: requestPaint()
        onModeChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            // rejilla
            ctx.strokeStyle = app.dark ? "#2e2e30" : "#ececee";
            ctx.lineWidth = 1;
            for (let i = 1; i < 4; i++) {
                const y = Math.round(height * i / 4) + 0.5;
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
            }
            const n = app.histLen;
            const step = width / (n - 1);
            let max = fixedMax;
            if (!max) {
                for (const v of ch.a.concat(ch.b)) max = Math.max(max, v);
                max = Math.max(max * 1.15, 1024);
            }
            const X = (i, len) => width - (len - 1 - i) * step;
            const Y = v => height - Math.min(1, v / max) * (height - 2) - 1;
            function area(vals, base, color, alpha) {
                if (vals.length < 2) return;
                ctx.beginPath();
                for (let i = 0; i < vals.length; i++) {
                    const y = Y(vals[i] + (base ? base[i] : 0));
                    i === 0 ? ctx.moveTo(X(i, vals.length), y) : ctx.lineTo(X(i, vals.length), y);
                }
                ctx.lineTo(X(vals.length - 1, vals.length), height);
                ctx.lineTo(X(0, vals.length), height);
                ctx.closePath();
                ctx.globalAlpha = alpha; ctx.fillStyle = color; ctx.fill(); ctx.globalAlpha = 1;
            }
            function stroke(vals, base, color) {
                if (vals.length < 2) return;
                ctx.beginPath();
                for (let i = 0; i < vals.length; i++) {
                    const y = Y(vals[i] + (base ? base[i] : 0));
                    i === 0 ? ctx.moveTo(X(i, vals.length), y) : ctx.lineTo(X(i, vals.length), y);
                }
                ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.stroke();
            }
            if (mode === "stacked") {
                // sistema abajo, usuario encima
                const len = Math.min(a.length, b.length);
                const sys = a.slice(-len);
                const usr = b.slice(-len);
                area(usr, sys, colorB, 0.55); stroke(usr, sys, colorB);
                area(sys, null, colorA, 0.65); stroke(sys, null, colorA);
            } else if (mode === "single") {
                area(a, null, colorA, 0.45); stroke(a, null, colorA);
            } else {
                area(a, null, colorA, 0.25); stroke(a, null, colorA);
                area(b, null, colorB, 0.25); stroke(b, null, colorB);
            }
        }
    }
}
