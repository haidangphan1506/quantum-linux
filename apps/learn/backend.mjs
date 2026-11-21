#!/usr/bin/env node
// Quantum Learn backend: nạp engine khoá học (shell mô phỏng + dữ liệu bài) của dự án course-vps,
// rồi phục vụ shell.qml qua stdin/stdout, mỗi dòng một JSON.
//
//   vào : {"id":1,"op":"catalog"}
//         {"id":2,"op":"open","key":"lab:lb1","host":"vps","user":"u","lesson":"lb1","debug":""}
//         {"id":3,"op":"run","key":"lab:lb1","text":"ls","passed":[true,false,...]}
//         {"id":4,"op":"complete","key":"lab:lb1","line":"cd ph"}
//         {"id":5,"op":"reset","key":"lab:lb1"}
//         {"id":6,"op":"load"}   {"id":7,"op":"save","data":{...}}
//         {"id":8,"op":"export","data":{...}}        → báo cáo .md + bản sao lưu .json trong ~/Documents/QuantumLearn
//         {"id":9,"op":"backups"}                    → các bản sao lưu (xuất tay + tự động mỗi ngày)
//         {"id":10,"op":"restore","path":"…","data":{...}} → gộp bản sao lưu vào tiến độ hiện tại
//   ra  : {"id":1,"ok":true,...} hoặc {"id":1,"ok":false,"error":"..."}
//
// Nguồn khoá học: $QUANTUM_LEARN_COURSE, hoặc ~/Documents/tutor/course-vps, ~/Documents/course-vps.
// Tiến độ: $XDG_STATE_HOME/quantum/learn.json (cùng cấu trúc với store Redux của bản web).
// Mỗi ngày giữ thêm một bản sao lưu tự động ($XDG_STATE_HOME/quantum/learn-backups, 30 ngày gần nhất).
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";

const HOME = homedir();
const STATE = join(process.env.XDG_STATE_HOME || join(HOME, ".local/state"), "quantum", "learn.json");
const AUTO_DIR = join(dirname(STATE), "learn-backups");
const KEEP_AUTO = 30;

function documentsDir() {
  try {
    const d = execFileSync("xdg-user-dir", ["DOCUMENTS"], { encoding: "utf8" }).trim();
    if (d && d !== HOME && existsSync(d)) return d;
  } catch {}
  return join(HOME, "Documents");
}
const EXPORT_DIR = process.env.QUANTUM_LEARN_EXPORT || join(documentsDir(), "QuantumLearn");
const ENGINE = "lib/course/engine/index.js";

function findCourse() {
  const cands = [
    process.env.QUANTUM_LEARN_COURSE,
    join(HOME, "Documents/tutor/course-vps"),
    join(HOME, "Documents/course-vps"),
  ].filter(Boolean);
  return cands.find((d) => existsSync(join(d, ENGINE))) ?? null;
}

const send = (obj) => process.stdout.write(JSON.stringify(obj) + "\n");

let engine = null; // { lessons, ip, Shell, equiv }
let loadError = null;
const course = findCourse();
try {
  if (!course) throw new Error("Không tìm thấy mã nguồn course-vps (đặt biến QUANTUM_LEARN_COURSE).");
  globalThis.window ??= globalThis;
  await import(pathToFileURL(join(course, ENGINE)).href);
  const g = globalThis;
  engine = { lessons: g.COURSE.lessons, ip: g.VPS.IP, Shell: g.VPS.Shell, equiv: g.COURSE.equiv };
} catch (e) {
  loadError = String(e?.message ?? e);
}

const byId = new Map(engine?.lessons.map((l) => [l.id, l]) ?? []);
const shells = new Map(); // key → { sh, lesson, debug }

/** Dữ liệu bài học dạng JSON (bỏ các hàm setup/check). */
function catalog() {
  return {
    ip: engine.ip,
    source: course,
    lessons: engine.lessons.map((l) => ({
      id: l.id,
      group: l.group,
      short: l.short,
      title: l.title,
      dek: l.dek,
      theory: l.theory,
      quiz: l.quiz.map(({ q, opts, ans, why }) => ({ q, opts, ans, why })),
      lab: { host: l.lab.host, user: l.lab.user, items: l.lab.items.map(({ text, hint }) => ({ text, hint })) },
      debugs: l.debugs.map(({ id, title, hard, host, user, symptom, story, goal, hints, fix, cause }) => ({
        id, title, hard: !!hard, host, user, symptom, story, goal, hints, fix, cause,
      })),
    })),
  };
}

function open({ key, lesson, debug }) {
  let s = shells.get(key);
  if (!s) {
    const l = byId.get(lesson);
    if (!l) throw new Error(`Không có bài ${lesson}`);
    const d = debug ? l.debugs.find((x) => x.id === debug) : null;
    if (debug && !d) throw new Error(`Không có sự cố ${debug}`);
    const src = d ?? l.lab;
    s = { sh: new engine.Shell({ host: src.host, user: src.user, setup: src.setup }), lesson: l, debug: d };
    shells.set(key, s);
  }
  return { prompt: s.sh.prompt() };
}

/** Chạy lệnh rồi chấm: lab → các câu chưa pass vừa đạt; sự cố → đã sửa xong chưa. */
function run({ key, text, passed = [] }) {
  const s = shells.get(key);
  if (!s) throw new Error("Terminal chưa mở");
  let r;
  try {
    r = s.sh.run(text);
  } catch (e) {
    r = { out: `lỗi mô phỏng: ${e?.message ?? e}\n`, code: 1 };
  }
  const res = { out: r.out ?? "", code: r.code ?? 0, clear: !!r.clear, needMore: !!r.needMore, prompt: s.sh.prompt() };
  if (r.needMore) return res;
  (s.sh.cmdLog ||= []).push({ t: text, out: res.out, code: res.code });

  if (s.debug) {
    let ok = false;
    try {
      ok = !!s.debug.check(s.sh);
    } catch {}
    res.solved = ok;
  } else {
    const budget = { t0: Date.now(), ms: 1500 };
    res.newly = [];
    s.lesson.lab.items.forEach((it, i) => {
      if (passed[i]) return;
      let ok = false;
      try {
        ok = !!it.check(s.sh);
      } catch {}
      if (!ok && engine.equiv) {
        try {
          ok = !!engine.equiv(s.lesson, s.sh, it, budget);
        } catch {}
      }
      if (ok) res.newly.push(i);
    });
  }
  return res;
}

function complete({ key, line }) {
  const s = shells.get(key);
  if (!s) return { word: "", matches: [] };
  try {
    return s.sh.complete(line) ?? { word: "", matches: [] };
  } catch {
    return { word: "", matches: [] };
  }
}

function load() {
  try {
    return { data: JSON.parse(readFileSync(STATE, "utf8")) };
  } catch {
    return { data: null };
  }
}

function writeAtomic(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.tmp`;
  writeFileSync(tmp, text);
  renameSync(tmp, path); // ghi nguyên tử: không bao giờ để lại file hỏng
}

const pad = (n) => String(n).padStart(2, "0");
const day = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const stamp = (d = new Date()) => `${day(d)}-${pad(d.getHours())}${pad(d.getMinutes())}`;
const fmtTime = (t) => {
  const d = new Date(t);
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

function save({ data }) {
  const text = JSON.stringify(data);
  writeAtomic(STATE, text);
  // bản sao lưu tự động của ngày hôm nay (ghi đè trong ngày), giữ KEEP_AUTO ngày gần nhất
  writeAtomic(join(AUTO_DIR, `learn-${day()}.json`), text);
  const old = readdirSync(AUTO_DIR).filter((f) => /^learn-\d{4}-\d{2}-\d{2}\.json$/.test(f)).sort().slice(0, -KEEP_AUTO);
  for (const f of old) {
    try {
      unlinkSync(join(AUTO_DIR, f));
    } catch {}
  }
  return { savedAt: Date.now() };
}

/** Gộp hai bản tiến độ, không làm mất dữ liệu (giống mergeProgress của bản web). */
function merge(a, b) {
  const o = { labs: {}, quiz: {}, debugs: {}, wrong: {}, flag: {}, hist: [], qord: {}, labOrd: {} };
  const seen = new Set();
  for (const src of [a, b]) {
    if (!src || typeof src !== "object") continue;
    for (const [k, arr] of Object.entries(src.labs ?? {})) {
      const cur = o.labs[k] ?? [];
      (arr ?? []).forEach((v, i) => (cur[i] = cur[i] || !!v));
      o.labs[k] = cur;
    }
    for (const [k, m] of Object.entries(src.quiz ?? {})) {
      o.quiz[k] ??= {};
      for (const [q, v] of Object.entries(m ?? {})) if (o.quiz[k][q] == null) o.quiz[k][q] = v;
    }
    for (const [k, v] of Object.entries(src.debugs ?? {})) if (v) o.debugs[k] = true;
    for (const [k, m] of Object.entries(src.wrong ?? {})) {
      o.wrong[k] ??= {};
      for (const [q, v] of Object.entries(m ?? {})) o.wrong[k][q] = Math.max(o.wrong[k][q] ?? 0, v ?? 0);
    }
    for (const [k, m] of Object.entries(src.flag ?? {})) {
      o.flag[k] ??= {};
      for (const [q, v] of Object.entries(m ?? {})) if (v) o.flag[k][q] = true;
    }
    for (const x of src.hist ?? []) {
      const key = `${x?.l}:${x?.t}`;
      if (x && x.l && !seen.has(key)) {
        seen.add(key);
        o.hist.push(x);
      }
    }
    Object.assign(o.qord, src.qord ?? {});
    Object.assign(o.labOrd, src.labOrd ?? {});
  }
  o.hist.sort((x, y) => x.t - y.t);
  if (o.hist.length > 300) o.hist = o.hist.slice(-300);
  // giữ vị trí đang học + giao diện của bản hiện tại
  return { ...o, cur: a?.cur ?? b?.cur ?? "", step: a?.step ?? 0, ui: a?.ui ?? {} };
}

/** Số liệu từng bài (dùng cho báo cáo). */
function summarize(p) {
  return engine.lessons.map((l, i) => {
    const q = p.quiz?.[l.id] ?? {};
    const quizNow = l.quiz.filter((x, j) => q[j] === x.ans).length;
    const best = Math.max(quizNow, ...(p.hist ?? []).filter((h) => h.l === l.id).map((h) => h.s));
    const lab = l.lab.items.filter((_, j) => p.labs?.[l.id]?.[j]).length;
    const dbg = l.debugs.filter((d) => p.debugs?.[d.id]).length;
    const total = l.quiz.length + l.lab.items.length + l.debugs.length;
    return { i, l, best, lab, dbg, done: quizNow + lab + dbg, total };
  });
}

function report(p) {
  const rows = summarize(p);
  const sum = (f) => rows.reduce((a, r) => a + f(r), 0);
  const full = rows.filter((r) => r.done === r.total).length;
  const out = [
    "# Kết quả học tập: Khoá học VPS Linux",
    "",
    `Xuất lúc ${fmtTime(Date.now())} từ Quantum Learn.`,
    "",
    "| Chỉ số | Kết quả |",
    "|---|---|",
    `| Bài hoàn thành | ${full} / ${rows.length} |`,
    `| Quiz đúng (tốt nhất) | ${sum((r) => r.best)} / ${sum((r) => r.l.quiz.length)} |`,
    `| Lab đã pass | ${sum((r) => r.lab)} / ${sum((r) => r.l.lab.items.length)} |`,
    `| Sự cố đã sửa | ${sum((r) => r.dbg)} / ${sum((r) => r.l.debugs.length)} |`,
    "",
  ];
  let group = "";
  for (const r of rows) {
    if (r.l.group !== group) {
      group = r.l.group;
      out.push(`## ${group}`, "", "| Bài | Quiz | Lab | Sự cố | Tiến độ |", "|---|---:|---:|---:|---:|");
    }
    const pct = Math.round((r.done / Math.max(1, r.total)) * 100);
    out.push(`| ${r.i + 1}. ${r.l.short} | ${r.best}/${r.l.quiz.length} | ${r.lab}/${r.l.lab.items.length} | ${r.dbg}/${r.l.debugs.length} | ${pct}%${pct === 100 ? " ✓" : ""} |`);
    if (rows[r.i + 1]?.l.group !== group) out.push("");
  }
  const hist = (p.hist ?? []).slice(-30).reverse();
  if (hist.length) {
    const byId = new Map(engine.lessons.map((l) => [l.id, l]));
    out.push("## Lịch sử làm quiz (30 lượt gần nhất)", "", "| Thời gian | Bài | Điểm |", "|---|---|---:|");
    for (const h of hist) out.push(`| ${fmtTime(h.t)} | ${byId.get(h.l)?.short ?? h.l} | ${h.s}/${h.n} |`);
    out.push("");
  }
  return out.join("\n");
}

function exportReport({ data }) {
  const base = `ket-qua-${stamp()}`;
  const json = join(EXPORT_DIR, `${base}.json`);
  const md = join(EXPORT_DIR, `${base}.md`);
  writeAtomic(json, JSON.stringify({ app: "quantum-learn", version: 1, exportedAt: Date.now(), progress: data }, null, 1));
  writeAtomic(md, report(data));
  return { dir: EXPORT_DIR, json, md };
}

/** Đọc một file sao lưu: của app này ({progress}), bản lưu learn.json, hoặc bản sao lưu dán từ bản web. */
function readBackup(path) {
  let o;
  try {
    o = JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    throw new Error(e?.code === "ENOENT" ? "Không tìm thấy file sao lưu" : "File sao lưu không đọc được (không phải JSON)");
  }
  const p = o && typeof o === "object" && o.progress ? o.progress : o;
  if (!p || typeof p !== "object" || !(p.labs || p.quiz || p.debugs || p.hist)) throw new Error("File không phải bản sao lưu kết quả học tập");
  return p;
}

function backups() {
  mkdirSync(EXPORT_DIR, { recursive: true }); // để nút "Mở thư mục" luôn mở được
  const list = [];
  const scan = (dir, kind, re) => {
    if (!existsSync(dir)) return;
    for (const f of readdirSync(dir)) {
      if (!re.test(f)) continue;
      const path = join(dir, f);
      list.push({ path, name: f, kind, mtime: statSync(path).mtimeMs });
    }
  };
  scan(EXPORT_DIR, "export", /\.json$/);
  scan(AUTO_DIR, "auto", /^learn-\d{4}-\d{2}-\d{2}\.json$/);
  list.sort((a, b) => b.mtime - a.mtime);
  return { dir: EXPORT_DIR, autoDir: AUTO_DIR, list: list.slice(0, 20) };
}

function restore({ path, data }) {
  return { data: merge(data, readBackup(path)) };
}

const ops = {
  catalog,
  open,
  run,
  complete,
  reset: ({ key }) => (shells.delete(key), {}),
  load,
  save,
  export: exportReport,
  backups,
  restore,
};
const needsEngine = new Set(["catalog", "open", "run", "complete", "export"]);

createInterface({ input: process.stdin }).on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return send({ id: null, ok: false, error: "JSON không hợp lệ" });
  }
  const fn = ops[msg.op];
  try {
    if (!fn) throw new Error(`op không hỗ trợ: ${msg.op}`);
    if (needsEngine.has(msg.op) && !engine) throw new Error(loadError ?? "Engine chưa nạp");
    send({ id: msg.id, ok: true, ...fn(msg) });
  } catch (e) {
    send({ id: msg.id, ok: false, error: String(e?.message ?? e) });
  }
});
