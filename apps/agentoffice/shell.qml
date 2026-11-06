import QtQuick
import QtQuick.Layouts
import QtQuick3D
import QtQuick3D.Helpers
import Quickshell
import Quickshell.Io

// Claude Agent Office: văn phòng 3D (QtQuick3D, GPU), mỗi agent của Claude Code là một robot đang làm việc.
// Dữ liệu: ../agentviz/collector.py (hook của Claude Code) ghi ~/.cache/claude-agentviz/state.json.
//   3 vai cố định (luôn hiện, kể cả khi rảnh): Opus = kiểm tra, làm việc khó (cam, bàn lớn), Sonnet = thực hiện (hồng, bàn cạnh sếp),
//   Haiku = việc dễ (xanh ngọc, chỗ ngồi đầu tiên). Jev router (hook) chọn tầng model; dòng "Jev ▸" ở HUD hiện quyết định gần nhất. Phiên đang chạy model nào thì vai đó là lead: gõ phím khi tự làm, giơ tay chỉ đạo khi giao việc
//   subagent = robot xanh đi vào từ cửa, theo lối đi tới chỗ trong 2 cụm bàn rồi gõ phím; màn hình chạy code
//   fork     = robot xanh lá; advisor = robot tím viết lời khuyên lên bảng trắng
//   xong     = đi sang góc nghỉ (sofa, máy cà phê), cầm cốc
//   gói tin  = khối sáng bay vòng cung giữa bàn sếp và robot đang chạy
// Đơn vị: 1 m = 100 đơn vị Quick3D. Phòng x ∈ [-7, 7], z ∈ [-5, 5], sàn y = 0.
// Mở: apps/agentoffice/claude-agentoffice   (hoặc qs -p ~/dev/cael-src/apps/agentoffice/shell.qml)
// Điều khiển: kéo chuột = xoay · cuộn = zoom · R = đặt lại · Space = tự xoay · 1..8 = chọn phiên · 0 = phiên mới nhất
// Thử với dữ liệu khác: AGENTVIZ_STATE=/đường/dẫn/state.json qs -p …
// IPC: qs -p … ipc call agentoffice close|status|shot /đường/dẫn.png
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

    function mixc(a, b, k) { return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1); }
    function rnd(x) { const v = Math.sin(x * 12.9898) * 43758.5453; return v - Math.floor(v); }

    // ------------------------------------------------------------------ dữ liệu
    property var st: ({})
    property string stText: ""
    property real now: Date.now() / 1000
    property string pinned: ""
    readonly property var sessionList: Object.values(st.sessions ?? {}).sort((a, b) => b.at - a.at)
    readonly property string sid: pinned && (st.sessions ?? {})[pinned] ? pinned : (st.active ?? "")
    readonly property var s: (st.sessions ?? {})[sid] ?? null
    readonly property var subsAll: s ? Object.values(s.subs ?? {}).sort((a, b) => a.start - b.start) : []
    readonly property var swarm: subsAll.filter(x => !x.advisor)
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
        onLoaded: {
            const tx = text();
            if (tx === app.stText) return;      // không đổi: khỏi dựng lại cảnh
            try { app.st = JSON.parse(tx); app.stText = tx; } catch (e) {}
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

    IpcHandler {
        target: "agentoffice"
        function close(): void { Qt.quit(); }
        // chụp cửa sổ ra file PNG (không phụ thuộc workspace đang hiện)
        function shot(path: string): void { root.grabToImage(r => r.saveToFile(path)); }
        function status(): string {
            return JSON.stringify({ live: app.live, phase: app.phase, swarm: app.swarm.length, running: app.running });
        }
    }

    // ------------------------------------------------------------------ bố cục phòng
    readonly property real rx: 7
    readonly property real rz: 5
    readonly property var door: [-7.9, 3.5]           // cửa ở tường x = -7
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

    // ------------------------------------------------------------------ nhân vật
    // 3 vai cố định, luôn có mặt (kể cả khi rảnh / chưa có phiên): Opus = giám đốc, Sonnet = điều phối, Haiku = thực hiện.
    // Phiên Claude Code đang chạy bằng model nào thì robot vai đó là "lead" (hiện số liệu phiên, giao việc cho subagent).
    function fam(m) { m = (m ?? "").toLowerCase(); return ["opus", "sonnet", "haiku"].find(f => m.includes(f)) ?? ""; }
    readonly property string leadFam: fam(s?.model) || "opus"
    readonly property var roles: ({
        opus:   { title: "KIỂM TRA", name: "Opus",   col: cLead,   sc: 1.3 },
        sonnet: { title: "THỰC HIỆN", name: "Sonnet", col: cOrch,   sc: 1.15 },
        haiku:  { title: "VIỆC DỄ", name: "Haiku",  col: cWorker, sc: 1.0 },
        jev:    { title: "ĐIỀU PHỐI", name: "Jev",   col: cJev,    sc: 1.15 }
    })
    // chỗ đứng của từng vai + vị trí mặt bàn (điểm gói tin xuất phát): sếp & điều phối ở hàng bàn cuối phòng, thực hiện ở chỗ ngồi 0
    readonly property var stations: ({
        opus:   { x: 0,     z: -4.3, h: 0, desk: [0, -3.3] },
        sonnet: { x: -3.6,  z: -4.3, h: 0, desk: [-3.6, -3.3] },
        haiku:  { x: seats[0].x, z: seats[0].z, h: seats[0].h, desk: [seats[0].x, podZ] },
        jev:    { x: 3.0,   z: -4.3, h: 0, desk: [3.0, -3.3] }
    })
    // vai nào đang làm việc: lead đang bận, hoặc có subagent cùng model đang chạy
    readonly property var roleAct: {
        const r = { opus: false, sonnet: false, haiku: false, jev: !!jev && now - jev.at < 20 };
        if (s?.busy) r[leadFam] = true;
        for (const x of swarm) if (x.status === "running") { const f = fam(x.model); if (f) r[f] = true; }
        return r;
    }
    readonly property var nodes: {
        const out = [];
        for (const f of ["opus", "sonnet", "haiku", "jev"]) {
            const r = roles[f], lead = f === leadFam;
            out.push({ id: "role-" + f, kind: "role", fam: f, col: r.col, sc: r.sc, lead,
                       label: r.title + " · " + (lead && s ? cap(s.model) : r.name) });
        }
        if (!s) return out;
        const adv = advisorRuns[advisorRuns.length - 1];
        if (adv) out.push({ id: "advisor", kind: "advisor", col: cAdv, label: "advisor", d: adv });
        const run = swarm.filter(x => x.status === "running");
        const done = swarm.filter(x => x.status !== "running").slice(-lounge.length);
        run.forEach(x => out.push({ id: x.id, kind: "sub", col: x.fork ? cFork : cSwarm, label: x.type || "agent", d: x }));
        done.forEach((x, i) => out.push({ id: x.id, kind: "done", col: x.fork ? cFork : cSwarm, label: x.type || "agent", d: x, i }));
        (s.pending ?? []).slice(-3).forEach((x, i) => out.push({ id: "pend" + i, kind: "pend", col: cSwarm, label: x.type, d: x, i }));
        return out;
    }
    readonly property var nodeMap: { const m = {}; for (const n of nodes) m[n.id] = n; return m; }
    // các gói tin: 2 đi + 2 về cho mỗi robot đang chạy, advisor chỉ gửi về
    readonly property var packets: {
        const out = [];
        for (const n of nodes) {
            if (n.kind === "sub") for (let k = 0; k < 2; k++) { out.push({ id: n.id, k, dir: 1 }); out.push({ id: n.id, k, dir: -1 }); }
            else if (n.kind === "advisor" && n.d.status === "running") for (let k = 0; k < 2; k++) out.push({ id: n.id, k, dir: -1 });
        }
        return out;
    }

    // ListModel giữ delegate robot ổn định (không tạo lại khi state đổi)
    ListModel { id: robotModel }
    onNodesChanged: syncRobots()
    Component.onCompleted: syncRobots()
    function syncRobots() {
        const ids = new Set(nodes.map(n => n.id));
        for (let i = robotModel.count - 1; i >= 0; i--) if (!ids.has(robotModel.get(i).rid)) robotModel.remove(i);
        const have = new Set();
        for (let i = 0; i < robotModel.count; i++) have.add(robotModel.get(i).rid);
        for (const n of nodes) if (!have.has(n.id)) robotModel.append({ rid: n.id });
    }

    property var seatOf: ({})
    property var actors: ({})
    property real sessionSince: 0
    onSidChanged: { actors = {}; seatOf = {}; sessionSince = t; }

    // ---- Jev tuần tra: đứng quan sát lần lượt từng agent đang làm việc (5 s mỗi chỗ)
    property real patrolT: 0
    property string patrolLabel: ""
    property var watchList: []
    function computeWatch() {
        const out = [];
        for (const f of ["opus", "sonnet", "haiku"]) if (roleAct[f]) {
            const st = stations[f];
            if (f === "haiku") out.push({ label: "Haiku", x: st.x, z: st.z - 1.0, h: st.h });
            else out.push({ label: cap(f), x: st.x, z: -2.1, h: Math.PI });
        }
        for (const n of nodes) if (n.kind === "sub" && n.d.status === "running") {
            const si = seatOf[n.id];
            if (si === undefined) continue;
            const sd = seats[si];
            out.push({ label: n.label || "agent", x: sd.x - Math.sin(sd.h) * 1.0, z: sd.z - Math.cos(sd.h) * 1.0, h: sd.h });
        }
        return out;
    }
    // ---- robot rảnh: ngủ tại bàn, xen kẽ đi dạo quanh văn phòng (chu kỳ 12 s)
    readonly property var wander: ({
        opus:   [[1.85, -1.6], [-2.05, -1.2]],
        sonnet: [[-5.3, -1.0], [-2.05, -1.8]],
        haiku:  [[-6.0, 3.2], [4.0, 3.3]]
    })
    readonly property var wanderOff: ({ opus: 0, sonnet: 5, haiku: 9 })
    function target(nd) {
        switch (nd.kind) {
        case "role": {
            if (nd.fam === "jev") {
                if (watchList.length > 0) {
                    const w = watchList[Math.floor(patrolT / 5) % watchList.length];
                    return { x: w.x, z: w.z, h: w.h };
                }
                return stations.jev;
            }
            if (!roleAct[nd.fam]) {
                const slot = Math.floor((t + wanderOff[nd.fam]) / 12);
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
            return { x: -5.2, z: 3.9 - (nd.d.start % 3) * 0.5, h: Math.PI / 2 };
        }
        case "done": {
            const p = lounge[nd.i % lounge.length];
            return { x: p[0], z: p[1], h: Math.atan2(5.9 - p[0], -2.6 - p[1]) };
        }
        default: return { x: -6.3, z: 3.5 - nd.i * 0.75, h: Math.PI / 2 };
        }
    }
    function waypoint(a, tg) {
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
    property real dist: 15
    property bool spin: false
    property real t: 0
    readonly property vector3d look: Qt.vector3d(30, 60, 30)
    readonly property var cam: [look.x / 100 + dist * Math.sin(yaw) * Math.cos(pitch), look.y / 100 + dist * Math.sin(pitch), look.z / 100 + dist * Math.cos(yaw) * Math.cos(pitch)]
    property string hovered: ""

    // 0 sau, 1 trái (có cửa), 2 phải, 3 trước: chỉ dựng tường phía xa camera
    function wallShown(i) {
        switch (i) {
        case 0: return cam[2] > -rz;
        case 1: return cam[0] > -rx;
        case 2: return cam[0] < rx;
        default: return cam[2] < rz;
        }
    }

    function step(dt) {
        t += dt;
        if (spin && !drag.pressed) yaw += dt * 0.06;

        const run = nodes.filter(n => n.kind === "sub");
        const so = {}, used = new Set([0]);   // chỗ 0 dành cho Haiku
        for (const n of run) if (seatOf[n.id] !== undefined && !used.has(seatOf[n.id])) { so[n.id] = seatOf[n.id]; used.add(so[n.id]); }
        for (const n of run) if (so[n.id] === undefined) {
            const free = seats.findIndex((_, i) => !used.has(i));
            if (free >= 0) { so[n.id] = free; used.add(free); }
        }
        seatOf = so;
        watchList = computeWatch();
        if (watchList.length > 0) patrolT += dt; else patrolT = 0;
        patrolLabel = watchList.length > 0 ? watchList[Math.floor(patrolT / 5) % watchList.length].label : "";

        const A = {}, fresh = t - sessionSince < 0.4, turn = 1 - Math.pow(0.0005, dt);
        for (const nd of nodes) {
            const tg = target(nd);
            let a = actors[nd.id];
            if (!a) a = (fresh || nd.kind === "role" || nd.kind === "advisor")
                ? { x: tg.x, z: tg.z, h: tg.h, walk: 0 }
                : { x: door[0], z: door[1], h: Math.PI / 2, walk: 0 };
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

    // 24 fps khi có hoạt động / đang xoay / robot đang đi, 12 fps khi văn phòng yên tĩnh
    readonly property bool busyScene: live || spin || drag.pressed || Object.values(actors).some(a => a.moving)
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

    component Robot: Node {
        id: rb
        required property string rid
        readonly property var nd: app.nodeMap[rid] ?? null
        readonly property var a: app.actors[rid] ?? null
        readonly property string robotId: rid
        readonly property real k: nd?.sc ?? 1
        readonly property real seed: (rid.charCodeAt(1) || 3) * 0.37
        readonly property real tt: app.t
        readonly property string kind: nd?.kind ?? ""
        readonly property bool moving: a?.moving ?? false
        readonly property real swing: moving ? Math.sin(a.walk) : 0
        readonly property bool run: kind === "sub"
        readonly property bool done: kind === "done"
        readonly property bool isRole: kind === "role"
        readonly property bool roleActive: isRole && (app.roleAct[nd.fam] ?? false)
        readonly property bool directing: isRole && nd.lead && app.running > 0
        readonly property bool isJev: isRole && nd.fam === "jev"
        readonly property bool inspecting: isJev && !moving && app.watchList.length > 0
        readonly property bool sleeping: isRole && !isJev && !roleActive && !moving
        readonly property bool typing: !moving && (run || (roleActive && !directing && !inspecting))
        readonly property bool writing: kind === "advisor" && nd?.d?.status === "running"
        readonly property real armL: typing ? 1.2 + Math.sin(tt * 17 + seed) * 0.13 : inspecting ? 0.5 : directing ? 0.15 : writing ? 0.1 : done ? 0.9 : swing * 0.6
        readonly property real armR: typing ? 1.2 + Math.sin(tt * 17 + seed + 2.1) * 0.13 : inspecting ? 1.9 + Math.sin(tt * 3) * 0.3 : directing ? 2.3 + Math.sin(tt * 2.2) * 0.25
                                   : writing ? 1.75 + Math.sin(tt * 6) * 0.2 : done ? 0.9 : -swing * 0.6
        readonly property real bob: typing ? Math.sin(tt * 9 + seed) * 0.006 : 0
        readonly property color shell: done ? "#b9bdc6" : kind === "pend" ? "#d4d8df" : "#eef1f6"
        readonly property color accent: !nd ? app.cDone : done ? app.mixc(nd.col, app.cDone, 0.6) : nd.col
        readonly property color status: isRole ? (nd.lead && app.s?.repeatError && Math.sin(tt * 6) > 0 ? app.cErr : roleActive || directing ? app.cOk : app.cDone)
                                      : run || writing ? app.cOk : kind === "pend" ? app.cWait : app.cDone
        readonly property real pulse: status === app.cDone ? 0.12 : 0.42 + Math.sin(tt * 5 + seed) * 0.12
        readonly property bool blink: ((tt * 0.6 + seed) % 4) < 0.12
        readonly property color eye: !nd ? "black" : done ? Qt.darker(nd.col, 1.7) : nd.col

        visible: !!a && !!nd
        position: Qt.vector3d((a?.x ?? 0) * 100, 0, (a?.z ?? 0) * 100)
        eulerRotation.y: (a?.h ?? 0) * 180 / Math.PI
        scale: Qt.vector3d(k, k, k)

        // Kiểu robot trợ lý tròn: vỏ trắng bóng, kính mặt đen, mắt phát sáng, huy hiệu "AI" ở ngực,
        // tay dạng vây, không chân: lơ lửng trên luồng sáng (cao 0.2 m).
        Node {
            y: (0.2 + rb.bob + Math.sin(rb.tt * 2.6 + rb.seed) * 0.025) * 100
            eulerRotation.x: rb.moving ? 9 : 0          // nghiêng người về trước khi bay

            // luồng sáng bên dưới
            Box { py: 0.11; sx: 0.2; sy: 0.05; sz: 0.2; shape: "#Cylinder"; col: "#5a606c"; metal: 0.6; rough: 0.3 }
            Box { py: 0.08; sx: 0.17; sy: 0.01; sz: 0.17; shape: "#Cylinder"; col: "black"; glow: rb.accent; glowK: rb.moving ? 0.5 : 0.32 + Math.sin(rb.tt * 6 + rb.seed) * 0.08; castsShadows: false }

            // thân hình trứng
            Box { py: 0.42; sx: 0.56; sy: 0.62; sz: 0.5; shape: "#Sphere"; col: rb.shell; rough: 0.18; metal: 0.05; pickable: true }
            Box { py: 0.16; sx: 0.42; sy: 0.05; sz: 0.38; shape: "#Cylinder"; col: "#8a909c"; rough: 0.3; metal: 0.4 }
            // huy hiệu AI ở ngực
            Box { py: 0.5; pz: 0.247; sx: 0.25; sy: 0.02; sz: 0.25; shape: "#Cylinder"; eulerRotation.x: 90; col: "black"; glow: rb.accent; glowK: rb.done ? 0.12 : 0.45 }
            Box { py: 0.5; pz: 0.255; sx: 0.19; sy: 0.03; sz: 0.19; shape: "#Cylinder"; eulerRotation.x: 90; col: "#141821"; rough: 0.15; metal: 0.5 }
            Panel3D {
                py: 0.5; pz: 0.272; w: 0.14; h: 0.1; bright: rb.done ? 1 : 1.8
                src: Item {
                    width: 70; height: 50
                    Text { anchors.centerIn: parent; text: "AI"; color: "#eef4ff"; font { family: "Inter"; pixelSize: 34; bold: true } }
                }
            }

            // tay dạng vây (xoay quanh vai)
            Repeater3D {
                model: [-1, 1]
                Node {
                    required property var modelData
                    position: Qt.vector3d(modelData * 30, 64, 0)
                    eulerRotation.x: -(modelData < 0 ? rb.armL : rb.armR) * 180 / Math.PI
                    eulerRotation.z: modelData * 8
                    Box { py: -0.13; sx: 0.11; sy: 0.32; sz: 0.17; shape: "#Sphere"; col: rb.shell; rough: 0.2; metal: 0.05 }
                    Box { visible: rb.done && modelData > 0; py: -0.3; pz: 0.04; sx: 0.09; sy: 0.11; sz: 0.09; shape: "#Cylinder"; col: "#f6f6f8"; rough: 0.2 }
                }
            }

            // cổ + đầu
            Box { py: 0.75; sx: 0.18; sy: 0.06; sz: 0.18; shape: "#Cylinder"; col: "#9aa0aa"; metal: 0.5; rough: 0.3 }
            Box { py: 1.0; sx: 0.6; sy: 0.52; sz: 0.52; shape: "#Sphere"; col: rb.shell; rough: 0.15; metal: 0.05; pickable: true }
            // tai: đĩa tròn hai bên, viền sáng
            Box { py: 1.0; sx: 0.16; sy: 0.68; sz: 0.16; shape: "#Cylinder"; eulerRotation.z: 90; col: rb.shell; rough: 0.2 }
            Box { py: 1.0; sx: 0.1; sy: 0.69; sz: 0.1; shape: "#Cylinder"; eulerRotation.z: 90; col: "black"; glow: rb.accent; glowK: rb.done ? 0.1 : 0.38 }
            // kính mặt đen bóng + mắt
            Box { py: 1.0; pz: 0.16; sx: 0.46; sy: 0.3; sz: 0.22; shape: "#Sphere"; col: "#0a0d14"; rough: 0.05; metal: 0.7 }
            Box { px: -0.095; py: 1.005; pz: 0.272; sx: 0.1; sy: rb.blink || rb.sleeping ? 0.015 : rb.done ? 0.04 : 0.13; sz: 0.03; shape: "#Sphere"; col: "black"; glow: rb.eye; glowK: 0.45; castsShadows: false }
            Box { px: 0.095; py: 1.005; pz: 0.272; sx: 0.1; sy: rb.blink || rb.sleeping ? 0.015 : rb.done ? 0.04 : 0.13; sz: 0.03; shape: "#Sphere"; col: "black"; glow: rb.eye; glowK: 0.45; castsShadows: false }
            // ngủ: chữ z nổi lên trên đầu
            Panel3D {
                visible: rb.sleeping
                py: 1.62 + Math.sin(rb.tt * 1.5) * 0.05; w: 0.5; h: 0.25
                src: Item {
                    width: 120; height: 60
                    Text { anchors.centerIn: parent; text: "z Z z"; color: "#aab4ff"; font { family: "Inter"; pixelSize: 40; bold: true } }
                }
            }
            // ăng-ten nhỏ: đèn trạng thái
            Box { py: 1.3; sx: 0.02; sy: 0.1; sz: 0.02; shape: "#Cylinder"; col: "#9aa0aa"; metal: 0.6 }
            Box { py: 1.36; sx: 0.055; sy: 0.055; sz: 0.055; shape: "#Sphere"; col: "black"; glow: rb.status; glowK: rb.pulse; castsShadows: false }
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

    // ------------------------------------------------------------------ cửa sổ
    FloatingWindow {
        id: win
        title: "Claude Agent Office"
        implicitWidth: 1100
        implicitHeight: 760
        minimumSize: Qt.size(720, 500)
        color: app.bg
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_R) { app.yaw = 0.7; app.pitch = 0.62; app.dist = 15; }
                else if (e.key === Qt.Key_Space) app.spin = !app.spin;
                else if (e.key === Qt.Key_0 || e.key === Qt.Key_A) app.pinned = "";
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_8) {
                    const x = app.sessionList[e.key - Qt.Key_1];
                    if (x) app.pinned = x.id;
                } else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Q) Qt.quit();
            }

            View3D {
                id: view
                anchors.fill: parent
                camera: camera

                environment: ExtendedSceneEnvironment {
                    backgroundMode: SceneEnvironment.Color
                    clearColor: "#0e1016"
                    antialiasingMode: SceneEnvironment.MSAA
                    antialiasingQuality: SceneEnvironment.Medium
                    tonemapMode: SceneEnvironment.TonemapModeFilmic
                    exposure: 1.45
                    aoEnabled: true
                    aoStrength: 40
                    aoDistance: 18
                    aoSoftness: 40
                    glowEnabled: true
                    glowIntensity: 1.1
                    glowBloom: 0.25
                    glowStrength: 1.1
                    glowHDRMinimumValue: 0.55
                    glowQualityHigh: true
                    glowUseBicubicUpscale: true
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
                        clipNear: 20
                        clipFar: 8000
                    }
                }

                // ánh sáng: nắng chéo có bóng + đèn phụ màu lạnh + đèn trần ấm
                DirectionalLight {
                    eulerRotation: Qt.vector3d(-58, -32, 0)
                    color: "#fff1e0"
                    brightness: 2.0
                    ambientColor: Qt.rgba(0.55, 0.57, 0.64, 1)
                    castsShadow: true
                    shadowMapQuality: Light.ShadowMapQualityHigh
                    shadowFactor: 55
                    pcfFactor: 2
                    softShadowQuality: Light.PCF8
                    shadowMapFar: 4000
                }
                DirectionalLight {
                    eulerRotation: Qt.vector3d(-25, 150, 0)
                    color: "#a8bcff"
                    brightness: 0.75
                }
                // đèn trần: khu làm việc, bàn sếp, góc nghỉ
                Repeater3D {
                    model: [[-2.2, 1.4], [2.0, 1.4], [0, -3.2], [5.0, -2.6]]
                    PointLight {
                        required property var modelData
                        position: Qt.vector3d(modelData[0] * 100, 290, modelData[1] * 100)
                        color: "#ffe2c0"
                        brightness: 1.4
                        quadraticFade: 0.6
                    }
                }
                PointLight {    // màn hình sếp hắt sáng khi đang làm
                    position: Qt.vector3d(0, 140, -360)
                    color: app.cLead
                    brightness: app.live ? 0.6 : 0
                    quadraticFade: 4
                }

                // ---------------------------------------------- sàn + thảm
                Box { py: -0.05; sx: 14; sy: 0.1; sz: 10; col: "#3a3f4a"; rough: 0.85 }
                Box { px: -1.2; py: 0.005; pz: 1.4; sx: 9.6; sy: 0.01; sz: 3.0; col: "#323b52"; rough: 1 }
                Box { py: 0.005; pz: -3.6; sx: 4.4; sy: 0.01; sz: 2.8; col: "#56362f"; rough: 1 }
                Box { px: 4.95; py: 0.005; pz: -2.6; sx: 3.9; sy: 0.01; sz: 4.4; col: "#3f3750"; rough: 1 }
                // ---------------------------------------------- tường (xa camera: cao; gần camera: gờ thấp)
                Repeater3D {
                    model: [
                        { x: 0, z: -5.05, w: 14.2, d: 0.1 }, { x: -7.05, z: 0, w: 0.1, d: 10.2 },
                        { x: 7.05, z: 0, w: 0.1, d: 10.2 }, { x: 0, z: 5.05, w: 14.2, d: 0.1 }
                    ]
                    Node {
                        id: wallN
                        required property var modelData
                        required property int index
                        readonly property bool tall: app.wallShown(index)
                        Box { px: wallN.modelData.x; pz: wallN.modelData.z; py: wallN.tall ? 1.5 : 0.09; sx: wallN.modelData.w; sz: wallN.modelData.d; sy: wallN.tall ? 3 : 0.18; col: "#4e5568"; rough: 0.9 }
                        Box { visible: wallN.tall; px: wallN.modelData.x; pz: wallN.modelData.z; py: 0.07; sx: wallN.modelData.w + 0.02; sz: wallN.modelData.d + 0.02; sy: 0.14; col: "#262a33" }
                    }
                }

                // cửa sổ + biển tên + đồng hồ (tường sau)
                Node {
                    visible: app.wallShown(0)
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
                                text: "CLAUDE · HQ"
                                color: app.cLead
                                font { family: app.mono; pixelSize: 44; bold: true; letterSpacing: 8 }
                            }
                        }
                    }
                    // đồng hồ treo tường
                    Node {
                        position: Qt.vector3d(-150, 245, -497)
                        Box { sx: 0.46; sy: 0.04; sz: 0.46; shape: "#Cylinder"; eulerRotation.x: 90; col: "#ececf0"; rough: 0.4 }
                        Repeater3D {
                            model: {
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

                // cửa ra vào (tường trái)
                Node {
                    visible: app.wallShown(1)
                    Box { px: -6.99; py: 1.1; pz: 3.5; sx: 0.02; sy: 2.2; sz: 1.16; col: "#1c1e24" }
                    Box { px: -6.95; py: 1.1; pz: 2.9; sx: 0.1; sy: 2.2; sz: 0.12; col: app.mWood }
                    Box { px: -6.95; py: 1.1; pz: 4.1; sx: 0.1; sy: 2.2; sz: 0.12; col: app.mWood }
                    Box { px: -6.95; py: 2.24; pz: 3.5; sx: 0.1; sy: 0.12; sz: 1.32; col: app.mWood }
                    Box { px: -6.5; py: 0.008; pz: 3.5; sx: 0.9; sy: 0.012; sz: 1.1; col: "#5a463c" }
                    Box { px: -6.9; py: 1.1; pz: 3.92; sx: 0.06; sy: 0.06; sz: 0.06; shape: "#Sphere"; col: "#d0b070"; metal: 1; rough: 0.25 }
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
                        // robot đang ngồi đúng chỗ này (để bật màn hình)
                        readonly property var occ: {
                            if (index === 0) return app.roleAct.haiku ? app.nodeMap["role-haiku"] ?? null : null;
                            for (const id in app.seatOf) if (app.seatOf[id] === index) {
                                const a = app.actors[id];
                                if (a && Math.hypot(a.x - modelData.x, a.z - modelData.z) < 0.6) return app.nodeMap[id] ?? null;
                            }
                            return null;
                        }
                        readonly property real zf: app.podZ + modelData.side * 0.22
                        Box { px: seatN.modelData.x; py: 1.09; pz: seatN.zf; sx: 0.66; sy: 0.4; sz: 0.05; col: app.mDark; rough: 0.4; metal: 0.3 }
                        Box { px: seatN.modelData.x; py: 0.84; pz: app.podZ + seatN.modelData.side * 0.12; sx: 0.06; sy: 0.12; sz: 0.06; col: app.mMetal }
                        Box { px: seatN.modelData.x; py: 0.8; pz: app.podZ + seatN.modelData.side * 0.42; sx: 0.4; sy: 0.024; sz: 0.14; col: "#3a3e48" }
                        Box { px: seatN.modelData.x + 0.32; py: 0.8; pz: app.podZ + seatN.modelData.side * 0.42; sx: 0.07; sy: 0.03; sz: 0.1; col: "#3a3e48" }
                        Panel3D {
                            px: seatN.modelData.x; py: 1.09; pz: seatN.zf + seatN.modelData.side * 0.027; w: 0.6; h: 0.34
                            eulerRotation.y: seatN.modelData.side > 0 ? 0 : 180
                            bright: seatN.occ ? 1.6 : 1
                            src: CodeScreen { node: seatN.occ; sd: seatN.index * 3.7 }
                        }
                    }
                }

                // ---------------------------------------------- bàn sếp
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
                            bright: app.live ? 1.5 : 1
                            src: CodeScreen { node: app.roleAct.opus ? app.nodeMap["role-opus"] ?? null : null; sd: monN.modelData * 9 + 40 }
                        }
                    }
                }
                Box { px: 0.9; py: 1.04; pz: -2.95; sx: 0.1; sy: 0.12; sz: 0.1; shape: "#Cylinder"; col: "#f0f0f4"; rough: 0.2 }

                // bàn điều phối (Sonnet): cạnh bàn sếp, 2 màn hình
                Box { px: -3.6; py: 0.95; pz: -3.3; sx: 1.9; sy: 0.08; sz: 1.0; col: "#8a6a58"; rough: 0.5 }
                Box { px: -4.5; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
                Box { px: -2.7; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
                Box { px: -3.6; py: 0.5; pz: -2.84; sx: 1.7; sy: 0.8; sz: 0.05; col: "#6e5446" }
                Box { px: -3.6; py: 0.6; pz: -4.3; sx: 0.8; sy: 0.04; sz: 0.8; shape: "#Cylinder"; col: "#3a2c34"; rough: 0.8 }
                Repeater3D {
                    model: [-0.42, 0.42]
                    Node {
                        id: orN
                        required property var modelData
                        position: Qt.vector3d(-360 + modelData * 100, 130, -320)
                        eulerRotation.y: modelData * 30
                        Box { sx: 0.66; sy: 0.42; sz: 0.05; col: app.mDark; rough: 0.4; metal: 0.3 }
                        Box { py: -0.26; sx: 0.06; sy: 0.12; sz: 0.06; col: app.mMetal }
                        Panel3D {
                            pz: -0.027; w: 0.6; h: 0.36
                            eulerRotation.y: 180
                            bright: app.roleAct.sonnet ? 1.5 : 1
                            src: CodeScreen { node: app.roleAct.sonnet ? app.nodeMap["role-sonnet"] ?? null : null; sd: orN.modelData * 7 + 90 }
                        }
                    }
                }

                // bàn điều phối Jev (đối xứng bàn Sonnet): 2 màn hình
                Box { px: 3.0; py: 0.95; pz: -3.3; sx: 1.5; sy: 0.08; sz: 1.0; col: "#8a7a4a"; rough: 0.5 }
                Box { px: 2.3; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
                Box { px: 3.7; py: 0.46; pz: -3.3; sx: 0.1; sy: 0.92; sz: 0.92; col: app.mDark }
                Box { px: 3.0; py: 0.5; pz: -2.84; sx: 1.35; sy: 0.8; sz: 0.05; col: "#6e6446" }
                Box { px: 3.0; py: 0.6; pz: -4.3; sx: 0.8; sy: 0.04; sz: 0.8; shape: "#Cylinder"; col: "#3a3624"; rough: 0.8 }
                Repeater3D {
                    model: [-0.42, 0.42]
                    Node {
                        id: jvN
                        required property var modelData
                        position: Qt.vector3d(300 + modelData * 90, 130, -320)
                        eulerRotation.y: modelData * 30
                        Box { sx: 0.66; sy: 0.42; sz: 0.05; col: app.mDark; rough: 0.4; metal: 0.3 }
                        Box { py: -0.26; sx: 0.06; sy: 0.12; sz: 0.06; col: app.mMetal }
                        Panel3D {
                            pz: -0.027; w: 0.6; h: 0.36
                            eulerRotation.y: 180
                            bright: app.roleAct.jev ? 1.5 : 1
                            src: CodeScreen { node: app.roleAct.jev ? app.nodeMap["role-jev"] ?? null : null; sd: jvN.modelData * 5 + 130 }
                        }
                    }
                }

                // ---------------------------------------------- bảng trắng (advisor)
                Node {
                    Box { px: app.board[0]; py: 1.45; pz: app.board[1]; sx: 0.06; sy: 1.24; sz: 2.0; col: "#eceef2"; rough: 0.3 }
                    Box { px: app.board[0]; py: 1.45; pz: app.board[1]; sx: 0.05; sy: 1.3; sz: 2.06; col: app.mMetal; metal: 0.6; rough: 0.35 }
                    Box { px: app.board[0]; py: 0.42; pz: app.board[1] - 0.9; sx: 0.06; sy: 0.84; sz: 0.06; col: app.mMetal }
                    Box { px: app.board[0]; py: 0.42; pz: app.board[1] + 0.9; sx: 0.06; sy: 0.84; sz: 0.06; col: app.mMetal }
                    Box { px: app.board[0] + 0.08; py: 0.83; pz: app.board[1]; sx: 0.12; sy: 0.024; sz: 1.8; col: app.mMetal }
                    Panel3D {
                        px: app.board[0] + 0.032; py: 1.45; pz: app.board[1]; w: 1.94; h: 1.18
                        eulerRotation.y: 90
                        src: Rectangle {
                            id: wb
                            width: 420; height: 256
                            color: "#f4f5f8"
                            readonly property var lines: app.s?.advisor?.last ?? []
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
                                    visible: app.advisorRunning
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
                        readonly property int tick: Math.floor(app.t * (app.live ? 8 : 1.5))
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
                                        color: app.rnd(parent.index * 3.1 + rack.tick) > (app.live ? 0.35 : 0.8) ? (parent.index % 5 ? app.cOk : app.cWait) : "#203028"
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
                Box { px: 6.04; py: 1.0; pz: -4.5; sx: 0.012; sy: 0.08; sz: 0.12; col: "black"; glow: app.live ? app.cWait : "#5a4628"; glowK: 0.5 }

                // ---------------------------------------------- cây xanh
                Repeater3D {
                    model: [[-6.5, -4.5, 1.2], [6.5, 4.5, 1], [-6.5, 4.6, 0.8], [3.0, -4.6, 0.9]]
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

                // ---------------------------------------------- robot
                Repeater3D {
                    model: robotModel
                    Robot {}
                }

                // ---------------------------------------------- gói tin
                Repeater3D {
                    model: app.packets
                    Box {
                        required property var modelData
                        readonly property var a: app.actors[modelData.id] ?? null
                        readonly property var hub: app.stations[app.leadFam].desk
                        readonly property real spd: 0.35 + Math.min(1, (app.nodeMap[modelData.id]?.d?.tools ?? 0) / 40) * 0.5
                        readonly property real u0: (app.t * spd + modelData.k / 2 + (modelData.dir < 0 ? 0.25 : 0)) % 1
                        readonly property real u: modelData.dir > 0 ? u0 : 1 - u0
                        visible: !!a && !a.moving
                        px: a ? hub[0] + (a.x - hub[0]) * u : 0
                        py: 1.55 - 0.2 * u + Math.sin(Math.PI * u) * 1.4
                        pz: a ? hub[1] + (a.z - hub[1]) * u : 0
                        sx: 0.08; sy: 0.08; sz: 0.08
                        eulerRotation: Qt.vector3d(app.t * 120, app.t * 90, 0)
                        col: "black"
                        glow: modelData.dir > 0 ? app.roles[app.leadFam].col : (app.nodeMap[modelData.id]?.col ?? app.cSwarm)
                        glowK: 0.5
                        castsShadows: false
                    }
                }
            }

            // ---------------------------------------------------------- nhãn trên đầu robot
            Repeater {
                model: robotModel
                Item {
                    id: lab
                    required property string rid
                    readonly property var nd: app.nodeMap[rid] ?? null
                    readonly property var a: app.actors[rid] ?? null
                    readonly property vector3d sp: (app.yaw, app.pitch, app.dist, view.width, view.height, a
                        ? view.mapFrom3DScene(Qt.vector3d(a.x * 100, (nd?.sc ?? 1) * 172, a.z * 100))
                        : Qt.vector3d(0, 0, -1))
                    visible: !!nd && !!a && sp.z > 0
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
                                    const m = lab.nd, d = m?.d;
                                    if (!m) return "";
                                    if (m.kind === "role") {
                                        if (m.lead && app.s) {
                                            if (app.running > 0) return `📋 giao việc cho ${app.running} agent`;
                                            return app.s.busy ? `⌨ đang làm · ${app.s.tools ?? 0}⚒` : `☕ rảnh · turn ${app.s.turns ?? 0}`;
                                        }
                                        const mv = app.actors[m.id]?.moving ?? false;
                        if (m.fam === "jev") {
                            if (app.patrolLabel) return mv ? `🚶 đi kiểm tra ${app.patrolLabel}` : `🔍 giám sát ${app.patrolLabel}`;
                            return app.jev ? `▸ ${app.jev.worker} · ${app.ago(app.jev.at)}` : "☕ chờ việc để giám sát";
                        }
                        if (app.roleAct[m.fam]) return "⌨ đang làm";
                        return mv ? "🚶 đi dạo" : "💤 ngủ";
                                    }
                                    if (m.kind === "sub") return `${app.cap(d.model)} · ${d.tools}⚒${d.tool ? " · " + d.tool : ""}`;
                                    if (m.kind === "advisor") return d.status === "running" ? "✎ đang tư vấn…" : `${app.s?.advisor?.calls ?? 0} lần tư vấn`;
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
                onPressed: m => { lx = m.x; ly = m.y; root.forceActiveFocus(); }
                onPositionChanged: m => {
                    if (pressed) {
                        app.yaw -= (m.x - lx) * 0.007;
                        app.pitch = Math.max(0.12, Math.min(1.4, app.pitch + (m.y - ly) * 0.005));
                        lx = m.x; ly = m.y;
                        return;
                    }
                    // chọn robot dưới chuột (đi ngược lên cây node tìm robotId)
                    let o = view.pick(m.x, m.y).objectHit;
                    while (o && o.robotId === undefined) o = o.parent;
                    app.hovered = o ? o.robotId : "";
                    tip.mx = m.x; tip.my = m.y;
                }
                onExited: app.hovered = ""
                onWheel: w => app.dist = Math.max(9, Math.min(30, app.dist * (w.angleDelta.y > 0 ? 0.92 : 1.08)))
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
                        T { text: "CLAUDE AGENT OFFICE"; font.bold: true; font.letterSpacing: 1.5 }
                    }
                    T { text: app.s ? "📁 " + app.base(app.s.cwd) : "chưa có phiên — 3 vai đang chờ việc"; color: app.muted }
                    T {
                        visible: !!app.s
                        text: app.cap(app.s?.model) + "  effort " + app.effortBlocks(app.s?.effort) + " " + (app.s?.effort || "—")
                        color: app.cLead
                    }
                    T {
                        visible: !!app.jev && app.jev.worker !== "none"
                        color: app.cAdv
                        text: app.jev ? `Jev ▸ ${app.jev.worker} → ${app.jev.reviewer === "none" ? "không review" : app.jev.reviewer} · ${app.ago(app.jev.at)}` : ""
                    }
                    T {
                        visible: !!app.s
                        text: `phase ${app.phase} · ${app.running} đang làm · ${app.swarm.length - app.running} xong`
                    }
                    T {
                        visible: !!app.s
                        color: app.muted
                        text: `lead tools ${app.s?.tools ?? 0} · swarm tools ${app.swarm.reduce((n, x) => n + x.tools, 0)}`
                    }
                }
            }

            Column {
                anchors { top: parent.top; right: parent.right; margins: 14 }
                spacing: 5
                Repeater {
                    model: app.sessionList
                    Panel {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool sel: modelData.id === app.sid
                        readonly property bool busy: modelData.busy || Object.values(modelData.subs ?? {}).some(x => x.status === "running")
                        anchors.right: parent.right
                        width: row.implicitWidth + 18; height: 26
                        border.color: sel ? Qt.alpha(app.cLead, 0.8) : Qt.rgba(1, 1, 1, 0.08)
                        Row {
                            id: row
                            anchors.centerIn: parent
                            spacing: 6
                            T { text: (chip.index + 1) + ""; color: app.muted }
                            T { text: chip.busy ? "●" : "○"; color: chip.busy ? app.cOk : app.muted }
                            T { text: app.base(chip.modelData.cwd) }
                            T { text: app.ago(chip.modelData.at); color: app.muted }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.pinned = chip.sel && app.pinned ? "" : chip.modelData.id
                        }
                    }
                }
                T {
                    anchors.right: parent.right
                    text: app.pinned ? "📌 đã ghim · 0 = theo phiên mới" : "tự theo phiên mới nhất"
                    color: app.muted; font.pixelSize: 10
                }
            }

            Panel {
                visible: !!app.s?.repeatError
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 14 }
                width: Math.min(parent.width * 0.5, errT.implicitWidth + 24); height: 30
                border.color: Qt.alpha(app.cErr, 0.8)
                T {
                    id: errT
                    anchors.centerIn: parent
                    width: parent.width - 24
                    elide: Text.ElideRight
                    text: "⚠ cùng lỗi ×2 · " + (app.s?.repeatError ?? "")
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
                            { c: app.cLead, t: "kiểm tra (Opus)" }, { c: app.cOrch, t: "thực hiện (Sonnet)" }, { c: app.cJev, t: "Jev điều phối" }, { c: app.cWorker, t: "việc dễ (Haiku)" }, { c: app.cSwarm, t: "subagent" }, { c: app.cFork, t: "fork" },
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
                text: "kéo: xoay · cuộn: zoom · R: đặt lại · Space: " + (app.spin ? "dừng xoay" : "tự xoay")
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
                            if (n.kind === "role" && n.lead && app.s) return [
                                "vai " + app.roles[n.fam].title.toLowerCase() + " · phiên chính · " + app.base(app.s.cwd),
                                "effort " + (app.s.effort || "—") + " · turn " + (app.s.turns ?? 0),
                                (app.s.busy ? "◐ đang làm việc" : "○ rảnh") + " · " + (app.s.tools ?? 0) + " tool calls"
                            ];
                            if (n.kind === "role") return [
                                "vai " + app.roles[n.fam].title.toLowerCase() + " · model " + app.roles[n.fam].name,
                                app.roleAct[n.fam] ? "◐ đang làm việc" : "○ chờ việc"
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
