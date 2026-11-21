import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Quantum Store: cửa hàng ứng dụng cho pacman (repo chính thức) + AUR (qua paru/yay).
// App độc lập (tiến trình Quickshell riêng, giống Claude Agent HQ): mở bằng launcher `quantum-store`
// (cùng thư mục), đóng cửa sổ là thoát. Không dùng qs.services của shell: chỉ ĐỌC
// ~/.config/quantum/settings.json (ngôn ngữ, sáng/tối, màu nhấn) và colors.json của quantum-theme.
// Dữ liệu: backend.py (pacman -Ss/-Qs, AppStream, AUR RPC) → JSON.
// Cài/gỡ gói repo: pkexec pacman (hộp thoại polkit). Gói AUR: mở kitty chạy paru/yay.
// Không bao giờ chạy `pacman -Sy <gói>` (partial upgrade): database cũ thì nhắc cập nhật.
// Mở sẵn một trang: QS_STORE_OPEN="search:<từ khoá>" | "detail:<gói>" | "updates" | "installed"
// IPC: qs -p …/apps/store/shell.qml ipc call store open|close|refresh|search <q>|page <p>|detail <gói>|state
ShellRoot {
    id: app

    readonly property string dir: Quickshell.shellDir
    readonly property string backend: dir + "/backend.py"

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
    readonly property string lang: settings.ui?.lang === "en" ? "en" : "vi"

    // ------------------------------------------------------------------ giao diện (macOS)
    readonly property bool dark: (colors.mode ?? settings.appearance?.mode ?? "dark") !== "light"
    readonly property color win: dark ? "#1e1e1e" : "#f5f5f7"
    readonly property color side: dark ? "#262628" : "#e8e8ea"
    readonly property color content: dark ? "#1e1e1e" : "#ffffff"
    readonly property color card: dark ? "#2a2a2c" : "#f5f5f7"
    readonly property color cardHover: dark ? "#333336" : "#ececee"
    readonly property color fg: dark ? "#f2f2f4" : "#1d1d1f"
    readonly property color muted: dark ? "#9a9a9e" : "#6e6e73"
    readonly property color line: dark ? "#3a3a3c" : "#d8d8dc"
    readonly property color accent: settings.appearance?.accent || "#007aff"
    readonly property color danger: "#ff453a"
    readonly property color warn: "#ff9f0a"
    readonly property string uiFont: "Inter"
    readonly property string iconFont: "Material Symbols Rounded"

    function tr(vi: string, en: string): string { return app.lang === "en" ? en : vi; }

    // ------------------------------------------------------------------ dữ liệu
    property var pkgs: []               // [{ n, r, v, d, i (bản đã cài), e (cài chủ động) }]
    property var byName: ({})
    property var apps: []               // ứng dụng AppStream: { p, id, n, s, desc, c, k, icf, icn, sh, u, dsk, con }
    property var appByPkg: ({})
    property bool hasAppstream: false
    property bool dbLocked: false
    property bool multilib: true
    property bool loading: false
    property bool loaded: false
    property int rev: 0                 // tăng mỗi lần nạp lại: buộc các binding tính lại

    // điều hướng
    property string page: "discover"    // discover | category | installed | updates | search
    property string category: ""
    property string query: ""
    property string detail: ""          // tên gói đang xem chi tiết ("" = không)
    property var info: null
    property bool infoLoading: false

    // thao tác cài/gỡ (mỗi lần một gói)
    property string opPkg: ""
    property string opKind: ""          // install | remove | aur
    property string opLog: ""
    readonly property bool busy: opPkg !== ""
    property string toastText: ""
    property bool toastError: false
    property string errorLog: ""

    // AUR
    property var aurResults: []
    property bool aurLoading: false
    property string aurError: ""

    readonly property var categories: [
        { id: "AudioVideo", vi: "Âm thanh & Video", en: "Music & Video", icon: "movie" },
        { id: "Graphics", vi: "Đồ hoạ & Thiết kế", en: "Graphics & Design", icon: "palette" },
        { id: "Development", vi: "Lập trình", en: "Developer Tools", icon: "code" },
        { id: "Office", vi: "Văn phòng", en: "Productivity", icon: "description" },
        { id: "Network", vi: "Internet", en: "Internet", icon: "language" },
        { id: "Game", vi: "Trò chơi", en: "Games", icon: "sports_esports" },
        { id: "Education", vi: "Giáo dục", en: "Education", icon: "school" },
        { id: "Science", vi: "Khoa học", en: "Science", icon: "science" },
        { id: "Utility", vi: "Tiện ích", en: "Utilities", icon: "handyman" },
        { id: "System", vi: "Hệ thống", en: "System", icon: "settings" }
    ]
    function catTitle(id: string): string {
        const c = categories.find(x => x.id === id);
        return c ? tr(c.vi, c.en) : id;
    }

    // Ứng dụng nổi bật (chỉ hiện cái có trong repo)
    readonly property var featuredNames: ["firefox", "chromium", "thunderbird", "libreoffice-fresh", "gimp", "inkscape",
        "krita", "blender", "kdenlive", "obs-studio", "vlc", "mpv", "audacity", "steam", "discord", "telegram-desktop",
        "signal-desktop", "keepassxc", "qbittorrent", "obsidian", "code", "zed", "neovim", "btop"]

    // gói → các .desktop của nó (cùng cách quét với services/Apps.qml của shell)
    property var pkgDesktop: ({})
    function scanDesktop(): void { if (!desktopProc.running) desktopProc.running = true; }
    Process {
        id: desktopProc
        command: ["sh", "-c",
            "IFS=:; for d in ${XDG_DATA_HOME:-$HOME/.local/share} ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do " +
            "for f in \"$d\"/applications/*.desktop; do [ -e \"$f\" ] || continue; " +
            "case $f in */flatpak/*|$HOME/*) continue;; esac; " +
            "id=${f##*/}; p=$(pacman -Qoq \"$f\" 2>/dev/null) && echo \"${id%.desktop}\t$p\"; done; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of text.split("\n")) {
                    const [id, p] = line.split("\t");
                    if (!id || !p) continue;
                    if (!m[p]) m[p] = [];
                    if (!m[p].includes(id)) m[p].push(id);
                }
                app.pkgDesktop = m;
                app.rev++;
            }
        }
    }

    // cập nhật: checkupdates (bản sao riêng của database, không cần quyền root)
    property var updList: []            // [{ name, from, to }]
    property bool updChecking: false
    readonly property int updCount: updList.length
    readonly property var updSet: {
        const s = {};
        for (const u of updList) s[u.name] = u;
        return s;
    }
    function checkUpdates(): void {
        if (updProc.running) return;
        updChecking = true;
        updProc.running = true;
    }
    Process {
        id: updProc
        command: ["sh", "-c", "checkupdates 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const items = [];
                for (const line of text.split("\n")) {
                    const m = line.match(/^(\S+) (\S+) -> (\S+)/);
                    if (m) items.push({ name: m[1], from: m[2], to: m[3] });
                }
                app.updList = items.sort((a, b) => a.name.localeCompare(b.name));
                app.updChecking = false;
            }
        }
    }
    // Cập nhật toàn hệ thống trong kitty (giống Updates.update() của shell)
    function updateAll(): void {
        if (sysUpdProc.running) return;
        sysUpdProc.running = true;
    }
    Process {
        id: sysUpdProc
        command: ["kitty", "--title", "Quantum Store — cập nhật / update", "sh", "-c",
            "if command -v paru >/dev/null; then paru -Syu; else sudo pacman -Syu; fi; " +
            "printf '\\n%s' 'Xong / Done — Enter'; read _"]
        onExited: app.afterChange()
    }
    // Báo cho shell (biểu tượng cập nhật trên thanh) và nạp lại dữ liệu của Store
    function afterChange(): void {
        reload();
        checkUpdates();
        scanDesktop();
        Quickshell.execDetached(["sh", "-c", "qs -c caelestia ipc call updates check >/dev/null 2>&1 || qs -c quantum ipc call updates check >/dev/null 2>&1; true"]);
    }

    // ------------------------------------------------------------------ tra cứu
    function norm(s: string): string { return (s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase(); }
    function isInstalled(name: string): bool { return !!(byName[name]?.i); }
    function nameOf(name: string): string { return appByPkg[name]?.n || name; }
    function summaryOf(name: string): string { return appByPkg[name]?.s || byName[name]?.d || ""; }

    function entryOf(name: string): var {
        void rev;
        const a = appByPkg[name];
        if (a?.dsk) {
            const e = DesktopEntries.byId(a.dsk);
            if (e) return e;
        }
        for (const id of (pkgDesktop[name] ?? [])) {
            const e = DesktopEntries.byId(id);
            if (e && !e.noDisplay) return e;
        }
        return null;
    }

    function iconOf(name: string): string {
        const a = appByPkg[name];
        if (a?.icf) return "file://" + a.icf;
        const e = isInstalled(name) ? entryOf(name) : null;
        for (const c of [e?.icon, a?.icn, name]) {
            if (!c) continue;
            if (c.startsWith("/")) return "file://" + c;
            const p = Quickshell.iconPath(c, true);
            if (p) return p;
        }
        return "";
    }

    // available | installed | update | busy
    function stateOf(name: string): string {
        if (opPkg === name) return "busy";
        if (isInstalled(name)) return updSet[name] ? "update" : "installed";
        return "available";
    }

    // ------------------------------------------------------------------ danh sách tính sẵn
    function rankApps(list: var): var {
        return list.slice().sort((a, b) =>
            ((b.sh.length > 0) - (a.sh.length > 0)) || ((!!b.icf) - (!!a.icf)) || a.n.localeCompare(b.n));
    }
    readonly property var featured: {
        void rev;
        return featuredNames.filter(n => byName[n]);
    }
    readonly property var appsByCat: {
        const m = {};
        for (const c of categories) m[c.id] = [];
        for (const a of apps) {
            if (a.con) continue;
            const c = categories.find(c => a.c.includes(c.id));
            if (c) m[c.id].push(a);
        }
        for (const k in m) m[k] = rankApps(m[k]);
        return m;
    }

    // ------------------------------------------------------------------ tìm kiếm
    // Một danh sách chung (repo + AUR) xếp theo độ khớp, rồi độ phổ biến:
    //   tên trùng hẳn > tên gọi quen (vscode → code) > tên bắt đầu bằng > tên chứa > mọi từ có trong tên/mô tả/từ khoá.
    //   + phổ biến (pkgstats với gói repo, vote với AUR) + đã cài + là ứng dụng (AppStream).
    //   − gói phụ (ngôn ngữ, docs, debug) trừ khi bạn gõ đúng chúng.
    // Tên gọi quen → tên gói
    readonly property var aliases: ({
        "vscode": ["code", "visual-studio-code-bin"], "vs code": ["code", "visual-studio-code-bin"],
        "visual studio code": ["visual-studio-code-bin", "code"],
        "chrome": ["google-chrome", "chromium"], "google chrome": ["google-chrome"],
        "office": ["libreoffice-fresh", "onlyoffice-bin"], "word": ["libreoffice-fresh"], "excel": ["libreoffice-fresh"],
        "powerpoint": ["libreoffice-fresh"], "photoshop": ["gimp", "krita"], "illustrator": ["inkscape"],
        "obs": ["obs-studio"], "edge": ["microsoft-edge-stable-bin"], "spotify": ["spotify-launcher"]
    })
    // Tiếng Việt (không dấu) → từ khoá tiếng Anh trong mô tả gói
    readonly property var synonyms: [
        ["trinh duyet", "web browser"], ["nghe nhac", "music player"], ["xem phim", "video player"], ["xem video", "video player"],
        ["chinh sua anh", "image editor"], ["sua anh", "image editor"], ["ve tranh", "painting"], ["van phong", "office suite"],
        ["go tieng viet", "vietnamese input"], ["bo go", "input method"], ["tro choi", "game"], ["soan thao", "text editor"],
        ["lap trinh", "ide"], ["giai nen", "archive"], ["nen file", "archive"], ["ghi am", "audio recorder"],
        ["quay man hinh", "screen recorder"], ["chup man hinh", "screenshot"], ["tai xuong", "download manager"],
        ["mat khau", "password manager"], ["may ao", "virtual machine"], ["dung video", "video editor"], ["chinh sua video", "video editor"],
        ["xem phim", "media player"], ["xem video", "media player"], ["nghe nhac", "audio player"]
    ]
    // tiếng Anh: mô tả gói hay dùng từ khác (chỉ dùng để dò trong máy, không gửi lên AUR)
    readonly property var enSynonyms: [
        ["video player", "media player"], ["music player", "audio player"], ["photo editor", "image editor"]
    ]
    readonly property var noise: /(-i18n-|-l10n-|-langpack|-lang-|-docs?$|-debug$|-headers$|-plugins?-|-plugins?$|-module$|-backend$|-info$|-data$|-common$)/
    // thư viện / binding: chỉ khớp qua mô tả thì xếp sau ứng dụng
    readonly property var libLike: /^(lib|python-|python2-|perl-|haskell-|ruby-|rust-|nodejs-|node-|lua-|go-|php-|r-|ocaml-|java-|qt[56]-|kf[56]-|gst-|gtk[234]?-|vlc-plugin|gstreamer)/

    // chữ để dò cho mỗi gói (tính một lần khi nạp): tên + mô tả + tên/tóm tắt/từ khoá AppStream
    property var hay: ({})
    function buildHay(): void {
        const h = {};
        for (const p of pkgs) {
            const a = appByPkg[p.n];
            h[p.n] = words(p.n + " " + p.d + (a ? " " + norm(a.n + " " + a.s + " " + a.k) : ""));
        }
        hay = h;
    }

    // " từ1 từ2 … " (chữ thường, bỏ dấu câu): để so khớp theo đầu từ
    function words(t: string): string { return " " + t.toLowerCase().replace(/[^a-z0-9]+/g, " ") + " "; }

    readonly property var qinfo: {
        const q = norm(query.trim()).replace(/\s+/g, " ");
        if (!q) return null;
        const vs = [q];
        for (const [vi, en] of synonyms)
            if (q.includes(vi)) vs.push(q.replace(vi, en).trim());
        const translated = vs.length > 1 ? vs[1] : "";
        for (const [a, b] of enSynonyms)
            for (const v of vs.slice())
                if (v.includes(a)) vs.push(v.replace(a, b));
        return {
            q: q,
            aurQ: translated,           // truy vấn tiếng Việt → tìm AUR bằng tiếng Anh
            noisy: noise.test(q.replace(/ /g, "-")),
            alias: aliases[q] ?? [],
            // biến thể đầu = đúng chữ bạn gõ; các biến thể sau (dịch / đồng nghĩa) chỉ dò theo từ trong mô tả
            variants: vs.map((v, i) => ({ s: v, dash: v.replace(/ /g, "-"), words: v.split(" ").filter(w => w.length > 0), derived: i > 0 }))
        };
    }

    function matchScore(name: string, h: string, appName: string, v: var): real {
        const d = v.dash;
        const token = "-" + name + "-";
        const wordBonus = v.words.some(w => token.includes("-" + w + "-")) ? 60 : 0;
        if (v.derived)
            return v.words.every(w => w.length >= 5 ? h.includes(w) : h.includes(" " + w)) ? 220 + wordBonus : -1;
        if (name === d) return 1000;
        if (appName && appName === v.s) return 950;
        if (name.startsWith(d)) return 650 - Math.min(150, (name.length - d.length) * 5);
        if (appName && appName.startsWith(v.s)) return 600;
        if (name.includes(d)) return 450 - Math.min(150, (name.length - d.length) * 3);
        if (v.words.length > 1 && v.words.every(w => name.includes(w))) return 400;
        // từng từ phải có trong tên / mô tả: từ ngắn khớp đầu từ ("ide" ≠ "video"), từ dài khớp cả giữa từ ("media" ⊂ "multimedia")
        if (v.words.every(w => w.length >= 5 ? h.includes(w) : h.includes(" " + w)))
            return 220 + wordBonus;
        return -1;
    }

    function scorePkg(name: string, h: string, extra: var): real {
        const qi = qinfo;
        const a = appByPkg[name];
        const appName = a ? norm(a.n) : "";
        let best = -1;
        const ai = qi.alias.indexOf(name);
        if (ai >= 0) best = 900 - ai * 10;
        for (const v of qi.variants) best = Math.max(best, matchScore(name, h, appName, v));
        if (best < 0) return -1;
        const byDesc = best < 400;          // khớp chỉ nhờ mô tả, không nhờ tên
        // độ phổ biến: gói thư viện được cài kèm rất nhiều nên chỉ tính nửa khi khớp qua mô tả
        if (extra.aur) best += Math.min(120, Math.log(1 + (extra.votes ?? 0)) / Math.LN10 * 40) - 80;
        else if (extra.pop) best += Math.min(200, Math.sqrt(extra.pop) * (byDesc ? 14 : 24));
        if (extra.installed) best += 30;
        if (a && !a.con) best += byDesc ? 120 : 50;
        if (byDesc && !qi.q.startsWith("lib") && libLike.test(name)) best -= 150;
        // gói phụ (ngôn ngữ, plugin, docs): phạt, trừ khi bạn gõ đúng nó ("firefox vi", "vlc plugin")
        const allInName = qi.variants[0].words.length > 1 && qi.variants[0].words.every(w => name.includes(w));
        if (!qi.noisy && !allInName && noise.test(name)) best -= 350;
        return best;
    }

    // [{ n, r, v, d, i, votes, ood, score }] tốt nhất trước
    readonly property var results: {
        const qi = qinfo;
        if (!qi) return [];
        const out = [];
        for (const p of pkgs) {
            const sc = scorePkg(p.n, hay[p.n] ?? "", { pop: p.pp, installed: !!p.i, aur: p.r === "aur" });
            if (sc >= 0) out.push({ n: p.n, r: p.r, v: p.v, d: p.d, i: p.i, score: sc });
        }
        for (const r of aurResults) {
            if (byName[r.n]) continue;              // đã có (repo hoặc AUR đã cài)
            const h = words(r.n + " " + r.d);
            const sc = scorePkg(r.n, h, { aur: true, votes: r.votes });
            if (sc >= 0) out.push({ n: r.n, r: "aur", v: r.v, d: r.d, i: "", votes: r.votes, ood: r.ood, score: sc });
        }
        out.sort((x, y) => y.score - x.score || x.n.localeCompare(y.n));
        return out.slice(0, 400);
    }
    // ứng dụng (AppStream) nằm trong 40 kết quả đầu: hiện thành thẻ ở trên cùng
    readonly property var appResults: results.slice(0, 40).filter(r => appByPkg[r.n] && !appByPkg[r.n].con).slice(0, 12).map(r => r.n)
    readonly property var listResults: {
        const shown = {};
        for (const n of appResults) shown[n] = true;
        return results.filter(r => !shown[r.n]);
    }
    readonly property bool anyAur: results.some(r => r.r === "aur")

    // đã cài
    property string instFilter: "apps"     // apps | explicit | all | aur
    property string instQuery: ""
    readonly property var installedList: {
        void rev;
        const q = instQuery.trim().toLowerCase();
        const out = [];
        for (const p of pkgs) {
            if (!p.i) continue;
            if (instFilter === "apps" && !(appByPkg[p.n] || (pkgDesktop[p.n] ?? []).length)) continue;
            if (instFilter === "explicit" && !p.e) continue;
            if (instFilter === "aur" && p.r !== "aur") continue;
            if (q && !p.n.includes(q) && !nameOf(p.n).toLowerCase().includes(q)) continue;
            out.push(p);
        }
        return out.sort((a, b) => nameOf(a.n).localeCompare(nameOf(b.n)));
    }
    readonly property int installedCount: {
        void rev;
        return pkgs.filter(p => p.i).length;
    }

    // ------------------------------------------------------------------ hành động
    function go(p, cat): void {
        detail = "";
        page = p;
        category = cat ?? "";
    }
    function show(name: string): void {
        detail = name;
        info = null;
        infoLoading = true;
        infoProc.want = name;
        infoProc.command = ["python3", "-I", app.backend, "info", name];
        infoProc.running = false;
        infoProc.running = true;
    }
    function reload(): void {
        if (catProc.running) return;
        loading = true;
        catProc.command = ["python3", "-I", app.backend, "catalog", app.lang];
        catProc.running = true;
    }
    function validName(n: string): bool { return /^[a-zA-Z0-9@_+][a-zA-Z0-9@._+-]*$/.test(n); }

    function install(name: string): void {
        if (busy || !validName(name)) return;
        const p = byName[name];
        errorLog = "";
        opLog = "";
        opPkg = name;
        if (!p || p.r === "aur") {
            opKind = "aur";
            aurProc.command = ["kitty", "--title", "Quantum Store — AUR", "sh", "-c",
                "if command -v paru >/dev/null; then paru -S -- \"$1\"; " +
                "elif command -v yay >/dev/null; then yay -S -- \"$1\"; " +
                "else echo 'Cần paru hoặc yay để cài gói AUR / An AUR helper (paru or yay) is required'; fi; " +
                "printf '\\n%s' 'Xong / Done — Enter'; read _", "sh", name];
            aurProc.running = true;
            return;
        }
        opKind = "install";
        opProc.command = ["pkexec", "pacman", "-S", "--noconfirm", "--needed", "--", name];
        opProc.running = true;
    }
    function remove(name: string): void {
        if (busy || !validName(name)) return;
        errorLog = "";
        opLog = "";
        opPkg = name;
        opKind = "remove";
        opProc.command = ["pkexec", "pacman", "-Rns", "--noconfirm", "--", name];
        opProc.running = true;
    }
    function launch(name: string): void {
        const e = entryOf(name);
        if (!e) return;
        if (e.runInTerminal) Quickshell.execDetached(["kitty", "-e", ...e.command]);
        else e.execute();
    }

    function opDone(code: int): void {
        const name = opPkg, kind = opKind;
        opPkg = "";
        opKind = "";
        const label = nameOf(name);
        if (kind === "aur") {
            // không biết paru thành công hay không: xem lại trạng thái thật
            notify(tr("Đã đóng trình cài AUR cho ", "AUR installer closed for ") + label, false);
        } else if (code === 0) {
            notify(kind === "remove" ? tr("Đã gỡ ", "Removed ") + label : tr("Đã cài ", "Installed ") + label, false);
        } else if (code === 126 || code === 127) {
            notify(tr("Đã huỷ (chưa xác thực)", "Cancelled (not authenticated)"), true);
        } else {
            const log = opLog;
            let msg = kind === "remove" ? tr("Không gỡ được ", "Couldn't remove ") + label : tr("Không cài được ", "Couldn't install ") + label;
            if (/db\.lck|unable to lock database/.test(log))
                msg += tr(": pacman đang chạy ở nơi khác", ": pacman is already running");
            else if (/failed retrieving file|404|could not satisfy|not found/i.test(log))
                msg += tr(": dữ liệu gói đã cũ, hãy cập nhật hệ thống trước", ": package database is outdated, update the system first");
            else if (/breaks dependency|required by/.test(log))
                msg += tr(": gói khác đang cần nó", ": other packages depend on it");
            errorLog = log.trim();
            notify(msg, true);
        }
        afterChange();
        if (detail === name) show(name);
    }
    function notify(text: string, error: bool): void {
        toastText = text;
        toastError = error;
        toastTimer.restart();
    }

    function fmtVotes(n: int): string { return n >= 1000 ? (n / 1000).toFixed(1) + "k" : String(n); }

    // ------------------------------------------------------------------ tiến trình
    Process {
        id: catProc
        stdout: StdioCollector {
            onStreamFinished: {
                app.loading = false;
                let d;
                try { d = JSON.parse(text); } catch (e) { console.warn("store: catalog", e); return; }
                const by = {};
                for (const p of d.pkgs) by[p.n] = p;
                const ab = {};
                for (const a of d.apps) ab[a.p] = a;
                app.pkgs = d.pkgs;
                app.byName = by;
                app.apps = d.apps;
                app.appByPkg = ab;
                app.buildHay();
                app.hasAppstream = d.appstream;
                app.dbLocked = d.locked;
                app.multilib = d.multilib !== false;
                app.loaded = true;
                app.rev++;
            }
        }
    }

    Process {
        id: infoProc
        property string want: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (infoProc.want !== app.detail) return;
                app.infoLoading = false;
                try { app.info = JSON.parse(text); } catch (e) { app.info = { error: String(e) }; }
            }
        }
    }

    Process {
        id: opProc
        stdout: SplitParser { onRead: l => app.opLog += l + "\n" }
        stderr: SplitParser { onRead: l => app.opLog += l + "\n" }
        onExited: code => app.opDone(code)
    }
    Process {
        id: aurProc
        onExited: code => app.opDone(code)
    }

    Process {
        id: aurSearch
        property string want: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (aurSearch.want !== app.query.trim()) return;
                app.aurLoading = false;
                try {
                    const d = JSON.parse(text);
                    app.aurResults = d.results ?? [];
                    app.aurError = d.error ?? "";
                } catch (e) { app.aurResults = []; app.aurError = String(e); }
            }
        }
    }
    Timer {
        id: aurTimer
        interval: 600
        onTriggered: {
            const q = app.query.trim();
            if (q.length < 2) { app.aurResults = []; app.aurLoading = false; return; }
            aurSearch.want = q;
            aurSearch.command = ["python3", "-I", app.backend, "aur", app.qinfo?.aurQ || q];
            aurSearch.running = false;
            aurSearch.running = true;
        }
    }
    onQueryChanged: {
        aurResults = [];
        aurError = "";
        aurLoading = query.trim().length >= 2;
        aurTimer.restart();
        if (query.trim()) { page = "search"; detail = ""; }
        else if (page === "search") page = "discover";
    }

    Timer { id: toastTimer; interval: 6000; onTriggered: app.toastText = "" }

    // Mở sẵn một trang (launcher: quantum-store search <q> | detail <gói> | updates | installed)
    function openArg(arg: string): void {
        if (!arg) return;
        const i = arg.indexOf(":");
        const kind = i < 0 ? arg : arg.slice(0, i), val = i < 0 ? "" : arg.slice(i + 1);
        if (kind === "search") query = val;
        else if (kind === "detail" && val) show(val);
        else if (["discover", "installed", "updates"].includes(kind)) { query = ""; go(kind); }
        else if (kind === "category" && val) { query = ""; go("category", val); }
    }
    // độ phổ biến (pkgstats): tải ngầm nếu cache quá 7 ngày, xong thì nạp lại để xếp hạng theo nó
    Process {
        id: popProc
        command: ["python3", "-I", app.backend, "popularity"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { if (JSON.parse(text).fresh) app.reload(); } catch (e) {}
            }
        }
    }
    Component.onCompleted: {
        popProc.running = true;
        reload();
        checkUpdates();
        scanDesktop();
        openArg(Quickshell.env("QS_STORE_OPEN") ?? "");
    }

    IpcHandler {
        target: "store"
        function refresh(): void { app.reload(); }
        function open(arg: string): void { app.openArg(arg); }
        function close(): void { Qt.quit(); }
        function search(q: string): void { app.query = q; }
        function page(p: string): void { app.query = ""; app.go(p, p === "category" ? "Graphics" : ""); }
        function detail(pkg: string): void { app.show(pkg); }
        function results(): string {
            return "apps: " + app.appResults.join(" ") + "\nlist: " + app.listResults.slice(0, 14).map(r => r.n + (r.r === "aur" ? "*" : "") + ":" + Math.round(r.score)).join(" ");
        }
        function state(): string { return `loaded=${app.loaded} pkgs=${app.pkgs.length} apps=${app.apps.length} page=${app.page} detail=${app.detail} info=${app.info ? (app.info.error ?? app.info.version) : "-"} busy=${app.busy} results=${app.appResults.length}/${app.listResults.length} aur=${app.aurResults.length}`; }
    }

    // ------------------------------------------------------------------ cửa sổ
    FloatingWindow {
        id: window
        title: "Quantum Store"
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()
        implicitWidth: 1100
        implicitHeight: 740
        minimumSize: Qt.size(820, 520)
        color: app.win

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ------------------------------------------------------ thanh bên
            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 230
                color: app.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: app.line }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    anchors.topMargin: 16
                    spacing: 2

                    // ô tìm kiếm
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 10
                        implicitHeight: 32
                        radius: 8
                        color: app.dark ? "#1c1c1e" : "#ffffff"
                        border.width: search.activeFocus ? 2 : 1
                        border.color: search.activeFocus ? app.accent : app.line
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 6; spacing: 6
                            Sym { text: "search"; size: 17; color: app.muted }
                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                font.family: app.uiFont; font.pixelSize: 13
                                color: app.fg; clip: true
                                selectionColor: app.accent
                                focus: true
                                // Bộ gõ (fcitx5 Telex/VNI) giữ chữ đang gõ trong preeditText tới khi nhấn Space:
                                // tính cả phần đó để placeholder mất ngay và kết quả cập nhật ngay khi gõ.
                                readonly property string typed: text + preeditText
                                onTypedChanged: searchDelay.restart()
                                Keys.onEscapePressed: text = ""
                                Timer { id: searchDelay; interval: 220; onTriggered: app.query = search.typed }
                                Connections {
                                    target: app
                                    function onQueryChanged(): void { if (search.typed !== app.query) search.text = app.query; }
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !search.typed
                                    text: app.tr("Tìm ứng dụng, gói…", "Search apps, packages…")
                                    color: app.muted
                                }
                            }
                            Sym {
                                visible: search.typed !== ""
                                text: "cancel"; size: 16; color: app.muted
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Qt.inputMethod.reset(); search.text = ""; } }
                            }
                        }
                    }

                    NavItem { icon: "explore"; label: app.tr("Khám phá", "Discover"); active: app.page === "discover"; onClicked: app.go("discover") }

                    Label {
                        visible: app.hasAppstream
                        Layout.topMargin: 12; Layout.leftMargin: 8; Layout.bottomMargin: 2
                        text: app.tr("Danh mục", "Categories")
                        color: app.muted; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: app.hasAppstream ? app.categories : []
                        NavItem {
                            required property var modelData
                            icon: modelData.icon
                            label: app.tr(modelData.vi, modelData.en)
                            active: app.page === "category" && app.category === modelData.id
                            onClicked: app.go("category", modelData.id)
                        }
                    }

                    Item { Layout.fillHeight: true }

                    NavItem {
                        icon: "download_done"; label: app.tr("Đã cài đặt", "Installed")
                        badge: app.loaded ? String(app.installedCount) : ""
                        badgeMuted: true
                        active: app.page === "installed"; onClicked: app.go("installed")
                    }
                    NavItem {
                        icon: "update"; label: app.tr("Cập nhật", "Updates")
                        badge: app.updCount > 0 ? String(app.updCount) : ""
                        active: app.page === "updates"; onClicked: app.go("updates")
                    }

                    // trạng thái thao tác đang chạy
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        visible: app.busy
                        implicitHeight: 44
                        radius: 8
                        color: app.card
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 8
                            Spinner { size: 18 }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                Label {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    text: app.opKind === "remove" ? app.tr("Đang gỡ…", "Removing…") : app.tr("Đang cài…", "Installing…")
                                    font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                                Label { Layout.fillWidth: true; elide: Text.ElideRight; text: app.nameOf(app.opPkg); font.pixelSize: 11; color: app.muted }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------ nội dung
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                Rectangle { anchors.fill: parent; color: app.content }

                Loader {
                    anchors.fill: parent
                    visible: app.detail === ""
                    active: app.loaded
                    sourceComponent: app.page === "updates" ? updatesPage
                        : app.page === "installed" ? installedPage
                        : app.page === "search" ? searchPage
                        : app.page === "category" ? categoryPage : discoverPage
                }
                Loader {
                    anchors.fill: parent
                    active: app.detail !== ""
                    sourceComponent: detailPage
                }

                // đang nạp lần đầu
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !app.loaded
                    spacing: 12
                    Spinner { Layout.alignment: Qt.AlignHCenter; size: 28 }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: app.tr("Đang đọc danh sách gói…", "Reading package lists…")
                        color: app.muted
                    }
                }

                // thông báo (toast)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: app.toastText ? 18 : -height
                    Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    width: Math.min(parent.width - 40, toastRow.implicitWidth + 28)
                    height: 40
                    radius: 10
                    color: app.toastError ? (app.dark ? "#4a1f1c" : "#ffe5e3") : (app.dark ? "#2c2c2e" : "#1d1d1f")
                    border.width: 1
                    border.color: app.toastError ? app.danger : "transparent"
                    RowLayout {
                        id: toastRow
                        anchors.centerIn: parent
                        spacing: 10
                        Sym { text: app.toastError ? "error" : "check_circle"; size: 18; color: app.toastError ? app.danger : "#32d74b" }
                        Label {
                            Layout.maximumWidth: 560; elide: Text.ElideRight
                            text: app.toastText
                            color: app.toastError ? app.fg : "#ffffff"
                        }
                        Label {
                            visible: app.errorLog !== "" && app.toastError
                            text: app.tr("Chi tiết", "Details")
                            color: app.accent; font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { logPanel.visible = true; toastTimer.stop(); } }
                        }
                    }
                }

                // nhật ký lỗi của pacman
                Rectangle {
                    id: logPanel
                    visible: false
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                    MouseArea { anchors.fill: parent; onClicked: logPanel.visible = false }
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 60, 720)
                        height: Math.min(parent.height - 60, 440)
                        radius: 12
                        color: app.win
                        border.width: 1; border.color: app.line
                        MouseArea { anchors.fill: parent }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16; spacing: 10
                            RowLayout {
                                Label { text: app.toastText; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                Btn { text: app.tr("Đóng", "Close"); onClicked: { logPanel.visible = false; app.toastText = ""; } }
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 8; color: app.content; border.width: 1; border.color: app.line
                                Flickable {
                                    anchors.fill: parent; anchors.margins: 10
                                    clip: true
                                    contentHeight: logText.implicitHeight
                                    TextEdit {
                                        id: logText
                                        width: parent.width
                                        readOnly: true; selectByMouse: true
                                        wrapMode: Text.WrapAnywhere
                                        text: app.errorLog
                                        color: app.fg
                                        font.family: "monospace"; font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================================================================== trang
    Component {
        id: discoverPage
        Page {
            // chưa có AppStream: gợi ý cài để có icon, ảnh, danh mục
            Rectangle {
                visible: !app.hasAppstream
                Layout.fillWidth: true
                implicitHeight: bannerRow.implicitHeight + 32
                radius: 12
                color: app.dark ? "#1f2a3a" : "#e8f1ff"
                RowLayout {
                    id: bannerRow
                    anchors.fill: parent; anchors.margins: 16; spacing: 14
                    Sym { text: "auto_awesome"; size: 30; color: app.accent }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        Label { text: app.tr("Bật giao diện cửa hàng đầy đủ", "Enable the full store experience"); font.pixelSize: 14; font.weight: Font.DemiBold }
                        Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: app.muted
                            text: app.tr("Cài gói archlinux-appstream-data để có icon, ảnh chụp màn hình, mô tả và danh mục cho hơn 1.200 ứng dụng.",
                                         "Install archlinux-appstream-data to get icons, screenshots, descriptions and categories for 1,200+ apps.")
                        }
                    }
                    ActionButton { pkg: "archlinux-appstream-data" }
                }
            }

            Rectangle {
                visible: app.dbLocked
                Layout.fillWidth: true
                implicitHeight: 44; radius: 10
                color: app.dark ? "#3a2c12" : "#fff4e0"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10
                    Sym { text: "lock_clock"; size: 20; color: app.warn }
                    Label { Layout.fillWidth: true; text: app.tr("pacman đang chạy ở nơi khác — chờ xong rồi hãy cài/gỡ.", "pacman is running elsewhere — wait before installing or removing.") }
                }
            }

            PageTitle { text: app.tr("Khám phá", "Discover") }

            SectionTitle { text: app.tr("Ứng dụng nổi bật", "Featured apps") }
            CardGrid { model: app.featured }

            Repeater {
                model: app.hasAppstream ? app.categories : []
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    visible: (app.appsByCat[modelData.id] ?? []).length > 0
                    SectionTitle {
                        text: app.tr(modelData.vi, modelData.en)
                        link: app.tr("Xem tất cả", "See all")
                        onLinkClicked: app.go("category", modelData.id)
                    }
                    CardGrid { model: (app.appsByCat[modelData.id] ?? []).slice(0, 6).map(a => a.p) }
                }
            }
        }
    }

    Component {
        id: categoryPage
        Page {
            PageTitle { text: app.catTitle(app.category) }
            Label { text: (app.appsByCat[app.category] ?? []).length + app.tr(" ứng dụng", " apps"); color: app.muted }
            CardGrid { model: (app.appsByCat[app.category] ?? []).map(a => a.p) }
        }
    }

    Component {
        id: searchPage
        Page {
            PageTitle { text: app.tr("Kết quả cho “", "Results for “") + app.query.trim() + "”" }

            SectionTitle { visible: app.appResults.length > 0; text: app.tr("Ứng dụng", "Apps") }
            CardGrid { visible: app.appResults.length > 0; model: app.appResults }

            SectionTitle {
                text: (app.appResults.length > 0 ? app.tr("Gói khác", "More packages") : app.tr("Kết quả", "Results"))
                    + "  ·  " + app.listResults.length
                link: app.tr("Tìm trên aur.archlinux.org", "Search aur.archlinux.org")
                onLinkClicked: Qt.openUrlExternally("https://aur.archlinux.org/packages?K=" + encodeURIComponent(app.query.trim()))
            }
            RowLayout {
                visible: app.aurLoading
                spacing: 8
                Spinner { size: 16 }
                Label { text: app.tr("Đang tìm thêm trên AUR…", "Searching the AUR too…"); color: app.muted; font.pixelSize: 12 }
            }
            Label {
                visible: !app.aurLoading && app.aurError !== ""
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: app.tr("Không tìm được trên AUR: ", "AUR search failed: ") + app.aurError
                color: app.danger; font.pixelSize: 12
            }
            Label {
                visible: app.anyAur
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: app.muted; font.pixelSize: 12
                text: app.tr("Gói có nhãn AUR do cộng đồng đóng gói, không được Arch kiểm duyệt. Khi cài, một cửa sổ terminal sẽ mở để bạn xem lại PKGBUILD.",
                             "Packages tagged AUR are community-maintained and not vetted by Arch. Installing opens a terminal so you can review the PKGBUILD.")
            }
            // steam, wine… nằm trong kho multilib (tắt mặc định)
            Rectangle {
                visible: !app.multilib && /^(steam|wine|lib32|proton|lutris)/.test(app.qinfo?.q ?? "")
                Layout.fillWidth: true
                implicitHeight: mlText.implicitHeight + 24; radius: 10
                color: app.dark ? "#3a2c12" : "#fff4e0"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10
                    Sym { text: "info"; size: 20; color: app.warn }
                    Label {
                        id: mlText
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: app.tr("Steam, Wine và các gói 32-bit nằm trong kho multilib, máy bạn chưa bật. Bỏ dấu # trước [multilib] và dòng Include bên dưới trong /etc/pacman.conf, rồi chạy cập nhật hệ thống.",
                                     "Steam, Wine and 32-bit packages live in the multilib repository, which is disabled. Uncomment [multilib] and its Include line in /etc/pacman.conf, then update the system.")
                    }
                }
            }
            Label {
                visible: !app.aurLoading && app.results.length === 0
                text: app.tr("Không tìm thấy gì. Thử từ khoá khác hoặc tiếng Anh.", "Nothing found. Try other or English keywords.")
                color: app.muted
            }
            RowList { model: app.listResults; limit: 80 }
        }
    }

    Component {
        id: installedPage
        Page {
            PageTitle { text: app.tr("Đã cài đặt", "Installed") }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Segmented {
                    value: app.instFilter
                    options: [
                        { v: "apps", t: app.tr("Ứng dụng", "Apps") },
                        { v: "explicit", t: app.tr("Đã chọn cài", "Explicit") },
                        { v: "aur", t: "AUR" },
                        { v: "all", t: app.tr("Tất cả", "All") }
                    ]
                    onPicked: v => app.instFilter = v
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 220; implicitHeight: 28; radius: 7
                    color: app.card
                    border.width: instSearch.activeFocus ? 2 : 1
                    border.color: instSearch.activeFocus ? app.accent : app.line
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                        Sym { text: "filter_list"; size: 16; color: app.muted }
                        TextInput {
                            id: instSearch
                            Layout.fillWidth: true
                            text: app.instQuery
                            font.family: app.uiFont; font.pixelSize: 12
                            color: app.fg; clip: true
                            readonly property string typed: text + preeditText
                            onTypedChanged: app.instQuery = typed
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !instSearch.typed
                                text: app.tr("Lọc", "Filter"); color: app.muted; font.pixelSize: 12
                            }
                        }
                    }
                }
            }
            Label {
                text: app.installedList.length + app.tr(" gói", " packages")
                color: app.muted; font.pixelSize: 12
            }
            RowList { model: app.installedList; showVersion: true }
        }
    }

    Component {
        id: updatesPage
        Page {
            RowLayout {
                Layout.fillWidth: true
                PageTitle { text: app.tr("Cập nhật", "Updates"); Layout.fillWidth: true }
                Btn {
                    text: app.updChecking ? app.tr("Đang kiểm tra…", "Checking…") : app.tr("Kiểm tra", "Check")
                    onClicked: app.checkUpdates()
                }
                Btn {
                    primary: true
                    visible: app.updCount > 0
                    text: app.tr("Cập nhật tất cả", "Update all")
                    onClicked: app.updateAll()
                }
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: app.muted
                text: app.updCount > 0
                    ? app.updCount + app.tr(" gói có bản mới. Arch cập nhật cả hệ thống cùng lúc (pacman -Syu), terminal sẽ mở để bạn theo dõi.",
                                             " packages have updates. Arch updates the whole system at once (pacman -Syu); a terminal opens so you can follow along.")
                    : app.tr("Mọi thứ đã là bản mới nhất.", "Everything is up to date.")
            }
            Repeater {
                model: app.updList
                Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: 8
                    color: updHover.hovered ? app.card : "transparent"
                    HoverHandler { id: updHover }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 12
                        PkgIcon { name: modelData.name; size: 34 }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            Label { text: app.nameOf(modelData.name); font.weight: Font.DemiBold }
                            Label { Layout.fillWidth: true; elide: Text.ElideRight; text: app.summaryOf(modelData.name); color: app.muted; font.pixelSize: 12 }
                        }
                        Label { text: modelData.from; color: app.muted; font.pixelSize: 12 }
                        Sym { text: "arrow_forward"; size: 14; color: app.muted }
                        Label { text: modelData.to; color: app.accent; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.show(modelData.name) }
                }
            }
        }
    }

    Component {
        id: detailPage
        Page {
            id: dp
            readonly property string name: app.detail
            readonly property var a: app.appByPkg[name] ?? null
            readonly property var p: app.byName[name] ?? null
            readonly property var inf: app.info
            readonly property bool aur: (p?.r ?? inf?.repo) === "aur" || (!p && !!inf && !inf.error)

            Item {
                implicitWidth: backRow.implicitWidth
                implicitHeight: backRow.implicitHeight
                RowLayout {
                    id: backRow
                    spacing: 4
                    Sym { text: "chevron_left"; size: 22; color: app.accent }
                    Label { text: app.tr("Quay lại", "Back"); color: app.accent }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.detail = "" }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 20
                PkgIcon { name: dp.name; size: 112; Layout.alignment: Qt.AlignTop }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: app.nameOf(dp.name); font.pixelSize: 26; font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: app.summaryOf(dp.name) || dp.inf?.desc || ""
                        color: app.muted; font.pixelSize: 14
                    }
                    RowLayout {
                        Layout.topMargin: 4
                        spacing: 6
                        Chip { text: dp.aur ? "AUR" : (dp.p?.r ?? dp.inf?.repo ?? ""); warn: dp.aur }
                        Chip { visible: dp.name !== app.nameOf(dp.name); text: dp.name }
                        Chip { visible: !!dp.inf?.ood; text: app.tr("Bị đánh dấu lỗi thời", "Flagged out-of-date"); warn: true }
                    }
                    RowLayout {
                        Layout.topMargin: 10
                        spacing: 10
                        ActionButton { pkg: dp.name; big: true; aurPkg: dp.aur }
                        Btn {
                            visible: app.isInstalled(dp.name) && app.stateOf(dp.name) !== "busy"
                            text: app.tr("Gỡ cài đặt", "Uninstall")
                            danger: true
                            enabled: !app.busy && (dp.inf?.requiredBy ?? []).length === 0
                            onClicked: app.remove(dp.name)
                        }
                        Label {
                            visible: app.isInstalled(dp.name) && (dp.inf?.requiredBy ?? []).length > 0
                            Layout.maximumWidth: 360; elide: Text.ElideRight
                            text: app.tr("Không gỡ được — cần bởi: ", "Can't remove — required by: ") + (dp.inf?.requiredBy ?? []).join(", ")
                            color: app.muted; font.pixelSize: 12
                        }
                    }
                }
            }

            // ảnh chụp màn hình
            ListView {
                visible: (dp.a?.sh ?? []).length > 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                implicitHeight: 300
                orientation: ListView.Horizontal
                spacing: 14
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: dp.a?.sh ?? []
                delegate: Rectangle {
                    required property string modelData
                    height: 300
                    width: shot.status === Image.Ready ? Math.min(560, shot.implicitWidth * height / Math.max(1, shot.implicitHeight)) : 480
                    radius: 10
                    color: app.card
                    clip: true
                    Image {
                        id: shot
                        anchors.fill: parent
                        source: modelData
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectFit
                        sourceSize.height: 600
                    }
                    Spinner { anchors.centerIn: parent; size: 22; visible: shot.status === Image.Loading }
                    Sym { anchors.centerIn: parent; text: "broken_image"; size: 30; color: app.muted; visible: shot.status === Image.Error }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(modelData) }
                }
            }

            Label {
                visible: !!dp.a?.desc || !!dp.inf?.desc
                Layout.fillWidth: true
                Layout.topMargin: 8
                wrapMode: Text.WordWrap
                text: dp.a?.desc || dp.inf?.desc || ""
                font.pixelSize: 13
                lineHeight: 1.25
            }

            SectionTitle { text: app.tr("Thông tin", "Information"); Layout.topMargin: 8 }
            RowLayout {
                visible: app.infoLoading
                spacing: 8
                Spinner { size: 16 }
                Label { text: app.tr("Đang tải…", "Loading…"); color: app.muted }
            }
            Label { visible: !!dp.inf?.error; text: dp.inf?.error ?? ""; color: app.danger }
            GridLayout {
                visible: !!dp.inf && !dp.inf.error
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 24
                rowSpacing: 8
                InfoRow { k: app.tr("Phiên bản", "Version"); v: dp.inf?.version ?? "" }
                InfoRow { k: app.tr("Đã cài", "Installed"); v: dp.inf?.installedVersion ? dp.inf.installedVersion + (dp.inf.installDate ? "  ·  " + dp.inf.installDate : "") : "" }
                InfoRow { k: app.tr("Nguồn", "Source"); v: dp.inf?.repo ?? "" }
                InfoRow { k: app.tr("Dung lượng tải", "Download size"); v: dp.inf?.downloadSize ?? "" }
                InfoRow { k: app.tr("Dung lượng cài", "Installed size"); v: dp.inf?.installedSize ?? "" }
                InfoRow { k: app.tr("Giấy phép", "License"); v: dp.inf?.licenses ?? "" }
                InfoRow { k: app.tr("Đóng gói bởi", "Packager"); v: dp.inf?.packager ?? "" }
                InfoRow { k: app.tr("Lượt vote AUR", "AUR votes"); v: dp.inf?.votes !== undefined ? String(dp.inf.votes) : "" }
                InfoRow { k: app.tr("Trang chủ", "Website"); v: dp.a?.u || dp.inf?.url || ""; url: true }
                InfoRow { k: app.tr("Phụ thuộc", "Dependencies"); v: (dp.inf?.depends ?? []).join("  ") }
                InfoRow { k: app.tr("Tuỳ chọn thêm", "Optional"); v: dp.inf?.optdepends ?? "" }
                InfoRow { k: app.tr("Được cần bởi", "Required by"); v: (dp.inf?.requiredBy ?? []).join("  ") }
            }
        }
    }

    // ================================================================== thành phần
    component Label: Text {
        font.family: app.uiFont
        font.pixelSize: 13
        color: app.fg
    }

    component Sym: Text {
        property int size: 20
        font.family: app.iconFont
        font.pixelSize: size
        color: app.fg
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    component Spinner: Sym {
        text: "progress_activity"
        color: app.accent
        RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: true }
    }

    // trang cuộn được, nội dung xếp dọc
    component Page: Flickable {
        id: pg
        default property alias body: col.data
        contentHeight: col.implicitHeight + 56
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ColumnLayout {
            id: col
            x: 28; y: 24
            width: pg.width - 56
            spacing: 14
        }
    }

    component PageTitle: Label {
        font.pixelSize: 26
        font.weight: Font.Bold
    }

    component SectionTitle: RowLayout {
        id: st
        property string text
        property string link: ""
        signal linkClicked()
        Layout.fillWidth: true
        Layout.topMargin: 10
        Label { text: st.text; font.pixelSize: 17; font.weight: Font.Bold; Layout.fillWidth: true }
        Label {
            visible: st.link !== ""
            text: st.link; color: app.accent
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.linkClicked() }
        }
    }

    component NavItem: Rectangle {
        id: ni
        property string icon
        property string label
        property string badge: ""
        property bool badgeMuted: false
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 7
        color: active ? Qt.rgba(app.accent.r, app.accent.g, app.accent.b, app.dark ? 0.35 : 0.2)
             : niHover.hovered ? Qt.rgba(0.5, 0.5, 0.5, 0.15) : "transparent"
        HoverHandler { id: niHover }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 9
            Sym { text: ni.icon; size: 18; color: ni.active ? app.accent : app.muted }
            Label { Layout.fillWidth: true; text: ni.label; elide: Text.ElideRight; font.weight: ni.active ? Font.DemiBold : Font.Normal }
            Rectangle {
                visible: ni.badge !== ""
                implicitWidth: Math.max(20, bt.implicitWidth + 10); implicitHeight: 18; radius: 9
                color: ni.badgeMuted ? "transparent" : app.danger
                Label { id: bt; anchors.centerIn: parent; text: ni.badge; font.pixelSize: 11; color: ni.badgeMuted ? app.muted : "white"; font.weight: Font.DemiBold }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ni.clicked() }
    }

    component PkgIcon: Item {
        id: pi
        property string name
        property int size: 48
        readonly property string src: { void app.rev; return app.iconOf(name); }
        implicitWidth: size
        implicitHeight: size
        Image {
            id: img
            anchors.fill: parent
            source: pi.src
            sourceSize: Qt.size(pi.size * 2, pi.size * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true; mipmap: true
            visible: pi.src !== "" && status === Image.Ready
        }
        Rectangle {
            anchors.fill: parent
            visible: !img.visible
            radius: pi.size * 0.22
            color: app.dark ? "#3a3a3c" : "#e3e3e8"
            Sym { anchors.centerIn: parent; text: "package_2"; size: pi.size * 0.55; color: app.muted }
        }
    }

    component Btn: Rectangle {
        id: b
        property string text
        property bool primary: false
        property bool danger: false
        signal clicked()
        implicitWidth: bl.implicitWidth + 28
        implicitHeight: 28
        radius: 14
        opacity: enabled ? 1 : 0.45
        color: primary ? (bHover.hovered ? Qt.lighter(app.accent, 1.1) : app.accent)
             : (bHover.hovered ? app.cardHover : app.card)
        border.width: primary ? 0 : 1
        border.color: app.line
        HoverHandler { id: bHover }
        Label {
            id: bl
            anchors.centerIn: parent
            text: b.text
            font.pixelSize: 12; font.weight: Font.DemiBold
            color: b.primary ? "white" : b.danger ? app.danger : app.fg
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: b.enabled; onClicked: b.clicked() }
    }

    // nút chính của một gói: Tải về / Mở / Cập nhật / đang cài
    component ActionButton: Rectangle {
        id: ab
        property string pkg
        property bool big: false
        property bool aurPkg: false
        readonly property string st: app.stateOf(pkg)
        readonly property var entry: st === "installed" || st === "update" ? app.entryOf(pkg) : null
        readonly property string label: st === "busy" ? ""
            : st === "update" ? app.tr("Cập nhật", "Update")
            : st === "installed" ? (entry ? app.tr("Mở", "Open") : app.tr("Đã cài", "Installed"))
            : app.tr("Tải về", "Get")
        readonly property bool clickable: st === "available" ? !app.busy : st === "update" || (st === "installed" && !!entry)
        implicitWidth: st === "busy" ? implicitHeight * 1.6 : Math.max(big ? 96 : 64, al.implicitWidth + 26)
        implicitHeight: big ? 32 : 26
        radius: implicitHeight / 2
        color: big && st === "available" ? app.accent : (abHover.hovered && clickable ? app.cardHover : (app.dark ? "#3a3a3c" : "#e8e8ed"))
        opacity: st === "available" && app.busy ? 0.5 : 1
        HoverHandler { id: abHover }
        Label {
            id: al
            anchors.centerIn: parent
            text: ab.label
            font.pixelSize: ab.big ? 13 : 12
            font.weight: Font.Bold
            color: ab.big && ab.st === "available" ? "white" : ab.st === "installed" && !ab.entry ? app.muted : app.accent
        }
        Spinner { anchors.centerIn: parent; size: 16; visible: ab.st === "busy" }
        MouseArea {
            anchors.fill: parent
            cursorShape: ab.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (!ab.clickable) return;
                if (ab.st === "available") app.install(ab.pkg);
                else if (ab.st === "update") app.go("updates");
                else app.launch(ab.pkg);
            }
        }
    }

    // lưới thẻ ứng dụng (model = danh sách tên gói)
    component CardGrid: ColumnLayout {
        id: cgBox
        property var model: []
        property int limit: 48
        Layout.fillWidth: true
        spacing: 12
        CardFlow { model: cgBox.model.slice(0, cgBox.limit) }
        Btn {
            visible: cgBox.model.length > cgBox.limit
            text: app.tr("Hiện thêm", "Show more") + " (" + (cgBox.model.length - cgBox.limit) + ")"
            onClicked: cgBox.limit += 96
        }
    }

    component CardFlow: Flow {
        id: cg
        property var model: []
        readonly property int cols: Math.max(1, Math.floor((width + spacing) / (300 + spacing)))
        readonly property real cardW: (width - spacing * (cols - 1)) / cols
        Layout.fillWidth: true
        spacing: 12
        Repeater {
            model: cg.model
            Rectangle {
                id: c
                required property string modelData
                width: cg.cardW
                height: 84
                radius: 12
                color: cHover.hovered ? app.cardHover : app.card
                HoverHandler { id: cHover }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.show(c.modelData) }
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 12
                    PkgIcon { name: c.modelData; size: 56 }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Label { Layout.fillWidth: true; text: app.nameOf(c.modelData); font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Label {
                            Layout.fillWidth: true
                            text: app.summaryOf(c.modelData)
                            color: app.muted; font.pixelSize: 12
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        }
                    }
                    ActionButton { pkg: c.modelData }
                }
            }
        }
    }

    // danh sách gói dạng hàng (model = [{ n, r, v, d, i } ...] hoặc kết quả AUR)
    component RowList: ColumnLayout {
        id: rl
        property var model: []
        property bool aur: false
        property bool showVersion: false
        property int limit: 150
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: rl.model.slice(0, rl.limit)
            Rectangle {
                id: r
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 8
                color: rHover.hovered ? app.card : "transparent"
                HoverHandler { id: rHover }
                Rectangle {
                    visible: r.index > 0 && !rHover.hovered
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 56; height: 1; color: app.line; opacity: 0.6
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.show(r.modelData.n) }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 12
                    PkgIcon { name: r.modelData.n; size: 34 }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        RowLayout {
                            spacing: 6
                            Label { text: app.nameOf(r.modelData.n); font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.maximumWidth: 360 }
                            Label { visible: app.nameOf(r.modelData.n) !== r.modelData.n; text: r.modelData.n; color: app.muted; font.pixelSize: 11 }
                            Chip { visible: r.modelData.r === "aur"; text: "AUR"; warn: true }
                            Chip { visible: !!r.modelData.ood; text: app.tr("lỗi thời", "out-of-date"); warn: true }
                        }
                        Label {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: app.summaryOf(r.modelData.n) || r.modelData.d || ""
                            color: app.muted; font.pixelSize: 12
                        }
                    }
                    Label {
                        visible: r.modelData.votes !== undefined
                        text: "▲ " + app.fmtVotes(r.modelData.votes ?? 0)
                        color: app.muted; font.pixelSize: 11
                    }
                    Label {
                        text: rl.showVersion ? (r.modelData.i || r.modelData.v) : r.modelData.v
                        color: app.muted; font.pixelSize: 11
                        Layout.maximumWidth: 140; elide: Text.ElideRight
                    }
                    ActionButton { pkg: r.modelData.n; aurPkg: r.modelData.r === "aur" }
                }
            }
        }
        Btn {
            visible: rl.model.length > rl.limit
            Layout.topMargin: 8
            text: app.tr("Hiện thêm", "Show more") + " (" + (rl.model.length - rl.limit) + ")"
            onClicked: rl.limit += 200
        }
    }

    component Chip: Rectangle {
        id: ch
        property string text
        property bool warn: false
        visible: text !== ""
        implicitWidth: chl.implicitWidth + 12
        implicitHeight: 18
        radius: 5
        color: warn ? Qt.rgba(1, 0.62, 0.04, 0.18) : (app.dark ? "#3a3a3c" : "#e8e8ed")
        Label { id: chl; anchors.centerIn: parent; text: ch.text; font.pixelSize: 10; font.weight: Font.DemiBold; color: ch.warn ? app.warn : app.muted }
    }

    component Segmented: Rectangle {
        id: sg
        property string value
        property var options: []
        signal picked(string v)
        implicitWidth: sgRow.implicitWidth + 4
        implicitHeight: 28
        radius: 7
        color: app.dark ? "#2c2c2e" : "#e3e3e8"
        Row {
            id: sgRow
            anchors.centerIn: parent
            Repeater {
                model: sg.options
                Rectangle {
                    required property var modelData
                    width: Math.max(72, sgl.implicitWidth + 20); height: 24; radius: 5
                    color: sg.value === modelData.v ? (app.dark ? "#636366" : "#ffffff") : "transparent"
                    Label {
                        id: sgl
                        anchors.centerIn: parent
                        text: modelData.t; font.pixelSize: 12
                        font.weight: sg.value === modelData.v ? Font.DemiBold : Font.Normal
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sg.picked(modelData.v) }
                }
            }
        }
    }

    component InfoRow: ColumnLayout {
        id: ir
        property string k
        property string v
        property bool url: false
        visible: v !== ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        spacing: 2
        Label { text: ir.k; color: app.muted; font.pixelSize: 11 }
        Label {
            Layout.fillWidth: true
            text: ir.v
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: ir.url ? app.accent : app.fg
            font.pixelSize: 12
            MouseArea {
                anchors.fill: parent
                enabled: ir.url
                cursorShape: ir.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: Qt.openUrlExternally(ir.v)
            }
        }
    }
}
