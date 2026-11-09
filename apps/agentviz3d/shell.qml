import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Claude Agent Space: các agent của Claude Code vẽ dạng 3D (phối cảnh tự tính, không cần QtQuick3D).
// Dữ liệu: ../agentviz/collector.py (hook của Claude Code) ghi ~/.cache/claude-agentviz/state.json.
//   lead     = lõi nguyên tử ở tâm, các electron quay khi lead đang làm việc
//   subagent = vệ tinh xanh trên quỹ đạo, hạt sáng chạy theo dây khi đang chạy
//   fork     = vệ tinh xanh lá; advisor = khối tím lơ lửng phía trên
//   xong     = lùi ra quỹ đạo ngoài, mờ đi
// Mở: apps/agentviz3d/claude-agentviz3d   (hoặc qs -p ~/dev/cael-src/apps/agentviz3d/shell.qml)
// Điều khiển: kéo chuột = xoay · cuộn = zoom · R = đặt lại · Space = tự xoay bật/tắt · 1..8 = chọn phiên
// Thử với dữ liệu khác: AGENTVIZ_STATE=/đường/dẫn/state.json qs -p …
// IPC: qs -p … ipc call agentviz3d close|status
ShellRoot {
    id: app

    // ------------------------------------------------------------------ màu
    readonly property color bg: "#0d0f14"
    readonly property color fg: "#d6d8de"
    readonly property color muted: "#7c818c"
    readonly property var cLead: [224, 128, 90]
    readonly property var cSwarm: [122, 167, 240]
    readonly property var cFork: [103, 201, 138]
    readonly property var cAdv: [166, 154, 240]
    readonly property var cErr: [240, 122, 122]
    readonly property var cDone: [110, 116, 128]
    readonly property var cPend: [200, 200, 210]
    readonly property string mono: "CaskaydiaCove Nerd Font Mono"

    function css(c, a) { return `rgba(${c[0]},${c[1]},${c[2]},${a})`; }
    function qc(c, a) { return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, a ?? 1); }
    function mix(c, k) { return c.map(v => Math.round(v + (255 - v) * k)); }
    function shade(c, k) { return c.map(v => Math.round(v * k)); }

    // ------------------------------------------------------------------ dữ liệu
    property var st: ({})
    property real now: Date.now() / 1000
    property string pinned: ""            // "" = theo phiên đang hoạt động
    readonly property var sessionList: Object.values(st.sessions ?? {}).sort((a, b) => b.at - a.at)
    readonly property string sid: pinned && (st.sessions ?? {})[pinned] ? pinned : (st.active ?? "")
    readonly property var s: (st.sessions ?? {})[sid] ?? null
    readonly property var subsAll: s ? Object.values(s.subs ?? {}).sort((a, b) => a.start - b.start) : []
    readonly property var swarm: subsAll.filter(x => !x.advisor).slice(-14)
    readonly property var advisorRuns: subsAll.filter(x => x.advisor)
    readonly property bool advisorRunning: advisorRuns.some(x => x.status === "running")
    readonly property int running: swarm.filter(x => x.status === "running").length
    readonly property bool live: !!s && (s.busy || subsAll.some(x => x.status === "running"))
    readonly property string phase: s?.phase ?? "idle"

    function cap(m) { return (m ?? "").replace(/^\w/, c => c.toUpperCase()); }
    function base(p) { return (p ?? "").split("/").filter(x => x).pop() ?? "~"; }
    function ago(t) {
        const d = Math.max(0, Math.round(now - t));
        return d < 60 ? d + "s" : d < 3600 ? Math.round(d / 60) + "m" : Math.round(d / 3600) + "h";
    }
    function effortBlocks(e) {
        const n = ({ low: 1, medium: 2, high: 3, xhigh: 4, max: 5 })[e] ?? 0;
        return "▮".repeat(n) + "▯".repeat(5 - n);
    }

    FileView {
        id: file
        path: Quickshell.env("AGENTVIZ_STATE") || Quickshell.env("HOME") + "/.cache/claude-agentviz/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { app.st = JSON.parse(text()); } catch (e) {} }
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { app.now = Date.now() / 1000; file.reload(); }
    }

    IpcHandler {
        target: "agentviz3d"
        function close(): void { Qt.quit(); }
        function status(): string {
            return JSON.stringify({ live: app.live, phase: app.phase, swarm: app.swarm.length, running: app.running });
        }
    }

    // ------------------------------------------------------------------ các nút trong cảnh
    // Danh sách nút (đổi khi state đổi); vị trí đích tính lại mỗi khung hình.
    readonly property var nodes: {
        const out = [];
        if (!s) return out;
        out.push({ id: "lead", kind: "lead", r: 0.62, col: cLead, label: cap(s.model) + " · lead",
                   on: s.busy && running === 0 });
        const adv = advisorRuns[advisorRuns.length - 1];
        out.push({ id: "advisor", kind: "advisor", r: 0.32, col: cAdv, label: "advisor",
                   on: advisorRunning, d: adv ?? null, ghost: !adv });
        const run = swarm.filter(x => x.status === "running");
        const done = swarm.filter(x => x.status !== "running");
        run.forEach((x, i) => out.push({ id: x.id, kind: "sub", r: 0.3, col: x.fork ? cFork : cSwarm,
                                         label: x.type || "agent", on: true, d: x, i, n: run.length }));
        done.forEach((x, i) => out.push({ id: x.id, kind: "done", r: 0.2, col: x.fork ? shade(cFork, 0.6) : cDone,
                                          label: x.type || "agent", on: false, d: x, i, n: done.length }));
        (s.pending ?? []).slice(-4).forEach((x, i) => out.push({ id: "pend" + i, kind: "pend", r: 0.14, col: cPend,
                                                                 label: x.type, on: true, d: x, i, n: 1 }));
        return out;
    }

    function target(nd, t) {
        switch (nd.kind) {
        case "lead": return [0, 0, 0];
        case "advisor": return [0, 2.1 + Math.sin(t * 1.3) * 0.08, 0];
        case "sub": {
            const a = nd.i / nd.n * Math.PI * 2 + t * 0.22;
            const r = 2.7 + Math.sin(t * 0.9 + nd.i) * 0.12;
            return [Math.cos(a) * r, Math.sin(t * 1.1 + nd.i * 1.7) * 0.25, Math.sin(a) * r];
        }
        case "done": {
            const a = nd.i / Math.max(1, nd.n) * Math.PI * 2 - t * 0.05 + 0.4;
            return [Math.cos(a) * 4.0, -0.75, Math.sin(a) * 4.0];
        }
        default: { // pending: đang được lead "phóng" ra
            const k = (t * 0.6 + nd.i * 0.25) % 1;
            const a = nd.i * 1.9 + 0.6;
            return [Math.cos(a) * 2.7 * k, 0, Math.sin(a) * 2.7 * k];
        }
        }
    }

    // ------------------------------------------------------------------ camera
    property real yaw: 0.6
    property real pitch: 0.42
    property real dist: 10
    property bool spin: true
    property real t: 0
    property var cur: ({})             // id -> [x,y,z] đang nội suy
    property var proj: ({})            // id -> {x,y,s,d} trên màn hình
    property string hovered: ""

    function project(p, w, h) {
        const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
        const x = p[0], y = p[1] - 0.25, z = p[2];
        const x1 = x * cy - z * sy, z1 = x * sy + z * cy;
        const y2 = y * cp - z1 * sp, z2 = y * sp + z1 * cp;
        const d = Math.max(0.5, z2 + dist);
        const f = Math.min(w, h) * 1.15;
        return { x: w / 2 + x1 * f / d, y: h / 2 - y2 * f / d, s: f / d, d };
    }

    function step(dt) {
        t += dt;
        if (spin && !drag.pressed) yaw += dt * 0.12;
        const w = scene.width, h = scene.height, c = {}, p = {};
        const k = 1 - Math.pow(0.02, dt);  // nội suy mượt, độc lập fps
        for (const nd of nodes) {
            const tg = target(nd, t), o = cur[nd.id] ?? (nd.kind === "lead" ? tg : [0, 0, 0]);
            const v = [o[0] + (tg[0] - o[0]) * k, o[1] + (tg[1] - o[1]) * k, o[2] + (tg[2] - o[2]) * k];
            c[nd.id] = v;
            p[nd.id] = project(v, w, h);
        }
        cur = c;
        proj = p;
        scene.requestPaint();
    }

    FrameAnimation {
        running: win.visible
        onTriggered: app.step(Math.min(0.05, frameTime))
    }

    // ------------------------------------------------------------------ thành phần HUD
    component T: Text {
        color: app.fg
        font.family: app.mono
        font.pixelSize: 12
    }
    component Panel: Rectangle {
        color: Qt.rgba(0.08, 0.09, 0.12, 0.72)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        radius: 8
    }


    // ------------------------------------------------------------------ cửa sổ
    FloatingWindow {
        id: win
        title: "Claude Agent Space"
        implicitWidth: 1000
        implicitHeight: 700
        minimumSize: Qt.size(640, 460)
        color: app.bg
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_R) { app.yaw = 0.6; app.pitch = 0.42; app.dist = 10; }
                else if (e.key === Qt.Key_Space) app.spin = !app.spin;
                else if (e.key === Qt.Key_0 || e.key === Qt.Key_A) app.pinned = "";
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_8) {
                    const x = app.sessionList[e.key - Qt.Key_1];
                    if (x) app.pinned = x.id;
                } else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Q) Qt.quit();
            }

            // nền: trời sao (vẽ 1 lần)
            Canvas {
                id: stars
                anchors.fill: parent
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const g = ctx.createRadialGradient(width / 2, height * 0.45, 0, width / 2, height * 0.45, Math.max(width, height) * 0.7);
                    g.addColorStop(0, "#1a1d29");
                    g.addColorStop(1, "#0b0c11");
                    ctx.fillStyle = g;
                    ctx.fillRect(0, 0, width, height);
                    let seed = 7;
                    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
                    for (let i = 0; i < 260; i++) {
                        ctx.fillStyle = `rgba(200,210,255,${0.15 + rnd() * 0.5})`;
                        const r = rnd() < 0.08 ? 1.6 : 0.9;
                        ctx.fillRect(rnd() * width, rnd() * height, r, r);
                    }
                }
            }

            // cảnh 3D
            Canvas {
                id: scene
                anchors.fill: parent
                renderTarget: Canvas.FramebufferObject
                onPaint: app.paintScene(getContext("2d"), width, height)
            }

            // nhãn chữ (Text cho nét chữ sắc), đi theo vị trí chiếu của từng nút
            Repeater {
                model: app.nodes
                Item {
                    id: lab
                    required property var modelData
                    readonly property var p: app.proj[modelData.id] ?? null
                    readonly property bool show: !!p && modelData.kind !== "pend" && !(modelData.kind === "advisor" && modelData.ghost)
                    visible: show
                    x: p ? p.x : 0
                    y: p ? p.y + modelData.r * p.s + 6 : 0
                    z: p ? 1000 - p.d * 10 : 0
                    opacity: modelData.kind === "done" ? 0.55 : 1
                    Column {
                        x: -width / 2
                        spacing: 1
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: lab.modelData.label
                            color: app.qc(lab.modelData.col)
                            font { family: app.mono; pixelSize: lab.modelData.kind === "lead" ? 14 : 11; bold: true }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: text !== ""
                            color: app.muted
                            font { family: app.mono; pixelSize: 10 }
                            text: {
                                const m = lab.modelData, d = m.d;
                                if (m.kind === "lead") return `tools ${app.s?.tools ?? 0} · turn ${app.s?.turns ?? 0}`;
                                if (!d) return "";
                                if (m.kind === "sub") return `${app.cap(d.model)} · ${d.tools}⚒${d.tool ? " · " + d.tool : ""}`;
                                if (m.kind === "advisor") return m.on ? "đang đọc phiên…" : `${app.s?.advisor?.calls ?? 0} lần gọi`;
                                return `✓ ${Math.round((d.end || d.start) - d.start)}s`;
                            }
                        }
                    }
                }
            }

            // chuột: xoay / zoom / di qua nút
            MouseArea {
                id: drag
                anchors.fill: parent
                hoverEnabled: true
                property real lx; property real ly
                onPressed: m => { lx = m.x; ly = m.y; root.forceActiveFocus(); }
                onPositionChanged: m => {
                    if (pressed) {
                        app.yaw += (m.x - lx) * 0.008;
                        app.pitch = Math.max(-0.2, Math.min(1.35, app.pitch + (m.y - ly) * 0.006));
                        lx = m.x; ly = m.y;
                    }
                    let best = "", bd = 1e9;
                    for (const nd of app.nodes) {
                        const p = app.proj[nd.id];
                        if (!p || nd.kind === "pend") continue;
                        const dd = Math.hypot(p.x - m.x, p.y - m.y);
                        if (dd < Math.max(12, nd.r * p.s) && p.d < bd) { best = nd.id; bd = p.d; }
                    }
                    app.hovered = best;
                    tip.mx = m.x; tip.my = m.y;
                }
                onExited: app.hovered = ""
                onWheel: w => app.dist = Math.max(6.5, Math.min(18, app.dist * (w.angleDelta.y > 0 ? 0.92 : 1.08)))
                onDoubleClicked: app.spin = !app.spin
            }

            // ---------------------------------------------------------- HUD
            // trên trái: phiên
            Panel {
                x: 14; y: 14
                width: info.implicitWidth + 24; height: info.implicitHeight + 20
                ColumnLayout {
                    id: info
                    x: 12; y: 10
                    spacing: 3
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            width: 9; height: 9; radius: 5
                            color: app.live ? app.qc(app.cFork) : app.muted
                            SequentialAnimation on opacity {
                                running: app.live; loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 700 }
                                NumberAnimation { to: 1; duration: 700 }
                            }
                        }
                        T { text: "CLAUDE AGENT SPACE"; font.bold: true; font.letterSpacing: 1.5 }
                    }
                    T { text: app.s ? "📁 " + app.base(app.s.cwd) : "chưa có phiên nào — chạy claude để bắt đầu"; color: app.muted }
                    T {
                        visible: !!app.s
                        text: app.cap(app.s?.model) + "  effort " + app.effortBlocks(app.s?.effort) + " " + (app.s?.effort || "—")
                        color: app.qc(app.cLead)
                    }
                    T {
                        visible: !!app.s
                        text: `phase ${app.phase} · ${app.running}/${app.swarm.length} agent đang chạy`
                    }
                    T {
                        visible: !!app.s
                        color: app.muted
                        text: `lead tools ${app.s?.tools ?? 0} · swarm tools ${app.swarm.reduce((n, x) => n + x.tools, 0)}`
                    }
                }
            }

            // trên phải: chọn phiên
            Column {
                anchors { top: parent.top; right: parent.right; margins: 14 }
                spacing: 5
                Repeater {
                    model: app.sessionList
                    Panel {
                        required property var modelData
                        required property int index
                        readonly property bool sel: modelData.id === app.sid
                        readonly property bool busy: modelData.busy || Object.values(modelData.subs ?? {}).some(x => x.status === "running")
                        anchors.right: parent.right
                        width: row.implicitWidth + 18; height: 26
                        border.color: sel ? app.qc(app.cLead, 0.8) : Qt.rgba(1, 1, 1, 0.08)
                        Row {
                            id: row
                            anchors.centerIn: parent
                            spacing: 6
                            T { text: (parent.parent.index + 1) + ""; color: app.muted }
                            T { text: parent.parent.busy ? "●" : "○"; color: parent.parent.busy ? app.qc(app.cFork) : app.muted }
                            T { text: app.base(parent.parent.modelData.cwd) }
                            T { text: app.ago(parent.parent.modelData.at); color: app.muted }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.pinned = parent.sel && app.pinned ? "" : parent.modelData.id
                        }
                    }
                }
                T {
                    anchors.right: parent.right
                    text: app.pinned ? "📌 đã ghim · 0 = theo phiên mới" : "tự theo phiên mới nhất"
                    color: app.muted; font.pixelSize: 10
                }
            }

            // cảnh báo lỗi lặp
            Panel {
                visible: !!app.s?.repeatError
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 14 }
                width: Math.min(parent.width * 0.5, errT.implicitWidth + 24); height: 30
                border.color: app.qc(app.cErr, 0.8)
                T {
                    id: errT
                    anchors.centerIn: parent
                    width: parent.width - 24
                    elide: Text.ElideRight
                    text: "⚠ cùng lỗi ×2 · " + (app.s?.repeatError ?? "")
                    color: app.qc(app.cErr)
                }
            }

            // lời khuyên advisor gần nhất
            Panel {
                readonly property var lines: app.s?.advisor?.last ?? []
                visible: Array.isArray(lines) && lines.length > 0
                anchors { left: parent.left; bottom: legend.top; margins: 14 }
                width: Math.min(360, parent.width * 0.4); height: advCol.implicitHeight + 18
                border.color: app.qc(app.cAdv, 0.5)
                Column {
                    id: advCol
                    x: 12; y: 9; width: parent.width - 24
                    spacing: 3
                    T { text: "ADVISOR · " + app.ago(app.s?.advisor?.at ?? 0) + " trước"; color: app.qc(app.cAdv); font.bold: true }
                    Repeater {
                        model: parent.parent.lines
                        T { required property string modelData; text: "» " + modelData; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                }
            }

            // dưới trái: chú thích
            Panel {
                id: legend
                anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                width: legRow.implicitWidth + 24; height: 30
                Row {
                    id: legRow
                    anchors.centerIn: parent
                    spacing: 14
                    Repeater {
                        model: [
                            { c: app.cLead, t: "lead" }, { c: app.cSwarm, t: "subagent" }, { c: app.cFork, t: "fork" },
                            { c: app.cAdv, t: "advisor" }, { c: app.cDone, t: "xong" }
                        ]
                        Row {
                            required property var modelData
                            spacing: 5
                            Rectangle { width: 9; height: 9; radius: 5; color: app.qc(parent.modelData.c); anchors.verticalCenter: parent.verticalCenter }
                            T { text: parent.modelData.t; color: app.muted }
                        }
                    }
                }
            }

            // dưới phải: điều khiển
            T {
                anchors { right: parent.right; bottom: parent.bottom; margins: 18 }
                text: "kéo: xoay · cuộn: zoom · R: đặt lại · Space: " + (app.spin ? "dừng xoay" : "tự xoay")
                color: app.muted; font.pixelSize: 10
            }

            // tooltip khi di chuột qua nút
            Panel {
                id: tip
                property real mx; property real my
                readonly property var nd: app.nodes.find(n => n.id === app.hovered) ?? null
                visible: !!nd && !drag.pressed
                x: Math.min(parent.width - width - 8, mx + 16)
                y: Math.min(parent.height - height - 8, my + 16)
                z: 2000
                width: Math.max(220, tipCol.implicitWidth + 24); height: tipCol.implicitHeight + 18
                border.color: nd ? app.qc(nd.col, 0.7) : "transparent"
                Column {
                    id: tipCol
                    x: 12; y: 9
                    spacing: 3
                    width: 300
                    T { text: tip.nd?.label ?? ""; color: tip.nd ? app.qc(tip.nd.col) : app.fg; font.bold: true }
                    Repeater {
                        model: {
                            const n = tip.nd, d = n?.d;
                            if (!n) return [];
                            if (n.kind === "lead") return [
                                "phiên chính · " + app.base(app.s?.cwd),
                                "effort " + (app.s?.effort || "—") + " · turn " + (app.s?.turns ?? 0),
                                (app.s?.busy ? "◐ đang làm việc" : "○ rảnh") + " · " + (app.s?.tools ?? 0) + " tool calls"
                            ];
                            if (!d) return ["chưa được gọi trong phiên này"];
                            const rows = ["model " + app.cap(d.model) + (d.fork ? " · fork" : "") + (d.bg ? " · nền" : "")];
                            if (d.desc) rows.push("“" + d.desc + "”");
                            rows.push(d.tools + " tool calls" + (d.tool ? " · đang dùng " + d.tool : ""));
                            rows.push(d.status === "running" ? "◐ chạy " + app.ago(d.start)
                                                             : "✓ xong sau " + Math.round((d.end || d.start) - d.start) + "s · " + app.ago(d.end || d.start) + " trước");
                            return rows;
                        }
                        T { required property string modelData; text: modelData; width: 300; wrapMode: Text.Wrap; color: app.fg }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ vẽ cảnh
    function paintScene(ctx, w, h) {
        ctx.reset();
        ctx.clearRect(0, 0, w, h);
        const P = p => project(p, w, h);

        // sàn lưới
        const G = 6, fy = -1.25;
        ctx.lineWidth = 1;
        for (let i = -G; i <= G; i++) {
            for (const [a, b] of [[[i, fy, -G], [i, fy, G]], [[-G, fy, i], [G, fy, i]]]) {
                const pa = P(a), pb = P(b);
                const grad = ctx.createLinearGradient(pa.x, pa.y, pb.x, pb.y);
                const fa = Math.max(0, 0.22 - Math.abs(i) * 0.03);
                grad.addColorStop(0, "rgba(120,140,200,0)");
                grad.addColorStop(0.5, `rgba(120,140,200,${fa})`);
                grad.addColorStop(1, "rgba(120,140,200,0)");
                ctx.strokeStyle = grad;
                ctx.beginPath(); ctx.moveTo(pa.x, pa.y); ctx.lineTo(pb.x, pb.y); ctx.stroke();
            }
        }
        // vòng quỹ đạo trên sàn
        for (const [r, a] of [[2.7, 0.18], [4.0, 0.08]]) {
            ctx.strokeStyle = `rgba(122,167,240,${a})`;
            ctx.setLineDash(r > 3 ? [3, 6] : []);
            ctx.beginPath();
            for (let k = 0; k <= 72; k++) {
                const q = P([Math.cos(k / 72 * Math.PI * 2) * r, 0, Math.sin(k / 72 * Math.PI * 2) * r]);
                k ? ctx.lineTo(q.x, q.y) : ctx.moveTo(q.x, q.y);
            }
            ctx.stroke();
        }
        ctx.setLineDash([]);

        const items = [];   // {d, f} vẽ từ xa tới gần
        const lead = cur["lead"];

        // dây nối + hạt dữ liệu
        for (const nd of nodes) {
            const pos = cur[nd.id];
            if (!pos || nd.kind === "lead" || !lead) continue;
            if (nd.kind === "advisor" && nd.ghost) continue;
            const pa = proj["lead"], pb = proj[nd.id];
            const act = nd.on;
            const col = nd.col;
            items.push({ d: (pa.d + pb.d) / 2 + 0.01, f: () => {
                const g = ctx.createLinearGradient(pa.x, pa.y, pb.x, pb.y);
                g.addColorStop(0, css(cLead, act ? 0.55 : 0.12));
                g.addColorStop(1, css(col, act ? 0.75 : 0.15));
                ctx.strokeStyle = g;
                ctx.lineWidth = act ? 1.6 : 1;
                ctx.setLineDash(nd.kind === "advisor" || nd.kind === "done" ? [4, 5] : []);
                ctx.beginPath(); ctx.moveTo(pa.x, pa.y); ctx.lineTo(pb.x, pb.y); ctx.stroke();
                ctx.setLineDash([]);
            } });
            if (!act || nd.kind === "pend") continue;
            // gói tin: đi ra (giao việc) và chạy về (kết quả), nhanh hơn khi agent dùng nhiều tool
            const n = 3, sp = 0.45 + Math.min(1, (nd.d?.tools ?? 0) / 30) * 0.6;
            for (let k = 0; k < n; k++) {
                for (const dir of [1, -1]) {
                    let u = (t * sp + k / n + (dir < 0 ? 0.5 / n : 0)) % 1;
                    if (dir < 0) u = 1 - u;
                    const q = P([lead[0] + (pos[0] - lead[0]) * u, lead[1] + (pos[1] - lead[1]) * u, lead[2] + (pos[2] - lead[2]) * u]);
                    const c = dir > 0 ? cLead : col;
                    items.push({ d: q.d, f: () => glow(ctx, q.x, q.y, Math.max(2, q.s * 0.05), c, 0.9) });
                }
            }
        }

        // các quả cầu
        for (const nd of nodes) {
            const p = proj[nd.id];
            if (!p) continue;
            if (nd.kind === "advisor" && nd.ghost) {
                items.push({ d: p.d, f: () => {
                    ctx.strokeStyle = css(cAdv, 0.25);
                    ctx.setLineDash([2, 4]);
                    ctx.beginPath(); ctx.arc(p.x, p.y, nd.r * p.s, 0, Math.PI * 2); ctx.stroke();
                    ctx.setLineDash([]);
                } });
                continue;
            }
            items.push({ d: p.d, f: () => sphere(ctx, nd, p) });
        }

        // electron quanh lõi lead (3 quỹ đạo nghiêng)
        if (lead) {
            const busy = !!s?.busy;
            const R = 1.05;
            for (let o = 0; o < 3; o++) {
                const tx = 1.1, ty = o * Math.PI / 3 + t * 0.15;
                const ring = a => {
                    let x = Math.cos(a) * R, y = Math.sin(a) * R, z = 0;
                    const y1 = y * Math.cos(tx), z1 = y * Math.sin(tx);
                    return [x * Math.cos(ty) + z1 * Math.sin(ty), y1, -x * Math.sin(ty) + z1 * Math.cos(ty)];
                };
                for (let k = 0; k < 48; k++) {
                    const a0 = k / 48 * Math.PI * 2, a1 = (k + 1) / 48 * Math.PI * 2;
                    const q0 = P(ring(a0)), q1 = P(ring(a1));
                    items.push({ d: (q0.d + q1.d) / 2, f: () => {
                        ctx.strokeStyle = css(cLead, busy ? 0.4 : 0.16);
                        ctx.lineWidth = 1;
                        ctx.beginPath(); ctx.moveTo(q0.x, q0.y); ctx.lineTo(q1.x, q1.y); ctx.stroke();
                    } });
                }
                const e = P(ring(t * (busy ? 2.4 : 0.5) + o * 2.1));
                items.push({ d: e.d, f: () => glow(ctx, e.x, e.y, Math.max(2.5, e.s * 0.07), mix(cLead, 0.4), busy ? 1 : 0.5) });
            }
        }

        items.sort((a, b) => b.d - a.d);
        for (const it of items) it.f();
    }

    function glow(ctx, x, y, r, c, a) {
        const g = ctx.createRadialGradient(x, y, 0, x, y, r * 3);
        g.addColorStop(0, css(mix(c, 0.6), a));
        g.addColorStop(0.3, css(c, a * 0.6));
        g.addColorStop(1, css(c, 0));
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(x, y, r * 3, 0, Math.PI * 2); ctx.fill();
    }

    function sphere(ctx, nd, p) {
        const r = nd.r * p.s;
        const c = nd.col;
        const pulse = nd.on ? 0.5 + 0.5 * Math.sin(t * 4 + (nd.i ?? 0)) : 0;
        // quầng sáng khi đang hoạt động
        if (nd.on || nd.kind === "lead") {
            const R = r * (2.2 + pulse * 0.6);
            const g = ctx.createRadialGradient(p.x, p.y, r * 0.6, p.x, p.y, R);
            g.addColorStop(0, css(c, nd.on ? 0.35 : 0.12));
            g.addColorStop(1, css(c, 0));
            ctx.fillStyle = g;
            ctx.beginPath(); ctx.arc(p.x, p.y, R, 0, Math.PI * 2); ctx.fill();
        }
        // bóng trên sàn
        const sh = project([cur[nd.id][0], -1.25, cur[nd.id][2]], scene.width, scene.height);
        ctx.fillStyle = "rgba(0,0,0,0.35)";
        ctx.beginPath();
        ctx.ellipse(sh.x - r * 0.9, sh.y - r * 0.25, r * 1.8, r * 0.5);
        ctx.fill();
        // thân cầu: ánh sáng từ trên trái
        const g = ctx.createRadialGradient(p.x - r * 0.35, p.y - r * 0.4, r * 0.05, p.x, p.y, r);
        g.addColorStop(0, css(mix(c, 0.75), 1));
        g.addColorStop(0.45, css(c, 1));
        g.addColorStop(1, css(shade(c, 0.28), 1));
        ctx.fillStyle = g;
        ctx.globalAlpha = nd.kind === "done" ? 0.6 : nd.kind === "pend" ? 0.7 : 1;
        ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, Math.PI * 2); ctx.fill();
        // vành sáng (rim light)
        ctx.strokeStyle = css(mix(c, 0.5), nd.on ? 0.6 + pulse * 0.4 : 0.25);
        ctx.lineWidth = 1;
        ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, Math.PI * 2); ctx.stroke();
        ctx.globalAlpha = 1;
        // advisor: vòng halo xoay
        if (nd.kind === "advisor") {
            ctx.strokeStyle = css(cAdv, nd.on ? 0.8 : 0.35);
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.ellipse(p.x - r * 1.7, p.y - r * 0.45, r * 3.4, r * 0.9);
            ctx.stroke();
        }
        // vòng tiến độ quanh subagent (số tool call)
        if (nd.kind === "sub" && nd.d) {
            const frac = Math.min(0.95, nd.d.tools / Math.max(8, ...swarm.map(x => x.tools)));
            ctx.strokeStyle = css(mix(c, 0.3), 0.9);
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(p.x, p.y, r + 4, -Math.PI / 2 + t, -Math.PI / 2 + t + Math.max(0.15, frac) * Math.PI * 2);
            ctx.stroke();
        }
        if (hovered === nd.id) {
            ctx.strokeStyle = "rgba(255,255,255,0.8)";
            ctx.lineWidth = 1;
            ctx.setLineDash([3, 3]);
            ctx.beginPath(); ctx.arc(p.x, p.y, r + 8, 0, Math.PI * 2); ctx.stroke();
            ctx.setLineDash([]);
        }
    }
}
