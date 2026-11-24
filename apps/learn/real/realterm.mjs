// Terminal THẬT cho Quantum Learn: mỗi lab / sự cố chạy trong một container Linux (docker hoặc kiri)
// với nhân Linux và các gói thật; bash chạy trong PTY thật, hiển thị qua bộ giả lập terminal (vt.mjs).
// Trạng thái bài (file, user…) do shell mô phỏng của khoá học dựng; ta đẩy nó vào container, và sau mỗi lệnh
// đọc ngược trạng thái thật (hệ file + lịch sử lệnh) vào shell mô phỏng để các hàm check() chấm như cũ.
import { spawn, execFile } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { VT } from "./vt.mjs";
import { DockProxy, cleanupLab, cleanupAllLabs } from "./dockproxy.mjs";
import { provisionDocker, bridgeDocker } from "./labdocker.mjs";
import { homedir } from "node:os";

const HERE = dirname(fileURLToPath(import.meta.url));
const IMAGE = "quantum-learn:vps";
const LABEL = "quantum-learn=1";
const sessions = new Map(); // key → { name, vt, pty, offset, ... }
const wanted = new Map();
const pending = new Map();  // lab đang dựng (để dừng được giữa chừng)
const GW_IP = "172.17.0.1";   // key → [rows, cols] pedido por la UI mientras el contenedor aún se prepara

function sh(cmd, args, { input, timeout = 60000 } = {}) {
  return new Promise((resolve, reject) => {
    const p = execFile(cmd, args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, timeout }, (err, stdout, stderr) => {
      if (err) { err.stderr = stderr; reject(err); } else resolve(stdout);
    });
    if (input != null) p.stdin.end(input);
  });
}

let imageReady = null;
export function ensureImage(log = () => {}) {
  imageReady ??= (async () => {
    try { await sh("docker", ["image", "inspect", IMAGE]); return; } catch {}
    log("Đang dựng image lab lần đầu (cài gói, khoảng 1–2 phút)…");
    await sh("sh", [join(HERE, "build-image.sh")], { timeout: 900000 });
  })().catch((e) => { imageReady = null; throw e; });
  return imageReady;
}

const q = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";

/** Script bash dựng lại hệ file mô phỏng trong container. */
function provisionScript(simSh, user) {
  const n = simSh.fs.n;
  const skip = new Set(["/", "/proc", "/dev", "/etc/hostname", "/etc/os-release", "/etc/passwd", "/etc/group", "/etc/shadow", "/etc/sudoers"]);
  const paths = Object.keys(n).filter((p) => !skip.has(p)).sort((a, b) => a.split("/").length - b.split("/").length || a.localeCompare(b));
  const owners = new Set([user]);
  for (const p of paths) if (n[p].owner) owners.add(n[p].owner);
  const out = ["set +e", "export LC_ALL=C.UTF-8", "userdel -r ubuntu >/dev/null 2>&1"];
  for (const o of owners) {
    if (o === "root") continue;
    out.push(`id ${q(o)} >/dev/null 2>&1 || useradd -m -s /bin/bash ${q(o)}`);
  }
  out.push(`[ ${q(user)} = root ] || usermod -aG sudo,adm,systemd-journal ${q(user)}`);
  out.push(`install -m644 -o ${q(user)} /dev/null ${q(user === "root" ? "/root" : "/home/" + user)}/.sudo_as_admin_successful`);
  const after = [];
  // Binarios y unit files del sistema son los REALES de la imagen: los falsos del simulador ("ELF…") no se copian.
  const isSystem = (p) => /^\/(usr\/(bin|sbin|lib|lib64|share)|bin|sbin|lib|lib64)(\/|$)/.test(p);
  const STUB = "const http=require('http');const fs=require('fs');let port=8888;try{const m=/^PORT=(\\d+)/m.exec(fs.readFileSync(__dirname+'/../.env','utf8'));if(m)port=+m[1];}catch(e){}\nif(process.env.PORT)port=+process.env.PORT;\nhttp.createServer((q,r)=>{r.end('ok from '+__filename+'\\n');}).listen(port,()=>console.log('listening on '+port));\n";
  for (const p of paths) {
    const e = n[p];
    if (isSystem(p) && e.t !== "d") continue;
    const mode = ((e.mode ?? (e.t === "d" ? 493 : 420)) & 0o7777).toString(8);
    if (e.t === "d") { if (!isSystem(p)) out.push(`mkdir -p ${q(p)}`); }
    else if (e.t === "l") out.push(`mkdir -p ${q(dirname(p))}; ln -sfn ${q(e.target)} ${q(p)}`);
    else {
      let c = String(e.c ?? "");
      if (/\/dist\/main\.js$/.test(p) && /NestFactory|nội dung build/.test(c)) c = STUB;   // app Node mẫu: máy chủ HTTP thật
      const b64 = Buffer.from(c, "utf8").toString("base64");
      out.push(`mkdir -p ${q(dirname(p))}; printf %s ${q(b64)} | base64 -d > ${q(p)}`);
    }
    if (isSystem(p)) continue;
    if (e.t !== "l") after.push(`chmod ${mode} ${q(p)}`);
    if (e.owner) after.push(`chown -h ${q(e.owner)}:${q(e.group || e.owner)} ${q(p)} 2>/dev/null || chown -h ${q(e.owner)} ${q(p)}`);
  }
  // ---- nginx: cấu hình của bài thay hẳn cấu hình mặc định của gói
  const hasNginx = !!n["/etc/nginx/nginx.conf"];
  if (hasNginx) out.unshift("rm -rf /etc/nginx/sites-enabled/* /etc/nginx/conf.d/* /var/www/html/index*.html 2>/dev/null");
  // chứng chỉ giả của bài ("CERT x" / "KEY") → chứng chỉ tự ký thật, để `nginx -t` và `curl -k` chạy được
  const certDomains = new Set();
  for (const p of paths) { const m = /^\/etc\/letsencrypt\/live\/([^/]+)\/(fullchain|privkey)\.pem$/.exec(p); if (m) certDomains.add(m[1]); }
  for (const d of certDomains) {
    out.push(`mkdir -p /etc/letsencrypt/live/${q(d)}; openssl req -x509 -nodes -newkey rsa:2048 -days 90 -subj "/CN=${d}" -keyout /etc/letsencrypt/live/${d}/privkey.pem -out /etc/letsencrypt/live/${d}/fullchain.pem >/dev/null 2>&1`);
  }
  if (n["/etc/letsencrypt/ssl-dhparams.pem"]) out.push("openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 1024 >/dev/null 2>&1");
  // tên miền trong server_name → 127.0.0.1 (curl https://domain chạy được trong lab)
  const names = new Set();
  for (const [p, e] of Object.entries(n)) {
    if (e.t !== "f" || !/^\/etc\/nginx\//.test(p)) continue;
    for (const m of String(e.c).matchAll(/server_name\s+([^;]+);/g)) for (const x of m[1].split(/\s+/)) if (/^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/i.test(x)) names.add(x);
  }
  if (names.size) out.push(`echo "127.0.0.1 ${[...names].join(" ")}" >> /etc/hosts`);
  // ---- ufw: đặt tường lửa thật về đúng trạng thái bài mô phỏng (mặc định: chưa chọn chính sách ⇒ cho phép hết)
  out.push("ufw --force reset >/dev/null 2>&1; ufw --force disable >/dev/null 2>&1; ssh-keygen -A >/dev/null 2>&1; mkdir -p /run/sshd");
  const U = simSh.W?.ufw;
  if (U) {
    out.push(`ufw default ${U.defIn || "allow"} incoming >/dev/null 2>&1; ufw default ${U.defOut || "allow"} outgoing >/dev/null 2>&1`);
    for (const r of U.rules ?? []) {
      const act = String(r.action || "ALLOW").toLowerCase();
      const to = String(r.to || "");
      const m = /^(\d+)(?:\/(tcp|udp))?$/.exec(to);
      if (r.from && r.from !== "Anywhere" && m) out.push(`ufw ${act} from ${q(r.from)} to any port ${m[1]}${m[2] ? " proto " + m[2] : ""} >/dev/null 2>&1`);
      else if (to && to !== "Anywhere") out.push(`ufw ${act} ${q(to)} >/dev/null 2>&1`);
    }
    if (U.active) out.push("ufw --force enable >/dev/null 2>&1");
  }
  // systemd: nạp unit mới, rồi đưa dịch vụ về đúng trạng thái mà bài mô phỏng quy định
  const L = simSh.W?.lin;
  after.reverse();
  out.push(...after);
  after.length = 0;
  out.push("systemctl daemon-reload");
  // Các bài ghi sẵn PID cụ thể (kill 905, kill 3150…): ghim PID bằng ns_last_pid. Độ lệch = số tiến trình systemd
  // fork trước khi tiến trình chính ra đời (đo thực tế: cron +2, nginx +5, ssh +6).
  out.push("systemctl disable --now ssh.socket >/dev/null 2>&1");
  const pin = (unit, pid, off) => out.push(`systemctl stop ${unit} 2>/dev/null; echo ${pid - off} > /proc/sys/kernel/ns_last_pid; systemctl start ${unit} 2>/dev/null`);
  const byName = (nm) => (L?.procs ?? []).find((p) => p.base && p.name === nm && p.pid);
  const cron = byName("cron"), sshd = byName("sshd"), nginx = byName("nginx");
  if (cron) pin("cron", cron.pid, 2); else out.push("systemctl start cron");
  if (sshd) pin("ssh", sshd.pid, 6); else out.push("systemctl start ssh 2>/dev/null");
  if (simSh.W?.nginx && simSh.W.nginx.active === false) out.push("systemctl stop nginx 2>/dev/null");
  else if (nginx) pin("nginx", nginx.pid, 5); else out.push("systemctl start nginx 2>/dev/null");
  for (const u of Object.values(L?.units ?? {})) {
    if (!u?.name || u.name === "cron.service") continue;
    if (u.enabled === "enabled") out.push(`systemctl enable ${q(u.name)} 2>/dev/null`);
    if (["active", "activating", "failed"].includes(u.active)) out.push(`systemctl start ${q(u.name)} 2>/dev/null`);
  }
  // ứng dụng upstream (cổng 3000, 8888…): máy chủ HTTP nhỏ thật, thay cho "node app" của mô phỏng
  const BACKEND = "const http=require('http');const port=+process.argv[2];\nhttp.createServer((q,r)=>{const slow=/slow|report|export|stats/.test(q.url);const ok=port===3000||port===3100||/^\\/(health|healthz)?$|^\\/api(\\/|$)|^\\/(socket\\.io|uploads|auth)\\//.test(q.url.split('?')[0]);\nconst go=()=>{r.writeHead(ok?200:404,{'Content-Type':'application/json','X-Upstream-Port':port});r.end(JSON.stringify({ok,port,path:q.url,host:q.headers.host}));};slow?setTimeout(go,2000):go();}).listen(port,'127.0.0.1');\n";
  const ups = [];
  for (const x of simSh.W?.extra ?? []) if (x?.port && x.proc === "node") ups.push({ port: x.port, pid: x.pid, user: "tutor" });
  for (const p of L?.procs ?? []) if (p.port && p.name === "node" && !ups.some((u) => u.port === p.port)) ups.push({ port: p.port, pid: p.pid, user: p.user });
  if (ups.length) out.push(`mkdir -p /opt/ql; printf %s ${q(Buffer.from(BACKEND).toString("base64"))} | base64 -d > /opt/ql/backend.js`);
  for (const u of ups) {
    const usr = n["/home/" + u.user] || u.user === "root" ? u.user : "root";
    out.push(`bash -c ${q("cd /tmp; " + (u.pid ? `echo ${u.pid - 1} > /proc/sys/kernel/ns_last_pid; ` : "") + `setsid nohup setpriv --reuid=${usr} --regid=${usr} --init-groups node /opt/ql/backend.js ${u.port} >/dev/null 2>&1 &`)}`);
  }
  // tiến trình nền có sẵn cho bài (vd. `yes` ngốn CPU, `sleep` treo): lệnh trơn, không thuộc unit nào
  for (const p of L?.procs ?? []) {
    if (p.unit || !p.cmd || /^[\/-]|:/.test(p.cmd) || p.name === "bash") continue;
    const u = q(p.user || "root");
    const pinPid = p.pid ? `echo ${p.pid - 1} > /proc/sys/kernel/ns_last_pid; ` : "";
    out.push(`bash -c ${q("cd /tmp; " + pinPid + "setsid nohup setpriv --reuid=" + (p.user || "root") + " --regid=" + (p.user || "root") + " --init-groups " + p.cmd + " >/dev/null 2>&1 &")}`);
  }
  out.push(": > /var/tmp/.qlhist", "chmod 666 /var/tmp/.qlhist", "true");
  return out.join("\n") + "\n";
}

export async function start({ key, simSh, host, user, emit, rows = 28, cols = 100 }) {
  await stop(key);
  wanted.set(key, [rows, cols]);
  await ensureImage((m) => emit({ ev: "note", key, text: m }));
  const name = "ql-" + key.replace(/[^a-zA-Z0-9_.-]/g, "-") + "-" + Date.now().toString(36);
  // Docker của lab = engine Kiri thật, qua proxy giới hạn theo nhãn (dockproxy.mjs); socket gắn vào /opt/ql-docker
  const sockDir = join(process.env.XDG_RUNTIME_DIR || "/tmp", "quantum-learn", name);
  const stage = join(process.env.XDG_STATE_HOME || join(homedir(), ".local/state"), "quantum", "learn-labs", name);
  const dnat = (rules) => sh("docker", ["exec", name, "bash", "-c", [
    "iptables -t nat -N QL_DOCKER 2>/dev/null; iptables -t nat -F QL_DOCKER",
    "iptables -t nat -C OUTPUT -o lo -j QL_DOCKER 2>/dev/null || iptables -t nat -A OUTPUT -o lo -j QL_DOCKER",
    "iptables -t nat -C POSTROUTING -s 127.0.0.1 ! -o lo -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 127.0.0.1 ! -o lo -j MASQUERADE",
    ...rules.map((r) => `iptables -t nat -A QL_DOCKER -p ${r.proto} -d 127.0.0.1 --dport ${r.port} -j DNAT --to-destination ${r.ip}:${r.cport}`),
    "true"].join("; ")]).catch(() => {});
  const proxy = new DockProxy({ lab: name, sockDir, stage, labContainer: name, onPorts: dnat });
  await proxy.start();
  pending.set(key, { proxy, stage, name });
  await sh("docker", ["run", "-d", "--name", name, "--hostname", host || "vps", "--label", LABEL, "--label", `quantum-learn.owner=${process.pid}`,
    "--privileged", "--memory", "1g", "--pids-limit", "1024", "-v", `${sockDir}:/opt/ql-docker`, IMAGE, "/sbin/init"]);
  emit({ ev: "note", key, text: "Đang khởi động systemd trong container…" });
  await sh("docker", ["exec", name, "systemctl", "is-system-running", "--wait"], { timeout: 60000 }).catch(() => {});
  // script chấm luôn lấy bản mới nhất trong repo (không phụ thuộc image đã dựng)
  for (const f of ["dump.sh", "dump_state.py", "bashrc"]) await sh("docker", ["cp", join(HERE, f), `${name}:/opt/ql/${f}`]);
  await sh("docker", ["exec", name, "chmod", "+x", "/opt/ql/dump.sh", "/opt/ql/dump_state.py"]);
  await sh("docker", ["exec", "-i", name, "bash", "-s"], { input: provisionScript(simSh, user), timeout: 120000 });
  // docker trong lab: socket chỉ nhóm docker dùng được (như máy thật), localhost:<cổng publish> đi tới container
  const inDocker = simSh.W?.dockerGroup !== false;
  await sh("docker", ["exec", name, "bash", "-c", `groupadd -f docker; chgrp docker /opt/ql-docker; chmod 750 /opt/ql-docker; ln -sf /opt/ql-docker/docker.sock /var/run/docker.sock; sysctl -qw net.ipv4.conf.all.route_localnet=1; ${inDocker ? `usermod -aG docker ${user}` : `gpasswd -d ${user} docker >/dev/null 2>&1`}; true`]);
  await setupBuilder(name, user).catch((e) => emit({ ev: "note", key, text: "Không dựng được builder: " + String(e.message).slice(0, 120) }));
  if ((simSh.W?.containers ?? []).length) {
    emit({ ev: "note", key, text: "Đang dựng các container Docker của bài (engine Kiri)…" });
    await provisionDocker(simSh, { lab: name, proxy, note: (t) => emit({ ev: "note", key, text: t }) });
    await proxy.syncPorts().catch(() => {});
  }

  [rows, cols] = wanted.get(key) ?? [rows, cols];
  const vt = new VT(rows, cols);
  pending.delete(key);
  const s = { key, name, vt, offset: 0, proxy, stage, simSh, user, emit, dead: false, timer: null, gradeTimer: null, grading: false, again: false, cmds: 0 };
  sessions.set(key, s);
  const cwd = simSh.cwd || simSh.home;
  const pty = spawn("python3", ["-I", join(HERE, "ptyhost.py"),
    "docker", "exec", "-it", "-u", user, "-w", cwd, "-e", "TERM=xterm-256color", name, "bash", "--rcfile", "/opt/ql/bashrc", "-i"],
    { stdio: ["pipe", "pipe", "inherit"] });
  s.pty = pty;
  vt.reply = (t) => write(s, Buffer.from(t));
  vt.onOsc = (o) => {
    const m = /^777;ql;(-?\d+);(.*)$/.exec(o);
    if (!m) return;
    s.pwd = m[2];
    if (s.ready) scheduleGrade(s); else s.ready = true;   // el primer prompt no cuenta
  };
  let acc = "";
  pty.stdout.on("data", (d) => {
    acc += d.toString("latin1");
    let i;
    while ((i = acc.indexOf("\n")) >= 0) {
      const line = acc.slice(0, i); acc = acc.slice(i + 1);
      let m; try { m = JSON.parse(line); } catch { continue; }
      if (m.o) { vt.write(Buffer.from(m.o, "base64")); s.offset = 0; schedulePaint(s); }
      else if (m.x != null) { s.dead = true; paint(s); emit({ ev: "exit", key, code: m.x }); }
    }
  });
  pty.on("exit", () => { s.dead = true; });
  await runGrade(s);   // trạng thái ban đầu (đường cơ sở để nhận ra nginx nạp lại cấu hình)
  return { prompt: "" };
}

function write(s, buf) {
  if (s.dead || !s.pty?.stdin.writable) return;
  s.pty.stdin.write(JSON.stringify({ i: buf.toString("base64") }) + "\n");
}
function schedulePaint(s) {
  if (s.timer) return;
  s.timer = setTimeout(() => { s.timer = null; paint(s); }, 25);
}
function paint(s) { s.emit({ ev: "screen", key: s.key, ...s.vt.snapshot(s.offset), dead: s.dead }); }

export function input(key, b64) { const s = sessions.get(key); if (s) write(s, Buffer.from(b64, "base64")); }
export function resize(key, rows, cols) {
  if (rows < 2 || cols < 10) return;
  const s = sessions.get(key);
  if (!s) { wanted.set(key, [rows, cols]); return; }
  if (rows === s.vt.rows && cols === s.vt.cols) return;
  s.vt.resize(rows, cols);
  if (!s.dead) s.pty.stdin.write(JSON.stringify({ r: [rows, cols] }) + "\n");
  paint(s);
}
export function scroll(key, delta) {
  const s = sessions.get(key);
  if (!s) return;
  s.offset = Math.max(0, Math.min(s.vt.scrollback.length, s.offset + delta));
  paint(s);
}
export function repaint(key) { const s = sessions.get(key); if (s) paint(s); }

export async function stop(key) {
  const s = sessions.get(key) ?? pending.get(key);
  if (!s) return;
  sessions.delete(key); pending.delete(key); wanted.delete(key);
  clearTimeout(s.timer); clearTimeout(s.gradeTimer);
  try { s.pty?.kill(); } catch {}
  await s.proxy?.stop();
  await sh("docker", ["rm", "-f", s.name]).catch(() => {});
  await cleanupLab(s.name, s.stage).catch(() => {});
}
const alive = (pid) => { try { process.kill(+pid, 0); return true; } catch { return false; } };
/** Dọn lab: chỉ của backend này (own) hoặc của backend đã chết (mồ côi). Không đụng lab của app khác đang chạy. */
async function sweep(ownOnly) {
  try {
    const ids = (await sh("docker", ["ps", "-aq", "--filter", `label=${LABEL}`])).split("\n").filter(Boolean);
    for (const id of ids) {
      const owner = (await sh("docker", ["inspect", "-f", '{{index .Config.Labels "quantum-learn.owner"}}', id]).catch(() => "")).trim();
      const mine = owner === String(process.pid);
      if (mine || (!ownOnly && (!owner || !alive(owner)))) {
        const nm = (await sh("docker", ["inspect", "-f", "{{.Name}}", id]).catch(() => "")).trim().replace(/^\//, "");
        await sh("docker", ["rm", "-f", id]).catch(() => {});
        if (nm) await cleanupLab(nm, null).catch(() => {});
      }
    }
  } catch {}
}
export async function stopAll() {
  await Promise.all([...sessions.keys(), ...pending.keys()].map(stop));
  await sweep(true);
}
export const cleanupStale = () => sweep(false);

// ---------------- chấm bài: đọc trạng thái thật vào shell mô phỏng
function scheduleGrade(s) {
  clearTimeout(s.gradeTimer);
  s.gradeTimer = setTimeout(() => runGrade(s), 250);
}
async function runGrade(s) {
  if (s.grading) { s.again = true; return; }
  s.grading = true;
  try {
    const raw = await sh("docker", ["exec", s.name, "/opt/ql/dump.sh"], { timeout: 30000 });
    const nodes = { "/": { t: "d", mode: 0o755, owner: "root" } };
    const hist = [], histLines = [], procs = [], units = [], listens = [], extraFiles = {}, ufw = { rules: [] };
    let sshSig = "";
    for (const line of raw.split("\n")) {
      if (line.startsWith("N\t")) {
        const [, t, m, owner, group, p, link, b64] = line.split("\t");
        const e = { mode: parseInt(m, 8), owner, group };
        if (t === "d") e.t = "d";
        else if (t === "l") { e.t = "l"; e.target = link; }
        else { e.t = "f"; e.c = b64 ? Buffer.from(b64, "base64").toString("utf8") : ""; }
        if (p) nodes[p] = e;
      } else if (line.startsWith("P\t")) {
        const [, pid, ppid, user, ni, st, tty, sigign, unit, comm, ...cmd] = line.split("\t");
        procs.push({ pid: +pid, ppid: +ppid, user, ni: +ni, stat: st, tty, nohup: sigign === "1", unit, name: comm, cmd: cmd.join("\t") });
      } else if (line.startsWith("S\t")) {
        const [, name, active, sub, enabled, pid, nr, result] = line.split("\t");
        units.push({ name, active, sub, enabled, pid: +pid, restarts: +nr, result });
      } else if (line.startsWith("L\t")) {
        const [, bind, port, pid] = line.split("\t");
        listens.push({ bind, port: +port, pid: +pid });
      } else if (line.startsWith("G\t")) {
        ufw.logging = line.split("\t")[1];
      } else if (line.startsWith("U\t")) {
        const [, a, di, dout] = line.split("\t");
        ufw.active = a === "1"; ufw.defIn = di; ufw.defOut = dout;
      } else if (line.startsWith("R\t")) {
        const [, to, action, from] = line.split("\t");
        ufw.rules.push({ to, action, from });
      } else if (line.startsWith("X\t")) {
        const [, mp, n2] = line.split("\t");
        sshSig = mp + ":" + n2;
      } else if (line.startsWith("F\t")) {
        const [, path, b64] = line.split("\t");
        extraFiles[path] = Buffer.from(b64, "base64").toString("utf8");
      } else if (line.startsWith("H\t")) {
        const [, rc, ...c] = line.split("\t");
        const cmd = c.join("\t").trim();
        if (!cmd) continue;
        histLines.push({ cmd, code: parseInt(rc, 10) || 0 });
        // cada comando simple de la línea es una entrada (como en el shell simulado)
        for (const part of cmd.split(/\s*(?:\|\||&&|\||;)\s*/).filter(Boolean)) {
          hist.push({ cmd: part.replace(/^sudo\s+/, "sudo "), code: parseInt(rc, 10) || 0, sudo: /^sudo\b/.test(part), out: "" });
        }
      }
    }
    for (const [path, c] of Object.entries(extraFiles)) nodes[path] ??= { t: "f", c, mode: 0o644, owner: "root" };
    s.simSh.fs.n = nodes;
    bridgeWorld(s.simSh, procs, units, listens, nodes);
    bridgeNginx(s.simSh, procs, units);
    bridgeSecurity(s.simSh, procs, units, ufw, sshSig, nodes);
    await bridgeDocker(s.simSh, s.proxy, nodes, s.user).catch(() => {});
    s.simSh.hist = hist;
    s.simSh.histLines = histLines;
    if (s.pwd) s.simSh.cwd = s.pwd;
    s.cmds = hist.length;
    await s.onState?.(s);
  } catch (e) {
    s.emit({ ev: "note", key: s.key, text: "Không đọc được trạng thái container: " + (e?.message ?? e) });
  } finally {
    s.grading = false;
    if (s.again) { s.again = false; scheduleGrade(s); }
  }
}
export function onState(key, fn) { const s = sessions.get(key); if (s) s.onState = fn; }
export function has(key) { return sessions.has(key); }
export async function available() {
  try { await sh("docker", ["version", "--format", "{{.Server.Version}}"], { timeout: 8000 }); return true; } catch { return false; }
}

/** Trạng thái thật của container → mô hình "thế giới" (W.lin) mà check() của các bài dịch vụ/tiến trình đọc. */
function bridgeWorld(simSh, procs, units, listens, nodes) {
  const l = simSh.W?.lin;
  if (!l) return;
  const now = l.now;
  for (const li of listens) {
    const p = procs.find((x) => x.pid === li.pid);
    if (p && !p.port) { p.port = li.port; p.bind = li.bind === "::" || li.bind === "*" ? "0.0.0.0" : li.bind; }
  }
  l.procs = procs.map((p) => Object.assign({ cpu: 0, mem: 0.1, rss: 4000, vsz: 20000, start: now, cputime: 0, base: false }, p));
  const old = l.units ?? {};
  l.units = {};
  for (const u of units) {
    const prev = old[u.name] ?? {};
    const file = nodes["/etc/systemd/system/" + u.name] ? "/etc/systemd/system/" + u.name : "/lib/systemd/system/" + u.name;
    const text = nodes[file]?.c ?? "";
    let cfg = prev.cfg;
    try { cfg = globalThis.VPS?.lin?.parseUnit?.(text) ?? prev.cfg; } catch {}
    l.units[u.name] = Object.assign({ since: now, loadedText: text, cfg, kind: /\.timer$/.test(u.name) ? "timer" : "service", dirty: false },
      prev, { name: u.name, file, active: u.active, sub: u.sub, enabled: u.enabled === "enabled-runtime" ? "enabled" : u.enabled, pid: u.pid, restarts: u.restarts, result: u.result, loadedText: text });
  }
  // crontab: los archivos reales de /var/spool/cron/crontabs/<user>
  l.cron = {};
  for (const [path, e] of Object.entries(nodes)) {
    const m = /^\/var\/spool\/cron\/crontabs\/([^/]+)$/.exec(path);
    if (m && e.t === "f") l.cron[m[1]] = e.c;
  }
  l.ownSS = true;
}

/** nginx: `live` = cấu hình nginx đang chạy. Nginx thật nạp lại cấu hình ⇒ bộ worker đổi; khi đó nạp lại cấu hình trên đĩa vào mô hình. */
const ngSig = new WeakMap();
function bridgeNginx(simSh, procs, units) {
  const W = simSh.W;
  if (!W?.nginx) return;
  const unit = units.find((u) => u.name === "nginx.service");
  const active = !!unit && unit.active === "active";
  const sig = procs.filter((p) => /^nginx/.test(p.name)).map((p) => p.pid).sort((a, b) => a - b).join(",");
  const prev = ngSig.get(simSh);
  if (process.env.QL_DEBUG) console.error("ngSig", prev, "->", sig, active);
  ngSig.set(simSh, sig);
  if (!active) { W.nginx.active = false; return; }
  if (prev === undefined) { W.nginx.active = true; return; }      // lần đầu: giữ live do bài dựng
  if (sig !== prev) { let ok; try { ok = globalThis.VPS?.ngReload?.(simSh, false); } catch (e) { ok = String(e); } if (process.env.QL_DEBUG) console.error("ngReload", prev, sig, ok); }
  W.nginx.active = true;
}

/** ufw + sshd + trạng thái dịch vụ thật → W.ufw / W.ssh / W.svc (mô hình mà check() của các bài bảo mật đọc). */
const sshSigs = new WeakMap();
function bridgeSecurity(simSh, procs, units, ufw, sshSig, nodes) {
  const W = simSh.W;
  if (!W) return;
  syncUsers(simSh, nodes);
  const act = (n) => units.some((u) => u.name === n && u.active === "active");
  if (W.svc) { W.svc.ssh = act("ssh.service"); W.svc.nginx = act("nginx.service"); W.svc.cron = act("cron.service"); W.svc.fail2ban = act("fail2ban.service"); W.svc.ufw = ufw.active; }
  if (W.sec && ufw.logging) W.sec.logging = ufw.logging;
  if (W.ufw) {
    W.ufw.active = !!ufw.active; W.ufw.defIn = ufw.defIn; W.ufw.defOut = ufw.defOut;
    W.ufw.rules = ufw.rules.filter((r, i, a) => !/\(v6\)$/.test(r.to) && a.findIndex((x) => x.to === r.to && x.action === r.action && x.from === r.from) === i);
    const port = W.ssh?.activePort ?? 22;
    const ssh = (r) => r.action !== "DENY" && r.action !== "REJECT" && r.from !== undefined && (r.to === "OpenSSH" || r.to === "ssh" || r.to === String(port) || r.to === port + "/tcp" || r.to === "22" || r.to === "22/tcp" || r.to === "Anywhere");
    W.ufw.lockedOut = W.ufw.active && W.ufw.defIn === "deny" && !W.ufw.rules.some(ssh);
  }
  if (W.ssh) {
    const sp = procs.find((p) => p.name === "sshd" && p.port);
    const prev = sshSigs.get(simSh);
    sshSigs.set(simSh, sshSig);
    if (prev !== undefined && sshSig !== prev && act("ssh.service")) {          // sshd nạp lại / khởi động lại ⇒ áp dụng cấu hình trên đĩa
      try { globalThis.VPS?.sec?.snapshot?.(simSh); } catch {}
      W.ssh.reloadedOK = true;
    }
    if (sp && prev === undefined) W.ssh.activePort = sp.port;
    else if (sp && sshSig !== prev) W.ssh.activePort = sp.port;
  }
}

/** /etc/passwd, /etc/group, /etc/shadow thật → W.sec.users (adduser, usermod, passwd -l… do bash thật thực hiện). */
function syncUsers(simSh, nodes) {
  const S = simSh.W?.sec;
  const pw = nodes["/etc/passwd"]?.c, gr = nodes["/etc/group"]?.c;
  if (!S || !S.users || !pw) return;
  const shadow = Object.fromEntries(String(nodes["/etc/shadow"]?.c ?? "").split("\n").filter(Boolean).map((l) => l.split(":")).map((f) => [f[0], f[1] ?? ""]));
  const groups = {};
  for (const l of String(gr ?? "").split("\n").filter(Boolean)) { const [name, , gid, mem] = l.split(":"); groups[name] = { gid, mem: (mem || "").split(",").filter(Boolean) }; }
  const next = {};
  for (const l of pw.split("\n").filter(Boolean)) {
    const [name, , uid] = l.split(":");
    if (+uid < 1000 || +uid >= 65534 || name === "ubuntu") continue;
    const prev = S.users[name] ?? {};
    const sh = shadow[name] ?? "";
    next[name] = Object.assign({}, prev, {
      uid: +uid,
      sudo: !!groups.sudo?.mem.includes(name),
      locked: sh.startsWith("!") && sh.length > 1 || sh.startsWith("*") && sh.length > 1,
      groups: Object.entries(groups).filter(([g, v]) => v.mem.includes(name) && g !== "sudo").map(([g]) => g),
    });
  }
  S.users = next;
  S.nextUid = Math.max(S.nextUid || 1002, ...Object.values(next).map((u) => u.uid + 1));
}

/** Builder dùng chung cho `docker build`: buildkitd chạy trong một container riêng (builder tích hợp của Kiri đang hỏng). */
let buildkit = null;
async function ensureBuildkit() {
  buildkit ??= (async () => {
    const ip = async () => (await sh("docker", ["inspect", "-f", "{{.NetworkSettings.IPAddress}}", "ql-buildkitd"])).trim();
    try { const st = (await sh("docker", ["inspect", "-f", "{{.State.Running}}", "ql-buildkitd"])).trim(); if (st === "true") return await ip(); } catch {}
    await sh("docker", ["rm", "-f", "ql-buildkitd"]).catch(() => {});
    await sh("docker", ["run", "-d", "--privileged", "--name", "ql-buildkitd", "--label", "quantum-learn-shared=1", "moby/buildkit:buildx-stable-1", "--addr", "tcp://0.0.0.0:1234"]);
    await new Promise((r) => setTimeout(r, 3000));
    return await ip();
  })().catch((e) => { buildkit = null; throw e; });
  return buildkit;
}
async function setupBuilder(name, user) {
  const ip = await ensureBuildkit();
  const wrapper = `#!/bin/sh
# Quantum Learn: docker build → buildx với builder buildkitd chung, kết quả nạp vào engine của lab (--load)
real=/usr/local/bin/docker
case "$1" in
  build) shift; exec $real buildx build --builder qlb --load "$@" ;;
  buildx) if [ "$2" = build ]; then shift 2; exec $real buildx build --builder qlb --load "$@"; fi ;;
esac
exec $real "$@"
`;
  await sh("docker", ["exec", "-i", name, "bash", "-c", "mkdir -p /opt/ql/bin && cat > /opt/ql/bin/docker && chmod +x /opt/ql/bin/docker && echo 'export PATH=/opt/ql/bin:$PATH' >> /opt/ql/bashrc"], { input: wrapper });
  await sh("docker", ["exec", "-u", user, name, "docker", "buildx", "create", "--name", "qlb", "--driver", "remote", `tcp://${ip}:1234`]);
}
