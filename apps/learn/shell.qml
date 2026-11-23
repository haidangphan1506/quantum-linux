import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Quantum Learn: app học khoá VPS Linux (dữ liệu + shell mô phỏng lấy từ dự án course-vps).
// App độc lập (tiến trình Quickshell riêng, giống Quantum Store): mở bằng launcher `quantum-learn`.
// Giao diện: nền giấy kem, font JetBrains Mono, viền mực + bóng đổ cứng, màu nhấn pastel.
// Mỗi bài = chuỗi bước: các thẻ lý thuyết → Quiz → Thực hành (terminal) → Fix lỗi.
// backend.mjs (Node) nạp engine của khoá học, chạy lệnh trong shell mô phỏng và chấm bài;
// nói chuyện qua stdin/stdout (JSON từng dòng). Tiến độ: ~/.local/state/quantum/learn.json.
// IPC: qs -p …/apps/learn/shell.qml ipc call learn open <lessonId> | step <n> | view <learn|results> | theme | state
ShellRoot {
    id: app

    readonly property string dir: Quickshell.shellDir

    // ------------------------------------------------------------------ ajustes del shell (solo lectura)
    property var settings: ({})
    property var colors: ({})
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quantum/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { app.settings = JSON.parse(text()); } catch (e) {} }
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quantum/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { app.colors = JSON.parse(text()); } catch (e) {} }
    }

    // ------------------------------------------------------------------ bảng màu (giấy kem / mực)
    property string themeOverride: ""   // "" = theo hệ thống, "light" | "dark" = người dùng chọn
    readonly property bool systemDark: (colors.mode ?? settings.appearance?.mode ?? "light") !== "light"
    readonly property bool dark: themeOverride !== "" ? themeOverride === "dark" : systemDark

    readonly property color paper: dark ? "#211e1a" : "#f4ebe0"
    readonly property color paper2: dark ? "#24201c" : "#f7efe4"
    readonly property color sheet: dark ? "#28241f" : "#f9f2e8"
    readonly property color card: dark ? "#26231e" : "#f8f0e6"
    readonly property color cardHi: dark ? "#2d2923" : "#fbf7f1"
    readonly property color line: dark ? "#342f28" : "#ddd3c5"
    readonly property color lineSoft: dark ? "#2e2a24" : "#e6ddd0"
    readonly property color lineStrong: dark ? "#4f473d" : "#c6bbac"
    readonly property color ink: dark ? "#efe6d6" : "#1d1b18"
    readonly property color ink2: dark ? "#ddd3c2" : "#34302b"
    readonly property color muted: dark ? "#a3998b" : "#6f6961"
    readonly property color muted2: dark ? "#8a8174" : "#8b847a"
    readonly property color green: dark ? "#3f4c2b" : "#cfe3b2"
    readonly property color green3: "#7fc278"
    readonly property color greenInk: dark ? "#9fd38f" : "#2a6b35"
    readonly property color greenTile: dark ? "#2b3320" : "#e8efd9"
    readonly property color greenTileLine: dark ? "#3d4a2c" : "#c9d6b3"
    readonly property color violet: dark ? "#493563" : "#e7ddf5"
    readonly property color violetTile: dark ? "#30263c" : "#ebe3f1"
    readonly property color violetTileLine: dark ? "#4a3a5e" : "#d5c8e2"
    readonly property color orange: dark ? "#5a4531" : "#f6e6c9"
    readonly property color orangeTile: dark ? "#3a2f22" : "#fbeedd"
    readonly property color orangeTileLine: dark ? "#5c4831" : "#ebcfa6"
    readonly property color red: dark ? "#5a2c26" : "#f8d5cf"
    readonly property color redInk: dark ? "#ffb4a8" : "#7d241d"
    readonly property color redTile: dark ? "#3b2420" : "#fbe5e0"
    readonly property color redTileLine: dark ? "#613a33" : "#e9b8ae"
    readonly property color mint: dark ? "#2c3a2b" : "#dff0de"
    readonly property color rust: "#d0683a"
    readonly property color codeBg: dark ? "#15130f" : "#1d1b18"
    readonly property color codeInk: "#efe6d6"
    readonly property color drop: dark ? "#050403" : "#1d1b18"
    readonly property string mono: "JetBrains Mono"
    readonly property string iconFont: "Material Symbols Rounded"
    readonly property var groupColors: ["#d9b98f", "#7fc278", "#9b7fd1", "#e08a4f", "#4f8fd6", "#2a9d8f", "#d9576b", "#9aa64a", "#6b7a8f"]

    // ------------------------------------------------------------------ dữ liệu
    property var lessons: []
    property var groups: []             // [{ name, color, num, idx: [chỉ số bài] }]
    property string ip: ""
    property bool loaded: false
    property string loadError: ""

    // Tiến độ (cùng cấu trúc với store Redux của bản web). Đối tượng JS: sửa xong gọi touch().
    property var prog: ({ labs: {}, quiz: {}, debugs: {}, wrong: {}, flag: {}, hist: [], cur: "", step: 0, ui: {} })
    property int rev: 0
    function touch(): void { rev++; saveTimer.restart(); }
    Timer { id: saveTimer; interval: 500; onTriggered: app.saveNow(null) }
    property real savedAt: 0
    function saveNow(after: var): void {
        saveTimer.stop();
        call("save", { data: prog }, r => {
            if (r.ok) savedAt = r.savedAt;
            else toast("Không lưu được tiến độ: " + r.error, true);
            if (after) after();
        });
    }
    // Đóng app: lưu nốt rồi mới thoát (tối đa 1,5 s nếu backend không trả lời).
    function quit(): void {
        saveNow(() => Qt.quit());
        quitTimer.start();
    }
    Timer { id: quitTimer; interval: 1500; onTriggered: Qt.quit() }
    function clock(t: real): string {
        const d = new Date(t), p = n => String(n).padStart(2, "0");
        return `${p(d.getHours())}:${p(d.getMinutes())}`;
    }
    function dateTime(t: real): string {
        const d = new Date(t), p = n => String(n).padStart(2, "0");
        return `${p(d.getDate())}/${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
    }
    function normalize(d: var): var {
        for (const k of ["labs", "quiz", "debugs", "wrong", "flag"]) d[k] = d[k] || {};
        d.hist = d.hist || [];
        d.ui = d.ui || {};
        return d;
    }

    // ------------------------------------------------------------------ sao lưu / xuất báo cáo
    property var backupList: []
    property string exportDir: ""
    property string lastExport: ""
    function loadBackups(): void {
        call("backups", {}, r => { if (r.ok) { backupList = r.list; exportDir = r.dir; } });
    }
    function exportReport(): void {
        saveNow(null);
        call("export", { data: prog }, r => {
            if (!r.ok) { toast("Không xuất được: " + r.error, true); return; }
            lastExport = r.md;
            toast("Đã xuất báo cáo vào " + r.dir.replace(Quickshell.env("HOME"), "~"), false);
            loadBackups();
        });
    }
    function openExportDir(): void {
        if (exportDir) Quickshell.execDetached(["xdg-open", exportDir]);
    }
    function restoreFrom(path: string): void {
        call("restore", { path: path, data: prog }, r => {
            if (!r.ok) { toast("Không khôi phục được: " + r.error, true); return; }
            prog = normalize(r.data);
            touch();
            toast("Đã gộp kết quả từ bản sao lưu", false);
        });
    }

    // ------------------------------------------------------------------ thông báo nhỏ
    property string toastText: ""
    property bool toastError: false
    function toast(t: string, err: bool): void { toastText = t; toastError = err; toastTimer.restart(); }
    Timer { id: toastTimer; interval: 4000; onTriggered: app.toastText = "" }

    // ------------------------------------------------------------------ nút cửa sổ (đỏ / vàng / xanh)
    // App tự vẽ header nên không có thanh hyprbars: nút gọi thẳng các hàm cửa sổ của Hyprland
    // (config/hypr/hyprlands/minimize.lua), áp cho cửa sổ đang focus (chính app khi vừa bấm).
    function winAction(a: string): void {
        if (a === "close") quit();
        else if (a === "min") Quickshell.execDetached(["hyprctl", "eval", "cael_minimize('')"]);
        else Quickshell.execDetached(["hyprctl", "eval", "cael_toggle_size('')"]);
    }

    // điều hướng
    property int cur: 0
    property int step: 0
    property string view: "learn"       // learn | results
    property bool menuOpen: false
    readonly property var lesson: lessons.length ? lessons[cur] : null
    readonly property var steps: lesson ? stepsOf(lesson) : []
    readonly property var curStep: steps.length ? steps[Math.min(step, steps.length - 1)] : null

    function go(i: int, s: int): void {
        if (i < 0 || i >= lessons.length) return;
        cur = i;
        step = Math.max(0, Math.min(s, stepsOf(lessons[i]).length - 1));
        view = "learn";
        prog.cur = lessons[i].id;
        prog.step = step;
        saveTimer.restart();
    }
    function goId(id: string, s: int): void {
        const i = lessons.findIndex(l => l.id === id);
        if (i >= 0) go(i, s);
    }

    // ------------------------------------------------------------------ backend (Node)
    property int seq: 0
    property var pending: ({})
    function call(op: string, args: var, cb: var): void {
        const id = ++seq;
        if (cb) pending[id] = cb;
        backend.write(JSON.stringify(Object.assign({ id: id, op: op }, args || {})) + "\n");
    }
    function onMessage(data: string): void {
        let m;
        try { m = JSON.parse(data); } catch (e) { console.warn("learn: JSON lỗi từ backend"); return; }
        if (m.ev) { onEvent(m); return; }
        const cb = pending[m.id];
        delete pending[m.id];
        if (cb) cb(m);
        else if (!m.ok) console.warn("learn:", m.error);
    }
    Process {
        id: backend
        command: ["node", "--no-warnings", app.dir + "/backend.mjs"]
        running: true
        stdinEnabled: true
        stdout: SplitParser { onRead: data => app.onMessage(data) }
        stderr: SplitParser { onRead: data => console.warn("learn backend:", data) }
        onStarted: {
            app.call("load", {}, r => {
                if (r.ok && r.data) {
                    const d = app.normalize(r.data);
                    app.prog = d;
                    app.themeOverride = d.ui.theme || "";
                }
                app.call("catalog", {}, c => {
                    if (!c.ok) { app.loadError = c.error; return; }
                    app.ip = c.ip;
                    app.lessons = c.lessons;
                    app.groups = app.groupLessons(c.lessons);
                    app.loaded = true;
                    const i = Math.max(0, c.lessons.findIndex(l => l.id === app.prog.cur));
                    app.cur = i;
                    app.step = Math.max(0, Math.min(app.prog.step || 0, app.stepsOf(c.lessons[i]).length - 1));
                    const open = Quickshell.env("QS_LEARN_OPEN") ?? "";
                    if (open) app.goId(open, 0);
                });
            });
        }
        onExited: (code, status) => {
            if (!app.loaded) app.loadError = app.loadError || "Không chạy được backend (cần cài nodejs).";
        }
    }

    // ------------------------------------------------------------------ tiện ích dữ liệu
    function plain(s: string): string { return (s || "").replace(/[`*]/g, ""); }
    function fold(s: string): string {
        let t = plain(s).toLowerCase().replace(/đ/g, "d");
        if (typeof t.normalize === "function") t = t.normalize("NFD").replace(/[̀-ͯ]/g, "");
        return t;
    }
    function esc(s: string): string { return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    // Markdown rút gọn → RichText: `code` và **đậm**.
    function md(s: string): string {
        void app.dark;
        return (s || "").split(/(`[^`]+`|\*\*[^*]+\*\*)/g).map(p => {
            if (p.length > 2 && p[0] === "`" && p[p.length - 1] === "`")
                return `<span style="background-color:${app.dark ? "#3a342c" : "#eadfce"}; color:${app.dark ? "#f0b892" : "#8a3a17"}">&#8202;${app.esc(p.slice(1, -1))}&#8202;</span>`;
            if (p.length > 4 && p.startsWith("**") && p.endsWith("**")) return `<b>${app.esc(p.slice(2, -2))}</b>`;
            return app.esc(p);
        }).join("").replace(/\n/g, "<br>");
    }

    function groupLessons(ls: var): var {
        const out = [], by = {};
        ls.forEach((l, i) => {
            let g = by[l.group];
            if (!g) {
                g = { name: l.group, color: groupColors[out.length % groupColors.length], num: String(out.length + 1).padStart(2, "0"), idx: [] };
                by[l.group] = g;
                out.push(g);
            }
            g.idx.push(i);
        });
        return out;
    }
    function groupOf(l: var): var { return groups.find(g => g.name === l.group) ?? null; }

    function stepsOf(l: var): var {
        const st = l.theory.map((c, i) => {
            const t = plain(c.title);
            const head = t.split(/[:—(]/)[0].trim() || t;
            return { kind: "theory", card: i, label: head.length > 18 ? head.slice(0, 17).trim() + "…" : head, title: t };
        });
        if (l.quiz.length) st.push({ kind: "quiz", card: -1, label: "Quiz", title: "Kiểm tra nhanh" });
        if (l.lab.items.length) st.push({ kind: "lab", card: -1, label: "Thực hành", title: "Thực hành trên container Linux thật" });
        if (l.debugs.length) st.push({ kind: "debug", card: -1, label: "Fix lỗi", title: "Tìm và sửa sự cố" });
        return st;
    }
    // Thẻ lý thuyết: đoạn mở đầu (panel phải), ý chính (ghi chú đầu tiên), phần còn lại (khung giữa).
    function splitCard(body: var): var {
        const lead = typeof body[0] === "string" ? body[0] : null;
        const keyAt = body.findIndex(b => typeof b === "object" && b.note !== undefined);
        const rest = body.filter((b, i) => !(i === 0 && lead !== null) && i !== keyAt);
        return { lead: lead, key: keyAt >= 0 ? body[keyAt] : null, rest: rest.length ? rest : (lead ? [lead] : []) };
    }
    function estimate(l: var): int {
        return Math.max(5, Math.round((l.theory.length * 3 + l.quiz.length + l.lab.items.length * 1.5 + l.debugs.length * 5) / 5) * 5);
    }

    function labDone(l: var): int { void rev; const a = prog.labs[l.id] || []; return l.lab.items.filter((x, i) => a[i]).length; }
    function quizDone(l: var): int { void rev; const q = prog.quiz[l.id] || {}; return l.quiz.filter((x, i) => q[i] === x.ans).length; }
    function debugDone(l: var): int { void rev; return l.debugs.filter(d => prog.debugs[d.id]).length; }
    function total(l: var): int { return l.lab.items.length + l.quiz.length + l.debugs.length; }
    function done(l: var): int { return labDone(l) + quizDone(l) + debugDone(l); }
    function stepDone(s: var, i: int): bool {
        if (!lesson) return false;
        if (s.kind === "theory") return i < step;
        if (s.kind === "quiz") return quizDone(lesson) === lesson.quiz.length;
        if (s.kind === "lab") return labDone(lesson) === lesson.lab.items.length;
        return debugDone(lesson) === lesson.debugs.length;
    }

    // quiz
    function answer(l: var, qi: int, oi: int): void {
        const ans = prog.quiz[l.id] = prog.quiz[l.id] || {};
        if (ans[qi] !== undefined) return;
        ans[qi] = oi;
        if (oi !== l.quiz[qi].ans) {
            const w = prog.wrong[l.id] = prog.wrong[l.id] || {};
            w[qi] = (w[qi] || 0) + 1;
            (prog.flag[l.id] = prog.flag[l.id] || {})[qi] = true;
        }
        if (l.quiz.every((x, j) => ans[j] !== undefined)) {
            prog.hist.push({ l: l.id, s: l.quiz.filter((x, j) => ans[j] === x.ans).length, n: l.quiz.length, t: Date.now() });
            if (prog.hist.length > 300) prog.hist = prog.hist.slice(-300);
        }
        touch();
    }
    function resetQuiz(l: var): void { prog.quiz[l.id] = {}; touch(); }

    // ------------------------------------------------------------------ terminal THẬT (container docker/kiri, ở backend)
    property string activeTerm: ""      // terminal đang hiện (để IPC run gửi lệnh vào)
    property var terms: ({})            // key → { status, error, note, snap, opts, rows, cols }
    property int termRev: 0
    function openTerm(key: string, opts: var, rows: int, cols: int): void {
        const old = terms[key];
        if (old && old.status !== "error" && old.status !== "exit") return;
        terms[key] = { status: "starting", error: "", note: "", snap: null, opts: opts, rows: rows, cols: cols };
        termRev++;
        call("ropen", { key: key, lesson: opts.lesson, debug: opts.debug || "", passed: prog.labs[opts.lesson] || [], rows: rows, cols: cols }, r => {
            const s = terms[key];
            if (!s) return;
            if (r.ok) { if (s.status === "starting") s.status = "run"; s.note = ""; }
            else { s.status = "error"; s.error = r.error; }
            termRev++;
        });
    }
    function termInput(key: string, text: string): void { if (text) call("rinput", { key: key, text: text }); }
    function termResize(key: string, rows: int, cols: int): void {
        const s = terms[key];
        if (!s || (s.rows === rows && s.cols === cols)) return;
        s.rows = rows; s.cols = cols;
        call("rresize", { key: key, rows: rows, cols: cols });
    }
    function termReset(key: string): void {
        const s = terms[key];
        if (!s) return;
        const o = s.opts, rows = s.rows, cols = s.cols;
        delete terms[key];
        termRev++;
        call("reset", { key: key }, () => openTerm(key, o, rows, cols));
    }
    function onEvent(m: var): void {
        const s = terms[m.key];
        if (!s) return;
        if (m.ev === "screen") { s.snap = m; if (s.status === "starting") s.status = "run"; }
        else if (m.ev === "note") s.note = m.text;
        else if (m.ev === "exit") { s.status = "exit"; s.exitCode = m.code; }
        else if (m.ev === "grade") {
            const o = s.opts;
            if (m.newly && m.newly.length) {
                const a = prog.labs[o.lesson] = prog.labs[o.lesson] || [];
                for (const i of m.newly) a[i] = true;
                touch();
            }
            if (m.solved && o.debug && !prog.debugs[o.debug]) { prog.debugs[o.debug] = true; touch(); }
        }
        termRev++;
    }
    // Ảnh màn hình → HTML cho Text (mỗi đoạn cùng màu là một span)
    function rowHtml(segs: var): string {
        let h = "";
        for (const g of segs) {
            const t = g.t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/ /g, "&nbsp;");
            const st = (g.f ? "color:" + g.f + ";" : "") + (g.b ? "background-color:" + g.b + ";" : "")
                + (g.a & 1 ? "font-weight:bold;" : "") + (g.a & 4 ? "text-decoration:underline;" : "");
            h += st ? `<span style="${st}">${t}</span>` : t;
        }
        return h;
    }

    // ------------------------------------------------------------------ IPC
    IpcHandler {
        target: "learn"
        function open(id: string): void { app.goId(id, 0); }
        function step(n: int): void { app.go(app.cur, n - 1); }
        function view(v: string): void { app.view = v === "results" ? "results" : "learn"; }
        function theme(): void { app.toggleTheme(); }
        // chạy một lệnh trong terminal của bước đang mở (lab hoặc sự cố đang chọn), để thử tự động
        function run(text: string): void { if (app.terms[app.activeTerm]) app.termInput(app.activeTerm, text + "\r"); }
        function lines(): string {
            const s = app.terms[app.activeTerm];
            if (!s || !s.snap) return "-";
            return s.snap.rows.map(r => r.map(g => g.t).join("").replace(/\s+$/, "")).filter(x => x).slice(-8).join("\n");
        }
        function results(): void { app.view = "results"; }
        function answer(qi: int, oi: int): void { app.answer(app.lesson, qi, oi); }
        function close(): void { app.quit(); }
        // chụp nội dung cửa sổ ra file PNG (không cần cửa sổ đang hiện trên màn hình)
        function shot(path: string): void { mainLayout.grabToImage(r => r.saveToFile(path)); }
        function state(): string {
            return `loaded=${app.loaded} err=${app.loadError} lessons=${app.lessons.length} cur=${app.lesson ? app.lesson.id : "-"} step=${app.step + 1}/${app.steps.length} kind=${app.curStep ? app.curStep.kind : "-"} view=${app.view} dark=${app.dark}`;
        }
    }
    function toggleTheme(): void {
        themeOverride = dark ? "light" : "dark";
        prog.ui = prog.ui || {};
        prog.ui.theme = themeOverride;
        saveTimer.restart();
    }

    // ------------------------------------------------------------------ cửa sổ
    FloatingWindow {
        id: window
        title: "Quantum Learn"
        visible: true
        onVisibleChanged: if (!visible) app.quit()
        implicitWidth: 1440
        implicitHeight: 900
        minimumSize: Qt.size(1040, 640)
        color: app.paper

        Shortcut { sequences: ["Ctrl+K"]; onActivated: { searchInput.forceActiveFocus(); searchInput.selectAll(); } }
        Shortcut { sequences: ["Right"]; enabled: app.view === "learn"; onActivated: if (app.step < app.steps.length - 1) app.go(app.cur, app.step + 1) }
        Shortcut { sequences: ["Left"]; enabled: app.view === "learn"; onActivated: if (app.step > 0) app.go(app.cur, app.step - 1) }

        Item {
            anchors.fill: parent
            visible: !app.loaded
            Label {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 620)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: app.loadError ? "Không tải được khoá học: " + app.loadError : "Đang tải khoá học…"
                color: app.loadError ? app.redInk : app.muted
            }
        }

        Rectangle {
            id: mainLayout
            anchors.fill: parent
            color: app.paper
            visible: app.loaded
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // ====================================================== header
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 54
                    z: 10
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.lineStrong }

                    // kéo header để di chuyển cửa sổ, bấm đúp để phóng to / trả về (như thanh tiêu đề)
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        property point p0
                        onPressed: m => p0 = Qt.point(m.x, m.y)
                        onPositionChanged: m => {
                            if (pressed && Math.abs(m.x - p0.x) + Math.abs(m.y - p0.y) > 6) dragArea.Window.window.startSystemMove();
                        }
                        onDoubleClicked: app.winAction("max")
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 18
                        spacing: 18

                        WinButtons {}

                        // logo
                        RowLayout {
                            spacing: 10
                            Rectangle {
                                implicitWidth: 28; implicitHeight: 28; radius: 7; color: app.ink
                                Pop { target: parent; radius: 7 }
                                Label { anchors.centerIn: parent; text: "$_"; color: app.paper; font.pixelSize: 12; font.weight: Font.Bold }
                            }
                            Label { text: "Khoá học"; font.pixelSize: 16; font.weight: Font.ExtraBold }
                            Item {
                                implicitWidth: brand2.implicitWidth + 4; implicitHeight: brand2.implicitHeight
                                Rectangle { x: 0; y: parent.height * 0.55; width: parent.width; height: parent.height * 0.42; color: app.green }
                                Label { id: brand2; x: 2; text: "VPS Linux"; font.pixelSize: 16; font.weight: Font.ExtraBold }
                            }
                        }

                        Item { Layout.fillWidth: true }
                        RowLayout {
                            spacing: 6
                            NavBtn { icon: "menu_book"; label: "Học"; active: app.view === "learn"; onClicked: app.view = "learn" }
                            NavBtn { icon: "bar_chart"; label: "Kết quả"; active: app.view === "results"; onClicked: app.view = "results" }
                        }
                        Item { Layout.fillWidth: true }

                        // tìm kiếm
                        Rectangle {
                            id: searchBox
                            implicitWidth: window.width > 1250 ? 270 : 200
                            implicitHeight: 32
                            radius: 8
                            color: app.cardHi
                            border.color: searchInput.activeFocus ? app.ink2 : app.lineStrong
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6; spacing: 8
                                Sym { text: "search"; size: 16; color: app.muted }
                                TextInput {
                                    id: searchInput
                                    Layout.fillWidth: true
                                    font.family: app.mono; font.pixelSize: 12
                                    color: app.ink; clip: true
                                    selectionColor: app.green; selectedTextColor: app.ink
                                    readonly property string typed: text + preeditText
                                    property int hi: 0
                                    onTypedChanged: hi = 0
                                    Keys.onEscapePressed: { text = ""; focus = false; }
                                    Keys.onDownPressed: hi = Math.min(hi + 1, searchResults.hits.length - 1)
                                    Keys.onUpPressed: hi = Math.max(hi - 1, 0)
                                    Keys.onReturnPressed: if (searchResults.hits[hi] !== undefined) searchResults.pick(searchResults.hits[hi])
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !searchInput.typed
                                        text: "Tìm bài học, lệnh…"; color: app.muted2; font.pixelSize: 12
                                    }
                                }
                                Kbd { text: "Ctrl K" }
                            }
                        }
                        IconBtn {
                            icon: app.dark ? "light_mode" : "dark_mode"
                            onClicked: app.toggleTheme()
                        }
                        Rectangle {
                            visible: window.width > 1250
                            implicitWidth: chipRow.implicitWidth + 12; implicitHeight: 32; radius: 8
                            color: app.cardHi; border.color: app.lineStrong
                            RowLayout {
                                id: chipRow
                                anchors.verticalCenter: parent.verticalCenter; x: 3; spacing: 7
                                Rectangle {
                                    implicitWidth: 24; implicitHeight: 24; radius: 6; color: app.ink
                                    Sym { anchors.centerIn: parent; text: "dns"; size: 14; color: app.paper }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    Label { text: "VPS lab"; font.pixelSize: 10; color: app.muted }
                                    Label { text: app.ip; font.pixelSize: 11; font.weight: Font.Bold }
                                }
                            }
                        }
                    }
                }

                // ====================================================== thân: 3 cột
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 12
                    spacing: 12

                    Sidebar {
                        Layout.fillHeight: true
                        Layout.fillWidth: false
                        Layout.preferredWidth: window.width > 1300 ? 270 : 236
                        Layout.maximumWidth: Layout.preferredWidth
                    }

                    // ---------------------------------------------- khung giữa
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 420
                        color: app.sheet
                        visible: app.view === "learn" && app.lesson !== null

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            LessonHead { Layout.fillWidth: true }
                            Stage { Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: 12; Layout.rightMargin: 12 }
                            Timeline { Layout.fillWidth: true; Layout.margins: 12 }
                        }
                    }

                    ResultsPage {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: app.view === "results"
                    }

                    // ---------------------------------------------- panel phải
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.fillWidth: false
                        Layout.preferredWidth: window.width > 1300 ? 340 : 300
                        Layout.maximumWidth: Layout.preferredWidth
                        visible: app.view === "learn" && app.lesson !== null
                        spacing: 12
                        StepPanel { Layout.fillWidth: true; Layout.fillHeight: true }
                        LearnList { Layout.fillWidth: true; Layout.preferredHeight: Math.min(implicitHeight, window.height * 0.34) }
                    }
                }
            }
        }

        Toast {}

        // menu kết quả tìm kiếm (nổi trên mọi thứ)
        Rectangle {
            id: searchResults
            readonly property var hits: {
                const words = app.fold(searchInput.typed).split(/\s+/).filter(w => w);
                if (!words.length || !app.loaded) return [];
                const out = [];
                for (let i = 0; i < app.lessons.length && out.length < 8; i++) {
                    const l = app.lessons[i];
                    const hay = app.fold(`${l.short} ${l.title} ${l.dek} ${l.group} ${l.id}`);
                    if (words.every(w => hay.includes(w))) out.push(i);
                }
                return out;
            }
            function pick(i: int): void { app.go(i, 0); searchInput.text = ""; searchInput.focus = false; }
            visible: searchInput.activeFocus && searchInput.typed.trim() !== ""
            z: 100
            x: { void window.width; return searchBox.mapToItem(window.contentItem, 0, 0).x + searchBox.width - width; }
            y: 54 + 4
            width: 430
            height: resCol.implicitHeight + 12
            radius: 10
            color: app.cardHi
            border.color: app.ink2
            Rectangle { z: -1; x: 1.5; y: 2.5; width: parent.width; height: parent.height; radius: parent.radius; color: app.drop }
            Column {
                id: resCol
                x: 6; y: 6; width: parent.width - 12
                Label {
                    visible: searchResults.hits.length === 0
                    padding: 8
                    text: "Không có bài nào khớp “" + searchInput.typed + "”."
                    color: app.muted
                }
                Repeater {
                    model: searchResults.hits
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var l: app.lessons[modelData]
                        width: resCol.width; height: 32; radius: 7
                        color: searchInput.hi === index ? app.greenTile : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 9
                            Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 2; color: app.groupOf(parent.parent.l).color }
                            Label { Layout.fillWidth: true; text: parent.parent.l.short; elide: Text.ElideRight }
                            Label { text: parent.parent.l.group; color: app.muted; font.pixelSize: 11 }
                        }
                        HoverHandler { onHoveredChanged: if (hovered) searchInput.hi = parent.index }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: searchResults.pick(parent.modelData) }
                    }
                }
            }
        }
    }

    // ================================================================== thành phần giao diện
    component Toast: Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26
        width: tst.width + 3; height: tst.height + 3
        visible: app.toastText !== ""
        z: 200
        Rectangle { x: 1.5; y: 2.5; width: tst.width; height: tst.height; radius: 9; color: app.drop }
        Rectangle {
            id: tst
            width: Math.min(tsl.implicitWidth + 44, 720); height: 38; radius: 9
            color: app.toastError ? app.red : app.green
            border.color: app.ink
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 14; spacing: 8
                Sym { text: app.toastError ? "error" : "check_circle"; size: 16; color: app.toastError ? app.redInk : app.ink }
                Label { id: tsl; Layout.fillWidth: true; text: app.toastText; elide: Text.ElideMiddle; font.weight: Font.DemiBold; color: app.toastError ? app.redInk : app.ink }
            }
        }
    }

    component Label: Text {
        font.family: app.mono
        font.pixelSize: 13
        color: app.ink
    }
    component Rich: Text {
        font.family: app.mono
        font.pixelSize: 13
        color: app.ink
        textFormat: Text.RichText
        wrapMode: Text.Wrap
        lineHeight: 1.3
    }
    component Sym: Text {
        property int size: 18
        font.family: app.iconFont
        font.pixelSize: size
        color: app.ink
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
    component Caps: Label {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.6
        font.capitalization: Font.AllUppercase
        color: app.muted
    }
    component Kbd: Rectangle {
        property alias text: kt.text
        implicitWidth: kt.implicitWidth + 10; implicitHeight: 18; radius: 5
        color: app.cardHi; border.color: app.lineStrong
        Label { id: kt; anchors.centerIn: parent; font.pixelSize: 11; color: app.muted }
    }
    // nút cửa sổ kiểu macOS: đỏ đóng, vàng thu xuống dock, xanh phóng to / trả về 3/4
    // (cùng màu và cách hiện ký hiệu khi rê chuột như quantum-window-buttons.css của app GTK)
    component WinButtons: RowLayout {
        id: wb
        spacing: 8
        readonly property bool focused: wb.Window.active
        HoverHandler { id: wbHover }
        Repeater {
            model: [
                { a: "close", c: "#ff5f57", f: "#4d0000", g: "×", tip: "Đóng" },
                { a: "min", c: "#febc2e", f: "#5a3e00", g: "−", tip: "Thu nhỏ xuống dock" },
                { a: "max", c: "#28c840", f: "#004d00", g: "+", tip: "Phóng to / trả về" }
            ]
            Rectangle {
                id: wbtn
                required property var modelData
                implicitWidth: 13; implicitHeight: 13; radius: 6.5
                color: wb.focused || wbHover.hovered ? modelData.c : app.dark ? "#4a443c" : "#d3c9bb"
                border.color: Qt.rgba(0, 0, 0, 0.14)
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -0.5
                    visible: wbHover.hovered
                    text: wbtn.modelData.g
                    font.pixelSize: 12; font.weight: Font.Black
                    color: wbtn.modelData.f
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: wbtn.opacity = 0.75
                    onReleased: wbtn.opacity = 1
                    onClicked: app.winAction(wbtn.modelData.a)
                }
            }
        }
    }

    // bóng đổ cứng lệch xuống phải (đặt làm con đầu tiên của khối cần bóng)
    component Pop: Rectangle {
        property Item target
        property real dx: 1.5
        property real dy: 2.5
        z: -1
        x: dx; y: dy
        width: target ? target.width : 0
        height: target ? target.height : 0
        color: app.drop
    }
    component Card: Rectangle {
        radius: 12
        color: app.paper2
        border.color: app.line
        clip: true
    }
    component NavBtn: Rectangle {
        id: nb
        property string icon
        property string label
        property bool active: false
        signal clicked()
        implicitWidth: nbRow.implicitWidth + 36
        implicitHeight: 34
        radius: 8
        color: active ? app.green : nbHover.hovered ? app.card : "transparent"
        border.color: active ? app.ink : nbHover.hovered ? app.line : "transparent"
        Pop { target: nb; radius: 8; visible: nb.active }
        HoverHandler { id: nbHover }
        RowLayout {
            id: nbRow
            anchors.centerIn: parent; spacing: 8
            Sym { text: nb.icon; size: 16; color: nb.active ? app.ink : app.ink2 }
            Label { text: nb.label; font.pixelSize: 14; font.weight: Font.DemiBold; color: nb.active ? app.ink : app.ink2 }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nb.clicked() }
    }
    component IconBtn: Rectangle {
        id: ib
        property string icon
        signal clicked()
        implicitWidth: 32; implicitHeight: 32; radius: 8
        color: app.cardHi
        border.color: ibHover.hovered ? app.ink2 : app.lineStrong
        HoverHandler { id: ibHover }
        Sym { anchors.centerIn: parent; text: ib.icon; size: 17 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }
    // nút: thường (viền mực, bóng mảnh) hoặc chính (nền xanh, bóng cứng)
    component Btn: Item {
        id: bt
        property string text
        property string icon: ""
        property string trailing: ""
        property bool primary: false
        property bool small: false
        signal clicked()
        implicitWidth: btRow.implicitWidth + (small ? 22 : 28)
        implicitHeight: small ? 28 : 38
        opacity: enabled ? 1 : 0.45
        Rectangle {
            id: btShadow
            x: bt.primary ? 1.5 : 0; y: bt.primary ? 2.5 : 1.5
            width: parent.width; height: parent.height; radius: 8
            color: bt.primary ? app.drop : app.ink2
            visible: bt.enabled && !btArea.pressed
        }
        Rectangle {
            id: btFace
            width: parent.width; height: parent.height; radius: 8
            x: btArea.pressed && bt.enabled ? 1 : 0
            y: btArea.pressed && bt.enabled ? 2 : (btHover.hovered && bt.enabled ? -1 : 0)
            color: bt.primary ? app.green : app.cardHi
            border.color: bt.primary ? app.ink : app.ink2
            RowLayout {
                id: btRow
                anchors.fill: parent
                anchors.leftMargin: bt.small ? 11 : 14
                anchors.rightMargin: bt.small ? 11 : 14
                spacing: 7
                Sym { visible: bt.icon !== ""; text: bt.icon; size: bt.small ? 14 : 16 }
                Label {
                    Layout.fillWidth: bt.trailing !== ""
                    text: bt.text
                    elide: Text.ElideRight
                    font.pixelSize: bt.small ? 12 : 13
                    font.weight: bt.primary ? Font.Bold : Font.DemiBold
                }
                Sym { visible: bt.trailing !== ""; text: bt.trailing; size: 17 }
            }
        }
        HoverHandler { id: btHover }
        MouseArea { id: btArea; anchors.fill: parent; cursorShape: bt.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; enabled: bt.enabled; onClicked: bt.clicked() }
    }
    component Pill: Rectangle {
        property string icon
        property string text
        implicitWidth: plRow.implicitWidth + 22; implicitHeight: 25; radius: 13
        border.color: app.ink2
        RowLayout {
            id: plRow
            anchors.centerIn: parent; spacing: 6
            Sym { text: parent.parent.icon; size: 13 }
            Label { text: parent.parent.text; font.pixelSize: 11; font.weight: Font.DemiBold }
        }
    }
    component Tag: Rectangle {
        property string text
        property string tone: "plain"
        implicitWidth: tgl.implicitWidth + 20; implicitHeight: 22; radius: 11
        color: tone === "red" ? app.red : tone === "green" ? app.green : tone === "violet" ? app.violet
             : tone === "orange" ? app.orange : tone === "mint" ? app.mint : app.card
        border.color: app.ink2
        Rectangle { z: -1; y: 1.5; width: parent.width; height: parent.height; radius: parent.radius; color: app.ink2 }
        Caps { id: tgl; anchors.centerIn: parent; text: parent.text; font.weight: Font.ExtraBold; color: parent.tone === "red" ? app.redInk : app.ink }
    }
    // ghi chú / ý chính: ô màu có icon vuông
    component Note: Rectangle {
        id: nt
        property var note: ({ note: "" })
        property string label: ""
        readonly property string kind: note && ["tip", "warn", "err"].includes(note.kind) ? note.kind : "info"
        implicitHeight: ntRow.implicitHeight + 22
        radius: 10
        color: kind === "tip" ? app.greenTile : kind === "warn" ? app.orangeTile : kind === "err" ? app.redTile : app.violetTile
        border.color: kind === "tip" ? app.greenTileLine : kind === "warn" ? app.orangeTileLine : kind === "err" ? app.redTileLine : app.violetTileLine
        RowLayout {
            id: ntRow
            x: 12; y: 11; width: parent.width - 24
            spacing: 10
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 24; implicitHeight: 24; radius: 6
                color: app.cardHi; border.color: app.ink2
                Sym { anchors.centerIn: parent; text: nt.kind === "warn" ? "warning" : nt.kind === "err" ? "error" : nt.kind === "tip" ? "lightbulb" : "auto_awesome"; size: 14 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Caps { text: nt.label || ({ tip: "Mẹo", warn: "Lưu ý", err: "Lỗi hay gặp" })[nt.kind] || "Ghi chú" }
                Rich { Layout.fillWidth: true; text: app.md(nt.note ? nt.note.note : ""); font.pixelSize: 12 }
            }
        }
    }

    // ---------------------------------------------------------------- khối nội dung lý thuyết
    component BlockView: Item {
        id: bv
        property var b
        readonly property string kind: typeof b === "string" ? "p" : !b ? "" : b.pre ? "pre" : b.tbl ? "tbl" : b.ul ? "ul" : "note"
        implicitHeight: bvLoader.item ? bvLoader.item.implicitHeight + 14 : 0
        Loader {
            id: bvLoader
            width: parent.width
            sourceComponent: bv.kind === "p" ? paraC : bv.kind === "pre" ? preC : bv.kind === "tbl" ? tblC : bv.kind === "ul" ? ulC : bv.kind === "note" ? noteC : null
        }
        Component {
            id: paraC
            Rich { text: app.md(bv.b); lineHeight: 1.45; font.pixelSize: 14 }
        }
        Component {
            id: noteC
            Note { note: bv.b }
        }
        Component {
            id: ulC
            Column {
                spacing: 5
                Repeater {
                    model: bv.b.ul
                    RowLayout {
                        required property var modelData
                        width: bv.width
                        spacing: 8
                        Label { Layout.alignment: Qt.AlignTop; text: "▸"; color: app.rust }
                        Rich { Layout.fillWidth: true; text: app.md(parent.modelData); lineHeight: 1.4 }
                    }
                }
            }
        }
        Component {
            id: preC
            Item {
                id: pre
                readonly property string code: bv.b.pre.join("\n")
                implicitHeight: preBox.height + (bv.b.cap ? preCap.implicitHeight + 6 : 0) + 2.5
                Rectangle { x: 1.5; y: 2.5; width: preBox.width; height: preBox.height; radius: 10; color: app.drop }
                Rectangle {
                    id: preBox
                    width: parent.width - 2
                    height: Math.min(preText.implicitHeight + 24, 460)
                    radius: 10
                    color: app.codeBg
                    border.color: "#1d1b18"
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 12
                        contentWidth: preText.implicitWidth
                        contentHeight: preText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Text {
                            id: preText
                            text: pre.code
                            font.family: app.mono; font.pixelSize: 12
                            color: app.codeInk
                            lineHeight: 1.35
                            textFormat: Text.PlainText
                        }
                    }
                    Rectangle {
                        id: copyBtn
                        property bool copied: false
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 7
                        implicitWidth: cpl.implicitWidth + 16; implicitHeight: 22; radius: 6
                        color: "#34302b"; border.color: "#4f473d"
                        opacity: cpHover.hovered ? 1 : 0.8
                        HoverHandler { id: cpHover }
                        Label { id: cpl; anchors.centerIn: parent; text: copyBtn.copied ? "Đã chép" : "Chép"; font.pixelSize: 11; color: "#ddd3c2" }
                        Timer { id: cpTimer; interval: 1200; onTriggered: copyBtn.copied = false }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { Quickshell.clipboardText = pre.code; copyBtn.copied = true; cpTimer.restart(); }
                        }
                    }
                }
                Rich {
                    id: preCap
                    visible: !!bv.b.cap
                    y: preBox.height + 8; width: parent.width
                    text: app.md(bv.b.cap || ""); color: app.muted; font.pixelSize: 11
                }
            }
        }
        Component {
            id: tblC
            Rectangle {
                id: tbl
                readonly property var head: bv.b.tbl[0]
                readonly property var rows: bv.b.tbl.slice(1)
                // độ rộng cột theo độ dài nội dung (căn bậc hai để cột ngắn không quá hẹp)
                readonly property var widths: {
                    const n = head.length;
                    const w = [];
                    for (let c = 0; c < n; c++) {
                        let m = 4;
                        for (const r of bv.b.tbl) m = Math.max(m, app.plain(r[c] || "").length);
                        w.push(Math.sqrt(Math.min(m, 60)));
                    }
                    const sum = w.reduce((a, x) => a + x, 0);
                    return w.map(x => x / sum);
                }
                implicitHeight: tblCol.implicitHeight + 2
                radius: 10
                color: "transparent"
                border.color: app.lineStrong
                clip: true
                Column {
                    id: tblCol
                    x: 1; y: 1; width: parent.width - 2
                    Rectangle {
                        width: parent.width; height: hdRow.implicitHeight + 14
                        color: app.paper2
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.lineStrong }
                        Row {
                            id: hdRow
                            y: 7
                            Repeater {
                                model: tbl.head
                                Rich {
                                    required property var modelData
                                    required property int index
                                    width: tblCol.width * tbl.widths[index]
                                    leftPadding: 10; rightPadding: 10
                                    text: app.md(app.plain(modelData).toUpperCase())
                                    font.pixelSize: 11; font.weight: Font.Bold; color: app.muted
                                }
                            }
                        }
                    }
                    Repeater {
                        model: tbl.rows
                        Rectangle {
                            id: tr
                            required property var modelData
                            required property int index
                            width: tblCol.width
                            height: trRow.implicitHeight + 14
                            color: "transparent"
                            Rectangle { visible: tr.index > 0; width: parent.width; height: 1; color: app.lineSoft }
                            Row {
                                id: trRow
                                y: 7
                                Repeater {
                                    model: tr.modelData
                                    Rich {
                                        required property var modelData
                                        required property int index
                                        width: tblCol.width * tbl.widths[index]
                                        leftPadding: 10; rightPadding: 10
                                        text: app.md(modelData)
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- thanh bên: cây bài học
    component Sidebar: ColumnLayout {
        id: sb
        spacing: 10
        property var toggled: ({})
        property int tick: 0
        function isOpen(name: string): bool {
            void tick;
            return toggled[name] !== undefined ? toggled[name] : (app.lesson && app.lesson.group === name);
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6; Layout.rightMargin: 6
            spacing: 9
            Sym { text: "folder"; size: 18 }
            Label { text: "Khoá học"; font.pixelSize: 14; font.weight: Font.Bold; Layout.fillWidth: true }
            Label { text: app.lessons.length + " bài"; color: app.muted; font.pixelSize: 11 }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: treeCol.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: treeCol
                width: parent.width - 4
                Repeater {
                    model: app.groups
                    Column {
                        id: grp
                        required property var modelData
                        readonly property bool opened: sb.isOpen(modelData.name)
                        width: treeCol.width
                        Rectangle {
                            width: parent.width; height: 30; radius: 7
                            color: fHover.hovered ? app.card : "transparent"
                            HoverHandler { id: fHover }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 6
                                Sym { text: "chevron_right"; size: 16; color: app.muted; rotation: grp.opened ? 90 : 0; Behavior on rotation { NumberAnimation { duration: 120 } } }
                                Sym { text: "folder"; size: 18; color: grp.modelData.color; font.variableAxes: ({ "FILL": 1 }) }
                                Label { Layout.fillWidth: true; text: grp.modelData.num + ". " + grp.modelData.name; font.weight: Font.Bold; elide: Text.ElideRight }
                                Label {
                                    text: { void app.rev; return grp.modelData.idx.filter(i => app.done(app.lessons[i]) === app.total(app.lessons[i])).length + "/" + grp.modelData.idx.length; }
                                    color: app.muted; font.pixelSize: 11
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { sb.toggled[grp.modelData.name] = !grp.opened; sb.tick++; }
                            }
                        }
                        Item {
                            visible: grp.opened
                            width: parent.width
                            height: visible ? lsCol.implicitHeight + 8 : 0
                            Rectangle { x: 13; y: 2; width: 1; height: lsCol.implicitHeight; color: app.lineStrong }
                            Column {
                                id: lsCol
                                x: 22; y: 2; width: parent.width - 24
                                spacing: 1
                                Repeater {
                                    model: grp.opened ? grp.modelData.idx : []
                                    Item {
                                        id: li
                                        required property var modelData
                                        readonly property var l: app.lessons[modelData]
                                        readonly property bool active: app.cur === modelData && app.view === "learn"
                                        readonly property int d: { void app.rev; return app.done(l); }
                                        readonly property int t: app.total(l)
                                        width: lsCol.width; height: 27
                                        Rectangle { visible: li.active; x: 1.5; y: 2.5; width: parent.width - 2; height: parent.height - 1; radius: 8; color: app.drop }
                                        Rectangle {
                                            width: parent.width - 2; height: parent.height - 1; radius: 8
                                            color: li.active ? app.green : liHover.hovered ? app.card : "transparent"
                                            border.color: li.active ? app.ink : "transparent"
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 7; spacing: 7
                                                Sym {
                                                    text: li.d === li.t ? "check_circle" : li.d > 0 ? "clock_loader_40" : "radio_button_unchecked"
                                                    size: 14
                                                    color: li.d === li.t ? (li.active ? app.greenInk : app.green3) : li.active ? app.ink : app.muted2
                                                }
                                                Label {
                                                    Layout.fillWidth: true
                                                    text: li.l.short
                                                    elide: Text.ElideRight
                                                    font.weight: li.active ? Font.Bold : Font.Normal
                                                    color: li.active ? app.ink : app.ink2
                                                }
                                            }
                                        }
                                        HoverHandler { id: liHover }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { app.go(li.modelData, app.cur === li.modelData ? app.step : 0); sb.toggled = ({}); sb.tick++; }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // tiến độ toàn khoá
        Card {
            id: progCard
            Layout.fillWidth: true
            implicitHeight: 62
            readonly property var sums: {
                void app.rev;
                let d = 0, t = 0, n = 0;
                for (const l of app.lessons) { const a = app.done(l), b = app.total(l); d += a; t += b; if (a === b) n++; }
                return { pct: t ? Math.round(d / t * 100) : 0, n: n };
            }
            border.color: pcHover.hovered ? app.lineStrong : app.line
            HoverHandler { id: pcHover }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 13; spacing: 8
                RowLayout {
                    Caps { text: "Tiến độ"; color: app.ink }
                    Label {
                        visible: app.savedAt > 0
                        text: "· đã lưu " + app.clock(app.savedAt)
                        font.pixelSize: 10; color: app.muted2
                    }
                    Item { Layout.fillWidth: true }
                    Label { text: progCard.sums.n + " / " + app.lessons.length + " bài · " + progCard.sums.pct + "%"; color: app.muted; font.pixelSize: 11 }
                    Sym { text: "chevron_right"; size: 15; color: app.muted }
                }
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 5; radius: 3; color: app.line
                    Rectangle { width: parent.width * progCard.sums.pct / 100; height: parent.height; radius: 3; color: app.green3 }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.view = "results" }
        }
    }

    // ---------------------------------------------------------------- tiêu đề bài
    component LessonHead: RowLayout {
        readonly property var g: app.lesson ? app.groupOf(app.lesson) : null
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24; Layout.topMargin: 18; Layout.bottomMargin: 12
            spacing: 4
            Label {
                text: parent.parent.g ? `${parent.parent.g.num}. ${parent.parent.g.name}  /  Bài ${parent.parent.g.idx.indexOf(app.cur) + 1} / ${parent.parent.g.idx.length}` : ""
                font.pixelSize: 12; color: app.ink2
            }
            Label {
                Layout.fillWidth: true
                text: app.lesson ? app.lesson.title : ""
                font.pixelSize: 26; font.weight: Font.ExtraBold; font.letterSpacing: -0.45
                wrapMode: Text.Wrap
            }
            Label {
                Layout.fillWidth: true
                Layout.maximumWidth: 760
                text: app.lesson ? app.plain(app.lesson.dek) : ""
                color: app.muted; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
        Flow {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 18; Layout.rightMargin: 24
            Layout.preferredWidth: Math.min(380, implicitWidth)
            spacing: 6
            layoutDirection: Qt.RightToLeft
            Pill { color: app.violet; icon: "layers"; text: app.steps.length + " bước" }
            Pill { color: app.mint; icon: "terminal"; text: app.lesson ? app.lesson.lab.user + "@" + app.lesson.lab.host : "" }
            Pill { color: app.orange; icon: "schedule"; text: app.lesson ? "≈ " + app.estimate(app.lesson) + " phút" : "" }
        }
    }

    // ---------------------------------------------------------------- stage: lưới isometric + nội dung bước
    component Stage: Rectangle {
        id: stage
        radius: 10
        color: app.paper2
        border.color: app.line
        clip: true

        Canvas {
            id: grid
            anchors.fill: parent
            property color c: app.lineSoft
            onCChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = c;
                ctx.lineWidth = 1;
                const k = Math.tan(Math.PI / 6), gap = 28, w = width, h = height;
                ctx.beginPath();
                for (let x = -h / k; x < w + h / k; x += gap / k * 0.5 * 2) {
                    ctx.moveTo(x, 0); ctx.lineTo(x + h / k, h);
                    ctx.moveTo(x, 0); ctx.lineTo(x - h / k, h);
                }
                ctx.stroke();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // chỉ số bài
            Flow {
                Layout.fillWidth: true
                Layout.margins: 10
                spacing: 6
                readonly property var l: app.lesson
                Metric { icon: "menu_book"; label: "Lý thuyết"; value: app.lesson ? app.lesson.theory.length + " thẻ" : "" }
                Metric { icon: "help"; label: "Quiz"; value: { void app.rev; return app.lesson ? app.quizDone(app.lesson) + "/" + app.lesson.quiz.length : ""; } ok: { void app.rev; return !!app.lesson && app.quizDone(app.lesson) === app.lesson.quiz.length; } }
                Metric { icon: "terminal"; label: "Thực hành"; value: { void app.rev; return app.lesson ? app.labDone(app.lesson) + "/" + app.lesson.lab.items.length : ""; } ok: { void app.rev; return !!app.lesson && app.labDone(app.lesson) === app.lesson.lab.items.length; } }
                Metric { icon: "bug_report"; label: "Fix lỗi"; value: { void app.rev; return app.lesson ? app.debugDone(app.lesson) + "/" + app.lesson.debugs.length : ""; } ok: { void app.rev; return !!app.lesson && app.debugDone(app.lesson) === app.lesson.debugs.length; } }
                Metric {
                    readonly property int pct: { void app.rev; return app.lesson ? Math.round(app.done(app.lesson) / Math.max(1, app.total(app.lesson)) * 100) : 0; }
                    icon: "flag"; label: "Hoàn thành"; value: pct + "%"; ok: pct === 100
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // tạo lại khi đổi bài/bước (cuộn về đầu, terminal gắn đúng khoá)
                property string stepKey: app.lesson && app.curStep ? app.lesson.id + ":" + app.step : ""
                onStepKeyChanged: { active = false; active = true; }
                sourceComponent: !app.curStep ? null
                    : app.curStep.kind === "theory" ? theoryStageC
                    : app.curStep.kind === "quiz" ? quizStageC
                    : app.curStep.kind === "lab" ? labStageC : debugStageC
            }
        }

        Component { id: theoryStageC; TheoryStage {} }
        Component { id: quizStageC; QuizStage {} }
        Component { id: labStageC; LabStage {} }
        Component { id: debugStageC; DebugStage {} }
    }

    component Metric: Rectangle {
        property string icon
        property string label
        property string value
        property bool ok: false
        implicitWidth: Math.max(100, mtCol.implicitWidth + 24)
        implicitHeight: mtCol.implicitHeight + 13
        radius: 9
        color: ok ? app.greenTile : Qt.rgba(app.cardHi.r, app.cardHi.g, app.cardHi.b, 0.92)
        border.color: ok ? app.greenTileLine : app.lineStrong
        ColumnLayout {
            id: mtCol
            x: 12; y: 6; spacing: 2
            RowLayout {
                spacing: 5
                Sym { text: parent.parent.parent.icon; size: 12; color: app.muted }
                Caps { text: parent.parent.parent.label; font.pixelSize: 10; font.weight: Font.Normal }
            }
            Label { text: parent.parent.value; font.weight: Font.Bold }
        }
    }

    // trang cuộn (nội dung căn giữa, rộng tối đa maxW)
    component Scroller: Flickable {
        id: sc
        default property alias body: scCol.data
        property real maxW: 880
        contentHeight: scCol.implicitHeight + 28
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ColumnLayout {
            id: scCol
            width: Math.min(sc.width - 36, sc.maxW)
            x: (sc.width - width) / 2
            y: 4
            spacing: 12
        }
    }

    component TheoryStage: Scroller {
        id: ths
        readonly property var c: app.lesson.theory[app.curStep.card]
        readonly property var parts: app.splitCard(c.body)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: shCol.implicitHeight + 34
            radius: 12
            color: app.cardHi
            border.color: app.lineStrong
            ColumnLayout {
                id: shCol
                x: 24; y: 20; width: parent.width - 48
                spacing: 0
                Caps { text: "Thẻ " + (app.curStep.card + 1) + " / " + app.lesson.theory.length }
                Rich { Layout.fillWidth: true; Layout.topMargin: 4; text: app.md(ths.c.title); font.pixelSize: 18; font.weight: Font.ExtraBold }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 12; Layout.bottomMargin: 14; implicitHeight: 1; color: app.lineStrong; opacity: 0.8 }
                Repeater {
                    model: ths.parts.rest
                    BlockView { required property var modelData; Layout.fillWidth: true; b: modelData }
                }
            }
        }
    }

    // ---------------------------------------------------------------- quiz
    component QuizStage: Scroller {
        id: qs
        readonly property var l: app.lesson
        readonly property var ans: { void app.rev; return Object.assign({}, app.prog.quiz[l.id] || {}); }
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: { void app.rev; return "Đúng " + app.quizDone(qs.l) + " / " + qs.l.quiz.length + " · đã trả lời " + Object.keys(qs.ans).length; }
                font.weight: Font.Bold
            }
            Btn { small: true; icon: "restart_alt"; text: "Làm lại quiz"; onClicked: app.resetQuiz(qs.l) }
        }
        Repeater {
            model: qs.l.quiz
            Card {
                id: qc
                required property var modelData
                required property int index
                readonly property var chosen: qs.ans[index]
                readonly property bool answered: chosen !== undefined
                Layout.fillWidth: true
                implicitHeight: qcCol.implicitHeight + 28
                color: app.cardHi
                border.color: app.lineStrong
                ColumnLayout {
                    id: qcCol
                    x: 16; y: 14; width: parent.width - 32
                    spacing: 7
                    RowLayout {
                        Caps { text: "Câu " + (qc.index + 1) + " / " + qs.l.quiz.length; Layout.fillWidth: true }
                        Caps {
                            visible: qc.answered
                            text: qc.chosen === qc.modelData.ans ? "Đúng" : "Sai"
                            color: qc.chosen === qc.modelData.ans ? app.greenInk : app.redInk
                        }
                    }
                    Rich { Layout.fillWidth: true; text: app.md(qc.modelData.q); font.weight: Font.Bold; font.pixelSize: 14 }
                    Repeater {
                        model: qc.modelData.opts
                        Rectangle {
                            id: opt
                            required property var modelData
                            required property int index
                            readonly property bool isAns: index === qc.modelData.ans
                            readonly property bool isChosen: index === qc.chosen
                            Layout.fillWidth: true
                            implicitHeight: optRow.implicitHeight + 16
                            radius: 8
                            color: qc.answered && isAns ? app.greenTile : qc.answered && isChosen ? app.redTile : optHover.hovered && !qc.answered ? app.card : app.paper2
                            border.color: qc.answered && isAns ? app.green3 : qc.answered && isChosen ? app.redTileLine : optHover.hovered && !qc.answered ? app.ink2 : app.line
                            HoverHandler { id: optHover }
                            RowLayout {
                                id: optRow
                                x: 10; y: 8; width: parent.width - 20; spacing: 10
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    implicitWidth: 20; implicitHeight: 20; radius: 5
                                    color: app.cardHi; border.color: app.muted2
                                    Label { anchors.centerIn: parent; text: "ABCDEFGH"[opt.index]; font.pixelSize: 11; font.weight: Font.Bold }
                                }
                                Rich { Layout.fillWidth: true; text: app.md(opt.modelData) }
                                Sym {
                                    visible: qc.answered && (opt.isAns || opt.isChosen)
                                    text: opt.isAns ? "check_circle" : "cancel"
                                    size: 16; color: opt.isAns ? app.greenInk : app.redInk
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !qc.answered
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: app.answer(qs.l, qc.index, opt.index)
                            }
                        }
                    }
                    Note {
                        visible: qc.answered
                        Layout.fillWidth: true
                        note: ({ note: qc.modelData.why, kind: qc.chosen === qc.modelData.ans ? "tip" : "err" })
                        label: "Giải thích"
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- thực hành
    component LabStage: RowLayout {
        id: lab
        readonly property var l: app.lesson
        readonly property var passed: { void app.rev; return (app.prog.labs[l.id] || []).slice(); }
        readonly property int nPass: l.lab.items.filter((x, i) => passed[i]).length
        property var openHints: ({})
        property int hintTick: 0
        spacing: 12

        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.preferredWidth: lab.width * 0.42
            Layout.maximumWidth: Layout.preferredWidth
            Layout.leftMargin: 14; Layout.bottomMargin: 14
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: "Đã pass " + lab.nPass + " / " + lab.l.lab.items.length + " câu"
                    font.weight: Font.Bold
                    color: lab.nPass === lab.l.lab.items.length ? app.greenInk : app.ink
                }
                Btn {
                    small: true; icon: "restart_alt"; text: "Làm lại"
                    onClicked: { app.prog.labs[lab.l.id] = []; app.touch(); app.termReset("lab:" + lab.l.id); }
                }
            }
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: labCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: labCol
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: lab.l.lab.items
                        Rectangle {
                            id: it
                            required property var modelData
                            required property int index
                            readonly property bool ok: !!lab.passed[index]
                            readonly property bool showHint: { void lab.hintTick; return !!lab.openHints[index]; }
                            Layout.fillWidth: true
                            implicitHeight: itCol.implicitHeight + 18
                            radius: 9
                            color: ok ? app.greenTile : app.cardHi
                            border.color: ok ? app.greenTileLine : app.lineStrong
                            ColumnLayout {
                                id: itCol
                                x: 10; y: 9; width: parent.width - 20
                                spacing: 6
                                RowLayout {
                                    spacing: 9
                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        implicitWidth: 18; implicitHeight: 18; radius: 4
                                        color: it.ok ? app.green3 : app.cardHi
                                        border.color: it.ok ? app.greenInk : app.muted2
                                        Sym { anchors.centerIn: parent; visible: it.ok; text: "check"; size: 14; color: "#10200c" }
                                    }
                                    Rich { Layout.fillWidth: true; text: app.md(it.modelData.text); font.pixelSize: 12 }
                                }
                                Label {
                                    Layout.leftMargin: 27
                                    visible: !!it.modelData.hint
                                    text: (it.showHint ? "▾ " : "▸ ") + "Gợi ý"
                                    font.pixelSize: 11; color: app.muted
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { lab.openHints[it.index] = !it.showHint; lab.hintTick++; }
                                    }
                                }
                                Rectangle {
                                    visible: it.showHint
                                    Layout.fillWidth: true; Layout.leftMargin: 27
                                    implicitHeight: hintText.implicitHeight + 14; radius: 7
                                    color: app.codeBg
                                    Text {
                                        id: hintText
                                        x: 9; y: 7; width: parent.width - 18
                                        text: it.modelData.hint || ""
                                        font.family: app.mono; font.pixelSize: 12; color: app.codeInk
                                        wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Terminal {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.rightMargin: 14; Layout.bottomMargin: 14
            key: "lab:" + lab.l.id
            opts: ({ lesson: lab.l.id, host: lab.l.lab.host, user: lab.l.lab.user })
        }
    }

    // ---------------------------------------------------------------- sửa lỗi
    component DebugStage: RowLayout {
        id: dbg
        readonly property var l: app.lesson
        property int sel: 0
        readonly property var d: l.debugs[Math.min(sel, l.debugs.length - 1)]
        readonly property bool solved: { void app.rev; return !!app.prog.debugs[d.id]; }
        property var help: ({})          // id → { hints, sol }
        property int helpTick: 0
        readonly property var h: { void helpTick; return help[d.id] || { hints: 0, sol: false }; }
        function setHelp(p: var): void { help[d.id] = Object.assign({}, h, p); helpTick++; }
        spacing: 12

        Flickable {
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.preferredWidth: dbg.width * 0.42
            Layout.maximumWidth: Layout.preferredWidth
            Layout.leftMargin: 14; Layout.bottomMargin: 14
            contentHeight: dbCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: dbCol
                width: parent.width
                spacing: 8

                // danh sách sự cố
                Repeater {
                    model: dbg.l.debugs
                    Rectangle {
                        id: dc
                        required property var modelData
                        required property int index
                        readonly property bool ok: { void app.rev; return !!app.prog.debugs[modelData.id]; }
                        Layout.fillWidth: true
                        implicitHeight: dcRow.implicitHeight + 16
                        radius: 9
                        color: ok ? app.greenTile : dbg.sel === index ? app.orangeTile : app.cardHi
                        border.color: ok ? app.greenTileLine : dbg.sel === index ? app.ink2 : app.lineStrong
                        RowLayout {
                            id: dcRow
                            x: 10; y: 8; width: parent.width - 20; spacing: 10
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 24; implicitHeight: 24; radius: 6
                                color: dc.ok ? app.green3 : "#e0a33a"
                                Label { anchors.centerIn: parent; text: dc.ok ? "✓" : "!"; font.weight: Font.Bold; color: "#1d1b18" }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Rich { Layout.fillWidth: true; text: app.md(dc.modelData.title); font.weight: Font.Bold; font.pixelSize: 12 }
                                Label {
                                    text: dc.ok ? "Đã xử lý" : dc.modelData.hard ? "Nâng cao · không có lời giải" : "Sự cố " + (dc.index + 1) + "/" + dbg.l.debugs.length
                                    font.pixelSize: 11; color: app.muted
                                }
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dbg.sel = dc.index }
                    }
                }

                Caps { Layout.topMargin: 6; text: "Triệu chứng" }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: symText.implicitHeight + 20; radius: 8
                    color: app.codeBg
                    Rectangle { width: 4; height: parent.height; radius: 2; color: "#e0a33a" }
                    Text {
                        id: symText
                        x: 14; y: 10; width: parent.width - 24
                        text: dbg.d.symptom.join("\n")
                        font.family: app.mono; font.pixelSize: 12; color: app.codeInk
                        wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; lineHeight: 1.3
                    }
                }
                Caps { text: "Bối cảnh" }
                Rich { Layout.fillWidth: true; text: app.md(dbg.d.story); lineHeight: 1.4 }
                Caps { text: "Mục tiêu" }
                Rich { Layout.fillWidth: true; text: app.md(dbg.d.goal); lineHeight: 1.4 }
                Caps { text: "Cần trợ giúp?" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: dbg.d.hints.length
                        Btn {
                            required property int index
                            small: true
                            text: "Gợi ý " + (index + 1)
                            enabled: index <= dbg.h.hints
                            opacity: index < dbg.h.hints ? 0.6 : enabled ? 1 : 0.45
                            onClicked: dbg.setHelp({ hints: Math.max(dbg.h.hints, index + 1) })
                        }
                    }
                    Btn {
                        visible: !dbg.d.hard || dbg.solved
                        small: true
                        text: dbg.h.sol ? "Ẩn lời giải" : "Xem lời giải"
                        onClicked: dbg.setHelp({ sol: !dbg.h.sol })
                    }
                }
                Repeater {
                    model: dbg.d.hints.slice(0, dbg.h.hints)
                    Note { required property var modelData; required property int index; Layout.fillWidth: true; note: ({ note: modelData, kind: "warn" }); label: "Gợi ý " + (index + 1) }
                }
                Rectangle {
                    visible: dbg.h.sol && (!dbg.d.hard || dbg.solved)
                    Layout.fillWidth: true
                    implicitHeight: solCol.implicitHeight + 20; radius: 9
                    color: app.cardHi; border.color: app.lineStrong
                    ColumnLayout {
                        id: solCol
                        x: 10; y: 10; width: parent.width - 20; spacing: 5
                        Caps { text: "Lời giải (chạy lần lượt)" }
                        Repeater {
                            model: dbg.d.fix
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: fixText.implicitHeight + 12; radius: 6; color: app.codeBg
                                Text {
                                    id: fixText
                                    x: 9; y: 6; width: parent.width - 18
                                    text: parent.modelData
                                    font.family: app.mono; font.pixelSize: 12; color: app.codeInk
                                    wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                }
                            }
                        }
                    }
                }
                Note {
                    visible: dbg.solved
                    Layout.fillWidth: true
                    note: ({ note: "**Đã khắc phục.** Nguyên nhân gốc: " + dbg.d.cause, kind: "tip" })
                    label: "Hoàn thành"
                }
            }
        }
        Terminal {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.rightMargin: 14; Layout.bottomMargin: 14
            key: "dbg:" + dbg.d.id
            opts: ({ lesson: dbg.l.id, debug: dbg.d.id, host: dbg.d.host, user: dbg.d.user, extra: "Hãy tự chẩn đoán: bắt đầu từ triệu chứng ở bên cạnh." })
        }
    }

    // ---------------------------------------------------------------- terminal (kiểu herdr: panel tối, tab tiêu đề, PTY thật)
    component Terminal: Rectangle {
        id: term
        property string key
        property var opts
        // copia superficial: así cada cambio (termRev) notifica a todos los bindings que dependen de sess
        readonly property var sess: { void app.termRev; const t = app.terms[key]; return t ? Object.assign({}, t) : null; }
        readonly property var snap: sess ? sess.snap : null
        readonly property real cellW: tm.advanceWidth
        readonly property real cellH: Math.ceil(tm.height * 1.18)
        readonly property int wantCols: Math.max(20, Math.floor(grid.width / Math.max(1, cellW)))
        readonly property int wantRows: Math.max(4, Math.floor(grid.height / Math.max(1, cellH)))
        function begin(): void {
            if (!key || !opts) return;
            app.openTerm(key, opts, wantRows, wantCols);
            app.activeTerm = key;
        }
        onKeyChanged: Qt.callLater(begin)
        Component.onCompleted: Qt.callLater(begin)
        onWantColsChanged: sizeTimer.restart()
        onWantRowsChanged: sizeTimer.restart()
        Timer { id: sizeTimer; interval: 120; onTriggered: if (term.sess) app.termResize(term.key, term.wantRows, term.wantCols) }
        TextMetrics { id: tm; font.family: app.mono; font.pixelSize: 13; text: "M" }

        radius: 10
        color: "#161513"
        border.color: "#2a2723"
        Rectangle { x: 1.5; y: 2.5; z: -1; width: parent.width; height: parent.height; radius: 10; color: app.drop }
        TapHandler { onTapped: input.forceActiveFocus() }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            // thanh tab giống herdr: chấm trạng thái + tên phiên + nút
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                color: "#1d1b18"
                radius: 10
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 10; color: parent.color }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2e2a24" }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                    Rectangle {
                        implicitHeight: 24; implicitWidth: tabRow.implicitWidth + 20; radius: 6
                        color: "#2a2722"
                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent; spacing: 7
                            Rectangle {
                                implicitWidth: 8; implicitHeight: 8; radius: 4
                                color: !term.sess ? "#6b645a" : term.sess.status === "run" ? "#8fc27a" : term.sess.status === "starting" ? "#e5c07b" : "#e06c60"
                            }
                            Text {
                                text: term.opts ? term.opts.user + "@" + term.opts.host + (term.opts.debug ? " · sự cố" : " · lab") : ""
                                font.family: app.mono; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#ddd3c2"
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: !term.sess ? "" : term.sess.status === "starting" ? (term.sess.note || "Đang khởi động container Linux…")
                              : term.sess.status === "run" ? "container Linux thật · docker/kiri" : term.sess.status === "exit" ? "phiên đã kết thúc" : "lỗi"
                        font.family: app.mono; font.pixelSize: 11; color: "#8a8174"; elide: Text.ElideRight
                    }
                    Rectangle {
                        implicitWidth: rsl.implicitWidth + 16; implicitHeight: 22; radius: 6
                        color: rsHover.hovered ? "#3a342c" : "#2d2923"
                        HoverHandler { id: rsHover }
                        Text { id: rsl; anchors.centerIn: parent; text: "Đặt lại"; font.family: app.mono; font.pixelSize: 11; color: "#ddd3c2" }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.termReset(term.key) }
                    }
                }
            }
            Item {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 12; Layout.rightMargin: 8; Layout.topMargin: 6; Layout.bottomMargin: 8
                clip: true

                Column {
                    Repeater {
                        model: { void app.termRev; return term.snap ? term.snap.rows.length : 0; }
                        Text {
                            required property int index
                            width: grid.width; height: term.cellH
                            font.family: app.mono; font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            color: "#e9e1d3"
                            textFormat: Text.RichText
                            wrapMode: Text.NoWrap
                            text: { void app.termRev; return term.snap && term.snap.rows[index] ? app.rowHtml(term.snap.rows[index]) : ""; }
                        }
                    }
                }
                // con trỏ
                Rectangle {
                    visible: !!term.snap && term.snap.cursor && !term.snap.dead && input.activeFocus
                    x: term.snap ? term.snap.cx * term.cellW : 0
                    y: term.snap ? term.snap.cy * term.cellH : 0
                    width: term.cellW; height: term.cellH
                    color: "#9fd38f"; opacity: 0.7
                    SequentialAnimation on opacity { loops: Animation.Infinite; running: input.activeFocus; NumberAnimation { to: 0.25; duration: 550 } NumberAnimation { to: 0.7; duration: 550 } }
                }
                // trạng thái / lỗi
                Text {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 520)
                    visible: !term.snap || (!!term.sess && term.sess.status === "error")
                    wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    font.family: app.mono; font.pixelSize: 12
                    color: term.sess && term.sess.status === "error" ? "#ff9b85" : "#8a8174"
                    text: !term.sess ? "" : term.sess.status === "error" ? term.sess.error : (term.sess.note || "Đang dựng container Linux cho bài này…\n(lần đầu có thể mất 1–2 phút để dựng image)")
                }
                // bản nháp của bộ gõ (Unikey/fcitx gửi từng ký tự ở dạng preedit tới khi bấm Space): vẽ ngay tại con trỏ
                Rectangle {
                    visible: input.preeditText !== ""
                    x: term.snap ? term.snap.cx * term.cellW : 0
                    y: term.snap ? term.snap.cy * term.cellH : 0
                    width: preeditLbl.implicitWidth; height: term.cellH
                    color: "#161513"
                    Text {
                        id: preeditLbl
                        anchors.verticalCenter: parent.verticalCenter
                        text: input.preeditText
                        font.family: app.mono; font.pixelSize: 13; font.underline: true
                        color: "#e9e1d3"
                    }
                }
                // nhập chữ: TextInput ẩn (hỗ trợ bộ gõ tiếng Việt); phím đặc biệt xử lý ở Keys.onPressed
                TextInput {
                    id: input
                    x: term.snap ? term.snap.cx * term.cellW : 0
                    y: term.snap ? term.snap.cy * term.cellH : 0
                    width: 2; height: term.cellH
                    opacity: 0
                    focus: true
                    font.family: app.mono; font.pixelSize: 13
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    onTextChanged: if (text !== "" && preeditText === "") { app.termInput(term.key, text); text = ""; }
                    Keys.onPressed: event => {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        const alt = (event.modifiers & Qt.AltModifier) !== 0;
                        const send = t => { app.termInput(term.key, t); event.accepted = true; };
                        const k = event.key;
                        const page = Math.max(1, (term.snap ? term.snap.rows.length : 20) - 2);
                        if (ctrl && shift && k === Qt.Key_V) { input.paste(); event.accepted = true; return; }
                        if (shift && k === Qt.Key_PageUp) { app.call("rscroll", { key: term.key, delta: page }); event.accepted = true; return; }
                        if (shift && k === Qt.Key_PageDown) { app.call("rscroll", { key: term.key, delta: -page }); event.accepted = true; return; }
                        if (k === Qt.Key_Return || k === Qt.Key_Enter) return send("\r");
                        if (k === Qt.Key_Backspace) return send(ctrl ? "\x17" : "\x7f");
                        if (k === Qt.Key_Tab) return send("\t");
                        if (k === Qt.Key_Backtab) return send("\x1b[Z");
                        if (k === Qt.Key_Escape) return send("\x1b");
                        if (k === Qt.Key_Up) return send(ctrl ? "\x1b[1;5A" : "\x1b[A");
                        if (k === Qt.Key_Down) return send(ctrl ? "\x1b[1;5B" : "\x1b[B");
                        if (k === Qt.Key_Right) return send(ctrl ? "\x1b[1;5C" : "\x1b[C");
                        if (k === Qt.Key_Left) return send(ctrl ? "\x1b[1;5D" : "\x1b[D");
                        if (k === Qt.Key_Home) return send("\x1b[H");
                        if (k === Qt.Key_End) return send("\x1b[F");
                        if (k === Qt.Key_PageUp) return send("\x1b[5~");
                        if (k === Qt.Key_PageDown) return send("\x1b[6~");
                        if (k === Qt.Key_Delete) return send("\x1b[3~");
                        if (k === Qt.Key_Insert) return send("\x1b[2~");
                        if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return send(["\x1bOP", "\x1bOQ", "\x1bOR", "\x1bOS", "\x1b[15~", "\x1b[17~", "\x1b[18~", "\x1b[19~", "\x1b[20~", "\x1b[21~", "\x1b[23~", "\x1b[24~"][k - Qt.Key_F1]);
                        if (ctrl && !alt && k >= Qt.Key_A && k <= Qt.Key_Z) return send(String.fromCharCode(k - Qt.Key_A + 1));
                        if (ctrl && k === Qt.Key_BracketLeft) return send("\x1b");
                        if (ctrl && k === Qt.Key_Backslash) return send("\x1c");
                        if (ctrl && k === Qt.Key_Space) return send("\x00");
                        if (alt && !ctrl && event.text.length) return send("\x1b" + event.text);
                    }
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => app.call("rscroll", { key: term.key, delta: event.angleDelta.y > 0 ? 3 : -3 })
                }
            }
        }
    }

    // ---------------------------------------------------------------- timeline các bước
    component Timeline: Rectangle {
        implicitHeight: tlCol.implicitHeight + 18
        radius: 10
        color: app.card
        border.color: app.line
        ColumnLayout {
            id: tlCol
            x: 12; y: 9; width: parent.width - 24
            spacing: 6
            RowLayout {
                Caps { text: "Trong bài này"; color: app.ink; Layout.fillWidth: true }
                Label { text: "Bước " + (app.step + 1) + " / " + app.steps.length; font.pixelSize: 11; color: app.muted }
            }
            Flickable {
                Layout.fillWidth: true
                implicitHeight: 50
                contentWidth: Math.max(width, tlRow.implicitWidth)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: tlRow
                    readonly property real cell: Math.max(86, parent.width / Math.max(1, app.steps.length))
                    Repeater {
                        model: app.steps
                        Item {
                            id: ts
                            required property var modelData
                            required property int index
                            readonly property bool active: index === app.step
                            readonly property bool isDone: { void app.rev; void app.step; return app.stepDone(modelData, index); }
                            readonly property bool prevDone: { void app.rev; void app.step; return index > 0 && app.stepDone(app.steps[index - 1], index - 1); }
                            width: tlRow.cell; height: 50
                            Rectangle {
                                visible: ts.index > 0
                                x: -parent.width / 2; y: 15; width: parent.width; height: 1
                                color: ts.prevDone ? app.green3 : app.lineStrong
                            }
                            Rectangle {
                                visible: ts.active
                                x: (parent.width - 28) / 2 + 1; y: 2.5; width: 28; height: 28; radius: 14; color: app.drop
                            }
                            Rectangle {
                                x: (parent.width - width) / 2; y: ts.active ? 1 : 2
                                width: ts.active ? 28 : 26; height: width; radius: width / 2
                                color: ts.active ? app.green : ts.isDone ? app.greenTile : app.card
                                border.color: ts.active ? app.ink : ts.isDone ? app.green3 : "#5f584f"
                                Label {
                                    anchors.centerIn: parent
                                    visible: ts.active || !ts.isDone
                                    text: ts.index + 1; font.pixelSize: 11; font.weight: Font.Bold
                                }
                                Sym { anchors.centerIn: parent; visible: !ts.active && ts.isDone; text: "check"; size: 14; color: app.greenInk }
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 34; width: parent.width - 6
                                horizontalAlignment: Text.AlignHCenter
                                text: ts.modelData.label; elide: Text.ElideRight
                                font.pixelSize: 11; font.weight: ts.active ? Font.Bold : Font.Normal
                                color: ts.active ? app.ink : app.muted
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.go(app.cur, ts.index) }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- panel bước (phải)
    component StepPanel: Card {
        id: sp
        readonly property var s: app.curStep
        readonly property var next: app.steps[app.step + 1] ?? null
        readonly property var nextLesson: app.cur + 1 < app.lessons.length ? app.lessons[app.cur + 1] : null
        readonly property var card: s && s.kind === "theory" ? app.lesson.theory[s.card] : null
        readonly property var parts: card ? app.splitCard(card.body) : null
        readonly property var tones: ({ "Khái niệm": "violet", "Cú pháp": "green", "Lưu ý": "red", "Quy trình": "mint", "Bảng lệnh": "orange", "Bảng tra": "orange" })
        readonly property string tag: !s ? "" : card ? card.tag : s.kind === "quiz" ? "Quiz" : s.kind === "lab" ? "Thực hành" : "Fix lỗi"
        readonly property string tone: !s ? "plain" : card ? (tones[card.tag] ?? "plain") : s.kind === "quiz" ? "orange" : s.kind === "lab" ? "green" : "red"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 15
            anchors.bottomMargin: 12
            spacing: 10

            RowLayout {
                Caps { text: "Bước " + (app.step + 1) + " / " + app.steps.length; color: app.ink; Layout.fillWidth: true }
                Tag { text: sp.tag; tone: sp.tone }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: spCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: spCol
                    width: parent.width
                    spacing: 10
                    Rich {
                        Layout.fillWidth: true
                        text: !sp.s ? "" : sp.card ? app.md(sp.card.title) : app.esc(sp.s.title)
                        font.pixelSize: 17; font.weight: Font.ExtraBold; lineHeight: 1.2
                    }
                    Rich {
                        Layout.fillWidth: true
                        visible: text !== ""
                        lineHeight: 1.2
                        text: {
                            void app.rev;
                            const l = app.lesson, s = sp.s;
                            if (!s || !l) return "";
                            if (sp.parts) return sp.parts.lead ? app.md(sp.parts.lead) : "";
                            if (s.kind === "quiz") return app.md(`${l.quiz.length} câu trắc nghiệm về **${l.short}**. Câu trả lời sai được gắn cờ để bạn ôn lại.\n\nĐúng: **${app.quizDone(l)}** / ${l.quiz.length}`);
                            if (s.kind === "lab") return app.md(`Gõ lệnh trong terminal \`${l.lab.user}@${l.lab.host}\`. Sau mỗi lệnh, hệ thống tự chấm các câu chưa pass.\n\nĐã pass: **${app.labDone(l)}** / ${l.lab.items.length}`);
                            return app.md(`${l.debugs.length} sự cố mô phỏng: đọc triệu chứng, tìm nguyên nhân rồi sửa ngay trong terminal.\n\nĐã sửa: **${app.debugDone(l)}** / ${l.debugs.length}`);
                        }
                    }
                    Note {
                        Layout.fillWidth: true
                        label: "Ý chính"
                        visible: !!note
                        note: !sp.s ? null
                            : sp.parts ? sp.parts.key
                            : sp.s.kind === "quiz" ? { note: "Trả lời hết các câu thì lượt làm được lưu vào trang **Kết quả** cùng điểm số.", kind: "tip" }
                            : sp.s.kind === "lab" ? { note: "Bí thì mở **gợi ý** ở từng câu. Cách làm khác cho cùng kết quả vẫn được tính." }
                            : { note: "Đọc log và thông báo lỗi trước khi sửa. Đoán mò thường làm sự cố tệ hơn.", kind: "warn" }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Btn { icon: "arrow_back"; text: "Lùi"; enabled: app.step > 0; onClicked: app.go(app.cur, app.step - 1) }
                Btn {
                    Layout.fillWidth: true
                    primary: true
                    trailing: "arrow_forward"
                    text: sp.next ? "Tiếp: " + sp.next.label : sp.nextLesson ? "Bài tiếp: " + sp.nextLesson.short : "Đã hết khoá học"
                    enabled: !!sp.next || !!sp.nextLesson
                    onClicked: sp.next ? app.go(app.cur, app.step + 1) : app.go(app.cur + 1, 0)
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                Kbd { text: "←" }
                Kbd { text: "→" }
                Label { text: "chuyển bước ·"; font.pixelSize: 11; color: app.muted2 }
                Kbd { text: "Ctrl K" }
                Label { text: "tìm bài"; font.pixelSize: 11; color: app.muted2 }
            }
        }
    }

    component LearnList: Card {
        implicitHeight: llCol.implicitHeight + 24
        Flickable {
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: llCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: llCol
                width: parent.width
                spacing: 3
                Caps { text: "Bạn sẽ học"; color: app.ink; Layout.bottomMargin: 4 }
                Repeater {
                    model: app.steps
                    Rectangle {
                        id: lr
                        required property var modelData
                        required property int index
                        readonly property bool isDone: { void app.rev; void app.step; return app.stepDone(modelData, index); }
                        Layout.fillWidth: true
                        implicitHeight: lrRow.implicitHeight + 6
                        radius: 6
                        color: lrHover.hovered ? app.card : "transparent"
                        HoverHandler { id: lrHover }
                        RowLayout {
                            id: lrRow
                            x: 4; y: 3; width: parent.width - 8; spacing: 8
                            Rectangle {
                                Layout.alignment: Qt.AlignTop; Layout.topMargin: 1
                                implicitWidth: 14; implicitHeight: 14; radius: 3
                                color: lr.isDone ? app.green3 : app.cardHi
                                border.color: lr.isDone ? app.greenInk : app.muted2
                                Sym { anchors.centerIn: parent; visible: lr.isDone; text: "check"; size: 11; color: "#10200c" }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: lr.modelData.title
                                wrapMode: Text.Wrap
                                font.pixelSize: 12
                                font.weight: lr.index === app.step ? Font.Bold : Font.Normal
                                color: lr.index === app.step ? app.ink : app.ink2
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.go(app.cur, lr.index) }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- kết quả
    component ResultsPage: Card {
        id: rp
        color: app.sheet
        onVisibleChanged: if (visible) app.loadBackups()
        readonly property var rows: {
            void app.rev;
            return app.lessons.map((l, i) => {
                const runs = app.prog.hist.filter(x => x.l === l.id);
                const best = Math.max(app.quizDone(l), runs.reduce((b, x) => Math.max(b, x.s), 0));
                return { i: i, l: l, best: best, runs: runs.length, lab: app.labDone(l), dbg: app.debugDone(l), d: app.done(l), t: app.total(l) };
            });
        }
        readonly property var sum: {
            let q = 0, qn = 0, lb = 0, ln = 0, db = 0, dn = 0, full = 0;
            for (const r of rows) {
                q += r.best; qn += r.l.quiz.length; lb += r.lab; ln += r.l.lab.items.length;
                db += r.dbg; dn += r.l.debugs.length; if (r.d === r.t) full++;
            }
            return { q: q, qn: qn, lb: lb, ln: ln, db: db, dn: dn, full: full };
        }
        Scroller {
            anchors.fill: parent
            anchors.topMargin: 18
            maxW: 1000
            Caps { text: "Khoá học VPS Linux" }
            Label { text: "Kết quả của tôi"; font.pixelSize: 26; font.weight: Font.ExtraBold; font.letterSpacing: -0.45 }
            Label { text: "Điểm quiz tốt nhất, lab và sự cố đã xử lý của từng bài. Bấm vào một bài để học tiếp."; color: app.muted; font.pixelSize: 12 }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8
                Metric { icon: "flag"; label: "Bài hoàn thành"; value: rp.sum.full + " / " + app.lessons.length; ok: rp.sum.full === app.lessons.length }
                Metric { icon: "help"; label: "Quiz đúng"; value: rp.sum.q + " / " + rp.sum.qn }
                Metric { icon: "terminal"; label: "Lab đã pass"; value: rp.sum.lb + " / " + rp.sum.ln }
                Metric { icon: "bug_report"; label: "Sự cố đã sửa"; value: rp.sum.db + " / " + rp.sum.dn }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 12

                // ---- lưu và sao lưu
                Card {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: svCol.implicitHeight + 28
                    color: app.cardHi
                    border.color: app.lineStrong
                    ColumnLayout {
                        id: svCol
                        x: 16; y: 14; width: parent.width - 32
                        spacing: 8
                        Caps { text: "Lưu kết quả học tập"; color: app.ink }
                        Rich {
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            text: app.md("Tiến độ **tự động lưu** sau mỗi thao tác"
                                + (app.savedAt ? " (lần cuối " + app.clock(app.savedAt) + ")" : "")
                                + ", mỗi ngày giữ thêm một bản sao lưu tự động trong 30 ngày.\n**Xuất báo cáo** tạo file `.md` để đọc và file `.json` để khôi phục.")
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Btn { small: true; primary: true; icon: "download"; text: "Xuất báo cáo"; onClicked: app.exportReport() }
                            Btn { small: true; icon: "folder_open"; text: "Mở thư mục"; enabled: app.exportDir !== ""; onClicked: app.openExportDir() }
                        }
                        Label {
                            visible: app.lastExport !== ""
                            Layout.fillWidth: true
                            text: "Vừa xuất: " + app.lastExport.replace(Quickshell.env("HOME"), "~")
                            font.pixelSize: 11; color: app.greenInk; elide: Text.ElideMiddle
                        }
                        Caps { Layout.topMargin: 6; text: "Khôi phục từ bản sao lưu" }
                        Label {
                            visible: app.backupList.length === 0
                            Layout.fillWidth: true
                            text: "Chưa có bản sao lưu nào."
                            font.pixelSize: 12; color: app.muted
                        }
                        Repeater {
                            model: app.backupList.slice(0, 6)
                            RowLayout {
                                id: bk
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    implicitWidth: bkTag.implicitWidth + 12; implicitHeight: 20; radius: 10
                                    color: bk.modelData.kind === "auto" ? app.violet : app.mint
                                    border.color: app.ink2
                                    Label { id: bkTag; anchors.centerIn: parent; text: bk.modelData.kind === "auto" ? "Tự động" : "Đã xuất"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                Label { Layout.fillWidth: true; text: bk.modelData.name; elide: Text.ElideMiddle; font.pixelSize: 12 }
                                Label { text: app.dateTime(bk.modelData.mtime); font.pixelSize: 11; color: app.muted }
                                Btn { small: true; text: "Khôi phục"; onClicked: app.restoreFrom(bk.modelData.path) }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "Khôi phục sẽ gộp với tiến độ hiện tại, không làm mất gì. Bản sao lưu của bản web (JSON) đặt vào thư mục QuantumLearn cũng khôi phục được."
                            font.pixelSize: 11; color: app.muted
                        }
                    }
                }

                // ---- lịch sử quiz
                Card {
                    id: histCard
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: hsCol.implicitHeight + 28
                    color: app.cardHi
                    border.color: app.lineStrong
                    readonly property var items: { void app.rev; return app.prog.hist.slice(-12).reverse(); }
                    ColumnLayout {
                        id: hsCol
                        x: 16; y: 14; width: parent.width - 32
                        spacing: 6
                        Caps { text: "Lịch sử làm quiz"; color: app.ink }
                        Label {
                            visible: histCard.items.length === 0
                            text: "Chưa có lượt làm quiz nào."
                            font.pixelSize: 12; color: app.muted
                        }
                        Repeater {
                            model: histCard.items
                            RowLayout {
                                id: hr
                                required property var modelData
                                readonly property var l: app.lessons.find(x => x.id === modelData.l)
                                readonly property bool full: modelData.s === modelData.n
                                Layout.fillWidth: true
                                spacing: 8
                                Label { text: app.dateTime(hr.modelData.t); font.pixelSize: 11; color: app.muted }
                                Label { Layout.fillWidth: true; text: hr.l ? hr.l.short : hr.modelData.l; elide: Text.ElideRight; font.pixelSize: 12 }
                                Rectangle {
                                    implicitWidth: hsl.implicitWidth + 14; implicitHeight: 20; radius: 10
                                    color: hr.full ? app.green : hr.modelData.s * 2 >= hr.modelData.n ? app.orange : app.red
                                    border.color: app.ink2
                                    Label { id: hsl; anchors.centerIn: parent; text: hr.modelData.s + "/" + hr.modelData.n; font.pixelSize: 11; font.weight: Font.Bold; color: hr.full || hr.modelData.s * 2 >= hr.modelData.n ? app.ink : app.redInk }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: rtCol.implicitHeight + 2
                radius: 10
                color: app.cardHi
                border.color: app.lineStrong
                clip: true
                Column {
                    id: rtCol
                    x: 1; y: 1; width: parent.width - 2
                    Rectangle {
                        width: parent.width; height: 32; color: app.paper2
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.lineStrong }
                        ResultRow { anchors.fill: parent; cells: ["Bài", "Quiz", "Lab", "Sự cố", "Tiến độ"]; head: true }
                    }
                    Repeater {
                        model: rp.rows
                        Rectangle {
                            id: rr
                            required property var modelData
                            required property int index
                            width: rtCol.width; height: 32
                            color: rrHover.hovered ? app.card : "transparent"
                            Rectangle { visible: rr.index > 0; width: parent.width; height: 1; color: app.lineSoft }
                            HoverHandler { id: rrHover }
                            ResultRow {
                                anchors.fill: parent
                                done: rr.modelData.d === rr.modelData.t
                                cells: [
                                    (rr.modelData.i + 1) + ". " + rr.modelData.l.short,
                                    rr.modelData.runs || rr.modelData.best ? rr.modelData.best + "/" + rr.modelData.l.quiz.length : "–",
                                    rr.modelData.lab + "/" + rr.modelData.l.lab.items.length,
                                    rr.modelData.dbg + "/" + rr.modelData.l.debugs.length,
                                    Math.round(rr.modelData.d / Math.max(1, rr.modelData.t) * 100) + "%"
                                ]
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.go(rr.modelData.i, 0) }
                        }
                    }
                }
            }
        }
    }
    component ResultRow: RowLayout {
        id: rw
        property var cells: []
        property bool head: false
        property bool done: false
        spacing: 8
        Repeater {
            model: rw.cells
            Label {
                required property var modelData
                required property int index
                Layout.fillWidth: index === 0
                Layout.preferredWidth: index === 0 ? -1 : 76
                Layout.leftMargin: index === 0 ? 12 : 0
                Layout.rightMargin: index === rw.cells.length - 1 ? 12 : 0
                horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight
                text: modelData
                elide: Text.ElideRight
                font.pixelSize: rw.head ? 10.5 : 12.5
                font.weight: rw.head || (index === 4 && rw.done) ? Font.Bold : Font.Normal
                font.capitalization: rw.head ? Font.AllUppercase : Font.MixedCase
                color: rw.head ? app.muted : index === 4 && rw.done ? app.greenInk : app.ink
            }
        }
    }
}
