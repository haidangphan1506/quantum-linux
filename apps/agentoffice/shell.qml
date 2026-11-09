import QtQuick
import QtQuick.Layouts
import QtQuick3D
import QtQuick3D.Helpers
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Claude Agents City: MỘT thành phố 3D (QtQuick3D, GPU) có lưới đường chung; mỗi dự án (nhóm phiên Claude Code theo cwd,
// base(cwd) là tên dự án) là MỘT NGÔI NHÀ trên một lô đất dọc phố. Bên trong mỗi nhà là văn phòng thu gọn có các mascot Claude cam (kiểu Clawd).
// Dữ liệu: ../agentviz/collector.py (hook của Claude Code) ghi ~/.cache/claude-agentviz/state.json.
//   Mỗi nhà có 3 vai cố định (luôn có mặt, kể cả khi rảnh): Sonnet = kiểm tra, và điều phối khi Jev không đủ tin cậy (bàn cạnh sếp),
//   Haiku = thực hiện (chỗ ngồi đầu tiên), Opus = việc khó chỉ khi người dùng yêu cầu (bàn lớn), + Jev (điều phối; hook router; dòng "Jev ▸" ở HUD hiện quyết định gần nhất và quality).
//   Phiên MỚI NHẤT của cwd đó quyết định lead (model nào thì vai đó là lead) và subagent / fork / advisor:
//   subagent = mascot viền xanh đi từ vỉa hè vào cửa nhà, theo lối đi tới chỗ trong 2 cụm bàn rồi gõ phím; màn hình chạy code
//   fork     = viền xanh lá; advisor = viền tím viết lời khuyên lên bảng trắng
//   xong     = đi sang góc nghỉ (sofa, máy cà phê), cầm cốc
//   gói tin  = khối sáng bay vòng cung giữa bàn sếp và mascot đang chạy
//   Màu viền / đèn ăng-ten / huy hiệu phân biệt vai & model (Opus cam đậm, Sonnet hồng, Haiku ngọc, Jev vàng ...)
// Tối đa 8 nhà trên 8 lô cố định hai bên phố chính (phố cắt ngang ở giữa có bùng binh, đèn giao thông). Lô trống = công viên nhỏ.
// Toàn cảnh: nhà có mái; trạng thái thấy qua đèn cửa sổ, khói ống khói, biển tên (● đang chạy · số agent).
// Vào một nhà: mái nhấc lên, tường phía camera hạ thấp (cutaway) để nhìn vào trong; nhà khác giữ mái, nội thất ẩn để nhẹ GPU.
// Đơn vị: 1 m = 100 đơn vị Quick3D. Mỗi nhà: x ∈ [-7, 7], z ∈ [-5, 5] (toạ độ cục bộ), sàn y = 0, cửa ở tường trước (z = +5) hướng ra phố.
//   Toạ độ thế giới = (cx + sg·x, cz + sg·z), sg = -1 cho nhà phía nam (xoay 180° để cửa vẫn hướng ra phố).
// Mở: apps/agentoffice/claude-agentoffice   (hoặc qs -p ~/dev/cael-src/apps/agentoffice/shell.qml)
// Điều khiển: kéo chuột = xoay · cuộn = zoom · click nhà / phím 1..8 / chip bên phải = vào nhà · 0 / A / R = toàn cảnh · Space = tự xoay
// Thử với dữ liệu khác: AGENTVIZ_STATE=/đường/dẫn/state.json qs -p …
// IPC: qs -p … ipc call agentoffice close|status|focus <0..8>|shot /đường/dẫn.png
ShellRoot {
    id: app

    // ------------------------------------------------------------------ màu
    readonly property color bg: "#0d0f14"
    readonly property color fg: "#d6d8de"
    readonly property color muted: "#7c818c"
    readonly property color cLead: "#e0805a"
    readonly property color cOrch: "#e070b0"
    readonly property color cWorker: "#45c8d8"
    readonly property color cJev: "#e8c548"
    readonly property color cSwarm: "#6ea0f0"
    readonly property color cFork: "#5fc482"
    readonly property color cAdv: "#a092f0"
    readonly property color cErr: "#f06e6e"
    readonly property color cDone: "#808692"
    readonly property color cOk: "#6edc8c"
    readonly property color cWait: "#f0be5a"
    readonly property string mono: "CaskaydiaCove Nerd Font Mono"

    readonly property color mWood: "#a8805a"
    readonly property color mMetal: "#464c58"
    readonly property color mDark: "#22252c"
    readonly property color mHead: "#dee2ea"
    readonly property color cClaude: "#d97757"     // thân mascot
    readonly property color cGrey: "#8a8f99"
    readonly property color cWhite: "#ffffff"

    // màu mái / tường theo hash dự án (dễ phân biệt các nhà)
    readonly property var roofPal: ["#b5523b", "#4f6d8f", "#5f8a4e", "#8a5a9e", "#c08a3a", "#3f7f86", "#a0443f", "#6a6f7c"]
    readonly property var wallPal: ["#d9cbb4", "#c9d3dc", "#e0d0c0", "#bfc8b8", "#d8c2c8", "#cfc6a8", "#c4c0d4"]

    function mixc(a, b, k) { return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1); }
    function rnd(x) { const v = Math.sin(x * 12.9898) * 43758.5453; return v - Math.floor(v); }

    // ------------------------------------------------------------------ dữ liệu
    property var st: ({})
    property string stText: ""
    property real now: Date.now() / 1000
    readonly property var sessionList: Object.values(st.sessions ?? {}).sort((a, b) => b.at - a.at)

    // hash của cwd: id mascot ổn định khi thêm/bớt dự án (không phụ thuộc chỉ số lô), màu nhà
    function hnum(k) { let h = 5381; for (let i = 0; i < k.length; i++) h = ((h * 33) ^ k.charCodeAt(i)) >>> 0; return h; }
    function hkey(k) { return hnum(k).toString(36); }
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
        onLoaded: {
            const tx = text();
            if (tx === app.stText) return;      // không đổi: khỏi dựng lại cảnh
            try {
                const first = app.stText === "";
                app.st = JSON.parse(tx) ?? {};
                app.stText = tx;
                if (first) app.sessionSince = app.t;   // lần tải đầu: mascot hiện ngay tại chỗ, không đi từ vỉa hè vào
            } catch (e) {}
        }
    }
    // quyết định định tuyến mới nhất của Jev router (~/.claude/jev-router/hook.py ghi)
    property var jev: null
    FileView {
        id: jevFile
        path: Quickshell.env("HOME") + "/.cache/claude-agentviz/jev.json"
        onLoaded: { try { app.jev = JSON.parse(text()); } catch (e) { app.jev = null; } }
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { app.now = Date.now() / 1000; file.reload(); jevFile.reload(); }
    }

    // Thu nhỏ cửa sổ (Hyprland không có minimize gốc, Qt không báo Minimized): minimize.lua (nút vàng, dock, menu bar,
    // hyprctl eval 'cael_minimize(…)') đẩy cửa sổ sang "special:minimized" bằng window.move(follow = false)
    // => event movewindow>>ADDR,special:minimized / movewindowv2>>ADDR,special:minimized,special:minimized
    // => đang ở trong nhà thì về toàn cảnh. Đọc thẳng data của event, không polling/IPC.
    property string myAddr: ""                     // address (không 0x) của cửa sổ này
    function normAddr(a) { return (a ?? "").toLowerCase().replace(/^0x/, ""); }
    // Tìm address từ Hyprland.toplevels (không phụ thuộc thời điểm openwindow: qs -p hot reload giữ nguyên cửa sổ cũ
    // nên không có openwindow mới). Cửa sổ của chính mình có thể có title/lastIpcObject rỗng ở phía Hyprland IPC,
    // nên ưu tiên title/appId của wlr-foreign-toplevel (t.wayland).
    function syncMyAddr() {
        for (const t of Hyprland.toplevels.values) {
            const cls = t.wayland?.appId || t.lastIpcObject?.class || "";
            const ttl = t.wayland?.title || t.title || "";
            if (cls === "org.quickshell" && ttl === win.title) { app.myAddr = app.normAddr(t.address); return; }
        }
    }
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { app.syncMyAddr(); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "openwindow") {               // ADDR,WSNAME,CLASS,TITLE (fallback)
                const q = ev.data.split(",");
                if (q[2] === "org.quickshell" && q.slice(3).join(",") === win.title) app.myAddr = app.normAddr(q[0]);
                return;
            }
            if (app.sel < 0) return;
            if (ev.name !== "movewindow" && ev.name !== "movewindowv2") return;
            const p = ev.data.split(",");                 // v2: ADDR,WSID,WSNAME   v1: ADDR,WSNAME
            const ws = (ev.name === "movewindowv2" ? p.slice(2) : p.slice(1)).join(",");
            if (ws !== "special:minimized") return;       // trùng MIN_WS trong ~/.config/hypr/hyprlands/minimize.lua
            if (app.myAddr === "") app.syncMyAddr();      // wayland handle có thể gắn muộn hơn valuesChanged
            if (app.normAddr(p[0]) === app.myAddr) app.flyOverview();
        }
    }

    IpcHandler {
        target: "agentoffice"
        function close(): void { Qt.quit(); }
        // chụp cửa sổ ra file PNG (không phụ thuộc workspace đang hiện)
        function shot(path: string): void { root.grabToImage(r => r.saveToFile(path)); }
        // vào nhà n (1..8), 0 = toàn cảnh
        function focus(n: int): void { if (n >= 1) app.flyHouse(n - 1); else app.flyOverview(); }
        function status(): string {
            const hs = app.houses.map(c => ({ index: c.i + 1, name: c.name, cwd: c.cwd, sessions: c.nSess, model: c.s?.model ?? "", live: c.live,
                                              running: c.running, agents: c.nAgents, phase: c.phase }));
            // cities: alias cũ của houses (giữ tương thích script cũ)
            return JSON.stringify({ live: app.live, phase: app.hc.phase, swarm: app.hc.swarm.length, running: app.hc.running, selected: app.sel,
                                    dist: app.dist, houses: hs, cities: hs });
        }
    }

    // ------------------------------------------------------------------ bố cục một nhà (toạ độ cục bộ)
    readonly property real rx: 7
    readonly property real rz: 5
    readonly property real doorX: -6.0                // cửa chính ở tường trước (z = +rz), thẳng hành lang trái
    readonly property var entry: [-6.0, 7.8]          // điểm xuất hiện trên vỉa hè trước cửa (subagent mới)
    readonly property var corridors: [-6.0, 4.0]      // lối đi vòng qua cụm bàn
    readonly property var pods: [-3.4, 1.4]
    readonly property real podZ: 1.4
    readonly property var seats: {
        const out = [];
        for (const side of [-1, 1])
            for (const px of pods)
                for (const dx of [-0.95, 0.95])
                    out.push({ x: px + dx, z: podZ + side * 0.86, h: side < 0 ? 0 : Math.PI, side });
        return out;
    }
    readonly property var lounge: [[5.0, -3.4], [5.0, -1.3], [4.4, -1.8], [4.4, -0.8], [5.3, -4.4], [5.3, -0.7]]
    readonly property var gaps: [-5.3, -2.05, 1.85, 4.2]   // khe hở giữa các bàn ở hàng cuối phòng (z < -3.75)
    readonly property var board: [-6.3, -1.5]

    // ---- thành phố: 8 lô cố định hai bên phố chính (z = 0); [x tâm, phía] với phía -1 = bắc (cửa nhìn +z), +1 = nam (xoay 180°)
    readonly property var lots: [[-13, -1], [13, -1], [-13, 1], [13, 1], [-30, -1], [30, -1], [-30, 1], [30, 1]]
    readonly property real lotOZ: 11.5               // |z| tâm nhà: phố 3 m + vỉa hè 2 m + sân trước 1.5 m + nửa nhà 5 m

    // ------------------------------------------------------------------ nhân vật
    // 3 vai cố định mỗi nhà, luôn có mặt (kể cả khi rảnh / chưa có phiên): Sonnet = kiểm tra / điều phối, Haiku = thực hiện, Opus = việc khó (theo yêu cầu).
    // Phiên Claude Code đang chạy bằng model nào thì mascot vai đó là "lead" (hiện số liệu phiên, giao việc cho subagent).
    function fam(m) { m = (m ?? "").toLowerCase(); return ["opus", "sonnet", "haiku"].find(f => m.includes(f)) ?? ""; }
    readonly property var roles: ({
        opus:   { title: "KHÓ", name: "Opus",   col: cLead,   sc: 1.3 },
        sonnet: { title: "KIỂM TRA", name: "Sonnet", col: cOrch,   sc: 1.15 },
        haiku:  { title: "THỰC HIỆN", name: "Haiku",  col: cWorker, sc: 1.0 },
        jev:    { title: "ĐIỀU PHỐI", name: "Jev",   col: cJev,    sc: 1.15 }
    })
    // chỗ đứng của từng vai + vị trí mặt bàn (điểm gói tin xuất phát): sếp & điều phối ở hàng bàn cuối phòng, thực hiện ở chỗ ngồi 0
    readonly property var stations: ({
        opus:   { x: 0,     z: -4.3, h: 0, desk: [0, -3.3] },
        sonnet: { x: -3.6,  z: -4.3, h: 0, desk: [-3.6, -3.3] },
        haiku:  { x: seats[0].x, z: seats[0].z, h: seats[0].h, desk: [seats[0].x, podZ] },
        jev:    { x: 3.0,   z: -4.3, h: 0, desk: [3.0, -3.3] }
    })

    // ---- các nhà: nhóm phiên theo cwd (tối đa 8 cwd gần nhất, xếp theo tên để lô ổn định)
    readonly property var houses: {
        const by = {}, keys = [];
        for (const x of sessionList) {
            const k = x.cwd || "";
            if (!by[k]) { by[k] = []; keys.push(k); }     // sessionList mới nhất trước
            by[k].push(x);
        }
        const ks = keys.slice(0, 8).sort((a, b) => base(a).localeCompare(base(b)) || (a < b ? -1 : a > b ? 1 : 0));
        if (ks.length === 0) ks.push("");
        return ks.map((k, i) => {
            const sess = by[k] ?? [];
            const s = sess[0] ?? null;
            const subsAll = s ? Object.values(s.subs ?? {}).sort((a, b) => a.start - b.start) : [];
            const swarm = subsAll.filter(x => !x.advisor);
            const advisorRuns = subsAll.filter(x => x.advisor);
            const running = swarm.filter(x => x.status === "running").length;
            const advisorRunning = advisorRuns.some(x => x.status === "running");
            const leadFam = fam(s?.model) || "opus";
            const L = lots[i], cx = L[0], cz = L[1] * lotOZ, sg = -L[1];
            const hn = hnum(k);
            const pf = "k" + hkey(k) + "-";
            const nodes = [];
            for (const f of ["opus", "sonnet", "haiku", "jev"]) {
                const r = roles[f], lead = f === leadFam;
                nodes.push({ id: pf + "role-" + f, ci: i, cx, cz, sg, kind: "role", fam: f, col: r.col, sc: r.sc, lead,
                             label: r.title + " · " + (lead && s ? cap(s.model) : r.name) });
            }
            if (s) {
                const adv = advisorRuns[advisorRuns.length - 1];
                if (adv) nodes.push({ id: pf + "advisor", ci: i, cx, cz, sg, kind: "advisor", col: cAdv, label: "advisor", d: adv });
                const run = swarm.filter(x => x.status === "running");
                const done = swarm.filter(x => x.status !== "running").slice(-lounge.length);
                run.forEach(x => nodes.push({ id: pf + x.id, ci: i, cx, cz, sg, kind: "sub", col: x.fork ? cFork : cSwarm, label: x.type || "agent", d: x }));
                done.forEach((x, j) => nodes.push({ id: pf + x.id, ci: i, cx, cz, sg, kind: "done", col: x.fork ? cFork : cSwarm, label: x.type || "agent", d: x, i: j }));
                (s.pending ?? []).slice(-3).forEach((x, j) => nodes.push({ id: pf + "pend" + j, ci: i, cx, cz, sg, kind: "pend", col: cSwarm, label: x.type, d: x, i: j }));
            }
            return { i, pf, cwd: k, name: sess.length ? base(k) : "chưa có dự án", sess, nSess: sess.length, s, subsAll, swarm, advisorRuns,
                     advisorRunning, running, nAgents: (s?.busy ? 1 : 0) + running + (advisorRunning ? 1 : 0),
                     live: !!s && (s.busy || subsAll.some(x => x.status === "running")),
                     phase: s?.phase ?? "idle", leadFam, cx, cz, sg, nodes,
                     roofCol: roofPal[hn % roofPal.length], wallCol: wallPal[(hn >>> 4) % wallPal.length], gable: hn % 3 !== 0 };
        });
    }
    readonly property int houseCount: houses.length
    // nhà của phiên mới nhất (active)
    readonly property int hotIdx: {
        const a = (st.sessions ?? {})[st.active ?? ""];
        if (a) { const j = houses.findIndex(c => c.cwd === (a.cwd || "")); if (j >= 0) return j; }
        let bi = 0, ba = -1;
        for (const c of houses) { const at = c.s?.at ?? 0; if (at > ba) { ba = at; bi = c.i; } }
        return bi;
    }
    property var selCwd: null                    // cwd nhà đang chọn (null = toàn cảnh)
    readonly property int sel: selCwd === null ? -1 : houses.findIndex(c => c.cwd === selCwd)   // chỉ số lô (-1 = toàn cảnh)
    readonly property var hc: houses[sel >= 0 && sel < houseCount ? sel : hotIdx] ?? houses[0]   // nhà hiện ở HUD
    readonly property bool live: houses.some(c => c.live)
    // vai nào đang làm việc ở mỗi nhà: lead đang bận, hoặc có subagent cùng model đang chạy
    readonly property var houseAct: houses.map(c => {
        const r = { opus: false, sonnet: false, haiku: false, jev: c.i === hotIdx && !!jev && now - jev.at < 20 };
        if (c.s?.busy) r[c.leadFam] = true;
        for (const x of c.swarm) if (x.status === "running") { const f = fam(x.model); if (f) r[f] = true; }
        return r;
    })
    readonly property var nodes: houses.reduce((o, c) => o.concat(c.nodes), [])
    readonly property var nodeMap: { const m = {}; for (const n of nodes) m[n.id] = n; return m; }
    // các gói tin: 2 đi + 2 về cho mỗi mascot đang chạy, advisor chỉ gửi về
    readonly property var packets: {
        const out = [];
        for (const n of nodes) {
            if (n.kind === "sub") for (let k = 0; k < 2; k++) { out.push({ id: n.id, ci: n.ci, k, dir: 1 }); out.push({ id: n.id, ci: n.ci, k, dir: -1 }); }
            else if (n.kind === "advisor" && n.d.status === "running") for (let k = 0; k < 2; k++) out.push({ id: n.id, ci: n.ci, k, dir: -1 });
        }
        return out;
    }
    // lô chưa có nhà: công viên nhỏ
    readonly property var parkLots: lots.map((_, i) => i).filter(i => i >= houseCount)

    // ListModel giữ delegate mascot ổn định (không tạo lại khi state đổi)
    ListModel { id: robotModel }
    onNodesChanged: syncRobots()
    Component.onCompleted: { syncRobots(); snapOverview(); syncMyAddr(); }
    function syncRobots() {
        const ids = new Set(nodes.map(n => n.id));
        for (let i = robotModel.count - 1; i >= 0; i--) if (!ids.has(robotModel.get(i).rid)) robotModel.remove(i);
        const have = new Set();
        for (let i = 0; i < robotModel.count; i++) have.add(robotModel.get(i).rid);
        for (const n of nodes) if (!have.has(n.id)) robotModel.append({ rid: n.id });
    }

    // House item theo chỉ số (đọc roofK/open của nhà)
    property var houseNodes: ({})
    function regHouse(i, n) { const m = Object.assign({}, houseNodes); m[i] = n; houseNodes = m; }
    function unregHouse(i, n) { if (houseNodes[i] !== n) return; const m = Object.assign({}, houseNodes); delete m[i]; houseNodes = m; }
    function houseOpen(i) { return houseNodes[i]?.open ?? false; }
    property var seatOf: ({})        // id -> chỗ ngồi (trong nhà của nó)
    property var actors: ({})        // id -> {x, z, h, walk, moving} (toạ độ cục bộ của nhà)
    property real sessionSince: 0

    // ---- Jev tuần tra: đứng quan sát lần lượt từng agent đang làm việc (5 s mỗi chỗ), mỗi nhà một Jev
    property real patrolT: 0
    property var patrolLabels: []
    property var watchLists: []
    function computeWatch(c) {
        const out = [], act = houseAct[c.i];
        for (const f of ["opus", "sonnet", "haiku"]) if (act[f]) {
            const st = stations[f];
            if (f === "haiku") out.push({ label: "Haiku", x: st.x, z: st.z - 1.0, h: st.h });
            else out.push({ label: cap(f), x: st.x, z: -2.1, h: Math.PI });
        }
        for (const n of c.nodes) if (n.kind === "sub" && n.d.status === "running") {
            const si = seatOf[n.id];
            if (si === undefined) continue;
            const sd = seats[si];
            out.push({ label: n.label || "agent", x: sd.x - Math.sin(sd.h) * 1.0, z: sd.z - Math.cos(sd.h) * 1.0, h: sd.h });
        }
        return out;
    }
    // ---- mascot rảnh: ngủ tại bàn, xen kẽ đi dạo quanh văn phòng (chu kỳ 12 s)
    readonly property var wander: ({
        opus:   [[1.85, -1.6], [-2.05, -1.2]],
        sonnet: [[-5.3, -1.0], [-2.05, -1.8]],
        haiku:  [[-6.0, 3.2], [4.0, 3.3]]
    })
    readonly property var wanderOff: ({ opus: 0, sonnet: 5, haiku: 9 })
    function target(nd) {
        const act = houseAct[nd.ci] ?? {}, wl = watchLists[nd.ci] ?? [];
        switch (nd.kind) {
        case "role": {
            if (nd.fam === "jev") {
                if (wl.length > 0) {
                    const w = wl[Math.floor(patrolT / 5) % wl.length];
                    return { x: w.x, z: w.z, h: w.h };
                }
                return stations.jev;
            }
            if (!act[nd.fam]) {
                const slot = Math.floor((t + wanderOff[nd.fam] + nd.ci * 3.7) / 12);
                if (slot % 2 === 1) {
                    const w = wander[nd.fam][(slot >> 1) % wander[nd.fam].length];
                    return { x: w[0], z: w[1], h: Math.atan2(-w[0], 3 - w[1]) };
                }
            }
            return stations[nd.fam];
        }
        case "advisor": return { x: -5.45, z: -0.75, h: Math.atan2(board[0] + 5.45, board[1] + 0.2 + 0.75) };
        case "sub": {
            const si = seatOf[nd.id];
            if (si !== undefined) return seats[si];
            return { x: -2.4 + (nd.d.start % 3) * 0.7, z: 3.9, h: Math.PI };       // hết chỗ: đứng chờ ở lối trước
        }
        case "done": {
            const p = lounge[nd.i % lounge.length];
            return { x: p[0], z: p[1], h: Math.atan2(5.9 - p[0], -2.6 - p[1]) };
        }
        default: return { x: -4.8 + nd.i * 0.75, z: 4.1, h: Math.PI };        // pend: vừa vào cửa
        }
    }
    function waypoint(a, tg) {
        // ngoài nhà (vỉa hè / sân trước): đi thẳng theo lối vào tới khung cửa (x = doorX) rồi mới vào trong — không xuyên tường trước
        if (a.z > rz - 0.4 && tg.z < rz - 0.4) {
            if (Math.abs(a.x - doorX) > 0.08) return { x: doorX, z: a.z };
            return { x: doorX, z: rz - 0.75 };
        }
        // hàng bàn cuối phòng: ra/vào qua khe hở giữa các bàn, không xuyên bàn
        if ((a.z < -3.75) !== (tg.z < -3.75)) {
            const g = gaps.reduce((b, c) => Math.abs((a.z < -3.75 ? a.x : tg.x) - c) < Math.abs((a.z < -3.75 ? a.x : tg.x) - b) ? c : b);
            if (Math.abs(a.x - g) > 0.08) return { x: g, z: a.z };
            return { x: g, z: tg.z };
        }
        if ((a.z - podZ) * (tg.z - podZ) >= 0 || Math.abs(a.z - tg.z) < 0.3) return tg;
        const cx = corridors.reduce((b, c) => Math.abs(a.x - c) + Math.abs(tg.x - c) < Math.abs(a.x - b) + Math.abs(tg.x - b) ? c : b);
        if (Math.abs(a.x - cx) > 0.08) return { x: cx, z: a.z };
        return { x: cx, z: tg.z };
    }
    function lerpAngle(a, b, k) {
        const d = ((b - a) % (2 * Math.PI) + 3 * Math.PI) % (2 * Math.PI) - Math.PI;
        return a + d * k;
    }

    // ------------------------------------------------------------------ camera
    property real yaw: 0.7
    property real pitch: 0.62
    property real dist: 22
    property real lookX: 0          // điểm nhìn (m) — animate khi bay
    property real lookZ: 0
    property bool spin: false
    property real t: 0
    readonly property vector3d look: Qt.vector3d(lookX * 100, 60, lookZ * 100)
    readonly property var cam: [look.x / 100 + dist * Math.sin(yaw) * Math.cos(pitch), look.y / 100 + dist * Math.sin(pitch), look.z / 100 + dist * Math.cos(yaw) * Math.cos(pitch)]
    property string hovered: ""

    // toàn cảnh: khung bao các lô đang có nhà (+ phố chính) — tính trực tiếp từ n (handler onHouseCountChanged có thể chạy trước binding khác)
    function overviewFor(n) {
        let x0 = 1e9, x1 = -1e9, z0 = -3, z1 = 3;
        for (let i = 0; i < Math.max(1, Math.min(n, lots.length)); i++) {
            const L = lots[i], cz = L[1] * lotOZ;
            x0 = Math.min(x0, L[0] - 8); x1 = Math.max(x1, L[0] + 8);
            z0 = Math.min(z0, cz - 6.5); z1 = Math.max(z1, cz + 6.5);
        }
        return { x: (x0 + x1) / 2, z: (z0 + z1) / 2, d: Math.max(26, Math.max(x1 - x0, (z1 - z0) * 1.25) * 1.0 + 10) };
    }
    readonly property real overviewDist: overviewFor(houseCount).d
    ParallelAnimation {
        id: fly
        onRunningChanged: { app.refreshFx(); app.updatePeek(); }
        NumberAnimation { id: flyX; target: app; property: "lookX"; duration: 850; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyZ; target: app; property: "lookZ"; duration: 850; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyD; target: app; property: "dist"; duration: 850; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyY; target: app; property: "yaw"; duration: 850; easing.type: Easing.InOutCubic }
    }
    function flyTo(x, z, d, yw) {
        fly.stop();
        flyX.to = x; flyZ.to = z; flyD.to = d; flyY.to = yw ?? yaw;
        fly.start();
    }
    // vào nhà i: camera nhìn từ phía phố (mặt có cửa), xoay theo đường ngắn nhất
    function flyHouse(i) {
        if (i < 0 || i >= houseCount) return;
        const h = houses[i];
        selCwd = h.cwd;
        const want = h.sg > 0 ? 0.55 : 0.55 + Math.PI;
        const d = ((want - yaw) % (2 * Math.PI) + 3 * Math.PI) % (2 * Math.PI) - Math.PI;
        flyTo(h.cx, h.cz, 16, yaw + d);
    }
    function flyOverview() { selCwd = null; const o = overviewFor(houses.length); flyTo(o.x, o.z, o.d); }
    function snapOverview() { fly.stop(); selCwd = null; const o = overviewFor(houses.length); lookX = o.x; lookZ = o.z; dist = o.d; }
    // số nhà đổi: khung toàn cảnh đổi, bay lại theo mục tiêu hiện tại
    onHouseCountChanged: { if (sel >= 0) flyHouse(sel); else flyOverview(); refreshFx(); }
    // nhà đang chọn biến mất (dự án rơi khỏi top 8): về toàn cảnh
    onSelChanged: {
        if (selCwd !== null && sel < 0) { selCwd = null; flyOverview(); }
        refreshFx();
        hovered = "";
        updatePeek();
    }
    // vị trí nhà đang chọn đổi (thứ tự lô đổi do thêm/bớt dự án): bay lại
    readonly property real selX: sel >= 0 ? houses[sel].cx : 0
    readonly property real selZ: sel >= 0 ? houses[sel].cz : 0
    onSelXChanged: if (sel >= 0) flyHouse(sel)
    onSelZChanged: if (sel >= 0) flyHouse(sel)
    // AO / bóng đổ chỉ đổi khi không đang bay (tránh biên dịch lại shader giữa chuyến bay)
    property bool aoOn: false
    property bool shadowOn: false
    function refreshFx() { if (fly.running) return; aoOn = sel >= 0 && dist < 30; shadowOn = dist < 30; }
    onDistChanged: {
        refreshFx();
        if (dist < peekIn) zoomNear = true;
        else if (dist > peekOut) zoomNear = false;
    }

    // Toàn cảnh + cuộn lại gần: nhấc mái một nhà phía trước camera, gần điểm giữa camera–tâm nhìn nhất (mặt xz).
    // Hysteresis zoom: dưới peekIn thì nhấc, trên peekOut mới hạ lại (không nhấp nháy quanh ngưỡng).
    // Không áp dụng khi đang bay (giữ hành vi cũ của 0/1..8/thu nhỏ) hoặc khi đã vào nhà (sel >= 0 dùng logic focus).
    readonly property real peekIn: 20
    readonly property real peekOut: 24
    property bool zoomNear: false
    // nhà đang focus mà zoom ra xa (cùng hysteresis): mái trở lại; khi đang bay luôn false (vào nhà không nhấp nháy mái)
    readonly property bool farOut: !zoomNear && !fly.running
    // gán mệnh lệnh (không binding) để có hysteresis đổi nhà: chỉ đổi khi nhà mới gần hơn nhà hiện tại >= 2 m
    property int peekIdx: -1
    function updatePeek() {
        let next = -1;
        if (sel < 0 && !fly.running && zoomNear) {
            const cx = cam[0], cz = cam[2], fx = lookX - cx, fz = lookZ - cz;
            const px = cx + 0.5 * fx, pz = cz + 0.5 * fz;
            let bd = 1e9, cur = 1e9;
            for (let i = 0; i < houseCount; i++) {
                const h = houses[i];
                if (!h || (h.nSess ?? 0) === 0) continue;                       // bỏ nhà giữ chỗ (như click)
                if ((h.cx - cx) * fx + (h.cz - cz) * fz <= 0) continue;          // sau lưng camera
                const d = Math.hypot(h.cx - px, h.cz - pz);
                if (i === peekIdx) cur = d;
                if (d < bd) { bd = d; next = i; }
            }
            if (next >= 0 && cur < 1e9 && bd > cur - 2) next = peekIdx;
        }
        if (next !== peekIdx) peekIdx = next;
    }
    onCamChanged: updatePeek()
    onZoomNearChanged: updatePeek()
    onHousesChanged: updatePeek()

    // 0 sau, 1 trái, 2 phải, 3 trước (có cửa): chỉ dựng cao tường phía xa camera (camera đổi về toạ độ cục bộ của nhà)
    function wallShown(i, ci) {
        const h = houses[ci];
        if (!h) return true;
        const lx = h.sg * (cam[0] - h.cx), lz = h.sg * (cam[2] - h.cz);
        switch (i) {
        case 0: return lz > -rz;
        case 1: return lx > -rx;
        case 2: return lx < rx;
        default: return lz < rz;
        }
    }

    function step(dt) {
        t += dt;
        if (spin && !drag.pressed) yaw += dt * 0.06;

        const so = {};
        for (const c of houses) {
            const used = new Set([0]);   // chỗ 0 dành cho Haiku
            const run = c.nodes.filter(n => n.kind === "sub");
            for (const n of run) if (seatOf[n.id] !== undefined && !used.has(seatOf[n.id])) { so[n.id] = seatOf[n.id]; used.add(so[n.id]); }
            for (const n of run) if (so[n.id] === undefined) {
                const free = seats.findIndex((_, i) => !used.has(i));
                if (free >= 0) { so[n.id] = free; used.add(free); }
            }
        }
        seatOf = so;
        const wls = houses.map(c => computeWatch(c));
        watchLists = wls;
        if (wls.some(w => w.length > 0)) patrolT += dt; else patrolT = 0;
        patrolLabels = wls.map(w => w.length > 0 ? w[Math.floor(patrolT / 5) % w.length].label : "");

        const A = {}, fresh = t - sessionSince < 0.4, turn = 1 - Math.pow(0.0005, dt);
        for (const nd of nodes) {
            const tg = target(nd);
            let a = actors[nd.id];
            if (!a) a = (fresh || nd.kind === "role" || nd.kind === "advisor")
                ? { x: tg.x, z: tg.z, h: tg.h, walk: 0 }
                : { x: entry[0], z: entry[1], h: Math.PI, walk: 0 };     // mascot mới: từ vỉa hè, mặt hướng vào cửa
            a = { x: a.x, z: a.z, h: a.h, walk: a.walk, moving: false };
            const wp = waypoint(a, tg);
            const dx = wp.x - a.x, dz = wp.z - a.z, dd = Math.hypot(dx, dz);
            if (dd > 0.03) {
                const sp = Math.min(dd, 1.9 * dt);
                a.x += dx / dd * sp; a.z += dz / dd * sp;
                a.h = lerpAngle(a.h, Math.atan2(dx, dz), turn);
                a.walk += dt * 9;
                a.moving = true;
            } else {
                a.h = lerpAngle(a.h, tg.h, turn * 0.5);
            }
            A[nd.id] = a;
        }
        actors = A;
    }

    // 24 fps khi có hoạt động / đang xoay / mascot đang đi, 12 fps khi thành phố yên tĩnh
    readonly property bool busyScene: live || spin || drag.pressed || fly.running
        || (sel >= 0 ? nodes.filter(n => n.ci === sel).map(n => actors[n.id]) : Object.values(actors)).some(a => a?.moving ?? false)
    property real lastTick: Date.now()
    Timer {
        interval: app.busyScene ? 42 : 83
        running: win.visible
        repeat: true
        onTriggered: {
            const n = Date.now();
            app.step(Math.min(0.1, (n - app.lastTick) / 1000));
            app.lastTick = n;
        }
    }

    // ------------------------------------------------------------------ thành phần 3D
    // Hộp / cầu / trụ: tâm (px, py, pz) và kích thước (sx, sy, sz) tính bằng mét
    component Box: Model {
        property real px
        property real py
        property real pz
        property real sx: 1
        property real sy: 1
        property real sz: 1
        property color col: "#808080"
        property real rough: 0.75
        property real metal: 0
        property color glow: "black"
        property real glowK: 0
        property string shape: "#Cube"
        source: shape
        position: Qt.vector3d(px * 100, py * 100, pz * 100)
        scale: Qt.vector3d(sx, sy, sz)
        materials: PrincipledMaterial {
            baseColor: col
            roughness: rough
            metalness: metal
            emissiveFactor: Qt.vector3d(glow.r * glowK, glow.g * glowK, glow.b * glowK)
        }
    }
    // Mặt phẳng hiển thị một Item 2D (màn hình, bảng trắng, cửa sổ, biển tên). Pháp tuyến +z.
    component Panel3D: Model {
        property real px
        property real py
        property real pz
        property real w: 1
        property real h: 1
        property Item src
        property real bright: 1
        source: "#Rectangle"
        position: Qt.vector3d(px * 100, py * 100, pz * 100)
        scale: Qt.vector3d(w, h, 1)
        receivesShadows: false
        castsShadows: false
        materials: PrincipledMaterial {
            lighting: PrincipledMaterial.NoLighting
            baseColorMap: Texture { sourceItem: src }
            baseColor: Qt.rgba(bright, bright, bright, 1)
            alphaMode: PrincipledMaterial.Blend
        }
    }
    // cây tròn (toạ độ thế giới hoặc cục bộ của Node cha)
    component Tree: Node {
        id: tr
        property real px
        property real pz
        property real k: 1
        Box { px: tr.px; py: 0.3 * tr.k; pz: tr.pz; sx: 0.16 * tr.k; sy: 0.6 * tr.k; sz: 0.16 * tr.k; shape: "#Cylinder"; col: "#6b4a34"; rough: 0.9 }
        Box { px: tr.px; py: 1.0 * tr.k; pz: tr.pz; sx: 1.0 * tr.k; sy: 0.95 * tr.k; sz: 1.0 * tr.k; shape: "#Sphere"; col: "#4f9a56"; rough: 0.8 }
        Box { px: tr.px; py: 1.55 * tr.k; pz: tr.pz; sx: 0.66 * tr.k; sy: 0.62 * tr.k; sz: 0.66 * tr.k; shape: "#Sphere"; col: "#62b268"; rough: 0.8 }
    }


    // Mascot Claude (kiểu Clawd): thân khối vuông cam, hai mắt vuông đen, tay/chân ngắn dạng khối. Màu vai/model nằm ở
    // đèn ăng-ten (trạng thái), huy hiệu ngực và viền chân (accent). Chỉ hiện trong nhà đang mở (nhà khác có mái che).
    component Robot: Node {
        id: rb
        required property string rid
        readonly property var nd: app.nodeMap[rid] ?? null
        // chỉ cập nhật khi nhà của mascot đang mở (mái nhấc) — nhà đóng: đứng yên, ẩn
        readonly property bool on: !!nd && app.houseOpen(nd.ci)
        readonly property var a: on ? (app.actors[rid] ?? null) : null
        readonly property var cc: nd ? (app.houses[nd.ci] ?? null) : null
        readonly property var act: nd ? (app.houseAct[nd.ci] ?? null) : null
        readonly property string robotId: rid
        readonly property real sg: nd?.sg ?? 1
        readonly property real k: (nd?.sc ?? 1) * 0.92
        readonly property real seed: (rid.charCodeAt(rid.length - 1) || 3) * 0.37 + (nd?.ci ?? 0) * 1.3
        readonly property real tt: on ? app.t : 0
        readonly property string kind: nd?.kind ?? ""
        readonly property bool moving: a?.moving ?? false
        readonly property real walkP: a?.walk ?? 0
        readonly property real swing: moving ? Math.sin(walkP) : 0
        readonly property bool run: kind === "sub"
        readonly property bool done: kind === "done"
        readonly property bool isRole: kind === "role"
        readonly property bool roleActive: isRole && !!(act && act[nd.fam])
        readonly property bool directing: isRole && nd.lead && (cc?.running ?? 0) > 0
        readonly property bool isJev: isRole && nd.fam === "jev"
        readonly property bool inspecting: isJev && !moving && (app.watchLists[nd?.ci ?? 0] ?? []).length > 0
        readonly property bool sleeping: isRole && !isJev && !roleActive && !moving
        readonly property bool typing: !moving && (run || (roleActive && !directing && !inspecting))
        readonly property bool writing: kind === "advisor" && nd?.d?.status === "running"
        readonly property real armL: typing ? 1.2 + Math.sin(tt * 17 + seed) * 0.13 : inspecting ? 0.5 : directing ? 0.15 : writing ? 0.1 : done ? 0.9 : swing * 0.6
        readonly property real armR: typing ? 1.2 + Math.sin(tt * 17 + seed + 2.1) * 0.13 : inspecting ? 1.9 + Math.sin(tt * 3) * 0.3 : directing ? 2.3 + Math.sin(tt * 2.2) * 0.25
                                   : writing ? 1.75 + Math.sin(tt * 6) * 0.2 : done ? 0.9 : -swing * 0.6
        readonly property real bob: typing ? Math.sin(tt * 9 + seed) * 0.006 : moving ? Math.abs(Math.sin(walkP)) * 0.035 : Math.sin(tt * 2 + seed) * 0.004
        readonly property color shell: done ? app.mixc(app.cClaude, app.cGrey, 0.55) : kind === "pend" ? app.mixc(app.cClaude, app.cWhite, 0.35) : app.cClaude
        readonly property color shellDk: Qt.darker(shell, 1.18)
        readonly property color accent: !nd ? app.cDone : done ? app.mixc(nd.col, app.cDone, 0.6) : nd.col
        readonly property color status: isRole ? (nd.lead && cc?.s?.repeatError && Math.sin(tt * 6) > 0 ? app.cErr : roleActive || directing ? app.cOk : app.cDone)
                                      : run || writing ? app.cOk : kind === "pend" ? app.cWait : app.cDone
        readonly property real pulse: status === app.cDone ? 0.12 : 0.42 + Math.sin(tt * 5 + seed) * 0.12
        readonly property bool blink: ((tt * 0.6 + seed) % 4) < 0.12
        readonly property real eyeH: blink || sleeping ? 0.02 : done ? 0.07 : 0.17

        visible: on && !!a
        position: Qt.vector3d(((nd?.cx ?? 0) + sg * (a?.x ?? 0)) * 100, 0, ((nd?.cz ?? 0) + sg * (a?.z ?? 0)) * 100)
        eulerRotation.y: ((a?.h ?? 0) + (sg < 0 ? Math.PI : 0)) * 180 / Math.PI
        scale: Qt.vector3d(k, k, k)

        Node {
            y: rb.bob * 100
            eulerRotation.x: rb.moving ? 4 : 0          // hơi chúi người khi đi

            // bốn chân ngắn (cặp chéo đung đưa ngược pha khi đi)
            Repeater3D {
                model: [-0.27, -0.09, 0.09, 0.27]
                Node {
                    id: legN
                    required property var modelData
                    required property int index
                    position: Qt.vector3d(modelData * 100, 24, 0)
                    eulerRotation.x: rb.swing * 38 * (index % 2 ? -1 : 1)
                    Box { py: -0.1; sx: 0.11; sy: 0.24; sz: 0.13; col: rb.shellDk; rough: 0.6 }
                }
            }
            // viền accent ở chân thân
            Box { py: 0.25; sx: 0.78; sy: 0.04; sz: 0.54; col: "black"; glow: rb.accent; glowK: rb.done ? 0.12 : 0.45; castsShadows: false }

            // thân: hai khối chồng lệch nhau cho góc bo
            Box { py: 0.52; sx: 0.76; sy: 0.5; sz: 0.5; col: rb.shell; rough: 0.55; pickable: true }
            Box { py: 0.52; sx: 0.7; sy: 0.56; sz: 0.44; col: rb.shell; rough: 0.55; pickable: true }
            Box { py: 0.52; sx: 0.82; sy: 0.42; sz: 0.4; col: rb.shell; rough: 0.55; pickable: true }

            // hai mắt vuông đen
            Box { px: -0.16; py: 0.6; pz: 0.255; sx: 0.1; sy: rb.eyeH; sz: 0.03; col: "#0c0c10"; rough: 0.3; castsShadows: false }
            Box { px: 0.16; py: 0.6; pz: 0.255; sx: 0.1; sy: rb.eyeH; sz: 0.03; col: "#0c0c10"; rough: 0.3; castsShadows: false }
            // huy hiệu accent ở ngực
            Box { py: 0.37; pz: 0.255; sx: 0.18; sy: 0.07; sz: 0.025; col: "black"; glow: rb.accent; glowK: rb.done ? 0.12 : 0.5; castsShadows: false }

            // tay khối ngắn (xoay quanh vai)
            Repeater3D {
                model: [-1, 1]
                Node {
                    required property var modelData
                    position: Qt.vector3d(modelData * 45, 68, 0)
                    eulerRotation.x: -(modelData < 0 ? rb.armL : rb.armR) * 180 / Math.PI
                    eulerRotation.z: modelData * 6
                    Box { py: -0.11; sx: 0.12; sy: 0.3; sz: 0.15; col: rb.shellDk; rough: 0.6 }
                    // cầm cốc khi nghỉ
                    Box { visible: rb.done && modelData > 0; py: -0.3; pz: 0.05; sx: 0.1; sy: 0.12; sz: 0.1; shape: "#Cylinder"; col: "#f6f6f8"; rough: 0.2 }
                }
            }

            // ngủ: chữ z nổi lên trên đầu
            Panel3D {
                visible: rb.sleeping
                py: 1.3 + Math.sin(rb.tt * 1.5) * 0.05; w: 0.5; h: 0.25
                src: Item {
                    width: 120; height: 60
                    Text { anchors.centerIn: parent; text: "z Z z"; color: "#aab4ff"; font { family: "Inter"; pixelSize: 40; bold: true } }
                }
            }
            // ăng-ten nhỏ: đèn trạng thái
            Box { py: 0.84; sx: 0.02; sy: 0.1; sz: 0.02; col: "#9aa0aa"; metal: 0.6 }
            Box { py: 0.92; sx: 0.07; sy: 0.07; sz: 0.07; col: "black"; glow: rb.status; glowK: rb.pulse; castsShadows: false }
        }
    }


    // nội dung màn hình máy tính: dòng code chạy khi có robot ngồi
    component CodeScreen: Rectangle {
        id: cs
        property var node: null
        property real sd: 0
        readonly property int tick: node ? Math.floor(app.t * 3) : 0
        width: 256; height: 150
        color: node ? "#0f1a2c" : "#05070b"
        Column {
            x: 14; y: 12
            spacing: 9
            visible: !!cs.node
            Repeater {
                model: 7
                Rectangle {
                    required property int index
                    readonly property int line: cs.tick + index
                    x: (line * 7 % 3) * 14
                    height: 9; radius: 2
                    width: 40 + app.rnd(line + cs.sd) * 150
                    color: index === 6 ? (cs.tick % 2 ? app.cOk : "transparent")
                                       : cs.node ? (index % 2 ? Qt.lighter(cs.node.col, 1.3) : cs.node.col) : "black"
                }
            }
        }
    }


    // một ngôi nhà = một dự án, đặt trên lô của nó (xoay 180° nếu ở phía nam để cửa hướng ra phố).
    // Ngoài: tường màu theo hash, cửa chính + lối vào, cửa sổ (sáng khi có agent chạy), mái dốc hoặc mái bằng, ống khói, biển tên.
    // Trong (chỉ khi nhà đang mở): văn phòng thu gọn như cũ, đèn trần riêng.
    component House: Node {
        id: house
        required property int ci
        readonly property var c: app.houses[ci] ?? null
        readonly property var act: app.houseAct[ci] ?? ({ opus: false, sonnet: false, haiku: false, jev: false })
        readonly property real ox: c?.cx ?? 0
        readonly property real oz: c?.cz ?? 0
        readonly property real rotDeg: (c?.sg ?? 1) > 0 ? 0 : 180
        readonly property bool live: c?.live ?? false
        readonly property string pfx: c?.pf ?? ""
        readonly property int houseId: ci
        readonly property bool focused: app.sel === ci
        readonly property color wallCol: c?.wallCol ?? "#d0c8b8"
        readonly property color roofCol: c?.roofCol ?? "#a0503a"
        readonly property bool gable: c?.gable ?? true
        // 0 = mái che kín, 1 = mái đã nhấc (đang nhìn vào trong)
        property real roofK: (focused && !app.farOut) || app.peekIdx === ci ? 1 : 0
        Behavior on roofK { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
        readonly property bool open: roofK > 0.001
        // tường cao hay hạ thấp (cutaway) — nhà đóng thì luôn cao
        readonly property bool t0: !open || app.wallShown(0, ci)
        readonly property bool t1: !open || app.wallShown(1, ci)
        readonly property bool t2: !open || app.wallShown(2, ci)
        readonly property bool t3: !open || app.wallShown(3, ci)
        readonly property real chimTop: gable ? 5.7 : 4.1
        visible: !!c
        position: Qt.vector3d(ox * 100, 0, oz * 100)
        Component.onCompleted: app.regHouse(ci, house)
        Component.onDestruction: app.unregHouse(ci, house)
        eulerRotation.y: rotDeg

        // ---------------------------------------------- lô đất, sàn, lối vào
        Box { py: -0.09; pz: 0.25; sx: 16; sy: 0.1; sz: 12.5; col: "#3f6c47"; rough: 0.95; pickable: true }
        Box { py: -0.05; sx: 14; sy: 0.1; sz: 10; col: "#4a4542"; rough: 0.85; pickable: true }
        Box { px: app.doorX; py: -0.04; pz: app.rz + 0.75; sx: 1.3; sy: 0.06; sz: 1.5; col: "#9a9284"; rough: 0.9; pickable: true }
        Box { px: app.doorX; py: -0.005; pz: app.rz + 0.45; sx: 0.95; sy: 0.012; sz: 0.55; col: "#5a463c" }
        // bụi cây dưới cửa sổ trước
        Box { px: -3.2; py: 0.28; pz: app.rz + 0.5; sx: 1.5; sy: 0.6; sz: 0.6; shape: "#Sphere"; col: "#4f8f52"; rough: 0.85 }
        Box { px: 4.4; py: 0.28; pz: app.rz + 0.5; sx: 1.5; sy: 0.6; sz: 0.6; shape: "#Sphere"; col: "#4f8f52"; rough: 0.85 }

        // ---------------------------------------------- tường (xa camera: cao; gần camera khi đang mở: gờ thấp). Tường trước chia 3 đoạn quanh cửa.
        Repeater3D {
            model: [
                { s: 0, x: 0, z: -5.05, w: 14.2, d: 0.1 }, { s: 1, x: -7.05, z: 0, w: 0.1, d: 10.2 },
                { s: 2, x: 7.05, z: 0, w: 0.1, d: 10.2 },
                { s: 3, x: -6.85, z: 5.05, w: 0.5, d: 0.1 }, { s: 3, x: 0.85, z: 5.05, w: 12.5, d: 0.1 },
                { s: 3, x: -6.0, z: 5.05, w: 1.2, d: 0.1, top: true }
            ]
            Node {
                id: wallN
                required property var modelData
                readonly property bool tall: [house.t0, house.t1, house.t2, house.t3][modelData.s]
                readonly property bool top: modelData.top ?? false
                Box {
                    visible: !wallN.top || wallN.tall
                    px: wallN.modelData.x; pz: wallN.modelData.z; sx: wallN.modelData.w; sz: wallN.modelData.d
                    py: wallN.top ? 2.65 : wallN.tall ? 1.5 : 0.09; sy: wallN.top ? 0.7 : wallN.tall ? 3 : 0.18
                    col: house.wallCol; rough: 0.9; pickable: true
                }
                Box { visible: wallN.tall && !wallN.top; px: wallN.modelData.x; pz: wallN.modelData.z; py: 0.1; sx: wallN.modelData.w + 0.03; sz: wallN.modelData.d + 0.03; sy: 0.2; col: "#5a5550" }
            }
        }
        // cửa sổ ngoài (kính sáng vàng ấm khi dự án có agent đang chạy)
        Repeater3D {
            model: [
                { s: 3, x: -3.2, z: 5.0, w: 1.9, h: 1.25, y: 1.75 }, { s: 3, x: 0.6, z: 5.0, w: 1.9, h: 1.25, y: 1.75 }, { s: 3, x: 4.4, z: 5.0, w: 1.9, h: 1.25, y: 1.75 },
                { s: 0, x: -3.8, z: -5.0, w: 2.6, h: 1.5, y: 1.85 }, { s: 0, x: 3.8, z: -5.0, w: 2.6, h: 1.5, y: 1.85 },
                { s: 1, x: -7.0, z: 1.8, w: 1.6, h: 1.2, y: 1.8 }, { s: 2, x: 7.0, z: 1.8, w: 1.6, h: 1.2, y: 1.8 }
            ]
            Node {
                id: winX
                required property var modelData
                readonly property bool sideW: modelData.s === 1 || modelData.s === 2
                // hướng ra ngoài
                readonly property real nx: modelData.s === 1 ? -1 : modelData.s === 2 ? 1 : 0
                readonly property real nz: modelData.s === 3 ? 1 : modelData.s === 0 ? -1 : 0
                visible: [house.t0, house.t1, house.t2, house.t3][modelData.s]
                Box {
                    px: winX.modelData.x + winX.nx * 0.115; py: winX.modelData.y; pz: winX.modelData.z + winX.nz * 0.115
                    sx: winX.sideW ? 0.05 : winX.modelData.w + 0.18; sy: winX.modelData.h + 0.18; sz: winX.sideW ? winX.modelData.w + 0.18 : 0.05
                    col: "#4a3c30"; rough: 0.6
                }
                Box {
                    px: winX.modelData.x + winX.nx * 0.135; py: winX.modelData.y; pz: winX.modelData.z + winX.nz * 0.135
                    sx: winX.sideW ? 0.04 : winX.modelData.w; sy: winX.modelData.h; sz: winX.sideW ? winX.modelData.w : 0.04
                    col: house.live ? "#1a1208" : "#3a4a60"; rough: 0.15; metal: 0.1
                    glow: house.live ? "#ffa53a" : "#000000"; glowK: house.live ? 0.85 : 0; castsShadows: false
                }
                // song cửa
                Box {
                    px: winX.modelData.x + winX.nx * 0.16; py: winX.modelData.y; pz: winX.modelData.z + winX.nz * 0.16
                    sx: winX.sideW ? 0.03 : 0.06; sy: winX.modelData.h; sz: winX.sideW ? 0.06 : 0.03; col: "#efece6"
                }
                Box {
                    px: winX.modelData.x + winX.nx * 0.16; py: winX.modelData.y; pz: winX.modelData.z + winX.nz * 0.16
                    sx: winX.sideW ? 0.03 : winX.modelData.w; sy: 0.06; sz: winX.sideW ? winX.modelData.w : 0.03; col: "#efece6"
                }
            }
        }
        // cửa chính: khung xuyên tường + cánh cửa mở vào trong + đèn cửa + số nhà
        Node {
            visible: house.t3
            Box { px: app.doorX - 0.66; py: 1.15; pz: 5.05; sx: 0.12; sy: 2.3; sz: 0.22; col: app.mWood }
            Box { px: app.doorX + 0.66; py: 1.15; pz: 5.05; sx: 0.12; sy: 2.3; sz: 0.22; col: app.mWood }
            Box { px: app.doorX; py: 2.32; pz: 5.05; sx: 1.44; sy: 0.12; sz: 0.22; col: app.mWood }
            Node {
                position: Qt.vector3d((app.doorX - 0.58) * 100, 0, 497)
                eulerRotation.y: 72
                Box { px: 0.55; py: 1.1; sx: 1.08; sy: 2.16; sz: 0.06; col: "#7a5236"; rough: 0.6 }
                Box { px: 0.95; py: 1.1; pz: -0.05; sx: 0.06; sy: 0.06; sz: 0.06; shape: "#Sphere"; col: "#d0b070"; metal: 1; rough: 0.25 }
            }
            Box { px: app.doorX + 0.95; py: 2.35; pz: 5.2; sx: 0.16; sy: 0.16; sz: 0.16; shape: "#Sphere"; col: "black"; glow: "#ffd9a0"; glowK: house.live ? 1.4 : 0.6; castsShadows: false }
            Panel3D {
                px: app.doorX + 1.1; py: 1.55; pz: 5.115; w: 0.5; h: 0.5; bright: 1.6
                src: Rectangle {
                    width: 100; height: 100; radius: 14
                    color: "#1a1d24"; border.width: 4; border.color: house.live ? app.cOk : app.cClaude
                    Text { anchors.centerIn: parent; text: (house.ci + 1) + ""; color: app.fg; font { family: app.mono; pixelSize: 60; bold: true } }
                }
            }
        }

        // ---------------------------------------------- mái (nhấc lên & ẩn khi đang mở) + ống khói
        Node {
            y: house.roofK * 700
            visible: house.roofK < 0.995
            Node {
                visible: house.gable
                Box { pz: -2.7; py: 4.08; sx: 14.9; sy: 0.16; sz: 5.95; eulerRotation.x: -23.96; col: house.roofCol; rough: 0.7; pickable: true }
                Box { pz: 2.7; py: 4.08; sx: 14.9; sy: 0.16; sz: 5.95; eulerRotation.x: 23.96; col: house.roofCol; rough: 0.7; pickable: true }
                Box { py: 5.3; sx: 15.0; sy: 0.16; sz: 0.34; col: Qt.darker(house.roofCol, 1.35); rough: 0.7 }
                // đầu hồi tam giác: khối vuông xoay 45° trong Node co giãn (nửa dưới chìm trong tường)
                Repeater3D {
                    model: [-7.04, 7.04]
                    Node {
                        required property var modelData
                        position: Qt.vector3d(modelData * 100, 288, 0)
                        scale: Qt.vector3d(0.08, 3.394, 7.142)
                        Box { eulerRotation.x: 45; col: house.wallCol; rough: 0.9 }
                    }
                }
            }
            Node {
                visible: !house.gable
                Box { py: 3.08; sx: 14.5; sy: 0.16; sz: 10.5; col: house.roofCol; rough: 0.8; pickable: true }
                Box { py: 3.32; pz: -5.2; sx: 14.5; sy: 0.34; sz: 0.12; col: Qt.darker(house.roofCol, 1.25) }
                Box { py: 3.32; pz: 5.2; sx: 14.5; sy: 0.34; sz: 0.12; col: Qt.darker(house.roofCol, 1.25) }
                Box { py: 3.32; px: -7.2; sx: 0.12; sy: 0.34; sz: 10.5; col: Qt.darker(house.roofCol, 1.25) }
                Box { py: 3.32; px: 7.2; sx: 0.12; sy: 0.34; sz: 10.5; col: Qt.darker(house.roofCol, 1.25) }
                Box { px: -3.0; py: 3.45; pz: -1.5; sx: 1.3; sy: 0.6; sz: 0.9; col: "#9aa0aa"; metal: 0.5; rough: 0.4 }
                Box { px: 1.5; py: 3.25; pz: 1.5; sx: 3.0; sy: 0.06; sz: 1.6; col: "#26324a"; metal: 0.4; rough: 0.25 }   // pin mặt trời
            }
            Box { px: 4.0; py: house.chimTop - (house.gable ? 0.85 : 0.6); pz: -2.2; sx: 0.62; sy: house.gable ? 1.7 : 1.2; sz: 0.62; col: "#8a4a3a"; rough: 0.9 }
            Box { px: 4.0; py: house.chimTop + 0.04; pz: -2.2; sx: 0.74; sy: 0.1; sz: 0.74; col: "#5a3028" }
            // khói khi có agent chạy
            Repeater3D {
                model: house.live ? 4 : 0
                Box {
                    required property int index
                    readonly property real u: (app.t * 0.4 + index / 4) % 1
                    readonly property real sz0: (0.32 + u * 0.75) * Math.min(1, (1 - u) * 5)
                    px: 4.0 + Math.sin(u * 4 + index) * 0.18 + u * 0.5; py: house.chimTop + 0.3 + u * 2.0; pz: -2.2
                    sx: sz0; sy: sz0; sz: sz0
                    shape: "#Sphere"; col: "#cdd1d8"; rough: 1; castsShadows: false
                }
            }
        }

        // ---------------------------------------------- biển tên dự án (luôn quay về phía camera)
        Panel3D {
            // ẩn khi đang ở trong nhà (tên đã có ở HUD, tránh che nhãn mascot); toàn cảnh xa: phóng to theo khoảng cách camera
            visible: !house.focused
            readonly property real k: Math.max(1, Math.min(1.8, app.dist / 40))
            py: (house.gable ? 6.6 : 4.8) + 0.6 * k; w: 7.2 * k; h: 1.18 * k; bright: 2.0
            eulerRotation.y: app.yaw * 180 / Math.PI - house.rotDeg
            src: Rectangle {
                width: 640; height: 105; radius: 14
                color: "#10131a"
                border.width: 3
                border.color: house.live ? app.cOk : app.cLead
                Text {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 8 }
                    text: (house.ci + 1) + " · " + (house.c?.name ?? "")
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    color: app.cClaude
                    font { family: app.mono; pixelSize: 44; bold: true }
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
                    text: !house.c ? "" : house.live ? `● đang chạy · ${house.c.nAgents} agent · ${app.cap(house.c.s?.model ?? "")}`
                                                      : `○ rảnh · ${house.c.nSess} phiên${house.c.s ? " · " + house.c.phase : ""}`
                    color: house.live ? app.cOk : app.muted
                    font { family: app.mono; pixelSize: 19 }
                }
            }
        }

        // ================================================= nội thất (chỉ dựng khi nhà đang mở)
        Node {
            visible: house.open

            // đèn trần riêng của nhà
            PointLight {
                position: Qt.vector3d(0, 290, -30)
                visible: house.focused
                color: "#ffe2c0"
                brightness: 3.0
                quadraticFade: 0.12
            }
            Box { px: -1.2; py: 0.005; pz: 1.4; sx: 9.6; sy: 0.01; sz: 3.0; col: "#323b52"; rough: 1 }
            Box { py: 0.005; pz: -3.6; sx: 4.4; sy: 0.01; sz: 2.8; col: "#56362f"; rough: 1 }
            Box { px: 4.95; py: 0.005; pz: -2.6; sx: 3.9; sy: 0.01; sz: 4.4; col: "#3f3750"; rough: 1 }

            // cửa sổ trời + biển tên + đồng hồ (mặt trong tường sau)
            Node {
                visible: house.t0
                Repeater3D {
                    model: [-3.8, 3.8]
                    Node {
                        id: winN
                        required property var modelData
                        Panel3D {
                            px: winN.modelData; py: 1.85; pz: -4.995; w: 2.6; h: 1.5
                            src: Rectangle {
                                id: sky
                                readonly property int hr: new Date(app.now * 1000).getHours()
                                readonly property bool night: hr >= 19 || hr < 5
                                readonly property bool day: hr >= 7 && hr < 17
                                width: 260; height: 150
                                gradient: Gradient {
                                    GradientStop { position: 0; color: sky.day ? "#78afe6" : sky.night ? "#0a1028" : "#5a4682" }
                                    GradientStop { position: 1; color: sky.day ? "#cde6f7" : sky.night ? "#1e2c50" : "#f0a06e" }
                                }
                                Repeater {
                                    model: sky.night ? 22 : 0
                                    Rectangle { required property int index; x: app.rnd(index) * 256; y: app.rnd(index + 50) * 110; width: 2; height: 2; color: "#d8e0ff" }
                                }
                                Rectangle { x: 0; y: 112; width: 260; height: 38; color: sky.night ? "#121830" : "#4a5670"; opacity: 0.8 }
                            }
                        }
                        Box { px: winN.modelData; py: 1.85; pz: -4.99; sx: 0.06; sy: 1.5; sz: 0.04; col: app.mDark }
                        Box { px: winN.modelData; py: 1.85; pz: -4.99; sx: 2.6; sy: 0.05; sz: 0.04; col: app.mDark }
                        Box { px: winN.modelData; py: 1.08; pz: -4.94; sx: 2.8; sy: 0.06; sz: 0.14; col: "#d8d8dc" }
                    }
                }
                Panel3D {
                    px: 1.5; py: 2.72; pz: -4.99; w: 2.4; h: 0.34; bright: 2.2
                    src: Item {
                        width: 480; height: 68
                        Text {
                            anchors.centerIn: parent
                            width: 470; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                            text: (house.c?.name ?? "claude").toUpperCase() + " · HQ"
                            color: app.cLead
                            font { family: app.mono; pixelSize: 40; bold: true; letterSpacing: 6 }
                        }
                    }
                }
                // đồng hồ treo tường
                Node {
                    position: Qt.vector3d(-150, 245, -497)
                    Box { sx: 0.46; sy: 0.04; sz: 0.46; shape: "#Cylinder"; eulerRotation.x: 90; col: "#ececf0"; rough: 0.4 }
                    Repeater3D {
                        model: {
                            if (!house.open) return [];
                            const d = new Date(app.now * 1000);
                            return [
                                { f: (d.getHours() % 12 + d.getMinutes() / 60) / 12, l: 0.12, c: "#1e1e24" },
                                { f: d.getMinutes() / 60, l: 0.18, c: "#1e1e24" },
                                { f: d.getSeconds() / 60, l: 0.19, c: app.cLead }
                            ];
                        }
                        Node {
                            id: handN
                            required property var modelData
                            z: 3
                            eulerRotation.z: -handN.modelData.f * 360
                            Box { py: handN.modelData.l / 2; sx: 0.018; sy: handN.modelData.l; sz: 0.01; col: handN.modelData.c }
                        }
                    }
                }
            }

            // ---------------------------------------------- cụm bàn
            Repeater3D {
                model: app.pods
                Node {
                    id: podN
                    required property var modelData
                    Box { px: podN.modelData; py: 0.76; pz: app.podZ; sx: 3.9; sy: 0.06; sz: 1.12; col: app.mWood; rough: 0.55 }
                    Box { px: podN.modelData - 1.85; py: 0.37; pz: app.podZ; sx: 0.08; sy: 0.74; sz: 1.0; col: app.mMetal; metal: 0.5; rough: 0.4 }
                    Box { px: podN.modelData + 1.85; py: 0.37; pz: app.podZ; sx: 0.08; sy: 0.74; sz: 1.0; col: app.mMetal; metal: 0.5; rough: 0.4 }
                    Box { px: podN.modelData; py: 0.98; pz: app.podZ; sx: 3.9; sy: 0.38; sz: 0.036; col: "#4f6a86"; rough: 0.9 }
                }
            }
            Repeater3D {
                model: app.seats
                Node {
                    id: seatN
                    required property var modelData
                    required property int index
                    // robot đang ngồi đúng chỗ này (để bật màn hình) — chỉ id thuộc nhà này (pfx)
                    readonly property var occ: {
                        if (!house.open) return null;
                        if (index === 0) return house.act.haiku ? app.nodeMap[house.pfx + "role-haiku"] ?? null : null;
                        for (const id in app.seatOf) if (id.startsWith(house.pfx) && app.seatOf[id] === index) {
                            const a = app.actors[id];
                            if (a && Math.hypot(a.x - modelData.x, a.z - modelData.z) < 0.6) return app.nodeMap[id] ?? null;
                        }
                        return null;
                    }
                    readonly property real zf: app.podZ + modelData.side * 0.22
                    Box { px: seatN.modelData.x; py: 1.09; pz: seatN.zf; sx: 0.66; sy: 0.4; sz: 0.05; col: app.mDark; rough: 0.4; metal: 0.3 }
                    Box { px: seatN.modelData.x; py: 0.84; pz: app.podZ + seatN.modelData.side * 0.12; sx: 0.06; sy: 0.12; sz: 0.06; col: app.mMetal }
                    Box { px: seatN.modelData.x; py: 0.8; pz: app.podZ + seatN.modelData.side * 0.42; sx: 0.4; sy: 0.024; sz: 0.14; col: "#3a3e48" }
                    Panel3D {
                        px: seatN.modelData.x; py: 1.09; pz: seatN.zf + seatN.modelData.side * 0.027; w: 0.6; h: 0.34
                        eulerRotation.y: seatN.modelData.side > 0 ? 0 : 180
                        bright: seatN.occ ? 1.6 : 1
                        src: CodeScreen { node: seatN.occ; sd: seatN.index * 3.7 }
                    }
                }
            }

            // ---------------------------------------------- bàn sếp (Opus)
            Box { py: 0.95; pz: -3.3; sx: 2.9; sy: 0.08; sz: 1.16; col: "#86664a"; rough: 0.5 }
            Box { px: -1.38; py: 0.46; pz: -3.3; sx: 0.12; sy: 0.92; sz: 1.08; col: app.mDark }
            Box { px: 1.38; py: 0.46; pz: -3.3; sx: 0.12; sy: 0.92; sz: 1.08; col: app.mDark }
            Box { py: 0.5; pz: -2.8; sx: 2.7; sy: 0.8; sz: 0.06; col: "#6a503a" }
            Repeater3D {
                model: [-0.75, 0, 0.75]
                Node {
                    id: monN
                    required property var modelData
                    position: Qt.vector3d(modelData * 100, 130, -315)
                    eulerRotation.y: modelData * 22
                    Box { sx: 0.68; sy: 0.44; sz: 0.05; col: app.mDark; rough: 0.4; metal: 0.3 }
                    Box { py: -0.27; sx: 0.06; sy: 0.12; sz: 0.06; col: app.mMetal }
                    Panel3D {
                        pz: -0.027; w: 0.62; h: 0.38
                        eulerRotation.y: 180
                        bright: house.live ? 1.5 : 1
                        src: CodeScreen { node: house.open && house.act.opus ? app.nodeMap[house.pfx + "role-opus"] ?? null : null; sd: monN.modelData * 9 + 40 }
                    }
                }
            }
            Box { px: 0.9; py: 1.04; pz: -2.95; sx: 0.1; sy: 0.12; sz: 0.1; shape: "#Cylinder"; col: "#f0f0f4"; rough: 0.2 }

            // bàn thực hiện (Sonnet): cạnh bàn sếp, 2 màn hình
            Box { px: -3.6; py: 0.95; pz: -3.3; sx: 1.9; sy: 0.08; sz: 1.0; col: "#8a6a58"; rough: 0.5 }
            Box { px: -4.5; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
            Box { px: -2.7; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
            Box { px: -3.6; py: 0.5; pz: -2.84; sx: 1.7; sy: 0.8; sz: 0.05; col: "#6e5446" }
            Repeater3D {
                model: [-0.42, 0.42]
                Node {
                    id: orN
                    required property var modelData
                    position: Qt.vector3d(-360 + modelData * 100, 130, -320)
                    eulerRotation.y: modelData * 30
                    Box { sx: 0.66; sy: 0.42; sz: 0.05; col: app.mDark; rough: 0.4; metal: 0.3 }
                    Panel3D {
                        pz: -0.027; w: 0.6; h: 0.36
                        eulerRotation.y: 180
                        bright: house.act.sonnet ? 1.5 : 1
                        src: CodeScreen { node: house.open && house.act.sonnet ? app.nodeMap[house.pfx + "role-sonnet"] ?? null : null; sd: orN.modelData * 7 + 90 }
                    }
                }
            }

            // bàn điều phối Jev (đối xứng bàn Sonnet): 2 màn hình
            Box { px: 3.0; py: 0.95; pz: -3.3; sx: 1.5; sy: 0.08; sz: 1.0; col: "#8a7a4a"; rough: 0.5 }
            Box { px: 2.3; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
            Box { px: 3.7; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
            Box { px: 3.0; py: 0.5; pz: -2.84; sx: 1.35; sy: 0.8; sz: 0.05; col: "#6e6446" }
            Repeater3D {
                model: [-0.42, 0.42]
                Node {
                    id: jvN
                    required property var modelData
                    position: Qt.vector3d(300 + modelData * 90, 130, -320)
                    eulerRotation.y: modelData * 30
                    Box { sx: 0.66; sy: 0.42; sz: 0.05; col: app.mDark; rough: 0.4; metal: 0.3 }
                    Panel3D {
                        pz: -0.027; w: 0.6; h: 0.36
                        eulerRotation.y: 180
                        bright: house.act.jev ? 1.5 : 1
                        src: CodeScreen { node: house.open && house.act.jev ? app.nodeMap[house.pfx + "role-jev"] ?? null : null; sd: jvN.modelData * 5 + 130 }
                    }
                }
            }

            // ---------------------------------------------- bảng trắng (advisor)
            Node {
                Box { px: app.board[0]; py: 1.45; pz: app.board[1]; sx: 0.06; sy: 1.24; sz: 2.0; col: "#eceef2"; rough: 0.3 }
                Box { px: app.board[0]; py: 1.45; pz: app.board[1]; sx: 0.05; sy: 1.3; sz: 2.06; col: app.mMetal; metal: 0.6; rough: 0.35 }
                Box { px: app.board[0]; py: 0.42; pz: app.board[1] - 0.9; sx: 0.06; sy: 0.84; sz: 0.06; col: app.mMetal }
                Box { px: app.board[0]; py: 0.42; pz: app.board[1] + 0.9; sx: 0.06; sy: 0.84; sz: 0.06; col: app.mMetal }
                Panel3D {
                    px: app.board[0] + 0.032; py: 1.45; pz: app.board[1]; w: 1.94; h: 1.18
                    eulerRotation.y: 90
                    src: Rectangle {
                        id: wb
                        width: 420; height: 256
                        color: "#f4f5f8"
                        readonly property var lines: house.c?.s?.advisor?.last ?? []
                        Column {
                            x: 18; y: 14; width: 384
                            spacing: 6
                            Text { text: "ADVICE ✎"; color: "#6a5cc8"; font { family: "Comic Sans MS"; pixelSize: 26; bold: true } }
                            Repeater {
                                model: Array.isArray(wb.lines) ? wb.lines : []
                                Text {
                                    required property string modelData
                                    width: 384; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                    text: "• " + modelData
                                    color: "#3a3a8a"
                                    font { family: "Comic Sans MS"; pixelSize: 19 }
                                }
                            }
                            Text {
                                visible: house.open && (house.c?.advisorRunning ?? false)
                                text: "…".repeat(1 + Math.floor(app.t * 2) % 3)
                                color: "#6a5cc8"; font.pixelSize: 26
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------- tủ server
            Box { px: -5.6; py: 1.1; pz: -4.55; sx: 0.9; sy: 2.2; sz: 0.7; col: "#1c1f26"; metal: 0.5; rough: 0.4 }
            Panel3D {
                px: -5.6; py: 1.15; pz: -4.195; w: 0.76; h: 1.8; bright: 1.8
                src: Rectangle {
                    id: rack
                    readonly property int tick: house.open ? Math.floor(app.t * (house.live ? 8 : 1.5)) : 0
                    width: 76; height: 180; color: "#24272f"
                    Grid {
                        x: 6; y: 8; columns: 2; rowSpacing: 8; columnSpacing: 6
                        Repeater {
                            model: 18
                            Row {
                                required property int index
                                spacing: 4
                                Rectangle { width: 22; height: 10; color: "#353944" }
                                Rectangle {
                                    width: 4; height: 4; anchors.verticalCenter: parent.verticalCenter
                                    color: app.rnd(parent.index * 3.1 + rack.tick) > (house.live ? 0.35 : 0.8) ? (parent.index % 5 ? app.cOk : app.cWait) : "#203028"
                                }
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------- góc nghỉ
            Box { px: 6.1; py: 0.22; pz: -2.6; sx: 0.9; sy: 0.44; sz: 2.3; col: "#755c8c"; rough: 0.95 }
            Box { px: 6.5; py: 0.6; pz: -2.6; sx: 0.2; sy: 0.8; sz: 2.3; col: "#6c5482"; rough: 0.95 }
            Box { px: 6.1; py: 0.38; pz: -3.8; sx: 0.9; sy: 0.32; sz: 0.16; col: "#644e78"; rough: 0.95 }
            Box { px: 6.1; py: 0.38; pz: -1.4; sx: 0.9; sy: 0.32; sz: 0.16; col: "#644e78"; rough: 0.95 }
            Box { px: 5.1; py: 0.32; pz: -2.6; sx: 0.6; sy: 0.05; sz: 1.1; col: app.mWood; rough: 0.5 }
            Box { px: 5.1; py: 0.15; pz: -2.6; sx: 0.1; sy: 0.3; sz: 0.1; shape: "#Cylinder"; col: app.mMetal }
            Box { px: 6.45; py: 0.45; pz: -4.5; sx: 0.8; sy: 0.9; sz: 0.7; col: "#c8cad0"; rough: 0.4 }
            Box { px: 6.45; py: 1.08; pz: -4.5; sx: 0.5; sy: 0.36; sz: 0.5; col: "#323438"; metal: 0.6; rough: 0.3 }
            Box { px: 6.04; py: 1.0; pz: -4.5; sx: 0.012; sy: 0.08; sz: 0.12; col: "black"; glow: house.live ? app.cWait : "#5a4628"; glowK: 0.5 }

            // ---------------------------------------------- chậu cây
            Repeater3D {
                model: [[-6.5, -4.5, 1.2], [6.5, 4.5, 1], [2.4, 4.55, 0.8]]
                Node {
                    id: plantN
                    required property var modelData
                    readonly property real sc: modelData[2]
                    Box { px: plantN.modelData[0]; py: 0.22 * plantN.sc; pz: plantN.modelData[1]; sx: 0.4 * plantN.sc; sy: 0.44 * plantN.sc; sz: 0.4 * plantN.sc; shape: "#Cylinder"; col: "#b46e50"; rough: 0.9 }
                    Repeater3D {
                        model: 3
                        Box {
                            required property int index
                            px: plantN.modelData[0] + Math.cos(index * 2.1) * 0.12 * plantN.sc
                            py: (0.62 + index * 0.18) * plantN.sc
                            pz: plantN.modelData[1] + Math.sin(index * 2.1) * 0.12 * plantN.sc
                            sx: 0.48 * plantN.sc; sy: 0.48 * plantN.sc; sz: 0.48 * plantN.sc
                            shape: "#Sphere"; col: index === 1 ? "#5aa860" : "#4a9452"; rough: 0.8
                        }
                    }
                }
            }
        }
    }


    // ------------------------------------------------------------------ cửa sổ
    FloatingWindow {
        id: win
        title: "Claude Agents City"
        implicitWidth: 1200
        implicitHeight: 800
        minimumSize: Qt.size(720, 500)
        color: app.bg
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_R) { app.yaw = 0.7; app.pitch = 0.62; app.flyOverview(); }
                else if (e.key === Qt.Key_Space) app.spin = !app.spin;
                else if (e.key === Qt.Key_0 || e.key === Qt.Key_A) app.flyOverview();
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_8) app.flyHouse(e.key - Qt.Key_1);
                else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Q) Qt.quit();
            }

            View3D {
                id: view
                anchors.fill: parent
                camera: camera

                environment: ExtendedSceneEnvironment {
                    backgroundMode: SceneEnvironment.Color
                    clearColor: "#1a2332"
                    antialiasingMode: SceneEnvironment.MSAA
                    antialiasingQuality: SceneEnvironment.Medium
                    tonemapMode: SceneEnvironment.TonemapModeFilmic
                    exposure: 1.3
                    aoEnabled: app.aoOn     // AO nặng: chỉ khi đang ở trong một nhà và zoom gần
                    aoStrength: 40
                    aoDistance: 18
                    aoSoftness: 40
                    glowEnabled: true
                    glowIntensity: 1.1
                    glowBloom: 0.25
                    glowStrength: 1.1
                    glowHDRMinimumValue: 0.55
                    glowQualityHigh: false
                    glowUseBicubicUpscale: false
                    // không dùng vignette: hiệu ứng này phủ lớp xám lên cả khung hình, làm mất màu vật phát sáng
                    vignetteEnabled: false
                    ditheringEnabled: true
                }

                Node {
                    position: app.look
                    eulerRotation.y: app.yaw * 180 / Math.PI
                    eulerRotation.x: -app.pitch * 180 / Math.PI
                    PerspectiveCamera {
                        id: camera
                        z: app.dist * 100
                        fieldOfView: 38
                        clipNear: 50
                        clipFar: 40000
                    }
                }

                // ánh sáng ngoài trời: nắng chéo (bóng chỉ khi zoom gần) + ánh sáng trời lạnh + ambient; đèn trần chỉ trong nhà đang mở
                DirectionalLight {
                    eulerRotation: Qt.vector3d(-55, -32, 0)
                    color: "#fff1e0"
                    brightness: 2.1
                    ambientColor: Qt.rgba(0.48, 0.5, 0.58, 1)
                    castsShadow: app.shadowOn
                    shadowMapQuality: Light.ShadowMapQualityHigh
                    shadowFactor: 50
                    pcfFactor: 2
                    softShadowQuality: Light.PCF8
                    shadowMapFar: 6000
                }
                DirectionalLight {
                    eulerRotation: Qt.vector3d(-30, 150, 0)
                    color: "#b4c6ff"
                    brightness: 0.8
                }

                // ---------------------------------------------- nền đất + lưới đường chung (toạ độ thế giới)
                Box { py: -0.3; sx: 300; sy: 0.3; sz: 300; col: "#2f4234"; rough: 0.95 }
                // mặt đường: phố chính (z = 0), phố cắt ngang (x = 0), đường vành đai
                Repeater3D {
                    model: [
                        { x: 0, z: 0, w: 86, d: 6 }, { x: 0, z: 0, w: 6, d: 44 },
                        { x: 0, z: -20, w: 86, d: 4 }, { x: 0, z: 20, w: 86, d: 4 },
                        { x: -41, z: 0, w: 4, d: 44 }, { x: 41, z: 0, w: 4, d: 44 }
                    ]
                    Box {
                        required property var modelData
                        px: modelData.x; pz: modelData.z; py: -0.13; sx: modelData.w; sy: 0.04; sz: modelData.d; col: "#2b2f37"; rough: 0.9
                    }
                }
                // vỉa hè dọc phố chính và phố cắt ngang
                Repeater3D {
                    model: [
                        { x: -21, z: -4, w: 36, d: 2 }, { x: 21, z: -4, w: 36, d: 2 }, { x: -21, z: 4, w: 36, d: 2 }, { x: 21, z: 4, w: 36, d: 2 },
                        { x: -4, z: -11.5, w: 2, d: 13 }, { x: 4, z: -11.5, w: 2, d: 13 }, { x: -4, z: 11.5, w: 2, d: 13 }, { x: 4, z: 11.5, w: 2, d: 13 }
                    ]
                    Box {
                        required property var modelData
                        px: modelData.x; pz: modelData.z; py: -0.1; sx: modelData.w; sy: 0.1; sz: modelData.d; col: "#767b85"; rough: 0.9; pickable: true
                    }
                }
                // vạch giữa đường (nét đứt) + vạch qua đường kiểu ngựa vằn ở ngã tư
                Repeater3D {
                    model: {
                        const out = [];
                        for (let v = -40; v <= 40; v += 3) if (Math.abs(v) > 6) out.push({ x: v, z: 0, w: 1.5, d: 0.12, c: "#d8c060" });
                        for (let v = -19; v <= 19; v += 3) if (Math.abs(v) > 6) out.push({ x: 0, z: v, w: 0.12, d: 1.5, c: "#d8c060" });
                        for (const sx of [-4.4, 4.4]) for (let k = -2.5; k <= 2.5; k += 1) out.push({ x: sx, z: k, w: 1.5, d: 0.45, c: "#e2e4ea" });
                        for (const sz of [-4.4, 4.4]) for (let k = -2.5; k <= 2.5; k += 1) out.push({ x: k, z: sz, w: 0.45, d: 1.5, c: "#e2e4ea" });
                        return out;
                    }
                    Box {
                        required property var modelData
                        px: modelData.x; pz: modelData.z; py: -0.105; sx: modelData.w; sy: 0.01; sz: modelData.d; col: modelData.c; rough: 0.8
                    }
                }
                // bùng binh ở ngã tư: bồn cỏ + đài phun nước nhỏ
                Box { py: -0.02; sx: 3.4; sy: 0.22; sz: 3.4; shape: "#Cylinder"; col: "#9c968a"; rough: 0.8 }
                Box { py: 0.1; sx: 3.0; sy: 0.04; sz: 3.0; shape: "#Cylinder"; col: "#4f9a56"; rough: 0.9 }
                Box { py: 0.2; sx: 1.4; sy: 0.25; sz: 1.4; shape: "#Cylinder"; col: "#b8b2a6"; rough: 0.6 }
                Box { py: 0.33; sx: 1.2; sy: 0.02; sz: 1.2; shape: "#Cylinder"; col: "#3a7fc0"; rough: 0.1; glow: "#6ab0ff"; glowK: 0.25 }
                Box { py: 0.75; sx: 0.14; sy: 0.9; sz: 0.14; shape: "#Cylinder"; col: "#b8b2a6" }
                Box { py: 1.25; sx: 0.4 + Math.sin(app.t * 3) * 0.04; sy: 0.25; sz: 0.4; shape: "#Sphere"; col: "#a8d4ff"; rough: 0.1; glow: "#80c0ff"; glowK: 0.3; castsShadows: false }
                // đèn giao thông ở 4 góc ngã tư (phố chính / phố ngang luân phiên)
                Repeater3D {
                    model: [[-3.5, -3.5, 0], [3.5, 3.5, 0], [3.5, -3.5, 1], [-3.5, 3.5, 1]]
                    Node {
                        id: tlN
                        required property var modelData
                        // 0 xanh, 1 vàng, 2 đỏ — chu kỳ 16 s
                        readonly property real ph: (app.t + tlN.modelData[2] * 8) % 16
                        readonly property int light: ph < 6.5 ? 0 : ph < 8 ? 1 : 2
                        Box { px: tlN.modelData[0]; py: 1.4; pz: tlN.modelData[1]; sx: 0.1; sy: 2.8; sz: 0.1; shape: "#Cylinder"; col: "#3a3e46"; metal: 0.5; rough: 0.4 }
                        Box { px: tlN.modelData[0]; py: 2.95; pz: tlN.modelData[1]; sx: 0.32; sy: 0.86; sz: 0.32; col: "#1c1e22"; rough: 0.5 }
                        Repeater3D {
                            model: [{ c: "#4ef08a", y: 2.69 }, { c: "#ffc640", y: 2.95 }, { c: "#ff4a3a", y: 3.21 }]
                            Box {
                                required property var modelData
                                required property int index
                                px: tlN.modelData[0]; py: modelData.y; pz: tlN.modelData[1]; sx: 0.36; sy: 0.2; sz: 0.36
                                shape: "#Sphere"; col: tlN.light === index ? "black" : "#25272c"
                                glow: modelData.c; glowK: tlN.light === index ? 1.6 : 0; castsShadows: false
                            }
                        }
                    }
                }
                // đèn đường dọc vỉa hè (đặt ở khe giữa các nhà để không che tầm nhìn vào nhà)
                Repeater3D {
                    model: [[-21.5, -4.6], [-38.5, -4.6], [21.5, -4.6], [38.5, -4.6],
                            [-21.5, 4.6], [-38.5, 4.6], [21.5, 4.6], [38.5, 4.6],
                            [-4.6, -12], [4.6, -12], [-4.6, 12], [4.6, 12]]
                    Node {
                        id: lampN
                        required property var modelData
                        Box { px: lampN.modelData[0]; py: 1.5; pz: lampN.modelData[1]; sx: 0.08; sy: 3.0; sz: 0.08; shape: "#Cylinder"; col: app.mMetal; metal: 0.5; rough: 0.4 }
                        Box { px: lampN.modelData[0]; py: 3.05; pz: lampN.modelData[1]; sx: 0.32; sy: 0.26; sz: 0.32; shape: "#Sphere"; col: "black"; glow: "#ffd9a0"; glowK: 1.0; castsShadows: false }
                    }
                }
                // cây ở khe giữa các nhà / cuối dãy
                Repeater3D {
                    model: [[-21.5, -9], [-21.5, -15], [21.5, -9], [21.5, -15], [-21.5, 9], [-21.5, 15], [21.5, 9], [21.5, 15],
                            [-39, -8], [39, -8], [-39, 8], [39, 8], [-39, -15], [39, 15]]
                    Tree {
                        required property var modelData
                        px: modelData[0]; pz: modelData[1]; k: 1.2
                    }
                }
                // lô trống: công viên nhỏ (bãi cỏ, lối đi, cây, ghế đá)
                Repeater3D {
                    model: app.parkLots
                    Node {
                        id: parkN
                        required property var modelData
                        readonly property var lot: app.lots[modelData]
                        position: Qt.vector3d(lot[0] * 100, 0, lot[1] * (app.lotOZ - 0.25) * 100)
                        Box { py: -0.09; sx: 16; sy: 0.1; sz: 12.5; col: "#4a8050"; rough: 0.95 }
                        Box { py: -0.04; sx: 1.2; sy: 0.02; sz: 12.4; col: "#b0a48a"; rough: 0.9 }
                        Box { py: -0.04; sx: 15.8; sy: 0.02; sz: 1.2; col: "#b0a48a"; rough: 0.9 }
                        Box { py: -0.02; sx: 2.6; sy: 0.08; sz: 2.6; shape: "#Cylinder"; col: "#c87aa0"; rough: 0.9 }
                        Tree { px: -4.5; pz: -3.2; k: 1.3 }
                        Tree { px: 4.8; pz: 3.0; k: 1.1 }
                        Tree { px: 5.2; pz: -3.6; k: 0.9 }
                        Box { px: -3.6; py: 0.42; pz: 2.2; sx: 1.6; sy: 0.08; sz: 0.5; col: app.mWood; rough: 0.6 }
                        Box { px: -3.6; py: 0.2; pz: 2.2; sx: 1.4; sy: 0.4; sz: 0.1; col: app.mMetal }
                    }
                }

                // ---------------------------------------------- các nhà (một House mỗi dự án)
                Repeater3D {
                    model: app.houseCount
                    House {
                        required property int index
                        ci: index
                    }
                }

                // ---------------------------------------------- mascot
                Repeater3D {
                    model: robotModel
                    Robot {}
                }

                // ---------------------------------------------- gói tin (chỉ trong nhà đang mở)
                Repeater3D {
                    model: app.packets
                    Box {
                        required property var modelData
                        readonly property var a: app.actors[modelData.id] ?? null
                        readonly property var cc: app.houses[modelData.ci] ?? null
                        readonly property real sg: cc?.sg ?? 1
                        readonly property var hub: app.stations[cc?.leadFam ?? "opus"].desk
                        readonly property real spd: 0.35 + Math.min(1, (app.nodeMap[modelData.id]?.d?.tools ?? 0) / 40) * 0.5
                        readonly property real u0: (app.t * spd + modelData.k / 2 + (modelData.dir < 0 ? 0.25 : 0)) % 1
                        readonly property real u: modelData.dir > 0 ? u0 : 1 - u0
                        readonly property real lx: a ? hub[0] + (a.x - hub[0]) * u : 0
                        readonly property real lz: a ? hub[1] + (a.z - hub[1]) * u : 0
                        visible: !!a && !!cc && !a.moving && app.houseOpen(modelData.ci)
                        px: (cc?.cx ?? 0) + sg * lx
                        py: 1.55 - 0.2 * u + Math.sin(Math.PI * u) * 1.4
                        pz: (cc?.cz ?? 0) + sg * lz
                        sx: 0.08; sy: 0.08; sz: 0.08
                        eulerRotation: Qt.vector3d(app.t * 120, app.t * 90, 0)
                        col: "black"
                        glow: modelData.dir > 0 ? app.roles[cc?.leadFam ?? "opus"].col : (app.nodeMap[modelData.id]?.col ?? app.cSwarm)
                        glowK: 0.5
                        castsShadows: false
                    }
                }
            }

            // ---------------------------------------------------------- nhãn trên đầu mascot (chỉ nhà đang mở)
            Repeater {
                model: robotModel
                Item {
                    id: lab
                    required property string rid
                    readonly property var nd: app.nodeMap[rid] ?? null
                    readonly property bool on: !!nd && app.houseOpen(nd.ci)
                    readonly property var a: on ? (app.actors[rid] ?? null) : null
                    readonly property var cc: nd ? (app.houses[nd.ci] ?? null) : null
                    readonly property bool shown: on && !!a
                    readonly property vector3d sp: (app.yaw, app.pitch, app.dist, app.lookX, app.lookZ, view.width, view.height, shown
                        ? view.mapFrom3DScene(Qt.vector3d((nd.cx + nd.sg * a.x) * 100, (nd.sc ?? 1) * 125, (nd.cz + nd.sg * a.z) * 100))
                        : Qt.vector3d(0, 0, -1))
                    visible: shown && sp.z > 0
                    x: sp.x
                    y: sp.y
                    z: 100 - sp.z / 100
                    opacity: nd?.kind === "done" ? 0.6 : 1
                    Rectangle {
                        x: -width / 2; y: -height - 4
                        width: col.implicitWidth + 12; height: col.implicitHeight + 6
                        radius: 5
                        color: Qt.rgba(0.06, 0.07, 0.1, 0.78)
                        border.color: lab.nd ? Qt.alpha(lab.nd.col, lab.nd.kind === "sub" || lab.nd.kind === "role" ? 0.7 : 0.3) : "transparent"
                        Column {
                            id: col
                            anchors.centerIn: parent
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: lab.nd?.label ?? ""
                                color: lab.nd?.col ?? app.fg
                                font { family: app.mono; pixelSize: lab.nd?.kind === "role" ? 11 : 10; bold: true }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: text !== ""
                                color: app.fg
                                font { family: app.mono; pixelSize: 9 }
                                text: {
                                    const m = lab.nd, d = m?.d, c = lab.cc;
                                    if (!m || !c) return "";
                                    if (m.kind === "role") {
                                        if (m.lead && c.s) {
                                            if (c.running > 0) return `📋 giao việc cho ${c.running} agent`;
                                            if (!c.s.busy) return `☕ rảnh · turn ${c.s.turns ?? 0}`;
                                            const tk = (c.s.task || "đang làm").slice(0, 40);
                                            return `⌨ ${tk}${c.s.tool ? " · " + c.s.tool : ""} · ${c.s.tools ?? 0}⚒`;
                                        }
                                        const mv = app.actors[m.id]?.moving ?? false;
                                        if (m.fam === "jev") {
                                            const pl = app.patrolLabels[m.ci] ?? "";
                                            if (pl) return mv ? `🚶 đi kiểm tra ${pl}` : `🔍 giám sát ${pl}`;
                                            return app.jev && m.ci === app.hotIdx ? `▸ ${app.jev.worker} · ${app.ago(app.jev.at)}` : "☕ chờ việc để giám sát";
                                        }
                                        if (m.fam === "haiku") {
                                            // Haiku: mặc định 1 agent rảnh; đang làm thì hiện mô tả + số đang làm; xong thì "done" trong 30 s
                                            const hs = c.swarm.filter(x => app.fam(x.model) === "haiku");
                                            const run = hs.filter(x => x.status === "running");
                                            const lastEnd = Math.max(0, ...hs.map(x => x.end || 0));
                                            const tail = hs.length ? ` · ${hs.length} tham gia` : "";
                                            if (run.length) return `⌨ ${(run[0].desc || run[0].type || "đang làm").slice(0, 36)} · ${run.length} làm${tail}`;
                                            // done: giữ 30 s sau khi lượt dừng (Stop) hoặc subagent Haiku vừa xong, rồi về rảnh
                                            const stopped = !c.s?.busy && (c.s?.doneAt ?? 0) > 0 && app.now - c.s.doneAt < 30;
                                            if (hs.length && ((lastEnd && app.now - lastEnd < 30) || stopped)) return `✓ done${tail}`;
                                            return `☕ 1 rảnh${tail}`;
                                        }
                                        const rs = c.swarm.find(x => x.status === "running" && app.fam(x.model) === m.fam);
                                        if (rs) return `⌨ ${(rs.desc || rs.type || "đang làm").slice(0, 40)}${rs.tool ? " · " + rs.tool : ""} · ${rs.tools}⚒`;
                                        if ((app.houseAct[m.ci] ?? {})[m.fam]) return "⌨ đang làm";
                                        return mv ? "🚶 đi dạo" : "💤 ngủ";
                                    }
                                    if (m.kind === "sub") return `${app.cap(d.model)}${d.desc ? " · " + d.desc.slice(0, 40) : ""} · ${d.tools}⚒${d.tool ? " · " + d.tool : ""}`;
                                    if (m.kind === "advisor") return d.status === "running" ? "✎ đang tư vấn…" : `${c.s?.advisor?.calls ?? 0} lần tư vấn`;
                                    if (m.kind === "pend") return "🚪 đang vào…";
                                    return `✓ ${Math.round((d.end || d.start) - d.start)}s · ☕`;
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                hoverEnabled: true
                property real lx
                property real ly
                property real px0
                property real py0
                // đi ngược cây node từ vật bị chọn: tìm mascot (robotId) hoặc nhà (houseId)
                function hit(x, y) {
                    let o = view.pick(x, y).objectHit;
                    while (o && o.robotId === undefined && o.houseId === undefined) o = o.parent;
                    return o;
                }
                onPressed: m => { lx = m.x; ly = m.y; px0 = m.x; py0 = m.y; root.forceActiveFocus(); }
                onReleased: m => {
                    if (Math.hypot(m.x - px0, m.y - py0) > 4) return;      // vừa kéo xoay, không phải click
                    const o = hit(m.x, m.y);
                    const ci = !o ? -1 : o.robotId !== undefined ? (app.nodeMap[o.robotId]?.ci ?? -1) : o.houseId;
                    // nhà giữ chỗ "chưa có dự án" (cwd rỗng, không phiên) không được chọn bằng click
                    if (ci >= 0 && ci !== app.sel && (app.houses[ci]?.nSess ?? 0) > 0) app.flyHouse(ci);
                }
                onPositionChanged: m => {
                    if (pressed) {
                        app.yaw -= (m.x - lx) * 0.007;
                        app.pitch = Math.max(0.12, Math.min(1.4, app.pitch + (m.y - ly) * 0.005));
                        lx = m.x; ly = m.y;
                        return;
                    }
                    const o = hit(m.x, m.y);
                    app.hovered = o && o.robotId !== undefined ? o.robotId : "";
                    tip.mx = m.x; tip.my = m.y;
                }
                onExited: app.hovered = ""
                // chuột: angleDelta ±120/nấc; touchpad 2 ngón có thể chỉ có pixelDelta (angleDelta = 0) → dùng dự phòng.
                // Zoom tỉ lệ theo độ lớn delta (1 nấc = ×0.92 như cũ), delta 0 (cuộn ngang) thì bỏ qua.
                onWheel: w => {
                    const dy = w.angleDelta.y !== 0 ? w.angleDelta.y / 120 : w.pixelDelta.y / 120;
                    if (dy === 0) return;
                    fly.stop();
                    app.dist = Math.max(6, Math.min(160, app.dist * Math.pow(0.92, Math.max(-3, Math.min(3, dy)))));
                }
            }

            // ---------------------------------------------------------- HUD
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
                            color: app.live ? app.cOk : app.muted
                            SequentialAnimation on opacity {
                                running: app.live; loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 700 }
                                NumberAnimation { to: 1; duration: 700 }
                            }
                        }
                        T { text: "CLAUDE AGENTS CITY · " + app.houseCount + " nhà"; font.bold: true; font.letterSpacing: 1.5 }
                    }
                    T { text: app.sessionList.length ? app.sessionList.length + " phiên · " + app.houses.filter(c => c.live).length + " nhà đang chạy" : "chưa có phiên"; color: app.muted; font.pixelSize: 10 }
                    T {
                        text: app.hc.s ? "🏠 " + app.hc.name + (app.sel < 0 ? "  (phiên mới nhất)" : "") : "🏠 chưa có dự án — 3 vai đang chờ việc"
                        color: app.cClaude
                    }
                    T {
                        visible: !!app.hc.s
                        text: app.cap(app.hc.s?.model) + "  effort " + app.effortBlocks(app.hc.s?.effort) + " " + (app.hc.s?.effort || "—")
                        color: app.cLead
                    }
                    T {
                        visible: !!app.jev && app.jev.worker !== "none"
                        color: app.cAdv
                        text: app.jev ? `Jev ▸ ${app.jev.worker} → ${app.jev.reviewer === "none" ? "không review" : app.jev.reviewer}${app.jev.quality !== undefined ? " · q " + app.jev.quality.toFixed(2) : ""}${(app.jev.quality ?? 1) < 0.5 ? " · Sonnet điều phối" : ""} · ${app.ago(app.jev.at)}` : ""
                    }
                    T {
                        visible: !!app.hc.s
                        text: `phase ${app.hc.phase} · ${app.hc.running} đang làm · ${app.hc.swarm.length - app.hc.running} xong`
                    }
                    T {
                        visible: !!app.hc.s
                        color: app.muted
                        text: `lead tools ${app.hc.s?.tools ?? 0} · swarm tools ${app.hc.swarm.reduce((n, x) => n + x.tools, 0)}`
                    }
                }
            }

            Column {
                anchors { top: parent.top; right: parent.right; margins: 14 }
                spacing: 5
                Repeater {
                    model: app.houses
                    Panel {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === app.sel
                        anchors.right: parent.right
                        width: row.implicitWidth + 18; height: 26
                        border.color: sel ? Qt.alpha(app.cClaude, 0.9) : Qt.rgba(1, 1, 1, 0.08)
                        Row {
                            id: row
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle { width: 8; height: 8; radius: 2; color: chip.modelData.roofCol; anchors.verticalCenter: parent.verticalCenter }
                            T { text: (chip.index + 1) + ""; color: app.muted }
                            T { text: chip.modelData.live ? "●" : "○"; color: chip.modelData.live ? app.cOk : app.muted }
                            T { text: chip.modelData.name }
                            T { text: chip.modelData.nSess > 0 ? "×" + chip.modelData.nSess : ""; color: app.muted }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: chip.sel ? app.flyOverview() : app.flyHouse(chip.index)
                        }
                    }
                }
                T {
                    anchors.right: parent.right
                    text: app.sel >= 0 ? "đang ở trong nhà " + (app.sel + 1) + " · 0 = toàn cảnh" : "toàn cảnh · 1..8 hoặc click nhà để vào"
                    color: app.muted; font.pixelSize: 10
                }
            }

            Panel {
                visible: !!app.hc.s?.repeatError
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 14 }
                width: Math.min(parent.width * 0.5, errT.implicitWidth + 24); height: 30
                border.color: Qt.alpha(app.cErr, 0.8)
                T {
                    id: errT
                    anchors.centerIn: parent
                    width: parent.width - 24
                    elide: Text.ElideRight
                    text: "⚠ cùng lỗi ×2 · " + (app.hc.s?.repeatError ?? "")
                    color: app.cErr
                }
            }

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
                            { c: app.cOrch, t: "kiểm tra (Sonnet)" }, { c: app.cWorker, t: "thực hiện (Haiku)" }, { c: app.cJev, t: "Jev điều phối" }, { c: app.cLead, t: "khó (Opus)" }, { c: app.cSwarm, t: "subagent" }, { c: app.cFork, t: "fork" },
                            { c: app.cAdv, t: "advisor" }, { c: app.cOk, t: "đang chạy" }, { c: app.cWait, t: "chờ" }
                        ]
                        Row {
                            required property var modelData
                            spacing: 5
                            Rectangle { width: 9; height: 9; radius: 5; color: parent.modelData.c; anchors.verticalCenter: parent.verticalCenter }
                            T { text: parent.modelData.t; color: app.muted }
                        }
                    }
                }
            }

            T {
                anchors { right: parent.right; bottom: parent.bottom; margins: 18 }
                text: "kéo: xoay · cuộn: zoom · 1..8: vào nhà · 0/A/R: toàn cảnh · Space: " + (app.spin ? "dừng xoay" : "tự xoay")
                color: app.muted; font.pixelSize: 10
            }

            Panel {
                id: tip
                property real mx
                property real my
                readonly property var nd: app.nodeMap[app.hovered] ?? null
                visible: !!nd && !drag.pressed
                x: Math.min(parent.width - width - 8, mx + 16)
                y: Math.min(parent.height - height - 8, my + 16)
                z: 2000
                width: tipCol.width + 24; height: tipCol.implicitHeight + 18
                border.color: nd ? Qt.alpha(nd.col, 0.7) : "transparent"
                Column {
                    id: tipCol
                    x: 12; y: 9
                    spacing: 3
                    width: 280
                    T { text: tip.nd?.label ?? ""; color: tip.nd?.col ?? app.fg; font.bold: true }
                    Repeater {
                        model: {
                            const n = tip.nd, d = n?.d;
                            if (!n) return [];
                            const c = app.houses[n.ci], s = c?.s;
                            if (n.kind === "role" && n.lead && s) return [
                                "vai " + app.roles[n.fam].title.toLowerCase() + " · phiên chính · nhà " + c.name,
                                "effort " + (s.effort || "—") + " · turn " + (s.turns ?? 0),
                                (s.busy ? "◐ đang làm việc" : "○ rảnh") + " · " + (s.tools ?? 0) + " tool calls"
                            ];
                            if (n.kind === "role") return [
                                "vai " + app.roles[n.fam].title.toLowerCase() + " · model " + app.roles[n.fam].name + " · nhà " + (c?.name ?? ""),
                                (app.houseAct[n.ci] ?? {})[n.fam] ? "◐ đang làm việc" : "○ chờ việc"
                            ];
                            if (n.kind === "pend") return ["đã được giao việc, chưa bắt đầu", "model " + app.cap(d.model)];
                            const rows = ["model " + app.cap(d.model) + (d.fork ? " · fork" : "") + (d.bg ? " · nền" : "")];
                            if (d.desc) rows.push("“" + d.desc + "”");
                            rows.push(d.tools + " tool calls" + (d.tool ? " · đang dùng " + d.tool : ""));
                            rows.push(d.status === "running" ? "◐ chạy " + app.ago(d.start)
                                                             : "✓ xong sau " + Math.round((d.end || d.start) - d.start) + "s · " + app.ago(d.end || d.start) + " trước");
                            return rows;
                        }
                        T { required property string modelData; text: modelData; width: 280; wrapMode: Text.Wrap }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ thành phần HUD
    component T: Text {
        color: app.fg
        font.family: app.mono
        font.pixelSize: 12
    }
    component Panel: Rectangle {
        color: Qt.rgba(0.08, 0.09, 0.12, 0.78)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        radius: 8
    }
}
