import QtQuick
import QtQuick.Layouts
import QtQuick3D
import QtQuick3D.Helpers
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Claude Agent HQ: tòa nhà văn phòng 3D (QtQuick3D, Qt6) để quản lý các agent của Claude Code.
//   Mỗi DỰ ÁN (cwd) = một VĂN PHÒNG trên cùng một tầng. Trong văn phòng:
//     bàn làm việc = phiên Claude Code (tối đa 6 phiên mới nhất); robot ngồi ở bàn = phiên đang mở
//       đèn ăng-ten xanh = đang làm · cam + "!" = chờ bạn duyệt quyền (bị chặn) · xanh dương = rảnh · ghế trống = offline
//     robot xanh nhỏ đứng trước bảng = subagent đang chạy
//     bảng Kanban trên tường = việc Chờ làm / Đang chạy / Bị chặn / Xong (todo, task, subagent, yêu cầu)
//     TV trên tường = token đã dùng + chi phí + biểu đồ 14 ngày; tủ server ở góc cao theo log(token)
//   Panel bên phải: toàn cảnh (tổng token, hàng việc cần chú ý, danh sách văn phòng) hoặc chi tiết một văn phòng
//     (token theo loại / model / ngày, và các tab Yêu cầu · Task · Agent · Phiên, lọc theo trạng thái, click để xem chi tiết).
// Dữ liệu: scan.py (cùng thư mục) đọc thẳng ~/.claude/projects/*/*.jsonl, chạy --watch và đẩy JSON qua stdout.
// Điều khiển: kéo = xoay · cuộn = zoom · click văn phòng / phím 1..9 = vào · 0 / Esc = toàn cảnh · Space = tự xoay
//             Tab = ẩn/hiện panel · G = chất lượng (Tiết kiệm / Cân bằng / Cao, có lưu lại) · Q = thoát
// Hiệu năng: cảnh chỉ vẽ lại khi cần. Animation chỉ chạy khi cửa sổ đang focus và đang xem một văn phòng có agent đang làm;
//   toàn cảnh / không focus / agent rảnh thì đứng yên. Dữ liệu mới được gộp (2 s khi focus, 8 s khi không).
//   Khi xem một văn phòng: các văn phòng xa không vẽ, văn phòng bên cạnh chỉ vẽ vỏ.
// IPC: qs -p …/shell.qml ipc call agenthq status|focus <0..n>|shot /đường/dẫn.png|close
ShellRoot {
    id: app

    // ------------------------------------------------------------------ màu & chữ
    readonly property color bg: "#060912"
    readonly property color fg: "#d9dce3"
    readonly property color muted: "#8b98ad"
    readonly property color dim: "#5b677c"
    readonly property color card: "#171a21"
    readonly property color line: Qt.rgba(1, 1, 1, 0.07)
    readonly property color cClaude: "#d97757"
    readonly property string mono: "CaskaydiaCove Nerd Font Mono"
    readonly property string sans: "Inter"

    readonly property var stCol: ({ running: "#5fd38a", pending: "#e8c548", blocked: "#ff7a45", done: "#6f9bd8", failed: "#e05561", stopped: "#8a8f99" })
    readonly property var stName: ({ running: "Đang chạy", pending: "Chờ làm", blocked: "Bị chặn", done: "Xong", failed: "Lỗi", stopped: "Đã dừng" })
    readonly property var ssCol: ({ working: "#5fd38a", waiting: "#ff7a45", idle: "#6f9bd8", offline: "#5a5f6a" })
    readonly property var ssName: ({ working: "Đang làm", waiting: "Chờ duyệt", idle: "Rảnh", offline: "Offline" })
    readonly property var kindName: ({ request: "YÊU CẦU", command: "LỆNH", todo: "TODO", task: "TASK", agent: "AGENT", permission: "QUYỀN", session: "PHIÊN" })
    readonly property var famCol: ({ opus: "#d97757", sonnet: "#d070a8", haiku: "#45c8d8", fable: "#a092f0" })

    function fam(m) { m = (m ?? "").toLowerCase(); return ["opus", "sonnet", "haiku", "fable"].find(f => m.includes(f)) ?? ""; }
    function modelCol(m) { return famCol[fam(m)] ?? "#8a8f99"; }
    function mixc(a, b, k) { a = Qt.color(a); b = Qt.color(b); return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1); }
    function rnd(x) { const v = Math.sin(x * 12.9898) * 43758.5453; return v - Math.floor(v); }   // giả ngẫu nhiên ổn định
    function hnum(k) { let h = 5381; for (let i = 0; i < k.length; i++) h = ((h * 33) ^ k.charCodeAt(i)) >>> 0; return h; }
    function hueCol(k) { return Qt.hsla((hnum(k ?? "") % 360) / 360, 0.5, 0.55, 1); }

    function fmtTok(n) {
        n = n || 0;
        if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B";
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M";
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K";
        return "" + n;
    }
    function fmtCost(c) { return "$" + (c || 0).toFixed(c >= 100 ? 0 : 2); }
    function ago(ts) {
        if (!ts) return "";
        const d = Math.max(0, now - ts);
        return d < 45 ? "vừa xong" : d < 3600 ? Math.round(d / 60) + " phút trước" : d < 86400 ? Math.round(d / 3600) + " giờ trước" : Math.round(d / 86400) + " ngày trước";
    }
    function dur(s) {
        if (!s || s < 0) return "";
        return s < 60 ? Math.round(s) + "s" : s < 3600 ? Math.floor(s / 60) + "m" + (Math.round(s % 60) ? Math.round(s % 60) + "s" : "") : (s / 3600).toFixed(1) + "h";
    }
    function clock(ts) { return ts ? Qt.formatDateTime(new Date(ts * 1000), "HH:mm dd/MM") : ""; }
    function dayLabel(d) { return d ? d.slice(8, 10) + "/" + d.slice(5, 7) : ""; }

    // ------------------------------------------------------------------ dữ liệu
    property var hq: ({ projects: [], totals: { tokens: {}, counts: {} }, days: [] })
    property bool loaded: false
    property string scanErr: ""
    property var order: []                  // thứ tự văn phòng cố định trong phiên làm việc (không nhảy chỗ khi dự án khác hoạt động)
    readonly property var allProjects: {
        const m = {};
        for (const p of hq.projects ?? []) m[p.key] = p;
        return order.map(k => m[k]).filter(p => p);
    }
    property var hidden: []                 // key các dự án bị ẩn (lưu trong settings.json)
    property bool pickerOn: false
    readonly property var projects: allProjects.filter(p => !hidden.includes(p.key))
    function toggleProject(k) { hidden = hidden.includes(k) ? hidden.filter(x => x !== k) : hidden.concat([k]); }
    function showAll(v) { hidden = v ? [] : allProjects.map(p => p.key); }
    readonly property int n: projects.length
    readonly property string scanPath: decodeURIComponent(Qt.resolvedUrl("scan.py").toString().replace(/^file:\/\//, ""))
    // icon nằm ở <repo>/assets, ngoài thư mục app: Quickshell chặn URL tương đối ra ngoài nên dùng file:// tuyệt đối
    readonly property string iconUrl: "file://" + scanPath.replace(/apps\/agenthq\/scan\.py$/, "assets/claude-agenthq.svg")

    // gộp cập nhật: scan.py có thể đẩy dữ liệu vài giây một lần khi Claude đang làm; chỉ áp dụng bản mới nhất,
    // tối đa mỗi 2 s khi cửa sổ đang focus, mỗi 8 s khi không (mỗi lần áp dụng = parse + dựng lại panel + vẽ lại cảnh)
    property string pending: ""
    function queue(line) {
        if (!line || line[0] !== "{") return;
        pending = line;
        if (!loaded) { applyPending(); return; }
        if (!applyTimer.running) applyTimer.start();
    }
    function applyPending() { const l = pending; pending = ""; if (l) ingest(l); }
    Timer { id: applyTimer; interval: app.winActive ? 2000 : 8000; onTriggered: app.applyPending() }
    // vừa focus lại cửa sổ: áp dụng ngay bản đang chờ
    onWinActiveChanged: if (winActive && pending) { applyTimer.stop(); applyPending(); }
    property var projJson: ({})              // key -> JSON lần trước (so sánh để giữ nguyên object không đổi)
    function ingest(line) {
        if (!line || line[0] !== "{") return;
        try {
            const d = JSON.parse(line);
            const old = {};
            for (const p of hq.projects ?? []) old[p.key] = p;
            const str = {};
            d.projects = (d.projects ?? []).map(p => {
                const js = JSON.stringify(p);
                str[p.key] = js;
                return projJson[p.key] === js && old[p.key] ? old[p.key] : p;
            });
            projJson = str;
            const keys = (d.projects ?? []).map(p => p.key);
            const o = order.filter(k => keys.includes(k));
            for (const k of keys) if (!o.includes(k)) o.push(k);
            if (JSON.stringify(o) !== JSON.stringify(order)) order = o;
            hq = d;
            scanErr = "";
            if (!loaded) { loaded = true; snapOverview(); }
        } catch (e) {
            console.warn("agenthq: JSON lỗi", e);
        }
    }

    Process {
        id: scanner
        running: true
        command: ["python3", "-I", app.scanPath, "--watch"]
        stdout: SplitParser { onRead: data => app.queue(data) }
        stderr: SplitParser { onRead: data => { app.scanErr = data; console.warn("scan.py:", data); } }
        onExited: (code, status) => restart.start()
    }
    Timer { id: restart; interval: 3000; onTriggered: scanner.running = true }

    property real now: Date.now() / 1000
    property real t: 0
    Timer { interval: 1000; running: true; repeat: true; onTriggered: app.now = Date.now() / 1000 }
    // chất lượng đồ hoạ (phím G): 0 Tiết kiệm · 1 Cân bằng (mặc định) · 2 Cao. Đặt sẵn: AGENTHQ_QUALITY=0|1|2
    property int quality: { const v = parseInt(Quickshell.env("AGENTHQ_QUALITY") ?? ""); return isNaN(v) ? 1 : Math.max(0, Math.min(2, v)); }
    readonly property var qualityName: ["Tiết kiệm", "Cân bằng", "Cao"]
    // lưu lựa chọn chất lượng giữa các lần mở (~/.cache/claude-agenthq/settings.json); biến môi trường vẫn được ưu tiên
    FileView {
        id: prefs
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/claude-agenthq/settings.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try { const j = JSON.parse(text()); if (!Quickshell.env("AGENTHQ_QUALITY") && j.quality >= 0 && j.quality <= 2) app.quality = j.quality; if (Array.isArray(j.hidden)) app.hidden = j.hidden; } catch (e) {}
        }
    }
    function savePrefs() { if (loaded) { Quickshell.execDetached(["mkdir", "-p", prefs.path.replace(/\/[^\/]*$/, "")]); prefs.setText(JSON.stringify({ quality: quality, hidden: hidden })); } }
    onQualityChanged: savePrefs()
    onHiddenChanged: savePrefs()
    // cửa sổ đang được focus (Hyprland): không focus thì đứng hình, chỉ vẽ lại khi dữ liệu đổi
    readonly property bool winActive: ToplevelManager.activeToplevel?.title === win.title
    // animation chỉ chạy khi: tự xoay, hoặc cửa sổ đang focus + đang xem trong một văn phòng có agent đang làm / chờ duyệt
    // (agent rảnh thì đứng yên: không vẽ lại khung hình nào cho tới khi dữ liệu đổi)
    readonly property bool animOn: win.visible && (spin || (winActive && (interior ? sel >= 0 && (selP?.state === "working" || selP?.state === "waiting") : nWorking > 0)))
    Timer {
        // đồng hồ animation: Tiết kiệm 10 fps · Cân bằng 15 fps · Cao 30 fps; toàn cảnh đứng yên
        interval: [100, 67, 33][app.quality]
        running: app.animOn
        repeat: true
        onTriggered: { app.t += interval / 1000; if (app.spin) app.yaw += interval / 1000 * 0.08; }
    }

    // ------------------------------------------------------------------ bố cục tầng văn phòng
    readonly property real ow: 10           // rộng văn phòng (m)
    readonly property real od: 8            // sâu văn phòng (m)
    readonly property real pitchX: 12.5
    readonly property real pitchZ: 11
    readonly property int cols: Math.max(1, Math.min(4, Math.ceil(Math.sqrt(n))))
    readonly property int rows: Math.max(1, Math.ceil(n / cols))
    // interior = false: cảnh "chòm sao" (bệ lục giác quanh quả cầu điều phối); true: văn phòng nội thất (phím I)
    property bool interior: false
    readonly property real islPitch: 27
    function islRing(i) { let k = 1; while (i >= 3 * k * (k + 1)) k++; return k; }
    readonly property int rings: n > 0 ? islRing(n - 1) : 1
    function islandAng(i) {
        const k = islRing(i), start = 3 * k * (k - 1), cnt = Math.min(6 * k, n - start);
        return Math.PI / 4 + k * 0.35 + (i - start) / cnt * Math.PI * 2;
    }
    function islandX(i) { return Math.cos(islandAng(i)) * islPitch * islRing(i); }
    function islandZ(i) { return Math.sin(islandAng(i)) * islPitch * islRing(i); }
    function cellX(i) { return interior ? ((i % cols) - (cols - 1) / 2) * pitchX : islandX(i); }
    function cellZ(i) { return interior ? (Math.floor(i / cols) - (rows - 1) / 2) * pitchZ : islandZ(i); }
    readonly property real focusDist: interior ? 16 : 26
    // 6 bàn (phiên) trong mỗi văn phòng: [x, z] cục bộ
    readonly property var deskSlots: [[-3.0, 0.1], [0, 0.1], [3.0, 0.1], [-3.0, 2.5], [0, 2.5], [3.0, 2.5]]

    // ------------------------------------------------------------------ chọn & camera
    property string selKey: ""
    readonly property int sel: selKey === "" ? -1 : projects.findIndex(p => p.key === selKey)
    readonly property var selP: sel >= 0 ? projects[sel] : null
    property int hoverOffice: -1
    property string hoverInfo: ""
    property string hlSession: ""           // phiên đang được chọn (robot có vòng sáng, thẻ trong panel viền trắng)
    // click robot / thẻ phiên: vào văn phòng của nó và đánh dấu phiên
    function pickSession(pi, sid) {
        if (pi >= 0 && pi !== sel) flyOffice(pi);
        hlSession = sid;
    }
    property bool spin: false
    property bool panelOn: true

    property real lookX: 0
    property real lookZ: 0
    property real yaw: 0.0
    property real pitch: 0.78
    property real dist: 40
    readonly property real yawDeg: yaw * 180 / Math.PI

    ParallelAnimation {
        id: fly
        NumberAnimation { id: flyX; target: app; property: "lookX"; duration: 800; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyZ; target: app; property: "lookZ"; duration: 800; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyD; target: app; property: "dist"; duration: 800; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyP; target: app; property: "pitch"; duration: 800; easing.type: Easing.InOutCubic }
    }
    function flyTo(x, z, d, p) {
        fly.stop();
        flyX.to = x; flyZ.to = z; flyD.to = d; flyP.to = p;
        fly.start();
    }
    function overview() {
        if (!interior) { const R = islPitch * (n > 1 ? rings : 0) + 14; return { x: 0, z: 0, d: Math.max(60, R * 2.35) }; }
        const w = cols * pitchX, dd = rows * pitchZ;
        // panel bên phải che ~1/3 khung: dời tâm nhìn sang phải một chút
        const d = Math.max(w * 1.2, dd * 1.75) + 8;
        return { x: panelOn ? d * 0.02 : 0, z: dd * 0.06, d: panelOn ? d * 1.18 : d };
    }
    function flyOverview() { selKey = ""; hlSession = ""; const o = overview(); flyTo(o.x, o.z, o.d, 0.85); }
    function snapOverview() { fly.stop(); const o = overview(); lookX = o.x; lookZ = o.z; dist = o.d; pitch = 0.85; }
    function flyOffice(i) {
        if (i < 0 || i >= n) return;
        selKey = projects[i].key;
        app.tab = "requests"; app.filter = "all"; app.expanded = ""; app.limit = 60;
        flyTo(cellX(i) + (panelOn ? 0.4 : 0), cellZ(i) + 0.3, focusDist, 0.8);
    }
    onInteriorChanged: if (loaded) { if (sel >= 0) flyOffice(sel); else snapOverview(); }
    onNChanged: if (loaded) { if (sel >= 0) flyTo(cellX(sel) + (panelOn ? 0.4 : 0), cellZ(sel) + 0.3, focusDist, 0.8); else flyOverview(); }
    onPanelOnChanged: if (sel >= 0) flyTo(cellX(sel) + (panelOn ? 0.4 : 0), cellZ(sel) + 0.3, dist, pitch); else flyOverview()

    // ------------------------------------------------------------------ trạng thái panel
    property string tab: "requests"         // requests | tasks | agents | sessions
    property string filter: "all"           // all | running | pending | blocked | done | fail
    property string expanded: ""
    property int limit: 60
    function match(it) {
        if (filter === "all") return true;
        if (filter === "fail") return it.status === "failed" || it.status === "stopped";
        return it.status === filter;
    }
    function tabItems(p, tb) {
        if (!p) return [];
        if (tb === "requests") return p.requests ?? [];
        if (tb === "tasks") return p.tasks ?? [];
        if (tb === "agents") return p.agents ?? [];
        return (p.sessions ?? []).map(s => Object.assign({ kind: "session", status: s.state === "working" ? "running" : s.state === "waiting" ? "blocked" : s.state === "idle" ? "pending" : "done" }, s));
    }
    function countBy(list) {
        const c = { running: 0, pending: 0, blocked: 0, done: 0, failed: 0, stopped: 0 };
        for (const it of list) c[it.status] = (c[it.status] ?? 0) + 1;
        return c;
    }
    // mọi việc của một dự án (yêu cầu + task + agent), mới nhất trước
    function allItems(p) {
        if (!p) return [];
        return (p.tasks ?? []).concat(p.agents ?? [], p.requests ?? []).sort((a, b) => (b.ts ?? 0) - (a.ts ?? 0));
    }
    // việc cần chú ý trên toàn tầng: bị chặn > đang chạy > chờ làm
    readonly property var attention: {
        const out = [];
        const rank = { blocked: 0, running: 1, pending: 2 };
        projects.forEach((p, i) => {
            for (const it of allItems(p))
                if (rank[it.status] !== undefined) out.push(Object.assign({ pi: i, pname: p.name }, it));
        });
        return out.sort((a, b) => rank[a.status] - rank[b.status] || (b.ts ?? 0) - (a.ts ?? 0)).slice(0, 40);
    }
    // tool -> động từ tiếng Việt + màu nhóm
    function verbOf(t) {
        if (!t) return "";
        if (t.startsWith("mcp__claude-in-chrome")) return "Trình duyệt";
        if (t.startsWith("mcp__")) return t.split("__")[1] ?? "MCP";
        return ({ Bash: "Chạy lệnh", PowerShell: "Chạy lệnh", bash: "Chạy lệnh", Read: "Đọc", Edit: "Sửa", MultiEdit: "Sửa", Write: "Viết",
                  NotebookEdit: "Sửa notebook", Grep: "Tìm", Glob: "Tìm file", WebFetch: "Đọc web", WebSearch: "Tìm web",
                  Agent: "Giao việc", Task: "Giao việc", TodoWrite: "Todo", TaskCreate: "Tạo task", TaskUpdate: "Cập nhật task",
                  AskUserQuestion: "Hỏi bạn", Skill: "Skill", ToolSearch: "Tìm tool", Monitor: "Theo dõi", TaskStop: "Dừng task" })[t] ?? t;
    }
    function verbCol(t) {
        if (!t) return muted;
        if (["Edit", "MultiEdit", "Write", "NotebookEdit"].includes(t)) return "#5fd38a";
        if (["Read", "Grep", "Glob", "ToolSearch"].includes(t)) return "#6f9bd8";
        if (["Bash", "PowerShell", "bash", "Monitor"].includes(t)) return "#e8c548";
        if (["Agent", "Task"].includes(t)) return "#6ea0f0";
        if (t === "AskUserQuestion") return "#ff7a45";
        if (t.startsWith("Web") || t.startsWith("mcp__")) return "#b08cf0";
        return "#9aa3b5";
    }
    // mọi phiên đang mở trên toàn tầng: chờ duyệt > đang làm > rảnh
    readonly property var liveList: {
        const out = [];
        projects.forEach((p, i) => { for (const s of p.sessions ?? []) if (s.live) out.push({ s, p, pi: i }); });
        const r = { waiting: 0, working: 1, idle: 2, offline: 3 };
        return out.sort((a, b) => r[a.s.state] - r[b.s.state] || b.s.mtime - a.s.mtime);
    }
    readonly property int nWorking: liveList.filter(x => x.s.state !== "idle").length
    // nhóm tool (khối quanh quả cầu điều phối): sáng khi có agent đang dùng
    readonly property var toolGroups: [["Bash", ["Bash", "PowerShell", "bash", "Monitor"]], ["Edit", ["Edit", "MultiEdit", "Write", "NotebookEdit"]], ["Read", ["Read"]],
        ["Search", ["Grep", "Glob", "ToolSearch"]], ["Web", ["WebFetch", "WebSearch"]], ["Agent", ["Agent", "Task"]], ["Todo", ["TodoWrite", "TaskCreate", "TaskUpdate"]], ["MCP", ["mcp__"]]]
    readonly property var activeTools: {
        const out = [];
        for (const x of liveList) {
            const t = x.s.doing?.tool;
            if (!t || x.s.state === "idle") continue;
            for (const g of toolGroups) if (g[1].some(n => n === "mcp__" ? t.startsWith("mcp__") : n === t) && !out.includes(g[0])) out.push(g[0]);
        }
        return out;
    }
    // subagent -> vai trò: review / test / dev (đoán theo loại + tiêu đề)
    readonly property var roles: [["dev", "Dev", "#22d3ee"], ["test", "Test", "#facc15"], ["review", "Review", "#a78bfa"]]
    function roleOf(a) {
        const t = ((a.type ?? "") + " " + (a.title ?? "")).toLowerCase();
        if (/review|audit|critic|security|code-review|lint/.test(t)) return "review";
        if (/test|qa|verif|spec|e2e|kiểm thử|kiểm tra/.test(t)) return "test";
        if (/explore|plan\b|web-fetch|fetch|search|research|guide|statusline|tìm|nghiên cứu/.test(t)) return "other";   // không thuộc dev/test/review
        return "dev";
    }
    function roleStats(p) {
        const r = { dev: { run: 0, all: 0, last: "", doing: "", blocked: false }, test: { run: 0, all: 0, last: "", doing: "", blocked: false }, review: { run: 0, all: 0, last: "", doing: "", blocked: false }, other: { run: 0, all: 0, last: "", doing: "", blocked: false } };
        const sst = {};
        for (const s of p?.sessions ?? []) sst[s.id] = s.state;
        for (const a of p?.agents ?? []) {
            const x = r[roleOf(a)];
            x.all++;
            if (a.status === "running") {
                x.run++;
                if (!x.last) { x.last = a.title; x.doing = a.doing ? verbOf(a.doing.tool) + ": " + a.doing.text : a.title; }
                if (sst[a.session] === "waiting") x.blocked = true;
            }
        }
        return r;
    }
    readonly property var waitList: liveList.filter(x => x.s.state === "waiting")

    // danh sách agent (cột trái): đang chọn văn phòng thì mọi phiên của nó, không thì các phiên đang mở
    property string agFilter: "all"
    readonly property var agentScope: selP ? (selP.sessions ?? []).slice(0, 14).map(s => ({ s, p: selP, pi: sel })) : liveList
    readonly property var agentRows: agentScope.filter(x => agFilter === "all" || x.s.state === agFilter)
    function agentCount(f) { return f === "all" ? agentScope.length : agentScope.filter(x => x.s.state === f).length; }
    readonly property real agMaxTok: Math.max(1, ...agentScope.map(x => x.s.tokens?.total ?? 0))
    // token (cột trái dưới): theo văn phòng đang chọn hoặc toàn tầng
    readonly property var tokScope: selP ? selP.tokens : hq.totals?.tokens
    readonly property real costScope: selP ? selP.cost : (hq.totals?.cost ?? 0)
    readonly property var modelsScope: {
        const m = {};
        for (const p of selP ? [selP] : projects) for (const [k, v] of Object.entries(p.models ?? {})) m[k] = (m[k] ?? 0) + v;
        return Object.entries(m).sort((a, b) => b[1] - a[1]);
    }
    readonly property real modelsSum: Math.max(1, modelsScope.reduce((a, m) => a + m[1], 0))
    readonly property var daysScope: {
        const out = [];
        for (let i = 0; i < 14; i++) {
            let t = 0, day = "";
            for (const p of selP ? [selP] : projects) { const d = p.daily?.[i]; if (d) { t += d.total; day = d.day; } }
            out.push({ total: t, day });
        }
        return out;
    }
    readonly property real daysMax: Math.max(1, ...daysScope.map(d => d.total))
    // nhật ký: hành động gần nhất của các phiên (đang mở, hoặc cả văn phòng đang chọn)
    readonly property var logEntries: {
        const out = [];
        for (const x of agentScope)
            for (const a of (x.s.activity ?? []).slice(0, 8))
                out.push({ ts: a.ts, tool: a.tool, text: a.text, st: a.st, who: x.s.title || x.p.name, pkey: x.p.key });
        return out.sort((a, b) => b.ts - a.ts).slice(0, 6);
    }
    function metaOf(it) {
        const a = [];
        if (it.kind === "session") {
            a.push(ssName[it.state] ?? it.state);
            if (it.model) a.push(it.model);
            a.push(fmtTok(it.tokens?.total) + " tok");
            if (it.requests) a.push(it.requests + " yêu cầu");
            if (it.agents) a.push(it.agents + " agent");
            a.push(ago(it.mtime));
            return a.join(" · ");
        }
        a.push(stName[it.status] ?? it.status);
        if (it.ts) a.push(ago(it.ts));
        if (it.tokens) a.push(fmtTok(it.tokens) + " tok");
        const d = it.dur || (it.end && it.ts ? it.end - it.ts : 0);
        if (d) a.push(dur(d));
        if (it.nTools) a.push(it.nTools + " tool");
        if (it.kind === "agent") { a.push(it.type); if (it.model) a.push(it.model); if (it.bg) a.push("nền"); }
        if (it.blockedBy?.length) a.push("chờ " + it.blockedBy.join(", "));
        return a.join(" · ");
    }

    IpcHandler {
        target: "agenthq"
        function close(): void { Qt.quit(); }
        function shot(path: string): void { root.grabToImage(r => r.saveToFile(path)); }
        function focus(i: int): void { if (i >= 1) app.flyOffice(i - 1); else app.flyOverview(); }
        function tab(name: string): void { app.tab = name; }
        function zoom(d: real): void { app.dist = d; }
        function interior(v: bool): void { app.interior = v; }
        function quality(q: int): void { app.quality = Math.max(0, Math.min(2, q)); }
        function status(): string {
            return JSON.stringify({ loaded: app.loaded, selected: app.sel, quality: app.quality, winActive: app.winActive, animOn: app.animOn, offices: app.projects.map((p, i) => ({ index: i + 1, name: p.name, state: p.state,
                tokens: p.tokens.total, counts: p.counts, sessions: p.sessions.length })), totals: app.hq.totals, err: app.scanErr });
        }
    }

    // ------------------------------------------------------------------ thành phần 3D
    // hộp / cầu / trụ: tâm (px, py, pz), kích thước (sx, sy, sz) tính bằng mét (1 m = 100 đơn vị)
    component Box: Model {
        property real px
        property real py
        property real pz
        property real sx: 1
        property real sy: 1
        property real sz: 1
        property color col: "#808080"
        property real alpha: 1
        property real rough: 0.75
        property real metal: 0
        property real clear: 0
        property color glow: "black"
        property real glowK: 0
        property string shape: "#Cube"
        source: shape
        position: Qt.vector3d(px * 100, py * 100, pz * 100)
        scale: Qt.vector3d(sx, sy, sz)
        // vật nhỏ (sách, cốc, mắt robot…) không đổ bóng: bớt một lượt vẽ trong shadow pass
        castsShadows: alpha >= 1 && Math.max(sx, sy, sz) > 0.3
        materials: PrincipledMaterial {
            baseColor: Qt.rgba(col.r, col.g, col.b, alpha)
            alphaMode: alpha < 1 ? PrincipledMaterial.Blend : PrincipledMaterial.Opaque
            roughness: rough
            metalness: metal
            clearcoatAmount: clear
            clearcoatRoughnessAmount: 0.12
            emissiveFactor: Qt.vector3d(glow.r * glowK, glow.g * glowK, glow.b * glowK)
        }
    }
    // mặt phẳng hiển thị một Item 2D (bảng, TV, nhãn). Pháp tuyến +z.
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

    // robot agent kiểu chibi, mặt nhìn về +z (phía camera): vỏ trắng bóng, mũ / tai / đai / găng màu model,
    // kính mặt tối với mắt phát sáng theo trạng thái. mode: working | waiting | idle
    //   working: chồm tới gõ phím, đầu cúi, mắt nhìn xuống · waiting: giơ tay vẫy, đầu nghiêng, mắt tròn to · idle: ngả lưng, mắt nhắm
    component Bot: Node {
        id: bot
        property color body: app.cClaude
        property color status: app.ssCol.working
        property string mode: "working"
        property real k: 1
        property real seed: 0
        property string botInfo: ""
        property string sessId: ""
        property bool seated: true
        property bool hl: false
        scale: Qt.vector3d(k, k, k)
        readonly property real tt: app.t + seed
        readonly property bool work: mode === "working"
        readonly property bool wait: mode === "waiting"
        readonly property bool idle: mode === "idle"
        readonly property real bob: idle ? Math.sin(tt * 1.4) * 0.02 : wait ? Math.abs(Math.sin(tt * 3.2)) * 0.04 : Math.sin(tt * 7) * 0.006
        readonly property real blink: Math.sin(tt * 0.9) > 0.985 ? 0.12 : 1
        readonly property color shell: "#f4f3ef"
        readonly property color eyeCol: app.mixc(status, "#ffffff", 0.3)
        // chân ngắn + bàn chân (khi đứng)
        Repeater3D {
            model: [-1, 1]
            delegate: Node {
                required property int modelData
                visible: !bot.seated
                Box { px: modelData * 0.12; py: 0.13; sx: 0.15; sy: 0.26; sz: 0.15; shape: "#Cylinder"; col: bot.body; rough: 0.4 }
                Box { px: modelData * 0.12; py: 0.04; pz: 0.04; sx: 0.2; sy: 0.09; sz: 0.27; shape: "#Sphere"; col: bot.body; rough: 0.4 }
            }
        }
        Node {
            y: ((bot.seated ? 0 : 0.12) + bot.bob) * 100
            eulerRotation.x: bot.idle ? -10 : bot.work ? 6 : 0
            eulerRotation.z: bot.work ? Math.sin(bot.tt * 1.3) * 3 : 0
            // thân: vỏ trắng + đai màu model + màn hình ngực
            Box { py: 0.64; sx: 0.5; sy: 0.54; sz: 0.44; shape: "#Sphere"; col: bot.shell; rough: 0.3; clear: 0.7; pickable: true }
            Box { py: 0.56; sx: 0.515; sy: 0.07; sz: 0.455; shape: "#Cylinder"; col: bot.body; rough: 0.35 }
            Box { py: 0.71; pz: 0.19; sx: 0.17; sy: 0.11; sz: 0.05; col: "#101216"; rough: 0.1 }
            Box { py: 0.71; pz: 0.217; sx: 0.12; sy: 0.06; sz: 0.005; col: "black"; glow: bot.status; glowK: 1.6; castsShadows: false }
            // đầu to (chibi)
            Node {
                y: 1.13 * 100
                eulerRotation.x: bot.work ? 9 : bot.idle ? -8 : 0
                eulerRotation.z: bot.wait ? Math.sin(bot.tt * 4) * 7 : 0
                Box { sx: 0.76; sy: 0.6; sz: 0.62; shape: "#Sphere"; col: bot.shell; rough: 0.28; clear: 0.8; pickable: true }
                Box { py: 0.19; sx: 0.52; sy: 0.24; sz: 0.48; shape: "#Sphere"; col: bot.body; rough: 0.35; clear: 0.4 }
                Box { py: -0.01; pz: 0.19; sx: 0.58; sy: 0.38; sz: 0.27; shape: "#Sphere"; col: "#0d0f13"; rough: 0.06; metal: 0.2; clear: 1 }
                Repeater3D {
                    model: [-1, 1]
                    delegate: Node {
                        required property int modelData
                        // mắt
                        Box {
                            px: modelData * 0.12; py: bot.work ? -0.035 : 0; pz: 0.33
                            sx: bot.wait ? 0.11 : 0.085; sy: (bot.idle ? 0.02 : bot.wait ? 0.12 : 0.1) * bot.blink; sz: 0.02
                            shape: "#Sphere"; col: "black"; glow: bot.eyeCol; glowK: 2.4; castsShadows: false
                        }
                        // má hồng
                        Box { px: modelData * 0.25; py: -0.1; pz: 0.265; sx: 0.09; sy: 0.05; sz: 0.03; shape: "#Sphere"; col: "#ff8fa3"; glow: "#ff8fa3"; glowK: 0.2; rough: 0.6; castsShadows: false }
                        // tai nghe
                        Box { px: modelData * 0.385; sx: 0.2; sy: 0.07; sz: 0.2; shape: "#Cylinder"; eulerRotation.z: 90; col: bot.body; rough: 0.35 }
                    }
                }
                // ăng-ten + đèn trạng thái
                Box { py: 0.4; sx: 0.025; sy: 0.16; sz: 0.025; shape: "#Cylinder"; col: "#8a8f99"; metal: 0.5; rough: 0.3 }
                Box {
                    py: 0.5; sx: 0.12; sy: 0.12; sz: 0.12; shape: "#Sphere"; col: "black"; castsShadows: false
                    glow: bot.status; glowK: bot.wait ? 1.3 + Math.sin(bot.tt * 7) * 0.9 : bot.work ? 1.6 : 0.6
                }
            }
            // tay (khớp vai): gõ phím / giơ tay vẫy khi chờ duyệt / buông khi rảnh
            Repeater3D {
                model: [-1, 1]
                delegate: Node {
                    required property int modelData
                    x: modelData * 0.3 * 100; y: 0.76 * 100
                    eulerRotation.z: modelData * (bot.wait && modelData > 0 ? 8 : 18)
                    eulerRotation.x: bot.work ? -70 + Math.sin(bot.tt * 15 + modelData * 1.7) * 10
                                   : bot.wait && modelData > 0 ? -160 + Math.sin(bot.tt * 6) * 14
                                   : bot.idle ? 8 : -15
                    Box { py: -0.13; sx: 0.1; sy: 0.26; sz: 0.1; shape: "#Cylinder"; col: bot.shell; rough: 0.3; clear: 0.5 }
                    Box { py: -0.29; sx: 0.14; sy: 0.14; sz: 0.14; shape: "#Sphere"; col: bot.body; rough: 0.4 }
                }
            }
        }
        // vòng sáng dưới chân khi được chọn từ panel
        Box {
            visible: bot.hl
            py: 0.03; sx: 1.4; sy: 0.01; sz: 1.4; shape: "#Cylinder"; col: "black"; castsShadows: false
            glow: "white"; glowK: 0.7 + Math.sin(bot.tt * 4) * 0.3
        }
    }

    // bong bóng thoại (billboard): [NHÃN] nội dung
    component Bubble: Panel3D {
        id: bb
        property string text
        property string tag
        property color accent: app.ssCol.working
        property real kk: 1
        w: 2.4 * kk; h: 0.52 * kk; bright: 1.25
        eulerRotation.y: app.yawDeg
        src: Item {
            width: 480; height: 104
            Rectangle { x: 44; y: 66; width: 30; height: 30; rotation: 45; color: "#f6f5f1"; border.color: bb.accent; border.width: 4 }
            Rectangle {
                width: 480; height: 80; radius: 20; color: "#f6f5f1"; border.color: bb.accent; border.width: 4
                Row {
                    x: 14; spacing: 10; anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: tagT.implicitWidth + 18; height: 44; radius: 10; color: bb.accent
                        Text { id: tagT; anchors.centerIn: parent; text: bb.tag; color: "#111318"; font { family: app.sans; pixelSize: 22; bold: true } }
                    }
                    Text {
                        width: 480 - tagT.implicitWidth - 60; anchors.verticalCenter: parent.verticalCenter
                        text: bb.text; elide: Text.ElideRight; color: "#1b1d22"; font { family: app.sans; pixelSize: 25 }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ cảnh "chòm sao" kiểu AgentOps 3D
    // trời sao + lưới nền, quả cầu điều phối ở giữa (vòng quỹ đạo + khối công cụ), mỗi dự án = một bệ lục giác có hub, robot = phiên đang mở
    component Galaxy: Node {
        id: gx
        visible: !app.interior
        readonly property real k: Math.max(1, Math.min(4.5, app.dist / 32))
        readonly property var gpos: Qt.vector3d(0, 3.2, 0)
        Component { id: entryC; InstanceListEntry {} }
        InstanceList { id: starsL }
        InstanceList { id: gridL }
        InstanceList { id: linkL }
        InstanceList { id: ringL }
        function fill(list, arr) {
            list.instances = arr.map(a => entryC.createObject(list, { position: a.p, scale: a.s, color: a.c ?? "white" }));
        }
        function bez(a, b, c, t) { const u = 1 - t; return [u * u * a[0] + 2 * u * t * b[0] + t * t * c[0], u * u * a[1] + 2 * u * t * b[1] + t * t * c[1], u * u * a[2] + 2 * u * t * b[2] + t * t * c[2]]; }
        function build() {
            // sao
            const st = [];
            for (let i = 0; i < 700; i++) {
                const r = 160 + app.rnd(i * 3.1) * 220, th = app.rnd(i * 5.7) * Math.PI * 2, ph = Math.acos(-0.15 + app.rnd(i * 7.3) * 1.15);
                st.push({ p: Qt.vector3d(r * Math.sin(ph) * Math.cos(th) * 100, (r * Math.cos(ph) - 5) * 100, r * Math.sin(ph) * Math.sin(th) * 100),
                          s: Qt.vector3d(1, 1, 1).times(0.7 + app.rnd(i * 1.3) * 1.5) });
            }
            fill(starsL, st);
            // lưới nền
            const g = [], E = 220, S = 5;
            for (let v = -E; v <= E; v += S) {
                const c = Math.abs(v) % 25 === 0 ? Qt.rgba(0.11, 0.23, 0.39, 0.55) : Qt.rgba(0.055, 0.1, 0.18, 0.5);
                g.push({ p: Qt.vector3d(0, -300, v * 100), s: Qt.vector3d(E * 2, 0.02, 0.12), c });
                g.push({ p: Qt.vector3d(v * 100, -300, 0), s: Qt.vector3d(0.12, 0.02, E * 2), c });
            }
            fill(gridL, g);
            // đường nối cong điều phối -> hub từng dự án
            const lk = [];
            for (let i = 0; i < app.n; i++) {
                const hx = app.islandX(i), hz = app.islandZ(i), col = app.hueCol(app.projects[i].key);
                const c = Qt.rgba(col.r, col.g, col.b, 0.55);
                const a = [0, 3.2, 0], b = [hx / 2, 3.2 / 2 + 2.1 / 2 + 7 + Math.hypot(hx, hz) * 0.12, hz / 2], e = [hx, 2.1, hz];
                const N = Math.max(30, Math.round(Math.hypot(hx, hz) * 1.6));
                for (let j = 0; j <= N; j++) { const q = bez(a, b, e, j / N); lk.push({ p: Qt.vector3d(q[0] * 100, q[1] * 100, q[2] * 100), s: Qt.vector3d(0.14, 0.14, 0.14), c }); }
            }
            fill(linkL, lk);
            // vòng quỹ đạo (đơn vị 1m, dùng chung cho nhiều vòng)
            const rg = [];
            for (let j = 0; j < 72; j++) { const a = j / 72 * Math.PI * 2; rg.push({ p: Qt.vector3d(Math.cos(a) * 100, 0, Math.sin(a) * 100), s: Qt.vector3d(0.07, 0.07, 0.07) }); }
            fill(ringL, rg);
        }
        readonly property string sig: app.projects.map(p => p.key).join("|")
        onSigChanged: Qt.callLater(build)
        Component.onCompleted: build()

        // sao + lưới + đường nối (instancing: mỗi loại 1 draw call)
        Model { source: "#Sphere"; instancing: starsL; castsShadows: false; receivesShadows: false; materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; baseColor: "#9fb4d6" } }
        Model { source: "#Cube"; instancing: gridL; castsShadows: false; receivesShadows: false; materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; baseColor: "white"; alphaMode: PrincipledMaterial.Blend } }
        Model { source: "#Sphere"; instancing: linkL; castsShadows: false; receivesShadows: false; materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; baseColor: "white"; alphaMode: PrincipledMaterial.Blend } }

        // ---- trung tâm điều phối
        Node {
            id: hubC
            Box { py: -0.25; sx: 21; sy: 0.25; sz: 21; shape: "#Cylinder"; col: "#0c1424"; rough: 0.8; metal: 0.05; pickable: true }
            Box { py: -0.32; sx: 21.6; sy: 0.2; sz: 21.6; shape: "#Cylinder"; col: "black"; glow: "#38bdf8"; glowK: 0.9; castsShadows: false }
            // tủ công cụ: mỗi khối = một nhóm tool, sáng khi có agent đang dùng
            Repeater3D {
                model: app.toolGroups
                delegate: Node {
                    id: tg
                    required property var modelData
                    required property int index
                    readonly property real ang: index / app.toolGroups.length * Math.PI * 2
                    readonly property bool act: app.activeTools.includes(modelData[0])
                    x: Math.cos(ang) * 760; z: Math.sin(ang) * 760
                    Box { py: 0.9; sx: 0.9; sy: 0.9; sz: 0.9; col: "#1e293b"; metal: 0.4; rough: 0.5; glow: app.verbCol(tg.modelData[1][0]); glowK: tg.act ? 1.1 + Math.sin(app.t * 6 + tg.index) * 0.3 : 0.08; eulerRotation.y: tg.act ? app.t * 40 : 0 }
                    Panel3D {
                        py: 1.9; w: 2.6 * gx.k * 0.55; h: 0.6 * gx.k * 0.55
                        eulerRotation.y: app.yawDeg
                        src: Item { width: 260; height: 60; Text { anchors.centerIn: parent; text: tg.modelData[0]; color: tg.act ? "white" : "#94a3b8"; font { family: app.mono; pixelSize: 30; bold: tg.act } } }
                    }
                }
            }
            // quả cầu điều phối
            Node {
                y: 320
                Box { sx: 2.3; sy: 2.3; sz: 2.3; shape: "#Sphere"; col: "#9ad8ff"; glow: "#2b8fff"; glowK: 1.2 + (app.nWorking > 0 ? Math.sin(app.t * 3) * 0.3 : 0); rough: 0.25; castsShadows: false; pickable: true }
                Box { sx: 4.1; sy: 4.1; sz: 4.1; shape: "#Sphere"; col: "#7dd3fc"; alpha: 0.12; castsShadows: false }
                Node { eulerRotation.x: 70; eulerRotation.y: app.t * 25; scale: Qt.vector3d(2.9, 2.9, 2.9); Model { source: "#Sphere"; instancing: ringL; castsShadows: false; materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; baseColor: "#22d3ee" } } }
                Node { eulerRotation.x: 66; eulerRotation.z: 35; eulerRotation.y: -app.t * 18; scale: Qt.vector3d(3.35, 3.35, 3.35); Model { source: "#Sphere"; instancing: ringL; castsShadows: false; materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; baseColor: "#a78bfa" } } }
            }
            Box { py: 1.6; sx: 0.4; sy: 1.6; sz: 0.4; shape: "#Cylinder"; col: "black"; alpha: 0.4; glow: "#38bdf8"; glowK: 0.6; castsShadows: false }
            Panel3D {
                py: -1.1; pz: 0
                w: 7 * gx.k * 0.85; h: 1.1 * gx.k * 0.85
                eulerRotation.y: app.yawDeg
                src: Item {
                    width: 700; height: 110
                    Text { anchors.centerIn: parent; text: "ĐIỀU PHỐI · " + app.nWorking + "/" + app.liveList.length + " AGENT"; color: "#bae6fd"; font { family: app.sans; pixelSize: 44; bold: true; letterSpacing: 4 } }
                }
            }
        }

        // ---- mỗi dự án = một đảo lục giác
        Repeater3D {
            model: app.n
            delegate: Node {
                id: isl
                required property int index
                readonly property int officeId: index
                readonly property var p: app.projects[index] ?? null
                readonly property bool focused: app.sel === index
                readonly property bool hover: app.hoverOffice === index
                readonly property color tint: app.hueCol(p?.key)
                readonly property string pstate: p?.state ?? "offline"
                readonly property bool active: pstate === "working" || pstate === "waiting"
                readonly property var live: (p?.sessions ?? []).filter(s => s.live).slice(0, 6)
                readonly property var rstats: app.roleStats(p)
                x: app.islandX(index) * 100; z: app.islandZ(index) * 100

                Repeater3D {
                    model: [0, 60, 120]
                    delegate: Box { required property int modelData; py: -0.25; sx: 7.8; sy: 0.25; sz: 13.5; eulerRotation.y: modelData; col: "#0c1424"; rough: 0.8; metal: 0.05; pickable: true }
                }
                Repeater3D {
                    model: 6
                    delegate: Box {
                        required property int index
                        readonly property real th: 30 + index * 60
                        px: Math.cos(th * Math.PI / 180) * 6.75; pz: Math.sin(th * Math.PI / 180) * 6.75
                        py: 0.02; sx: 7.8; sy: 0.03; sz: 0.14; eulerRotation.y: -(th + 90)
                        col: "black"; glow: isl.focused || isl.hover ? "white" : isl.pstate === "waiting" ? app.ssCol.waiting : isl.tint
                        glowK: isl.focused ? 1.8 : isl.hover ? 1.3 : isl.active ? 1.0 + Math.sin(app.t * (isl.pstate === "waiting" ? 6 : 2.5)) * 0.35 : 0.55
                        castsShadows: false
                    }
                }
                Box { py: 0.01; sx: 11.2; sy: 0.005; sz: 11.2; shape: "#Cylinder"; col: "black"; glow: isl.tint; glowK: 0.06; castsShadows: false }
                // hub dự án
                Node {
                    y: 210
                    Box { sx: 1.1; sy: 1.1; sz: 1.1; shape: "#Sphere"; col: isl.tint; glow: isl.tint; glowK: isl.active ? 1.0 + Math.sin(app.t * 3 + isl.index) * 0.3 : 0.5; castsShadows: false; pickable: true }
                    Box { sx: 2.1; sy: 2.1; sz: 2.1; shape: "#Sphere"; col: isl.tint; alpha: 0.16; castsShadows: false }
                    Node { eulerRotation.y: app.t * 30; scale: Qt.vector3d(1.45, 1.45, 1.45); Model { source: "#Sphere"; instancing: ringL; castsShadows: false; materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; baseColor: isl.tint } } }
                }
                Box { py: 1.05; sx: 0.3; sy: 1.05; sz: 0.3; shape: "#Cylinder"; col: "black"; alpha: 0.4; glow: isl.tint; glowK: 0.5; castsShadows: false }
                // 3 trạm subagent: dev / test / review (robot làm việc khi có subagent đang chạy)
                Repeater3D {
                    model: app.roles
                    delegate: Node {
                        id: rs
                        required property var modelData
                        required property int index
                        readonly property var st: isl.rstats[modelData[0]]
                        readonly property real th: (90 + (index - 1) * 42) * Math.PI / 180
                        x: Math.cos(th) * 560; z: Math.sin(th) * 560
                        eulerRotation.y: 0
                        Box { py: 0.03; sx: 1.5; sy: 0.03; sz: 1.5; shape: "#Cylinder"; col: "black"; glow: rs.st.blocked ? app.ssCol.waiting : rs.modelData[2]; glowK: rs.st.run > 0 ? 0.9 + Math.sin(app.t * (rs.st.blocked ? 6 : 3)) * 0.3 : isl.pstate === "offline" ? 0.1 : 0.35; castsShadows: false }
                        Bubble {
                            visible: app.dist < 90 && rs.st.run > 0
                            py: 3.1; kk: Math.max(1.8, gx.k * 0.8)
                            eulerRotation.y: app.yawDeg - rs.eulerRotation.y
                            opacity: rs.st.blocked ? 0.65 + 0.35 * Math.abs(Math.sin(app.t * 5)) : 1
                            accent: rs.st.blocked ? app.ssCol.waiting : rs.modelData[2]
                            tag: rs.st.blocked ? "BỊ CHẶN" : rs.modelData[1].toUpperCase()
                            text: rs.st.doing
                        }
                        Bot {
                            k: 1.0; seated: false
                            body: rs.modelData[2]
                            status: rs.st.blocked ? app.ssCol.waiting : rs.st.run > 0 ? app.ssCol.working : isl.pstate === "offline" ? app.ssCol.offline : app.ssCol.idle
                            mode: rs.st.blocked ? "waiting" : rs.st.run > 0 ? "working" : "idle"
                            seed: rs.index * 2.3 + isl.index
                            botInfo: isl.p.name + " · sub-agent " + rs.modelData[1] + "\n" + rs.st.run + " đang chạy / " + rs.st.all + " tổng" + (rs.st.last ? "\n▸ " + rs.st.last : "")
                                     + (isl.rstats.other.all > 0 ? "\n(+" + isl.rstats.other.all + " sub-agent khác: explore/web/plan)" : "") + (isl.pstate === "offline" ? "\nDự án offline" : "")
                        }
                        Panel3D {
                            py: 2.2; w: 2.4 * Math.max(1, gx.k * 0.5); h: 0.55 * Math.max(1, gx.k * 0.5)
                            visible: app.dist < 90
                            eulerRotation.y: app.yawDeg - rs.eulerRotation.y
                            src: Rectangle {
                                width: 480; height: 110; radius: 20; color: Qt.rgba(0.02, 0.035, 0.07, 0.8)
                                border.width: 3; border.color: rs.modelData[2]
                                Row {
                                    anchors.centerIn: parent; spacing: 14
                                    Text { text: rs.modelData[1].toUpperCase(); color: isl.pstate === "offline" && rs.st.run === 0 ? "#64748b" : rs.modelData[2]; font { family: app.sans; pixelSize: 44; bold: true } }
                                    Text { text: rs.st.run + "/" + rs.st.all; color: "white"; font { family: app.mono; pixelSize: 44; bold: true } }
                                }
                            }
                        }
                    }
                }
                // robot = phiên đang mở, đứng quanh hub
                Repeater3D {
                    model: isl.live
                    delegate: Node {
                        id: gb
                        required property var modelData
                        required property int index
                        readonly property real th: Math.PI + (index + 0.5) / Math.max(1, isl.live.length) * Math.PI
                        readonly property string st: modelData.state
                        x: Math.cos(th) * 300; z: Math.sin(th) * 300
                        eulerRotation.y: Math.atan2(-Math.cos(th), -Math.sin(th)) * 180 / Math.PI
                        Bot {
                            k: 1.5; seated: false
                            body: app.modelCol(gb.modelData.model)
                            status: app.ssCol[gb.st]
                            mode: gb.st === "offline" ? "idle" : gb.st
                            seed: gb.index * 1.7 + isl.index
                            hl: app.hlSession === gb.modelData.id
                            sessId: gb.modelData.id
                            botInfo: isl.p.name + " · " + (app.ssName[gb.st] ?? "") + " · " + gb.modelData.model + "\n" + gb.modelData.title
                                     + (gb.modelData.doing ? "\n▸ " + app.verbOf(gb.modelData.doing.tool) + ": " + gb.modelData.doing.text : "")
                        }
                        // vòng sáng dưới chân: nhấp nháy theo trạng thái (làm = xanh, chờ duyệt/bị chặn = cam)
                        Box {
                            visible: gb.st === "working" || gb.st === "waiting"
                            py: 0.03; sx: 2.2 + Math.sin(app.t * (gb.st === "waiting" ? 6 : 3)) * 0.25; sy: 0.02; sz: 2.2 + Math.sin(app.t * (gb.st === "waiting" ? 6 : 3)) * 0.25
                            shape: "#Cylinder"; col: "black"; glow: app.ssCol[gb.st]; glowK: 0.9; castsShadows: false
                        }
                        // đang làm gì / bị chặn vì gì
                        Bubble {
                            visible: app.dist < 90 && (gb.st === "working" || gb.st === "waiting" || (gb.st === "idle" && app.dist < 40))
                            py: 3.9; kk: Math.max(2.3, gx.k * 0.9)
                            eulerRotation.y: app.yawDeg - gb.eulerRotation.y
                            opacity: gb.st === "waiting" ? 0.65 + 0.35 * Math.abs(Math.sin(app.t * 5)) : 1
                            accent: app.ssCol[gb.st] ?? app.ssCol.idle
                            tag: gb.st === "waiting" ? "BỊ CHẶN" : gb.st === "idle" ? "RẢNH" : app.verbOf(gb.modelData.doing?.tool).toUpperCase()
                            text: gb.st === "waiting" ? "chờ bạn duyệt " + (gb.modelData.doing?.tool ?? "quyền") + (gb.modelData.doing?.text ? " · " + gb.modelData.doing.text : "")
                                  : gb.st === "idle" ? "xong lượt, chờ yêu cầu mới" : (gb.modelData.doing?.text ?? gb.modelData.current ?? "đang xử lý…")
                        }
                        Panel3D {
                            py: 2.9; w: 3.2 * Math.max(1, gx.k * 0.55); h: 0.6 * Math.max(1, gx.k * 0.55)
                            visible: app.dist < 70
                            eulerRotation.y: app.yawDeg - gb.eulerRotation.y
                            src: Rectangle {
                                width: 640; height: 120; radius: 22; color: Qt.rgba(0.02, 0.035, 0.07, 0.78)
                                border.width: 3; border.color: app.hlSession === gb.modelData.id ? "white" : app.ssCol[gb.st]
                                Row {
                                    x: 20; spacing: 12; anchors.verticalCenter: parent.verticalCenter
                                    Rectangle { width: 20; height: 20; radius: 10; color: app.ssCol[gb.st]; anchors.verticalCenter: parent.verticalCenter }
                                    Text { width: 560; elide: Text.ElideRight; text: gb.modelData.title || "(phiên)"; color: "white"; font { family: app.sans; pixelSize: 40; bold: true } anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                    }
                }
                // nhãn dự án
                Panel3D {
                    py: (app.dist < 45 ? 6.6 : 5.4) + 0.9 * gx.k * 0.6; w: 6.4 * gx.k * 0.85; h: 1.35 * gx.k * 0.85; bright: 1.4
                    eulerRotation.y: app.yawDeg
                    src: Rectangle {
                        width: 640; height: 135; radius: 24; color: Qt.rgba(0.02, 0.035, 0.07, 0.8)
                        border.width: 4; border.color: isl.focused || isl.hover ? "white" : isl.pstate === "waiting" ? app.ssCol.waiting : isl.tint
                        Text { x: 24; y: 12; width: 590; elide: Text.ElideRight; text: (isl.index + 1) + "  " + (isl.p?.name ?? ""); color: "white"; font { family: app.sans; pixelSize: 46; bold: true } }
                        Row {
                            x: 24; y: 82; spacing: 18
                            Rectangle { width: 22; height: 22; radius: 11; color: app.ssCol[isl.pstate]; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: (app.ssName[isl.pstate] ?? "") + " · " + isl.live.length + "/" + (isl.p?.sessions?.length ?? 0) + " agent · " + app.fmtTok(isl.p?.tokens?.total); color: "#c9ccd3"; font { family: app.sans; pixelSize: 30 } }
                        }
                    }
                }
            }
        }
    }

    // một văn phòng = một dự án
    component Office: Node {
        id: of
        required property int index
        readonly property int officeId: index
        readonly property var p: app.projects[index] ?? null
        readonly property bool focused: app.sel === index
        // đồ vật nhỏ chỉ dựng cho văn phòng đang xem, hoặc khi zoom gần ở toàn cảnh (giảm số draw call)
        readonly property bool detail: focused || (app.sel < 0 && app.dist < 30)
        // đang xem văn phòng khác: chỉ giữ vỏ (sàn, tường, bảng, TV), bỏ bàn ghế / robot / cây để bớt draw call mỗi khung hình
        readonly property bool lite: app.sel >= 0 && !focused
        readonly property color tint: app.hueCol(p?.key)
        readonly property string pstate: p?.state ?? "offline"
        readonly property bool active: pstate === "working" || pstate === "waiting"
        readonly property var items: app.allItems(p)
        readonly property var board: {
            const o = { pending: [], running: [], blocked: [], done: [] };
            const c = { pending: 0, running: 0, blocked: 0, done: 0 };
            for (const it of items) {
                if (o[it.status] === undefined || it.kind === "command") continue;
                c[it.status]++;
                if (o[it.status].length < 3) o[it.status].push(it);
            }
            return { items: o, counts: c };
        }
        readonly property var runAgents: (p?.agents ?? []).filter(a => a.status === "running")
        readonly property int nLive: (p?.sessions ?? []).filter(s => s.live).length
        // đang xem một văn phòng: các văn phòng ở hàng phía trước (giữa camera và nó) hạ tường xuống để không che
        readonly property bool cut: app.sel >= 0 && app.sel !== index && Math.floor(index / app.cols) > Math.floor(app.sel / app.cols)
        property real wallH: cut ? 0.3 : 2.9
        Behavior on wallH { NumberAnimation { duration: 550; easing.type: Easing.InOutCubic } }
        readonly property real tokK: Math.max(0, Math.min(1, (Math.log10(Math.max(1, p?.tokens?.total ?? 1)) - 5) / 4))
        position: Qt.vector3d(app.cellX(index) * 100, 0, app.cellZ(index) * 100)
        // đang xem một văn phòng: chỉ vẽ nó và các văn phòng sát bên (camera không thấy phần còn lại)
        readonly property int col: index % app.cols
        readonly property int row: Math.floor(index / app.cols)
        visible: app.sel < 0 || (Math.abs(col - app.sel % app.cols) <= 1 && Math.abs(row - Math.floor(app.sel / app.cols)) <= 1)

        // sàn gỗ (texture vẽ bằng Item: các tấm ván so le) + viền sáng khi chọn / rê chuột / đang làm
        Model {
            source: "#Rectangle"
            y: 11.5; eulerRotation.x: -90
            scale: Qt.vector3d(app.ow, app.od, 1)
            pickable: true
            materials: PrincipledMaterial {
                baseColorMap: Texture { sourceItem: woodSrc }
                roughness: 0.5
                clearcoatAmount: 0.25
                clearcoatRoughnessAmount: 0.2
            }
            Item {
                id: woodSrc
                visible: false
                width: 800; height: 640
                Rectangle { anchors.fill: parent; color: "#7d5f45" }
                Repeater {
                    model: 16
                    delegate: Item {
                        id: plankRow
                        required property int index
                        y: index * 40; width: 800; height: 40
                        Repeater {
                            model: 5
                            delegate: Rectangle {
                                required property int index
                                readonly property real off: app.rnd(plankRow.index * 7.31) * 200
                                x: index * 210 - off + 2; width: 206; height: 38; y: 1
                                color: ["#cfa77c", "#c69c71", "#d6b089", "#bf946a", "#caa277"][Math.floor(app.rnd(plankRow.index * 13.7 + index * 3.1) * 5)]
                            }
                        }
                    }
                }
            }
        }
        Box {
            py: 0.01; sx: app.ow + 0.3; sy: 0.02; sz: app.od + 0.3; col: "#1a1c22"; castsShadows: false
            glow: of.tint; glowK: of.focused ? 0.9 : app.hoverOffice === of.index ? 0.45 : of.active ? 0.3 + 0.25 * Math.sin(app.t * 3 + of.index) : 0
        }
        Box { py: 0.06; sx: app.ow; sy: 0.1; sz: app.od; col: "#5b4636"; rough: 0.9; castsShadows: false }

        // tường sau hai tông: ốp chân tường màu dự án + phần trên kem + nẹp trắng + đèn hắt trần
        Box { py: Math.min(1.0, of.wallH) / 2; pz: -app.od / 2; sx: app.ow; sy: Math.min(1.0, of.wallH); sz: 0.18; col: app.mixc(of.tint, "#2a2d33", 0.45); rough: 0.7; pickable: true }
        Box { visible: of.wallH > 1.02; py: (1.0 + of.wallH) / 2; pz: -app.od / 2; sx: app.ow; sy: Math.max(0.01, of.wallH - 1.0); sz: 0.16; col: "#efebe3"; rough: 0.9; pickable: true }
        Box { py: Math.min(1.0, of.wallH); pz: -app.od / 2 + 0.02; sx: app.ow; sy: 0.05; sz: 0.24; col: "#fbfaf7"; rough: 0.5 }
        Box { py: of.wallH + 0.03; pz: -app.od / 2 + 0.02; sx: app.ow; sy: 0.08; sz: 0.22; col: of.tint; rough: 0.45 }
        Box {
            visible: !of.cut
            py: of.wallH - 0.08; pz: -app.od / 2 + 0.13; sx: app.ow - 0.4; sy: 0.04; sz: 0.05; castsShadows: false
            col: "black"; glow: "#ffdcaa"; glowK: of.active || of.focused ? 1.4 : 0.45
        }
        // vách hai bên: chân tường đặc + kính phía trên + khung nhôm
        Repeater3D {
            model: [-1, 1]
            delegate: Node {
                required property int modelData
                readonly property real lowH: Math.min(0.9, of.wallH)
                Box { px: modelData * app.ow / 2; py: parent.lowH / 2; sx: 0.12; sy: parent.lowH; sz: app.od; col: "#ebe6dc"; rough: 0.85; pickable: true }
                Box { px: modelData * app.ow / 2; py: parent.lowH; sx: 0.16; sy: 0.04; sz: app.od; col: "#fbfaf7"; rough: 0.5 }
                Box { visible: of.wallH > 0.95; px: modelData * app.ow / 2; py: (0.9 + of.wallH) / 2; sx: 0.04; sy: Math.max(0.01, of.wallH - 0.9); sz: app.od; col: "#b8d6f0"; alpha: 0.12; rough: 0.05 }
                Box { px: modelData * app.ow / 2; py: of.wallH; sx: 0.09; sy: 0.08; sz: app.od; col: "#4a505c"; metal: 0.7; rough: 0.3 }
                Repeater3D {
                    model: [-2, 0, 2, 4]
                    delegate: Box {
                        required property real modelData
                        px: parent.modelData * app.ow / 2; py: of.wallH / 2; pz: modelData; sx: 0.07; sy: of.wallH; sz: 0.07
                        col: "#4a505c"; metal: 0.7; rough: 0.3
                    }
                }
            }
        }

        // kệ sách (vách trái) + góc cà phê (vách phải): chỉ dựng khi nhìn gần cho nhẹ GPU
        Node {
            visible: of.detail && !of.cut
            x: (-app.ow / 2 + 0.3) * 100; z: -1.45 * 100
            Box { py: 0.95; pz: -0.85; sx: 0.36; sy: 1.9; sz: 0.05; col: "#e9e4da" }
            Box { py: 0.95; pz: 0.85; sx: 0.36; sy: 1.9; sz: 0.05; col: "#e9e4da" }
            Box { py: 0.95; px: -0.16; sx: 0.04; sy: 1.9; sz: 1.75; col: "#ddd7cb" }
            Repeater3D {
                model: [0.08, 0.55, 1.02, 1.49, 1.9]
                delegate: Box { required property real modelData; py: modelData; sx: 0.36; sy: 0.04; sz: 1.75; col: "#e9e4da" }
            }
            Repeater3D {
                model: 24
                delegate: Box {
                    required property int index
                    readonly property int shelf: Math.floor(index / 6)
                    readonly property real r: app.rnd(index * 3.7 + of.index * 11.1)
                    visible: shelf < 3 || r > 0.4
                    readonly property real hh: 0.26 + r * 0.12
                    px: 0.02; py: [0.1, 0.57, 1.04, 1.51][shelf] + hh / 2; pz: -0.7 + (index % 6) * 0.27 + r * 0.05
                    sx: 0.24; sy: hh; sz: 0.07 + r * 0.05
                    eulerRotation.x: index % 6 === 5 ? -14 : 0
                    col: ["#c0504d", "#4f81bd", "#9bbb59", "#8064a2", "#f79646", "#e8c548", "#3f7f86", "#d9d4c7"][Math.floor(app.rnd(index * 9.13 + of.index) * 8)]
                    rough: 0.7
                }
            }
        }
        Node {
            visible: of.detail && !of.cut
            x: (app.ow / 2 - 0.36) * 100; z: -1.45 * 100
            Box { py: 0.45; sx: 0.6; sy: 0.9; sz: 1.4; col: "#f1eee8"; rough: 0.6 }
            Box { py: 0.92; sx: 0.64; sy: 0.04; sz: 1.44; col: "#c49a6c"; rough: 0.5 }
            Box { py: 1.12; pz: -0.35; sx: 0.36; sy: 0.36; sz: 0.32; col: "#25272d"; metal: 0.4; rough: 0.35 }
            Box { py: 1.18; px: -0.181; pz: -0.35; sx: 0.01; sy: 0.06; sz: 0.06; shape: "#Sphere"; col: "black"; glow: of.active ? "#ff9b54" : "#4a4f59"; glowK: 1.2; castsShadows: false }
            Box { py: 0.99; pz: 0.15; sx: 0.1; sy: 0.12; sz: 0.1; shape: "#Cylinder"; col: "white" }
            Box { py: 0.99; pz: 0.35; sx: 0.1; sy: 0.12; sz: 0.1; shape: "#Cylinder"; col: of.tint }
        }

        // ---- bảng Kanban trên tường sau
        Panel3D {
            visible: !of.cut
            px: -2.25; py: 1.62; pz: -app.od / 2 + 0.09; w: 4.6; h: 2.1; bright: 1.05
            src: Rectangle {
                width: 920; height: 420; radius: 10; color: "#f3f1ea"; border.color: "#8d8f96"; border.width: 8
                Row {
                    x: 18; y: 16; spacing: 12
                    Repeater {
                        model: ["pending", "running", "blocked", "done"]
                        delegate: Column {
                            id: colK
                            required property string modelData
                            width: 210; spacing: 8
                            Rectangle {
                                width: 210; height: 40; radius: 6; color: app.stCol[colK.modelData]
                                Text {
                                    anchors.centerIn: parent
                                    text: app.stName[colK.modelData].toUpperCase() + "  " + (of.board.counts[colK.modelData] ?? 0)
                                    color: "#14161b"; font { family: app.sans; pixelSize: 21; bold: true }
                                }
                            }
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    required property int index
                                    readonly property var it: of.board.items[colK.modelData][index] ?? null
                                    visible: it !== null
                                    width: 210; height: 104; radius: 4
                                    color: app.mixc(app.stCol[colK.modelData], "#ffffff", 0.62)
                                    rotation: (index % 2 ? 1.2 : -1)
                                    Text {
                                        anchors { fill: parent; margins: 9 }
                                        text: parent.it ? parent.it.title : ""
                                        wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                        color: "#22242a"; font { family: app.sans; pixelSize: 19 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- TV token trên tường sau
        Box { visible: !of.cut; px: 2.55; py: 1.65; pz: -app.od / 2 + 0.1; sx: 3.9; sy: 2.2; sz: 0.07; col: "#0d0e11"; rough: 0.3 }
        Panel3D {
            visible: !of.cut
            px: 2.55; py: 1.65; pz: -app.od / 2 + 0.14; w: 3.75; h: 2.05; bright: 1.25
            src: Rectangle {
                width: 750; height: 410; color: "#0f1218"
                Column {
                    x: 26; y: 18; spacing: 4; width: 700
                    Text { text: "TOKEN · " + (of.p?.name ?? ""); color: "#8f96a3"; font { family: app.sans; pixelSize: 22; bold: true; letterSpacing: 2 } width: 700; elide: Text.ElideRight }
                    Row {
                        spacing: 18
                        Text { text: app.fmtTok(of.p?.tokens?.total); color: "white"; font { family: app.sans; pixelSize: 86; bold: true } }
                        Column {
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                            Text { text: app.fmtCost(of.p?.cost) ; color: "#e8c548"; font { family: app.sans; pixelSize: 34; bold: true } }
                            Text { text: "out " + app.fmtTok(of.p?.tokens?.out) + " · cache " + app.fmtTok(of.p?.tokens?.cacheRead); color: "#8f96a3"; font { family: app.sans; pixelSize: 20 } }
                        }
                    }
                    Item { width: 1; height: 8 }
                    Row {
                        id: bars
                        spacing: 6; height: 150
                        readonly property real mx: Math.max(1, ...(of.p?.daily ?? []).map(d => d.total))
                        Repeater {
                            model: of.p?.daily ?? []
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                anchors.bottom: parent.bottom
                                width: 44; radius: 3
                                height: Math.max(3, 150 * modelData.total / bars.mx)
                                color: index === (of.p?.daily.length ?? 0) - 1 ? "#5fd38a" : app.mixc(of.tint, "#ffffff", 0.15)
                                opacity: modelData.total > 0 ? 1 : 0.25
                            }
                        }
                    }
                    Text { text: "14 ngày gần nhất · hôm nay " + app.fmtTok((of.p?.daily ?? []).slice(-1)[0]?.total); color: "#8f96a3"; font { family: app.sans; pixelSize: 20 } }
                }
            }
        }

        // ---- tủ server ở góc: cao theo log(token), đèn nháy khi đang làm
        Node {
            x: (app.ow / 2 - 0.65) * 100; z: (-app.od / 2 + 0.75) * 100
            readonly property real hh: Math.min(of.wallH, 0.5 + 2.0 * of.tokK)
            Box { py: parent.hh / 2; sx: 0.7; sy: parent.hh; sz: 0.7; col: "#23262d"; metal: 0.4; rough: 0.4; pickable: true }
            Box {
                py: parent.hh / 2; pz: 0.355; sx: 0.08; sy: parent.hh * 0.9; sz: 0.02; col: "black"; castsShadows: false
                glow: app.ssCol[of.pstate]; glowK: of.active ? 1.0 + Math.sin(app.t * 8 + of.index) * 0.6 : 0.35
            }
            Box {
                px: 0.18; py: parent.hh / 2; pz: 0.355; sx: 0.04; sy: parent.hh * 0.9; sz: 0.02; col: "black"; castsShadows: false
                glow: of.tint; glowK: 0.5
            }
        }

        // ---- thảm tròn dưới khu bàn, cây cảnh hai góc trong
        Box { py: 0.122; pz: 1.3; sx: 8.0; sy: 0.012; sz: 4.8; shape: "#Cylinder"; col: app.mixc(of.tint, "#3a3e47", 0.5); rough: 1; castsShadows: false }
        Box { py: 0.128; pz: 1.3; sx: 7.4; sy: 0.012; sz: 4.3; shape: "#Cylinder"; col: app.mixc(of.tint, "#6e6a63", 0.5); rough: 1; castsShadows: false }
        Repeater3D {
            model: of.lite ? [] : [[-app.ow / 2 + 0.6, -app.od / 2 + 0.6, 1.0], [app.ow / 2 - 0.6, 1.0, 0.85]]
            delegate: Node {
                required property var modelData
                x: modelData[0] * 100; z: modelData[1] * 100
                scale: Qt.vector3d(modelData[2], modelData[2], modelData[2])
                Box { py: 0.28; sx: 0.5; sy: 0.56; sz: 0.5; shape: "#Cylinder"; col: "#e8e2d6"; rough: 0.6 }
                Box { py: 0.57; sx: 0.46; sy: 0.03; sz: 0.46; shape: "#Cylinder"; col: "#4a3628" }
                Box { py: 0.95; sx: 0.8; sy: 0.8; sz: 0.8; shape: "#Sphere"; col: "#4f9a56"; rough: 0.8 }
                Box { py: 1.3; px: 0.12; pz: 0.05; sx: 0.55; sy: 0.6; sz: 0.55; shape: "#Sphere"; col: "#62b268"; rough: 0.8 }
                Box { py: 1.15; px: -0.2; pz: 0.15; sx: 0.45; sy: 0.45; sz: 0.45; shape: "#Sphere"; col: "#57a65e"; rough: 0.8 }
            }
        }

        // ---- bồn cây phía trước (hai bên lối vào) mang biển tên + biển trạng thái; thảm chùi chân ở cửa
        Repeater3D {
            model: [-1, 1]
            delegate: Node {
                id: pl
                required property int modelData
                x: modelData * (app.ow / 2 - 1.65) * 100; z: (app.od / 2 - 0.26) * 100
                Box { py: 0.32; sx: 3.1; sy: 0.64; sz: 0.5; col: "#3b3f47"; rough: 0.55; pickable: true }
                Box { py: 0.65; sx: 3.16; sy: 0.04; sz: 0.56; col: "#5a5f6b"; rough: 0.4 }
                Box { py: 0.64; sx: 3.0; sy: 0.03; sz: 0.42; col: "#4a3628" }
                Repeater3D {
                    model: of.lite ? 0 : 5
                    delegate: Box {
                        required property int index
                        readonly property real r: app.rnd(index * 5.3 + pl.modelData * 2.2 + of.index)
                        px: -1.2 + index * 0.6 + (r - 0.5) * 0.15; py: 0.78 + r * 0.06; sx: 0.5 + r * 0.25; sy: 0.42 + r * 0.2; sz: 0.42
                        shape: "#Sphere"; col: ["#4f9a56", "#5aa860", "#468c4d"][index % 3]; rough: 0.85
                    }
                }
                Repeater3D {
                    model: of.detail ? 6 : 0
                    delegate: Box {
                        required property int index
                        readonly property real r: app.rnd(index * 2.9 + pl.modelData * 7.7 + of.index)
                        px: -1.35 + index * 0.52; py: 0.98 + r * 0.08; pz: (r - 0.5) * 0.2; sx: 0.08; sy: 0.08; sz: 0.08
                        shape: "#Sphere"; col: ["#ffd166", "#ef476f", "#ffffff", "#f78c6b"][index % 4]; rough: 0.6
                    }
                }
            }
        }
        Box { py: 0.12; pz: app.od / 2 - 0.25; sx: 1.3; sy: 0.012; sz: 0.6; col: app.mixc(of.tint, "#22252b", 0.6); rough: 1; castsShadows: false }
        Panel3D {
            px: -(app.ow / 2 - 1.65); py: 0.33; pz: app.od / 2 + 0.003; w: 2.9; h: 0.5; bright: 1.2
            src: Rectangle {
                width: 580; height: 100; radius: 10; color: "#16181d"
                Rectangle { width: 14; height: parent.height; radius: 7; color: of.tint }
                Text {
                    x: 30; width: 530; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                    text: (of.index + 1) + "  " + (of.p?.name ?? ""); color: "white"; font { family: app.sans; pixelSize: 48; bold: true }
                }
            }
        }
        Panel3D {
            px: app.ow / 2 - 1.65; py: 0.33; pz: app.od / 2 + 0.003; w: 2.9; h: 0.5; bright: 1.2
            src: Rectangle {
                width: 580; height: 100; radius: 10; color: "#16181d"
                Row {
                    x: 24; spacing: 16; anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: 30; height: 30; radius: 15; color: app.ssCol[of.pstate]; anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: (app.ssName[of.pstate] ?? "") + " · " + of.nLive + "/" + (of.p?.sessions?.length ?? 0) + " agent" + (of.runAgents.length ? " · " + of.runAgents.length + " sub" : "")
                        color: "white"; font { family: app.sans; pixelSize: 40 }
                    }
                }
            }
        }

        // ---- bàn làm việc = phiên; robot ngồi ghế xoay sau laptop, mặt nhìn ra phía trước
        Repeater3D {
            model: of.lite ? 0 : 6
            delegate: Node {
                id: desk
                required property int index
                readonly property var s: of.p?.sessions?.[index] ?? null
                readonly property string st: s?.state ?? "offline"
                readonly property bool on: s !== null && st !== "offline"
                readonly property bool hl: s !== null && app.hlSession === s.id
                readonly property color fabric: app.mixc(of.tint, "#2b2e35", 0.68)
                visible: s !== null
                x: app.deskSlots[index][0] * 100; z: app.deskSlots[index][1] * 100
                // bàn gỗ sồi chân trắng
                Box { py: 0.75; sx: 2.0; sy: 0.05; sz: 0.9; col: "#d6b088"; rough: 0.5; clear: 0.3; pickable: true }
                Box { py: 0.717; sx: 1.94; sy: 0.02; sz: 0.84; col: "#a9825c"; rough: 0.7 }
                Repeater3D {
                    model: [[-0.9, -0.38], [0.9, -0.38], [-0.9, 0.38], [0.9, 0.38]]
                    delegate: Box { required property var modelData; px: modelData[0]; pz: modelData[1]; py: 0.36; sx: 0.05; sy: 0.72; sz: 0.05; shape: "#Cylinder"; col: "#ececee"; metal: 0.3; rough: 0.35 }
                }
                // laptop: đế + nắp (mặt sau quay ra camera, logo sáng theo trạng thái)
                Box { py: 0.785; pz: -0.08; sx: 0.66; sy: 0.025; sz: 0.44; col: "#d0d4da"; metal: 0.6; rough: 0.3 }
                Node {
                    y: 0.79 * 100; z: 0.14 * 100
                    eulerRotation.x: 12
                    Box { py: 0.17; sx: 0.66; sy: 0.34; sz: 0.025; col: "#d0d4da"; metal: 0.6; rough: 0.3 }
                    Box {
                        py: 0.19; pz: 0.016; sx: 0.08; sy: 0.08; sz: 0.005; shape: "#Cylinder"; eulerRotation.x: 90; castsShadows: false
                        col: "black"; glow: desk.on ? app.ssCol[desk.st] : "#555a64"; glowK: desk.on ? (desk.st === "working" ? 1.3 + Math.sin(app.t * 4 + desk.index) * 0.5 : 1.0) : 0.3
                    }
                }
                // đèn bàn (sáng khi phiên mở), cốc, sổ tay, chậu sen đá
                Node {
                    visible: of.detail
                    x: 0.8 * 100; z: -0.28 * 100
                    Box { py: 0.785; sx: 0.17; sy: 0.025; sz: 0.17; shape: "#Cylinder"; col: "#2a2d33"; metal: 0.4; rough: 0.4 }
                    Box { py: 0.98; sx: 0.022; sy: 0.4; sz: 0.022; shape: "#Cylinder"; col: "#2a2d33"; metal: 0.4 }
                    Box { py: 1.18; px: -0.09; sx: 0.2; sy: 0.022; sz: 0.022; col: "#2a2d33"; metal: 0.4 }
                    Node {
                        x: -0.2 * 100; y: 1.08 * 100
                        eulerRotation.z: 18
                        Box { sx: 0.22; sy: 0.17; sz: 0.22; shape: "#Cone"; col: of.tint; rough: 0.4; clear: 0.4 }
                        Box { py: 0.01; sx: 0.08; sy: 0.08; sz: 0.08; shape: "#Sphere"; col: "black"; glow: "#ffd9a0"; glowK: desk.on ? 2.4 : 0; castsShadows: false }
                    }
                }
                Box { px: 0.62; py: 0.83; pz: 0.2; sx: 0.11; sy: 0.13; sz: 0.11; shape: "#Cylinder"; col: of.tint; rough: 0.35; clear: 0.5 }
                Box { visible: of.detail; px: -0.6; py: 0.78; pz: 0.08; sx: 0.34; sy: 0.012; sz: 0.44; eulerRotation.y: 9; col: "#f4f1ea"; rough: 0.9 }
                Box { visible: of.detail; px: -0.6; py: 0.787; pz: 0.08; sx: 0.02; sy: 0.012; sz: 0.44; eulerRotation.y: 9; col: of.tint }
                Node {
                    visible: of.detail && desk.index % 2 === 0
                    x: -0.82 * 100; z: -0.25 * 100
                    Box { py: 0.82; sx: 0.12; sy: 0.1; sz: 0.12; shape: "#Cylinder"; col: "#e2d6c6" }
                    Box { py: 0.9; sx: 0.14; sy: 0.1; sz: 0.14; shape: "#Sphere"; col: "#6fae75"; rough: 0.8 }
                }
                // ghế xoay (sau robot)
                Node {
                    z: -0.86 * 100
                    Box { py: 0.5; sx: 0.62; sy: 0.13; sz: 0.58; shape: "#Sphere"; col: desk.fabric; rough: 0.85 }
                    Box { py: 0.94; pz: -0.27; sx: 0.58; sy: 0.66; sz: 0.13; shape: "#Sphere"; col: desk.fabric; rough: 0.85 }
                    Box { py: 0.27; sx: 0.06; sy: 0.42; sz: 0.06; shape: "#Cylinder"; col: "#3a3d44"; metal: 0.5; rough: 0.3 }
                    Repeater3D {
                        model: 5
                        delegate: Node {
                            required property int index
                            visible: of.detail
                            eulerRotation.y: index * 72
                            Box { px: 0.17; py: 0.06; sx: 0.34; sy: 0.035; sz: 0.05; col: "#3a3d44"; metal: 0.5 }
                            Box { px: 0.33; py: 0.035; sx: 0.07; sy: 0.07; sz: 0.07; shape: "#Sphere"; col: "#1e2025" }
                        }
                    }
                }
                // vòng sáng dưới ghế khi phiên này được chọn
                Box {
                    visible: desk.hl
                    py: 0.13; pz: -0.3; sx: 2.4; sy: 0.01; sz: 1.9; shape: "#Cylinder"; col: "black"; castsShadows: false
                    glow: "white"; glowK: 0.45 + Math.sin(app.t * 4) * 0.2
                }
                // biển tên trước bàn (khi đang ở trong văn phòng)
                Panel3D {
                    visible: of.focused
                    py: 0.55; pz: 0.46; w: 1.8; h: 0.3; bright: 1.2
                    src: Rectangle {
                        width: 540; height: 90; radius: 12; color: "#16181d"
                        border.width: desk.hl ? 4 : 0; border.color: "white"
                        Row {
                            x: 16; spacing: 12; anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: 22; height: 22; radius: 11; color: app.ssCol[desk.st]; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                width: 480; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                text: (desk.s?.title ?? ""); color: "white"; font { family: app.sans; pixelSize: 30; bold: true }
                            }
                        }
                    }
                }
                // robot của phiên (chỉ khi phiên đang mở)
                Bot {
                    visible: desk.on
                    z: -0.8 * 100
                    body: app.modelCol(desk.s?.model)
                    status: app.ssCol[desk.st]
                    mode: desk.st
                    seed: desk.index * 1.7 + of.index
                    hl: desk.hl
                    sessId: desk.s?.id ?? ""
                    botInfo: desk.s ? (of.p.name + " · " + (app.ssName[desk.st] ?? "") + " · " + desk.s.model + "\n" + desk.s.title
                                       + (desk.s.doing ? "\n▸ " + app.verbOf(desk.s.doing.tool) + ": " + desk.s.doing.text : "")) : ""
                }
                // bong bóng: đang làm gì / chờ duyệt gì
                Bubble {
                    visible: desk.on && (of.focused || app.dist < 26) && desk.st !== "idle" && desk.s?.doing !== null
                    py: 2.35; pz: -0.8
                    kk: of.focused ? 1 : 1.3
                    accent: app.ssCol[desk.st]
                    tag: desk.st === "waiting" ? "CHỜ DUYỆT" : app.verbOf(desk.s?.doing?.tool).toUpperCase()
                    text: desk.st === "waiting" ? (desk.s?.doing?.tool ?? "") + " · " + (desk.s?.doing?.text ?? "") : (desk.s?.doing?.text ?? "")
                }
                Bubble {
                    visible: desk.on && of.focused && desk.st === "idle"
                    py: 2.15; pz: -0.8; kk: 0.8
                    accent: app.ssCol.idle
                    tag: "RẢNH"
                    text: "chờ yêu cầu mới"
                }
            }
        }

        // ---- subagent đang chạy: robot nhỏ đứng trước bảng, bong bóng = việc đang làm
        Repeater3D {
            model: of.lite ? 0 : 4
            delegate: Node {
                id: sub
                required property int index
                readonly property var a: of.runAgents[index] ?? null
                visible: a !== null
                x: (-3.7 + index * 1.05) * 100; z: (-app.od / 2 + 1.0) * 100
                Bot {
                    k: 0.72
                    seated: false
                    body: "#6ea0f0"
                    status: app.stCol.running
                    mode: "working"
                    seed: sub.index * 2.3
                    sessId: sub.a?.session ?? ""
                    botInfo: sub.a ? ("subagent · " + sub.a.type + " · " + sub.a.model + "\n" + sub.a.title
                                      + (sub.a.doing ? "\n▸ " + app.verbOf(sub.a.doing.tool) + ": " + sub.a.doing.text : "") + "\n" + app.fmtTok(sub.a.tokens) + " tok") : ""
                }
                Bubble {
                    visible: sub.a !== null && (of.focused || app.dist < 26)
                    py: 1.85 + (sub.index % 2) * 0.45; kk: 0.75
                    accent: "#6ea0f0"
                    tag: (sub.a?.type ?? "agent").toUpperCase()
                    text: sub.a?.doing ? app.verbOf(sub.a.doing.tool) + ": " + sub.a.doing.text : (sub.a?.title ?? "")
                }
            }
        }

        // ---- nhãn nổi (toàn cảnh): tên, trạng thái, token, số việc, đang làm gì
        Panel3D {
            id: lbl
            visible: app.sel < 0
            readonly property real k: Math.max(0.8, Math.min(1.8, app.dist / 45))
            readonly property bool doing: of.p?.doing ? true : false
            py: 4.3 + 0.6 * k; w: 6.0 * k; h: (doing ? 1.62 : 1.22) * k; bright: 1.5
            eulerRotation.y: app.yawDeg
            eulerRotation.x: -app.pitch * 180 / Math.PI * 0.6
            src: Rectangle {
                width: 640; height: lbl.doing ? 172 : 130; radius: 22
                color: Qt.rgba(0.07, 0.08, 0.1, 0.9)
                border.width: 4; border.color: app.hoverOffice === of.index ? "white" : app.ssCol[of.pstate]
                Row {
                    x: 22; y: 14; spacing: 14
                    Rectangle {
                        width: 26; height: 26; radius: 13; color: app.ssCol[of.pstate]; anchors.verticalCenter: nm.verticalCenter
                    }
                    Text { id: nm; text: (of.index + 1) + "  " + (of.p?.name ?? ""); color: "white"; width: 560; elide: Text.ElideRight; font { family: app.sans; pixelSize: 44; bold: true } }
                }
                Row {
                    x: 26; y: 76; spacing: 18
                    Text { text: app.fmtTok(of.p?.tokens?.total) + " tok"; color: "#c9ccd3"; font { family: app.sans; pixelSize: 30 } }
                    Text { text: of.nLive + "/" + (of.p?.sessions?.length ?? 0) + " agent"; color: "#c9ccd3"; font { family: app.sans; pixelSize: 30 } }
                    Text { visible: of.board.counts.running > 0; text: "▶ " + of.board.counts.running; color: app.stCol.running; font { family: app.sans; pixelSize: 30; bold: true } }
                    Text { visible: of.board.counts.pending > 0; text: "◷ " + of.board.counts.pending; color: app.stCol.pending; font { family: app.sans; pixelSize: 30; bold: true } }
                    Text { visible: of.board.counts.blocked > 0; text: "⛔ " + of.board.counts.blocked; color: app.stCol.blocked; font { family: app.sans; pixelSize: 30; bold: true } }
                }
                Text {
                    visible: lbl.doing
                    x: 26; y: 120; width: 590; elide: Text.ElideRight
                    text: "▸ " + app.verbOf(of.p?.doing?.tool) + ": " + (of.p?.doing?.text ?? "")
                    color: app.ssCol[of.pstate]; font { family: app.sans; pixelSize: 30; bold: true }
                }
            }
        }
    }

    // ------------------------------------------------------------------ cửa sổ
    FloatingWindow {
        id: win
        title: "Claude Agent HQ"
        implicitWidth: 1440
        implicitHeight: 880
        minimumSize: Qt.size(900, 560)
        color: app.bg
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Space) app.spin = !app.spin;
                else if (e.key === Qt.Key_0 || e.key === Qt.Key_Escape) app.flyOverview();
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) app.flyOffice(e.key - Qt.Key_1);
                else if (e.key === Qt.Key_Tab) app.panelOn = !app.panelOn;
                else if (e.key === Qt.Key_I) app.interior = !app.interior;
                else if (e.key === Qt.Key_G) app.quality = (app.quality + 1) % 3;
                else if (e.key === Qt.Key_Q) Qt.quit();
                else return;
                e.accepted = true;
            }

            View3D {
                id: view
                anchors.fill: parent
                camera: camera
                environment: ExtendedSceneEnvironment {
                    backgroundMode: SceneEnvironment.Color
                    clearColor: app.interior ? "#141922" : "#060912"
                    antialiasingMode: app.quality > 0 ? SceneEnvironment.MSAA : SceneEnvironment.NoAA
                    antialiasingQuality: app.quality > 1 ? SceneEnvironment.High : SceneEnvironment.Medium
                    fxaaEnabled: app.quality === 0
                    tonemapMode: SceneEnvironment.TonemapModeFilmic
                    exposure: 1.1
                    lightProbe: Texture {
                        textureData: ProceduralSkyTextureData {
                            skyTopColor: "#7d9cd6"
                            skyHorizonColor: "#e6d6c2"
                            groundHorizonColor: "#9a8c7a"
                            groundBottomColor: "#3b342d"
                            sunLatitude: 40
                            sunColor: "#fff2dc"
                        }
                    }
                    probeExposure: app.interior ? 0.55 : 0.12
                    aoEnabled: app.quality > 1 && app.sel >= 0 && !fly.running
                    aoStrength: 45
                    aoDistance: 9
                    aoSoftness: 35
                    glowEnabled: app.quality > 0
                    glowIntensity: 1.0
                    glowBloom: 0.2
                    glowStrength: 1.0
                    glowHDRMinimumValue: 0.6
                    glowQualityHigh: false
                    ditheringEnabled: true
                }

                Node {
                    position: Qt.vector3d(app.lookX * 100, 60, app.lookZ * 100)
                    eulerRotation.y: app.yawDeg
                    eulerRotation.x: -app.pitch * 180 / Math.PI
                    PerspectiveCamera {
                        id: camera
                        z: app.dist * 100
                        fieldOfView: 40
                        clipNear: 30
                        clipFar: 60000
                    }
                }
                DirectionalLight {
                    eulerRotation: Qt.vector3d(-58, -28, 0)
                    color: "#fff3e6"
                    brightness: app.interior ? 1.9 : 0.45
                    ambientColor: app.interior ? Qt.rgba(0.16, 0.17, 0.2, 1) : Qt.rgba(0.05, 0.07, 0.12, 1)
                    // bóng đổ: Cân bằng = chỉ khi đang ở trong văn phòng, Cao = luôn có
                    castsShadow: app.interior && (app.quality > 1 || (app.quality === 1 && app.sel >= 0))
                    shadowMapQuality: app.quality > 1 ? Light.ShadowMapQualityHigh : Light.ShadowMapQualityMedium
                    shadowFactor: 45
                    pcfFactor: 2
                    softShadowQuality: Light.PCF4
                    shadowMapFar: 9000
                }
                DirectionalLight {
                    eulerRotation: Qt.vector3d(-25, 150, 0)
                    color: "#b8c8ff"
                    brightness: app.interior ? 0.7 : 0.25
                }

                // sàn tầng + hành lang
                Box {
                    visible: app.interior
                    py: -0.1; sx: app.cols * app.pitchX + 8; sy: 0.2; sz: app.rows * app.pitchZ + 8
                    col: "#2a2e36"; rough: 0.85
                }
                Box {
                    visible: app.interior
                    py: -0.3; sx: app.cols * app.pitchX + 9; sy: 0.2; sz: app.rows * app.pitchZ + 9
                    col: "#1b1e24"; rough: 0.9
                }

                Galaxy {}
                Repeater3D {
                    model: app.interior ? app.n : 0
                    delegate: Office {}
                }
            }

            // ---------------------------------------------------------- chuột trên cảnh 3D
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                property real lx
                property real ly
                property real px0
                property real py0
                function hit(x, y) {
                    let o = view.pick(x, y).objectHit;
                    let info = "", sess = "";
                    while (o && o.officeId === undefined) {
                        if (info === "" && o.botInfo !== undefined) { info = o.botInfo; sess = o.sessId; }
                        o = o.parent;
                    }
                    return { office: o ? o.officeId : -1, info, sess };
                }
                onPressed: m => { lx = m.x; ly = m.y; px0 = m.x; py0 = m.y; root.forceActiveFocus(); }
                onReleased: m => {
                    if (Math.hypot(m.x - px0, m.y - py0) > 4) return;
                    const h = hit(m.x, m.y);
                    if (h.sess) app.pickSession(h.office, h.sess);
                    else if (h.office >= 0 && h.office !== app.sel) app.flyOffice(h.office);
                }
                onPositionChanged: m => {
                    if (pressed) {
                        fly.stop();
                        app.yaw -= (m.x - lx) * 0.006;
                        app.pitch = Math.max(0.15, Math.min(1.45, app.pitch + (m.y - ly) * 0.005));
                        lx = m.x; ly = m.y;
                        return;
                    }
                    const h = hit(m.x, m.y);
                    app.hoverOffice = h.office;
                    app.hoverInfo = h.info;
                    tip.mx = m.x; tip.my = m.y;
                }
                onExited: { app.hoverOffice = -1; app.hoverInfo = ""; }
                onWheel: w => {
                    const dy = w.angleDelta.y !== 0 ? w.angleDelta.y / 120 : w.pixelDelta.y / 120;
                    if (dy === 0) return;
                    fly.stop();
                    app.dist = Math.max(4, Math.min(300, app.dist * Math.pow(0.9, Math.max(-3, Math.min(3, dy)))));
                }
                cursorShape: (app.hoverOffice >= 0 && app.hoverOffice !== app.sel) || app.hoverInfo !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            // tooltip robot
            Rectangle {
                id: tip
                property real mx
                property real my
                visible: app.hoverInfo !== ""
                x: Math.min(parent.width - width - 8, mx + 16); y: my + 18
                width: tipT.implicitWidth + 20; height: tipT.implicitHeight + 14; radius: 7
                color: Qt.rgba(0.06, 0.07, 0.09, 0.95); border.color: app.line
                T { id: tipT; x: 10; y: 7; text: app.hoverInfo; font.pixelSize: 12; lineHeight: 1.15 }
            }

            // ---------------------------------------------------------- bố cục kiểu AgentOps 3D: header · thanh dự án · cột trái/phải · nhật ký
            readonly property real leftM: app.panelOn ? 316 : 12
            readonly property real rightM: app.panelOn ? 358 : 12

            // header: logo + KPI + điều khiển
            Rectangle {
                id: top
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 62
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0.024, 0.035, 0.07, 0.96) }
                    GradientStop { position: 1; color: Qt.rgba(0.024, 0.035, 0.07, 0.72) }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.line }
                MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: w => w.accepted = true }
                Row {
                    id: brand
                    x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                    Image { source: app.iconUrl; width: 32; height: 32; sourceSize: Qt.size(64, 64); anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        T { text: "Claude Agent HQ"; font { family: app.sans; pixelSize: 15; bold: true } }
                        T {
                            text: !app.loaded ? (app.scanErr ? "lỗi scan.py: " + app.scanErr : "đang đọc transcript…") : "Quản lý agent Claude Code theo dự án"
                            color: app.muted; font { family: app.sans; pixelSize: 11 }
                        }
                    }
                }
                Row {
                    id: kpis
                    anchors { left: brand.right; right: ctrl.left; leftMargin: 18; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 6; layoutDirection: Qt.LeftToRight
                    Kpi { label: "Agent hoạt động"; value: app.nWorking + "/" + app.liveList.length }
                    Kpi { label: "Văn phòng"; value: "" + app.n }
                    Kpi { label: "Phiên đang mở"; value: "" + (app.hq.totals?.live ?? 0) }
                    Kpi { label: "Token hôm nay"; value: app.fmtTok(app.hq.totals?.today) }
                    Kpi { label: "Chi phí ước tính"; value: app.fmtCost(app.hq.totals?.cost) }
                    Kpi { label: "Chờ duyệt"; value: "" + app.waitList.length; warn: true }
                }
                Row {
                    id: ctrl
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Btn { text: app.spin ? "Dừng xoay" : "Tự xoay"; on: app.spin; onClicked: app.spin = !app.spin }
                    Row {
                        spacing: 0
                        Repeater {
                            model: app.qualityName
                            delegate: Btn { required property string modelData; required property int index; text: modelData; on: app.quality === index; onClicked: app.quality = index }
                        }
                    }
                    Btn { text: "Dự án " + app.n + "/" + app.allProjects.length; on: app.pickerOn; onClicked: app.pickerOn = !app.pickerOn }
                    Btn { text: app.panelOn ? "Ẩn panel" : "Hiện panel"; onClicked: app.panelOn = !app.panelOn }
                }
            }

            // bảng chọn dự án hiển thị
            Card {
                visible: app.pickerOn
                z: 10
                x: parent.width - width - 14; y: 68
                width: 300; height: Math.min(parent.height - 90, 84 + app.allProjects.length * 32)
                title: "Chọn dự án hiển thị"; count: app.n + "/" + app.allProjects.length
                Row {
                    id: pkTop
                    x: 10; y: 8; spacing: 6
                    Btn { text: "Hiện tất cả"; onClicked: app.showAll(true) }
                    Btn { text: "Ẩn hết"; onClicked: app.showAll(false) }
                    Btn { text: "Xong"; onClicked: app.pickerOn = false }
                }
                ListView {
                    anchors { left: parent.left; right: parent.right; top: pkTop.bottom; bottom: parent.bottom; margins: 8; topMargin: 8 }
                    clip: true; spacing: 2; boundsBehavior: Flickable.StopAtBounds
                    model: app.allProjects
                    delegate: Rectangle {
                        id: pr
                        required property var modelData
                        readonly property bool vis: !app.hidden.includes(modelData.key)
                        width: ListView.view.width; height: 30; radius: 8
                        color: prm.containsMouse ? Qt.rgba(0.2, 0.25, 0.33, 0.45) : "transparent"
                        Row {
                            x: 8; spacing: 9; anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: 16; height: 16; radius: 4; anchors.verticalCenter: parent.verticalCenter
                                color: pr.vis ? app.hueCol(pr.modelData.key) : "transparent"; border.color: app.hueCol(pr.modelData.key); border.width: 2
                                T { anchors.centerIn: parent; visible: pr.vis; text: "✓"; color: "#0b0f1a"; font { pixelSize: 11; bold: true } }
                            }
                            T { text: pr.modelData.name; width: 190; elide: Text.ElideRight; color: pr.vis ? app.fg : app.muted; font { family: app.sans; pixelSize: 12 } anchors.verticalCenter: parent.verticalCenter }
                            T { text: app.fmtTok(pr.modelData.tokens.total); color: app.muted; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: prm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: app.toggleProject(pr.modelData.key) }
                    }
                }
            }

            // thanh dự án + chú thích
            Column {
                x: root.leftM; y: 74; width: root.width - root.leftM - root.rightM; spacing: 8
                Flow {
                    width: parent.width; spacing: 6
                    layoutDirection: Qt.LeftToRight
                    PjChip { text: "Toàn cảnh"; sub: ""; col: app.fg; on: app.sel < 0; onClicked: app.flyOverview() }
                    Repeater {
                        model: app.allProjects
                        delegate: PjChip {
                            required property var modelData
                            readonly property int vi: app.projects.findIndex(p => p.key === modelData.key)
                            readonly property int nl: (modelData.sessions ?? []).filter(s => s.live).length
                            readonly property int nw: (modelData.sessions ?? []).filter(s => s.state === "waiting").length
                            off: vi < 0
                            toggleable: true
                            text: (vi >= 0 ? (vi + 1) + " " : "") + modelData.name
                            sub: nl > 0 ? "" + nl : ""
                            badge: nw
                            col: app.hueCol(modelData.key)
                            on: vi >= 0 && app.sel === vi
                            onClicked: if (vi >= 0) app.flyOffice(vi)
                            onToggled: app.toggleProject(modelData.key)
                        }
                    }
                    PjChip { text: app.hidden.length > 0 ? "Hiện tất cả" : "Ẩn hết"; sub: ""; col: app.muted; onClicked: app.showAll(app.hidden.length > 0) }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: lgRow.implicitWidth + 24; height: 26; radius: 13
                    color: Qt.rgba(0.024, 0.035, 0.07, 0.6); border.color: app.line
                    Row {
                        id: lgRow
                        anchors.centerIn: parent; spacing: 12
                        Repeater {
                            model: [["working", "Đang làm"], ["idle", "Rảnh"], ["waiting", "Chờ duyệt"], ["offline", "Offline"]]
                            delegate: Row {
                                required property var modelData
                                spacing: 5
                                Rectangle { width: 7; height: 7; radius: 4; color: app.ssCol[modelData[0]]; anchors.verticalCenter: parent.verticalCenter }
                                T { text: modelData[1]; color: app.muted; font.pixelSize: 10 }
                            }
                        }
                        T { visible: root.width > 1180; text: "kéo xoay · cuộn zoom · click robot / văn phòng · 1-9 · 0 · Space · G"; color: Qt.rgba(1, 1, 1, 0.3); font.pixelSize: 10 }
                    }
                }
            }

            // cột trái: danh sách agent + token
            Item {
                id: leftCol
                visible: app.panelOn
                x: 12; y: 74; width: 292; height: parent.height - 86
                Card {
                    id: agCard
                    width: parent.width; height: parent.height - tkCard.height - 10
                    title: app.sel >= 0 ? "Agent · " + (app.selP?.name ?? "") : "Tất cả agent"
                    count: app.agentRows.length + ""
                    Flow {
                        id: agFilters
                        x: 11; y: 8; width: parent.width - 22; spacing: 5
                        Repeater {
                            model: [["all", "Tất cả"], ["working", "Đang làm"], ["waiting", "Chờ duyệt"], ["idle", "Rảnh"], ["offline", "Offline"]]
                            delegate: Chip {
                                required property var modelData
                                small: true
                                text: modelData[1] + " " + app.agentCount(modelData[0])
                                on: app.agFilter === modelData[0]
                                onClicked: app.agFilter = modelData[0]
                            }
                        }
                    }
                    ListView {
                        id: agList
                        anchors { left: parent.left; right: parent.right; top: agFilters.bottom; bottom: parent.bottom; topMargin: 6; leftMargin: 7; rightMargin: 7 }
                        clip: true; spacing: 3; boundsBehavior: Flickable.StopAtBounds
                        model: app.agentRows
                        delegate: AgentRow { width: agList.width }
                        T {
                            visible: agList.count === 0
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 14 }
                            text: "Không có agent nào"; color: app.muted; font.pixelSize: 12
                        }
                    }
                }
                Card {
                    id: tkCard
                    y: parent.height - height
                    width: parent.width; height: 196
                    title: "Token"; count: app.fmtTok(app.tokScope?.total) + " · " + app.fmtCost(app.costScope)
                    Column {
                        x: 12; y: 9; width: parent.width - 24; spacing: 8
                        Row {
                            width: parent.width; height: 8
                            Repeater {
                                model: app.modelsScope
                                delegate: Rectangle { required property var modelData; width: parent.width * modelData[1] / app.modelsSum; height: 8; color: app.modelCol(modelData[0]) }
                            }
                        }
                        Flow {
                            width: parent.width; spacing: 10
                            Repeater {
                                model: app.modelsScope
                                delegate: Row {
                                    required property var modelData
                                    spacing: 4
                                    Rectangle { width: 7; height: 7; radius: 4; color: app.modelCol(modelData[0]); anchors.verticalCenter: parent.verticalCenter }
                                    T { text: modelData[0] + " " + app.fmtTok(modelData[1]); font.pixelSize: 10; color: app.muted }
                                }
                            }
                        }
                        T { text: "14 NGÀY"; color: app.muted; font { pixelSize: 10; bold: true; letterSpacing: 1.2 } }
                        Row {
                            width: parent.width; height: 52; spacing: 3
                            Repeater {
                                model: app.daysScope
                                delegate: Item {
                                    required property var modelData
                                    required property int index
                                    width: (parent.width - 3 * 13) / 14; height: 52
                                    Rectangle {
                                        anchors.bottom: parent.bottom; width: parent.width; radius: 2
                                        height: Math.max(2, 52 * parent.modelData.total / app.daysMax)
                                        color: parent.index === 13 ? app.stCol.running : "#38bdf8"
                                        opacity: parent.modelData.total > 0 ? 0.9 : 0.22
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // cột phải: chi tiết + phê duyệt
            Item {
                id: rightCol
                visible: app.panelOn
                x: parent.width - 346; y: 74; width: 334; height: parent.height - 86
                Card {
                    id: dtCard
                    width: parent.width; height: parent.height - apCard.height - 10
                    title: app.sel >= 0 ? "Chi tiết · " + (app.selP?.name ?? "") : "Toàn cảnh"
                    count: ""
                    Flickable {
                        id: flick
                        anchors { fill: parent; margins: 12 }
                        contentWidth: width
                        contentHeight: body.implicitHeight + 10
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Loader {
                            id: body
                            width: flick.width
                            sourceComponent: app.sel >= 0 ? officeView : overviewView
                            onSourceComponentChanged: flick.contentY = 0
                        }
                    }
                }
                Card {
                    id: apCard
                    y: parent.height - height
                    width: parent.width
                    height: app.waitList.length === 0 ? 84 : Math.min(parent.height * 0.42, 44 + app.waitList.length * 112)
                    title: "Chờ duyệt quyền"; count: app.waitList.length > 0 ? app.waitList.length + "" : ""
                    T {
                        visible: app.waitList.length === 0
                        anchors.centerIn: parent; anchors.verticalCenterOffset: 0
                        text: "Không có agent nào đang chờ bạn."; color: app.muted; font.pixelSize: 12
                    }
                    ListView {
                        anchors { fill: parent; margins: 8 }
                        clip: true; spacing: 7; boundsBehavior: Flickable.StopAtBounds
                        model: app.waitList
                        delegate: Rectangle {
                            id: apr
                            required property var modelData
                            width: ListView.view.width; height: apc.implicitHeight + 18; radius: 10
                            color: Qt.rgba(0.44, 0.25, 0.07, 0.16); border.color: Qt.rgba(0.98, 0.8, 0.08, 0.3)
                            Column {
                                id: apc
                                x: 10; y: 9; width: parent.width - 20; spacing: 4
                                Row {
                                    spacing: 6
                                    Rectangle { width: apT.implicitWidth + 10; height: 16; radius: 4; color: "transparent"; border.color: app.ssCol.waiting
                                        T { id: apT; anchors.centerIn: parent; text: apr.modelData.s.waitingTool || apr.modelData.s.doing?.tool || "tool"; color: app.ssCol.waiting; font { pixelSize: 9; bold: true } } }
                                    T { text: apr.modelData.p.name; color: app.muted; font.pixelSize: 11; width: apc.width - apT.implicitWidth - 24; elide: Text.ElideRight }
                                }
                                T { text: apr.modelData.s.title || "(phiên)"; width: parent.width; elide: Text.ElideRight; font { family: app.sans; pixelSize: 12; bold: true } }
                                T { text: apr.modelData.s.doing?.text ?? ""; visible: text !== ""; width: parent.width; elide: Text.ElideRight; color: "#fde68a"; font { family: app.sans; pixelSize: 11 } }
                                Row {
                                    spacing: 6
                                    Btn { text: "Xem agent"; onClicked: app.pickSession(apr.modelData.pi, apr.modelData.s.id) }
                                    T { text: "duyệt trong terminal của phiên"; color: app.muted; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                    }
                }
            }

            // nhật ký hoạt động
            Card {
                id: logCard
                visible: app.panelOn && root.width > 1180
                x: root.leftM; width: root.width - root.leftM - root.rightM
                anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                height: 50 + app.logEntries.length * 18
                title: "Nhật ký hoạt động"; count: app.logEntries.length + ""
                Column {
                    x: 12; y: 6; width: parent.width - 24; spacing: 2
                    Repeater {
                        model: app.logEntries
                        delegate: Row {
                            required property var modelData
                            width: parent.width; spacing: 7; height: 16
                            T { text: Qt.formatDateTime(new Date(modelData.ts * 1000), "HH:mm:ss"); color: app.muted; font.pixelSize: 10; width: 56 }
                            T { text: modelData.who; color: app.hueCol(modelData.pkey); font { pixelSize: 10; bold: true } width: 120; elide: Text.ElideRight }
                            T { text: app.verbOf(modelData.tool); color: app.verbCol(modelData.tool); font { pixelSize: 10; bold: true } width: 78; elide: Text.ElideRight }
                            T { text: modelData.text; color: modelData.st === "err" ? "#fca5a5" : "#b9bec8"; font.pixelSize: 10; width: parent.width - 270; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ panel: toàn cảnh
    Component {
        id: overviewView
        Column {
            spacing: 14
            Grid {
                columns: 2; spacing: 8; width: parent.width
                Stat { width: (parent.width - 8) / 2; label: "TỔNG TOKEN"; value: app.fmtTok(app.hq.totals?.tokens?.total); sub: "out " + app.fmtTok(app.hq.totals?.tokens?.out) + " · in " + app.fmtTok(app.hq.totals?.tokens?.in) }
                Stat { width: (parent.width - 8) / 2; label: "HÔM NAY"; value: app.fmtTok(app.hq.totals?.today); sub: "token (gồm cache)"; accent: app.stCol.running }
                Stat { width: (parent.width - 8) / 2; label: "CHI PHÍ ƯỚC TÍNH"; value: app.fmtCost(app.hq.totals?.cost); sub: "theo Claude Code ghi lại"; accent: "#e8c548" }
                Stat { width: (parent.width - 8) / 2; label: "CACHE"; value: app.fmtTok(app.hq.totals?.tokens?.cacheRead); sub: "đọc · ghi " + app.fmtTok(app.hq.totals?.tokens?.cacheWrite) }
            }
            StatusRow { width: parent.width; counts: app.hq.totals?.counts ?? {} }

            SectionTitle { text: "CẦN CHÚ Ý (" + app.attention.length + ")" }
            T {
                visible: app.attention.length === 0
                text: "Không có việc nào đang chạy, chờ làm hay bị chặn."
                color: app.muted; font.pixelSize: 12; width: parent.width; wrapMode: Text.Wrap
            }
            Column {
                width: parent.width; spacing: 6
                Repeater {
                    model: app.attention
                    delegate: ItemRow { width: parent.width; showProject: true; onPicked: app.flyOffice(modelData.pi) }
                }
            }

            SectionTitle { text: "VĂN PHÒNG (" + app.n + ")" }
            Column {
                width: parent.width; spacing: 6
                Repeater {
                    model: app.projects
                    delegate: Rectangle {
                        id: orow
                        required property var modelData
                        required property int index
                        readonly property real mx: Math.max(1, ...app.projects.map(p => p.tokens.total))
                        readonly property var live: (modelData.sessions ?? []).filter(s => s.live)
                        readonly property bool busy: modelData.state === "working" || modelData.state === "waiting"
                        width: parent.width; height: ocol.implicitHeight + 16; radius: 8
                        color: om.containsMouse || app.hoverOffice === index ? "#1f232b" : app.card
                        border.color: busy ? Qt.rgba(app.ssCol[modelData.state].r, app.ssCol[modelData.state].g, app.ssCol[modelData.state].b, 0.45) : "transparent"
                        Rectangle { width: 4; height: parent.height - 16; y: 8; x: 6; radius: 2; color: app.hueCol(orow.modelData.key) }
                        Column {
                            id: ocol
                            x: 18; y: 8; width: parent.width - 28; spacing: 4
                            Row {
                                width: parent.width; spacing: 8
                                Rectangle {
                                    width: 8; height: 8; radius: 4; color: app.ssCol[orow.modelData.state]; anchors.verticalCenter: parent.verticalCenter
                                    opacity: (orow.busy) ? 0.4 + 0.6 * Math.abs(Math.sin(app.t * 2.2)) : 1
                                }
                                T { text: (orow.index + 1) + "  " + orow.modelData.name; font { pixelSize: 13; bold: true } width: parent.width - 150; elide: Text.ElideRight }
                                T { text: app.fmtTok(orow.modelData.tokens.total); color: app.fg; font.pixelSize: 12; width: 56; horizontalAlignment: Text.AlignRight }
                                T { text: app.fmtCost(orow.modelData.cost); color: "#e8c548"; font.pixelSize: 12; width: 60; horizontalAlignment: Text.AlignRight }
                            }
                            Rectangle {
                                width: parent.width; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.06)
                                Rectangle { width: Math.max(2, parent.width * orow.modelData.tokens.total / orow.mx); height: 4; radius: 2; color: app.hueCol(orow.modelData.key) }
                            }
                            T {
                                text: (app.ssName[orow.modelData.state] ?? "") + " · " + orow.live.length + "/" + orow.modelData.sessions.length + " agent mở · " + orow.modelData.nRequests + " yêu cầu · " + app.ago(orow.modelData.last)
                                color: app.muted; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight
                            }
                            DoingLine { width: parent.width; doing: orow.modelData.doing; waiting: orow.modelData.state === "waiting" }
                        }
                        MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: app.flyOffice(orow.index) }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ panel: một văn phòng
    Component {
        id: officeView
        Column {
            id: ov
            readonly property var p: app.selP
            readonly property var list: app.tabItems(p, app.tab)
            readonly property var shown: list.filter(it => app.tab === "sessions" || app.match(it))
            readonly property var cnt: app.countBy(list)
            spacing: 12

            Row {
                width: parent.width; spacing: 8
                Chip { text: "← Toàn cảnh"; onClicked: app.flyOverview() }
                Item { width: parent.width - 150; height: 1 }
                IconBtn { text: "✕"; onClicked: app.panelOn = false }
            }
            Column {
                width: parent.width; spacing: 3
                Row {
                    spacing: 10; width: parent.width
                    Rectangle { width: 6; height: 26; radius: 3; color: app.hueCol(ov.p?.key) }
                    T { text: ov.p?.name ?? ""; font { family: app.sans; pixelSize: 22; bold: true } width: parent.width - 120; elide: Text.ElideRight }
                    Pill { anchors.verticalCenter: parent.verticalCenter; text: app.ssName[ov.p?.state] ?? ""; col: app.ssCol[ov.p?.state] ?? app.muted }
                }
                T { text: ov.p?.short ?? ""; color: app.muted; font.pixelSize: 11; width: parent.width; elide: Text.ElideMiddle }
                T {
                    text: (ov.p?.sessions?.[0]?.branch ? " " + ov.p.sessions[0].branch + " · " : "") + "hoạt động " + app.ago(ov.p?.last)
                    color: app.muted; font.pixelSize: 11
                }
            }

            // hoạt động: các phiên đang mở (không có thì phiên gần nhất) + nhật ký hành động
            Column {
                id: actSec
                width: parent.width; spacing: 8
                readonly property var entries: {
                    const ss = (ov.p?.sessions ?? []);
                    const live = ss.filter(s => s.live);
                    return (live.length ? live : ss.slice(0, 1)).map(s => ({ s, p: ov.p, pi: app.sel }));
                }
                SectionTitle { text: (ov.p?.live ? "HOẠT ĐỘNG · " + actSec.entries.length + " agent đang mở" : "LẦN HOẠT ĐỘNG GẦN NHẤT") }
                Repeater {
                    model: actSec.entries
                    delegate: ActiveCard { width: actSec.width; entry: modelData; showProject: false; logN: 6 }
                }
            }

            // token
            Grid {
                columns: 3; spacing: 8; width: parent.width
                Stat { width: (parent.width - 16) / 3; label: "TỔNG TOKEN"; value: app.fmtTok(ov.p?.tokens?.total); sub: app.fmtCost(ov.p?.cost) }
                Stat { width: (parent.width - 16) / 3; label: "OUTPUT"; value: app.fmtTok(ov.p?.tokens?.out); sub: "input " + app.fmtTok(ov.p?.tokens?.in); accent: app.stCol.running }
                Stat { width: (parent.width - 16) / 3; label: "CACHE ĐỌC"; value: app.fmtTok(ov.p?.tokens?.cacheRead); sub: "ghi " + app.fmtTok(ov.p?.tokens?.cacheWrite); accent: app.stCol.done }
            }
            // theo model
            Column {
                width: parent.width; spacing: 6
                readonly property var ms: Object.entries(ov.p?.models ?? {})
                readonly property real sum: Math.max(1, ms.reduce((a, m) => a + m[1], 0))
                SectionTitle { text: "THEO MODEL" }
                Row {
                    width: parent.width; height: 8
                    Repeater {
                        model: parent.parent.ms
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width * modelData[1] / parent.parent.sum; height: 8
                            color: app.modelCol(modelData[0])
                        }
                    }
                }
                Flow {
                    width: parent.width; spacing: 12
                    Repeater {
                        model: parent.parent.ms
                        delegate: Row {
                            required property var modelData
                            spacing: 5
                            Rectangle { width: 8; height: 8; radius: 4; color: app.modelCol(modelData[0]); anchors.verticalCenter: parent.verticalCenter }
                            T { text: modelData[0] + " " + app.fmtTok(modelData[1]); font.pixelSize: 11; color: app.muted }
                        }
                    }
                }
            }
            // 14 ngày
            Column {
                id: chart
                width: parent.width; spacing: 6
                property int hov: -1
                readonly property var days: ov.p?.daily ?? []
                readonly property real mx: Math.max(1, ...days.map(d => d.total))
                SectionTitle {
                    text: chart.hov >= 0 ? "NGÀY " + app.dayLabel(chart.days[chart.hov].day) + ": " + app.fmtTok(chart.days[chart.hov].total) + " token · out " + app.fmtTok(chart.days[chart.hov].out)
                                         : "TOKEN 14 NGÀY"
                }
                Row {
                    width: parent.width; height: 64; spacing: 3
                    Repeater {
                        model: chart.days
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: (parent.width - 3 * 13) / 14; height: 64
                            Rectangle {
                                anchors.bottom: parent.bottom; width: parent.width; radius: 2
                                height: Math.max(2, 64 * parent.modelData.total / chart.mx)
                                color: chart.hov === parent.index ? "white" : parent.index === 13 ? app.stCol.running : app.hueCol(ov.p?.key)
                                opacity: parent.modelData.total > 0 ? 0.9 : 0.25
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: chart.hov = parent.index; onExited: if (chart.hov === parent.index) chart.hov = -1 }
                        }
                    }
                }
                Row {
                    width: parent.width
                    T { text: app.dayLabel(chart.days[0]?.day); color: app.muted; font.pixelSize: 10; width: parent.width / 2 }
                    T { text: "hôm nay"; color: app.muted; font.pixelSize: 10; width: parent.width / 2; horizontalAlignment: Text.AlignRight }
                }
            }

            // tab
            Row {
                spacing: 6
                Repeater {
                    model: [["requests", "Yêu cầu", ov.p?.requests?.length ?? 0], ["tasks", "Task", ov.p?.tasks?.length ?? 0],
                            ["agents", "Agent", ov.p?.agents?.length ?? 0], ["sessions", "Phiên", ov.p?.sessions?.length ?? 0]]
                    delegate: Chip {
                        required property var modelData
                        text: modelData[1] + " " + modelData[2]
                        on: app.tab === modelData[0]
                        onClicked: { app.tab = modelData[0]; app.filter = "all"; app.expanded = ""; app.limit = 60; }
                    }
                }
            }
            // lọc trạng thái
            Flow {
                visible: app.tab !== "sessions"
                width: parent.width; spacing: 6
                Repeater {
                    model: [["all", "Tất cả", ov.list.length, app.fg], ["running", "Đang chạy", ov.cnt.running, app.stCol.running],
                            ["pending", "Chờ làm", ov.cnt.pending, app.stCol.pending], ["blocked", "Bị chặn", ov.cnt.blocked, app.stCol.blocked],
                            ["done", "Xong", ov.cnt.done, app.stCol.done], ["fail", "Lỗi/Dừng", ov.cnt.failed + ov.cnt.stopped, app.stCol.failed]]
                    delegate: Chip {
                        required property var modelData
                        small: true
                        dot: modelData[0] === "all" ? "transparent" : modelData[3]
                        text: modelData[1] + " " + modelData[2]
                        on: app.filter === modelData[0]
                        onClicked: { app.filter = modelData[0]; app.limit = 60; }
                    }
                }
            }
            T {
                visible: ov.shown.length === 0
                width: parent.width; wrapMode: Text.Wrap; color: app.muted; font.pixelSize: 12
                text: app.tab === "tasks" ? "Chưa có todo/task nào. Claude Code tạo task khi làm việc nhiều bước (TodoWrite / TaskCreate)."
                    : app.tab === "agents" ? "Chưa có subagent nào trong dự án này."
                    : "Không có mục nào khớp bộ lọc."
            }
            Column {
                width: parent.width; spacing: 6
                Repeater {
                    model: ov.shown.slice(0, app.limit)
                    delegate: ItemRow { width: parent.width }
                }
            }
            Chip {
                visible: ov.shown.length > app.limit
                text: "Xem thêm (" + (ov.shown.length - app.limit) + ")"
                onClicked: app.limit += 60
            }
        }
    }

    // ------------------------------------------------------------------ thành phần 2D
    // ---- thành phần kiểu AgentOps
    component Card: Rectangle {
        id: cd
        property string title
        property string count
        default property alias content: cbody.data
        color: Qt.rgba(0.043, 0.063, 0.114, 0.84); border.color: app.line; radius: 14
        MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: w => w.accepted = true }
        Item {
            id: chead
            width: parent.width; height: 38
            T { x: 13; anchors.verticalCenter: parent.verticalCenter; text: cd.title; font { family: app.sans; pixelSize: 13; bold: true } width: parent.width - 80; elide: Text.ElideRight }
            T { anchors { right: parent.right; rightMargin: 13; verticalCenter: parent.verticalCenter } text: cd.count; color: app.muted; font.pixelSize: 11 }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.line }
        }
        Item { id: cbody; y: 38; width: parent.width; height: parent.height - 38; clip: true }
    }
    component Kpi: Rectangle {
        id: kp
        property string label
        property string value
        property bool warn: false
        width: Math.max(kpL.implicitWidth, kpV.implicitWidth) + 22; height: 44; radius: 10
        color: Qt.rgba(0.06, 0.09, 0.16, 0.55); border.color: app.line
        Column {
            anchors.centerIn: parent; spacing: 1
            T { id: kpL; text: kp.label.toUpperCase(); color: app.muted; font { pixelSize: 9; letterSpacing: 0.6 } }
            T { id: kpV; text: kp.value; color: kp.warn && kp.value !== "0" ? "#facc15" : app.fg; font { pixelSize: 14; bold: true } }
        }
    }
    component Btn: Rectangle {
        id: bt
        property string text
        property bool on: false
        signal clicked
        width: btT.implicitWidth + 22; height: 30; radius: 8
        color: on ? Qt.rgba(0.22, 0.74, 0.97, 0.18) : btm.containsMouse ? Qt.rgba(0.2, 0.25, 0.33, 0.8) : Qt.rgba(0.12, 0.16, 0.23, 0.6)
        border.color: on ? Qt.rgba(0.22, 0.74, 0.97, 0.5) : Qt.rgba(0.58, 0.64, 0.72, 0.24)
        T { id: btT; anchors.centerIn: parent; text: bt.text; color: bt.on ? "#e0f2fe" : app.fg; font { family: app.sans; pixelSize: 12 } }
        MouseArea { id: btm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bt.clicked() }
    }
    component PjChip: Rectangle {
        id: pj
        property string text
        property string sub
        property int badge: 0
        property color col: app.fg
        property bool on: false
        property bool off: false            // dự án đang bị ẩn (đảo không hiện trong cảnh)
        property bool toggleable: false
        signal clicked
        signal toggled
        opacity: off ? 0.5 : 1
        width: pjRow.implicitWidth + (toggleable ? 38 : 22); height: 30; radius: 10
        color: on ? Qt.rgba(0.12, 0.16, 0.23, 0.92) : Qt.rgba(0.03, 0.05, 0.09, 0.78)
        border.width: on ? 2 : 1
        border.color: on ? pj.col : pjm.containsMouse ? Qt.rgba(0.58, 0.64, 0.72, 0.45) : Qt.rgba(0.58, 0.64, 0.72, 0.24)
        Row {
            id: pjRow
            x: 11; anchors.verticalCenter: parent.verticalCenter; spacing: 7
            Rectangle { width: 9; height: 9; radius: 3; color: pj.col; anchors.verticalCenter: parent.verticalCenter }
            T { text: pj.text; font { family: app.sans; pixelSize: 12; weight: Font.Medium; strikeout: pj.off } }
            T { visible: pj.sub !== ""; text: pj.sub; color: app.muted; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                visible: pj.badge > 0; width: 16; height: 16; radius: 8; color: "#facc15"; anchors.verticalCenter: parent.verticalCenter
                T { anchors.centerIn: parent; text: "" + pj.badge; color: "#1a1300"; font { pixelSize: 9; bold: true } }
            }
        }
        MouseArea { id: pjm; anchors.fill: parent; hoverEnabled: !pj.off; cursorShape: pj.off ? Qt.ArrowCursor : Qt.PointingHandCursor; onClicked: pj.clicked() }
        // nút mắt: ẩn / hiện đảo của dự án
        Rectangle {
            visible: pj.toggleable
            x: parent.width - width - 3; anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 7
            color: eyem.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
            T { anchors.centerIn: parent; text: pj.off ? "◌" : "◉"; color: pj.off ? app.muted : pj.col; font.pixelSize: 14 }
            MouseArea { id: eyem; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pj.toggled() }
        }
    }
    // một dòng agent ở danh sách trái: robot nhỏ, tên phiên, trạng thái, đang làm gì, thanh token
    component AgentRow: Rectangle {
        id: ar
        required property var modelData
        readonly property var s: modelData.s
        readonly property color sc: app.ssCol[s.state] ?? app.muted
        readonly property bool hl: app.hlSession === s.id
        height: arCol.implicitHeight + 14; radius: 9
        color: hl ? Qt.rgba(0.22, 0.74, 0.97, 0.10) : arm.containsMouse ? Qt.rgba(0.2, 0.25, 0.33, 0.35) : "transparent"
        border.color: hl ? Qt.rgba(0.22, 0.74, 0.97, 0.35) : "transparent"
        Rectangle {
            id: arAv
            x: 7; y: 7; width: 26; height: 26; radius: 8; color: Qt.rgba(0.06, 0.09, 0.16, 0.8); border.color: Qt.rgba(0.58, 0.64, 0.72, 0.24)
            Rectangle {
                anchors.centerIn: parent; width: 18; height: 14; radius: 5; color: app.modelCol(ar.s.model)
                Rectangle {
                    anchors.centerIn: parent; width: 13; height: 7; radius: 3; color: "#0f1115"
                    Row { anchors.centerIn: parent; spacing: 3; Repeater { model: 2; delegate: Rectangle { width: 2.5; height: ar.s.state === "idle" ? 2 : 3.5; radius: 1; color: ar.sc } } }
                }
            }
        }
        Column {
            id: arCol
            x: 41; y: 7; width: parent.width - 49; spacing: 2
            Row {
                width: parent.width; spacing: 6
                T { width: parent.width - arPill.width - 6; text: ar.s.title || "(phiên mới)"; font { family: app.sans; pixelSize: 12; bold: true } elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                Pill { id: arPill; text: app.ssName[ar.s.state] ?? ""; col: ar.sc; height: 17; anchors.verticalCenter: parent.verticalCenter }
            }
            T {
                width: parent.width; elide: Text.ElideRight; color: ar.s.state === "waiting" ? "#fde68a" : app.muted; font { family: app.sans; pixelSize: 11 }
                text: ar.s.doing ? app.verbOf(ar.s.doing.tool) + ": " + ar.s.doing.text : (ar.s.lastText || ar.s.model || "")
            }
            T { width: parent.width; elide: Text.ElideRight; color: app.dim; font.pixelSize: 10; text: (app.selP ? "" : modelData.p.name + " · ") + (ar.s.model ?? "") + " · " + app.fmtTok(ar.s.tokens?.total) + " tok · " + app.ago(ar.s.mtime) }
            Rectangle {
                width: parent.width; height: 3; radius: 2; color: Qt.rgba(0.58, 0.64, 0.72, 0.15)
                Rectangle { width: Math.max(2, parent.width * (ar.s.tokens?.total ?? 0) / app.agMaxTok); height: 3; radius: 2; color: ar.sc }
            }
        }
        MouseArea { id: arm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: app.pickSession(ar.modelData.pi, ar.s.id) }
    }

    component T: Text {
        color: app.fg
        font.family: app.mono
        font.pixelSize: 12
    }
    component Panel: Rectangle {
        color: Qt.rgba(0.07, 0.08, 0.1, 0.82)
        border.color: app.line
        radius: 9
    }
    component SectionTitle: T {
        color: app.muted
        font { pixelSize: 11; bold: true; letterSpacing: 1.5 }
    }
    component IconBtn: Rectangle {
        id: ib
        property string text
        signal clicked
        width: 26; height: 26; radius: 6
        color: ibm.containsMouse ? "#262a33" : "transparent"
        T { anchors.centerIn: parent; text: ib.text; color: app.muted }
        MouseArea { id: ibm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }
    component Chip: Rectangle {
        id: ch
        property string text
        property bool on: false
        property bool small: false
        property color dot: "transparent"
        signal clicked
        width: chRow.implicitWidth + (small ? 16 : 20); height: small ? 24 : 28; radius: height / 2
        color: on ? "#2b3140" : chm.containsMouse ? "#1f232b" : app.card
        border.color: on ? Qt.rgba(1, 1, 1, 0.25) : app.line
        Row {
            id: chRow
            anchors.centerIn: parent; spacing: 6
            Rectangle { visible: ch.dot.a > 0; width: 7; height: 7; radius: 4; color: ch.dot; anchors.verticalCenter: parent.verticalCenter }
            T { text: ch.text; font.pixelSize: ch.small ? 11 : 12; color: ch.on ? "white" : app.fg }
        }
        MouseArea { id: chm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }
    component Pill: Rectangle {
        id: pl
        property string text
        property color col: app.muted
        width: plT.implicitWidth + 16; height: 20; radius: 10
        color: Qt.rgba(col.r, col.g, col.b, 0.18)
        border.color: Qt.rgba(col.r, col.g, col.b, 0.6)
        T { id: plT; anchors.centerIn: parent; text: pl.text; color: pl.col; font { pixelSize: 11; bold: true } }
    }
    component Stat: Rectangle {
        id: sx
        property string label
        property string value
        property string sub
        property color accent: app.fg
        height: 70; radius: 8; color: app.card
        Column {
            x: 10; y: 8; width: parent.width - 20; spacing: 2
            T { text: sx.label; color: app.muted; font { pixelSize: 10; bold: true; letterSpacing: 1 } width: parent.width; elide: Text.ElideRight }
            T { text: sx.value; color: sx.accent; font { family: app.sans; pixelSize: 21; bold: true } }
            T { text: sx.sub; color: app.muted; font.pixelSize: 10; width: parent.width; elide: Text.ElideRight }
        }
    }
    component StatusRow: Flow {
        id: sr
        property var counts: ({})
        spacing: 6
        Repeater {
            model: ["running", "pending", "blocked", "done", "failed", "stopped"]
            delegate: Pill {
                required property string modelData
                text: app.stName[modelData] + " " + (sr.counts[modelData] ?? 0)
                col: app.stCol[modelData]
                opacity: (sr.counts[modelData] ?? 0) > 0 ? 1 : 0.45
            }
        }
    }
    // "▸ [Sửa] cart.ts · 5s"
    component DoingLine: Row {
        id: dl
        property var doing: null
        property bool waiting: false
        visible: doing !== null && doing !== undefined
        spacing: 7
        Rectangle {
            width: dlT.implicitWidth + 12; height: 18; radius: 4
            color: dl.waiting ? app.ssCol.waiting : app.verbCol(dl.doing?.tool)
            T { id: dlT; anchors.centerIn: parent; text: dl.waiting ? "CHỜ DUYỆT " + (dl.doing?.tool ?? "") : app.verbOf(dl.doing?.tool); color: "#111318"; font { pixelSize: 10; bold: true } }
        }
        T {
            width: dl.width - dlT.implicitWidth - 19; anchors.verticalCenter: parent.verticalCenter
            text: (dl.doing?.text ?? "") + (dl.doing?.ts ? "  · " + app.ago(dl.doing.ts) : "")
            color: app.fg; font { family: app.sans; pixelSize: 12 } elide: Text.ElideRight
        }
    }
    // thẻ một agent (phiên) đang mở: yêu cầu hiện tại, đang làm gì, subagent, nhật ký hành động
    component ActiveCard: Rectangle {
        id: ac
        property var entry: ({})
        property bool showProject: true
        property int logN: 0
        readonly property var s: entry.s ?? ({})
        readonly property color sc: app.ssCol[s.state] ?? app.muted
        readonly property bool hl: app.hlSession === s.id
        readonly property var subs: (entry.p?.agents ?? []).filter(a => a.session === s.id && a.status === "running")
        height: acCol.implicitHeight + 18; radius: 9
        color: acm.containsMouse ? "#1d2129" : app.card
        border.width: hl ? 2 : 1
        border.color: hl ? "white" : Qt.rgba(sc.r, sc.g, sc.b, 0.4)
        Rectangle { x: 0; y: 9; width: 3; height: parent.height - 18; radius: 2; color: ac.sc }
        MouseArea { id: acm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: app.pickSession(ac.entry.pi, ac.s.id) }
        Column {
            id: acCol
            x: 13; y: 9; width: parent.width - 24; spacing: 5
            Row {
                width: parent.width; spacing: 8
                // "mặt robot" mini: màu model, mắt màu trạng thái
                Rectangle {
                    width: 22; height: 18; radius: 7; color: app.modelCol(ac.s.model); anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.centerIn: parent; width: 16; height: 9; radius: 4; color: "#0f1115"
                        Row {
                            anchors.centerIn: parent; spacing: 4
                            Repeater { model: 2; delegate: Rectangle { width: 3; height: ac.s.state === "idle" ? 2 : 4; radius: 1; color: ac.sc } }
                        }
                    }
                }
                T {
                    width: parent.width - 30 - acPill.width - 8
                    text: (ac.showProject ? (ac.entry.pi + 1) + " " + (ac.entry.p?.name ?? "") + " · " : "") + (ac.s.title || "(phiên mới)")
                    font { family: app.sans; pixelSize: 13; bold: true } elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }
                Pill { id: acPill; text: app.ssName[ac.s.state] ?? ""; col: ac.sc; anchors.verticalCenter: parent.verticalCenter }
            }
            T {
                visible: !!ac.s.current
                width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                text: "Yêu cầu: " + (ac.s.current ?? "")
                color: "#c3c7cf"; font { family: app.sans; pixelSize: 12 }
            }
            DoingLine { width: parent.width; doing: ac.s.doing ?? null; waiting: ac.s.state === "waiting" }
            T {
                visible: !ac.s.doing && !!ac.s.lastText
                width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                text: (ac.s.state === "idle" ? "Xong lượt, đang chờ bạn · " : "Lần cuối: ") + (ac.s.lastText ?? "")
                color: app.muted; font { family: app.sans; pixelSize: 11 }
            }
            // subagent đang chạy của phiên này
            Repeater {
                model: ac.subs
                delegate: Row {
                    required property var modelData
                    width: acCol.width; spacing: 6
                    T { text: "↳"; color: "#6ea0f0"; font.pixelSize: 12 }
                    Rectangle {
                        width: sbT.implicitWidth + 10; height: 17; radius: 4; color: Qt.rgba(0.43, 0.63, 0.94, 0.2)
                        T { id: sbT; anchors.centerIn: parent; text: modelData.type; color: "#6ea0f0"; font { pixelSize: 10; bold: true } }
                    }
                    T {
                        width: acCol.width - sbT.implicitWidth - 40
                        text: modelData.title + (modelData.doing ? " — " + app.verbOf(modelData.doing.tool) + ": " + modelData.doing.text : "")
                        color: app.fg; font { family: app.sans; pixelSize: 11 } elide: Text.ElideRight
                    }
                }
            }
            T {
                text: [ac.s.model, "lượt này " + app.fmtTok(ac.s.turnTok) + " tok", ac.s.currentTs ? "bắt đầu " + app.ago(ac.s.currentTs) : "",
                       "tổng " + app.fmtTok(ac.s.tokens?.total)].filter(x => x).join(" · ")
                color: app.muted; font.pixelSize: 10; width: parent.width; elide: Text.ElideRight
            }
            // nhật ký hành động gần nhất
            Column {
                visible: ac.logN > 0 && (ac.s.activity ?? []).length > 0
                width: parent.width; spacing: 3
                Rectangle { width: parent.width; height: 1; color: app.line }
                Repeater {
                    model: (ac.s.activity ?? []).slice(0, ac.logN)
                    delegate: Row {
                        required property var modelData
                        width: acCol.width; spacing: 6
                        Rectangle {
                            width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter
                            color: modelData.st === "err" ? app.stCol.failed : modelData.st === "run" ? app.stCol.running : modelData.st === "stop" ? app.stCol.stopped : app.stCol.done
                        }
                        T { text: Qt.formatDateTime(new Date(modelData.ts * 1000), "HH:mm:ss"); color: app.muted; font.pixelSize: 10; width: 52; anchors.verticalCenter: parent.verticalCenter }
                        T { text: app.verbOf(modelData.tool); color: app.verbCol(modelData.tool); font { pixelSize: 10; bold: true } width: 72; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                        T { text: modelData.text; color: "#b9bec8"; font.pixelSize: 10; width: acCol.width - 148; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }

    // một dòng việc (yêu cầu / todo / task / agent / quyền / phiên); click để mở chi tiết
    component ItemRow: Rectangle {
        id: ir
        required property var modelData
        property bool showProject: false
        signal picked
        readonly property bool open: app.expanded === modelData.id
        readonly property color sc: modelData.kind === "session" ? (app.ssCol[modelData.state] ?? app.muted) : (app.stCol[modelData.status] ?? app.muted)
        height: irCol.implicitHeight + 16; radius: 8
        color: open ? "#1e222b" : irm.containsMouse ? "#1b1f26" : app.card
        border.color: open ? Qt.rgba(sc.r, sc.g, sc.b, 0.5) : "transparent"
        Rectangle { x: 0; y: 8; width: 3; height: parent.height - 16; radius: 2; color: ir.sc }
        Column {
            id: irCol
            x: 12; y: 8; width: parent.width - 22; spacing: 4
            Row {
                width: parent.width; spacing: 7
                Rectangle {
                    width: kT.implicitWidth + 10; height: 17; radius: 4; anchors.top: parent.top; anchors.topMargin: 1
                    color: Qt.rgba(ir.sc.r, ir.sc.g, ir.sc.b, 0.16)
                    T { id: kT; anchors.centerIn: parent; text: app.kindName[ir.modelData.kind] ?? ir.modelData.kind; color: ir.sc; font { pixelSize: 9; bold: true } }
                }
                T {
                    width: parent.width - kT.implicitWidth - 17
                    text: (ir.showProject ? "[" + ir.modelData.pname + "] " : "") + (ir.modelData.title || "(không tiêu đề)")
                    font { family: app.sans; pixelSize: 13 }
                    wrapMode: ir.open ? Text.Wrap : Text.NoWrap
                    elide: ir.open ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: ir.open ? 6 : 1
                }
            }
            T { text: app.metaOf(ir.modelData); color: app.muted; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
            // chi tiết
            Column {
                visible: ir.open
                width: parent.width; spacing: 6
                Rectangle { width: parent.width; height: 1; color: app.line }
                T {
                    visible: text !== "" && text !== ir.modelData.title
                    text: ir.modelData.detail ?? ""
                    width: parent.width; wrapMode: Text.Wrap; font { family: app.sans; pixelSize: 12 } color: "#c3c7cf"; lineHeight: 1.2
                }
                T {
                    visible: !!ir.modelData.result
                    text: "Kết quả: " + (ir.modelData.result ?? "")
                    width: parent.width; wrapMode: Text.Wrap; font { family: app.sans; pixelSize: 12 } color: "#a8b4c8"; lineHeight: 1.2
                }
                Flow {
                    visible: Object.keys(ir.modelData.tools ?? {}).length > 0
                    width: parent.width; spacing: 5
                    Repeater {
                        model: Object.entries(ir.modelData.tools ?? {})
                        delegate: Pill { required property var modelData; text: modelData[0].replace(/^mcp__[^_]+__/, "") + " ×" + modelData[1]; col: "#9aa3b5" }
                    }
                }
                Repeater {
                    model: ir.modelData.files ?? []
                    delegate: T { required property string modelData; text: "✎ " + modelData.split("/").slice(-3).join("/"); color: "#9fc4a8"; font.pixelSize: 11; width: ir.width - 30; elide: Text.ElideMiddle }
                }
                T {
                    text: {
                        const m = ir.modelData;
                        const a = [];
                        if (m.kind === "session") {
                            a.push("bắt đầu " + app.clock(m.start), "cập nhật " + app.clock(m.mtime));
                            if (m.cost) a.push(app.fmtCost(m.cost));
                            if (m.branch) a.push(" " + m.branch);
                            a.push("in " + app.fmtTok(m.tokens?.in) + " · out " + app.fmtTok(m.tokens?.out) + " · cache " + app.fmtTok(m.tokens?.cacheRead) + "/" + app.fmtTok(m.tokens?.cacheWrite));
                            if (m.waitingTool) a.push("đang chờ duyệt: " + m.waitingTool);
                        } else {
                            if (m.ts) a.push("lúc " + app.clock(m.ts));
                            if (m.end && m.end > m.ts) a.push("xong " + app.clock(m.end));
                            if (m.agents) a.push(m.agents + " subagent");
                            if (m.owner) a.push("owner " + m.owner);
                            if (m.out) a.push("output " + app.fmtTok(m.out));
                            if (m.tools && typeof m.tools === "number") a.push(m.tools + " lần gọi tool");
                        }
                        a.push("phiên " + (m.session ?? m.id ?? "").slice(0, 8));
                        return a.join("\n");
                    }
                    color: app.muted; font.pixelSize: 11; width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2
                }
            }
        }
        MouseArea {
            id: irm
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: { if (ir.showProject) ir.picked(); else app.expanded = ir.open ? "" : ir.modelData.id; }
        }
    }
}
