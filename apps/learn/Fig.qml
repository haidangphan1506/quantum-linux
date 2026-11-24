import QtQuick

// Hình minh hoạ 2D / 3D (isometric) cho bài Docker, Nginx. Vẽ bằng Canvas, toạ độ thiết kế 640x256 rồi co theo bề rộng.
// kind: dk-layers dk-ports dk-volume dk-network dk-lifecycle dk-build dk-bluegreen
//       ng-proxy ng-errors ng-location ng-upstream ng-ws ng-sites ng-redirect ng-cache ng-docker
Item {
    id: fig
    property string kind: ""
    property bool dark: true
    property color ink: "#000"
    property color muted: "#666"
    property color line: "#ccc"
    readonly property real dw: 640
    readonly property real dh: 256
    implicitHeight: Math.round(width * dh / dw)
    onKindChanged: cv.requestPaint()
    onDarkChanged: cv.requestPaint()
    onInkChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (width < 10) return;
            ctx.scale(width / fig.dw, width / fig.dw);
            try { fig.draw(ctx); } catch (e) { console.warn("Fig " + fig.kind + ": " + e); }
        }
    }

    function draw(ctx: var): void {
        const dark = fig.dark;
        const C = {
            ink: "" + fig.ink, mut: "" + fig.muted, line: "" + fig.line,
            blue: dark ? "#6ea3e6" : "#3f74b8", green: dark ? "#7fc278" : "#3a8a4a",
            red: dark ? "#ef7b6d" : "#c2453a", amber: dark ? "#e8b04a" : "#d08a14",
            violet: dark ? "#a98ad6" : "#7a5aa8", rust: "#d0683a", grey: dark ? "#8a8174" : "#8b847a"
        };
        const hx = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
        const rgba = (h, a) => { const c = hx(h); return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + a + ")"; };
        const shade = (h, f) => { const c = hx(h).map(v => Math.max(0, Math.min(255, Math.round(f > 0 ? v + (255 - v) * f : v * (1 + f))))); return "rgb(" + c[0] + "," + c[1] + "," + c[2] + ")"; };

        function rr(x, y, w, h, r) {
            ctx.beginPath(); ctx.moveTo(x + r, y);
            ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
            ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
        }
        function T(s, x, y, o) {
            o = o || {};
            ctx.font = (o.bold ? "bold " : "") + Math.round((o.size || 11) * 1.18 * 10) / 10 + "px " + (o.mono ? "'JetBrains Mono', monospace" : "sans-serif");
            ctx.fillStyle = o.color || C.ink; ctx.textAlign = o.align || "center"; ctx.textBaseline = "middle";
            ctx.fillText(s, x, y);
        }
        function card(x, y, w, h, col, o) {
            o = o || {};
            rr(x, y, w, h, o.r === undefined ? 8 : o.r);
            ctx.fillStyle = rgba(col, o.fill === undefined ? 0.16 : o.fill); ctx.fill();
            ctx.lineWidth = 1.5; ctx.strokeStyle = col;
            ctx.setLineDash(o.dash ? [5, 4] : []); ctx.stroke(); ctx.setLineDash([]);
            if (o.title) T(o.title, x + w / 2, y + (o.sub ? h / 2 - 7 : h / 2), { bold: true, size: o.size || 11, mono: o.mono });
            if (o.sub) T(o.sub, x + w / 2, y + h / 2 + 8, { size: 9.5, color: C.mut, mono: o.submono });
        }
        function arrow(x1, y1, x2, y2, col, o) {
            o = o || {};
            ctx.strokeStyle = col; ctx.fillStyle = col; ctx.lineWidth = 2;
            ctx.setLineDash(o.dash ? [6, 4] : []);
            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); ctx.setLineDash([]);
            const a = Math.atan2(y2 - y1, x2 - x1);
            ctx.beginPath(); ctx.moveTo(x2, y2);
            ctx.lineTo(x2 - 9 * Math.cos(a - 0.4), y2 - 9 * Math.sin(a - 0.4));
            ctx.lineTo(x2 - 9 * Math.cos(a + 0.4), y2 - 9 * Math.sin(a + 0.4)); ctx.closePath(); ctx.fill();
            if (o.label) T(o.label, (x1 + x2) / 2 + (o.dx || 0), (y1 + y2) / 2 + (o.dy === undefined ? -9 : o.dy), { size: 9.5, color: o.lcol || col, mono: o.mono, bold: o.bold });
        }
        function badge(x, y, s, col, w) {
            const bw = w || (s.length * 6.4 + 16);
            rr(x - bw / 2, y - 10, bw, 20, 10); ctx.fillStyle = col; ctx.fill();
            T(s, x, y, { bold: true, size: 10.5, color: "#fff" });
        }
        function cross(x, y, col) {
            ctx.strokeStyle = col; ctx.lineWidth = 3; ctx.beginPath();
            ctx.moveTo(x - 7, y - 7); ctx.lineTo(x + 7, y + 7); ctx.moveTo(x + 7, y - 7); ctx.lineTo(x - 7, y + 7); ctx.stroke();
        }
        function tick(x, y, col) {
            ctx.strokeStyle = col; ctx.lineWidth = 3; ctx.beginPath();
            ctx.moveTo(x - 7, y); ctx.lineTo(x - 2, y + 6); ctx.lineTo(x + 8, y - 7); ctx.stroke();
        }
        function poly(pts, fill, stroke) {
            ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]);
            for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
            ctx.closePath(); ctx.fillStyle = fill; ctx.fill();
            if (stroke) { ctx.lineWidth = 1; ctx.strokeStyle = stroke; ctx.stroke(); }
        }
        // khối 3D isometric: mặt trước (x,y,w,h), chiều sâu d
        function box(x, y, w, h, d, col, label, sub, o) {
            o = o || {};
            const k = d * 0.6, ln = shade(col, -0.35);
            poly([[x + w, y], [x + w + d, y - k], [x + w + d, y + h - k], [x + w, y + h]], shade(col, -0.22), ln);
            poly([[x, y], [x + d, y - k], [x + w + d, y - k], [x + w, y]], shade(col, 0.3), ln);
            rr(x, y, w, h, 0); ctx.fillStyle = shade(col, o.light === false ? 0 : 0.05); ctx.fill(); ctx.lineWidth = 1; ctx.strokeStyle = ln; ctx.stroke();
            if (label) T(label, x + w / 2, y + (sub ? h / 2 - 6 : h / 2), { bold: true, size: o.size || 11, color: "#1d1b18", mono: o.mono });
            if (sub) T(sub, x + w / 2, y + h / 2 + 8, { size: 9, color: "#3a352f", mono: o.submono });
        }
        function cyl(cx, y, w, h, col, label) {
            const ry = 8, x = cx - w / 2;
            ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y + h);
            ctx.save(); ctx.translate(cx, y + h); ctx.scale(1, ry / (w / 2)); ctx.arc(0, 0, w / 2, Math.PI, 0, true); ctx.restore();
            ctx.lineTo(x + w, y); ctx.closePath();
            ctx.fillStyle = shade(col, -0.05); ctx.fill(); ctx.lineWidth = 1; ctx.strokeStyle = shade(col, -0.4); ctx.stroke();
            ctx.beginPath(); ctx.save(); ctx.translate(cx, y); ctx.scale(1, ry / (w / 2)); ctx.arc(0, 0, w / 2, 0, Math.PI * 2); ctx.restore();
            ctx.fillStyle = shade(col, 0.4); ctx.fill(); ctx.stroke();
            if (label) T(label, cx, y + h / 2 + 4, { bold: true, size: 10.5, color: "#1d1b18" });
        }
        function cap(s) { T(s, 320, 244, { size: 10, color: C.mut }); }

        const F = {
            // ------------------------------------------------------------------ Docker
            "dk-layers": () => {
                const lay = [["FROM node:20-slim", "~75 MB", C.blue], ["COPY package*.json", "vài KB", C.blue], ["RUN npm ci", "~180 MB", C.blue], ["COPY . .", "mã nguồn", C.blue]];
                for (let i = 0; i < lay.length; i++) box(70, 176 - i * 34, 190, 30, 26, lay[i][2], lay[i][0], lay[i][1], { mono: true, size: 10.5 });
                box(70, 176 - 4 * 34, 190, 30, 26, C.green, "lớp ghi được", "chỉ container có", { size: 10.5 });
                T("IMAGE (chỉ đọc)", 165, 214, { bold: true, size: 10.5, color: C.blue });
                arrow(330, 176 - 4 * 34 + 12, 296, 176 - 4 * 34 + 8, C.green);
                card(336, 28, 270, 52, C.green, { title: "container = image + 1 lớp ghi mỏng", sub: "docker run tạo lớp này; docker rm xoá nó" });
                arrow(330, 120, 292, 116, C.blue);
                card(336, 92, 270, 52, C.blue, { title: "image = chồng lớp bất biến", sub: "nhiều container dùng chung, không nhân bản" });
                card(336, 158, 270, 52, C.amber, { title: "ghi vào file cũ → copy-on-write", sub: "xoá ở lệnh sau KHÔNG làm image nhẹ đi" });
                cap("docker history <image>  → xem từng lớp và dung lượng");
            },
            "dk-ports": () => {
                T("Cách mở cổng", 12, 14, { bold: true, size: 10.5, align: "left", color: C.mut });
                card(14, 40, 92, 54, C.grey, { title: "Trình duyệt", sub: "Internet" });
                box(160, 48, 120, 46, 20, C.amber, "VPS (host)", "cổng :8080", {});
                box(380, 48, 120, 46, 20, C.blue, "container", "app :3000", {});
                arrow(106, 68, 158, 68, C.ink, { label: ":8080", dy: -12 });
                arrow(282, 68, 378, 68, C.green, { label: "-p 8080:3000", mono: true, bold: true, dx: 6, dy: 20 });
                card(520, 40, 106, 60, C.green, { title: "đúng", sub: "mở ra Internet", fill: 0.1 });
                T("Hai lỗi hay gặp", 12, 128, { bold: true, size: 10.5, align: "left", color: C.mut });
                box(30, 150, 100, 34, 14, C.blue, "api-1", "-p 8080:3000", { mono: false, submono: true });
                box(30, 200, 100, 34, 14, C.blue, "api-2", "-p 8080:3000", { submono: true });
                arrow(160, 168, 232, 190, C.red); arrow(160, 218, 232, 204, C.red);
                box(236, 172, 90, 38, 14, C.amber, "host :8080", "", {});
                cross(360, 190, C.red);
                badge(470, 190, "port is already allocated", C.red, 168);
                card(400, 150, 226, 24, C.amber, { title: "-p 127.0.0.1:8080:3000 = chỉ nội bộ", size: 9.5, mono: false });
                T("Nginx proxy tới 127.0.0.1:8080", 513, 226, { size: 9.5, color: C.mut });
            },
            "dk-volume": () => {
                box(235, 28, 170, 56, 28, C.blue, "container", "/var/lib/postgresql/data", { submono: true });
                cyl(100, 150, 110, 50, C.red, "lớp ghi");
                cyl(320, 150, 110, 50, C.green, "volume có tên");
                cyl(540, 150, 110, 50, C.violet, "bind mount");
                arrow(250, 90, 130, 140, C.red, { dash: true }); arrow(320, 90, 320, 138, C.green); arrow(390, 82, 520, 138, C.violet);
                T("docker rm → MẤT", 100, 214, { bold: true, size: 10, color: C.red });
                T("sống sót khi rm; mất khi down -v", 320, 214, { bold: true, size: 10, color: C.green });
                T("./data trên host, tự quản lý", 540, 214, { bold: true, size: 10, color: C.violet });
                T("tạm thời", 100, 232, { size: 9.5, color: C.mut }); T("/var/lib/docker/volumes/…", 320, 232, { size: 9.5, color: C.mut, mono: true }); T("đường dẫn tuyệt đối trên VPS", 540, 232, { size: 9.5, color: C.mut });
            },
            "dk-network": () => {
                card(14, 14, 612, 232, C.grey, { fill: 0.04, dash: true, r: 12 });
                T("VPS", 38, 28, { bold: true, size: 10, color: C.mut });
                card(30, 44, 380, 90, C.blue, { fill: 0.07, dash: true });
                T("mạng frontend", 96, 56, { bold: true, size: 10, color: C.blue });
                card(190, 128, 420, 98, C.green, { fill: 0.07, dash: true });
                T("mạng backend (internal: true)", 330, 214, { bold: true, size: 10, color: C.green });
                box(50, 76, 90, 38, 14, C.amber, "nginx", ":443", {});
                box(215, 76, 90, 38, 14, C.blue, "api", ":3000", {});
                box(215, 150, 90, 38, 14, C.blue, "api", "2 mạng", {});
                box(440, 150, 90, 38, 14, C.violet, "postgres", ":5432", {});
                arrow(141, 94, 213, 94, C.ink, { label: "api:3000", mono: true, dy: -10 });
                arrow(306, 168, 438, 168, C.ink, { label: "db:5432", mono: true, dy: -10 });
                                card(470, 52, 140, 52, C.red, { title: "Internet → db", sub: "không có đường vào" });
                cross(540, 120, C.red);
                T("Container gọi nhau bằng TÊN dịch vụ, không dùng IP", 320, 242, { size: 9.5, color: C.mut });
            },
            "dk-lifecycle": () => {
                card(14, 28, 100, 44, C.grey, { title: "created", sub: "docker create" });
                card(180, 28, 110, 44, C.green, { title: "running", sub: "docker start" });
                card(360, 28, 110, 44, C.grey, { title: "exited (0)", sub: "docker stop" });
                card(520, 28, 106, 44, C.amber, { title: "paused", sub: "docker pause" });
                arrow(114, 50, 178, 50, C.ink); arrow(290, 50, 358, 50, C.ink, { label: "stop / thoát", dy: -12 }); arrow(470, 50, 518, 50, C.amber, { dash: true });
                card(180, 118, 110, 44, C.red, { title: "exited (137)", sub: "OOM / kill -9" });
                arrow(235, 74, 235, 116, C.red, { label: "hết RAM", dx: 34, dy: 0 });
                card(360, 118, 140, 44, C.amber, { title: "restarting", sub: "restart: always" });
                arrow(290, 140, 358, 140, C.amber, { label: "tự bật lại", dy: -12 });
                arrow(430, 116, 290, 74, C.amber, { dash: true });
                cross(535, 140, C.red); T("crash-loop", 590, 140, { size: 10, bold: true, color: C.red });
                card(14, 184, 612, 46, C.blue, { fill: 0.08, title: "docker ps -a  → thấy exited; docker logs --tail 50 <tên>  → vì sao chết; docker inspect -f '{{.State.ExitCode}}'", size: 10, mono: false });
                cap("exit 0 = thoát bình thường · 1 = lỗi ứng dụng · 137 = bị kill (thường OOM) · 143 = SIGTERM");
            },
            "dk-build": () => {
                const L = [["FROM node:20-slim", true], ["COPY package*.json ./", true], ["RUN npm ci", true], ["COPY . .", false], ["RUN npm run build", false]];
                for (let i = 0; i < L.length; i++) {
                    const y = 20 + i * 38, hit = L[i][1], col = hit ? C.green : C.red;
                    card(20, y, 250, 30, col, { title: L[i][0], mono: true, size: 10.5, fill: 0.14 });
                    badge(318, y + 15, hit ? "CACHED" : "BUILD LẠI", col, hit ? 72 : 86);
                }
                                card(420, 22, 206, 60, C.amber, { title: "Bạn sửa 1 file .ts", sub: "COPY . . đổi → mất cache" });
                arrow(520, 82, 520, 134, C.red, { label: "từ dòng đổi trở xuống" , dy: 0, dx: -64 });
                card(420, 138, 206, 52, C.green, { title: "Đặt lệnh ÍT ĐỔI lên trên", sub: "package.json trước, mã nguồn sau" });
                card(420, 196, 206, 34, C.blue, { title: "docker build .", size: 9.5, mono: true });
                cap("CACHED = dùng lại lớp cũ, gần như 0 giây");
            },
            "dk-bluegreen": () => {
                box(30, 94, 110, 48, 20, C.amber, "nginx", "proxy_pass", {});
                box(300, 40, 130, 46, 20, C.blue, "blue :3001", "đang phục vụ", {});
                box(300, 150, 130, 46, 20, C.green, "green :3002", "bản mới", {});
                arrow(170, 108, 296, 70, C.ink, { label: "100% khách", dx: -8, dy: -12 });
                arrow(170, 126, 296, 172, C.green, { dash: true, label: "kiểm tra /health", dx: 20, dy: 16 });
                card(500, 20, 126, 44, C.grey, { title: "1 · up green", size: 10, mono: false, sub: "-d --wait" });
                card(500, 70, 126, 44, C.grey, { title: "2 · curl :3002", size: 10, sub: "healthcheck OK" });
                card(500, 120, 126, 44, C.amber, { title: "3 · đổi port, reload", size: 10, sub: "nginx -t && reload" });
                card(500, 170, 126, 44, C.red, { title: "4 · stop blue", size: 10, sub: "giữ để rollback" });
                cap("Lỗi → đổi proxy_pass về :3001 và reload: rollback trong vài giây, khách không bị gián đoạn");
            },
            // ------------------------------------------------------------------ Nginx
            "ng-proxy": () => {
                card(14, 82, 100, 50, C.grey, { title: "Trình duyệt", sub: "https://api.site.org" });
                box(170, 76, 110, 50, 20, C.amber, "Cloudflare", "DNS · cache · WAF", {});
                box(350, 76, 110, 50, 20, C.green, "Nginx", ":443 · TLS", {});
                box(530, 76, 90, 50, 20, C.blue, "App", "127.0.0.1:3000", { submono: true });
                arrow(114, 106, 168, 104, C.ink, { label: "1", dy: -12, bold: true });
                arrow(282, 104, 348, 102, C.ink, { label: "2", dy: -12, bold: true });
                arrow(462, 102, 528, 102, C.ink, { label: "3", dy: -12, bold: true });
                T("server_name → location → proxy_pass", 405, 156, { size: 10, color: C.green, bold: true });
                card(14, 176, 612, 50, C.blue, { fill: 0.08, title: "Nginx gửi kèm: Host · X-Real-IP · X-Forwarded-For · X-Forwarded-Proto", sub: "ứng dụng mới biết khách là ai và đi bằng https hay http", size: 10 });
                cap("App chỉ lắng nghe 127.0.0.1 → Internet không vào thẳng được, mọi thứ đi qua Nginx");
            },
            "ng-errors": () => {
                card(14, 110, 100, 46, C.grey, { title: "Trình duyệt" });
                box(170, 106, 110, 46, 20, C.amber, "Cloudflare", "", {});
                box(350, 106, 110, 46, 20, C.green, "Nginx", ":443", {});
                box(530, 106, 90, 46, 20, C.blue, "App", ":3000", {});
                arrow(114, 130, 168, 130, C.ink); arrow(282, 130, 348, 128, C.ink); arrow(462, 130, 528, 128, C.ink);
                badge(318, 38, "520 / 521 / 522", C.red, 120);
                T("Cloudflare không nói được với origin", 318, 58, { size: 9.5, color: C.mut });
                T("Nginx tắt? firewall chặn 443?", 318, 72, { size: 9.5, color: C.mut });
                badge(380, 180, "404", C.amber, 52); T("location không khớp", 380, 198, { size: 9.5, color: C.mut });
                badge(300, 226, "413", C.amber, 52); T("body > client_max_body_size", 334, 226, { size: 9.5, color: C.mut, align: "left" });
                badge(535, 38, "502", C.red, 56); T("app chết / sai cổng", 535, 58, { size: 9.5, color: C.mut }); T("docker ps · ss -ltnp", 535, 72, { size: 9.5, color: C.mut, mono: true });
                badge(600, 180, "504", C.red, 56); T("app chậm", 600, 198, { size: 9.5, color: C.mut });
                arrow(535, 84, 535, 102, C.red); arrow(318, 84, 318, 102, C.red);
                T("Mã lỗi cho biết sự cố ở chặng nào · tail -f /var/log/nginx/error.log", 320, 248, { size: 9.5, color: C.mut });
            },
            "ng-location": () => {
                card(14, 20, 190, 44, C.violet, { title: "GET /api/users", sub: "URI khách gửi tới", mono: true });
                const rows = [["1", "location = /", "khớp CHÍNH XÁC → dừng ngay", C.grey, false], ["2", "location ^~ /static/", "tiền tố ^~ → bỏ qua regex", C.grey, false], ["3", "location ~ \\.php$", "regex: khớp đầu tiên thắng", C.grey, false], ["4", "location /api/", "tiền tố dài nhất → THẮNG", C.green, true]];
                for (let i = 0; i < rows.length; i++) {
                    const y = 20 + i * 52, r = rows[i];
                    card(240, y, 386, 42, r[3], { fill: r[4] ? 0.22 : 0.08 });
                    badge(262, y + 21, r[0], r[4] ? C.green : C.grey, 24);
                    T(r[1], 288, y + 14, { bold: true, mono: true, size: 10.5, align: "left" });
                    T(r[2], 288, y + 31, { size: 9.5, color: C.mut, align: "left" });
                    if (r[4]) tick(602, y + 21, C.green);
                }
                arrow(204, 42, 238, 42, C.ink);
                T("Thứ tự ưu tiên: = › ^~ › regex (theo thứ tự viết) › tiền tố dài nhất", 320, 238, { size: 10, color: C.mut });
            },
            "ng-upstream": () => {
                box(40, 90, 120, 50, 20, C.green, "Nginx", "upstream api {}", { submono: true });
                const s = [["app1 :3001", "weight=3", C.blue, 14, false], ["app2 :3002", "weight=1", C.blue, 74, false], ["app3 :3003", "max_fails: bị loại", C.red, 134, false], ["app4 :3004", "backup", C.grey, 194, true]];
                for (let i = 0; i < s.length; i++) {
                    const r = s[i];
                    box(380, r[3], 130, 34, 18, r[2], r[0], r[1], { size: 10.5, submono: false });
                    if (i === 2) cross(560, r[3] + 18, C.red);
                    arrow(200, 112, 376, r[3] + 17, r[4] ? C.grey : (i === 2 ? C.red : C.ink), { dash: r[4] || i === 2 });
                }
                T("75%", 300, 52, { bold: true, size: 10.5, color: C.blue }); T("25%", 300, 110, { bold: true, size: 10.5, color: C.blue });
                T("chỉ dùng khi tất cả chết", 580, 228, { size: 9.5, color: C.mut });
            },
            "ng-ws": () => {
                T("Mặc định: Nginx nói HTTP/1.0 và bỏ header Upgrade", 14, 16, { bold: true, size: 10.5, align: "left", color: C.red });
                card(14, 30, 96, 40, C.grey, { title: "Trình duyệt" }); card(270, 30, 96, 40, C.green, { title: "Nginx" }); card(530, 30, 96, 40, C.blue, { title: "App" });
                arrow(110, 50, 268, 50, C.ink, { label: "Upgrade: websocket", mono: true, dy: -10 });
                arrow(368, 50, 528, 50, C.red, { label: "(header bị bỏ)", dy: -18 }); cross(448, 50, C.red);
                badge(150, 94, "ngắt sau ~60s / lỗi 400", C.red, 150);
                T("Cấu hình đúng", 14, 130, { bold: true, size: 10.5, align: "left", color: C.green });
                card(14, 146, 96, 40, C.grey, { title: "Trình duyệt" }); card(270, 146, 96, 40, C.green, { title: "Nginx" }); card(530, 146, 96, 40, C.blue, { title: "App" });
                arrow(110, 166, 268, 166, C.green, { label: "Upgrade: websocket", mono: true, dy: -10 });
                arrow(368, 166, 528, 166, C.green, { label: "Upgrade + HTTP/1.1", mono: true, dy: -10 });
                badge(320, 204, "101 Switching Protocols", C.green, 160);
                T("proxy_http_version 1.1;  proxy_set_header Upgrade $http_upgrade;  Connection $connection_upgrade;", 320, 232, { size: 9, mono: true, color: C.mut });
            },
            "ng-sites": () => {
                card(14, 70, 134, 56, C.blue, { title: "sites-available/", sub: "api.conf (bản gốc)", mono: true, size: 10 });
                card(184, 70, 124, 56, C.violet, { title: "sites-enabled/", sub: "api.conf (symlink)", mono: true, size: 10 });
                card(344, 70, 124, 56, C.amber, { title: "nginx -t", sub: "kiểm tra cú pháp", mono: true });
                card(504, 70, 122, 56, C.green, { title: "reload", sub: "nạp cấu hình mới", mono: true });
                arrow(148, 98, 182, 98, C.ink); arrow(308, 98, 342, 98, C.ink); arrow(468, 98, 502, 98, C.ink);
                T("ln -s", 165, 62, { mono: true, size: 9.5, color: C.violet, bold: true });
                T("systemctl reload nginx", 565, 62, { mono: true, size: 8.5, color: C.green, bold: true });
                tick(406, 150, C.green); T("syntax is ok → reload", 406, 172, { size: 9.5, color: C.green });
                cross(406, 202, C.red); T("emerg → KHÔNG reload, sửa trước", 406, 222, { size: 9.5, color: C.red });
                T("Dùng reload, không restart", 560, 150, { size: 9.5, color: C.mut });
                cap("Quên ln -s thì file nằm đó nhưng Nginx không đọc");
            },
            "ng-redirect": () => {
                card(14, 96, 100, 46, C.grey, { title: "Trình duyệt" });
                box(250, 40, 120, 46, 20, C.amber, "Cloudflare", "SSL: Flexible", {});
                box(250, 160, 120, 46, 20, C.green, "Nginx", "return 301 https", { submono: true });
                arrow(114, 112, 246, 74, C.ink, { label: "https", dx: -10 });
                arrow(310, 90, 310, 156, C.ink, { label: "gửi bằng HTTP", dx: 58, dy: 0 });
                arrow(246, 196, 70, 150, C.red, { label: "301 → https", dx: -4, dy: 12 });
                badge(540, 100, "ERR_TOO_MANY_REDIRECTS", C.red, 188);
                card(440, 130, 186, 70, C.green, { title: "Cách sửa", sub: "SSL mode = Full (strict)", fill: 0.12 });
                T("hoặc bỏ redirect khi", 533, 212, { size: 9, color: C.mut }); T("X-Forwarded-Proto đã là https", 533, 225, { size: 9, color: C.mut });
                T("vòng lặp", 120, 196, { bold: true, size: 10.5, color: C.red });
            },
            "ng-cache": () => {
                card(14, 96, 100, 46, C.grey, { title: "Trình duyệt", sub: "cache riêng" });
                box(250, 92, 120, 46, 20, C.green, "Nginx", "proxy_cache", {});
                box(510, 92, 110, 46, 20, C.blue, "App", "", {});
                arrow(114, 112, 246, 112, C.ink); arrow(372, 112, 508, 112, C.amber, { label: "MISS", bold: true, dy: -10 });
                badge(190, 40, "HIT", C.green, 50); T("Nginx trả luôn, app không bị gọi", 190, 62, { size: 9.5, color: C.mut });
                arrow(190, 72, 250, 98, C.green);
                badge(440, 40, "X-Cache-Status: MISS", C.amber, 170); T("lần đầu: hỏi app rồi lưu lên đĩa", 440, 62, { size: 9.5, color: C.mut });
                badge(64, 184, "304", C.blue, 50); T("ETag khớp → không tải lại body", 190, 184, { size: 9.5, color: C.mut, align: "left" });
                T("curl -I https://… | grep -i x-cache", 320, 226, { mono: true, size: 10, color: C.mut });
            },
            "ng-docker": () => {
                T("A. Nginx trên host  →  cổng đã publish", 14, 16, { bold: true, size: 10.5, align: "left", color: C.green });
                box(24, 34, 100, 36, 16, C.green, "Nginx", "host", {}); box(430, 34, 120, 36, 16, C.blue, "api", "127.0.0.1:3000", { submono: true });
                arrow(160, 50, 426, 50, C.green, { label: "proxy_pass http://127.0.0.1:3000", mono: true, dy: -10 }); tick(590, 50, C.green);
                T("B. Nginx trong container  →  tên dịch vụ cùng mạng", 14, 106, { bold: true, size: 10.5, align: "left", color: C.green });
                box(24, 124, 100, 36, 16, C.green, "nginx", "container", {}); box(430, 124, 120, 36, 16, C.blue, "api", "mạng chung", {});
                arrow(160, 140, 426, 140, C.green, { label: "proxy_pass http://api:3000", mono: true, dy: -10 }); tick(590, 140, C.green);
                T("C. Sai kinh điển: localhost trong container", 14, 196, { bold: true, size: 10.5, align: "left", color: C.red });
                box(24, 212, 100, 30, 14, C.red, "nginx", "", {}); 
                arrow(160, 228, 340, 228, C.red, { label: "http://localhost:3000", mono: true, dy: -10 }); cross(366, 228, C.red);
                badge(520, 228, "502 · connect() refused", C.red, 190);
                T("localhost = chính container nginx, không phải máy chủ", 330, 250, { size: 9.5, color: C.mut });
            }
        };
        if (F[fig.kind]) F[fig.kind]();
    }
}
